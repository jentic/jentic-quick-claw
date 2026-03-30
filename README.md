# Jentic Quick Claw

A one-command installer for OpenClaw on a VPS, equipped with Jentic Mini and File Browser, secured with Tailscale.

<!-- You get a fully-configured [OpenClaw](https://openclaw.ai) agent with a local [Jentic Mini](https://github.com/jentic/jentic-mini) instance pre-wired and ready to use — plus Mattermost for team chat, and a web-based file browser for your agent's workspace. Everything runs in Docker, everything is private to your Tailscale network. -->

You get a fully-configured [OpenClaw](https://openclaw.ai) agent with a local [Jentic Mini](https://github.com/jentic/jentic-mini) instance pre-wired and ready to use — plus a web-based file browser for your agent's workspace. Everything runs in Docker, everything is private to your Tailscale network.

## Contents

1. [What You Need Before Starting](#1-what-you-need-before-starting)
2. [Set Up Your Server](#2-set-up-your-server)
3. [Install OpenClaw on Your Server](#3-install-openclaw-on-your-server)
4. [Interact with Your OpenClaw Instance](#4-interact-with-your-openclaw-instance)
5. [Troubleshooting](#troubleshooting)

---

## 1. What You Need Before Starting

### 1.1 An AI provider API key

OpenClaw works with most major LLM providers. [Tensorix](https://tensorix.ai) is the recommended provider — ask event organisers for the registration link.

You will enter this as part of the install flow.

### 1.2 A Tailscale account

[Sign up free at tailscale.com](https://tailscale.com). The free tier supports up to 100 devices.

After signing up, do two things in the [Tailscale admin console](https://login.tailscale.com/admin/dns):
1. Enable **MagicDNS** — gives your server a stable hostname like `my-agent.tail-xxxx.ts.net`
2. Enable **HTTPS Certificates** — lets the installer get a real TLS cert for your server

Also install the Tailscale client on the device you'll use to connect:
- [macOS](https://tailscale.com/download/mac) · [Windows](https://tailscale.com/download/windows) · [iOS](https://tailscale.com/download/ios) · [Android](https://tailscale.com/download/android)

### 1.3 A Pipedream account

[Sign up at pipedream.com](https://pipedream.com). Pipedream is an Oauth broker to connect external APIs and services via SSO.

---

## 2. Set Up Your Server

You need a fresh **Ubuntu 22.04 or 24.04** server with at least **2 GB RAM** and **20 GB disk space**. Any VPS provider works.

### Recommended providers

| Provider | Recommended spec | Monthly cost |
|---|---|---|
| **[Google Compute Engine](https://console.cloud.google.com/compute/instancesAdd)** ⭐ | e2-small — 2 vCPU, 2 GB RAM | ~$13 |
| **[Hetzner](https://console.hetzner.cloud/)** | CX22 — 2 vCPU, 4 GB RAM | ~€4 |
| **[DigitalOcean](https://cloud.digitalocean.com/droplets/new)** | Basic Droplet — 2 GB RAM | ~$12 |
| **[Linode / Akamai](https://cloud.linode.com/linodes/create)** | Linode 2 GB | ~$12 |
| **[Vultr](https://my.vultr.com/deploy/)** | Cloud Compute — 2 GB RAM | ~$12 |
| **[OVHcloud](https://www.ovhcloud.com/en/vps/)** | VPS Starter — 2 GB RAM | ~€4 |
| **[AWS EC2](https://console.aws.amazon.com/ec2/v2/home#LaunchInstances:)** | t3.small — 2 GB RAM | ~$15 |

> Google Compute Engine is recommended — new users get $300 in free credits. DigitalOcean has the friendliest UI for beginners.

<details>
<summary><strong>Google Compute Engine</strong> (recommended)</summary>

1. [Create VM](https://console.cloud.google.com/compute/instancesAdd)
2. Machine: **E2 → e2-small**, Boot disk: Ubuntu 22.04 LTS (20 GB or more)
3. **Create**
4. Once the VM is running, click the **SSH** button in the console to open a web-based terminal, then run the install script (see below)

</details>

<details>
<summary><strong>Hetzner</strong></summary>

1. [Hetzner Cloud Console](https://console.hetzner.cloud/) → **New Server**
2. Image: **Ubuntu 22.04**
3. Type: **CX22** (2 vCPU, 4 GB, ~€4/mo)
4. Add your SSH key → **Create & Buy now**
5. Once the server is running, SSH in and run the install script (see below)

</details>

<details>
<summary><strong>DigitalOcean</strong></summary>

1. [Create Droplet](https://cloud.digitalocean.com/droplets/new?image=ubuntu-22-04-x64&size=s-2vcpu-4gb)
2. Add your SSH key → **Create Droplet**
3. Once the droplet is running, SSH in and run the install script (see below)

</details>

<details>
<summary><strong>Linode / Akamai</strong></summary>

1. [Create Linode](https://cloud.linode.com/linodes/create)
2. Image: Ubuntu 22.04 LTS, Plan: **Linode 2 GB**
3. Add your SSH key → **Create Linode**
4. Once the Linode is running, SSH in and run the install script (see below)

</details>

<details>
<summary><strong>Vultr</strong></summary>

1. [Deploy](https://my.vultr.com/deploy/) → Cloud Compute, Ubuntu 22.04, 2 GB plan
2. Add your SSH key → **Deploy Now**
3. Once the server is running, SSH in and run the install script (see below)

</details>

<details>
<summary><strong>AWS EC2</strong></summary>

1. [Launch Instance](https://console.aws.amazon.com/ec2/v2/home#LaunchInstances:)
2. AMI: Ubuntu Server 22.04 LTS, Instance type: **t3.small**
3. Security group: allow SSH (22) and UDP 41641 (Tailscale) from your IP
4. Add your SSH key → Launch
5. Once the instance is running, SSH in and run the install script (see below)

</details>

---

## 3. Install OpenClaw on Your Server

Once your server is running, SSH in and run:

```bash
curl -fsSL "https://raw.githubusercontent.com/jentic/jentic-quick-claw/main/install.sh" | \
  sudo LLM_BASE_URL=https://api.tensorix.ai/v1 \
       LLM_MODEL_ID=z-ai/glm-5 \
       bash
```

The script will prompt you for your **API key** — it is never pre-filled for security reasons.

> Having trouble with pairing? See [Troubleshooting: "Pairing required"](#pairing-required-in-the-control-ui-and-clicking-connect-doesnt-work).

### LLM Providers

Any OpenAI-compatible provider works. Just swap in the base URL and model ID:

| Provider | `LLM_BASE_URL` | Example `LLM_MODEL_ID` |
|---|---|---|
| Tensorix | `https://api.tensorix.ai/v1` | `z-ai/glm-5` |
| OpenAI | `https://api.openai.com/v1` | `gpt-4o` |
| Anthropic (via proxy) | your proxy URL | `claude-sonnet-4-5` |
| Local (Ollama) | `http://localhost:11434/v1` | `llama3` |

<!-- ### Option A — Interactive install (SSH)

SSH into your server as root, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/jentic/jentic-quick-claw/main/install.sh | sudo bash
```

The script prompts you for a machine name and walks you through Tailscale auth in your browser. Takes about 5–10 minutes.

--- -->

---

## What You Get

<!-- | Service | What it is |
|---|---|
| **OpenClaw** | Your personal AI agent. Chat with it via a web UI or Mattermost. Connects to any LLM (Anthropic, OpenAI, etc.). Runs 24/7. |
| **Jentic Mini** | A local API execution engine. Gives your agent access to hundreds of real-world APIs (GitHub, Slack, Stripe, Gmail, and more) without you managing credentials per-tool. |
| **Mattermost** | A self-hosted team chat server. Your agent has a bot account and is connected automatically. Chat with your agent like you would on Slack. |
| **Filebrowser** | A simple web UI to browse and edit your agent's workspace files — memory, notes, config. | -->

| Service | What it is |
|---|---|
| **OpenClaw** | Your personal AI agent. Chat with it via a web UI. Connects to any LLM (Anthropic, OpenAI, etc.). Runs 24/7. |
| **Jentic Mini** | A local API execution engine. Gives your agent access to hundreds of real-world APIs (GitHub, Slack, Stripe, Gmail, and more) without you managing credentials per-tool. |
| **Filebrowser** | A simple web UI to browse and edit your agent's workspace files — memory, notes, config. |

All services are only reachable on your **Tailscale network** (your private tailnet). Nothing is exposed to the public internet.

---

<!-- ## Install (manual / interactive)

SSH into your server as root, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/jentic/jentic-quick-claw/main/install.sh | sudo bash
```

The script will:

1. Install Docker and other dependencies
2. Add a 2GB swapfile
3. Ask you to name your machine (default: `claw-stack`)
4. Walk you through Tailscale authentication (a URL will appear — open it in your browser)
5. Request a TLS certificate automatically (requires MagicDNS + HTTPS Certificates enabled)
6. Pull all Docker images and start the stack
7. Bootstrap Mattermost — create an admin user, a bot account, and wire the token into OpenClaw
8. Lock down the firewall — only SSH and Tailscale traffic allowed in
9. Wait for you to open the auth link and approve device pairing

**Total time: ~5–10 minutes.**

At the end, you'll see something like:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✔ Stack is up and ready!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  🐾 OpenClaw:     https://claw-stack.tail-xxxx.ts.net
  ⚡ Jentic Mini:  https://claw-stack.tail-xxxx.ts.net:8900
  📁 Filebrowser:  https://claw-stack.tail-xxxx.ts.net:8080

  Click to authenticate:
  https://claw-stack.tail-xxxx.ts.net/?token=361357c19ee411f3...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

--- -->

## 4. Interact with Your OpenClaw Instance

### Step 1: Authenticate with OpenClaw

Make sure Tailscale is running on your device, then click the authentication link from the installer output. Your device is paired and you're in.

> To retrieve the token later:
> ```bash
> python3 -c "import json; print(json.load(open('/opt/claw/openclaw-config/openclaw.json'))['gateway']['auth']['token'])"
> ```

<!-- ### Step 2: Add Your AI Provider Key

Once in the OpenClaw UI, configure a model by entering your API key. Your agent will start up and introduce itself. -->

<!-- ### Step 3: Connect to Mattermost

Open Mattermost at `https://claw-stack.tail-xxxx.ts.net:8065`. Log in with the admin credentials printed at the end of the install. Your agent's bot (`@claw-agent`) is already in the `claw` team and connected to OpenClaw. -->

### Step 2: Say Hello

Send your agent an initial message to make sure everything is working:

> "Hey, are you there?"

Your agent should respond and introduce itself.

### Step 3: Complete Onboarding

Your agent will guide you through an onboarding process. Follow along to set up your preferences and get familiar with how OpenClaw works.

### Step 4: Save Tool URLs

Tell your agent to remember the URLs for the tools available in your stack:

> "Store the urls for filebrowser and jentic-mini in your workspace/TOOLS.md"

### Step 5: Install the Jentic Skill

Tell your agent:

> "Install the Jentic skill"

Or run in the OpenClaw terminal:

```
clawhub install jentic
```

When asked for a URL, enter: `http://jentic-mini:8900`

### Step 6 (Optional): Tune Agent Behaviour

If you'd like your agent to check in with you when things go wrong rather than repeatedly retrying tools, tell it:

> "Update your SOUL.md to prefer returning to me if something goes wrong, rather than repeatedly retrying tools. You should still be helpful and suggest next steps."

### Step 7: Explore the Workspace

Open Filebrowser at `https://claw-stack.tail-xxxx.ts.net:8080` to browse your agent's memory and config files. No login required — Tailscale handles authentication.

---

## Architecture

<!-- ```
Your device (Tailscale)
        │
        │  HTTPS (Tailscale cert)
        ▼
┌──────────────────────────────────┐
│  Caddy (reverse proxy)           │
│  :443  → OpenClaw                │
│  :8900 → Jentic Mini             │
│  :8080 → Filebrowser             │
│  :8065 → Mattermost              │
└──────────────┬───────────────────┘
               │ Docker network
    ┌──────────┼────────────┬──────────┐
    ▼          ▼            ▼          ▼
OpenClaw  Jentic Mini  Filebrowser  Mattermost
:18789      :8900          :80        :8065
    │                                   │
    └── workspace/ ─────────────────────┘
         (host-mounted)           Postgres
                                   :5432
``` -->

```
Your device (Tailscale)
        │
        │  HTTPS (Tailscale cert)
        ▼
┌──────────────────────────────────┐
│  Caddy (reverse proxy)           │
│  :443  → OpenClaw                │
│  :8900 → Jentic Mini             │
│  :8080 → Filebrowser             │
└──────────────┬───────────────────┘
               │ Docker network
    ┌──────────┼────────────┐
    ▼          ▼            ▼
OpenClaw  Jentic Mini  Filebrowser
:18789      :8900          :80
    │
    └── workspace/
         (host-mounted)
```

- **Firewall**: iptables DOCKER-USER chain blocks all public access to container ports. Only Tailscale traffic (`tailscale0`) and container-to-container traffic are allowed through.
- **Caddy** terminates TLS with a Tailscale-issued certificate and proxies to each service on the Docker bridge network.
<!-- - **OpenClaw** connects to Mattermost via its bot token — chat with your agent directly in Mattermost channels. -->
- The **workspace directory** (`/opt/claw/workspace`) is mounted into both OpenClaw and Filebrowser.

---

## Managing the Stack

```bash
cd /opt/claw

# View running containers
docker compose ps

# View logs
docker compose logs -f openclaw

# Restart a service
docker compose restart openclaw

# Stop / start everything
docker compose down
docker compose up -d
```

### Updating

```bash
cd /opt/claw
docker compose pull          # pull latest images for all services
docker compose up -d         # recreate updated containers
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

**Can't reach the services**
- Make sure Tailscale is running on your device: `tailscale status`
- Check containers: `cd /opt/claw && docker compose ps`

**OpenClaw keeps restarting / OOM**
```bash
swapon --show
# If empty:
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
```

**Lost the Gateway Token**
```bash
python3 -c "import json; print(json.load(open('/opt/claw/openclaw-config/openclaw.json'))['gateway']['auth']['token'])"
```

**"OpenClaw is only available over HTTPS" error in the control UI**
- Ensure **HTTPS Certificates** is enabled in the [Tailscale admin console](https://login.tailscale.com/admin/dns)
- If you enabled HTTPS after creating your VM, you may need to recreate the VM instance for the certificate to be issued correctly

**"Pairing required" in the control UI and clicking Connect doesn't work**

If auto-pairing fails and refreshing the page doesn't resolve it:
1. Press `Ctrl+C` in your terminal to stop the installer if it's still running
2. Run the following command to manually approve the device:
```bash
docker exec openclaw openclaw devices approve --latest
```
3. Refresh the control UI — you should now be connected

<!-- **Mattermost bot not responding**
```bash
docker logs mattermost
# Check the bot token is in openclaw.json:
python3 -c "import json; print(json.load(open('/opt/claw/openclaw-config/openclaw.json'))['channels']['mattermost']['token'])"
``` -->

---

## What's Next

- **Connect APIs via Jentic** — ask your agent to search Jentic for tools: Gmail, GitHub, Slack, Stripe, and more
- **Set up mobile access** — connect WhatsApp or Telegram so you can chat with your agent from your phone
- **Add skills** — browse [clawhub.com](https://clawhub.com) for community-built agent skills
- **Shape your agent** — edit `SOUL.md` and `AGENTS.md` in Filebrowser to define your agent's personality

---

## Credits

- [OpenClaw](https://openclaw.ai) — the agent runtime
- [Jentic](https://jentic.com) — the API execution layer
<!-- - [Mattermost](https://mattermost.com) — self-hosted team chat -->
- [Tailscale](https://tailscale.com) — the network security layer
- [Caddy](https://caddyserver.com) — the reverse proxy
- [Filebrowser](https://filebrowser.org) — the workspace file UI
