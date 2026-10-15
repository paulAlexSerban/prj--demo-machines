#!/usr/bin/env bash
# Writes an SSH host entry from terraform output, forwards ports, and opens VS Code.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER="${PROVIDER:-aws}"
PROFILE="${PROFILE:-demo-no-llm}"
STATE="${ROOT}/state/${PROVIDER}-${PROFILE}.tfstate"
TFVARS="${ROOT}/profiles/${PROFILE}.tfvars"
ALIAS="demo-${PROVIDER}"

if [[ ! -f "$STATE" ]]; then
  echo "no state for ${PROVIDER} ${PROFILE}. Run make up first." >&2
  exit 1
fi

if [[ ! -f "${ROOT}/dist/ssh-config/cli.js" ]]; then
  echo "+ npm run build" >&2
  npm --prefix "$ROOT" run build
fi

cfg_dir="${HOME}/.ssh/config.d"
cfg="${cfg_dir}/demo-machines"
mkdir -p "$cfg_dir"
chmod 700 "${HOME}/.ssh" "$cfg_dir"

raw_json="$(mktemp)"
json="$(mktemp)"
trap 'rm -f "$raw_json" "$json"' EXIT
bash "${ROOT}/scripts/tf.sh" output >"$raw_json"
python3 "${ROOT}/scripts/enrich-output-json.py" "$raw_json" "$TFVARS" >"$json"

echo "+ bash scripts/bootstrap-remote.sh"
bash "${ROOT}/scripts/bootstrap-remote.sh" "$json"

node "${ROOT}/dist/ssh-config/cli.js" --from-terraform --alias "$ALIAS" --out "$cfg" <"$json"
chmod 600 "$cfg"

ssh_config="${HOME}/.ssh/config"
include_line="Include config.d/demo-machines"
if [[ ! -f "$ssh_config" ]]; then
  printf '%s\n' "$include_line" >"$ssh_config"
  chmod 600 "$ssh_config"
elif ! grep -qxF "$include_line" "$ssh_config"; then
  printf '\n%s\n' "$include_line" >>"$ssh_config"
fi

ports="$(python3 -c 'import json,sys; data=json.load(sys.stdin); print(" ".join(str(p) for p in data["forward_ports"]["value"]))' <"$json")"
if [[ -z "${ports// }" ]]; then
  echo "forward_ports is empty in state and ${TFVARS}. Set forward_ports = [3000, ...] and run make open again." >&2
else
  for port in $ports; do
    # Drop a stale tunnel from an earlier make open so the port can bind again.
    pkill -f "ssh.*-L ${port}:127.0.0.1:${port}.*${ALIAS}" 2>/dev/null || true
    pkill -f "ssh.*-L ${port}:127.0.0.1:${port}.*@${ALIAS}" 2>/dev/null || true
    echo "+ ssh -f -N -L ${port}:127.0.0.1:${port} ${ALIAS}"
    if ! ssh -f -N -o ExitOnForwardFailure=yes -L "${port}:127.0.0.1:${port}" "$ALIAS"; then
      echo "failed to forward local port ${port} (is something else already using it?)" >&2
      exit 1
    fi
  done
  for port in $ports; do
    if command -v ss >/dev/null 2>&1; then
      if ! ss -tln | grep -qE ":${port} "; then
        echo "warning: local port ${port} is not listening after ssh -L" >&2
      fi
    fi
    if ssh -o ConnectTimeout=5 "$ALIAS" "timeout 2 bash -c 'echo >/dev/tcp/127.0.0.1/${port}'" 2>/dev/null; then
      echo "remote ${port}: accepting connections on the VM"
    else
      echo "remote ${port}: nothing listening on the VM yet (SSH in and start the app, or set autostart = true and startup_command in ${TFVARS})" >&2
    fi
  done
  echo "On this laptop, try http://127.0.0.1:<port> for each forwarded port (${ports})."
fi

repo="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["repo_url"]["value"])' <"$json")"
if [[ -n "$repo" ]]; then
  remote_dir="/home/ubuntu/demo"
else
  remote_dir="/home/ubuntu"
fi

if command -v code >/dev/null 2>&1; then
  echo "+ code --remote ssh-remote+${ALIAS} ${remote_dir}"
  code --remote "ssh-remote+${ALIAS}" "$remote_dir"
else
  echo "code is not on PATH. Connect with: ssh ${ALIAS}"
fi
