#!/usr/bin/env bash
# Generates an SSH key pair and saves the private key to the .ssh directory.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_DIR=".ssh"
SSH_KEY_PATH="${SSH_DIR}/id_ed25519_demo-machines"

if [[ ! -d "$SSH_DIR" ]]; then
  mkdir -p "$SSH_DIR"
fi

ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N ""