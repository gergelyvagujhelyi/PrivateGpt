"""Validate app/models.yaml schema.

Quota validation is provider-specific:
  - openai: azurerm quota usage API (retained from previous version)
  - anthropic (Foundry MaaS): no quota — pay per token.

Schema validation runs against models.yaml always. Quota validation, if
enabled, uses per-client foundry_deployments from tfvars when --tfvars is
given — models.yaml's sku_name/capacity are defaults that any client may
override, so validating the catalog defaults gives the wrong answer.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass
from typing import Optional

import yaml
from azure.identity import DefaultAzureCredential
from azure.mgmt.cognitiveservices import CognitiveServicesManagementClient

ALLOWED_PURPOSES = {"chat", "embedding", "reranker"}
ALLOWED_SKUS = {"Standard", "GlobalStandard", "ProvisionedManaged"}
ALLOWED_PROVIDERS = {"openai", "anthropic"}


@dataclass
class Model:
    name: str
    provider: str
    version: str
    purpose: str
    exposed_as: str
    sku_name: Optional[str] = None
    capacity: Optional[int] = None
    rpm: Optional[int] = None
    tpm: Optional[int] = None
    content_safety_policy: Optional[str] = None


def load(path: str) -> list[Model]:
    with open(path) as f:
        raw = yaml.safe_load(f)
    return [Model(**m) for m in raw["models"]]


# One line per deployment in foundry_deployments, e.g.:
#   "gpt-4o" = { provider = "openai", model = "gpt-4o", version = "...", sku_name = "Standard", capacity = 30 }
# Full HCL parsing (python-hcl2) keeps the surrounding quotes on string tokens,
# which makes post-processing fiddly; the single-line shape is reliable.
_DEPLOYMENT_LINE = re.compile(
    r'^\s*"(?P<key>[^"]+)"\s*=\s*\{\s*(?P<body>.*?)\s*\}\s*$',
    re.MULTILINE,
)
_KV = re.compile(r'(\w+)\s*=\s*(?:"([^"]*)"|(\d+))')


_SCALAR_ASSIGN = re.compile(
    r'^\s*(?P<key>\w+)\s*=\s*"(?P<value>[^"]*)"\s*$',
    re.MULTILINE,
)


def read_tfvars_scalar(tfvars_path: str, key: str) -> str | None:
    """Read a top-level scalar string assignment from a tfvars file.
    Returns None if not set."""
    text = open(tfvars_path).read()
    for m in _SCALAR_ASSIGN.finditer(text):
        if m.group("key") == key:
            return m.group("value")
    return None


def load_foundry_deployments(tfvars_path: str) -> list[Model]:
    """Read foundry_deployments = { ... } from a .tfvars and return per-line
    Model entries for quota validation. Anthropic entries are kept so callers
    can filter by provider — only openai entries affect quota."""
    text = open(tfvars_path).read()
    # Isolate the foundry_deployments block to avoid matching inside comments
    # elsewhere in the file.
    m = re.search(
        r"foundry_deployments\s*=\s*\{(?P<body>.*?)^\s*\}\s*$",
        text,
        re.DOTALL | re.MULTILINE,
    )
    if not m:
        return []
    deployments = []
    for entry in _DEPLOYMENT_LINE.finditer(m.group("body")):
        fields: dict[str, int | str] = {}
        for k, v_str, v_int in _KV.findall(entry.group("body")):
            fields[k] = int(v_int) if v_int else v_str
        capacity = fields.get("capacity")
        deployments.append(
            Model(
                name=str(fields.get("model") or entry.group("key")),
                provider=str(fields.get("provider", "")),
                version=str(fields.get("version", "")),
                purpose="chat",  # not represented in tfvars; not needed for quota
                exposed_as=entry.group("key"),
                sku_name=str(fields["sku_name"]) if "sku_name" in fields else None,
                capacity=capacity if isinstance(capacity, int) else None,
            )
        )
    return deployments


def validate_schema(models: list[Model]) -> list[str]:
    errs: list[str] = []
    seen: set[str] = set()
    for m in models:
        if m.name in seen:
            errs.append(f"duplicate model name: {m.name}")
        seen.add(m.name)
        if m.provider not in ALLOWED_PROVIDERS:
            errs.append(f"{m.name}: provider must be one of {ALLOWED_PROVIDERS}")
        if m.purpose not in ALLOWED_PURPOSES:
            errs.append(f"{m.name}: purpose must be one of {ALLOWED_PURPOSES}")
        if m.purpose == "chat" and not m.content_safety_policy:
            errs.append(f"{m.name}: chat models require content_safety_policy")
        if m.provider == "openai":
            if m.sku_name not in ALLOWED_SKUS:
                errs.append(f"{m.name}: sku_name must be one of {ALLOWED_SKUS}")
            if not m.capacity or m.capacity <= 0:
                errs.append(f"{m.name}: capacity must be > 0 for openai-provider models")
    return errs


def validate_openai_quota(models: list[Model], subscription_id: str, location: str) -> list[str]:
    errs: list[str] = []
    openai_models = [m for m in models if m.provider == "openai"]
    if not openai_models:
        return errs

    cred = DefaultAzureCredential()
    client = CognitiveServicesManagementClient(cred, subscription_id)
    try:
        usages = {
            u.name.value: u
            for u in client.usages.list(location=location)
            if u.name is not None and u.name.value is not None
        }
    except Exception as exc:  # noqa: BLE001
        print(f"warning: could not query quota ({exc}); skipping", file=sys.stderr)
        return errs

    requested: dict[str, int] = {}
    for m in openai_models:
        key = f"OpenAI.{m.sku_name}.{m.name}"
        requested[key] = requested.get(key, 0) + (m.capacity or 0)

    for key, want in requested.items():
        usage = usages.get(key)
        if usage is None:
            print(f"warning: no quota info for {key}", file=sys.stderr)
            continue
        if usage.limit is None or usage.current_value is None:
            print(f"warning: partial quota info for {key}; skipping", file=sys.stderr)
            continue
        # Compare against limit, not limit - current_value. current_value
        # includes this client's own already-deployed capacity, so the
        # previous (limit - current) check double-counted on a re-apply and
        # flagged idempotent deployments as quota-exceeded.
        if want > usage.limit:
            errs.append(
                f"quota: requested {want} for {key} but limit is {usage.limit:.0f} "
                f"(currently used={usage.current_value:.0f})"
            )
    return errs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("models_yaml")
    ap.add_argument("--skip-quota", action="store_true")
    ap.add_argument(
        "--tfvars",
        help="Per-client tfvars path; quota is validated against foundry_deployments "
             "from here rather than models.yaml defaults.",
    )
    args = ap.parse_args()

    models = load(args.models_yaml)
    errs = validate_schema(models)

    if not args.skip_quota:
        sub = os.environ.get("AZURE_SUBSCRIPTION_ID")
        # Prefer foundry_location from tfvars over AZURE_LOCATION env var: the
        # script is self-contained rather than relying on the caller to extract
        # the right region (the previous awk-in-pipeline approach was fragile).
        loc: str = (
            (read_tfvars_scalar(args.tfvars, "foundry_location") if args.tfvars else None)
            or (read_tfvars_scalar(args.tfvars, "location") if args.tfvars else None)
            or os.environ.get("AZURE_LOCATION")
            or "westeurope"
        )
        if sub:
            quota_targets = load_foundry_deployments(args.tfvars) if args.tfvars else models
            print(f"quota check: location={loc}, targets={len(quota_targets)}", file=sys.stderr)
            errs += validate_openai_quota(quota_targets, sub, loc)
        else:
            print("AZURE_SUBSCRIPTION_ID not set; skipping openai quota check", file=sys.stderr)

    if errs:
        print("Model validation FAILED:", file=sys.stderr)
        for e in errs:
            print(f"  - {e}", file=sys.stderr)
        return 1

    print(f"Model validation OK: {len(models)} models")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
