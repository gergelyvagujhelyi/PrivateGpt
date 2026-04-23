# PrivateGpt — OpenWebUI on Azure

Per-client private AI chat on Azure, scripted end-to-end.
**OpenWebUI + Azure AI Foundry (Claude MaaS and/or Azure OpenAI) + Langfuse**,
delivered through Terraform and Azure DevOps, running in a closed VNet.

![Architecture](architecture.png)

## What's in the box

- Private **OpenWebUI** (pinned to upstream `v0.9.1`) on **Azure Container Apps**, reachable only via Front Door + WAF.
- **Azure AI Foundry** with per-client model mix — any subset of **Claude Sonnet 4.5** / **Claude Haiku 4.5** (MaaS serverless), **GPT-4o** / **GPT-4o-mini** (Azure OpenAI), and **text-embedding-3-large** — all over Private Endpoint when the VNet region allows.
- **LiteLLM** as the single OpenAI-compatible endpoint — per-model routing, per-user budgets, Langfuse callbacks. Router config is rendered per-client at Terraform apply time from the intersection of `app/models.yaml` and the client's `foundry_deployments`.
- **Langfuse** (self-hosted Container App) for LLM tracing, cost visibility, and CI eval gates — always deployed; OpenWebUI's RAG + title-gen calls are routed through LiteLLM so they show up in traces too.
- **Postgres Flexible Server** with **pgvector** for OpenWebUI state, Langfuse, RAG embeddings, and digest preferences.
- **Entra ID** SSO, **Managed Identity** for all service-to-service auth, **Key Vault** for every secret (including a persisted `WEBUI_SECRET_KEY` so redeploys don't invalidate sessions).
- Optional, per-client feature flags:
  - **Scheduled digest emails** (tool-calling Claude Haiku 4.5 agent + Azure Communication Services)
  - **Custom RAG ingestion** (Blob → extract → chunk → embed → pgvector with HNSW cosine index)
  - **TypeScript/React admin UI** (Entra SSO, Langfuse-backed dashboard) on its own Front Door endpoint

Full rationale and trade-offs in [`slides.pdf`](slides.pdf) (v1 design-review deck — see the note inside for what's changed since).

## Repo layout

```
terraform/
  modules/           reusable modules (network, postgres, ai_foundry, keyvault,
                     storage, container_app{,_env,_job}, frontdoor,
                     communication_services, observability, managed_devops_pool)
  stacks/openwebui/  composed product stack (+ tests/ and templates/litellm-config.yaml.tftpl)
  stacks/ci_pool/    optional Managed DevOps Pool stack for VNet-injected CI agents
  envs/<client>/     per-client tfvars + backend config

app/
  openwebui/         Dockerfile + config layered on upstream OpenWebUI v0.9.1
  litellm/           Dockerfile + entrypoint (router config injected at deploy time)
  digest/            optional digest worker — tool-calling Claude Haiku 4.5 agent (Container Apps Job)
  rag/               optional RAG ingestion worker (Blob → chunk → embed → pgvector)
  admin/             optional admin UI — TypeScript + React + Express (Container App)
  models.yaml        single source of truth → drives Foundry deployments + LiteLLM config

.azuredevops/
  pipelines/
    infra.yml                       fmt · validate · tftest · checkov · plan → apply per env
    app.yml                         lint · validate models · tests · build · trivy · deploy → (optional) eval → (optional) prod
    templates/terraform-apply.yml   per-env apply job (OIDC + ADO environment gate)
    templates/container-app-deploy.yml  per-service Container App revision + canary

scripts/
  onboard_client.sh     scaffold tfvars for a new client
  validate_models.py    schema + live Foundry/AOAI quota check
  trivy-scan-local.sh   mirror of the Build-stage Trivy gate for local iteration

tests/eval/               Langfuse-backed golden-prompt eval suite (gates prod when enabled)
docker-compose.test.yml   local dev loop: Postgres (pgvector) + Langfuse
```

## Deploy a new client

Everything after the one-time prereqs fits in a single PR.

### One-time prereqs (per client, ~30 min)

1. Create (or request) the client's Azure subscription.
2. Create an ADO **service connection** with federated identity to that subscription.
3. Create the ADO **variable group** `owui-<client>` and ADO **environments**
   `owui-<client>-{dev,test,prod}` with approvers.
4. Register an **Entra app** for OpenWebUI SSO; client-id + secret go into Key Vault after the first apply.
5. If enabling the admin UI: register a **second Entra app** for the admin SPA + API (its client id goes into `entra_admin_app_client_id` in tfvars). After first apply, set the admin app's reply URL to the Terraform `admin_public_url` output.

### Platform bootstrap (once per platform tenant)

Before the first client can deploy, the shared platform resources must exist:
`rg-owui-platform`, the tfstate storage account (AAD-only, container `tfstate`),
the shared ACR, and the budget-driven killswitch (automation runbook + action
group + consumption budget that nukes every `rg-owui-*` except the platform RG
when the monthly budget is forecast or actually exceeded).

```bash
SUBSCRIPTION_ID=<uuid> BUDGET_AMOUNT_SEK=500 ./scripts/bootstrap_platform.sh
# writes .env.deploy with STATE_SA / ACR_NAME for the envs/*/backend.hcl files
```

Idempotent on re-run (reuses the random suffix captured in `.env.deploy`). Not
in Terraform because it hosts Terraform's own state — chicken/egg.

### The PR

```bash
./scripts/onboard_client.sh <client> <cost-center>
# Edit envs/<client>/*.tfvars as needed (models, regions, features)
git checkout -b onboard/<client>
git add terraform/envs/<client>/ && git commit -m "onboard: <client>"
git push -u origin onboard/<client>
```

Open the PR. The infra pipeline runs `plan` for each env and posts it as a
PR comment. On merge: apply to dev → test → prod with approval gates.

## Model catalogue

Everything about which models a client gets lives in two places:

- **`app/models.yaml`** — the platform-wide catalogue: provider, version, purpose, safety policy.
- **`terraform/envs/<client>/<env>.tfvars` → `foundry_deployments`** — the subset a given client actually deploys (with per-client SKU/capacity for AOAI).

At `terraform apply`, the stack intersects those two sets, renders
`templates/litellm-config.yaml.tftpl`, and injects the result as
`LITELLM_CONFIG_YAML` on the LiteLLM Container App. Adding a model to a
client is a tfvars change — no image rebuild. `OpenWebUI`'s `TASK_MODEL`
(used for chat-title/tag generation) is a separate tfvar so each client
can point it at a model it actually has.

As a worked example, `kdemo/dev.tfvars` runs **GPT-4o + embedding only**
(Anthropic MaaS isn't available in that region's quota) while
`kdemo/test.tfvars` and `kdemo/prod.tfvars` run **Claude Sonnet 4.5 +
Claude Haiku 4.5 + embedding**.

## Optional features

Features are flipped on per-client in tfvars via a typed `features` object.
Disabled features provision **zero resources**.

```hcl
# envs/<client>/prod.tfvars
features = {
  digest = {
    enabled        = true
    daily_cron     = "0 6 * * *"
    weekly_cron    = "0 6 * * MON"
    sender_local   = "assistant"
    default_opt_in = false
  }
  rag = {
    enabled          = true
    ingest_cron      = "*/15 * * * *"
    namespace_prefix = ""
  }
  admin_ui = {
    enabled = true
  }
}
```

### `digest` — scheduled per-user summary emails

A Container Apps Job runs on cron, invokes a **tool-calling agent**
powered by Claude Haiku 4.5 (`get_chat_titles` / `get_usage_stats`) to
compose each user's recap, and delivers the email via Azure
Communication Services.
Users opt in through the `user_preferences` table. Every email carries an
HMAC-signed unsubscribe link. The full agent trace (tool calls,
arguments, results, final message) shows up in Langfuse per run.

### `rag` — per-client document ingestion

A second Container Apps Job runs on cron, lists blobs under
`<namespace>/<path>` in the shared RAG container, extracts text (PDF,
DOCX, MD, TXT), chunks (`RecursiveCharacterTextSplitter`), embeds with
`text-embedding-3-large` through LiteLLM (traced in Langfuse), and
writes to `rag_chunks` in the same Postgres with an HNSW index on
`halfvec_cosine_ops` (embeddings are stored as `HALFVEC(3072)` — pgvector's
HNSW caps `vector` at 2000 dims, so `halfvec` is the canonical workaround
for `text-embedding-3-large`'s 3072). Idempotent via ETag tracking in
`rag_sources`.

Source blobs are capped at `MAX_INPUT_BYTES = 50 MB`; extracted text is
truncated to `MAX_OUTPUT_CHARS = 5 M` characters. Oversized inputs are
skipped and logged rather than parsed — protects the job from
decompression bombs and keeps memory bounded for the 1 Gi container.

Retrieval is exposed both as a CLI (`python -m src.retrieve "<query>"`)
and directly importable as a tool that agents can call.

### `admin_ui` — TypeScript/React admin dashboard

Single-page Vite + React + TypeScript app served from an Express
backend (also TS). Entra ID OIDC sign-in via `@azure/msal-react`;
backend validates access-tokens against Entra's JWKS (`jose`).
Configuration is loaded at runtime from `/api/config`, so one image
serves all clients.

Pages:
- **Dashboard** — per-user Langfuse usage (traces, tokens, cost, top models)
- **Preferences** — digest frequency toggle, unsubscribe state
- **Models** — live catalogue from `app/models.yaml`

Gets its own Front Door endpoint on the same profile
(`admin_public_url` output). Register that URL as the Entra app's
reply URL.

## Local development

### Run the digest worker locally

```bash
docker compose -f docker-compose.test.yml up -d
cd app/digest
pip install -r requirements-dev.txt
CADENCE=daily \
DATABASE_URL=postgresql://owui:owui@localhost:5432/openwebui \
LANGFUSE_HOST=http://localhost:3000 \
OPENAI_BASE_URL=<your-dev-litellm-url>/v1 \
OPENAI_API_KEY=<dev-master-key> \
python -m src.main
```

### Run the RAG ingestion worker locally

```bash
cd app/rag
pip install -r requirements-dev.txt
BLOB_ACCOUNT_URL=https://<dev-storage>.blob.core.windows.net \
BLOB_CONTAINER=rag-sources \
DATABASE_URL=postgresql://owui:owui@localhost:5432/openwebui \
OPENAI_BASE_URL=<your-dev-litellm-url>/v1 \
OPENAI_API_KEY=<dev-master-key> \
python -m src.ingest
# Retrieval check:
python -m src.retrieve "your question" --namespace default
```

### Run the admin UI locally

```bash
cd app/admin
npm ci
# Shell 1 — server
ENTRA_TENANT_ID=<tenant> \
ADMIN_API_AUDIENCE=<admin-app-client-id> \
DATABASE_URL=postgresql://owui:owui@localhost:5432/openwebui \
LANGFUSE_HOST=http://localhost:3000 \
LANGFUSE_PUBLIC_KEY=<pk> LANGFUSE_SECRET_KEY=<sk> \
npm run dev:server
# Shell 2 — client (Vite serves on :5173, proxies /api to :4000)
npm run dev:client
```

### Build and push an image by hand

```bash
az acr login -n acroopenwebuishared
# Most images: context is the app directory
docker build -t acroopenwebuishared.azurecr.io/openwebui:local app/openwebui
# Admin UI: context is the repo root so app/models.yaml is reachable
docker build -f app/admin/Dockerfile -t acroopenwebuishared.azurecr.io/admin:local .
docker push acroopenwebuishared.azurecr.io/admin:local
```

## Testing

Layered, cheapest first.

| Layer | What | Where | CI gate |
|---|---|---|---|
| Unit (Python) | HMAC unsub, agent loop + tool dispatch, prompt contract, chunker, embed batching | `app/digest/tests/`, `app/rag/tests/` | app.yml Validate |
| Unit (TS) | Zod schema contracts | `app/admin/server/__tests__/` | app.yml Validate |
| Integration | Postgres (Testcontainers) + stubbed externals for digest and RAG | `app/digest/tests/test_*integration*.py`, `app/rag/tests/test_store_integration.py` | app.yml Validate |
| Terraform | Plan-only, `mock_provider`, feature-flag gating | `terraform/tests/*.tftest.hcl` | infra.yml Validate |
| LLM eval | Golden prompts via deployed LiteLLM, traced in Langfuse | `tests/eval/` | app.yml Eval (gates prod) |
| E2E smoke | `az containerapp job start` + manual admin UI sign-in | manual | post-deploy |

Run the local suites:

```bash
# Python (digest + RAG)
cd app/digest && pytest -q
cd app/rag    && pytest -q

# TypeScript (admin UI)
cd app/admin  && npm ci && npm run lint && npm run typecheck && npm test

# Terraform (requires 1.7+ for mock_provider)
cd terraform && terraform init -backend=false && terraform test
```

## CI runner — VNet-injected agents

Because the stack locks down Key Vault and Storage to private endpoints
only, the Terraform executor needs a data-plane path inside the VNet.
The canonical pattern is **Azure DevOps Managed DevOps Pools with VNet
injection** — MS-managed ephemeral agents dropped into a delegated
subnet per job.

Scaffolded at `terraform/modules/managed_devops_pool/` and composed in
a tiny `terraform/stacks/ci_pool/` that reuses the spoke VNet the
`openwebui` stack already created. Deploy once per client (or once
platform-wide, depending on your isolation model), then point
`.azuredevops/pipelines/*.yml` at `pool: <pool_name>` instead of
`vmImage: ubuntu-latest`.

```bash
# Fill in ADO org, project, subscription in envs/<client>/ci_pool.tfvars first.
cd terraform/stacks/ci_pool
terraform init -backend-config=../../envs/<client>/ci_pool.backend.hcl
terraform apply -var-file=../../envs/<client>/ci_pool.tfvars
```

After apply, the pool shows up in Azure DevOps → **Organization
Settings → Agent pools** as a new pool named `mdp-owui-<client>`.
Grant the relevant ADO project permission to use it and flip the
`pool:` line in the pipelines.

**Why this over a static VM agent?**
- No VM to patch, MS handles the image + updates
- Scales to zero when idle — cheaper for low-frequency deploys
- Managed Identity replaces long-lived PATs for Azure auth

## Branching & CI/CD

- **Trunk-based**, short-lived feature branches, required reviews via CODEOWNERS.
- Two ADO pipelines:
  - `infra.yml` — Terraform plan + apply per env, gated by ADO environments.
  - `app.yml` — build + scan → deploy dev → eval → canary prod.
- Model changes are a PR against `app/models.yaml` — the pipeline validates
  against live Foundry / AOAI quota, and terraform renders the active subset
  (intersection with the client's `foundry_deployments`) into the LiteLLM
  container at deploy time.

## Security posture

- Zero public endpoints on DB, AI Services / Foundry, Blob, Key Vault (Private Endpoints only). Foundry PEs are gated by `foundry_private_endpoints_enabled` — leave disabled when `foundry_location` differs from the VNet region (cross-region PE for these resource types is not supported).
- Managed Identities for every service-to-service auth path; no app secrets in pipelines.
- **WAF in Prevention mode** on Front Door (DRS 2.1 + Bot Manager 1.1), shared across the OpenWebUI and admin-UI endpoints. Two rule-level exceptions are always applied and one is per-client opt-in — see *Operational notes* below.
- Customer-managed keys and geo-redundancy available as feature flags.
- Content Safety on prompts and responses via LiteLLM; golden-prompt evals block prod on regression.
- Every image passes a Trivy `HIGH,CRITICAL --ignore-unfixed` gate in `app.yml`; vendored `npm` / `site-packages` trees that aren't needed at runtime are stripped to keep the bar zero. The same gate also runs as a `trivy fs` pass over `app/`, `scripts/`, and `.azuredevops/` in the Validate stage on every PR, so vuln/misconfig/secret findings surface before merge.
- Every container image runs as a non-root user — the three first-party images always have had dedicated UIDs (`digest` / `rag` uid 10001, `admin` user `node`); the two layered-on-upstream images (OpenWebUI, LiteLLM) end with an explicit `USER` directive (`owui` uid 1000, and upstream's `1001`) so the runtime process isn't `root`.

## Operational notes

Things that aren't obvious from reading the code or a plan:

- **OpenWebUI `v0.9.1` is a forced pin.** v0.8.x overwrites the singular `OPENAI_API_BASE_URL` / `OPENAI_API_KEY` on boot with `api.openai.com`, leaving the Models page empty — the stack sets the **plural** `OPENAI_API_BASE_URLS` / `OPENAI_API_KEYS` instead, which v0.9.1 honours. `RAG_OPENAI_API_BASE_URL` points at LiteLLM for the same reason.
- **`WEBUI_SECRET_KEY` is persisted in Key Vault.** OpenWebUI defaults to a random per-boot session-cookie key; without persistence, every redeploy logs every user out and produces a stale-cookie → 401 → frontend JSON parse cascade.
- **Langfuse is mandatory**, not a flag. LiteLLM, the digest worker, the RAG worker, and the admin UI all depend on its trace API.
- **LiteLLM runs with `--num_workers 1`** at the default 1 Gi memory allocation, with a `/health/liveliness` startup probe (cold start is ~22 s once Langfuse callbacks initialise). Scale by adding Container App replicas, not workers.
- **WAF rule exceptions:**
  - DRS 2.1 `941380` (AngularJS template injection on `{{USER_NAME}}`) is always disabled — categorical false positive on OpenWebUI chat payloads.
  - DRS 2.1 `943120` (session fixation when `session_id` appears with no `Referer`) is always disabled — matches every OpenWebUI SPA fetch.
  - `waf_allow_signup_avatar = true` (per-client, default `false`) exempts `profile_image_url` from the XSS rule group for clients that rely on OpenWebUI's local signup flow; the base64 data URI the UI sends as the default avatar would otherwise trip `941130`/`941170`.
- **`task_model` defaults to `claude-haiku-4-5`.** Override in tfvars when a client doesn't have Claude deployed (e.g. `kdemo/dev.tfvars` points it at `gpt-4o`).
- **`BYPASS_MODEL_ACCESS_CONTROL=true`** is set stack-wide. In v0.9+ models from admin-added connections are Private by default, so non-admin users land on an empty dropdown. Product segmentation happens at the per-client stack boundary (separate subscription, VNet, Entra tenant) and per-user cost limits live in LiteLLM (`enforce_user_param: true`), so the per-model access-control layer isn't pulling its weight.
- **Images build `--platform=linux/amd64`** on the Apple-silicon CI agent via QEMU. Slower, but required — Container Apps is amd64-only.

## Cost controls

- Budget alerts per client subscription.
- Per-user / per-group token quotas enforced in LiteLLM.
- Container Apps scale-to-zero on non-prod.
- One shared ACR across clients (no per-client registry cost).

## References

- [`slides.pdf`](slides.pdf) — original architecture deck (v1, pre-Foundry)
- [`architecture.mmd`](architecture.mmd) — Mermaid source for the diagram (current)
- Upstream [OpenWebUI](https://openwebui.com) · [LiteLLM](https://docs.litellm.ai) · [Langfuse](https://langfuse.com)
