#!/usr/bin/env bash
# Install pinned host tools into /usr/local/bin.
# A tool already on PATH at the pinned version is left alone.
# An older copy earlier on PATH is replaced, so the pin is the one that runs.
# Does not create cloud resources.
#
# Pins checked 2026-10-13. The scanner is trivy.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="/usr/local/bin"
TFLINT_VERSION="0.64.0"
TRIVY_VERSION="0.75.0"
GITLEAKS_VERSION="8.30.1"
NODE_VERSION="24.21.0"

die() { echo "setup: $*" >&2; exit 1; }

command -v curl >/dev/null || die "curl is required"
command -v tar >/dev/null || die "tar is required"
command -v unzip >/dev/null || die "unzip is required"
if command -v sha256sum >/dev/null; then
  sha256_check() { echo "$1  $2" | sha256sum -c - >/dev/null; }
elif command -v shasum >/dev/null; then
  sha256_check() { echo "$1  $2" | shasum -a 256 -c - >/dev/null; }
else
  die "sha256sum or shasum is required"
fi

run_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

pin_file() {
  [[ -f "$1" ]] || die "missing $1"
  tr -d '[:space:]' <"$1" | sed 's/^v//'
}

version_of() {
  local name="$1" out=""
  command -v "$name" >/dev/null 2>&1 || return 0
  case "$name" in
    terraform) out="$(terraform version 2>&1 || true)" ;;
    tflint) out="$(tflint --version 2>&1 || true)" ;;
    trivy) out="$(trivy --version 2>&1 || true)" ;;
    gitleaks) out="$(gitleaks version 2>&1 || true)" ;;
    node) out="$(node --version 2>&1 || true)" ;;
    *) return 1 ;;
  esac
  out="${out%%$'\n'*}"
  printf '%s\n' "$out" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' || true
}

matches() {
  local got="$1" want="$2" mode="$3"
  [[ -n "$got" ]] || return 1
  if [[ "$mode" == "major" ]]; then
    [[ "${got%%.*}" == "$want" ]]
  else
    [[ "$got" == "$want" ]]
  fi
}

place_binary() {
  local src="$1" name="$2" found=""
  run_root install -m 0755 "$src" "$BIN/$name"
  hash -r
  found="$(command -v "$name" || true)"
  if [[ -n "$found" && "$found" != "$BIN/$name" ]]; then
    echo "replacing $found (it is ahead of $BIN on PATH)"
    run_root install -m 0755 "$src" "$found"
    hash -r
  fi
}

install_tool() {
  local name="$1" want="$2" mode="$3" url="$4" sums_url="$5" archive_name="$6" kind="$7"
  local got archive sums expect
  got="$(version_of "$name")"
  if matches "$got" "$want" "$mode"; then
    echo "ok  $name $got  $(command -v "$name")"
    return 0
  fi

  archive="$tmpdir/$archive_name"
  sums="$tmpdir/$name.sha256"
  echo "+ curl -fsSL -o $archive_name"
  echo "  $url"
  curl -fsSL --retry 3 --retry-delay 2 -o "$archive" "$url"
  curl -fsSL --retry 3 --retry-delay 2 -o "$sums" "$sums_url"
  expect="$(awk -v n="$archive_name" '{ f = $2; sub(/^\*/, "", f); if (f == n) { print $1; exit } }' "$sums")"
  [[ -n "$expect" ]] || die "no checksum for $archive_name"
  sha256_check "$expect" "$archive"

  case "$kind" in
    zip)
      unzip -q -o "$archive" "$name" -d "$tmpdir"
      place_binary "$tmpdir/$name" "$name"
      ;;
    tar)
      tar -xzf "$archive" -C "$tmpdir" "$name"
      place_binary "$tmpdir/$name" "$name"
      ;;
    node)
      [[ "$archive" == *.tar.gz ]] || command -v xz >/dev/null || die "xz is required to unpack Node"
      if [[ "$archive" == *.tar.xz ]]; then
        run_root tar -xJf "$archive" -C /usr/local --strip-components=1
      else
        run_root tar -xzf "$archive" -C /usr/local --strip-components=1
      fi
      hash -r
      ;;
    *) die "unknown archive kind $kind" ;;
  esac

  got="$(version_of "$name")"
  matches "$got" "$want" "$mode" || die "$name on PATH is '${got:-missing}', wanted $want ($(command -v "$name" || echo not found))"
  echo "installed  $name $got  $(command -v "$name")"
}

require_cmd() {
  local cmd="$1" hint="$2"
  if command -v "$cmd" >/dev/null; then
    echo "ok  $cmd  $(command -v "$cmd")"
  else
    echo "setup: missing $cmd" >&2
    echo "       $hint" >&2
    missing=1
  fi
}

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    tf_os=linux; tf_arch=amd64
    tflint_zip=tflint_linux_amd64.zip
    trivy_os=Linux-64bit
    gitleaks_os=linux_x64
    node_os=linux-x64; node_ext=tar.xz
    make_hint="sudo apt-get install make"
    ssh_hint="sudo apt-get install openssh-client"
    ;;
  Linux-aarch64)
    tf_os=linux; tf_arch=arm64
    tflint_zip=tflint_linux_arm64.zip
    trivy_os=Linux-ARM64
    gitleaks_os=linux_arm64
    node_os=linux-arm64; node_ext=tar.xz
    make_hint="sudo apt-get install make"
    ssh_hint="sudo apt-get install openssh-client"
    ;;
  Darwin-arm64)
    tf_os=darwin; tf_arch=arm64
    tflint_zip=tflint_darwin_arm64.zip
    trivy_os=macOS-ARM64
    gitleaks_os=darwin_arm64
    node_os=darwin-arm64; node_ext=tar.gz
    make_hint="xcode-select --install"
    ssh_hint="ssh ships with macOS"
    ;;
  Darwin-x86_64)
    tf_os=darwin; tf_arch=amd64
    tflint_zip=tflint_darwin_amd64.zip
    trivy_os=macOS-64bit
    gitleaks_os=darwin_x64
    node_os=darwin-x64; node_ext=tar.gz
    make_hint="xcode-select --install"
    ssh_hint="ssh ships with macOS"
    ;;
  *) die "unsupported platform $(uname -s) $(uname -m)" ;;
esac

terraform_version="$(pin_file "$ROOT/.terraform-version")"
[[ "$terraform_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die ".terraform-version must be X.Y.Z"

nvmrc="$(pin_file "$ROOT/.nvmrc")"
if [[ "$nvmrc" =~ ^[0-9]+$ ]]; then
  node_mode=major
  node_want="$nvmrc"
  node_install="$NODE_VERSION"
  [[ "${node_install%%.*}" == "$node_want" ]] || die ".nvmrc is $node_want but this script installs $node_install"
elif [[ "$nvmrc" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  node_mode=exact
  node_want="$nvmrc"
  node_install="$nvmrc"
else
  die ".nvmrc must be a major (24) or X.Y.Z"
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
missing=0

tf_zip="terraform_${terraform_version}_${tf_os}_${tf_arch}.zip"
install_tool terraform "$terraform_version" exact \
  "https://releases.hashicorp.com/terraform/${terraform_version}/${tf_zip}" \
  "https://releases.hashicorp.com/terraform/${terraform_version}/terraform_${terraform_version}_SHA256SUMS" \
  "$tf_zip" zip

install_tool tflint "$TFLINT_VERSION" exact \
  "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/${tflint_zip}" \
  "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/checksums.txt" \
  "$tflint_zip" zip

trivy_tar="trivy_${TRIVY_VERSION}_${trivy_os}.tar.gz"
install_tool trivy "$TRIVY_VERSION" exact \
  "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${trivy_tar}" \
  "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_checksums.txt" \
  "$trivy_tar" tar

gitleaks_tar="gitleaks_${GITLEAKS_VERSION}_${gitleaks_os}.tar.gz"
install_tool gitleaks "$GITLEAKS_VERSION" exact \
  "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${gitleaks_tar}" \
  "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_checksums.txt" \
  "$gitleaks_tar" tar

node_tar="node-v${node_install}-${node_os}.${node_ext}"
install_tool node "$node_want" "$node_mode" \
  "https://nodejs.org/dist/v${node_install}/${node_tar}" \
  "https://nodejs.org/dist/v${node_install}/SHASUMS256.txt" \
  "$node_tar" node

require_cmd make "$make_hint"
require_cmd ssh "$ssh_hint"
[[ "$missing" -eq 0 ]]
