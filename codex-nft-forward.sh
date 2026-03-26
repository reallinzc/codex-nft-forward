#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_HELPER="$SCRIPT_DIR/codex-nft-forward"
HELPER=""
REMOTE_BIN="/usr/local/bin/codex-nft-forward"
SSH_BIN="${SSH_BIN:-ssh}"
SSH_CONFIG_FILE="${SSH_CONFIG_FILE:-$HOME/.ssh/config}"
REPO_SLUG="${CODEX_NFT_FORWARD_REPO:-reallinzc/codex-nft-forward}"
REPO_REF="${CODEX_NFT_FORWARD_REF:-main}"
RAW_BASE_URL="${CODEX_NFT_FORWARD_RAW_BASE_URL:-https://raw.githubusercontent.com/${REPO_SLUG}/${REPO_REF}}"
TMP_HELPER=""

usage() {
  cat <<EOF
Usage:
  $0 install <alias> [--interval <seconds>]
  $0 upsert <alias> <name> <local_port> <target_host> <target_port> [all|tcp|udp] [--family auto|4|6] [--dry-run]
  $0 remove <alias> <name> [--dry-run]
  $0 list <alias> [--json]
  $0 apply <alias> [--dry-run]
  $0 status <alias> [--json]

Notes:
  - Remote state lives in /etc/codex-nft-forward/.
  - Managed rules live in dedicated nft tables named codex_forward.
  - This tool never saves the full ruleset to /etc/nftables.conf.
  - The wrapper uses standard ssh and respects \$SSH_CONFIG_FILE.
  - If the helper binary is not present locally, the wrapper will fetch it from:
    ${RAW_BASE_URL}/codex-nft-forward
EOF
}

need_helper() {
  if [[ -f "$LOCAL_HELPER" ]]; then
    HELPER="$LOCAL_HELPER"
    return
  fi
  command -v curl >/dev/null 2>&1 || {
    echo "curl not found and local helper missing: $LOCAL_HELPER" >&2
    exit 1
  }
  TMP_HELPER="$(mktemp "${TMPDIR:-/tmp}/codex-nft-forward.helper.XXXXXX")"
  curl -fsSL "${RAW_BASE_URL}/codex-nft-forward" -o "$TMP_HELPER"
  chmod +x "$TMP_HELPER"
  HELPER="$TMP_HELPER"
}

cleanup() {
  if [[ -n "$TMP_HELPER" && -f "$TMP_HELPER" ]]; then
    rm -f "$TMP_HELPER"
  fi
}

remote_exec() {
  local target="$1"
  shift
  "$SSH_BIN" -F "$SSH_CONFIG_FILE" "$target" "$@"
}

install_remote() {
  local target="$1"
  local interval="${2:-300}"
  local helper_b64

  need_helper
  helper_b64="$(base64 < "$HELPER" | tr -d '\n')"

  "$SSH_BIN" -F "$SSH_CONFIG_FILE" "$target" /bin/bash -s <<REMOTE
set -euo pipefail
mkdir -p /usr/local/bin /etc/codex-nft-forward
python3 - <<'PY'
import base64
from pathlib import Path

payload = base64.b64decode("${helper_b64}")
path = Path("${REMOTE_BIN}")
path.write_bytes(payload)
path.chmod(0o755)
PY
"${REMOTE_BIN}" install-systemd --interval "${interval}"
"${REMOTE_BIN}" status
REMOTE
}

proxy_remote_command() {
  local target="$1"
  shift
  remote_exec "$target" "$REMOTE_BIN" "$@"
}

main() {
  local cmd="${1:-}"
  [[ -n "$cmd" ]] || {
    usage >&2
    exit 2
  }
  shift

  case "$cmd" in
    install)
      local target="${1:-}"
      local interval="300"
      shift || true
      [[ -n "$target" ]] || {
        usage >&2
        exit 2
      }
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --interval)
            shift
            interval="${1:-}"
            ;;
          *)
            echo "unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        esac
        shift || true
      done
      install_remote "$target" "$interval"
      ;;
    upsert|remove|list|apply|status)
      local target="${1:-}"
      shift || true
      [[ -n "$target" ]] || {
        usage >&2
        exit 2
      }
      proxy_remote_command "$target" "$cmd" "$@"
      ;;
    help|--help|-h)
      usage
      ;;
    *)
      echo "unknown command: $cmd" >&2
      usage >&2
      exit 2
      ;;
  esac
}

trap cleanup EXIT
main "$@"
