"""Validate `app/models.yaml` before it's used to drive Terraform + LiteLLM config.

Run in CI:
    python scripts/validate_models.py app/models.yaml

Checks:
  * Schema (required fields, allowed values)
  * Unique names
  * Capacity fits subscription quota (queried via Azure SDK)
  * Content-safety policy is set for chat-purpose models
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass

import yaml
from azure.identity import DefaultAzureCredential
from azure.mgmt.cognitiveservices import CognitiveServicesManagementClient

ALLOWED_PURPOSES = {"chat", "embedding", "reranker"}
ALLOWED_SKUS = {"Standard", "GlobalStandard", "ProvisionedManaged"}


@dataclass
class Model:
    name: str
    version: str
    sku_name: str
    capacity: int
    purpose: str
    exposed_as: str
    rpm: int | None = None
    tpm: int | None = None
    content_safety_policy: str | None = None


def load(path: str) -> list[Model]:
    with open(path) as f:
        raw = yaml.safe_load(f)
    return [Model(**m) for m in raw["models"]]


def validate_schema(models: list[Model]) -> list[str]:
    errs: list[str] = []
    seen: set[str] = set()
    for m in models:
        if m.name in seen:
            errs.append(f"duplicate model name: {m.name}")
        seen.add(m.name)
        if m.purpose not in ALLOWED_PURPOSES:
            errs.append(f"{m.name}: purpose must be one of {ALLOWED_PURPOSES}")
        if m.sku_name not in ALLOWED_SKUS:
            errs.append(f"{m.name}: sku_name must be one of {ALLOWED_SKUS}")
        if m.capacity <= 0:
            errs.append(f"{m.name}: capacity must be > 0")
        if m.purpose == "chat" and not m.content_safety_policy:
            errs.append(f"{m.name}: chat models require content_safety_policy")
    return errs


def validate_quota(models: list[Model], subscription_id: str, location: str) -> list[str]:
    errs: list[str] = []
    cred = DefaultAzureCredential()
    client = CognitiveServicesManagementClient(cred, subscription_id)
    try:
        usages = {u.name.value: u for u in client.usages.list(location=location)}
    except Exception as exc:  # noqa: BLE001
        print(f"warning: could not query quota ({exc}); skipping", file=sys.stderr)
        return errs

    # Sum requested capacity per family key used by Azure quota ("OpenAI.Standard.gpt-4o", ...)
    requested: dict[str, int] = {}
    for m in models:
        key = f"OpenAI.{m.sku_name}.{m.name}"
        requested[key] = requested.get(key, 0) + m.capacity

    for key, want in requested.items():
        usage = usages.get(key)
        if usage is None:
            # Not yet visible in this region — trust but warn.
            print(f"warning: no quota info for {key}", file=sys.stderr)
            continue
        available = usage.limit - usage.current_value
        if want > available:
            errs.append(
                f"quota: requested {want} for {key} but only {available:.0f} remaining"
                f" (limit={usage.limit:.0f}, used={usage.current_value:.0f})"
            )
    return errs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("models_yaml")
    ap.add_argument("--skip-quota", action="store_true")
    args = ap.parse_args()

    models = load(args.models_yaml)

    errs = validate_schema(models)

    if not args.skip_quota:
        sub = os.environ.get("AZURE_SUBSCRIPTION_ID")
        loc = os.environ.get("AZURE_LOCATION", "westeurope")
        if not sub:
            print("AZURE_SUBSCRIPTION_ID not set; skipping quota check", file=sys.stderr)
        else:
            errs += validate_quota(models, sub, loc)

    if errs:
        print("Model validation FAILED:", file=sys.stderr)
        for e in errs:
            print(f"  - {e}", file=sys.stderr)
        return 1

    print(f"Model validation OK: {len(models)} models")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
