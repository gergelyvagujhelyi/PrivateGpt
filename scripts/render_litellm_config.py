"""Render LiteLLM config.yaml from the declarative models.yaml catalogue.

Kept deliberately small. The output is committed and reviewed in PRs.
"""

from __future__ import annotations

import argparse
import sys

import yaml


def render(models_path: str) -> str:
    with open(models_path) as f:
        catalogue = yaml.safe_load(f)

    model_list = []
    for m in catalogue["models"]:
        params = {
            "model": f"azure/{m['name']}",
            "api_base": "os.environ/AZURE_API_BASE",
            "api_key": "os.environ/AZURE_API_KEY",
            "api_version": "os.environ/AZURE_API_VERSION",
        }
        if m.get("rpm"):
            params["rpm"] = m["rpm"]
        if m.get("tpm"):
            params["tpm"] = m["tpm"]
        model_list.append({"model_name": m["exposed_as"], "litellm_params": params})

    config = {
        "model_list": model_list,
        "router_settings": {
            "routing_strategy": "simple-shuffle",
            "num_retries": 2,
            "timeout": 60,
            "allowed_fails": 3,
            "cooldown_time": 30,
        },
        "litellm_settings": {
            "drop_params": True,
            "success_callback": ["langfuse"],
            "failure_callback": ["langfuse"],
            "cache": True,
            "cache_params": {"type": "local", "ttl": 600},
        },
        "general_settings": {
            "master_key": "os.environ/LITELLM_MASTER_KEY",
            "enforce_user_param": True,
        },
    }
    return yaml.safe_dump(config, sort_keys=False)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("models_yaml")
    ap.add_argument("--out", default="-")
    args = ap.parse_args()

    rendered = render(args.models_yaml)
    if args.out == "-":
        sys.stdout.write(rendered)
    else:
        with open(args.out, "w") as f:
            f.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
