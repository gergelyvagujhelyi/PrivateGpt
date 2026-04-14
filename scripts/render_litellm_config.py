"""Render LiteLLM config.yaml from the declarative models.yaml catalogue."""

from __future__ import annotations

import argparse
import sys

import yaml


def _params_for(m: dict) -> dict:
    provider = m.get("provider", "openai")
    if provider == "anthropic":
        return {
            "model": f"azure_ai/{m['name']}",
            "api_base": "os.environ/AZURE_AI_API_BASE",
            "api_key": "os.environ/AZURE_AI_API_KEY",
            **({"rpm": m["rpm"]} if m.get("rpm") else {}),
            **({"tpm": m["tpm"]} if m.get("tpm") else {}),
        }
    return {
        "model": f"azure/{m['name']}",
        "api_base": "os.environ/AZURE_API_BASE",
        "api_key": "os.environ/AZURE_API_KEY",
        "api_version": "os.environ/AZURE_API_VERSION",
        **({"rpm": m["rpm"]} if m.get("rpm") else {}),
        **({"tpm": m["tpm"]} if m.get("tpm") else {}),
    }


def render(models_path: str) -> str:
    with open(models_path) as f:
        catalogue = yaml.safe_load(f)

    model_list = [
        {"model_name": m["exposed_as"], "litellm_params": _params_for(m)}
        for m in catalogue["models"]
    ]

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
    out = render(args.models_yaml)
    if args.out == "-":
        sys.stdout.write(out)
    else:
        with open(args.out, "w") as f:
            f.write(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
