# PrivateGpt — OpenWebUI on Azure

Per-client private AI chat on Azure, scripted end-to-end.
**OpenWebUI + Azure AI Foundry (Claude) + Langfuse**, delivered through
Terraform and Azure DevOps, running in a closed VNet.

![Architecture](architecture.png)

## What's in the box

- Private OpenWebUI on **Azure Container Apps**, reachable only via Front Door + WAF.
- **Azure AI Foundry** with **Claude Sonnet 4.5** + **Claude Haiku 4.5** (MaaS) and `text-embedding-3-large`, all over Private Endpoint.
- **LiteLLM** sidecar as the single OpenAI-compatible endpoint — multi-model routing, per-user budgets.
- **Langfuse** (self-hosted) for LLM tracing, cost visibility, and CI eval gates.
- **Postgres Flexible Server** with **pgvector** for both OpenWebUI state and RAG embeddings.
- **Entra ID** SSO, **Managed Identity** for all service-to-service auth, **Key Vault** for every secret.
- Optional **scheduled digest emails** per user, delivered via Azure Communication Services — feature-flagged per client.

Full rationale and trade-offs in [`slides.pdf`](slides.pdf).

## Repo layout

```
terraform/
  modules/           reusable modules (network, postgres, openai, container-apps, etc.)
  stacks/openwebui/  composed product stack
  envs/<client>/     per-client tfvars + backend config
  tests/             terraform test suite (mock_provider, plan-only)

app/
  openwebui/         Dockerfile + config layered on upstream OpenWebUI
  litellm/           Dockerfile + router config
  digest/            optional digest worker (Python, Container Apps Job)
  rag/               optional RAG ingestion worker (Blob → chunk → embed → pgvector)
  models.yaml        single source of truth → drives AOAI + LiteLLM config

.azuredevops/
  pipelines/
    infra.yml        fmt · validate · checkov · plan → apply per env
    app.yml          lint · tests · build · trivy · deploy → eval → canary

scripts/
  onboard_client.sh     scaffold tfvars for a new client
  validate_models.py    schema + live AOAI quota check
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
4. Register an **Entra app** for SSO; client-id + secret go into Key Vault after the first apply.

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

### Build and push an image by hand

```bash
az acr login -n acroopenwebuishared
docker build -t acroopenwebuishared.azurecr.io/openwebui:local app/openwebui
docker push acroopenwebuishared.azurecr.io/openwebui:local
```

## Testing

Layered, cheapest first.

| Layer | What | Where | CI gate |
|---|---|---|---|
| Unit | Pure logic (HMAC unsub, prompt contract) | `app/digest/tests/test_unsub.py`, `test_summariser.py` | app.yml Validate |
| Integration | Postgres (Testcontainers) + stubbed externals | `app/digest/tests/test_migrations.py`, `test_run_integration.py` | app.yml Validate |
| Terraform | Plan-only, `mock_provider`, feature-flag gating | `terraform/tests/digest_gating.tftest.hcl` | infra.yml Validate |
| LLM eval | Golden prompts via deployed LiteLLM, traced in Langfuse | `tests/eval/` | app.yml Eval (gates prod) |
| E2E smoke | `az containerapp job start` after dev deploy | manual | post-deploy |

Run the local suites:

```bash
# Python
cd app/digest && pytest -q
# Terraform (requires 1.7+ for mock_provider)
cd terraform && terraform init -backend=false && terraform test
```

## Branching & CI/CD

- **Trunk-based**, short-lived feature branches, required reviews via CODEOWNERS.
- Two ADO pipelines:
  - `infra.yml` — Terraform plan + apply per env, gated by ADO environments.
  - `app.yml` — build + scan → deploy dev → eval → canary prod.
- Model changes are a PR against `app/models.yaml` — the pipeline validates
  against live AOAI quota and re-renders `app/litellm/config.yaml`.

## Security posture

- Zero public endpoints on DB, AOAI, Blob, Key Vault (Private Endpoints only).
- Managed Identities for every service-to-service auth path; no app secrets in pipelines.
- WAF (OWASP + Bot Manager) in Prevention mode on Front Door.
- Customer-managed keys and geo-redundancy available as feature flags.
- Content Safety on prompts and responses; golden-prompt evals block prod on regression.

## Cost controls

- Budget alerts per client subscription.
- Per-user / per-group token quotas enforced in LiteLLM.
- Container Apps scale-to-zero on non-prod.
- One shared ACR across clients (no per-client registry cost).

## References

- [`slides.pdf`](slides.pdf) — the architecture deck, with trade-offs
- [`architecture.mmd`](architecture.mmd) — Mermaid source for the diagram
- Upstream [OpenWebUI](https://openwebui.com) · [LiteLLM](https://docs.litellm.ai) · [Langfuse](https://langfuse.com)
