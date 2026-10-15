#!/usr/bin/env bash
# Runs terraform for one provider and profile. Prints the terraform command.
# up and down are what you run; this work does not invoke them.
set -euo pipefail

cmd="${1:?usage: tf.sh plan|up|down|output}"
# This runs on a laptop. Don't wait on EC2 instance-metadata when no key is set.
export AWS_EC2_METADATA_DISABLED=true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER="${PROVIDER:-aws}"
PROFILE="${PROFILE:-demo-no-llm}"
TF_DIR="${ROOT}/terraform/${PROVIDER}"
TFVARS="${ROOT}/profiles/${PROFILE}.tfvars"
EXAMPLE="${ROOT}/profiles/${PROFILE}.example.tfvars"
STATE_DIR="${ROOT}/state"
STATE="${STATE_DIR}/${PROVIDER}-${PROFILE}.tfstate"
EXPIRES_FILE="${STATE_DIR}/${PROVIDER}-${PROFILE}.expires_at"

if [[ ! -d "$TF_DIR" ]]; then
  echo "no terraform root at $TF_DIR (only aws is implemented)" >&2
  exit 1
fi

if [[ ! -f "$TFVARS" ]]; then
  echo "missing $TFVARS" >&2
  echo "cp ${EXAMPLE} ${TFVARS}" >&2
  echo "Then set owner and ssh_public_key_path." >&2
  exit 1
fi

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

read_ttl() {
  local found
  found="$(awk -F= '/^[[:space:]]*ttl_hours[[:space:]]*=/ { gsub(/[[:space:]"#].*/, "", $2); print $2; exit }' "$TFVARS")"
  if [[ -z "$found" ]]; then
    echo 12
  else
    echo "$found"
  fi
}

compute_expires() {
  local ttl="$1"
  if date -u -d "+${ttl} hours" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    date -u -d "+${ttl} hours" +%Y-%m-%dT%H:%M:%SZ
  else
    date -u -v+"${ttl}"H +%Y-%m-%dT%H:%M:%SZ
  fi
}

ttl="$(read_ttl)"
if [[ -f "$EXPIRES_FILE" ]]; then
  saved_ttl="$(head -n 1 "$EXPIRES_FILE")"
  saved_at="$(sed -n '2p' "$EXPIRES_FILE")"
else
  saved_ttl=""
  saved_at=""
fi
if [[ "$saved_ttl" != "$ttl" || -z "$saved_at" ]]; then
  saved_at="$(compute_expires "$ttl")"
  printf '%s\n%s\n' "$ttl" "$saved_at" >"$EXPIRES_FILE"
  chmod 600 "$EXPIRES_FILE"
fi

extra_vars=(-var "expires_at=${saved_at}")
if ! grep -qE '^[[:space:]]*allowed_cidrs[[:space:]]*=' "$TFVARS"; then
  ip="$(curl -4 -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "could not detect a public IPv4 (got '${ip}')" >&2
    exit 1
  fi
  extra_vars+=(-var "allowed_cidrs=[\"${ip}/32\"]")
fi

init=(terraform -chdir="$TF_DIR" init -input=false -reconfigure -backend-config="path=${STATE}")
echo "+ ${init[*]}" >&2
"${init[@]}"
if [[ -f "$STATE" ]]; then
  chmod 600 "$STATE"
fi

var_args=(-var-file="$TFVARS" "${extra_vars[@]}")

case "$cmd" in
  plan)
    echo "+ terraform -chdir=${TF_DIR} plan -input=false ${var_args[*]}" >&2
    terraform -chdir="$TF_DIR" plan -input=false "${var_args[@]}"
    ;;
  up)
    echo "+ terraform -chdir=${TF_DIR} apply -input=false ${var_args[*]}" >&2
    terraform -chdir="$TF_DIR" apply -input=false "${var_args[@]}"
    ;;
  down)
    echo "+ terraform -chdir=${TF_DIR} destroy -input=false ${var_args[*]}" >&2
    terraform -chdir="$TF_DIR" destroy -input=false "${var_args[@]}"
    ;;
  output)
    echo "+ terraform -chdir=${TF_DIR} output -json" >&2
    terraform -chdir="$TF_DIR" output -json
    ;;
  *)
    echo "unknown command: $cmd" >&2
    exit 1
    ;;
esac
