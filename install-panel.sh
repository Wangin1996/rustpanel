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
BIND="${1:-}"
INSTALLER_REVISION=20260909.1
INSTALL_DIR=/opt/rust-panel
CONFIG_DIR=/etc/rust-panel
ENV_FILE="$CONFIG_DIR/panel.env"
AUX_FILES="/usr/local/libexec/rust-panel-update:panel-update-helper /usr/local/libexec/rust-panel-release-verify:release-verifier /etc/systemd/system/rust-panel-update.service:update-service /etc/systemd/system/rust-panel-update.path:update-path /opt/rust-panel/.release-version:release-version /opt/rust-panel/release.json:release-manifest /etc/rust-panel/update-base:update-base"

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
INSTALL_OK=0
BACKUP_READY=0
BACKUP_DIR=""
cleanup() {
  if [ "$INSTALL_STARTED" = 1 ] && [ "$INSTALL_OK" = 0 ] && [ "$BACKUP_READY" = 1 ]; then
    echo ">> installation failed; restoring the previous release" >&2
    systemctl stop rust-panel >/dev/null 2>&1 || true
    rm -rf "$INSTALL_DIR/xboard-admin/dist" "$INSTALL_DIR/user-portal"
    [ -d "$BACKUP_DIR/admin-dist" ] && cp -a "$BACKUP_DIR/admin-dist" "$INSTALL_DIR/xboard-admin/dist"
    [ -d "$BACKUP_DIR/user-portal" ] && cp -a "$BACKUP_DIR/user-portal" "$INSTALL_DIR/user-portal"
    [ -f "$BACKUP_DIR/rust-panel" ] && cp -a "$BACKUP_DIR/rust-panel" "$INSTALL_DIR/rust-panel"
    [ -f "$BACKUP_DIR/rust-panel.service" ] && cp -a "$BACKUP_DIR/rust-panel.service" /etc/systemd/system/rust-panel.service
    [ -f "$BACKUP_DIR/panel.env" ] && cp -a "$BACKUP_DIR/panel.env" "$ENV_FILE"
    for pair in $AUX_FILES; do
      target="${pair%%:*}"; name="${pair#*:}"
      if [ -f "$BACKUP_DIR/$name" ]; then
        cp -a "$BACKUP_DIR/$name" "$target"
      else
        rm -f -- "$target"
      fi
    done
    systemctl daemon-reload >/dev/null 2>&1 || true
    if [ "$WAS_ACTIVE" = 1 ]; then systemctl start rust-panel >/dev/null 2>&1 || true; fi
  fi
  rm -rf "$STAGE"
  if [ "$WAS_ACTIVE" = 1 ] && [ "$INSTALL_OK" = 0 ] && [ "$BACKUP_READY" = 0 ]; then
    systemctl start rust-panel >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

prepare_release() {
  command -v python3 >/dev/null || { echo "python3 is required for release verification" >&2; exit 1; }
  command -v sha256sum >/dev/null || { echo "sha256sum is required" >&2; exit 1; }
  python3 - "$BASE" <<'PY'
import sys, urllib.parse
value = urllib.parse.urlsplit(sys.argv[1])
if value.scheme != 'https' or not value.hostname or value.username or value.password or value.query or value.fragment:
    raise SystemExit('release base must use HTTPS without credentials or query parameters')
PY
  curl --proto '=https' --tlsv1.2 -fsS --max-time 30 --max-filesize 65536 "${BASE%/}/release.json" -o "$STAGE/release.json"
  EXPECTED_VERIFIER="$(python3 - "$STAGE/release.json" "${RP_EXPECTED_MANIFEST_SHA256:-}" <<'PY'
import hashlib, json, re, sys
raw = open(sys.argv[1], 'rb').read(65537)
if len(raw) > 65536:
    raise SystemExit('release manifest too large')
if sys.argv[2] and hashlib.sha256(raw).hexdigest() != sys.argv[2]:
    raise SystemExit('release changed after confirmation')
item = json.loads(raw)['files']['release-verify.py']
if not re.fullmatch('[0-9a-f]{64}', item['sha256']) or not 0 < item['size'] <= 1048576:
    raise SystemExit('invalid verifier metadata')
print(item['sha256'])
PY
)"
  curl --proto '=https' --tlsv1.2 -fsS --max-time 30 --max-filesize 1048576 "${BASE%/}/release-verify.py" -o "$STAGE/release-verify.py"
  ACTUAL_VERIFIER="$(sha256sum "$STAGE/release-verify.py" | awk '{print $1}')"
  [ "$ACTUAL_VERIFIER" = "$EXPECTED_VERIFIER" ] || { echo "verifier SHA-256 mismatch" >&2; exit 1; }
  RELEASE_VERSION="$(python3 "$STAGE/release-verify.py" manifest "$STAGE" --expected-digest "${RP_EXPECTED_MANIFEST_SHA256:-}")"
}

verify_release_file() {
  python3 "$STAGE/release-verify.py" file "$STAGE" "$1" --expected-digest "${RP_EXPECTED_MANIFEST_SHA256:-}"
}

download_artifact() {
  python3 "$STAGE/release-verify.py" download "$STAGE" "$1" --base "$BASE" --expected-digest "${RP_EXPECTED_MANIFEST_SHA256:-}"
}

random_hex() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$1"
  else
    head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

port_is_unused() {
  local port="$1" listeners="" port_hex=""
  if command -v ss >/dev/null 2>&1 && listeners="$(ss -H -ltn 2>/dev/null)"; then
    if printf '%s\n' "$listeners" | awk -v suffix=":${port}" \
      '$4 ~ suffix "$" { found=1 } END { exit found ? 0 : 1 }'; then
      return 1
    fi
    return 0
  fi

  port_hex="$(printf '%04X' "$port")"
  if awk -v suffix=":${port_hex}" \
    '$2 ~ suffix "$" && $4 == "0A" { found=1 } END { exit found ? 0 : 1 }' \
    /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
    return 1
  fi
  return 0
}

random_unused_port() {
  local attempts=0 random="" candidate=""
  while [ "$attempts" -lt 128 ]; do
    attempts=$((attempts + 1))
    random="$(od -An -N4 -tu4 /dev/urandom | tr -d '[:space:]')"
    case "$random" in *[!0-9]*|'') continue;; esac
    candidate=$((20000 + random % 10000))
    if port_is_unused "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  echo "unable to find an unused TCP port in 20000-29999" >&2
  return 1
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
echo ">> [1/4] downloading and verifying release artifacts ..."
prepare_release
for artifact in rust-panel web.tar.gz rust-panel.service panel-update-helper.sh rust-panel-update.service rust-panel-update.path; do
  download_artifact "$artifact"
done
chmod 755 "$STAGE/rust-panel"
[ "$("$STAGE/rust-panel" --version)" = "rust-panel $RELEASE_VERSION" ] || { echo "panel binary version mismatch" >&2; exit 1; }
python3 "$STAGE/release-verify.py" extract-web "$STAGE" --expected-digest "${RP_EXPECTED_MANIFEST_SHA256:-}"
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
  if [ -z "$BIND" ]; then
    BIND="127.0.0.1:$(random_unused_port)"
    echo ">> selected first-install bind $BIND"
  fi
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
sed -i '/^IP2REGION_DIR=/d; /^IP2REGION_V4_XDB=/d; /^IP2REGION_V6_XDB=/d' "$STAGE/panel.env"
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
mkdir -p "$INSTALL_DIR/xboard-admin"
BACKUP_DIR="$STAGE/previous"
mkdir -p "$BACKUP_DIR"
[ -d "$INSTALL_DIR/xboard-admin/dist" ] && cp -a "$INSTALL_DIR/xboard-admin/dist" "$BACKUP_DIR/admin-dist"
[ -d "$INSTALL_DIR/user-portal" ] && cp -a "$INSTALL_DIR/user-portal" "$BACKUP_DIR/user-portal"
[ -f "$INSTALL_DIR/rust-panel" ] && cp -a "$INSTALL_DIR/rust-panel" "$BACKUP_DIR/rust-panel"
[ -f /etc/systemd/system/rust-panel.service ] && cp -a /etc/systemd/system/rust-panel.service "$BACKUP_DIR/rust-panel.service"
[ -f "$ENV_FILE" ] && cp -a "$ENV_FILE" "$BACKUP_DIR/panel.env"
for pair in $AUX_FILES; do
  target="${pair%%:*}"; name="${pair#*:}"
  if [ -f "$target" ]; then cp -a "$target" "$BACKUP_DIR/$name"; fi
done
if [ -f "$BACKUP_DIR/rust-panel" ] && [ -f "$BACKUP_DIR/panel.env" ]; then
  BACKUP_READY=1
fi
rm -rf "$INSTALL_DIR/xboard-admin/dist" "$INSTALL_DIR/user-portal"
mv "$STAGE/web/xboard-admin/dist" "$INSTALL_DIR/xboard-admin/dist"
mv "$STAGE/web/user-portal" "$INSTALL_DIR/user-portal"
mv "$STAGE/rust-panel" "$INSTALL_DIR/rust-panel"
chmod +x "$INSTALL_DIR/rust-panel"
mv "$STAGE/rust-panel.service" /etc/systemd/system/rust-panel.service
mv "$STAGE/panel.env" "$ENV_FILE"
if ! getent passwd rust-panel >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/rust-panel --shell /usr/sbin/nologin rust-panel
fi
install -d -o rust-panel -g rust-panel -m 700 /var/lib/rust-panel
install -d -o root -g root -m 755 /usr/local/libexec /var/lib/rust-panel-updater
install -o root -g root -m 755 "$STAGE/panel-update-helper.sh" /usr/local/libexec/rust-panel-update.new
mv -f /usr/local/libexec/rust-panel-update.new /usr/local/libexec/rust-panel-update
install -o root -g root -m 644 "$STAGE/release-verify.py" /usr/local/libexec/rust-panel-release-verify.new
mv -f /usr/local/libexec/rust-panel-release-verify.new /usr/local/libexec/rust-panel-release-verify
install -o root -g root -m 644 "$STAGE/rust-panel-update.service" /etc/systemd/system/rust-panel-update.service
install -o root -g root -m 644 "$STAGE/rust-panel-update.path" /etc/systemd/system/rust-panel-update.path
printf '%s\n' "$BASE" > "$STAGE/update-base"
install -o root -g root -m 644 "$STAGE/update-base" "$CONFIG_DIR/update-base"
chown rust-panel:rust-panel "$ENV_FILE"
chmod 600 "$ENV_FILE"
rm -rf "$INSTALL_DIR/ip2region"
rm -f "$INSTALL_DIR/ip2region_v4.xdb" "$INSTALL_DIR/ip2region_v6.xdb"

echo ">> [3/4] enabling service ..."
systemctl daemon-reload
systemctl enable rust-panel >/dev/null 2>&1 || true

echo ">> [4/4] starting ..."
systemctl restart rust-panel
HEALTH_BIND="$(sed -n 's/^APP_BIND=//p' "$ENV_FILE" | tail -n 1)"
HEALTH_BIND="${HEALTH_BIND:-127.0.0.1:8080}"
case "$HEALTH_BIND" in
  0.0.0.0:*) HEALTH_BIND="127.0.0.1:${HEALTH_BIND##*:}" ;;
  \[::\]:*) HEALTH_BIND="[::1]:${HEALTH_BIND##*:}" ;;
esac
stable=0
previous_pid=""
for attempt in {1..90}; do
  current_pid="$(systemctl show rust-panel -p MainPID --value)"
  if [ "$current_pid" != "$previous_pid" ]; then stable=0; fi
  previous_pid="$current_pid"
  if systemctl is-active --quiet rust-panel && [ "$(curl --noproxy '*' --connect-timeout 1 --max-time 2 -fsS "http://$HEALTH_BIND/healthz" 2>/dev/null || true)" = "rust-panel $RELEASE_VERSION" ]; then
    stable=$((stable + 1))
    [ "$stable" -ge 10 ] && break
  else
    stable=0
  fi
  sleep 1
done
if [ "$stable" -lt 10 ]; then
  echo "rust-panel failed to start" >&2
  systemctl --no-pager -l status rust-panel || true
  journalctl -u rust-panel -n 50 --no-pager || true
  exit 1
fi
printf '%s\n' "$RELEASE_VERSION" > "$STAGE/release-version"
install -o root -g root -m 644 "$STAGE/release-version" "$INSTALL_DIR/.release-version"
install -o root -g root -m 644 "$STAGE/release.json" "$INSTALL_DIR/release.json"
systemctl enable --now rust-panel-update.path >/dev/null 2>&1
INSTALL_OK=1
systemctl --no-pager -l status rust-panel | head -n 12 || true

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
ACTIVE_BIND="$(sed -n 's/^APP_BIND=//p' "$ENV_FILE" | tail -n 1)"
ACTIVE_BIND="${ACTIVE_BIND:-${BIND:-127.0.0.1:8080}}"
PORT="${ACTIVE_BIND##*:}"
echo
case "$ACTIVE_BIND" in
  127.0.0.1:*|\[::1\]:*)
    echo ">> done. Local Admin: http://${ACTIVE_BIND}/  User portal: http://${ACTIVE_BIND}/app"
    echo ">> Reverse proxy upstream: http://${ACTIVE_BIND}"
    ;;
  *)
    echo ">> done. Admin: http://${IP:-<server-ip>}:${PORT}/  User portal: http://${IP:-<server-ip>}:${PORT}/app"
    ;;
esac
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
