#!/usr/bin/env bash
# rust-panel one-click installer (SQLite backend, systemd).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Wangin1996/rustpanel/main/install-panel.sh | sudo bash
#   curl -fsSL https://raw.githubusercontent.com/Wangin1996/rustpanel/main/install-panel.sh | sudo bash -s -- 0.0.0.0:8080
#   # Behind nginx/caddy (recommended): use 127.0.0.1:8080
#
# Override download base with env RP_BASE.
set -euo pipefail

BASE="${RP_BASE:-https://raw.githubusercontent.com/Wangin1996/rustpanel/main}"
BIND="${1:-0.0.0.0:8080}"

[ "$(id -u)" = "0" ] || { echo "please run as root (sudo)"; exit 1; }
ARCH="$(uname -m)"; [ "$ARCH" = "x86_64" ] || { echo "only x86_64 supported (got $ARCH)"; exit 1; }
command -v curl >/dev/null || { echo "curl required"; exit 1; }
command -v tar  >/dev/null || { echo "tar required"; exit 1; }
command -v systemctl >/dev/null || { echo "systemd required"; exit 1; }

echo ">> [1/4] downloading binary + web assets + service ..."
mkdir -p /opt/rust-panel /etc/rust-panel
curl -fsSL "$BASE/rust-panel" -o /opt/rust-panel/rust-panel.new
mv -f /opt/rust-panel/rust-panel.new /opt/rust-panel/rust-panel
chmod +x /opt/rust-panel/rust-panel
WEB_ARCHIVE="$(mktemp /tmp/rp-web.XXXXXX)"
WEB_STAGE="$(mktemp -d /opt/rust-panel/.web-stage.XXXXXX)"
cleanup_web() {
  rm -f "$WEB_ARCHIVE"
  rm -rf "$WEB_STAGE"
}
trap cleanup_web EXIT
curl -fsSL "$BASE/web.tar.gz" -o "$WEB_ARCHIVE"
tar xzf "$WEB_ARCHIVE" -C "$WEB_STAGE"
[ -f "$WEB_STAGE/xboard-admin/dist/index.html" ] || { echo "invalid web package: admin index missing"; exit 1; }
[ -f "$WEB_STAGE/user-portal/index.html" ] || { echo "invalid web package: user portal missing"; exit 1; }
[ -f "$WEB_STAGE/user-portal/portal.css" ] || { echo "invalid web package: portal stylesheet missing"; exit 1; }
[ -f "$WEB_STAGE/user-portal/portal.js" ] || { echo "invalid web package: portal script missing"; exit 1; }
[ -f "$WEB_STAGE/user-portal/dashboard.js" ] || { echo "invalid web package: dashboard script missing"; exit 1; }
[ -f "$WEB_STAGE/user-portal/dashboard.html" ] || { echo "invalid web package: dashboard markup missing"; exit 1; }

# Hashed Vite chunks must be replaced as one set. Overlay extraction leaves old
# chunks usable, allowing a cached index.html to keep loading a stale frontend.
mkdir -p /opt/rust-panel/xboard-admin
rm -rf /opt/rust-panel/xboard-admin/dist /opt/rust-panel/user-portal
mv "$WEB_STAGE/xboard-admin/dist" /opt/rust-panel/xboard-admin/dist
mv "$WEB_STAGE/user-portal" /opt/rust-panel/user-portal
cleanup_web
trap - EXIT
curl -fsSL "$BASE/rust-panel.service" -o /etc/systemd/system/rust-panel.service

echo ">> [2/4] preparing env ..."
if [ ! -f /etc/rust-panel/panel.env ]; then
  SECRET="$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  IDENTITY_KEY="$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  PW="$(openssl rand -base64 12 2>/dev/null | tr -d '/+=' || echo "changeme$(date +%s)")"
  cat > /etc/rust-panel/panel.env <<EOF
APP_BIND=$BIND
APP_ENV=prod
DATABASE_URL=sqlite:///opt/rust-panel/panel.db
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
  chmod 600 /etc/rust-panel/panel.env
  NEW_ADMIN=1
fi

# Existing installations also need a stable panel identity. Generate it once
# and preserve it across all future upgrades.
if ! grep -q '^PANEL_IDENTITY_KEY=' /etc/rust-panel/panel.env; then
  IDENTITY_KEY="$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  printf '\nPANEL_IDENTITY_KEY=%s\n' "$IDENTITY_KEY" >> /etc/rust-panel/panel.env
  chmod 600 /etc/rust-panel/panel.env
fi

if ! grep -q '^BUSINESS_TIMEZONE=' /etc/rust-panel/panel.env; then
  printf '\nBUSINESS_TIMEZONE=Asia/Shanghai\n' >> /etc/rust-panel/panel.env
  chmod 600 /etc/rust-panel/panel.env
fi

# Keep upgrades non-destructive while making the proxy trust boundary explicit
# for older installations. Application defaults are identical to this value.
if ! grep -q '^TRUSTED_PROXIES=' /etc/rust-panel/panel.env; then
  printf '\nTRUSTED_PROXIES=127.0.0.1,::1\n' >> /etc/rust-panel/panel.env
  chmod 600 /etc/rust-panel/panel.env
fi

# Migrate the old installer default. Values customized to anything else are
# preserved exactly as configured by the operator.
if grep -qx 'JWT_TTL_SECS=86400' /etc/rust-panel/panel.env; then
  sed -i 's/^JWT_TTL_SECS=86400$/JWT_TTL_SECS=7200/' /etc/rust-panel/panel.env
  chmod 600 /etc/rust-panel/panel.env
fi

echo ">> [3/4] enabling service ..."
systemctl daemon-reload
systemctl enable rust-panel >/dev/null 2>&1 || true

echo ">> [4/4] starting ..."
systemctl restart rust-panel
sleep 2
systemctl --no-pager -l status rust-panel | head -n 12 || true

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
ACTIVE_BIND="$(sed -n 's/^APP_BIND=//p' /etc/rust-panel/panel.env | tail -n 1)"
ACTIVE_BIND="${ACTIVE_BIND:-$BIND}"
PORT="${ACTIVE_BIND##*:}"
echo ""
echo ">> done.  管理后台: http://${IP:-<本机IP>}:${PORT}/    默认用户门户: http://${IP:-<本机IP>}:${PORT}/app"
echo ">> 自定义管理/门户路径以面板“访问与安全”设置为准。"
if [ "${NEW_ADMIN:-0}" = "1" ]; then
  echo ">> 初始管理员: admin@example.com  /  $PW"
  echo ">> (可编辑 /etc/rust-panel/panel.env 后 systemctl restart rust-panel)"
fi
echo ">> 生产建议前置 nginx/caddy 上 HTTPS。"
case "$ACTIVE_BIND" in
  0.0.0.0:*|\[::\]:*)
    echo ">> security: backend is publicly bound; firewall port ${PORT} or switch APP_BIND to 127.0.0.1:${PORT} after enabling nginx/caddy."
    ;;
esac
