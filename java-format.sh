#!/usr/bin/env bash
# google-java-format helper
# Known google-java-format version when this script was released: 1.35.0
# `install` resolves the latest GitHub release by default. Use --version to pin one.

set -euo pipefail
IFS=$'\n\t'

readonly TOOL_NAME="java-format.sh"
readonly KNOWN_GOOGLE_JAVA_FORMAT_VERSION="1.35.0"
readonly RELEASES_LATEST_URL="https://github.com/google/google-java-format/releases/latest"
readonly RELEASES_DOWNLOAD_BASE_URL="https://github.com/google/google-java-format/releases/download"

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SCRIPT_PATH="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_PATH

info() {
  printf '%s\n' "$*" >&2
}

die() {
  info "Error: $*"
  exit 1
}

is_windows_shell() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

data_root() {
  local root
  if is_windows_shell && [ -n "${LOCALAPPDATA:-}" ]; then
    root="$LOCALAPPDATA"
    if command -v cygpath >/dev/null 2>&1; then
      root="$(cygpath -u "$root")"
    fi
    printf '%s/google-java-format\n' "$root"
    return
  fi

  root="${XDG_DATA_HOME:-${HOME}/.local/share}"
  printf '%s/google-java-format\n' "$root"
}

readonly DATA_ROOT="$(data_root)"
readonly VERSIONS_DIR="${DATA_ROOT}/versions"
readonly CURRENT_FILE="${DATA_ROOT}/current"
readonly BIN_DIR="${DATA_ROOT}/bin"
readonly LAUNCHER="${BIN_DIR}/google-java-format"

usage() {
  cat <<'EOF'
Usage:
  ./java-format.sh install [--version <x.y.z>] [--force]
  ./java-format.sh format [path...]
  ./java-format.sh diff [--staged | --base <git-ref>]
  ./java-format.sh check [path...]
  ./java-format.sh install-hook
  ./java-format.sh uninstall-hook

Commands:
  install         Download google-java-format for this user. Latest is the default.
  format          Recursively format *.java below each path (default: current directory).
  diff            Format complete Java files that occur in a Git diff.
  check           Report Java files that google-java-format would change.
  install-hook    Install a safe, managed pre-commit formatter in the current Git repo.
  uninstall-hook  Remove this tool's pre-commit formatter and restore any prior hook.
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

normalize_version() {
  local version="${1#v}"
  [[ "$version" =~ ^[0-9]+([.][0-9]+)+$ ]] || die "Invalid version: $1"
  printf '%s\n' "$version"
}

resolve_latest_version() {
  local latest_url version
  require_command curl
  if ! latest_url="$(curl --fail --silent --show-error --location --output /dev/null \
      --write-out '%{url_effective}' "$RELEASES_LATEST_URL")"; then
    die "Could not resolve the latest google-java-format release. Use --version ${KNOWN_GOOGLE_JAVA_FORMAT_VERSION} to install a specific version."
  fi

  case "$latest_url" in
    */releases/tag/v*) version="${latest_url##*/releases/tag/v}" ;;
    *) die "GitHub returned an unexpected latest-release URL: $latest_url" ;;
  esac
  normalize_version "$version"
}

select_release_asset() {
  local version="$1" os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  ASSET_KIND="jar"
  ASSET_NAME="google-java-format-${version}-all-deps.jar"
  LOCAL_ARTIFACT_NAME="google-java-format.jar"

  case "$os" in
    Darwin)
      case "$arch" in
        arm64|aarch64)
          ASSET_KIND="native"
          ASSET_NAME="google-java-format_darwin-arm64"
          LOCAL_ARTIFACT_NAME="google-java-format"
          ;;
      esac
      ;;
    Linux)
      case "$arch" in
        x86_64|amd64)
          ASSET_KIND="native"
          ASSET_NAME="google-java-format_linux-x86-64"
          LOCAL_ARTIFACT_NAME="google-java-format"
          ;;
        arm64|aarch64)
          ASSET_KIND="native"
          ASSET_NAME="google-java-format_linux-arm64"
          LOCAL_ARTIFACT_NAME="google-java-format"
          ;;
      esac
      ;;
    MINGW*|MSYS*|CYGWIN*)
      case "$arch" in
        x86_64|amd64)
          ASSET_KIND="native"
          ASSET_NAME="google-java-format_windows-x86-64.exe"
          LOCAL_ARTIFACT_NAME="google-java-format.exe"
          ;;
      esac
      ;;
  esac
}

ensure_jdk_21() {
  local java_version major
  require_command java

  java_version="$(java -version 2>&1 | sed -n 's/.*version "\([^"]*\)".*/\1/p' | sed -n '1p')"
  [ -n "$java_version" ] || die "Could not determine the Java version. A JDK 21+ is required for the JAR fallback."

  major="${java_version%%.*}"
  if [ "$major" = "1" ]; then
    major="${java_version#1.}"
    major="${major%%.*}"
  fi
  case "$major" in
    ''|*[!0-9]*) die "Could not parse Java version: $java_version" ;;
  esac
  [ "$major" -ge 21 ] || die "google-java-format's JAR fallback requires JDK 21+; found Java ${java_version}."

  java --list-modules 2>/dev/null | grep -q '^jdk.compiler@' \
    || die "The selected Java runtime does not contain jdk.compiler. Install a full JDK 21+ instead of a JRE."
}

shell_quote() {
  printf '%q' "$1"
}

write_launcher() {
  local launcher_tmp
  mkdir -p "$BIN_DIR"
  launcher_tmp="${LAUNCHER}.tmp.$$"
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -eu'
    printf 'data_root=%s\n' "$(shell_quote "$DATA_ROOT")"
    printf 'current_file=%s\n' "$(shell_quote "$CURRENT_FILE")"
    printf '%s\n' \
      'if [ ! -f "$current_file" ]; then' \
      '  echo "google-java-format is not installed; run java-format.sh install." >&2' \
      '  exit 1' \
      'fi' \
      'version=$(sed -n "1p" "$current_file")' \
      'kind=$(sed -n "2p" "$current_file")' \
      'artifact=$(sed -n "3p" "$current_file")' \
      'case "$kind" in' \
      '  native) [ -n "$artifact" ] || artifact=google-java-format; exec "$data_root/versions/$version/$artifact" "$@" ;;' \
      '  jar) exec java -jar "$data_root/versions/$version/google-java-format.jar" "$@" ;;' \
      '  *) echo "google-java-format installation metadata is invalid." >&2; exit 1 ;;' \
      'esac'
  } >"$launcher_tmp"
  chmod +x "$launcher_tmp"
  mv -f "$launcher_tmp" "$LAUNCHER"
}

installed_kind() {
  [ -f "$CURRENT_FILE" ] || return 1
  sed -n '2p' "$CURRENT_FILE"
}

require_formatter() {
  local kind
  [ -x "$LAUNCHER" ] || die "google-java-format is not installed for this user. Run: ${SCRIPT_PATH} install"
  kind="$(installed_kind || true)"
  case "$kind" in
    native) ;;
    jar) ensure_jdk_21 ;;
    *) die "google-java-format installation metadata is invalid. Re-run: ${SCRIPT_PATH} install --force" ;;
  esac
  "$LAUNCHER" --version >/dev/null 2>&1
}

download_file() {
  local url="$1" destination="$2"
  require_command curl
  curl --fail --location --retry 3 --connect-timeout 15 --output "$destination" "$url"
}

cmd_install() {
  local requested_version="" force=0 version version_dir target url temp current_tmp

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --version)
        [ "$#" -ge 2 ] || die "--version requires a value."
        requested_version="$2"
        shift 2
        ;;
      --force)
        force=1
        shift
        ;;
      -h|--help)
        usage
        return
        ;;
      *) die "Unknown install option: $1" ;;
    esac
  done

  if [ -n "$requested_version" ]; then
    version="$(normalize_version "$requested_version")"
  else
    version="$(resolve_latest_version)"
  fi

  select_release_asset "$version"
  version_dir="${VERSIONS_DIR}/${version}"
  target="${version_dir}/${LOCAL_ARTIFACT_NAME}"
  url="${RELEASES_DOWNLOAD_BASE_URL}/v${version}/${ASSET_NAME}"

  mkdir -p "$version_dir" "$BIN_DIR"
  if [ "$force" -eq 1 ] || [ ! -f "$target" ]; then
    info "Downloading google-java-format ${version} (${ASSET_NAME})..."
    temp="$(mktemp "${version_dir}/.download.XXXXXX")"
    if ! download_file "$url" "$temp"; then
      rm -f "$temp"
      die "Download failed: $url"
    fi
    if [ "$ASSET_KIND" = "native" ]; then
      chmod +x "$temp"
    fi
    mv -f "$temp" "$target"
  else
    info "google-java-format ${version} is already downloaded."
  fi

  current_tmp="$(mktemp "${DATA_ROOT}/.current.XXXXXX")"
  printf '%s\n%s\n%s\n' "$version" "$ASSET_KIND" "$LOCAL_ARTIFACT_NAME" >"$current_tmp"
  mv -f "$current_tmp" "$CURRENT_FILE"
  write_launcher

  if [ "$ASSET_KIND" = "jar" ]; then
    ensure_jdk_21
  fi
  "$LAUNCHER" --version
  info "Installed google-java-format ${version} at ${DATA_ROOT}."
  info "This script will use ${LAUNCHER}; add ${BIN_DIR} to PATH only if you also want the standalone command."
}

JAVA_FILES=()

collect_java_files() {
  local input file
  JAVA_FILES=()
  for input in "$@"; do
    [ -e "$input" ] || die "Path does not exist: $input"
    if [ -d "$input" ]; then
      while IFS= read -r -d '' file; do
        JAVA_FILES+=("$file")
      done < <(find "$input" \( -type d -name .git -prune \) -o \( -type f -name '*.java' -print0 \))
    elif [ -f "$input" ]; then
      case "$input" in
        *.java) JAVA_FILES+=("$input") ;;
        *) info "Skipping non-Java file: $input" ;;
      esac
    fi
  done
}

format_java_files() {
  [ "$#" -gt 0 ] || {
    info "No Java files found."
    return 0
  }
  require_formatter
  printf '%s\0' "$@" | xargs -0 -n 50 "$LAUNCHER" --replace
}

check_java_files() {
  local file output status result=0
  [ "$#" -gt 0 ] || {
    info "No Java files found."
    return 0
  }
  require_formatter

  for file in "$@"; do
    output=""
    if output="$("$LAUNCHER" --dry-run --set-exit-if-changed "$file" 2>&1)"; then
      continue
    else
      status=$?
    fi
    result=1
    info "Needs formatting or could not be checked: $file"
    [ -z "$output" ] || printf '%s\n' "$output" >&2
    [ "$status" -eq 1 ] || info "Formatter exit status: $status"
  done
  return "$result"
}

cmd_format() {
  if [ "$#" -eq 0 ]; then
    set -- .
  fi
  collect_java_files "$@"
  format_java_files "${JAVA_FILES[@]}"
}

git_root() {
  local root
  if ! root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    die "This command must be run inside a Git working tree."
  fi
  printf '%s\n' "$root"
}

collect_diff_java_files() {
  local mode="$1" base="${2:-}" path
  JAVA_FILES=()
  case "$mode" in
    worktree)
      while IFS= read -r -d '' path; do
        case "$path" in *.java) [ -f "$path" ] && JAVA_FILES+=("$path") ;; esac
      done < <(git diff --name-only -z --diff-filter=ACMR)
      ;;
    staged)
      while IFS= read -r -d '' path; do
        case "$path" in *.java) JAVA_FILES+=("$path") ;; esac
      done < <(git diff --cached --name-only -z --diff-filter=ACMR)
      ;;
    base)
      while IFS= read -r -d '' path; do
        case "$path" in *.java) [ -f "$path" ] && JAVA_FILES+=("$path") ;; esac
      done < <(git diff --name-only -z --diff-filter=ACMR "$base" --)
      ;;
    *) die "Internal error: unknown diff mode $mode" ;;
  esac
}

format_staged_java_files() {
  (
    set -euo pipefail
    local_path=''
    [ "$#" -gt 0 ] || {
      info "No staged Java files to format."
      exit 0
    }
    require_formatter
    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/google-java-format-hook.XXXXXX")"
    trap 'rm -rf "$temp_dir"' EXIT

    for local_path in "$@"; do
      entry=""
      IFS= read -r -d '' entry < <(git ls-files -s -z -- "$local_path") || true
      [ -n "$entry" ] || die "Could not read staged file: $local_path"
      metadata="${entry%%$'\t'*}"
      mode="${metadata%% *}"

      git show ":${local_path}" >"${temp_dir}/source.java"
      "$LAUNCHER" --replace "${temp_dir}/source.java"
      new_blob="$(git hash-object -w "${temp_dir}/source.java")"
      printf '%s blob %s\t%s\0' "$mode" "$new_blob" "$local_path" | git update-index -z --index-info
      info "Formatted staged Java file: $local_path"
    done
  )
}

cmd_diff() {
  local mode="worktree" base="" root
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --staged)
        [ -z "$base" ] && [ "$mode" = "worktree" ] || die "--staged cannot be combined with --base."
        mode="staged"
        shift
        ;;
      --base)
        [ "$#" -ge 2 ] || die "--base requires a Git reference."
        [ "$mode" = "worktree" ] || die "--base cannot be combined with --staged."
        mode="base"
        base="$2"
        shift 2
        ;;
      -h|--help)
        usage
        return
        ;;
      *) die "Unknown diff option: $1" ;;
    esac
  done

  root="$(git_root)"
  (
    cd "$root"
    collect_diff_java_files "$mode" "$base"
    if [ "$mode" = "staged" ]; then
      format_staged_java_files "${JAVA_FILES[@]}"
    else
      format_java_files "${JAVA_FILES[@]}"
    fi
  )
}

cmd_check() {
  local root
  if [ "$#" -eq 0 ]; then
    if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
      set -- "$root"
    else
      set -- .
    fi
  fi
  collect_java_files "$@"
  if check_java_files "${JAVA_FILES[@]}"; then
    info "All checked Java files already match google-java-format."
  else
    exit 1
  fi
}

checksum_file() {
  cksum "$1" | awk '{print $1 ":" $2}'
}

canonical_path_for_write() {
  local requested="$1" existing="$1" suffix="" leaf parent canonical
  while [ ! -e "$existing" ]; do
    leaf="$(basename "$existing")"
    suffix="/${leaf}${suffix}"
    parent="$(dirname "$existing")"
    [ "$parent" != "$existing" ] || die "Cannot resolve hook path: $requested"
    existing="$parent"
  done
  [ -d "$existing" ] || die "Cannot use non-directory hook path parent: $existing"
  canonical="$(cd -P "$existing" && pwd)"
  printf '%s%s\n' "$canonical" "$suffix"
}

path_is_within() {
  local child="$1" parent="$2"
  case "$child" in
    "$parent"|"$parent"/*) return 0 ;;
    *) return 1 ;;
  esac
}

managed_hook_dir() {
  local root="$1" git_dir configured requested canonical_root canonical_git_dir hook_dir
  git_dir="$(git rev-parse --git-dir)"
  case "$git_dir" in
    /*|[A-Za-z]:/*) ;;
    *) git_dir="${root}/${git_dir}" ;;
  esac
  canonical_root="$(cd -P "$root" && pwd)"
  canonical_git_dir="$(cd -P "$git_dir" && pwd)"
  configured="$(git config --get core.hooksPath || true)"

  if [ -n "$configured" ]; then
    case "/${configured}/" in
      */../*) die "Refusing core.hooksPath containing '..': $configured" ;;
    esac
    case "$configured" in
      /*|[A-Za-z]:/*) requested="$configured" ;;
      *) requested="${canonical_root}/${configured}" ;;
    esac
    hook_dir="$(canonical_path_for_write "$requested")"
    if ! path_is_within "$hook_dir" "$canonical_root" && ! path_is_within "$hook_dir" "$canonical_git_dir"; then
      die "Refusing to modify shared core.hooksPath outside this repository: $configured"
    fi
  else
    hook_dir="${canonical_git_dir}/hooks"
  fi
  printf '%s\n' "$hook_dir"
}

write_managed_hook() {
  local hook_path="$1" original_hook="$2" temp_hook
  temp_hook="${hook_path}.google-java-format-tmp.$$"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' '# google-java-format managed pre-commit dispatcher; do not edit.'
    printf '%s\n' 'set -euo pipefail'
    printf 'script_path=%q\n' "$SCRIPT_PATH"
    printf 'original_hook=%q\n' "$original_hook"
    printf '%s\n' \
      'if [ ! -x "$script_path" ]; then' \
      '  echo "google-java-format hook cannot find its script: $script_path" >&2' \
      '  exit 1' \
      'fi' \
      '"$script_path" _hook-format-staged' \
      'if [ -n "$original_hook" ] && [ -e "$original_hook" ]; then' \
      '  if [ -x "$original_hook" ]; then' \
      '    "$original_hook" "$@"' \
      '  else' \
      '    echo "Existing pre-commit hook is not executable; preserving Git behavior by skipping it." >&2' \
      '  fi' \
      'fi'
  } >"$temp_hook"
  chmod +x "$temp_hook"
  mv -f "$temp_hook" "$hook_path"
}

cmd_install_hook() {
  local root hook_dir hook_path original_hook metadata checksum
  [ "$#" -eq 0 ] || die "install-hook takes no arguments."
  require_formatter
  root="$(git_root)"
  (
    cd "$root"
    hook_dir="$(managed_hook_dir "$root")"
    mkdir -p "$hook_dir"
    hook_path="${hook_dir}/pre-commit"
    original_hook="${hook_dir}/pre-commit.google-java-format-original"
    metadata="${hook_dir}/.google-java-format-pre-commit.checksum"

    if [ -e "$hook_path" ] && grep -Fq 'google-java-format managed pre-commit dispatcher' "$hook_path"; then
      [ -f "$metadata" ] || die "Managed pre-commit hook has no integrity metadata; refusing to replace it."
      checksum="$(checksum_file "$hook_path")"
      [ "$(sed -n '1p' "$metadata")" = "$checksum" ] \
        || die "Managed pre-commit hook was modified outside this tool; refusing to replace it."
      info "google-java-format pre-commit hook is already installed."
      exit 0
    fi

    [ ! -e "$original_hook" ] || die "Backup hook already exists at $original_hook; refusing to overwrite it."
    if [ -e "$hook_path" ]; then
      mv "$hook_path" "$original_hook"
    else
      original_hook=""
    fi
    write_managed_hook "$hook_path" "$original_hook"
    checksum="$(checksum_file "$hook_path")"
    printf '%s\n' "$checksum" >"$metadata"
    info "Installed google-java-format pre-commit hook in $hook_path."
  )
}

cmd_uninstall_hook() {
  local root hook_dir hook_path original_hook metadata expected actual
  [ "$#" -eq 0 ] || die "uninstall-hook takes no arguments."
  root="$(git_root)"
  (
    cd "$root"
    hook_dir="$(managed_hook_dir "$root")"
    hook_path="${hook_dir}/pre-commit"
    original_hook="${hook_dir}/pre-commit.google-java-format-original"
    metadata="${hook_dir}/.google-java-format-pre-commit.checksum"

    [ -e "$hook_path" ] || {
      [ ! -e "$original_hook" ] || die "Managed hook is missing but its backup exists; refusing to restore automatically."
      info "google-java-format pre-commit hook is not installed."
      exit 0
    }
    grep -Fq 'google-java-format managed pre-commit dispatcher' "$hook_path" \
      || die "pre-commit is not managed by google-java-format; refusing to remove it."
    [ -f "$metadata" ] || die "Managed pre-commit hook has no integrity metadata; refusing to remove it."
    expected="$(sed -n '1p' "$metadata")"
    actual="$(checksum_file "$hook_path")"
    [ "$expected" = "$actual" ] || die "Managed pre-commit hook was modified outside this tool; refusing to remove it."

    rm -f "$hook_path" "$metadata"
    if [ -e "$original_hook" ]; then
      mv "$original_hook" "$hook_path"
      info "Removed google-java-format hook and restored the prior pre-commit hook."
    else
      info "Removed google-java-format pre-commit hook."
    fi
  )
}

cmd_hook_format_staged() {
  local root
  [ "$#" -eq 0 ] || die "Internal hook command takes no arguments."
  root="$(git_root)"
  (
    cd "$root"
    collect_diff_java_files staged
    format_staged_java_files "${JAVA_FILES[@]}"
  )
}

main() {
  local command="${1:-}"
  case "$command" in
    install)
      shift
      cmd_install "$@"
      ;;
    format)
      shift
      cmd_format "$@"
      ;;
    diff)
      shift
      cmd_diff "$@"
      ;;
    check)
      shift
      cmd_check "$@"
      ;;
    install-hook)
      shift
      cmd_install_hook "$@"
      ;;
    uninstall-hook)
      shift
      cmd_uninstall_hook "$@"
      ;;
    _hook-format-staged)
      shift
      cmd_hook_format_staged "$@"
      ;;
    -h|--help|help)
      usage
      ;;
    '')
      usage
      exit 1
      ;;
    *)
      die "Unknown command: $command"
      ;;
  esac
}

main "$@"

