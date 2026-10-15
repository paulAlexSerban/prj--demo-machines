#!/usr/bin/env bash
# Writes this machine's public IPv4 as a /32 into the profile. Does not apply.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER="${PROVIDER:-aws}"
PROFILE="${PROFILE:-demo-no-llm}"
TFVARS="${ROOT}/profiles/${PROFILE}.tfvars"
EXAMPLE="${ROOT}/profiles/${PROFILE}.example.tfvars"

if [[ ! -f "$TFVARS" ]]; then
  echo "missing $TFVARS" >&2
  echo "cp ${EXAMPLE} ${TFVARS}" >&2
  exit 1
fi

ip="$(curl -4 -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "could not detect a public IPv4 (got '${ip}')" >&2
  exit 1
fi
cidr="${ip}/32"
line="allowed_cidrs = [\"${cidr}\"]"

if grep -qE '^[[:space:]]*allowed_cidrs[[:space:]]*=' "$TFVARS"; then
  tmp="$(mktemp)"
  awk -v repl="$line" '
    /^[[:space:]]*allowed_cidrs[[:space:]]*=/ && !done { print repl; done=1; next }
    { print }
  ' "$TFVARS" >"$tmp"
  mv "$tmp" "$TFVARS"
else
  printf '\n%s\n' "$line" >>"$TFVARS"
fi

echo "updated ${TFVARS}: ${line}"
echo "+ terraform -chdir=${ROOT}/terraform/${PROVIDER} apply -input=false -var-file=${TFVARS}"
echo "not applied. Run: make up PROVIDER=${PROVIDER} PROFILE=${PROFILE}"
