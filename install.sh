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

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}▶ $*${NC}"; }
success() { echo -e "${GREEN}✔ $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠ $*${NC}"; }
fatal()   { echo -e "${RED}✖ $*${NC}"; exit 1; }
prompt()  { echo -e "${BOLD}$*${NC}"; }

[[ $EUID -ne 0 ]] && fatal "Run as root or with sudo"

echo ""
INSTALLER_VERSION="v1.0.0"
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
else
    OPENCLAW_URL="http://$TS_DNS:18789"
    JENTIC_URL="http://$TS_DNS:8900"
    FILES_URL="http://$TS_DNS:8080"
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

Filebrowser has no password — it's only accessible on the Tailscale network.
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
{caddy_service}"""

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
  RESULT=$(docker exec openclaw openclaw devices approve --latest 2>&1)
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
echo "  All services are only reachable via Tailscale."
echo "  Filebrowser: no login required — Tailscale is your auth."
echo ""
