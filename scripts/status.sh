#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER="${PROVIDER:-aws}"
PROFILE="${PROFILE:-demo-no-llm}"
STATE="${ROOT}/state/${PROVIDER}-${PROFILE}.tfstate"

if [[ ! -f "$STATE" ]]; then
  echo "no state for ${PROVIDER} ${PROFILE} (${STATE})"
  exit 0
fi

bash "${ROOT}/scripts/tf.sh" output | python3 -c '
import datetime
import json
import sys

data = json.load(sys.stdin)

def val(key: str):
    return data[key]["value"]

expires = val("expires_at")
exp = datetime.datetime.strptime(expires, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
hours = (exp - datetime.datetime.now(datetime.timezone.utc)).total_seconds() / 3600
print("name " + val("name"))
print("instance_id " + val("instance_id"))
print("public_ip " + str(val("public_ip")))
print("ssh_user " + val("ssh_user"))
print(f"expires_at {expires}")
print(f"ttl_remaining_hours {hours:.1f}")
'
