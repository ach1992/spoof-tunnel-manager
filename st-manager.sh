#!/usr/bin/env bash
# Spoof Tunnel Manager
# Target: ParsaKSH/spoof-tunnel v1.0.3
# Language: English

set -u
set -o pipefail

APP_NAME="Spoof Tunnel Manager"
APP_VERSION="0.2.0"
TARGET_SPOOF_VERSION="v1.0.3"
UPSTREAM_REPO="ParsaKSH/spoof-tunnel"
UPSTREAM_RELEASE_API="https://api.github.com/repos/${UPSTREAM_REPO}/releases/tags/${TARGET_SPOOF_VERSION}"
UPSTREAM_SOURCE_TARBALL="https://github.com/${UPSTREAM_REPO}/archive/refs/tags/${TARGET_SPOOF_VERSION}.tar.gz"

INSTALL_BIN="/usr/local/bin/spoof"
MANAGER_BIN="/usr/local/bin/st-manager"
CONFIG_DIR="/etc/spoof-tunnel"
LOG_DIR="/var/log/spoof-tunnel"
BACKUP_DIR="${CONFIG_DIR}/backups"
CLIENT_CONFIG="${CONFIG_DIR}/client.json"
SERVER_CONFIG="${CONFIG_DIR}/server.json"
CLIENT_KEYS="${CONFIG_DIR}/client.keys"
SERVER_KEYS="${CONFIG_DIR}/server.keys"
SERVER_PENDING="${CONFIG_DIR}/server.pending"
SERVER_PAIRING="${CONFIG_DIR}/server.pairing"
CLIENT_PAIRING="${CONFIG_DIR}/client.pairing"
CLIENT_SERVICE="/etc/systemd/system/spoof-client.service"
SERVER_SERVICE="/etc/systemd/system/spoof-server.service"

SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" 2>/dev/null && pwd -P || pwd)"

if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

say() { printf '%b\n' "$*"; }
ok() { printf '%b\n' "${GREEN}[OK]${NC} $*" >&2; }
info() { printf '%b\n' "${CYAN}[INFO]${NC} $*" >&2; }
warn() { printf '%b\n' "${YELLOW}[WARN]${NC} $*" >&2; }
fail() { printf '%b\n' "${RED}[ERROR]${NC} $*" >&2; }

pause() {
  printf '\nPress Enter to continue... '
  read -r _ || true
}

is_root() { [ "${EUID:-$(id -u)}" -eq 0 ]; }

require_root() {
  if ! is_root; then
    fail "This action must be run as root. Use: sudo bash $0"
    return 1
  fi
  return 0
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

need_systemd() {
  if ! command_exists systemctl; then
    fail "systemctl was not found. This manager currently supports systemd-based Linux servers."
    return 1
  fi
  return 0
}

mkdirs() {
  mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$BACKUP_DIR"
  chmod 700 "$CONFIG_DIR" 2>/dev/null || true
  chmod 755 "$LOG_DIR" 2>/dev/null || true
}

backup_now() {
  require_root || return 1
  mkdirs
  local ts dest copied=0
  ts="$(date +%Y%m%d-%H%M%S)"
  dest="${BACKUP_DIR}/${ts}"
  mkdir -p "$dest"
  for f in "$CLIENT_CONFIG" "$SERVER_CONFIG" "$CLIENT_KEYS" "$SERVER_KEYS" "$CLIENT_SERVICE" "$SERVER_SERVICE"; do
    if [ -e "$f" ]; then
      cp -a "$f" "$dest/" && copied=1
    fi
  done
  if [ "$copied" -eq 1 ]; then
    ok "Backup created: $dest"
  else
    warn "No existing config/service files were found to back up."
    rmdir "$dest" 2>/dev/null || true
  fi
}

confirm() {
  local prompt="${1:-Continue?}" default="${2:-N}" reply
  if [ "$default" = "Y" ] || [ "$default" = "y" ]; then
    printf '%s [Y/n]: ' "$prompt" >&2
  else
    printf '%s [y/N]: ' "$prompt" >&2
  fi
  read -r reply || reply=""
  reply="${reply:-$default}"
  case "$reply" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

ask() {
  local prompt="$1" default="${2:-}" value
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$prompt" "$default" >&2
  else
    printf '%s: ' "$prompt" >&2
  fi
  read -r value || value=""
  if [ -z "$value" ]; then
    value="$default"
  fi
  printf '%s' "$value"
}

validate_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

validate_ipv4() {
  local ip="$1" IFS=. octets i
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  read -r -a octets <<< "$ip"
  [ "${#octets[@]}" -eq 4 ] || return 1
  for i in "${octets[@]}"; do
    [[ "$i" =~ ^[0-9]+$ ]] || return 1
    [ "$i" -ge 0 ] && [ "$i" -le 255 ] || return 1
  done
  return 0
}

ask_port() {
  local prompt="$1" default="$2" value
  while true; do
    value="$(ask "$prompt" "$default")"
    if validate_port "$value"; then
      printf '%s' "$value"
      return 0
    fi
    fail "Invalid port. Enter a number between 1 and 65535."
  done
}

ask_ipv4() {
  local prompt="$1" default="${2:-}" value
  while true; do
    value="$(ask "$prompt" "$default")"
    if validate_ipv4 "$value"; then
      printf '%s' "$value"
      return 0
    fi
    fail "Invalid IPv4 address. Example: 1.2.3.4"
  done
}

ask_transport() {
  local value
  while true; do
    value="$(ask "Transport type" "udp")"
    case "$value" in
      udp|icmp) printf '%s' "$value"; return 0 ;;
      *) fail "Invalid transport. Use udp or icmp." ;;
    esac
  done
}

ask_log_level() {
  local value
  while true; do
    value="$(ask "Log level" "info")"
    case "$value" in
      debug|info|warn|error) printf '%s' "$value"; return 0 ;;
      *) fail "Invalid log level. Use debug, info, warn, or error." ;;
    esac
  done
}

ask_non_empty() {
  local prompt="$1" default="${2:-}" value
  while true; do
    value="$(ask "$prompt" "$default")"
    if [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
    fail "This value is required."
  done
}

ask_yes_no() {
  local prompt="$1" default="${2:-N}"
  if confirm "$prompt" "$default"; then
    printf 'yes'
  else
    printf 'no'
  fi
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

arch_name() {
  local arch
  arch="$(uname -m 2>/dev/null || echo unknown)"
  case "$arch" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7) echo "armv7" ;;
    *) echo "$arch" ;;
  esac
}

copy_manager_to_path() {
  require_root || return 1
  if [ "$SCRIPT_PATH" = "$MANAGER_BIN" ]; then
    ok "Manager is already installed at $MANAGER_BIN"
    return 0
  fi
  cp "$SCRIPT_PATH" "$MANAGER_BIN"
  chmod +x "$MANAGER_BIN"
  ok "Manager installed as: $MANAGER_BIN"
}

check_binary_usable() {
  local bin="$1"
  [ -x "$bin" ] || return 1
  "$bin" --help >/dev/null 2>&1 || "$bin" version >/dev/null 2>&1 || "$bin" --version >/dev/null 2>&1 || return 1
  return 0
}

install_binary_file() {
  local src="$1"
  require_root || return 1
  if [ ! -f "$src" ]; then
    fail "Binary not found: $src"
    return 1
  fi
  mkdir -p "$(dirname "$INSTALL_BIN")"
  cp "$src" "$INSTALL_BIN"
  chmod +x "$INSTALL_BIN"
  if check_binary_usable "$INSTALL_BIN"; then
    ok "Spoof binary installed: $INSTALL_BIN"
    return 0
  fi
  warn "Binary was copied, but it did not respond to --help/--version. It may still work, but please verify it."
  return 0
}

build_from_source_dir() {
  local srcdir="$1" outbin="$2"
  if ! command_exists go; then
    fail "Go is not installed, so source build is not possible. Place a prebuilt spoof binary next to this script for offline install."
    return 1
  fi
  if [ ! -d "$srcdir/cmd/spoof" ]; then
    fail "Source directory does not look like spoof-tunnel v1.0.3: $srcdir"
    return 1
  fi
  info "Building spoof from local source using existing Go toolchain. No package manager will be used."
  (cd "$srcdir" && CGO_ENABLED=0 GOOS=linux GOARCH="$(arch_name)" go build -ldflags="-s -w" -o "$outbin" ./cmd/spoof/) || {
    fail "Go build failed."
    return 1
  }
  [ -x "$outbin" ] || { fail "Build finished but output binary was not found."; return 1; }
  return 0
}

extract_archive_find_binary() {
  local archive="$1" tmpdir="$2" found=""
  mkdir -p "$tmpdir"
  case "$archive" in
    *.tar.gz|*.tgz)
      command_exists tar || { fail "tar is required to extract $archive but was not found."; return 1; }
      tar -xzf "$archive" -C "$tmpdir" || return 1
      ;;
    *.zip)
      command_exists unzip || { fail "unzip is required to extract $archive but was not found."; return 1; }
      unzip -q "$archive" -d "$tmpdir" || return 1
      ;;
    *)
      fail "Unsupported archive format: $archive"
      return 1
      ;;
  esac

  found="$(find "$tmpdir" -type f \( -name 'spoof' -o -name 'spoof-*' -o -name 'spoof_*' \) -perm /111 2>/dev/null | head -n 1 || true)"
  if [ -n "$found" ]; then
    printf '%s' "$found"
    return 0
  fi

  local srcdir
  srcdir="$(find "$tmpdir" -type f -name go.mod -printf '%h\n' 2>/dev/null | head -n 1 || true)"
  if [ -n "$srcdir" ]; then
    local outbin="${tmpdir}/spoof-built"
    build_from_source_dir "$srcdir" "$outbin" || return 1
    printf '%s' "$outbin"
    return 0
  fi

  fail "No spoof binary or buildable source tree found inside archive: $archive"
  return 1
}

find_local_candidate() {
  local dirs=("$SCRIPT_DIR" "$SCRIPT_DIR/assets" "$SCRIPT_DIR/bin" "$(pwd)")
  local d f
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/spoof "$d"/spoof-linux-* "$d"/spoof_* "$d"/spoof-*; do
      [ -f "$f" ] || continue
      [ "$f" = "$SCRIPT_PATH" ] && continue
      printf '%s' "$f"
      return 0
    done
  done
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*.tar.gz "$d"/*.tgz "$d"/*.zip; do
      [ -f "$f" ] || continue
      printf '%s' "$f"
      return 0
    done
  done
  return 1
}

install_offline() {
  require_root || return 1
  mkdirs
  if [ -x "$INSTALL_BIN" ]; then
    warn "Spoof binary already exists: $INSTALL_BIN"
    if ! confirm "Replace it with a local/offline copy?" "N"; then
      ok "Keeping existing binary."
      copy_manager_to_path
      return 0
    fi
  fi

  local candidate tmp extracted
  candidate="$(find_local_candidate || true)"
  if [ -z "$candidate" ]; then
    fail "No local spoof binary/archive was found."
    say "Place one of these next to st-manager.sh, then retry:"
    say "  - ./spoof"
    say "  - ./spoof-linux-amd64 or ./spoof-linux-arm64"
    say "  - ./assets/spoof"
    say "  - a ${TARGET_SPOOF_VERSION} .tar.gz/.tgz/.zip release archive"
    return 1
  fi

  info "Found local candidate: $candidate"
  case "$candidate" in
    *.tar.gz|*.tgz|*.zip)
      tmp="$(mktemp -d)"
      extracted="$(extract_archive_find_binary "$candidate" "$tmp" || true)"
      if [ -z "$extracted" ]; then
        rm -rf "$tmp"
        return 1
      fi
      install_binary_file "$extracted"
      rm -rf "$tmp"
      ;;
    *)
      chmod +x "$candidate" 2>/dev/null || true
      install_binary_file "$candidate"
      ;;
  esac
  copy_manager_to_path
}

download_file() {
  local url="$1" out="$2"
  if command_exists curl; then
    curl -fL --connect-timeout 15 --retry 2 -o "$out" "$url"
  elif command_exists wget; then
    wget -O "$out" "$url"
  else
    fail "Neither curl nor wget is available. Use offline install instead."
    return 1
  fi
}

fetch_release_urls() {
  if command_exists curl; then
    curl -fsSL --connect-timeout 15 "$UPSTREAM_RELEASE_API" | grep -E '"browser_download_url"' | sed -E 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
  elif command_exists wget; then
    wget -qO- "$UPSTREAM_RELEASE_API" | grep -E '"browser_download_url"' | sed -E 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
  else
    return 1
  fi
}

select_release_url() {
  local arch url urls
  arch="$(arch_name)"
  urls="$(fetch_release_urls 2>/dev/null || true)"
  [ -n "$urls" ] || return 1

  # Prefer Linux binary/archive for the current architecture, avoid checksums and panel assets.
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    printf '%s' "$url" | grep -Eiq 'sha256|checksum|checksums|panel' && continue
    printf '%s' "$url" | grep -Eiq 'linux' || continue
    case "$arch" in
      amd64) printf '%s' "$url" | grep -Eiq 'amd64|x86_64' && { printf '%s' "$url"; return 0; } ;;
      arm64) printf '%s' "$url" | grep -Eiq 'arm64|aarch64' && { printf '%s' "$url"; return 0; } ;;
      armv7) printf '%s' "$url" | grep -Eiq 'armv7|armhf' && { printf '%s' "$url"; return 0; } ;;
    esac
  done <<EOF_URLS
$urls
EOF_URLS

  # Fallback: first non-checksum asset.
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    printf '%s' "$url" | grep -Eiq 'sha256|checksum|checksums|panel' && continue
    printf '%s' "$url"
    return 0
  done <<EOF_URLS2
$urls
EOF_URLS2

  return 1
}

install_online() {
  require_root || return 1
  mkdirs
  if [ -x "$INSTALL_BIN" ]; then
    warn "Spoof binary already exists: $INSTALL_BIN"
    if ! confirm "Download and replace it with ${TARGET_SPOOF_VERSION}?" "N"; then
      ok "Keeping existing binary. No update was performed."
      copy_manager_to_path
      return 0
    fi
  fi

  local url tmp file extracted srcdir outbin
  tmp="$(mktemp -d)"
  url="$(select_release_url || true)"
  if [ -n "$url" ]; then
    info "Downloading ${TARGET_SPOOF_VERSION} release asset."
    file="${tmp}/asset"
    download_file "$url" "$file" || { rm -rf "$tmp"; return 1; }
    case "$url" in
      *.tar.gz|*.tgz) mv "$file" "${file}.tar.gz"; file="${file}.tar.gz" ;;
      *.zip) mv "$file" "${file}.zip"; file="${file}.zip" ;;
      *) chmod +x "$file" 2>/dev/null || true ;;
    esac
    case "$file" in
      *.tar.gz|*.tgz|*.zip)
        extracted="$(extract_archive_find_binary "$file" "${tmp}/extract" || true)"
        [ -n "$extracted" ] || { rm -rf "$tmp"; return 1; }
        install_binary_file "$extracted"
        ;;
      *)
        install_binary_file "$file"
        ;;
    esac
    rm -rf "$tmp"
    copy_manager_to_path
    return 0
  fi

  warn "Could not discover release assets through GitHub API. Falling back to source tarball."
  if ! command_exists go; then
    fail "Go is not installed. Online source build cannot continue. Use offline install with a prebuilt spoof binary."
    rm -rf "$tmp"
    return 1
  fi
  file="${tmp}/source.tar.gz"
  download_file "$UPSTREAM_SOURCE_TARBALL" "$file" || { rm -rf "$tmp"; return 1; }
  tar -xzf "$file" -C "$tmp" || { rm -rf "$tmp"; fail "Could not extract source tarball."; return 1; }
  srcdir="$(find "$tmp" -maxdepth 2 -type f -name go.mod -printf '%h\n' 2>/dev/null | head -n 1 || true)"
  [ -n "$srcdir" ] || { rm -rf "$tmp"; fail "Could not find go.mod in source tarball."; return 1; }
  outbin="${tmp}/spoof-built"
  build_from_source_dir "$srcdir" "$outbin" || { rm -rf "$tmp"; return 1; }
  install_binary_file "$outbin"
  rm -rf "$tmp"
  copy_manager_to_path
}

parse_key_output() {
  local out="$1" label="$2"
  printf '%s\n' "$out" | grep -Ei "$label" | grep -Eo '[A-Za-z0-9+/]{40,}={0,2}' | head -n 1
}

generate_keys() {
  local prefix="$1" out private public keyfile
  if [ ! -x "$INSTALL_BIN" ]; then
    fail "spoof binary is not installed. Install it first."
    return 1
  fi
  out="$($INSTALL_BIN keygen 2>&1 || true)"
  private="$(parse_key_output "$out" 'private')"
  public="$(parse_key_output "$out" 'public')"
  if [ -z "$private" ] || [ -z "$public" ]; then
    warn "Could not parse keygen output automatically."
    printf '%s
' "$out" >&2
    private="$(ask "Enter ${prefix} private key manually" "")"
    public="$(ask "Enter ${prefix} public key manually" "")"
  fi
  if [ -z "$private" ] || [ -z "$public" ]; then
    fail "Both private and public keys are required."
    return 1
  fi
  keyfile="${CONFIG_DIR}/${prefix}.keys"
  {
    printf 'PRIVATE_KEY=%s\n' "$private"
    printf 'PUBLIC_KEY=%s\n' "$public"
  } > "$keyfile"
  chmod 600 "$keyfile"
  printf '%s|%s' "$private" "$public"
}

load_keys_or_generate() {
  local role="$1" keyfile private public generated
  keyfile="${CONFIG_DIR}/${role}.keys"
  if [ -f "$keyfile" ] && confirm "Existing ${role} keys found. Reuse them?" "Y"; then
    private="$(grep '^PRIVATE_KEY=' "$keyfile" | sed 's/^PRIVATE_KEY=//')"
    public="$(grep '^PUBLIC_KEY=' "$keyfile" | sed 's/^PUBLIC_KEY=//')"
    if [ -n "$private" ] && [ -n "$public" ]; then
      printf '%s|%s' "$private" "$public"
      return 0
    fi
    warn "Existing key file is incomplete. Generating new keys."
  fi
  generated="$(generate_keys "$role" || true)"
  [ -n "$generated" ] || return 1
  printf '%s' "$generated"
}


read_key_pair() {
  local role="$1" keyfile private public
  keyfile="${CONFIG_DIR}/${role}.keys"
  [ -f "$keyfile" ] || return 1
  private="$(grep '^PRIVATE_KEY=' "$keyfile" | sed 's/^PRIVATE_KEY=//' | tail -n 1)"
  public="$(grep '^PUBLIC_KEY=' "$keyfile" | sed 's/^PUBLIC_KEY=//' | tail -n 1)"
  [ -n "$private" ] && [ -n "$public" ] || return 1
  printf '%s|%s' "$private" "$public"
}

get_kv_file_value() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 1
  grep -E "^${key}=" "$file" | tail -n 1 | sed -E "s/^${key}=//" | sed 's/\r$//'
}

read_pairing_block() {
  local line block=""
  say "Paste the pairing block now. Press Enter on an empty line when finished."
  while IFS= read -r line; do
    [ -z "$line" ] && break
    block="${block}${line}
"
  done
  printf '%s' "$block"
}

pairing_value() {
  local block="$1" key="$2"
  printf '%s\n' "$block" |
    sed 's/\r$//' |
    grep -E "^[[:space:]]*${key}[[:space:]]*=" |
    tail -n 1 |
    sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//" |
    sed -E 's/^"//; s/"$//'
}

save_server_pending() {
  local transport="$1" listen_addr="$2" listen_port="$3" server_real_ip="$4" server_spoof_ip="$5" log_level="$6" log_file="$7"
  cat > "$SERVER_PENDING" <<EOF_PENDING
TRANSPORT=$transport
SERVER_LISTEN_ADDR=$listen_addr
SERVER_PORT=$listen_port
SERVER_REAL_IP=$server_real_ip
SERVER_SPOOF_IP=$server_spoof_ip
SERVER_LOG_LEVEL=$log_level
SERVER_LOG_FILE=$log_file
EOF_PENDING
  chmod 600 "$SERVER_PENDING"
}

print_server_pairing_from_file() {
  local keys public transport server_real_ip server_port server_spoof_ip
  keys="$(read_key_pair server || true)"
  [ -n "$keys" ] || { fail "Server keys were not found. Run server step 1 first."; return 1; }
  public="${keys#*|}"
  transport="$(get_kv_file_value "$SERVER_PENDING" TRANSPORT || true)"
  server_real_ip="$(get_kv_file_value "$SERVER_PENDING" SERVER_REAL_IP || true)"
  server_port="$(get_kv_file_value "$SERVER_PENDING" SERVER_PORT || true)"
  server_spoof_ip="$(get_kv_file_value "$SERVER_PENDING" SERVER_SPOOF_IP || true)"
  [ -n "$transport" ] && [ -n "$server_real_ip" ] && [ -n "$server_port" ] && [ -n "$server_spoof_ip" ] || {
    fail "Server pending file is incomplete: $SERVER_PENDING"
    return 1
  }
  say "\n${BOLD}Copy this SERVER pairing block to the client/Iran server:${NC}"
  cat <<EOF_PAIR
-----BEGIN SPOOF-TUNNEL SERVER PAIRING-----
VERSION=${TARGET_SPOOF_VERSION}
ROLE=server
TRANSPORT=${transport}
SERVER_REAL_IP=${server_real_ip}
SERVER_PORT=${server_port}
SERVER_SPOOF_IP=${server_spoof_ip}
SERVER_PUBLIC_KEY=${public}
-----END SPOOF-TUNNEL SERVER PAIRING-----
EOF_PAIR
}

print_client_pairing_from_file() {
  local keys public client_real_ip client_spoof_ip transport local_socks
  keys="$(read_key_pair client || true)"
  [ -n "$keys" ] || { fail "Client keys were not found. Configure client first."; return 1; }
  public="${keys#*|}"
  client_real_ip="$(get_kv_file_value "$CLIENT_PAIRING" CLIENT_REAL_IP || true)"
  client_spoof_ip="$(get_kv_file_value "$CLIENT_PAIRING" CLIENT_SPOOF_IP || true)"
  transport="$(get_kv_file_value "$CLIENT_PAIRING" TRANSPORT || true)"
  local_socks="$(get_kv_file_value "$CLIENT_PAIRING" LOCAL_SOCKS || true)"
  [ -n "$client_real_ip" ] && [ -n "$client_spoof_ip" ] || {
    fail "Client pairing file is incomplete: $CLIENT_PAIRING"
    return 1
  }
  say "\n${BOLD}Copy this CLIENT pairing block back to the server/foreign side:${NC}"
  cat <<EOF_PAIR
-----BEGIN SPOOF-TUNNEL CLIENT PAIRING-----
VERSION=${TARGET_SPOOF_VERSION}
ROLE=client
TRANSPORT=${transport}
CLIENT_REAL_IP=${client_real_ip}
CLIENT_SPOOF_IP=${client_spoof_ip}
CLIENT_PUBLIC_KEY=${public}
LOCAL_SOCKS=${local_socks}
-----END SPOOF-TUNNEL CLIENT PAIRING-----
EOF_PAIR
}

prepare_server_pairing() {
  require_root || return 1
  mkdirs
  [ -x "$INSTALL_BIN" ] || { fail "spoof binary is not installed. Run offline/online install first."; return 1; }
  backup_now >/dev/null 2>&1 || true

  say "\n${BOLD}Server Step 1: generate SERVER pairing info${NC}"
  say "This step is for the foreign/server side. It generates the server key automatically."
  say "You will copy the output block to the Iran/client side later."

  local keys transport listen_addr listen_port server_real_ip server_spoof_ip log_level log_file
  keys="$(load_keys_or_generate "server" || true)"
  [ -n "$keys" ] || return 1
  transport="$(ask_transport)"
  listen_addr="$(ask "Tunnel listen address" "0.0.0.0")"
  listen_port="$(ask_port "Tunnel listen port" "8080")"
  server_real_ip="$(ask_ipv4 "This server real/public IP to share with client" "")"
  server_spoof_ip="$(ask_ipv4 "Server spoof source IP" "")"
  log_level="$(ask_log_level)"
  log_file="$(ask "Server log file path" "${LOG_DIR}/server.log")"

  save_server_pending "$transport" "$listen_addr" "$listen_port" "$server_real_ip" "$server_spoof_ip" "$log_level" "$log_file"
  ok "Server key and pending settings saved."
  ok "No client key is needed in this step."
  print_server_pairing_from_file
  say "\nNext: run the manager on the client/Iran server and choose: Client Step 2."
}

configure_client_from_pairing() {
  require_root || return 1
  need_systemd || return 1
  mkdirs
  [ -x "$INSTALL_BIN" ] || { fail "spoof binary is not installed. Run offline/online install first."; return 1; }
  backup_now >/dev/null 2>&1 || true

  say "\n${BOLD}Client Step 2: configure CLIENT from SERVER pairing${NC}"
  say "Paste the SERVER pairing block generated on the foreign/server side."
  local block transport server_addr server_port server_spoof_ip server_public_key listen_addr listen_port client_real_ip client_spoof_ip keys private_key public_key log_level log_file
  block="$(read_pairing_block)"
  transport="$(pairing_value "$block" TRANSPORT)"
  server_addr="$(pairing_value "$block" SERVER_REAL_IP)"
  server_port="$(pairing_value "$block" SERVER_PORT)"
  server_spoof_ip="$(pairing_value "$block" SERVER_SPOOF_IP)"
  server_public_key="$(pairing_value "$block" SERVER_PUBLIC_KEY)"

  transport="$(ask "Transport type" "${transport:-udp}")"
  case "$transport" in udp|icmp) ;; *) fail "Invalid transport in pairing block or input. Use udp or icmp."; return 1 ;; esac
  server_addr="$(ask_ipv4 "Server real IP" "$server_addr")"
  server_port="$(ask_port "Server tunnel port" "${server_port:-8080}")"
  server_spoof_ip="$(ask_ipv4 "Expected server spoof source IP" "$server_spoof_ip")"
  server_public_key="$(ask_non_empty "Server public key" "$server_public_key")"
  listen_addr="$(ask "Local SOCKS listen address" "127.0.0.1")"
  listen_port="$(ask_port "Local SOCKS listen port" "1080")"
  client_real_ip="$(ask_ipv4 "This client/Iran server real IP to share with server" "")"
  client_spoof_ip="$(ask_ipv4 "Client spoof source IP" "")"

  keys="$(load_keys_or_generate "client" || true)"
  [ -n "$keys" ] || return 1
  private_key="${keys%%|*}"
  public_key="${keys#*|}"
  log_level="$(ask_log_level)"
  log_file="$(ask "Client log file path" "${LOG_DIR}/client.log")"

  write_client_config "$transport" "$listen_addr" "$listen_port" "$server_addr" "$server_port" "$client_spoof_ip" "$server_spoof_ip" "$private_key" "$server_public_key" "$log_level" "$log_file"
  create_client_service
  cat > "$CLIENT_PAIRING" <<EOF_CLIENT_PAIR
TRANSPORT=$transport
CLIENT_REAL_IP=$client_real_ip
CLIENT_SPOOF_IP=$client_spoof_ip
LOCAL_SOCKS=${listen_addr}:${listen_port}
EOF_CLIENT_PAIR
  chmod 600 "$CLIENT_PAIRING"
  ok "Client config written: $CLIENT_CONFIG"
  print_client_pairing_from_file
  say "\nNext: go back to the foreign/server side and choose: Server Step 3."
}

finalize_server_from_client_pairing() {
  require_root || return 1
  need_systemd || return 1
  mkdirs
  [ -x "$INSTALL_BIN" ] || { fail "spoof binary is not installed. Run offline/online install first."; return 1; }
  [ -f "$SERVER_PENDING" ] || { fail "Server pending file not found: $SERVER_PENDING"; say "Run Server Step 1 first on this server."; return 1; }
  backup_now >/dev/null 2>&1 || true

  say "\n${BOLD}Server Step 3: finalize SERVER from CLIENT pairing${NC}"
  say "Paste the CLIENT pairing block generated on the Iran/client side."
  local block transport listen_addr listen_port server_spoof_ip client_real_ip client_spoof_ip client_public_key keys private_key public_key log_level log_file
  block="$(read_pairing_block)"
  client_real_ip="$(pairing_value "$block" CLIENT_REAL_IP)"
  client_spoof_ip="$(pairing_value "$block" CLIENT_SPOOF_IP)"
  client_public_key="$(pairing_value "$block" CLIENT_PUBLIC_KEY)"

  transport="$(get_kv_file_value "$SERVER_PENDING" TRANSPORT || true)"
  listen_addr="$(get_kv_file_value "$SERVER_PENDING" SERVER_LISTEN_ADDR || true)"
  listen_port="$(get_kv_file_value "$SERVER_PENDING" SERVER_PORT || true)"
  server_spoof_ip="$(get_kv_file_value "$SERVER_PENDING" SERVER_SPOOF_IP || true)"
  log_level="$(get_kv_file_value "$SERVER_PENDING" SERVER_LOG_LEVEL || true)"
  log_file="$(get_kv_file_value "$SERVER_PENDING" SERVER_LOG_FILE || true)"

  transport="$(ask "Transport type" "${transport:-udp}")"
  case "$transport" in udp|icmp) ;; *) fail "Invalid transport. Use udp or icmp."; return 1 ;; esac
  listen_addr="$(ask "Tunnel listen address" "${listen_addr:-0.0.0.0}")"
  listen_port="$(ask_port "Tunnel listen port" "${listen_port:-8080}")"
  server_spoof_ip="$(ask_ipv4 "Server spoof source IP" "$server_spoof_ip")"
  client_real_ip="$(ask_ipv4 "Client real IP for responses" "$client_real_ip")"
  client_spoof_ip="$(ask_ipv4 "Expected client spoof source IP" "$client_spoof_ip")"
  client_public_key="$(ask_non_empty "Client public key" "$client_public_key")"

  keys="$(read_key_pair server || load_keys_or_generate server || true)"
  [ -n "$keys" ] || return 1
  private_key="${keys%%|*}"
  public_key="${keys#*|}"
  log_level="$(ask_log_level_default="${log_level:-info}"; ask "Log level" "$ask_log_level_default")"
  case "$log_level" in debug|info|warn|error) ;; *) fail "Invalid log level. Use debug, info, warn, or error."; return 1 ;; esac
  log_file="$(ask "Server log file path" "${log_file:-${LOG_DIR}/server.log}")"

  write_server_config "$transport" "$listen_addr" "$listen_port" "$server_spoof_ip" "$client_spoof_ip" "$client_real_ip" "$private_key" "$client_public_key" "$log_level" "$log_file"
  create_server_service
  ok "Server config written: $SERVER_CONFIG"
  say "Server public key in use: $public_key"
  say "\nNow you can start/restart spoof-server and spoof-client from the service menu."
}

show_pairing_info() {
  say "\n${BOLD}Saved Pairing Info${NC}"
  if [ -f "$SERVER_PENDING" ] && [ -f "$SERVER_KEYS" ]; then
    print_server_pairing_from_file || true
  else
    warn "No complete server pairing info found."
  fi
  if [ -f "$CLIENT_PAIRING" ] && [ -f "$CLIENT_KEYS" ]; then
    print_client_pairing_from_file || true
  else
    warn "No complete client pairing info found."
  fi
}

create_client_service() {
  require_root || return 1
  cat > "$CLIENT_SERVICE" <<EOF_SERVICE
[Unit]
Description=Spoof Tunnel Client (managed by st-manager)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${INSTALL_BIN} -c ${CLIENT_CONFIG}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=false
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF_SERVICE
  systemctl daemon-reload >/dev/null 2>&1 || true
  ok "Client service written: $CLIENT_SERVICE"
}

create_server_service() {
  require_root || return 1
  cat > "$SERVER_SERVICE" <<EOF_SERVICE
[Unit]
Description=Spoof Tunnel Server (managed by st-manager)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${INSTALL_BIN} -c ${SERVER_CONFIG}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=false
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF_SERVICE
  systemctl daemon-reload >/dev/null 2>&1 || true
  ok "Server service written: $SERVER_SERVICE"
}

write_client_config() {
  local transport listen_addr listen_port server_addr server_port source_ip peer_spoof_ip private_key peer_public_key log_level log_file
  transport="$1"; listen_addr="$2"; listen_port="$3"; server_addr="$4"; server_port="$5"; source_ip="$6"; peer_spoof_ip="$7"; private_key="$8"; peer_public_key="$9"; log_level="${10}"; log_file="${11}"
  cat > "$CLIENT_CONFIG" <<EOF_JSON
{
  "mode": "client",
  "transport": {
    "type": "$(json_escape "$transport")",
    "icmp_mode": "echo",
    "protocol_number": 0
  },
  "listen": {
    "address": "$(json_escape "$listen_addr")",
    "port": $listen_port
  },
  "server": {
    "address": "$(json_escape "$server_addr")",
    "port": $server_port
  },
  "spoof": {
    "source_ip": "$(json_escape "$source_ip")",
    "peer_spoof_ip": "$(json_escape "$peer_spoof_ip")"
  },
  "crypto": {
    "private_key": "$(json_escape "$private_key")",
    "peer_public_key": "$(json_escape "$peer_public_key")"
  },
  "performance": {
    "buffer_size": 65535,
    "mtu": 1400,
    "session_timeout": 90,
    "workers": 4,
    "read_buffer": 4194304,
    "write_buffer": 4194304
  },
  "fec": {
    "enabled": false,
    "data_shards": 10,
    "parity_shards": 3
  },
  "logging": {
    "level": "$(json_escape "$log_level")",
    "file": "$(json_escape "$log_file")"
  }
}
EOF_JSON
  chmod 600 "$CLIENT_CONFIG"
}

write_server_config() {
  local transport listen_addr listen_port source_ip peer_spoof_ip client_real_ip private_key peer_public_key log_level log_file
  transport="$1"; listen_addr="$2"; listen_port="$3"; source_ip="$4"; peer_spoof_ip="$5"; client_real_ip="$6"; private_key="$7"; peer_public_key="$8"; log_level="$9"; log_file="${10}"
  cat > "$SERVER_CONFIG" <<EOF_JSON
{
  "mode": "server",
  "transport": {
    "type": "$(json_escape "$transport")",
    "icmp_mode": "echo",
    "protocol_number": 0
  },
  "listen": {
    "address": "$(json_escape "$listen_addr")",
    "port": $listen_port
  },
  "spoof": {
    "source_ip": "$(json_escape "$source_ip")",
    "source_ipv6": "",
    "peer_spoof_ip": "$(json_escape "$peer_spoof_ip")",
    "peer_spoof_ipv6": "",
    "client_real_ip": "$(json_escape "$client_real_ip")",
    "client_real_ipv6": ""
  },
  "crypto": {
    "private_key": "$(json_escape "$private_key")",
    "peer_public_key": "$(json_escape "$peer_public_key")"
  },
  "performance": {
    "buffer_size": 131072,
    "mtu": 1400,
    "session_timeout": 600,
    "workers": 16,
    "read_buffer": 16777216,
    "write_buffer": 16777216
  },
  "reliability": {
    "enabled": true,
    "window_size": 128,
    "retransmit_timeout_ms": 300,
    "max_retries": 5,
    "ack_interval_ms": 50
  },
  "fec": {
    "enabled": true,
    "data_shards": 10,
    "parity_shards": 3
  },
  "keepalive": {
    "enabled": true,
    "interval_seconds": 30,
    "timeout_seconds": 120
  },
  "logging": {
    "level": "$(json_escape "$log_level")",
    "file": "$(json_escape "$log_file")"
  }
}
EOF_JSON
  chmod 600 "$SERVER_CONFIG"
}

configure_client() {
  require_root || return 1
  need_systemd || return 1
  mkdirs
  [ -x "$INSTALL_BIN" ] || { fail "spoof binary is not installed. Run install first."; return 1; }
  backup_now >/dev/null 2>&1 || true

  say "\n${BOLD}Client Configuration Wizard${NC}"
  local transport listen_addr listen_port server_addr server_port source_ip peer_spoof_ip keys private_key public_key peer_public_key log_level log_file
  transport="$(ask_transport)"
  listen_addr="$(ask "Local SOCKS listen address" "127.0.0.1")"
  listen_port="$(ask_port "Local SOCKS listen port" "1080")"
  server_addr="$(ask_ipv4 "Server real IP" "")"
  server_port="$(ask_port "Server tunnel port" "8080")"
  source_ip="$(ask_ipv4 "Client spoof source IP" "")"
  peer_spoof_ip="$(ask_ipv4 "Expected server spoof source IP" "")"
  keys="$(load_keys_or_generate "client" || true)"
  [ -n "$keys" ] || return 1
  private_key="${keys%%|*}"
  public_key="${keys#*|}"
  peer_public_key="$(ask "Server public key" "")"
  if [ -z "$peer_public_key" ]; then
    warn "Peer public key is empty. The service will not work until you edit $CLIENT_CONFIG."
  fi
  log_level="$(ask_log_level)"
  log_file="$(ask "Client log file path" "${LOG_DIR}/client.log")"

  write_client_config "$transport" "$listen_addr" "$listen_port" "$server_addr" "$server_port" "$source_ip" "$peer_spoof_ip" "$private_key" "$peer_public_key" "$log_level" "$log_file"
  create_client_service
  ok "Client config written: $CLIENT_CONFIG"
  say "\n${BOLD}Share this CLIENT pairing info with the server side:${NC}"
  say "CLIENT_REAL_IP=<this_server_real_ip>"
  say "CLIENT_SPOOF_IP=$source_ip"
  say "CLIENT_PUBLIC_KEY=$public_key"
  say "TRANSPORT=$transport"
  say "LOCAL_SOCKS=${listen_addr}:${listen_port}"
}

configure_server() {
  require_root || return 1
  need_systemd || return 1
  mkdirs
  [ -x "$INSTALL_BIN" ] || { fail "spoof binary is not installed. Run install first."; return 1; }
  backup_now >/dev/null 2>&1 || true

  say "\n${BOLD}Server Configuration Wizard${NC}"
  local transport listen_addr listen_port source_ip peer_spoof_ip client_real_ip keys private_key public_key peer_public_key log_level log_file
  transport="$(ask_transport)"
  listen_addr="$(ask "Tunnel listen address" "0.0.0.0")"
  listen_port="$(ask_port "Tunnel listen port" "8080")"
  source_ip="$(ask_ipv4 "Server spoof source IP" "")"
  peer_spoof_ip="$(ask_ipv4 "Expected client spoof source IP" "")"
  client_real_ip="$(ask_ipv4 "Client real IP for responses" "")"
  keys="$(load_keys_or_generate "server" || true)"
  [ -n "$keys" ] || return 1
  private_key="${keys%%|*}"
  public_key="${keys#*|}"
  peer_public_key="$(ask "Client public key" "")"
  if [ -z "$peer_public_key" ]; then
    warn "Peer public key is empty. The service will not work until you edit $SERVER_CONFIG."
  fi
  log_level="$(ask_log_level)"
  log_file="$(ask "Server log file path" "${LOG_DIR}/server.log")"

  write_server_config "$transport" "$listen_addr" "$listen_port" "$source_ip" "$peer_spoof_ip" "$client_real_ip" "$private_key" "$peer_public_key" "$log_level" "$log_file"
  create_server_service
  ok "Server config written: $SERVER_CONFIG"
  say "\n${BOLD}Share this SERVER pairing info with the client side:${NC}"
  say "SERVER_REAL_IP=<this_server_real_ip>"
  say "SERVER_PORT=$listen_port"
  say "SERVER_SPOOF_IP=$source_ip"
  say "SERVER_PUBLIC_KEY=$public_key"
  say "TRANSPORT=$transport"
}

service_name_for_role() {
  case "$1" in
    client) echo "spoof-client" ;;
    server) echo "spoof-server" ;;
    *) return 1 ;;
  esac
}

ask_role() {
  local role
  while true; do
    role="$(ask "Role" "client")"
    case "$role" in
      client|server) printf '%s' "$role"; return 0 ;;
      *) fail "Invalid role. Use client or server." ;;
    esac
  done
}

manage_service_action() {
  local action="$1" role svc
  require_root || return 1
  need_systemd || return 1
  role="$(ask_role)"
  svc="$(service_name_for_role "$role")"
  case "$action" in
    start)
      systemctl enable "$svc" >/dev/null 2>&1 || true
      systemctl start "$svc" && ok "$svc started." || fail "Could not start $svc. Check logs."
      ;;
    stop)
      systemctl stop "$svc" && ok "$svc stopped." || fail "Could not stop $svc."
      ;;
    restart)
      systemctl daemon-reload >/dev/null 2>&1 || true
      systemctl restart "$svc" && ok "$svc restarted." || fail "Could not restart $svc. Check logs."
      ;;
    status)
      systemctl status "$svc" --no-pager --lines=30 || true
      ;;
  esac
}

live_logs() {
  local role svc logfile
  need_systemd || return 1
  role="$(ask_role)"
  svc="$(service_name_for_role "$role")"
  logfile="${LOG_DIR}/${role}.log"
  info "Showing journal logs for $svc. Press Ctrl+C to stop."
  if [ -f "$logfile" ]; then
    info "File log also exists: $logfile"
  fi
  journalctl -u "$svc" -f --no-pager
}

extract_listen_port() {
  local file="$1"
  awk '
    /"listen"[[:space:]]*:/ {inlisten=1}
    inlisten && /"port"[[:space:]]*:/ {gsub(/[^0-9]/,"",$0); print $0; exit}
    inlisten && /}/ {inlisten=0}
  ' "$file" 2>/dev/null
}

extract_listen_address() {
  local file="$1"
  awk '
    /"listen"[[:space:]]*:/ {inlisten=1}
    inlisten && /"address"[[:space:]]*:/ {gsub(/.*"address"[[:space:]]*:[[:space:]]*"/,"",$0); gsub(/".*/,"",$0); print $0; exit}
    inlisten && /}/ {inlisten=0}
  ' "$file" 2>/dev/null
}

port_hex() { printf '%04X' "$1"; }

is_tcp_port_listening() {
  local port="$1" hex
  hex="$(port_hex "$port")"
  grep -qi ":${hex} .* 0A " /proc/net/tcp 2>/dev/null || grep -qi ":${hex} .* 0A " /proc/net/tcp6 2>/dev/null
}

check_config_placeholders() {
  local file="$1" bad=0
  [ -f "$file" ] || { fail "Missing config: $file"; return 1; }
  if grep -Eq 'YOUR_|EXPECTED_|CLIENT_REAL_IP_FOR_RESPONSES' "$file"; then
    warn "Config contains placeholder values: $file"
    bad=1
  fi
  if grep -Eq '"private_key"[[:space:]]*:[[:space:]]*""|"peer_public_key"[[:space:]]*:[[:space:]]*""' "$file"; then
    warn "Config has empty crypto keys: $file"
    bad=1
  fi
  return "$bad"
}

health_check() {
  local role svc cfg port addr
  need_systemd || return 1
  role="$(ask_role)"
  svc="$(service_name_for_role "$role")"
  if [ "$role" = "client" ]; then cfg="$CLIENT_CONFIG"; else cfg="$SERVER_CONFIG"; fi

  say "\n${BOLD}Health Check: $role${NC}"
  [ -x "$INSTALL_BIN" ] && ok "Binary exists: $INSTALL_BIN" || fail "Binary missing: $INSTALL_BIN"
  check_config_placeholders "$cfg" && ok "Config looks complete: $cfg" || warn "Config needs review: $cfg"
  if systemctl is-active --quiet "$svc"; then
    ok "Service is active: $svc"
  else
    fail "Service is not active: $svc"
  fi

  if [ "$role" = "client" ]; then
    port="$(extract_listen_port "$CLIENT_CONFIG")"
    addr="$(extract_listen_address "$CLIENT_CONFIG")"
    if [ -n "$port" ] && is_tcp_port_listening "$port"; then
      ok "Local SOCKS appears to be listening on ${addr:-127.0.0.1}:$port"
    else
      warn "Local SOCKS port is not listening yet. Check service logs and peer config."
    fi
  fi

  say "\nRecent logs:"
  journalctl -u "$svc" --no-pager --lines=20 || true
}

xui_helper() {
  local port addr
  if [ ! -f "$CLIENT_CONFIG" ]; then
    fail "Client config not found: $CLIENT_CONFIG"
    return 1
  fi
  port="$(extract_listen_port "$CLIENT_CONFIG")"
  addr="$(extract_listen_address "$CLIENT_CONFIG")"
  addr="${addr:-127.0.0.1}"
  port="${port:-1080}"
  say "\n${BOLD}X-UI Integration Helper${NC}"
  say "Use the local SOCKS endpoint created by spoof-tunnel as an outbound/proxy target in X-UI:"
  say "  Protocol : SOCKS5"
  say "  Address  : $addr"
  say "  Port     : $port"
  say "  Username : empty"
  say "  Password : empty"
  if is_tcp_port_listening "$port"; then
    ok "The local SOCKS port appears to be listening."
  else
    warn "The local SOCKS port is not listening right now. Start/restart spoof-client and check logs."
  fi
}

restore_backup() {
  require_root || return 1
  local backups count choice selected
  [ -d "$BACKUP_DIR" ] || { fail "No backup directory found."; return 1; }
  backups="$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r)"
  [ -n "$backups" ] || { fail "No backups found."; return 1; }
  say "Available backups:"
  count=0
  while IFS= read -r b; do
    count=$((count + 1))
    say "  $count) $(basename "$b")"
  done <<EOF_BK
$backups
EOF_BK
  choice="$(ask_port "Choose backup number" "1")"
  selected="$(printf '%s\n' "$backups" | sed -n "${choice}p")"
  [ -n "$selected" ] || { fail "Invalid backup selection."; return 1; }
  backup_now >/dev/null 2>&1 || true
  for f in client.json server.json client.keys server.keys spoof-client.service spoof-server.service; do
    if [ -e "$selected/$f" ]; then
      case "$f" in
        spoof-client.service) cp -a "$selected/$f" "$CLIENT_SERVICE" ;;
        spoof-server.service) cp -a "$selected/$f" "$SERVER_SERVICE" ;;
        *) cp -a "$selected/$f" "$CONFIG_DIR/$f" ;;
      esac
    fi
  done
  systemctl daemon-reload >/dev/null 2>&1 || true
  ok "Backup restored from: $selected"
}

uninstall_manager() {
  require_root || return 1
  if ! confirm "This will stop services and remove installed manager/binary. Keep configs unless you choose removal. Continue?" "N"; then
    return 0
  fi
  systemctl stop spoof-client >/dev/null 2>&1 || true
  systemctl stop spoof-server >/dev/null 2>&1 || true
  systemctl disable spoof-client >/dev/null 2>&1 || true
  systemctl disable spoof-server >/dev/null 2>&1 || true
  rm -f "$CLIENT_SERVICE" "$SERVER_SERVICE"
  systemctl daemon-reload >/dev/null 2>&1 || true
  rm -f "$INSTALL_BIN" "$MANAGER_BIN"
  ok "Services, manager, and spoof binary removed."
  if confirm "Remove configs and backups under $CONFIG_DIR?" "N"; then
    rm -rf "$CONFIG_DIR"
    ok "Configs removed."
  else
    ok "Configs kept: $CONFIG_DIR"
  fi
}

show_paths() {
  say "\n${BOLD}Paths${NC}"
  say "Manager      : $MANAGER_BIN"
  say "Spoof binary : $INSTALL_BIN"
  say "Config dir   : $CONFIG_DIR"
  say "Client config: $CLIENT_CONFIG"
  say "Server config: $SERVER_CONFIG"
  say "Log dir      : $LOG_DIR"
  say "Backups      : $BACKUP_DIR"
}

print_banner() {
  clear 2>/dev/null || true
  say "${CYAN}${BOLD}"
  say "========================================"
  say "  ${APP_NAME} ${APP_VERSION}"
  say "  Target upstream: ${UPSTREAM_REPO} ${TARGET_SPOOF_VERSION}"
  say "========================================"
  say "${NC}"
}

main_menu() {
  while true; do
    print_banner
    say "1) Install/repair manager only"
    say "2) Install spoof ${TARGET_SPOOF_VERSION} from local files (offline)"
    say "3) Install spoof ${TARGET_SPOOF_VERSION} from GitHub release (online)"
    say "4) Server Step 1: generate SERVER pairing"
    say "5) Client Step 2: configure from SERVER pairing"
    say "6) Server Step 3: finalize from CLIENT pairing"
    say "7) Manual configure as Client"
    say "8) Manual configure as Server"
    say "9) Start service"
    say "10) Stop service"
    say "11) Restart service"
    say "12) Service status"
    say "13) Live logs"
    say "14) Health check"
    say "15) X-UI helper"
    say "16) Show saved pairing info"
    say "17) Backup configs"
    say "18) Restore backup"
    say "19) Show paths"
    say "20) Uninstall"
    say "0) Exit"
    printf '\nSelect an option: '
    local choice
    read -r choice || choice=""
    case "$choice" in
      1) copy_manager_to_path; pause ;;
      2) install_offline; pause ;;
      3) install_online; pause ;;
      4) prepare_server_pairing; pause ;;
      5) configure_client_from_pairing; pause ;;
      6) finalize_server_from_client_pairing; pause ;;
      7) configure_client; pause ;;
      8) configure_server; pause ;;
      9) manage_service_action start; pause ;;
      10) manage_service_action stop; pause ;;
      11) manage_service_action restart; pause ;;
      12) manage_service_action status; pause ;;
      13) live_logs ;;
      14) health_check; pause ;;
      15) xui_helper; pause ;;
      16) show_pairing_info; pause ;;
      17) backup_now; pause ;;
      18) restore_backup; pause ;;
      19) show_paths; pause ;;
      20) uninstall_manager; pause ;;
      0) exit 0 ;;
      *) fail "Invalid option."; pause ;;
    esac
  done
}

case "${1:-}" in
  --install-manager) copy_manager_to_path ;;
  --install-offline) install_offline ;;
  --install-online) install_online ;;
  --server-step1) prepare_server_pairing ;;
  --client-step2) configure_client_from_pairing ;;
  --server-step3) finalize_server_from_client_pairing ;;
  --configure-client) configure_client ;;
  --configure-server) configure_server ;;
  --show-pairing) show_pairing_info ;;
  --health) health_check ;;
  --xui-helper) xui_helper ;;
  --version) echo "${APP_NAME} ${APP_VERSION} targeting spoof-tunnel ${TARGET_SPOOF_VERSION}" ;;
  --help|-h)
    cat <<EOF_HELP
${APP_NAME} ${APP_VERSION}

Usage:
  sudo bash st-manager.sh                 Interactive menu
  sudo bash st-manager.sh --install-offline
  sudo bash st-manager.sh --install-online
  sudo bash st-manager.sh --server-step1
  sudo bash st-manager.sh --client-step2
  sudo bash st-manager.sh --server-step3
  sudo bash st-manager.sh --configure-client   Manual client config
  sudo bash st-manager.sh --configure-server   Manual server config
  sudo st-manager                              Interactive menu after installation

Offline install:
  Put a spoof ${TARGET_SPOOF_VERSION} binary or release archive next to this script,
  then run: sudo bash st-manager.sh --install-offline
EOF_HELP
    ;;
  *) main_menu ;;
esac
