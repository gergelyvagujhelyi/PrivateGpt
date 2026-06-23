# Presentation prep — brief-to-slide mapping

Your existing deck already answers every ask in the brief — mapping below. Where you'll win is showing you *heard* the brief by echoing their language back in the opener.

## Brief → slide map

| Brief asks | Covered in slide |
|---|---|
| "Foundation for multiple clients' AI initiatives" | §1 Framing — "one template → many clients"; §7 WoW — template repo, new client in a day |
| "All components on Azure, closed and secure" | §2 Architecture — Private Endpoints, Firewall, VNet; §5 Security |
| "Fully scripted (infra + app)" | §3 IaC (Terraform); §4 CI/CD (two pipelines) |
| "CI/CD for changes, new models, bug fixes" | §4 — all three explicit: `app.yml` for app changes + bug fixes (canary + auto-rollback), `models.yaml` PR for new models (no image rebuild), `infra.yml` for infra |
| "Terraform + ADO, open to alternatives" | §3 — "matching your existing ADO setup; Bicep/Pulumi considered, Terraform wins" |
| "Scalability" | §2 Container Apps (revisions, scale-to-zero on non-prod); §4 canary; §6 per-user quotas |
| "Reliability" | §4 canary + auto-rollback; §6 SLOs |
| "Security" | §5 (full slide) |
| "Maintainability" | §3 modules; §7 runbooks + trunk-based; §4 model onboarding as PR |
| "Future iteration and growth" | §1 design stance — *"optimise for iteration speed on prompts and models, not infra heroics"*; §4 models-as-config; §6 Langfuse eval gates |
| "Reasoning, trade-offs, decision-making" | §2 trade-offs slide is the centrepiece |

**Zero gaps.** You don't need to add content — you need to make the mapping audible.

## 30-second opener (swap in for your current framing)

> *"You asked for a generic chatbot foundation, running entirely on Azure in a closed environment, fully scripted, with CI/CD for both feature changes and new-model introductions. You said the thing you care most about is the reasoning behind the choices. So I'll spend the 15 minutes on the trade-offs, not the component list — I'll name each choice, say what I rejected and why, and call out where I'd revisit the decision per client."*

That one paragraph: repeats their language verbatim ("closed environment", "fully scripted", "new models", "reasoning"), sets the contract that you'll talk in trade-offs, and gives you permission to not be exhaustive on components.

## What to emphasise given their "most interested in" signal

The brief says:
> "Ultimately, we are most interested in your thought process, trade-offs, and architectural decision-making."

That's a direct instruction. Reshape your delivery:

1. **On every architecture slide, name what you rejected.** Not "we chose X" — always "X over Y because Z". Your slides already have this on §2; verbalize it on every other slide too. Example §3: "Terraform over Bicep — not technical, you already run Terraform, cheaper transfer cost for your team."
2. **Flag decisions that depend on the client.** Per-client-stack vs multi-tenant, pgvector vs AI Search, Foundry region, model mix. "This is a *per-client* decision, not a platform decision" signals maturity.
3. **Say out loud what you'd change if you were wrong.** Example: "If retrieval quality becomes the bottleneck, pgvector → AI Search is a one-module swap." That's the kind of line that tells a reviewer you've thought past v1.

## Four non-functional lenses to hit explicitly

They listed these in the brief — use the exact words when answering:

- **Scalability** — "per-client subscription = per-client scale ceiling; Container Apps horizontal scaling, scale-to-zero on non-prod; LiteLLM fronts multiple models so adding capacity is a quota PR not a rewrite."
- **Reliability** — "canary with auto-rollback on health probe; Langfuse eval gate before prod; private origin so public outages don't cascade."
- **Security** — §5 slide. Already complete.
- **Maintainability** — "Everything is a PR: model change = PR, new client = PR, bug fix = PR. Runbooks next to code. No tribal knowledge."

If someone notes you missed one, you have a crisp answer. If nobody asks, you still worked the vocabulary in — which is what they're listening for.

## On "alternatives are welcome"

The brief explicitly invites you to propose alternatives. You've accepted Terraform (their stack) and Container Apps (not K8s, because they don't already run it). **That's a feature, not a gap** — you picked their existing tooling where it fits and chose boring defaults elsewhere. Say it out loud on §3:

> *"I kept Terraform because you already run it — switching costs are real and there's no technical reason to burn them. Container Apps is the swap — it's not what you might use for a generic workload, but for this shape of workload AKS's ops cost doesn't pay back."*

That's a mature answer. It shows you evaluated alternatives rather than defaulted.

## One explicit gap-filler worth 15 seconds

The brief says "foundation for their AI initiatives" — plural. That's a hint they expect this to grow beyond just chat. Your design *does* support this (LiteLLM seam, Langfuse traces, per-client data plane, digest agent as the first non-chat consumer), but the deck doesn't say it plainly. Add one sentence to §1 or §7:

> *"Because LiteLLM is the single LLM seam and Langfuse traces everything that goes through it, anything the client builds next — a second agent, a batch evaluator, a support bot — plugs into the same cost/auth/obs fabric. The chatbot is v1; the platform is the ask."*

That's the line that answers *"foundation for AI initiatives"* directly.

## What to rehearse out loud tonight

Three things:

1. The 30-second opener above.
2. Any two trade-offs from §2 you can defend in both directions (e.g. Container Apps vs AKS — what would change your mind?).
3. The models-as-config story: "`app/models.yaml` intersected with the client's `foundry_deployments` renders the LiteLLM config at apply time. Adding Claude 4.6 to a client next week is a tfvars PR, not an image rebuild." That's the line that proves you took "new models" as a first-class CI/CD ask.

You're in good shape. The deck already answers the brief — your job tomorrow is just to make the answers audible.
