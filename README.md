# jentic-claw-stack

A one-command installer for a personal AI agent stack, secured by Tailscale.

You get a fully-configured [OpenClaw](https://openclaw.ai) agent with a local [Jentic Mini](https://github.com/jentic/jentic-mini) instance pre-wired and ready to use — plus a web-based file browser for your agent's workspace. Everything runs in Docker, everything is private to your Tailscale network.

---

## What You Get

| Service | What it is |
|---|---|
| **OpenClaw** | Your personal AI agent. Chat with it via a web UI. Connects to any LLM (Anthropic, OpenAI, etc.). Runs 24/7 on your server. |
| **Jentic Mini** | A local API execution engine. Gives your agent access to hundreds of real-world APIs (GitHub, Slack, Stripe, Gmail, and more) without you managing credentials per-tool. |
| **Filebrowser** | A simple web UI to browse and edit your agent's workspace files — memory, notes, config. |

All three services are only reachable on your **Tailscale network** (your private tailnet). Nothing is exposed to the public internet.

---

## What You Need Before Starting

### 1. A server

A fresh Ubuntu 22.04 or 24.04 VPS with at least **2GB RAM**. The installer adds a 2GB swapfile automatically, so a 2GB machine is the minimum.

Good options:
- [Linode/Akamai](https://linode.com) — Shared CPU 2GB (~$12/month)
- [Hetzner](https://hetzner.com) — CX22 (~€4/month, excellent value)
- [DigitalOcean](https://digitalocean.com) — Basic Droplet 2GB (~$12/month)
- [Vultr](https://vultr.com) — Regular Cloud Compute 2GB (~$12/month)

You'll need SSH root access to the machine.

### 2. A Tailscale account

[Sign up free at tailscale.com](https://tailscale.com). The free tier supports up to 100 devices — more than enough.

After signing up, do two things in the [Tailscale admin console](https://login.tailscale.com/admin/dns):
1. Enable **MagicDNS** — gives your server a stable hostname like `my-agent.tail-xxxx.ts.net`
2. Enable **HTTPS Certificates** — lets the installer get a real TLS cert for your server

### 3. An AI provider API key

OpenClaw works with most major LLM providers. You'll need one:
- [Anthropic](https://console.anthropic.com) — Claude (recommended)
- [OpenAI](https://platform.openai.com) — GPT-4 / o-series
- [Google](https://aistudio.google.com) — Gemini

You enter this in the OpenClaw web UI after the install — not during the script.

### 4. Tailscale on your laptop/phone

You need to be on the same Tailscale network as the server to access the services. Install the Tailscale client on whatever device you'll use to connect:
- [macOS](https://tailscale.com/download/mac)
- [Windows](https://tailscale.com/download/windows)
- [iOS](https://tailscale.com/download/ios)
- [Android](https://tailscale.com/download/android)

Sign in with the same Tailscale account you used above.

---

## Install

SSH into your server as root, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/jentic/jentic-quick-claw/main/install.sh | sudo bash
```

The script will:

1. Install Docker, UFW, and other dependencies
2. Add a 2GB swapfile
3. Ask you to name your machine (default: `claw-stack`)
4. Walk you through Tailscale authentication (a URL will appear — open it in your browser)
5. Ask if you've enabled MagicDNS + HTTPS in the Tailscale admin (if yes, it gets a TLS cert automatically)
6. Clone and build Jentic Mini from source
7. Pull the OpenClaw Docker image
8. Write all config files and start the stack
9. Lock down the firewall — only SSH and Tailscale traffic allowed in

**Total time: ~5–10 minutes** (most of it is the Jentic Mini Docker build).

At the end, you'll see something like:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✔ Stack is up and ready!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  🐾 OpenClaw:     https://claw-stack.tail-xxxx.ts.net
  ⚡ Jentic Mini:  https://claw-stack.tail-xxxx.ts.net:8900
  📁 Filebrowser:  https://claw-stack.tail-xxxx.ts.net:8080

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  GATEWAY TOKEN (enter this in the OpenClaw web UI):

  361357c19ee411f34a2578893cdb85784244b810e0f0c00b
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Copy the Gateway Token** — you'll need it in the next step.

---

## First-Time Setup

### Step 1: Connect to OpenClaw

Make sure your Tailscale client is running on your device, then open the OpenClaw URL in your browser (e.g. `https://claw-stack.tail-xxxx.ts.net`).

You'll be prompted for the **Gateway Token** — paste the one from the installer output above.

> If you lose the token, you can retrieve it at any time:
> ```bash
> python3 -c "import json; print(json.load(open('/opt/claw/openclaw-config/openclaw.json'))['gateway']['auth']['token'])"
> ```

### Step 2: Add Your AI Provider Key

Once in the OpenClaw UI, you'll be prompted to configure a model. Enter your API key for your chosen provider (Anthropic, OpenAI, etc.).

Your agent will start up for the first time. Because a `BOOTSTRAP.md` was pre-written to the workspace during install, your agent already knows:
- Its Jentic Mini is at `http://jentic-mini:8900`
- The public URLs for all services
- What to do first

### Step 3: Install the Jentic Skill

Your agent will guide you through this, but if you want to do it manually, tell your agent:

> "Install the Jentic skill"

Or run in the OpenClaw terminal:

```
clawhub install jentic
```

When asked for a URL, enter: `http://jentic-mini:8900`

Your API key will be issued automatically — Jentic Mini trusts traffic from the Docker network.

### Step 4: Explore the Workspace

Open Filebrowser at `https://claw-stack.tail-xxxx.ts.net:8080` to see your agent's workspace. No login required — Tailscale handles authentication.

From here you can view memory files, edit config, and watch what your agent is up to.

---

## Architecture

```
Your device (Tailscale)
        │
        │  HTTPS (Tailscale cert)
        ▼
┌──────────────────────────────┐
│  Caddy (reverse proxy)       │
│  :443  → OpenClaw            │
│  :8900 → Jentic Mini         │
│  :8080 → Filebrowser         │
└──────────────┬───────────────┘
               │ Docker network
    ┌──────────┼────────────┐
    ▼          ▼            ▼
OpenClaw  Jentic Mini  Filebrowser
:18789      :8900          :80
    │
    └── workspace/ (host-mounted)
         also mounted into Filebrowser
```

- **UFW** blocks all public inbound traffic except SSH. Tailscale traffic arrives on `tailscale0` and is allowed through before the deny rules fire.
- **Caddy** terminates TLS using a Tailscale-issued certificate and proxies to each service internally.
- **OpenClaw** and **Jentic Mini** communicate over the Docker bridge network — no external traffic.
- The **workspace directory** (`/opt/claw/workspace`) is mounted into both OpenClaw (as the agent's workspace) and Filebrowser (as the browseable root).

---

## Managing the Stack

All compose files live at `/opt/claw/docker-compose.yml`.

```bash
# View running containers
cd /opt/claw && docker compose ps

# View logs
docker compose logs -f openclaw
docker compose logs -f jentic-mini

# Restart a service
docker compose restart openclaw

# Stop everything
docker compose down

# Start everything
docker compose up -d
```

### Updating OpenClaw

```bash
cd /opt/claw
docker compose pull openclaw
docker compose up -d openclaw
```

### Updating Jentic Mini

```bash
cd /opt/claw/jentic-mini
git pull
docker build -t jentic-mini:latest .
cd /opt/claw
docker compose up -d jentic-mini
```

### Renewing TLS Certificates

Tailscale certificates are valid for ~90 days. To renew:

```bash
TS_DNS=$(tailscale status --json | python3 -c "import json,sys; print(json.load(sys.stdin)['Self']['DNSName'].rstrip('.'))")
tailscale cert --cert-file /opt/claw/certs/cert.pem --key-file /opt/claw/certs/key.pem "$TS_DNS"
docker compose restart caddy
```

---

## Troubleshooting

### Can't reach the services

- Make sure Tailscale is running on your device: `tailscale status`
- Make sure the server is on your tailnet: `tailscale status` should show the server
- Check that the containers are running: `cd /opt/claw && docker compose ps`

### OpenClaw keeps restarting / OOM

If you're on a 2GB machine and the swapfile wasn't created properly:

```bash
swapon --show
# If empty:
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
```

### Lost the Gateway Token

```bash
python3 -c "import json; print(json.load(open('/opt/claw/openclaw-config/openclaw.json'))['gateway']['auth']['token'])"
```

### Jentic Mini not responding

```bash
docker logs jentic-mini
# Check JENTIC_TRUSTED_SUBNETS includes your Tailscale CGNAT range (100.64.0.0/10)
```

---

## What's Next

Once your agent is running, explore what it can do:

- **Connect APIs via Jentic** — ask your agent to search Jentic for tools you need: Gmail, GitHub, Slack, Stripe, and more
- **Set up messaging** — connect WhatsApp or Telegram so you can chat with your agent from your phone
- **Add skills** — browse [clawhub.com](https://clawhub.com) for community-built agent skills
- **Explore the workspace** — check `SOUL.md` and `AGENTS.md` to shape your agent's personality and behaviour

---

## Credits

- [OpenClaw](https://openclaw.ai) — the agent runtime
- [Jentic](https://jentic.com) — the API execution layer
- [Tailscale](https://tailscale.com) — the network security layer
- [Caddy](https://caddyserver.com) — the reverse proxy
- [Filebrowser](https://filebrowser.org) — the workspace file UI
