#!/usr/bin/env bash
# Idempotent demo-machine bootstrap. Running it twice must not break the VM.
# Cloud-init runs it as root with no repo arguments: Docker only.
# Clone from the laptop session, as the ubuntu user, so SSH agent forwarding works.
# Do not put tokens in this file or in user-data.
set -euo pipefail

docker_only=0
repo_url="${REPO_URL:-}"
repo_ref="${REPO_REF:-main}"
compose_file="${COMPOSE_FILE:-}"
compose_up="${COMPOSE_AUTOSTART:-false}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docker-only) docker_only=1; shift ;;
    --repo) repo_url="${2:?--repo needs a url}"; shift 2 ;;
    --ref) repo_ref="${2:?--ref needs a ref}"; shift 2 ;;
    --compose) compose_file="${2:?--compose needs a path}"; shift 2 ;;
    --up) compose_up=true; shift ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    echo "docker already installed"
  else
    export DEBIAN_FRONTEND=noninteractive
    as_root apt-get update
    as_root apt-get install -y ca-certificates curl
    as_root install -m 0755 -d /etc/apt/keyrings
    as_root curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    as_root chmod a+r /etc/apt/keyrings/docker.asc
    local codename arch
    # shellcheck disable=SC1091
    codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
    arch="$(dpkg --print-architecture)"
    as_root tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Architectures: ${arch}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    as_root apt-get update
    as_root apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi

  as_root systemctl enable --now docker
  if id ubuntu >/dev/null 2>&1; then
    as_root usermod -aG docker ubuntu
  fi
}

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    return 0
  fi
  as_root apt-get update
  as_root apt-get install -y git
}

clone_repo() {
  if [[ -z "$repo_url" ]]; then
    return 0
  fi
  ensure_git
  local dest="${HOME}/demo"
  if [[ ! -d "${dest}/.git" ]]; then
    git clone "$repo_url" "$dest"
  else
    git -C "$dest" remote set-url origin "$repo_url"
    git -C "$dest" fetch --tags origin
  fi
  git -C "$dest" checkout "$repo_ref"
  if [[ "$compose_up" == "true" && -n "$compose_file" ]]; then
    # sudo so the first run works before the docker group is on this login.
    sudo docker compose -f "${dest}/${compose_file}" up -d
  fi
}

if [[ "$(id -u)" -ne 0 ]]; then
  sudo "$0" --docker-only
  if [[ "$docker_only" -eq 1 ]]; then
    exit 0
  fi
  clone_repo
  exit 0
fi

install_docker
if [[ "$docker_only" -eq 1 ]]; then
  exit 0
fi
if [[ -n "$repo_url" ]]; then
  echo "clone is skipped as root. Run this script again over SSH as ubuntu, with the agent forwarded." >&2
fi
