# rustpanel deployment artifacts

This repository contains the Linux x86_64 deployment artifacts for
`rust-panel` and `xboard-node`. Files are kept at the repository root because
the installers download them directly through GitHub Raw.

Current releases: panel `v1.1.71`, Agent `v1.1.32`.

Panel `v1.1.71` (Agent remains `v1.1.32`):
- Completes the full Linear visual architecture refactor across all 14 `xboard-admin`
  pages and `user-portal`: introduces shared Linear primitives (`MetricStrip`,
  `LinearPanel`, `LinearPanelHeader`, `LinearToolbar`, `LinearSegmentedControl`,
  `StatusDot`, `LinearBadge`, right-side `Drawer`), replaces all disconnected 4-card
  KPI grids with unified 1px hairline metric strips, eliminates all glowing dots /
  `rounded-2xl` bloat, converts detail & complex form modals (Machines, Nodes,
  Subscription Sources, Groups, Outbounds, Certificates, Plans, Users) into right-side
  Linear inspector/editor drawers, upgrades Templates to a unified Linear IDE panel,
  and aligns Settings & User Portal (`portal.css`) to hairline-divided Linear layouts
  with 100% RPC/data contract parity.

Panel `v1.1.70` (Agent remains `v1.1.32`):
- Fixes the Subscriptions Template editor (`@codemirror/state` duplicate instance
  runtime crash) by removing the stale nested `node_modules/node_modules/@codemirror`
  copy and adding explicit `resolve.dedupe` for `@codemirror/*` and `@lezer/*` in
  `xboard-admin/vite.config.ts`.
- Redesigns the Dashboard (`dashboard.tsx`) in authentic Linear visual language:
  unified 4-column hairline-divided metric strip, flat monochrome-plus-accent
  Recharts traffic distribution bar chart with crisp horizontal hairlines, and
  full-bleed hairline-divided host telemetry & node/user traffic ranking panels.

Panel `v1.1.69` (Agent remains `v1.1.32`):
- Refactors `xboard-admin` and `user-portal` around Linear's restrained, high-density
  visual language while keeping 100% of existing functionality, forms, modals, and
  backend RPC contracts unchanged: neutral obsidian dark & crisp light surfaces,
  1px hairline borders, Linear Indigo default accent (`#5E6AD2` / `#6270DF`, custom
  theme override preserved), compact 48px header / 224px sidebar / 32px controls,
  unified `8px`/`6px` radii, WCAG AA contrast & `focus-visible` keyboard accessibility,
  and mobile/keyboard up/down buttons in `SortableList`.

Panel `v1.1.66` and Agent `v1.1.32`:
- Panel `v1.1.66` fixes `/healthz` loopback version reporting during `install-panel.sh`
  health checks (returning `rust-panel vX.Y.Z` for local loopback installer probes
  while still returning plain `ok` to external reverse-proxied callers in
  production) and sets `ignore_missing` on `sqlx::migrate!` + `build.rs`
  `rerun-if-changed=migrations-mysql` so rollbacks after additive migrations never
  crash-loop.
- Agent `v1.1.32` removes the unused client-side `with_gvisor` build tag and enables
  `-trimpath` across `Makefile` and `Dockerfile`, shrinking the `xboard-node`
  binary by ~15.3 MB (`83.5 MB` -> `68.2 MB`) while keeping full WireGuard
  outbound support via Mihomo's native MIPS stack.

Panel `v1.1.65` and Agent `v1.1.31` (with `mihomo v1.19.34-xboard.4`) complete a
full-repository security, reliability, billing, and UX hardening pass:
- Panel (`v1.1.65`): fixes Admin TOTP 2FA login (`AppError::Unprocessable` message
  preservation + `refund_login` + transactional `FOR UPDATE` TOTP store + rate
  limiting), enforces mutual `client_proof` HMAC on secure WebSocket handshakes,
  fixes IPv6 `/128` CIDR truncation & mapped-IPv4 underflow in `CidrRange`,
  enforces `portal_enabled` & admin protection on `Scope::User`, adds YAML
  alias-bomb guards, fixes `node_flag_override_existing` GeoIP re-resolution and
  `TW -> CN` region ordering, fixes Hysteria default v2 & cross-source proxy name
  deduplication, preserves route `sort` on edit, adds an explicit `sync_existing_users`
  switch when editing plans, raises default `MAX_BODY_BYTES` / Nginx body ceiling
  to 4 MiB, hardens `install-panel.sh` `0600` atomic `panel.env` permissions, and
  shrinks `web.tar.gz` by 96% (~641 KB) while fixing all audited Admin UI and
  User Portal edge cases. Includes automatic MySQL `utf8mb4` migration `0026`.
- Agent (`v1.1.31` + `mihomo v1.19.34-xboard.4`): enforces mandatory gateway and
  heartbeat `response_proof` + WebSocket `client_proof`, eliminates cumulative
  traffic double-billing on `Mihomo.Start` and rapid remove/re-add traffic loss
  via two-phase `SnapshotScope` eviction, fixes Hysteria2 UDP fragmentation bounds
  & pool ownership, hardens Snell v1-v6 (`obfs_host` parity, single-pass Argon2id,
  `v6-default` prefix fast-path, salt replay filter, idle timeouts), fixes Trojan
  TLS fail-closed enforcement, VMess AEAD trial loop & `authId` replay filter,
  zero-copy dynamic speed-limit enforcement, mux session revocation, machine
  `NodeMailbox` revision clocks & `401/403` revocation, DNS-01 & custom-route SSRF
  guards, and pre-exec `xbctl` signature verification.

Panel `v1.1.64` brings the v1.1.63 Dashboard visual system uniformly across all
12 remaining admin pages (Machines, Nodes, Node Groups, Routes, Outbounds,
Certificates, Plans, Users, Templates, Risk Records, Audit Log, and System
Settings): upgrades shared `OverviewCard`, `Card`, `Table`, `Tabs`, `PageHeader`,
`EmptyState`, and `DataPagination` primitives to airy `rounded-2xl` surfaces
with soft semantic icon tiles, replaces legacy frosted/pill tab bars with
unified segmented controls, adds a 4-card KPI strip to Certificates, wraps Risk
signal distribution in a dedicated card, and integrates Audit search cleanly
inside its table card. The Agent binary and database schema are unchanged.

Panel `v1.1.63` elevates the Dashboard into a clean, modern telemetry cockpit:
airy 4-column hero KPI cards with icon badges, an interactive Recharts gradient
bar chart for node traffic distribution (`今日 / 昨日 / 近 7 天` switcher with
total sum & share tooltips), a borderless Live Host Telemetry panel with
color-coded CPU/MEM micro-bars, and synced node breakdown + 7-day top users
cards. The Agent binary and database schema are unchanged.

Panel `v1.1.62` redesigns the Dashboard into a cohesive 4-column composite KPI
strip + conditional host/agent alert banner + 2:1 cockpit layout pairing
progress-bar traffic rankings with a live Host Health Matrix and quick
shortcuts. The Agent binary and database schema are unchanged.

Panel `v1.1.61` overhauls Node Flags and External Subscriptions (backend + frontend):
- Node Flags: fixes `ip-api.com` free-tier HTTP endpoint, adds `node_flag_override_existing`
  to strip and uniformly re-render existing flags (making `TW -> CN` and `[HK]`/text styles
  100% consistent across all nodes), and redesigns the Settings UI with live preview,
  conditional collapse, and collapsible GeoIP advanced controls.
- External Subscriptions: adds native Clash/Mihomo YAML (`proxies:`) parser support
  alongside Base64/plain links, pre-sync filtering (auto-filter traffic/expiry/website info
  nodes + include/exclude regex + strip upstream flags), live "Test Fetch & Preview" before
  saving (`admin.subscription_sources.test`), and expanded node list search + status filter +
  batch enable/disable (`admin.external_nodes.batch_toggle`).
The Agent binary and database schema are unchanged.

Panel `v1.1.60` comprehensively redesigns Access & Security (backend + frontend):
- Hot-reloadable `admin_path`, `portal_enabled`, `portal_path`, and `subscribe_path`
  with zero restart required, and scopes `/settings.js` under `/{admin_path}/` to
  eliminate root-path fingerprint leaks.
- Admin TOTP 2FA (RFC 6238, AES-256-GCM encrypted secrets, replay-protected,
  two-step login prompt in `xboard-admin`).
- Trusted risk-exempt IP/CIDR whitelist (`risk_ip_whitelist`) and optional Admin
  Login IP/CIDR whitelist (`admin_ip_whitelist_enabled` + self-lockout guard +
  one-click "fill current IP").
- Per-token subscription rate limiting (`sub_rate_limit_per_min`, 429 on abuse).
- Redesigned 4-module Access & Security UI with conditional collapse, 3 risk
  presets (`宽松`/`标准`/`严格`) + collapsible 14-item advanced tuning, live URL
  preview, and direct jump to Risk Records.
The Agent binary and database schema are unchanged.

Panel `v1.1.59` adjusts the sidebar proportions (`w-60` / `w-16`, `text-sm`
nav items with `h-9` rows, larger brand mark and admin card typography) so
the left navigation feels balanced and harmonious with the main workspace.
The Agent binary and database schema are unchanged.

Panel `v1.1.58` fixes the `release changed after update confirmation` error
during instant one-click panel updates by resolving GitHub Raw branch URLs
to immutable commit-SHA URLs inside `release-verify.py` (matching the panel's
instant update checker) while preserving the original branch URL in
`/etc/rust-panel/update-base` via `RP_CONFIG_BASE` in `install-panel.sh`.
The Agent binary and database schema are unchanged.

Panel `v1.1.57` completes the Precision Minimal Tech visual alignment across
all 13 `xboard-admin` pages: replaces legacy semi-transparent frosted card
overrides with crisp high-contrast `bg-card` surfaces, redesigns `Dashboard`
(7-column dot-KPI strip + progress-bar traffic rankings) and `OverviewCard`
(top label + glowing semantic dot + monospace KPI), adds the `跟随/浅色/深色`
segmented switcher to the top command bar, adds live host count badge to the
sidebar, switches `Settings` to crisp underline tabs, and updates the default
accent to `#0284c7`. The Agent binary and database schema are unchanged.

Panel `v1.1.56` introduces a cohesive Precision Minimal Tech UI refactor across
the entire `xboard-admin` console: refined cool-slate light/dark palette and
crisp 1px hairlines, 4-domain operational navigation (`Overview` ->
`Infrastructure` -> `Users & Delivery` -> `Security & System`), sticky top
command bar with breadcrumbs and a global `Cmd/Ctrl+K` Command Palette,
unified `PageHeader` / `OverviewCard` / `Card` / `Table` primitives, and
consolidated 4-tab System Settings (`基础配置` merging site/subscribe/server,
`节点国旗`, `访问与安全`, `外观偏好`). The Agent binary and database schema
are unchanged.

Panel `v1.1.55` allows manually refreshing/syncing disabled external
subscription sources (while keeping scheduled background sync limited to
enabled sources) and changes newly imported external subscription nodes to
default to disabled (`enabled = 0`) so admins can explicitly choose which
synced nodes to expose. The Agent binary and database schema are unchanged.

Panel `v1.1.54` harmonizes the Machines Management UI with the panel's
native `PageHeader`, `OverviewCard`, frosted `Card`, and `Dialog` design
language while adding compact Agent version status in the header, clickable
overview filtering, Table/Card dual views, relative heartbeat timestamps,
offline stale-load differentiation, and an inline install script block with
one-click copy at the top of the machine detail dialog. The Agent binary and
database schema are unchanged.

Panel `v1.1.53` reverts the `v1.1.52` Machines Management UI changes so the
page stays consistent with the rest of the admin console. The Agent binary
and database schema are unchanged.

Panel `v1.1.52` redesigns the Machines Management UI (`xboard-admin`) with a
compact header and inline Agent version pill, clickable 4-metric strip,
Table & Monitoring Card dual views, inline SVG region flags, relative
heartbeat timestamps, clear offline stale-load differentiation, floating
bulk-action bar, and a right slide-over detail drawer that displays the
install script directly inline with one-click copy. The Agent binary and
database schema are unchanged.

Panel `v1.1.51` and Agent `v1.1.30` add full single-port multi-user Snell
(v1–v6) support with lock-free in-place `UpdateUsers` hot-swaps (`mihomo`
`v1.19.34-xboard.3`), Snell subscription rendering (Mihomo v1–v6, Surge v1–v6,
Stash v1–v5, URI), Create/Edit Node Snell UI in `xboard-admin`, and instant
update detection by resolving GitHub Raw commits via immutable commit SHAs
with shared panel/agent release caching. No new database migrations are
included.

Agent `v1.1.29` upgrades the embedded Mihomo core to `v1.19.34-xboard.2`
(Go 1.26 uTLS, EasyTier off-heap memory & host-packet drain with `with_easytier`
opt-in, Snell v6, Mieru `tcp-idle-timeout`, SOCKS overflow fix) and aligns
Shadowsocks multi-user config to upstream `map[string]string` while preserving
lock-free in-place `UpdateUsers` hot-swaps. The panel binary and web assets
are unchanged.

Panel `v1.1.50` completes a 20-item security and reliability hardening pass
(RP-01 through RP-20): UTF-8 safe share-link decoding and Surge/Loon/QX
template injection hardening, bounded `MemStore` nonce/throttle caches with
MySQL replay fallback, read-only `agent_download_base` protection, cross-node
device-limit snapshot aggregation and broadcast, AES-256-GCM+HKDF encryption
for certificate private keys with legacy plaintext compatibility, admin secret
redaction/preservation, deadlock-free & cycle-reset-safe traffic accounting,
atomic plan-to-user synchronization, cached `panel_config` and supervised
panic-resilient workers, IPv6 `/64` risk bucketing and isolated admin password
verification, Fail-Closed routing rules, and SS2022 persisted `server_key`
client/server parity. Migration 0025 runs automatically on startup. The web
assets and Agent are unchanged.

Panel `v1.1.39` switches management IP location lookups to iLatency. User IP
history, subscription access history and risk records use its country, region
and city fields, filtering unknown location values. Migration 0024 expires
previous management location caches automatically on startup so subsequent
reads refresh them from iLatency. Subscription node-flag providers, the web
assets and the Agent are unchanged.

Panel `v1.1.38` completes provider-name simplification for country naming
formats. Gomami Nano/SG, V.ps Gen2 variants and DMIT LAX variants become
GOMAMI, V.PS and DMIT plus country and stable duplicate numbers. Upstream
flags and raw names remain intact. Provider simplification defaults on for
existing naming rules, can be disabled per source, and respects fixed names.
Resync sources or save their naming rules to update existing display names.
The Agent is unchanged; no new migration is required.

Panel `v1.1.37` replaces alphabetical region sorting with continuous domestic
region preference across all node sources, including newly synchronized nodes.
Automatic ordering is the default; the sort editor can switch immediately to
the preserved manual order. Country naming formats remove pipe-separated
provider suffixes and avoid repeating the country suffix while preserving
upstream flags. Resync a source or save its naming rules to rename existing
nodes. No new migration is needed. The Agent is unchanged.

Panel `v1.1.36` adds per-source node naming rules with live previews, fixed
names, literal/regex replacements and country suffixes. Original flags are
preserved; flagless nodes use the existing panel flag settings. Name changes
preserve node identity, sort positions and enabled state. Source management
now matches the manual-node table layout. The sort editor can arrange all
nodes by country across sources, with subtle source labels. Migration 0023
runs automatically on startup. The Agent is unchanged.

Panel `v1.1.35` adds third-party subscription sources with a configurable
User-Agent (default `v2rayN/6.60`) and scheduled/manual synchronization. Nodes
are grouped under their subscription, with manual nodes shown separately.
Plain and Base64 link lists are supported. Failed or invalid
subscriptions preserve existing nodes; successful syncs update only their own
nodes and preserve sorting and disabled-node choices. Disabling a source also
removes its nodes from user subscriptions. Migration 0022 runs automatically
on panel startup. The Agent is unchanged.

Panel `v1.1.25` and Agent `v1.1.19` improve update recovery, enforce the requested Agent version, fix traffic reset SQL, separate authentication failures from scan scoring, add certificate pagination and configuration status, and explain protocol options. Release validation checks executable versions and web archives. support-bundle.py exports allowlisted diagnostics without credentials. No database migrations are added.

Panel `v1.1.23` and Agent `v1.1.18` fix update commands missing the target
version, recover queued updates after reconnect, and expire unacknowledged
or stalled jobs so they can be retried. Agent validation failures report a
failed status. Machine management now shows release status, confirms target
versions, prevents duplicate updates, and supports bounded bulk updates.
Update both panel and Agent. No new database migrations are included.

Panel `v1.1.22` and Agent `v1.1.16` complete advanced configuration for the
ten managed protocols using a schema generated from the bundled Mihomo core.
This includes AnyTLS reuse, mTLS, ShadowTLS, Restls, JLS, VMess MKCP/Mekya/
TLSMirror, Shadowsocks KcpTun, Hysteria2 Realm, and nested XHTTP download and
reuse options. Nested fields are validated and supported client options are
rendered in Mihomo subscriptions. Unsupported inbound Proxy Protocol is
rejected. Update both the panel and Agent to use the new server options.
No new database migrations are included.

Panel `v1.1.21` improves risk history layouts with compact score and result
columns and more room for request details. Phones and tablets display labeled
record cards with directly accessible selection and unban actions. Filters,
pagination, long request paths and IPv6 addresses adapt to narrow screens.
No new database migrations are included.

Panel `v1.1.20` adds single and bulk unban actions to risk ban history.
Administrators can select active records on the current page and release their
IP bans immediately. Releases update both persisted and live enforcement state,
preserve history, and refresh the overview. Pending writes cannot restore a
released ban, and stale history selections cannot release a newer ban for the
same IP. No new database migrations are included.

Panel `v1.1.19` refreshes the version update area and shared certificate cards
using the panel's existing theme, with responsive layouts and dark mode support.
Certificate node references are collapsed by default. Persisted results from
previous updates no longer reappear when revisiting the settings page; progress
and completion results for the current visit remain visible. No new database
migrations are included.

Panel `v1.1.18` fixes long certificate labels overflowing the batch binding
dialog, including on mobile screens. Certificate cards now group domain labels,
validity dates, expiry status, and collapsible node references, with actions in
a dedicated footer. This release introduces no additional database migrations.

Panel `v1.1.18` adds shared PEM certificate management, node references,
atomic batch binding, and automatic configuration synchronization after
certificate replacement. It supports AnyTLS, Hysteria2, TUIC, Trojan,
and ordinary TLS configurations for VLESS, VMess, SOCKS and HTTP.
Certificate validity, key matching and node SNI coverage are checked before
saving. Existing independent node certificates remain available. The embedded
database migration adds the certificates table and node certificate references.

Panel `v1.1.16` restores proxy access for administrator accounts that also
hold a subscription plan. Administrator privileges no longer remove those
users from Agent authentication, traffic accounting, expiration, or reset
processing; subscription state remains independent from panel login access.

## Security maintenance release (2026-09-08)

This release fixes user revocation synchronization, Agent report authorization,
administrator availability, concurrent traffic updates, recurring traffic
resets, batch user creation, and isolation between Agent instances sharing a
node ID. Password work is bounded and offloaded from asynchronous workers;
credential and permission changes invalidate old sessions.

The panel now runs as a dedicated unprivileged service account and rejects
unsafe production credentials. The installer restores the previous deployment
files if activation fails. Back up MySQL before upgrading: the embedded schema
migration adds session and traffic-reset columns, and file rollback does not
roll back database migrations.

## Install or update the panel

```bash
curl -fsSL https://raw.githubusercontent.com/Wangin1996/rustpanel/main/install-panel.sh | sudo bash
```

On first install, the script selects an unused random TCP port in
`20000-29999` and binds it to `127.0.0.1`. Re-running the installer preserves
the existing `APP_BIND` value.

To bind the panel to another address on first install:

```bash
curl -fsSL https://raw.githubusercontent.com/Wangin1996/rustpanel/main/install-panel.sh | sudo bash -s -- 0.0.0.0:8080
```

The panel uses one Oracle MySQL backend. MySQL 5.7.8 and newer are supported;
MySQL 8.0/8.4 is recommended. On first install, the installer prompts for the
connection details. Running it again updates the binary and Web assets while
preserving `/etc/rust-panel/panel.env`.

The panel maintains its embedded MySQL schema during normal startup. There is
no separate migration executable, command, or service. If an existing
installation still has an SQLite `DATABASE_URL`, the installer stops before
replacing installed files.

## Install an Agent

Use the node or machine installation command generated by the panel. It uses:

```bash
curl -fsSL https://raw.githubusercontent.com/Wangin1996/rustpanel/main/install-node.sh | sudo bash -s -- \
  --url "https://panel.example.com" --token "TOKEN" --machine-id 1
```

Online Agents can be upgraded from the panel's machine management page. Each
Agent release is verified with all three of these checks before activation:

- SHA-256 matches `xboard-node.sha256`.
- The executable identifies itself as `xboard-node`.
- Its embedded version exactly matches `xboard-node.version`.

## Files

| File | Purpose |
| --- | --- |
| `rust-panel` | Panel backend binary |
| `xboard-node` | Node Agent binary |
| `xboard-node.sha256` | Agent content checksum |
| `xboard-node.version` | Expected Agent release version |
| `web.tar.gz` | Admin UI and user portal |
| `install-panel.sh` | Panel installer and updater |
| `install-node.sh` | Agent installer |
| `rust-panel.service` | Panel systemd unit |
| `xboard-node.service` | Agent systemd unit |
| `nginx-panel.conf` | Optional reverse-proxy example with subscription-token log redaction |

Both binaries target Linux x86_64. Production deployments should expose the
panel through an HTTPS reverse proxy.

The Nginx example is not installed automatically. Adapt its domain, certificate
paths and upstream port before using it; existing proxy configurations are not
changed by the panel installer.

IP locations are resolved through the iLatency JSON API. Dashboard requests
return cached data immediately while missing or expired locations are refreshed
in the background, so a slow lookup does not hold up the table response.
