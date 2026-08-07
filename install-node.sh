#!/usr/bin/env bash
# xboard-node one-click installer for Linux x86_64.
set -Eeuo pipefail

BASE="${XBN_BASE:-https://raw.githubusercontent.com/Wangin1996/rustpanel/main}"
URL=""
TOKEN=""
NODE_ID=""
MACHINE_ID=""
KERNEL="singbox"
RECONFIGURE=0

die() {
  echo "error: $*" >&2
  exit 1
}

need_value() {
  [ "$#" -ge 2 ] || die "$1 requires a value"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url) need_value "$@"; URL="$2"; shift 2 ;;
    --token) need_value "$@"; TOKEN="$2"; shift 2 ;;
    --node-id) need_value "$@"; NODE_ID="$2"; shift 2 ;;
    --machine-id) need_value "$@"; MACHINE_ID="$2"; shift 2 ;;
    --kernel) need_value "$@"; KERNEL="$2"; shift 2 ;;
    --base) need_value "$@"; BASE="$2"; shift 2 ;;
    --reconfigure) RECONFIGURE=1; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ "$(id -u)" = "0" ] || die "please run as root (sudo)"
[ -n "$URL" ] && [ -n "$TOKEN" ] || die "--url and --token are required"
if [ -n "$NODE_ID" ] && [ -n "$MACHINE_ID" ]; then
  die "--node-id and --machine-id are mutually exclusive"
fi
[ -n "$NODE_ID" ] || [ -n "$MACHINE_ID" ] || die "--node-id or --machine-id is required"
[[ "${NODE_ID:-${MACHINE_ID}}" =~ ^[1-9][0-9]*$ ]] || die "node or machine id must be positive"
case "$KERNEL" in singbox|xray) ;; *) die "--kernel must be singbox or xray" ;; esac
case "$BASE" in https://*) ;; *) die "download base must use HTTPS" ;; esac
case "$URL" in http://*|https://*) ;; *) die "panel URL must use HTTP or HTTPS" ;; esac
[[ "$URL" != *$'\n'* && "$URL" != *$'\r'* && "$URL" != *'"'* && "$URL" != *'\\'* ]] || die "panel URL contains unsafe characters"
[[ "$TOKEN" =~ ^[A-Za-z0-9._~-]+$ ]] || die "token contains unsafe characters"
[ "$(uname -m)" = "x86_64" ] || die "only Linux x86_64 is supported"
for command_name in curl systemctl sha256sum awk install; do
  command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required"
done

INSTALL_DIR="/opt/xboard-node"
CONFIG_DIR="/etc/xboard-node"
BINARY_PATH="$INSTALL_DIR/xboard-node"
CONFIG_PATH="$CONFIG_DIR/config.yml"
CREDENTIALS_PATH="$CONFIG_DIR/credentials.env"
SERVICE_PATH="/etc/systemd/system/xboard-node.service"

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
STAGE="$(mktemp -d "$INSTALL_DIR/.install.XXXXXX")"
BACKUP="$STAGE/backup"
mkdir -p "$BACKUP"
BACKUP_READY=0
WAS_ACTIVE=0
WAS_ENABLED=0

cleanup_stage() {
  rm -rf -- "$STAGE"
}

rollback_install() {
  [ "$BACKUP_READY" -eq 1 ] || return 0
  echo ">> rolling back failed installation" >&2
  systemctl stop xboard-node >/dev/null 2>&1 || true
  for entry in xboard-node config.yml credentials.env xboard-node.service; do
    case "$entry" in
      xboard-node) target="$BINARY_PATH"; mode=755 ;;
      config.yml) target="$CONFIG_PATH"; mode=600 ;;
      credentials.env) target="$CREDENTIALS_PATH"; mode=600 ;;
      xboard-node.service) target="$SERVICE_PATH"; mode=644 ;;
    esac
    if [ -f "$BACKUP/$entry" ]; then
      install -m "$mode" "$BACKUP/$entry" "$target"
    else
      rm -f -- "$target"
    fi
  done
  systemctl daemon-reload >/dev/null 2>&1 || true
  if [ "$WAS_ENABLED" -eq 1 ]; then
    systemctl enable xboard-node >/dev/null 2>&1 || true
  else
    systemctl disable xboard-node >/dev/null 2>&1 || true
  fi
  if [ "$WAS_ACTIVE" -eq 1 ]; then
    systemctl restart xboard-node >/dev/null 2>&1 || true
  fi
}

on_error() {
  code=$?
  trap - ERR
  rollback_install
  exit "$code"
}
trap on_error ERR
trap cleanup_stage EXIT

echo ">> [1/4] downloading and verifying xboard-node from $BASE"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 "$BASE/xboard-node" -o "$STAGE/xboard-node"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 "$BASE/xboard-node.sha256" -o "$STAGE/xboard-node.sha256"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 "$BASE/xboard-node.version" -o "$STAGE/xboard-node.version"
EXPECTED_SHA="$(awk 'NR == 1 { print tolower($1) }' "$STAGE/xboard-node.sha256")"
ACTUAL_SHA="$(sha256sum "$STAGE/xboard-node" | awk '{ print tolower($1) }')"
[[ "$EXPECTED_SHA" =~ ^[0-9a-f]{64}$ ]] || die "invalid SHA-256 manifest"
[ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] || die "xboard-node SHA-256 mismatch"
chmod 755 "$STAGE/xboard-node"
EXPECTED_VERSION="$(tr -d '\r\n' < "$STAGE/xboard-node.version")"
if [[ ! "$EXPECTED_VERSION" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)([-+][0-9A-Za-z.-]+)?$ ]] || [[ "${EXPECTED_VERSION,,}" == *dirty* ]]; then
  die "invalid release version: $EXPECTED_VERSION"
fi
VERSION_OUTPUT="$("$STAGE/xboard-node" -v)"
ACTUAL_VERSION="$(printf '%s\n' "$VERSION_OUTPUT" | awk '$1 == "xboard-node" { print $2; exit }')"
[ "$ACTUAL_VERSION" = "$EXPECTED_VERSION" ] || die "binary version mismatch: got ${ACTUAL_VERSION:-invalid}, expected $EXPECTED_VERSION"

WRITE_CONFIG=0
if [ "$RECONFIGURE" -eq 1 ] || [ ! -f "$CONFIG_PATH" ]; then
  WRITE_CONFIG=1
  if [ -n "$MACHINE_ID" ]; then
    cat > "$STAGE/config.yml" <<EOF
panel:
  url: "$URL"
machine:
  machine_id: $MACHINE_ID
  token_env: XBOARD_MACHINE_TOKEN
kernel:
  type: $KERNEL
  log_level: warn
log:
  level: info
  output: stdout
EOF
    printf 'XBOARD_MACHINE_TOKEN=%s\n' "$TOKEN" > "$STAGE/credentials.env"
  else
    cat > "$STAGE/config.yml" <<EOF
panel:
  url: "$URL"
  token_env: XBOARD_NODE_TOKEN
  node_id: $NODE_ID
kernel:
  type: $KERNEL
  log_level: warn
log:
  level: info
  output: stdout
EOF
    printf 'XBOARD_NODE_TOKEN=%s\n' "$TOKEN" > "$STAGE/credentials.env"
  fi
  chmod 600 "$STAGE/config.yml" "$STAGE/credentials.env"
else
  echo ">> preserving existing $CONFIG_PATH (use --reconfigure to replace it)"
fi

cat > "$STAGE/xboard-node.service" <<'EOF'
[Unit]
Description=xboard-node (proxy node agent)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/xboard-node
EnvironmentFile=-/etc/xboard-node/credentials.env
ExecStart=/opt/xboard-node/xboard-node -c /etc/xboard-node/config.yml
Restart=always
RestartSec=2
NoNewPrivileges=true
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW

[Install]
WantedBy=multi-user.target
EOF

for pair in "$BINARY_PATH:xboard-node" "$CONFIG_PATH:config.yml" "$CREDENTIALS_PATH:credentials.env" "$SERVICE_PATH:xboard-node.service"; do
  target="${pair%%:*}"
  name="${pair#*:}"
  [ -f "$target" ] && cp -p "$target" "$BACKUP/$name"
done
systemctl is-active xboard-node >/dev/null 2>&1 && WAS_ACTIVE=1 || true
systemctl is-enabled xboard-node >/dev/null 2>&1 && WAS_ENABLED=1 || true
BACKUP_READY=1

echo ">> [2/4] installing files atomically"
systemctl stop xboard-node >/dev/null 2>&1 || true
install -m 755 "$STAGE/xboard-node" "$BINARY_PATH.new"
mv -f "$BINARY_PATH.new" "$BINARY_PATH"
rm -f -- "$BINARY_PATH.bak" "$BINARY_PATH.failed" "$BINARY_PATH.update-pending" "$BINARY_PATH.update-pending.tmp"
if [ "$WRITE_CONFIG" -eq 1 ]; then
  install -m 600 "$STAGE/config.yml" "$CONFIG_PATH.new"
  mv -f "$CONFIG_PATH.new" "$CONFIG_PATH"
  install -m 600 "$STAGE/credentials.env" "$CREDENTIALS_PATH.new"
  mv -f "$CREDENTIALS_PATH.new" "$CREDENTIALS_PATH"
fi
install -m 644 "$STAGE/xboard-node.service" "$SERVICE_PATH.new"
mv -f "$SERVICE_PATH.new" "$SERVICE_PATH"

echo ">> [3/4] starting systemd service"
systemctl daemon-reload
systemctl enable xboard-node >/dev/null 2>&1
systemctl restart xboard-node
stable=0
for _ in {1..30}; do
  if systemctl is-active xboard-node >/dev/null 2>&1; then
    stable=$((stable + 1))
    [ "$stable" -ge 10 ] && break
  else
    stable=0
  fi
  sleep 1
done
if [ "$stable" -lt 10 ]; then
  journalctl -u xboard-node -n 30 --no-pager || true
  rollback_install
  BACKUP_READY=0
  die "service did not remain active"
fi

BACKUP_READY=0
echo ">> [4/4] installation succeeded: xboard-node $EXPECTED_VERSION"
echo ">> logs: journalctl -u xboard-node -f"
