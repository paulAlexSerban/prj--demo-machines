#!/usr/bin/env bash
# Writes an SSH host entry from terraform output, forwards ports, and opens VS Code.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER="${PROVIDER:-aws}"
PROFILE="${PROFILE:-demo-no-llm}"
STATE="${ROOT}/state/${PROVIDER}-${PROFILE}.tfstate"
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

json="$(mktemp)"
trap 'rm -f "$json"' EXIT
bash "${ROOT}/scripts/tf.sh" output >"$json"
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
for port in $ports; do
  echo "+ ssh -F ${cfg} -f -N -o ExitOnForwardFailure=yes -L ${port}:127.0.0.1:${port} ${ALIAS}"
  ssh -F "$cfg" -f -N -o ExitOnForwardFailure=yes -L "${port}:127.0.0.1:${port}" "$ALIAS"
done

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
