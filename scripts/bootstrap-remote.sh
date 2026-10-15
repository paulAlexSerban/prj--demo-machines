#!/usr/bin/env bash
# Clone the demo repo and optionally run startup_command on the VM over SSH (agent forwarding).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER="${PROVIDER:-aws}"
PROFILE="${PROFILE:-demo-no-llm}"
STATE="${ROOT}/state/${PROVIDER}-${PROFILE}.tfstate"
BOOTSTRAP="/usr/local/sbin/demo-machines-bootstrap"

if [[ ! -f "$STATE" ]]; then
  echo "no state for ${PROVIDER} ${PROFILE}. Run make up first." >&2
  exit 1
fi

TFVARS="${ROOT}/profiles/${PROFILE}.tfvars"
json="${1:-}"
tmp_json=""
if [[ -z "$json" ]]; then
  raw_json="$(mktemp)"
  tmp_json="$(mktemp)"
  json="$tmp_json"
  trap 'rm -f "$raw_json" "$tmp_json"' EXIT
  bash "${ROOT}/scripts/tf.sh" output >"$raw_json"
  python3 "${ROOT}/scripts/enrich-output-json.py" "$raw_json" "$TFVARS" >"$json"
  chmod 600 "$json"
fi

mapfile -t _boot < <(
  python3 - "$json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

def val(key: str):
    return data[key]["value"]

pub = val("ssh_public_key_path")
identity = pub[:-4] if pub.endswith(".pub") else pub
fields = [
    val("public_ip"),
    val("ssh_user"),
    identity,
    val("repo_url"),
    val("repo_ref"),
    val("startup_command"),
    "true" if val("autostart") else "false",
]
for field in fields:
    print(field)
PY
)

public_ip="${_boot[0]}"
ssh_user="${_boot[1]}"
identity="${_boot[2]}"
repo_url="${_boot[3]}"
repo_ref="${_boot[4]}"
startup_command="${_boot[5]}"
autostart="${_boot[6]}"

ssh_base=(
  ssh
  -i "$identity"
  -o "StrictHostKeyChecking=accept-new"
  -o "ConnectTimeout=10"
  -A
  "${ssh_user}@${public_ip}"
)

echo "+ waiting for SSH on ${public_ip}"
ready=0
for _ in $(seq 1 36); do
  if "${ssh_base[@]}" true 2>/dev/null; then
    ready=1
    break
  fi
  sleep 5
done
if [[ "$ready" -ne 1 ]]; then
  echo "SSH did not become ready on ${public_ip}" >&2
  exit 1
fi

remote_args=(--ref "$repo_ref")
if [[ -n "$repo_url" ]]; then
  remote_args+=(--repo "$repo_url")
fi
if [[ "$autostart" == "true" ]]; then
  remote_args+=(--autostart)
  if [[ -n "$startup_command" ]]; then
    remote_args+=(--startup "$startup_command")
  fi
fi

echo "+ install ${BOOTSTRAP} from repo"
"${ssh_base[@]}" "sudo tee ${BOOTSTRAP} >/dev/null && sudo chmod 0755 ${BOOTSTRAP}" \
  <"${ROOT}/bootstrap/bootstrap.sh"

remote_env="/tmp/demo-machines.env"
env_count="$(python3 -c 'import json,sys; print(len((json.load(sys.stdin).get("env") or {}).get("value") or {}))' <"$json")"
echo "+ writing ${remote_env} (${env_count} keys); copied to ~/demo/.env after clone"
python3 "${ROOT}/scripts/enrich-output-json.py" --dotenv "$json" \
  | "${ssh_base[@]}" "cat > ${remote_env} && chmod 600 ${remote_env}"
remote_args+=(--env-file "$remote_env")

# ssh joins extra argv into one remote shell string, so `make setup && ...`
# would become `--startup make` plus a leftover `setup` argument. Quote it.
quoted=()
for arg in "$BOOTSTRAP" "${remote_args[@]}"; do
  quoted+=("$(printf '%q' "$arg")")
done
echo "+ ssh -A ${ssh_user}@${public_ip} ${BOOTSTRAP} ..."
"${ssh_base[@]}" "${quoted[*]}"
