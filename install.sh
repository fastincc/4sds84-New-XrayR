#!/usr/bin/env bash
set -Eeuo pipefail

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

REPO="${XRAYR_REPO:-fastincc/4sds84-New-XrayR}"
VERSION="${1:-${XRAYR_VERSION:-v0.9.4}}"
INSTALL_ACME="${INSTALL_ACME:-0}"

WORK_DIR="$(pwd)"
INSTALL_DIR="/usr/local/XrayR"
CONFIG_DIR="/etc/XrayR"
SERVICE_FILE="/etc/systemd/system/XrayR.service"
MANAGER_FILE="/usr/bin/XrayR"
TMP_DIR="/tmp/xrayr-install.$$"

log() {
  echo -e "${green}$*${plain}"
}

warn() {
  echo -e "${yellow}$*${plain}"
}

fail() {
  echo -e "${red}$*${plain}"
  exit 1
}

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

[[ "${EUID}" -ne 0 ]] && fail "Error: please run this script as root."

release=""
if [[ -f /etc/redhat-release ]]; then
  release="centos"
elif grep -Eqi "debian" /etc/issue 2>/dev/null || grep -Eqi "debian" /proc/version 2>/dev/null; then
  release="debian"
elif grep -Eqi "ubuntu" /etc/issue 2>/dev/null || grep -Eqi "ubuntu" /proc/version 2>/dev/null; then
  release="ubuntu"
elif grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux" /etc/issue 2>/dev/null || grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux" /proc/version 2>/dev/null; then
  release="centos"
else
  fail "Error: unsupported Linux distribution."
fi

machine="$(uname -m)"
case "$machine" in
  x86_64|x64|amd64) arch="64" ;;
  aarch64|arm64) arch="arm64-v8a" ;;
  s390x) arch="s390x" ;;
  *)
    arch="64"
    warn "Warning: unknown architecture '$machine', fallback to linux-64."
    ;;
esac

if [[ "$(getconf WORD_BIT)" != "32" && "$(getconf LONG_BIT)" != "64" ]]; then
  fail "Error: 32-bit systems are not supported."
fi

install_base() {
  log "Installing base dependencies..."
  if [[ "$release" == "centos" ]]; then
    if command -v dnf >/dev/null 2>&1; then
      dnf install -y wget curl unzip tar crontabs socat ca-certificates
    else
      yum install -y epel-release
      yum install -y wget curl unzip tar crontabs socat ca-certificates
    fi
  else
    apt-get update -y
    apt-get install -y wget curl unzip tar cron socat ca-certificates
  fi
}

download_file() {
  local url="$1"
  local out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --connect-timeout 15 --retry 3 --retry-delay 2 -o "$out" "$url"
  else
    wget -q --tries=3 --timeout=20 --no-check-certificate -O "$out" "$url"
  fi
}

verify_digest() {
  local file="$1"
  local digest_file="$2"

  if [[ ! -f "$digest_file" ]]; then
    warn "Warning: digest file missing, skip sha256 verification."
    return
  fi
  if ! command -v sha256sum >/dev/null 2>&1; then
    warn "Warning: sha256sum not found, skip sha256 verification."
    return
  fi

  local expected
  expected="$(awk -F'= ' '/SHA2-256/{print $2}' "$digest_file" | tr -d '[:space:]')"
  [[ -z "$expected" ]] && fail "Error: cannot parse SHA2-256 from $digest_file."

  local actual
  actual="$(sha256sum "$file" | awk '{print $1}')"
  [[ "$actual" != "$expected" ]] && fail "Error: SHA256 mismatch for $file."
  log "SHA256 verification passed."
}

install_acme_optional() {
  [[ "$INSTALL_ACME" != "1" ]] && return
  if [[ -x "$HOME/.acme.sh/acme.sh" ]]; then
    log "acme.sh already exists, skip."
    return
  fi
  warn "Installing acme.sh because INSTALL_ACME=1."
  curl -fsSL https://get.acme.sh | sh || warn "Warning: acme.sh installation failed, continue."
}

write_service() {
  cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=XrayR Service
Documentation=https://github.com/XrayR-project/XrayR
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
WorkingDirectory=/usr/local/XrayR
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
ExecStart=/usr/local/XrayR/XrayR -config /etc/XrayR/config.yml
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
}

write_manager() {
  cat > "$MANAGER_FILE" <<EOF
#!/usr/bin/env bash
set -e

REPO="${REPO}"
DEFAULT_VERSION="${VERSION}"

case "\${1:-menu}" in
  start)
    systemctl start XrayR
    ;;
  stop)
    systemctl stop XrayR
    ;;
  restart)
    systemctl restart XrayR
    ;;
  status)
    systemctl status XrayR --no-pager
    ;;
  enable)
    systemctl enable XrayR
    ;;
  disable)
    systemctl disable XrayR
    ;;
  log)
    journalctl -u XrayR.service -e --no-pager
    ;;
  follow|logs)
    journalctl -u XrayR.service -f
    ;;
  version)
    /usr/local/XrayR/XrayR version || true
    go version -m /usr/local/XrayR/XrayR 2>/dev/null || true
    ;;
  update|install)
    version="\${2:-\$DEFAULT_VERSION}"
    bash <(curl -fsSL "https://raw.githubusercontent.com/\${REPO}/main/install.sh") "\$version"
    ;;
  uninstall)
    read -r -p "Uninstall XrayR? This keeps /etc/XrayR by default. [y/N] " confirm
    if [[ "\$confirm" =~ ^[Yy]$ ]]; then
      systemctl stop XrayR || true
      systemctl disable XrayR || true
      rm -f /etc/systemd/system/XrayR.service
      systemctl daemon-reload
      rm -rf /usr/local/XrayR
      rm -f /usr/bin/XrayR /usr/bin/xrayr
      echo "XrayR uninstalled. /etc/XrayR is kept."
    fi
    ;;
  menu|*)
    cat <<'MENU'
XrayR manager:
  XrayR start        Start XrayR
  XrayR stop         Stop XrayR
  XrayR restart      Restart XrayR
  XrayR status       Show service status
  XrayR log          Show recent logs
  XrayR follow       Follow logs
  XrayR enable       Enable auto start
  XrayR disable      Disable auto start
  XrayR version      Show binary version/build info
  XrayR update       Reinstall/update default version
  XrayR update vX.Y  Reinstall/update specified version
  XrayR uninstall    Uninstall binary and service
MENU
    ;;
esac
EOF
  chmod +x "$MANAGER_FILE"
  ln -sf "$MANAGER_FILE" /usr/bin/xrayr
}

install_xrayr() {
  local pkg="XrayR-linux-${arch}.zip"
  local base_url="https://github.com/${REPO}/releases/download/${VERSION}"
  local pkg_url="${base_url}/${pkg}"
  local digest_url="${pkg_url}.dgst"

  mkdir -p "$TMP_DIR"
  log "Downloading ${REPO} ${VERSION} (${pkg})..."
  download_file "$pkg_url" "$TMP_DIR/$pkg"
  download_file "$digest_url" "$TMP_DIR/${pkg}.dgst" || warn "Warning: failed to download digest file."
  verify_digest "$TMP_DIR/$pkg" "$TMP_DIR/${pkg}.dgst"

  if systemctl list-unit-files | grep -q '^XrayR.service'; then
    systemctl stop XrayR || true
  fi

  if [[ -d "$INSTALL_DIR" ]]; then
    local backup="${INSTALL_DIR}.bak.$(date +%Y%m%d%H%M%S)"
    log "Backing up existing ${INSTALL_DIR} to ${backup}"
    mv "$INSTALL_DIR" "$backup"
  fi

  mkdir -p "$INSTALL_DIR"
  unzip -q "$TMP_DIR/$pkg" -d "$INSTALL_DIR"
  chmod +x "$INSTALL_DIR/XrayR"

  mkdir -p "$CONFIG_DIR"
  cp -f "$INSTALL_DIR/geoip.dat" "$CONFIG_DIR/" 2>/dev/null || true
  cp -f "$INSTALL_DIR/geosite.dat" "$CONFIG_DIR/" 2>/dev/null || true

  for file in dns.json route.json custom_outbound.json custom_inbound.json rulelist; do
    if [[ -f "$INSTALL_DIR/$file" && ! -f "$CONFIG_DIR/$file" ]]; then
      cp "$INSTALL_DIR/$file" "$CONFIG_DIR/"
    fi
  done

  if [[ ! -f "$CONFIG_DIR/config.yml" ]]; then
    cp "$INSTALL_DIR/config.yml" "$CONFIG_DIR/config.yml"
    warn "Fresh install: please edit ${CONFIG_DIR}/config.yml before starting XrayR."
  else
    log "Keeping existing ${CONFIG_DIR}/config.yml"
  fi

  write_service
  write_manager
  systemctl daemon-reload
  systemctl enable XrayR

  if [[ -f "$CONFIG_DIR/config.yml" ]]; then
    systemctl start XrayR || true
    sleep 2
    if systemctl is-active --quiet XrayR; then
      log "XrayR ${VERSION} installed and started successfully."
    else
      warn "XrayR installed, but service is not running. Use 'XrayR log' to inspect logs."
    fi
  fi
}

log "Installing XrayR from ${REPO}, version ${VERSION}, arch linux-${arch}"
install_base
install_acme_optional
install_xrayr
cd "$WORK_DIR"

cat <<EOF

XrayR manager commands:
  XrayR start
  XrayR stop
  XrayR restart
  XrayR status
  XrayR log
  XrayR follow
  XrayR version
  XrayR update ${VERSION}

Config file:
  ${CONFIG_DIR}/config.yml

Binary:
  ${INSTALL_DIR}/XrayR
EOF
