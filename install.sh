#!/usr/bin/env bash
# install.sh — One-shot setup for OpenClaw + Jentic Mini + Filebrowser on Ubuntu 24.04
# Secured via Tailscale — services only accessible on the tailnet.
# TLS via Tailscale HTTPS certificates + Caddy reverse proxy.
#
# Usage: bash install.sh
#
# Requirements: Ubuntu 22.04 or 24.04, root, 2GB+ RAM (swap added automatically)

set -euo pipefail

CLAW_BASE="/opt/claw"
WORKSPACE_DIR="$CLAW_BASE/workspace"
JENTIC_DATA_DIR="$CLAW_BASE/jentic-data"
JENTIC_SRC_DIR="$CLAW_BASE/jentic-mini"
FB_DB_DIR="$CLAW_BASE/filebrowser-db"
OPENCLAW_CONFIG_DIR="$CLAW_BASE/openclaw-config"
CERTS_DIR="$CLAW_BASE/certs"

OPENCLAW_IMAGE="ghcr.io/openclaw/openclaw:latest"
JENTIC_MINI_IMAGE="ghcr.io/jentic/jentic-mini:latest"
USE_HTTPS=false  # set early; overridden in TLS step
MM_ADMIN_PASS=""
MM_DB_PASS=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}▶ $*${NC}"; }
success() { echo -e "${GREEN}✔ $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠ $*${NC}"; }
fatal()   { echo -e "${RED}✖ $*${NC}"; exit 1; }
prompt()  { echo -e "${BOLD}$*${NC}"; }

[[ $EUID -ne 0 ]] && fatal "Run as root or with sudo"

echo ""
INSTALLER_VERSION="v1.0.2"
echo "╔══════════════════════════════════════════════════════╗"
echo "║     OpenClaw + Jentic Mini — Stack Installer         ║"
echo "║                    $INSTALLER_VERSION                          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Step 1: System packages ───────────────────────────────────────────────────
info "Installing system packages..."
apt-get update
apt-get install -y curl git ca-certificates gnupg lsb-release python3
success "Packages ready"

# ── Step 2: Docker ────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    info "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    success "Docker installed"
else
    success "Docker already present: $(docker --version)"
fi

# ── Step 3: Tailscale ─────────────────────────────────────────────────────────
if ! command -v tailscale &>/dev/null; then
    info "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled
    success "Tailscale installed"
else
    success "Tailscale already present"
fi

# ── Step 4: Swap ──────────────────────────────────────────────────────────────
if ! swapon --show | grep -q /swapfile; then
    info "Adding 2GB swapfile (OpenClaw needs headroom)..."
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    success "Swap active ($(free -h | awk '/Swap/{print $2}') total)"
else
    success "Swap already configured"
fi

# ── Step 5: Hostname ──────────────────────────────────────────────────────────
echo ""
prompt "What should this machine be called on your Tailscale network?"
prompt "Press Enter to use the default: claw-stack"
CLAW_HOSTNAME_INPUT=""
read -r -p "Hostname: " CLAW_HOSTNAME_INPUT < /dev/tty || true
CLAW_HOSTNAME="${CLAW_HOSTNAME_INPUT:-claw-stack}"
hostnamectl set-hostname "$CLAW_HOSTNAME"
success "Hostname set to: $CLAW_HOSTNAME"

# ── Step 5b: LLM API key ──────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  LLM CONFIGURATION"
echo ""
echo "  Your agent needs an LLM to think. If you have a"
echo "  Tensorix.ai account, paste your API key below."
echo "  (Leave blank to configure manually after setup.)"
echo ""
echo "  Get a key + \$50 free credits at: https://tensorix.ai"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TENSORIX_API_KEY=""
read -r -p "Tensorix API key (tx_...): " TENSORIX_API_KEY < /dev/tty || true
if [[ -n "$TENSORIX_API_KEY" ]]; then
    success "Tensorix API key saved — will configure after stack starts."
else
    warn "No API key entered — you can configure your LLM in the OpenClaw UI after setup."
fi

# Generate MM credentials (needed later in docker-compose + bootstrap)
MM_ADMIN_PASS=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
MM_DB_PASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)

# ── Step 6: Tailscale auth ────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TAILSCALE AUTHENTICATION"
echo ""
echo "  A URL will appear below. Open it in any browser"
echo "  signed into your Tailscale account to approve this machine."
echo ""
echo "  No Tailscale account? Sign up free at https://tailscale.com"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
tailscale up --accept-dns=false --hostname="$CLAW_HOSTNAME"

TS_IP=$(tailscale ip -4 2>/dev/null || true)
[[ -z "$TS_IP" ]] && fatal "Tailscale connected but no IP assigned — run 'tailscale status' to debug"
tailscale set --hostname="$CLAW_HOSTNAME"
success "Tailscale IP: $TS_IP  hostname: $CLAW_HOSTNAME"

# Get the full Tailscale DNS name (e.g. claw-stack.tail1234.ts.net)
TS_DNS=$(tailscale status --json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
name=d.get('Self',{}).get('DNSName','')
print(name.rstrip('.'))
" 2>/dev/null || echo "")
[[ -z "$TS_DNS" ]] && TS_DNS="$TS_IP"
info "Tailscale DNS name: $TS_DNS"

# ── Step 7: TLS certificates (auto) ──────────────────────────────────────────
# Tailscale provides free TLS certs for .ts.net names — try automatically.
# Requires MagicDNS + HTTPS Certificates enabled in Tailscale admin.
# Falls back to HTTP if cert isn't available yet (e.g. feature not enabled).
info "Requesting Tailscale TLS certificate for $TS_DNS ..."
mkdir -p "$CERTS_DIR"
if tailscale cert --cert-file "$CERTS_DIR/cert.pem" --key-file "$CERTS_DIR/key.pem" "$TS_DNS" 2>/dev/null; then
    success "TLS certificate issued for $TS_DNS"
    USE_HTTPS=true
else
    warn "Could not get TLS cert — falling back to HTTP (still Tailscale-protected)."
    warn "To enable HTTPS later: turn on MagicDNS + HTTPS Certificates at https://login.tailscale.com/admin/dns"
fi

# ── Step 8: Directories ───────────────────────────────────────────────────────
info "Creating directories..."
mkdir -p "$WORKSPACE_DIR" "$JENTIC_DATA_DIR" "$FB_DB_DIR" "$OPENCLAW_CONFIG_DIR" "$CERTS_DIR"
mkdir -p "$CLAW_BASE/postgres-data" "$CLAW_BASE/mattermost-data" "$CLAW_BASE/mattermost-logs" "$CLAW_BASE/mattermost-config" "$CLAW_BASE/mattermost-plugins"
chmod 777 "$FB_DB_DIR"
chmod 777 "$JENTIC_DATA_DIR"   # jentic user (uid 999) must write the DB
chown -R 1000:1000 "$WORKSPACE_DIR" "$OPENCLAW_CONFIG_DIR"
success "Directories ready"

# ── Step 9: Pull Jentic Mini ──────────────────────────────────────────────────
info "Pulling Jentic Mini image..."
docker pull "$JENTIC_MINI_IMAGE"
docker tag "$JENTIC_MINI_IMAGE" jentic-mini:latest
success "Jentic Mini image ready"

# ── Step 10: Pull OpenClaw ────────────────────────────────────────────────────
info "Pulling OpenClaw image..."
docker pull "$OPENCLAW_IMAGE"
success "OpenClaw image ready"

# ── Step 11: Write OpenClaw config ────────────────────────────────────────────
info "Writing OpenClaw config..."
python3 - <<PYEOF
import json, os
cfg_path = '$OPENCLAW_CONFIG_DIR/openclaw.json'
cfg = {}
if os.path.exists(cfg_path):
    try:
        cfg = json.load(open(cfg_path))
    except Exception:
        pass
# Gateway: listen on all interfaces, allow Tailscale origins
cfg.setdefault('gateway', {})['bind'] = 'lan'
ts_dns = '${TS_DNS}'
allowed = cfg['gateway'].setdefault('controlUi', {}).setdefault('allowedOrigins', [
    'http://localhost:18789', 'http://127.0.0.1:18789'
])
if ts_dns:
    for origin in [f'https://{ts_dns}', f'http://{ts_dns}:18789']:
        if origin not in allowed:
            allowed.append(origin)
json.dump(cfg, open(cfg_path, 'w'), indent=4)
print('OpenClaw config written')
PYEOF
chown 1000:1000 "$OPENCLAW_CONFIG_DIR/openclaw.json"

# ── Step 12: Write BOOTSTRAP.md ───────────────────────────────────────────────
info "Writing BOOTSTRAP.md for the agent..."

if [[ "$USE_HTTPS" == "true" ]]; then
    OPENCLAW_URL="https://$TS_DNS"
    JENTIC_URL="https://$TS_DNS:8900"
    FILES_URL="https://$TS_DNS:8080"
    MATTERMOST_URL="https://$TS_DNS:8065"
else
    OPENCLAW_URL="http://$TS_DNS:18789"
    JENTIC_URL="http://$TS_DNS:8900"
    FILES_URL="http://$TS_DNS:8080"
    MATTERMOST_URL="http://$TS_IP:8065"
fi

cat > "$WORKSPACE_DIR/BOOTSTRAP.md" <<BOOTSTRAP
# BOOTSTRAP.md — Hello, World

You just came online on a fresh OpenClaw + Jentic Mini stack. Here's what you need to know.

## Your Environment

You're running on a Tailscale-secured server. Three services are available:

| Service      | Internal URL              | Web URL (Tailscale only)  |
|-------------|---------------------------|---------------------------|
| You (OpenClaw) | —                       | $OPENCLAW_URL             |
| Jentic Mini  | http://jentic-mini:8900   | $JENTIC_URL               |
| Filebrowser  | http://filebrowser:80     | $FILES_URL                |
| Mattermost   | http://mattermost:8065    | $MATTERMOST_URL           |

Filebrowser has no password — it's only accessible on the Tailscale network.

## Mattermost (Chat)

Your Mattermost server is pre-configured and running. You have a bot account there.
URL: $MATTERMOST_URL
Your Mattermost bot token is already wired into your OpenClaw config.
The admin credentials are printed at the end of the install script output.
Use it to browse and edit your workspace files.

## First Thing: Set Up Jentic

Your local Jentic Mini is already pre-configured at \`http://jentic-mini:8900\`.
It gives you access to hundreds of APIs without managing credentials yourself.

Run this to install the Jentic skill:

\`\`\`
clawhub install jentic
\`\`\`

When it asks for a URL, use: \`http://jentic-mini:8900\`

Your API key will be issued automatically — Jentic Mini trusts your network.

## Introduce Yourself

You're a fresh agent. Start a conversation with your user:

> "Hey, I just came online. What should I call you? What are we working on?"

Figure out together:
1. Your name and personality
2. What they want to accomplish
3. Any tools or integrations they need beyond Jentic

## After Setup

Update \`IDENTITY.md\`, \`USER.md\`, and \`SOUL.md\` with what you learn.

Then **delete this file** — you don't need a bootstrap script once you know who you are.

---

*Powered by Jentic Mini. Make it count.*
BOOTSTRAP

chown 1000:1000 "$WORKSPACE_DIR/BOOTSTRAP.md"
success "BOOTSTRAP.md written"

# ── Step 13: Write docker-compose.yml ────────────────────────────────────────
info "Writing docker-compose.yml..."

python3 - <<PYEOF
use_https = '${USE_HTTPS}' == 'true'
ts_ip = '${TS_IP}'
ts_dns = '${TS_DNS}'
certs_dir = '${CERTS_DIR}'
jentic_public_hostname = '${JENTIC_URL}'
claw_base = '${CLAW_BASE}'
mm_db_pass = '${MM_DB_PASS}'
mm_site_url = ('https://${TS_DNS}:8065' if '${USE_HTTPS}' == 'true' else 'http://${TS_IP}:8065')
mm_ports = '    expose:\n      - "8065"' if '${USE_HTTPS}' == 'true' else '    ports:\n      - "8065:8065"'

if use_https:
    openclaw_ports = '    expose:\n      - "18789"'
    jentic_ports   = '    expose:\n      - "8900"'
    fb_ports       = '    expose:\n      - "80"'
    caddy_service = f"""
  caddy:
    image: caddy:alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "443:443"
      - "8900:8900"
      - "8080:8080"
      - "8065:8065"
    volumes:
      - {certs_dir}:/certs:ro
      - {claw_base}/Caddyfile:/etc/caddy/Caddyfile:ro
    depends_on:
      - openclaw
      - jentic-mini
      - filebrowser
"""
else:
    openclaw_ports = '    ports:\n      - "18789:18789"'
    jentic_ports   = '    ports:\n      - "8900:8900"'
    fb_ports       = '    ports:\n      - "8080:80"'
    caddy_service  = ''

compose = f"""services:

  openclaw:
    image: ghcr.io/openclaw/openclaw:latest
    container_name: openclaw
    restart: unless-stopped
{openclaw_ports}
    volumes:
      - {claw_base}/openclaw-config:/home/node/.openclaw
      - {claw_base}/workspace:/home/node/.openclaw/workspace
    environment:
      NODE_ENV: production

  jentic-mini:
    image: jentic-mini:latest
    container_name: jentic-mini
    restart: unless-stopped
{jentic_ports}
    volumes:
      - {claw_base}/jentic-data:/app/data
    environment:
      JENTIC_PUBLIC_HOSTNAME: "{jentic_public_hostname}"
      JENTIC_TRUSTED_SUBNETS: "100.64.0.0/10,172.16.0.0/12"
      LOG_LEVEL: info

  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: filebrowser
    restart: unless-stopped
{fb_ports}
    volumes:
      - {claw_base}/workspace:/srv
      - {claw_base}/filebrowser-db:/database
    command: --database /database/filebrowser.db --noauth
{caddy_service}
  postgres:
    image: postgres:15-alpine
    container_name: postgres
    restart: unless-stopped
    expose:
      - "5432"
    volumes:
      - {claw_base}/postgres-data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: mattermost
      POSTGRES_USER: mattermost
      POSTGRES_PASSWORD: "{mm_db_pass}"

  mattermost:
    image: mattermost/mattermost-team-edition:latest
    container_name: mattermost
    restart: unless-stopped
{mm_ports}
    volumes:
      - {claw_base}/mattermost-data:/mattermost/data
      - {claw_base}/mattermost-logs:/mattermost/logs
      - {claw_base}/mattermost-config:/mattermost/config
      - {claw_base}/mattermost-plugins:/mattermost/plugins
    environment:
      MM_SQLSETTINGS_DRIVERNAME: postgres
      MM_SQLSETTINGS_DATASOURCE: "postgres://mattermost:{mm_db_pass}@postgres:5432/mattermost?sslmode=disable&connect_timeout=10"
      MM_SERVICESETTINGS_SITEURL: "{mm_site_url}"
      MM_SERVICESETTINGS_ENABLELOCALMODE: "true"
    depends_on:
      - postgres
"""

open(f'{claw_base}/docker-compose.yml', 'w').write(compose)
print('docker-compose.yml written')
PYEOF

# ── Step 14: Write Caddyfile (HTTPS only) ────────────────────────────────────
if [[ "$USE_HTTPS" == "true" ]]; then
    info "Writing Caddyfile..."
    python3 - <<PYEOF
ts_dns = '${TS_DNS}'
certs_dir = '${CERTS_DIR}'
claw_base = '${CLAW_BASE}'

caddyfile = f"""{{
    auto_https off
}}

https://{ts_dns} {{
    tls /certs/cert.pem /certs/key.pem
    reverse_proxy openclaw:18789
}}

https://{ts_dns}:8900 {{
    tls /certs/cert.pem /certs/key.pem
    reverse_proxy jentic-mini:8900
}}

https://{ts_dns}:8080 {{
    tls /certs/cert.pem /certs/key.pem
    reverse_proxy filebrowser:80
}}

https://{ts_dns}:8065 {{
    tls /certs/cert.pem /certs/key.pem
    reverse_proxy mattermost:8065
}}
"""
open(f'{claw_base}/Caddyfile', 'w').write(caddyfile)
print('Caddyfile written')
PYEOF
fi

# ── Step 15: Firewall ─────────────────────────────────────────────────────────
# NOTE: UFW alone is NOT sufficient on Docker hosts.
# Docker writes DNAT rules directly into iptables nat PREROUTING, which fires
# *before* UFW and bypasses its rules entirely. We use two layers:
#   1. iptables DOCKER-USER chain — blocks public internet from reaching containers
#   2. iptables INPUT chain rules — blocks non-SSH, non-Tailscale host traffic
# Both are saved via iptables-persistent and restored on every boot (before Docker starts).

info "Configuring firewall (iptables-persistent + DOCKER-USER)..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables-persistent

# Layer 1: Block public internet from Docker-published container ports
# DOCKER-USER is evaluated in FORWARD before Docker's own ACCEPT rules
iptables -F DOCKER-USER 2>/dev/null || true
iptables -A DOCKER-USER -i tailscale0 -j ACCEPT   # Tailscale traffic in
iptables -A DOCKER-USER -i docker0    -j ACCEPT   # Container-to-container (default bridge)
iptables -A DOCKER-USER -i br+        -j ACCEPT   # Container-to-container (custom bridges)
iptables -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A DOCKER-USER -j DROP                   # Drop everything else

# Layer 2: Host INPUT — allow SSH + Tailscale, drop the rest
# Flush any prior rules first, then set a DROP default
iptables -F INPUT 2>/dev/null || true
iptables -P INPUT DROP
iptables -A INPUT -i lo -j ACCEPT                                          # Loopback
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT    # Return traffic
iptables -A INPUT -i tailscale0 -j ACCEPT                                 # All Tailscale
iptables -A INPUT -p tcp --dport 22 -j ACCEPT                             # SSH (management)
iptables -A INPUT -p udp --dport 41641 -j ACCEPT                          # Tailscale WireGuard

# Save — netfilter-persistent restores on boot before Docker starts
netfilter-persistent save
success "Firewall configured — SSH + Tailscale only (Docker bypass closed)"

# ── Step 16: Start the stack ──────────────────────────────────────────────────
info "Starting stack..."
cd "$CLAW_BASE"
docker compose up -d
success "Stack started"

# ── Step 16.5: Bootstrap Mattermost ──────────────────────────────────────────
echo ""
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │  Waiting for Mattermost (first boot runs DB migrations) │"
echo "  │  This takes 2–4 min on small servers — totally normal.  │"
echo "  └─────────────────────────────────────────────────────────┘"
MM_INTERNAL="http://127.0.0.1:8065"
MM_WAIT_SECS=0
MM_READY=false
while [[ $MM_WAIT_SECS -lt 300 ]]; do
    STATUS=$(curl -sf http://127.0.0.1:8065/api/v4/system/ping 2>/dev/null || true)
    if echo "$STATUS" | grep -q "OK\|ok\|status"; then
        MM_READY=true
        break
    fi
    sleep 5
    MM_WAIT_SECS=$((MM_WAIT_SECS + 5))
    # Print a progress line every 15 seconds with elapsed time + last log line
    if (( MM_WAIT_SECS % 15 == 0 )); then
        LAST_LOG=$(docker logs --tail=1 mattermost 2>&1 | tr -d "\r\n" | cut -c1-80 || true)
        printf "  ⏳ %ds elapsed — %s\n" "$MM_WAIT_SECS" "$LAST_LOG"
    fi
done
if [[ "$MM_READY" != "true" ]]; then
    warn "Mattermost did not start within 5 minutes — skipping bot bootstrap."
    warn "Run 'docker logs mattermost' to diagnose. You can run the bootstrap manually later."
fi

info "Bootstrapping Mattermost (creating admin + bot)..."
MM_BOT_TOKEN=$(python3 - <<MMEOF
import urllib.request, urllib.error, json, sys, time

base = "http://127.0.0.1:8065/api/v4"

def api(method, path, data=None, token=None):
    """Call Mattermost API; returns parsed JSON dict (or {} on empty body)."""
    url = base + path
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            raw = r.read()
            return json.loads(raw) if raw.strip() else {}
    except urllib.error.HTTPError as e:
        raw = e.read()
        # Empty body on error (e.g. 503 while still starting) — return status only
        if not raw.strip():
            return {"_http_status": e.code}
        try:
            return json.loads(raw)
        except Exception:
            return {"_http_status": e.code, "_body": raw.decode(errors="replace")}

def mm_login(username, password):
    """Log in; returns (user_dict, token_str).
    Mattermost returns the session token in the 'Token' response header,
    NOT in the JSON body — this is why api() can't be used for login."""
    data = json.dumps({"login_id": username, "password": password}).encode()
    req = urllib.request.Request(base + "/users/login", data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            tok = r.headers.get("Token", "")
            raw = r.read()
            user = json.loads(raw) if raw.strip() else {}
            return user, tok
    except urllib.error.HTTPError as e:
        return {}, ""

# Wait for MM to be fully ready (up to 3 min)
ready = False
for _ in range(60):
    try:
        result = api("GET", "/system/ping")
        if result.get("status") == "OK" or result.get("status") == "ok":
            ready = True
            break
    except Exception:
        pass
    time.sleep(3)

if not ready:
    sys.stderr.write("Mattermost did not become ready in time\n")
    print("")
    sys.exit(0)

# Create admin user (first registered user becomes system admin automatically)
admin = api("POST", "/users", {
    "email": "admin@claw.local",
    "username": "admin",
    "password": "${MM_ADMIN_PASS}",
    "first_name": "Admin",
    "last_name": ""
})

# Log in — captures the Token header correctly
user, token = mm_login("admin", "${MM_ADMIN_PASS}")

if not token:
    sys.stderr.write("Login failed — could not obtain session token\n")
    print("")
    sys.exit(0)

admin_id = user.get("id", "")

# Enable personal access tokens and bot account creation
api("PUT", "/config/patch", {
    "ServiceSettings": {
        "EnableUserAccessTokens": True,
        "EnableBotAccountCreation": True
    }
}, token)

# Create a team
team = api("POST", "/teams", {
    "name": "claw",
    "display_name": "Claw",
    "type": "O"
}, token)
team_id = team.get("id", "")

# Add admin to team
if team_id and admin_id:
    api("POST", f"/teams/{team_id}/members", {
        "team_id": team_id,
        "user_id": admin_id
    }, token)

# Create bot account
bot = api("POST", "/bots", {
    "username": "claw-agent",
    "display_name": "Claw Agent",
    "description": "Your OpenClaw AI agent"
}, token)
bot_user_id = bot.get("user_id", "")

# Add bot to team
if team_id and bot_user_id:
    api("POST", f"/teams/{team_id}/members", {
        "team_id": team_id,
        "user_id": bot_user_id
    }, token)

# Generate personal access token for the bot
if bot_user_id:
    pat = api("POST", f"/users/{bot_user_id}/tokens", {
        "description": "OpenClaw agent token"
    }, token)
    bot_token = pat.get("token", "")
    if bot_token:
        print(bot_token)
    else:
        sys.stderr.write(f"PAT creation returned: {pat}\n")
        print("")
else:
    sys.stderr.write(f"Bot creation returned: {bot}\n")
    print("")
MMEOF
)

if [[ -n "$MM_BOT_TOKEN" ]]; then
    success "Mattermost bootstrapped — bot token acquired"
    # Write Mattermost channel config into openclaw.json
    python3 - <<PYEOF
import json, os
cfg_path = '${OPENCLAW_CONFIG_DIR}/openclaw.json'
cfg = json.load(open(cfg_path))
cfg.setdefault('channels', {})['mattermost'] = {
    "provider": "mattermost",
    "baseUrl": "http://mattermost:8065",
    "token": "${MM_BOT_TOKEN}",
    "groupPolicy": "open",
    "chatmode": "onmessage"
}
json.dump(cfg, open(cfg_path, 'w'), indent=4)
print('Mattermost channel config written to openclaw.json')
PYEOF
    chown 1000:1000 "$OPENCLAW_CONFIG_DIR/openclaw.json"
    # Restart OpenClaw so it picks up the new channel config
    docker restart openclaw
    success "OpenClaw restarted with Mattermost config"
else
    warn "Mattermost bootstrap incomplete — bot token not obtained. Set up manually."
fi

# ── Step 16.7: Seed workspace defaults ───────────────────────────────────────
info "Seeding workspace defaults (SOUL.md, AGENTS.md, TOOLS.md, USER.md...)..."
docker exec openclaw openclaw setup --non-interactive --workspace /root/.openclaw/workspace 2>&1 \
    | grep -v "^$" | sed 's/^/  /' || true
success "Workspace files seeded"

# ── Step 16.8: Configure LLM (Tensorix) ──────────────────────────────────────
if [[ -n "$TENSORIX_API_KEY" ]]; then
    info "Configuring Tensorix LLM..."
    docker exec \
        -e TENSORIX_API_KEY="$TENSORIX_API_KEY" \
        openclaw \
        openclaw onboard \
            --non-interactive \
            --auth-choice custom-api-key \
            --custom-base-url "https://api.tensorix.ai/v1" \
            --custom-api-key "$TENSORIX_API_KEY" \
            --custom-model-id "z-ai/glm-4.7" \
            --custom-compatibility openai \
            --accept-risk \
            --skip-channels \
            --skip-daemon \
            --skip-skills \
            --skip-search \
            --skip-ui 2>&1 \
        | grep -v "^$" | sed 's/^/  /' || true
    success "LLM configured: Tensorix / z-ai/glm-4.7"
fi

# ── Step 17: Retrieve Gateway Token ──────────────────────────────────────────
info "Waiting for OpenClaw to generate gateway token..."
GATEWAY_TOKEN=""
for i in $(seq 1 30); do
    GATEWAY_TOKEN=$(python3 -c "
import json, sys
try:
    cfg = json.load(open('$OPENCLAW_CONFIG_DIR/openclaw.json'))
    t = cfg.get('gateway', {}).get('auth', {}).get('token', '')
    print(t)
except:
    pass
" 2>/dev/null || true)
    [[ -n "$GATEWAY_TOKEN" ]] && break
    sleep 2
done

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}${BOLD}  ✔ Stack is up and ready!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "  ${YELLOW}${BOLD}⚠️  Before clicking these links, make sure your computer${NC}"
echo -e "  ${YELLOW}${BOLD}   is connected to your Tailscale network!${NC}"
echo ""
echo -e "  🐾 OpenClaw:     ${CYAN}$OPENCLAW_URL${NC}"
echo -e "  ⚡ Jentic Mini:  ${CYAN}$JENTIC_URL${NC}"
echo -e "  📁 Filebrowser:  ${CYAN}$FILES_URL${NC}"
echo -e "  💬 Mattermost:   ${CYAN}$MATTERMOST_URL${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ -n "$GATEWAY_TOKEN" ]]; then
echo -e "${YELLOW}${BOLD}  Click to authenticate:${NC}"
echo ""
echo -e "  ${CYAN}${BOLD}$OPENCLAW_URL/?token=$GATEWAY_TOKEN${NC}"
else
echo -e "${YELLOW}  Gateway token not ready yet. Run this to get it:${NC}"
echo "  python3 -c \"import json; print(json.load(open('$OPENCLAW_CONFIG_DIR/openclaw.json'))['gateway']['auth']['token'])\""
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo ""
echo "  Mattermost credentials:"
echo "    Username: admin"
echo "    Password: $MM_ADMIN_PASS"
echo ""
echo "  All services are only reachable via Tailscale."
echo "  Filebrowser: no login required — Tailscale is your auth."
echo ""

# ── Step 18: Wait for device pairing ─────────────────────────────────────────
# Block here so the user can see their device get approved before the script exits.
# No timeout — waits as long as needed.
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${YELLOW}${BOLD}  Waiting for device pairing...${NC}"
echo ""
echo "  Click the authentication link above, then open the OpenClaw"
echo "  dashboard. Once it loads, your device will be paired"
echo "  automatically and this script will complete."
echo ""
while true; do
  RESULT=$(docker exec openclaw openclaw devices approve --latest 2>&1) || true
  if echo "$RESULT" | grep -qi "approved\|success"; then
    break
  fi
  sleep 2
done
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}${BOLD}  ✔ Device paired! Setup complete.${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
