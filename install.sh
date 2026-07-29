#!/usr/bin/env bash
# Bootstrap installer for java-format-scripts.
# Update this tag whenever publishing a new GitHub Release.

set -euo pipefail

readonly REPOSITORY="samzhu/java-format-scripts"
readonly RELEASE_TAG="1"
readonly RELEASE_ASSET_URL="https://github.com/${REPOSITORY}/releases/download/${RELEASE_TAG}/java-format.sh"

info() {
  printf '%s\n' "$*" >&2
}

die() {
  info "Error: $*"
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  curl -fsSL https://github.com/samzhu/java-format-scripts/releases/latest/download/install.sh | bash

Arguments after the pipe are passed to `java-format.sh install`, for example:
  curl -fsSL URL | bash -s -- --version 1.35.0
EOF
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

command -v curl >/dev/null 2>&1 || die "curl is required. On macOS it is installed by default."

install_dir="${JAVA_FORMAT_SCRIPTS_INSTALL_DIR:-${XDG_BIN_HOME:-${HOME}/.local/bin}}"
target="${install_dir}/java-format"
mkdir -p "$install_dir"

temporary="$(mktemp "${install_dir}/.java-format.XXXXXX")"
cleanup() {
  rm -f "$temporary"
}
trap cleanup EXIT

info "Installing java-format ${RELEASE_TAG} to ${target}..."
curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 \
  --output "$temporary" "$RELEASE_ASSET_URL" \
  || die "Could not download ${RELEASE_ASSET_URL}"

chmod +x "$temporary"
mv -f "$temporary" "$target"
trap - EXIT

exec "$target" install "$@"
