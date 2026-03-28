# dev-setup

Bootstraps a fresh Ubuntu container on TrueNAS into a full Node.js dev environment in a single script.

## What gets installed

- System packages & full system update
- OpenSSH (key-only auth)
- GitHub CLI (`gh`) with interactive browser auth
- Node.js LTS via nvm
- Tailscale (VPN)
- Cloudflared (tunnel, runs as system service)
- MongoDB 8 (runs as system service)
- [`pdsykes2512/clean-prototype`](https://github.com/pdsykes2512/clean-prototype) cloned and scaffolded
- Claude Code CLI
- `.env.local` with MongoDB connection details
- `next.config` patched to allow Tailscale dev origins
- UFW firewall configured

---

## Prerequisites

### 1. Enable TUN device (Proxmox host only)

Tailscale requires access to `/dev/net/tun`. Run this on the **Proxmox host** before starting, replacing `100` with your actual container ID:

```bash
pct set 100 --features tun=1
```

Then restart the container.

---

## Setup workflow

### 2. Inside the container, as root:

Update the system and install curl:

```bash
apt update && apt upgrade -y && apt install -y curl
```

### 3. Download the script:

```bash
curl -fsSL https://raw.githubusercontent.com/pdsykes2512/dev-setup/main/setup.sh -o setup.sh
```

### 4. Run the script:

```bash
sudo bash setup.sh
```

---

## What you'll be asked

The script prompts for the following before installing anything:

| Prompt | Where to get it |
|---|---|
| **Tailscale auth key** | [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys) → Generate auth key → tick Reusable |
| **Cloudflare tunnel token** | [one.dash.cloudflare.com](https://one.dash.cloudflare.com) → Networks → Tunnels → Create tunnel → Linux → copy the full command or just the token |
| **SSH public key** | Run `cat ~/.ssh/id_ed25519.pub` on your local machine |
| **Developer username** | Default: `developer` |
| **Prototype name** | Default: `my-brand-prototype` |
| **MongoDB database name** | Default: `prototype_db` |
| **MongoDB username** | Default: `prototype_user` |
| **MongoDB password** | Leave blank to auto-generate |

A confirmation summary is shown before anything is installed.

---

## Mid-install: GitHub login

During the install, the script will pause for an interactive GitHub device login:

1. A one-time code will appear in the terminal
2. Visit [github.com/login/device](https://github.com/login/device)
3. Enter the code to authorise the machine
4. The script continues automatically

---

## If the script is interrupted

Just re-run it — it will skip completed steps and pick up where it stopped:

```bash
sudo bash setup.sh
```

---

## Starting over

To wipe progress and start completely fresh:

```bash
sudo rm /root/.dev-setup-progress /root/.dev-setup-config
sudo bash setup.sh
```

To reset a single failed step (replace `step-name` with the step from the list below):

```bash
sed -i '/^step-name$/d' /root/.dev-setup-progress
sudo bash setup.sh
```

### Step names for manual reset

| Step name | What it does |
|---|---|
| `system-packages` | apt update, upgrade, base packages |
| `dev-user` | Creates developer user, installs SSH key |
| `ssh-server` | Configures and starts SSH |
| `github-cli` | Installs `gh` |
| `nodejs` | Installs Node.js LTS via nvm |
| `tailscale` | Installs and connects Tailscale |
| `cloudflared` | Installs and starts Cloudflare tunnel |
| `mongodb` | Installs MongoDB 8, creates user and database |
| `github-auth` | Interactive `gh auth login` |
| `clone-repo` | Clones `clean-prototype` |
| `template-deps` | `npm install` in template repo |
| `scaffold-prototype` | Runs `prototype:new` |
| `prototype-deps` | `npm install` in prototype |
| `env-local` | Writes `.env.local` |
| `next-config` | Patches `next.config` for Tailscale origins |
| `claude-code` | Installs Claude Code CLI |
| `firewall` | Configures UFW |

---

## Once complete

SSH in and start the dev server:

```bash
ssh developer@<tailscale-ip>
cd ~/dev/my-brand-prototype
npm run dev
```

Then open in your browser:

```
http://<tailscale-ip>:3000
```

---

## Next steps

1. Update `NEXT_PUBLIC_SITE_URL` in `.env.local` with your Cloudflare tunnel hostname once it is assigned
2. To use MongoDB in the app, install the driver:
   ```bash
   cd ~/dev/my-brand-prototype && npm install mongodb
   ```
3. Initialise Claude Code in the project:
   ```bash
   cd ~/dev/my-brand-prototype
   claude
   ```
   Follow the browser prompt to authenticate on first run.
