# PrivateGpt — OpenWebUI on Azure

Per-client private AI chat on Azure, scripted end-to-end.
**OpenWebUI + Azure AI Foundry (Claude) + Langfuse**, delivered through
Terraform and Azure DevOps, running in a closed VNet.

![Architecture](architecture.png)

## What's in the box

- Private OpenWebUI on **Azure Container Apps**, reachable only via Front Door + WAF.
- **Azure AI Foundry** with **Claude Sonnet 4.5** + **Claude Haiku 4.5** (MaaS) and `text-embedding-3-large`, all over Private Endpoint.
- **LiteLLM** sidecar as the single OpenAI-compatible endpoint — per-model routing, per-user budgets.
- **Langfuse** (self-hosted) for LLM tracing, cost visibility, and CI eval gates.
- **Postgres Flexible Server** with **pgvector** for both OpenWebUI state and RAG embeddings.
- **Entra ID** SSO, **Managed Identity** for all service-to-service auth, **Key Vault** for every secret.
- Optional, per-client feature flags:
  - **Scheduled digest emails** (tool-calling Claude agent + Azure Communication Services)
  - **Custom RAG ingestion** (Blob → chunk → embed → pgvector)
  - **TypeScript/React admin UI** (Entra SSO, Langfuse-backed dashboard) on its own Front Door endpoint

Full rationale and trade-offs in [`slides.pdf`](slides.pdf) (v1 design-review deck — see the note inside for what's changed since).

## Repo layout

```
terraform/
  modules/           reusable modules (network, postgres, ai_foundry, container-apps, frontdoor…)
  stacks/openwebui/  composed product stack
  envs/<client>/     per-client tfvars + backend config
  tests/             terraform test suite (mock_provider, plan-only)

app/
  openwebui/         Dockerfile + config layered on upstream OpenWebUI
  litellm/           Dockerfile + router config
  digest/            optional digest worker (Python, Container Apps Job)
  rag/               optional RAG ingestion worker (Blob → chunk → embed → pgvector)
  admin/             optional admin UI — TypeScript + React + Express (Container App)
  models.yaml        single source of truth → drives Foundry deployments + LiteLLM config

.azuredevops/
  pipelines/
    infra.yml        fmt · validate · checkov · plan → apply per env
    app.yml          lint · tests · build · trivy · deploy → eval → canary

scripts/
  onboard_client.sh     scaffold tfvars for a new client
  validate_models.py    schema + live Foundry/AOAI quota check
  render_litellm_config.py

tests/eval/          Langfuse-backed golden-prompt eval suite (gates prod)
docker-compose.test.yml    local dev loop: Postgres + Langfuse
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
`vector_cosine_ops`. Idempotent via ETag tracking in `rag_sources`.

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
  against live Foundry / AOAI quota and re-renders `app/litellm/config.yaml`.

## Security posture

- Zero public endpoints on DB, AI Services / Foundry, Blob, Key Vault (Private Endpoints only).
- Managed Identities for every service-to-service auth path; no app secrets in pipelines.
- WAF (OWASP + Bot Manager) in Prevention mode on Front Door (shared across the public endpoints for OpenWebUI and the admin UI).
- Customer-managed keys and geo-redundancy available as feature flags.
- Content Safety on prompts and responses; golden-prompt evals block prod on regression.

## Cost controls

- Budget alerts per client subscription.
- Per-user / per-group token quotas enforced in LiteLLM.
- Container Apps scale-to-zero on non-prod.
- One shared ACR across clients (no per-client registry cost).

## References

- [`slides.pdf`](slides.pdf) — original architecture deck (v1, pre-Foundry)
- [`architecture.mmd`](architecture.mmd) — Mermaid source for the diagram (current)
- Upstream [OpenWebUI](https://openwebui.com) · [LiteLLM](https://docs.litellm.ai) · [Langfuse](https://langfuse.com)
