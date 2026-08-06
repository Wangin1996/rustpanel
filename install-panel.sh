#!/usr/bin/env bash
# rust-panel one-click installer (single MySQL backend, systemd).
#
# Interactive install:
#   curl -fsSL https://raw.githubusercontent.com/Wangin1996/rustpanel/main/install-panel.sh | sudo bash
#
# Non-interactive install:
#   curl -fsSL .../install-panel.sh | \
#     sudo env RP_DATABASE_URL='mysql://user:pass@127.0.0.1:3306/rust_panel' bash
set -euo pipefail

BASE="${RP_BASE:-https://raw.githubusercontent.com/Wangin1996/rustpanel/main}"
BIND="${1:-0.0.0.0:8080}"
INSTALLER_REVISION=20260806.3
INSTALL_DIR=/opt/rust-panel
CONFIG_DIR=/etc/rust-panel
ENV_FILE="$CONFIG_DIR/panel.env"

[ "$(id -u)" = "0" ] || { echo "please run as root (sudo)"; exit 1; }
ARCH="$(uname -m)"
[ "$ARCH" = "x86_64" ] || { echo "only x86_64 is supported (got $ARCH)"; exit 1; }
command -v curl >/dev/null || { echo "curl is required"; exit 1; }
command -v tar >/dev/null || { echo "tar is required"; exit 1; }
command -v systemctl >/dev/null || { echo "systemd is required"; exit 1; }

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
STAGE="$(mktemp -d /tmp/rust-panel-install.XXXXXX)"
WAS_ACTIVE=0
INSTALL_STARTED=0
cleanup() {
  rm -rf "$STAGE"
  if [ "$WAS_ACTIVE" = 1 ] && [ "$INSTALL_STARTED" = 0 ]; then
    systemctl start rust-panel >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

random_hex() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$1"
  else
    head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

urlencode() {
  local LC_ALL=C value="$1" out="" char hex index
  for ((index = 0; index < ${#value}; index++)); do
    char="${value:index:1}"
    case "$char" in
      [a-zA-Z0-9.~_-]) out+="$char" ;;
      *) printf -v hex '%%%02X' "'$char"; out+="$hex" ;;
    esac
  done
  printf '%s' "$out"
}

prompt_value() {
  local variable="$1" label="$2" default="$3" secret="${4:-0}" value=""
  if [ ! -r /dev/tty ]; then
    echo "no interactive terminal; set RP_DATABASE_URL for unattended installation" >&2
    exit 1
  fi
  if [ "$secret" = 1 ]; then
    read -r -s -p "$label: " value </dev/tty
    echo >/dev/tty
  else
    read -r -p "$label [$default]: " value </dev/tty
    value="${value:-$default}"
  fi
  printf -v "$variable" '%s' "$value"
}

mysql_url_from_input() {
  local host="${RP_MYSQL_HOST:-127.0.0.1}"
  local port="${RP_MYSQL_PORT:-3306}"
  local database="${RP_MYSQL_DATABASE:-rust_panel}"
  local user="${RP_MYSQL_USER:-rust_panel}"
  local password="${RP_MYSQL_PASSWORD:-}"

  if [ -z "${RP_MYSQL_HOST+x}" ]; then prompt_value host "MySQL host" "$host"; fi
  if [ -z "${RP_MYSQL_PORT+x}" ]; then prompt_value port "MySQL port" "$port"; fi
  if [ -z "${RP_MYSQL_DATABASE+x}" ]; then prompt_value database "MySQL database" "$database"; fi
  if [ -z "${RP_MYSQL_USER+x}" ]; then prompt_value user "MySQL user" "$user"; fi
  if [ -z "$password" ]; then prompt_value password "MySQL password" "" 1; fi

  [ -n "$host" ] && [ -n "$port" ] && [ -n "$database" ] && [ -n "$user" ] && [ -n "$password" ] || {
    echo "all MySQL connection fields are required" >&2
    exit 1
  }
  case "$port" in *[!0-9]*|'') echo "invalid MySQL port" >&2; exit 1;; esac
  if [[ "$host" == *:* && "$host" != \[*\] ]]; then host="[$host]"; fi
  MYSQL_URL="mysql://$(urlencode "$user"):$(urlencode "$password")@${host}:${port}/$(urlencode "$database")"
}

set_env_value() {
  local env_path key value output found line
  env_path="${1:?missing environment file path}"
  key="${2:?missing environment key}"
  value="${3-}"
  output="${env_path}.tmp"
  found=0
  line=""
  : > "$output"
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == "$key="* ]]; then
      printf '%s=%s\n' "$key" "$value" >> "$output"
      found=1
    else
      printf '%s\n' "$line" >> "$output"
    fi
  done < "$env_path"
  if [ "$found" = 0 ]; then printf '%s=%s\n' "$key" "$value" >> "$output"; fi
  mv "$output" "$env_path"
}

OLD_DATABASE_URL=""
if [ -f "$ENV_FILE" ]; then
  OLD_DATABASE_URL="$(sed -n 's/^DATABASE_URL=//p' "$ENV_FILE" | tail -n 1)"
fi
if [[ "$OLD_DATABASE_URL" == sqlite:* ]]; then
  echo "existing SQLite installations are no longer supported by this release" >&2
  exit 1
fi

echo ">> rust-panel installer revision $INSTALLER_REVISION"
echo ">> [1/4] downloading release artifacts ..."
curl -fsSL "$BASE/rust-panel" -o "$STAGE/rust-panel"
curl -fsSL "$BASE/web.tar.gz" -o "$STAGE/web.tar.gz"
curl -fsSL "$BASE/rust-panel.service" -o "$STAGE/rust-panel.service"
chmod +x "$STAGE/rust-panel"
mkdir -p "$STAGE/web"
tar xzf "$STAGE/web.tar.gz" -C "$STAGE/web"
[ -f "$STAGE/web/xboard-admin/dist/index.html" ] || { echo "invalid web package: admin index missing"; exit 1; }
[ -f "$STAGE/web/user-portal/index.html" ] || { echo "invalid web package: portal index missing"; exit 1; }
[ -f "$STAGE/web/user-portal/portal.css" ] || { echo "invalid web package: portal stylesheet missing"; exit 1; }
[ -f "$STAGE/web/user-portal/portal.js" ] || { echo "invalid web package: portal script missing"; exit 1; }
[ -f "$STAGE/web/user-portal/dashboard.js" ] || { echo "invalid web package: dashboard script missing"; exit 1; }
[ -f "$STAGE/web/user-portal/dashboard.html" ] || { echo "invalid web package: dashboard markup missing"; exit 1; }

if [ -n "${RP_DATABASE_URL:-}" ]; then
  MYSQL_URL="$RP_DATABASE_URL"
elif [[ "$OLD_DATABASE_URL" == mysql://* ]]; then
  MYSQL_URL="$OLD_DATABASE_URL"
else
  echo ">> MySQL connection (the database and user must already exist)"
  mysql_url_from_input
fi
[[ "$MYSQL_URL" == mysql://* ]] || { echo "DATABASE_URL must start with mysql://" >&2; exit 1; }

NEW_ADMIN=0
PW=""
if [ -f "$ENV_FILE" ]; then
  cp "$ENV_FILE" "$STAGE/panel.env"
else
  SECRET="$(random_hex 32)"
  IDENTITY_KEY="$(random_hex 32)"
  # 112 random bits plus every required character class; safe in panel.env.
  PW="Aa9-$(random_hex 14)"
  cat > "$STAGE/panel.env" <<EOF
APP_BIND=$BIND
APP_ENV=prod
DATABASE_URL=$MYSQL_URL
DB_MAX_CONNECTIONS=20
BUSINESS_TIMEZONE=Asia/Shanghai
JWT_SECRET=$SECRET
JWT_TTL_SECS=7200
TRUSTED_PROXIES=127.0.0.1,::1
RISK_ENABLED=true
RISK_PERSIST_BANS=true
LOGIN_WINDOW_SECS=600
LOGIN_ACCOUNT_LIMIT=5
LOGIN_IP_LIMIT=20
LOGIN_MAX_LOCK_SECS=3600
SCAN_WINDOW_SECS=60
SCAN_SCORE_LIMIT=15
SCAN_BAN_SECS=600
SCAN_BAN_MAX_SECS=3600
SCAN_SCORE_NOT_FOUND=1
SCAN_SCORE_SENSITIVE_PATH=5
SCAN_SCORE_BAD_REQUEST=2
SCAN_SCORE_METHOD_NOT_ALLOWED=2
SCAN_SCORE_PAYLOAD_TOO_LARGE=2
PANEL_IDENTITY_KEY=$IDENTITY_KEY
BOOTSTRAP_ADMIN_EMAIL=admin@example.com
BOOTSTRAP_ADMIN_PASSWORD=$PW
ADMIN_DIST=/opt/rust-panel/xboard-admin/dist
USER_PORTAL_DIR=/opt/rust-panel/user-portal
IP2REGION_DIR=/opt/rust-panel/ip2region
RUST_LOG=info,rust_panel=info
EOF
  NEW_ADMIN=1
fi
set_env_value "$STAGE/panel.env" DATABASE_URL "$MYSQL_URL"
if ! grep -q '^DB_MAX_CONNECTIONS=' "$STAGE/panel.env"; then
  printf 'DB_MAX_CONNECTIONS=20\n' >> "$STAGE/panel.env"
fi
if ! grep -q '^PANEL_IDENTITY_KEY=' "$STAGE/panel.env"; then
  printf 'PANEL_IDENTITY_KEY=%s\n' "$(random_hex 32)" >> "$STAGE/panel.env"
fi
if ! grep -q '^BUSINESS_TIMEZONE=' "$STAGE/panel.env"; then
  printf 'BUSINESS_TIMEZONE=Asia/Shanghai\n' >> "$STAGE/panel.env"
fi
if ! grep -q '^TRUSTED_PROXIES=' "$STAGE/panel.env"; then
  printf 'TRUSTED_PROXIES=127.0.0.1,::1\n' >> "$STAGE/panel.env"
fi
sed -i '/^IP2REGION_V4_XDB=/d; /^IP2REGION_V6_XDB=/d' "$STAGE/panel.env"
if ! grep -q '^IP2REGION_DIR=' "$STAGE/panel.env"; then
  printf 'IP2REGION_DIR=%s/ip2region\n' "$INSTALL_DIR" >> "$STAGE/panel.env"
fi
if grep -qx 'JWT_TTL_SECS=86400' "$STAGE/panel.env"; then
  set_env_value "$STAGE/panel.env" JWT_TTL_SECS 7200
fi

if systemctl is-active --quiet rust-panel; then
  WAS_ACTIVE=1
  systemctl stop rust-panel
fi
systemctl disable --now rust-panel-geoip-update.timer >/dev/null 2>&1 || true
rm -f /etc/systemd/system/rust-panel-geoip-update.service \
      /etc/systemd/system/rust-panel-geoip-update.timer \
      "$INSTALL_DIR/update-geoip.sh"

echo ">> [2/4] installing binary and web assets ..."
INSTALL_STARTED=1
mkdir -p "$INSTALL_DIR/xboard-admin" "$INSTALL_DIR/ip2region"
rm -rf "$INSTALL_DIR/xboard-admin/dist" "$INSTALL_DIR/user-portal"
mv "$STAGE/web/xboard-admin/dist" "$INSTALL_DIR/xboard-admin/dist"
mv "$STAGE/web/user-portal" "$INSTALL_DIR/user-portal"
mv "$STAGE/rust-panel" "$INSTALL_DIR/rust-panel"
chmod +x "$INSTALL_DIR/rust-panel"
mv "$STAGE/rust-panel.service" /etc/systemd/system/rust-panel.service
mv "$STAGE/panel.env" "$ENV_FILE"
chmod 600 "$ENV_FILE"
rm -f "$INSTALL_DIR/ip2region_v4.xdb" "$INSTALL_DIR/ip2region_v6.xdb"

echo ">> [3/4] enabling service ..."
systemctl daemon-reload
systemctl enable rust-panel >/dev/null 2>&1 || true

echo ">> [4/4] starting ..."
systemctl restart rust-panel
sleep 2
if ! systemctl is-active --quiet rust-panel; then
  echo "rust-panel failed to start" >&2
  systemctl --no-pager -l status rust-panel || true
  journalctl -u rust-panel -n 50 --no-pager || true
  exit 1
fi
systemctl --no-pager -l status rust-panel | head -n 12 || true

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
ACTIVE_BIND="$(sed -n 's/^APP_BIND=//p' "$ENV_FILE" | tail -n 1)"
ACTIVE_BIND="${ACTIVE_BIND:-$BIND}"
PORT="${ACTIVE_BIND##*:}"
echo
echo ">> done. Admin: http://${IP:-<server-ip>}:${PORT}/  User portal: http://${IP:-<server-ip>}:${PORT}/app"
if [ "$NEW_ADMIN" = 1 ]; then
  echo ">> Initial admin: admin@example.com"
  echo ">> Initial password: $PW"
fi
echo ">> Put nginx/caddy with HTTPS in front of the panel for production."
case "$ACTIVE_BIND" in
  0.0.0.0:*|\[::\]:*)
    echo ">> security: firewall port ${PORT}, or bind to 127.0.0.1 after enabling a reverse proxy."
    ;;
esac
