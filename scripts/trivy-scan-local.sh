#!/usr/bin/env bash
# Local mirror of app.yml's "Trivy scan (fail on HIGH/CRITICAL)" step.
# Builds each image from its Dockerfile + runs trivy with the pipeline's
# exact flags, so you find problems before the CI loop does.
#
# Usage:
#   scripts/trivy-scan-local.sh                # all five
#   scripts/trivy-scan-local.sh openwebui      # one
#   scripts/trivy-scan-local.sh litellm admin  # several

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Works on macOS's default bash 3.2 — no associative arrays.
# admin's Dockerfile COPYs app/models.yaml so its build context is repo root.
image_context() {
  case "$1" in
    openwebui) echo "app/openwebui" ;;
    litellm)   echo "app/litellm" ;;
    digest)    echo "app/digest" ;;
    rag)       echo "app/rag" ;;
    admin)     echo "." ;;
    *)         echo ""; return 1 ;;
  esac
}
image_dockerfile() {
  case "$1" in
    openwebui) echo "app/openwebui/Dockerfile" ;;
    litellm)   echo "app/litellm/Dockerfile" ;;
    digest)    echo "app/digest/Dockerfile" ;;
    rag)       echo "app/rag/Dockerfile" ;;
    admin)     echo "app/admin/Dockerfile" ;;
    *)         echo ""; return 1 ;;
  esac
}

ALL_IMAGES="openwebui litellm digest rag admin"

if [[ $# -eq 0 ]]; then
  set -- $ALL_IMAGES
fi

fail=0
for name in "$@"; do
  ctx="$(image_context "$name")" || { echo "unknown image: $name (expected: $ALL_IMAGES)" >&2; exit 2; }
  dockerfile="$(image_dockerfile "$name")"
  tag="privategpt-local/$name:scan"

  echo
  echo "============================================================"
  echo "  building $name → $tag"
  echo "============================================================"
  docker build -f "$dockerfile" -t "$tag" "$ctx" >/dev/null

  echo
  echo "  trivy $name (HIGH/CRITICAL, --ignore-unfixed, mirrors CI)"
  echo "------------------------------------------------------------"
  if trivy image \
       --exit-code 1 \
       --severity HIGH,CRITICAL \
       --ignore-unfixed \
       --quiet \
       "$tag"; then
    echo "  ✓ $name clean"
  else
    echo "  ✗ $name has findings above"
    fail=1
  fi
done

exit "$fail"
