#!/usr/bin/env bash
# xboard-node one-click installer.
#
# Usage (node mode):
#   curl -fsSL https://raw.githubusercontent.com/Wangin1996/rustpanel/main/install-node.sh | sudo bash -s -- \
#     --url https://panel.example.com:8080 --token NODE_TOKEN --node-id 1 --kernel singbox
#
# Usage (machine mode — one agent serves several nodes on this host):
#   ... | sudo bash -s -- --url URL --token MACHINE_TOKEN --machine-id 1 --kernel singbox
#
# Override the download base with --base or env XBN_BASE.
set -euo pipefail

BASE="${XBN_BASE:-https://raw.githubusercontent.com/Wangin1996/rustpanel/main}"
URL="" TOKEN="" NODE_ID="" MACHINE_ID="" KERNEL="singbox"

while [ $# -gt 0 ]; do
  case "$1" in
    --url)        URL="$2"; shift 2;;
    --token)      TOKEN="$2"; shift 2;;
    --node-id)    NODE_ID="$2"; shift 2;;
    --machine-id) MACHINE_ID="$2"; shift 2;;
    --kernel)     KERNEL="$2"; shift 2;;
    --base)       BASE="$2"; shift 2;;
    *) echo "unknown arg: $1"; exit 1;;
  esac
done

[ "$(id -u)" = "0" ] || { echo "please run as root (sudo)"; exit 1; }
[ -n "$URL" ] && [ -n "$TOKEN" ] || { echo "need --url and --token"; exit 1; }
[ -n "$NODE_ID" ] || [ -n "$MACHINE_ID" ] || { echo "need --node-id or --machine-id"; exit 1; }

ARCH="$(uname -m)"
[ "$ARCH" = "x86_64" ] || { echo "only x86_64 is supported (got $ARCH)"; exit 1; }
command -v curl >/dev/null || { echo "curl is required"; exit 1; }
command -v systemctl >/dev/null || { echo "systemd is required"; exit 1; }

echo ">> [1/4] downloading and verifying xboard-node from $BASE ..."
mkdir -p /opt/xboard-node /etc/xboard-node
STAGE="$(mktemp -d /opt/xboard-node/.install.XXXXXX)"
cleanup_stage() {
  rm -rf "$STAGE"
}
trap cleanup_stage EXIT
curl -fsSL "$BASE/xboard-node" -o "$STAGE/xboard-node"
curl -fsSL "$BASE/xboard-node.sha256" -o "$STAGE/xboard-node.sha256"
curl -fsSL "$BASE/xboard-node.version" -o "$STAGE/xboard-node.version"
(cd "$STAGE" && sha256sum -c xboard-node.sha256)
chmod +x "$STAGE/xboard-node"
EXPECTED_VERSION="$(tr -d '\r\n' < "$STAGE/xboard-node.version")"
if [[ ! "$EXPECTED_VERSION" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)([-+][0-9A-Za-z.-]+)?$ ]] || [[ "${EXPECTED_VERSION,,}" == *dirty* ]]; then
  echo "invalid release version: $EXPECTED_VERSION"
  exit 1
fi
VERSION_OUTPUT="$("$STAGE/xboard-node" -v)"
ACTUAL_VERSION="$(printf '%s\n' "$VERSION_OUTPUT" | awk '$1 == "xboard-node" { print $2; exit }')"
if [ "$ACTUAL_VERSION" != "$EXPECTED_VERSION" ]; then
  echo "binary version mismatch: got ${ACTUAL_VERSION:-<invalid>}, expected $EXPECTED_VERSION"
  exit 1
fi
mv -f "$STAGE/xboard-node" /opt/xboard-node/xboard-node
chmod +x /opt/xboard-node/xboard-node
cleanup_stage
trap - EXIT

echo ">> [2/4] writing /etc/xboard-node/config.yml ..."
if [ -n "$MACHINE_ID" ]; then
  # Machine mode: token + machine_id live under the top-level `machine:` block.
  # panel.token / panel.node_id are ignored when `machine:` is present.
  cat > /etc/xboard-node/config.yml <<EOF
panel:
  url: "$URL"
machine:
  machine_id: $MACHINE_ID
  token: "$TOKEN"
kernel:
  type: $KERNEL
  log_level: info
log:
  log_level: info
EOF
else
  cat > /etc/xboard-node/config.yml <<EOF
panel:
  url: "$URL"
  token: "$TOKEN"
  node_id: $NODE_ID
kernel:
  type: $KERNEL
  log_level: info
log:
  log_level: info
EOF
fi
chmod 600 /etc/xboard-node/config.yml

echo ">> [3/4] installing systemd service ..."
curl -fsSL "$BASE/xboard-node.service" -o /etc/systemd/system/xboard-node.service
systemctl daemon-reload
systemctl enable xboard-node >/dev/null 2>&1 || true

echo ">> [4/4] starting ..."
systemctl restart xboard-node
sleep 1
systemctl --no-pager -l status xboard-node | head -n 12 || true
echo ">> done.  实时日志: journalctl -u xboard-node -f"
