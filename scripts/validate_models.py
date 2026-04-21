"""Validate app/models.yaml schema.

Quota validation is provider-specific:
  - openai: azurerm quota usage API (retained from previous version)
  - anthropic (Foundry MaaS): no quota — pay per token.
"""

from __future__ import annotations

import argparse
import os
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
        available = usage.limit - usage.current_value
        if want > available:
            errs.append(
                f"quota: requested {want} for {key} but only {available:.0f} remaining "
                f"(limit={usage.limit:.0f}, used={usage.current_value:.0f})"
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
        if sub:
            errs += validate_openai_quota(models, sub, loc)
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
