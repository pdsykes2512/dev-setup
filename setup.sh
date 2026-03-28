#!/usr/bin/env bash
# =============================================================================
#  setup.sh — TrueNAS Ubuntu container bootstrap
#  github.com/pdsykes2512/dev-setup
#
#  Run with:
#    curl -fsSL https://raw.githubusercontent.com/pdsykes2512/dev-setup/main/setup.sh -o setup.sh
#    screen -S setup
#    sudo bash setup.sh
#
#  If the script is interrupted, just run it again — it will pick up where
#  it left off. To start completely fresh, delete the progress file:
#    sudo rm /root/.dev-setup-progress /root/.dev-setup-config
# =============================================================================

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "\n${CYAN}${BOLD}▶  $*${NC}"; }
success() { echo -e "${GREEN}✔  $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠  $*${NC}"; }
skip()    { echo -e "${GREEN}✔  $* — already done, skipping.${NC}"; }
die()     { echo -e "\n${RED}✘  ERROR: $*${NC}\n"; exit 1; }

# ── Progress tracking ─────────────────────────────────────────────────────────
PROGRESS_FILE="/root/.dev-setup-progress"
CONFIG_FILE="/root/.dev-setup-config"

touch "${PROGRESS_FILE}"

step_done() { grep -qxF "$1" "${PROGRESS_FILE}" 2>/dev/null; }
mark_done() { echo "$1" >> "${PROGRESS_FILE}"; }

# ── Prompt helpers ────────────────────────────────────────────────────────────
prompt_required() {
  local var="$1" label="$2" instructions="$3" value=""
  while [[ -z "$value" ]]; do
    echo -e "\n${BOLD}${label}${NC}"
    echo -e "${YELLOW}${instructions}${NC}"
    read -r -p "  → " value
    [[ -z "$value" ]] && echo -e "${RED}  This field is required.${NC}"
  done
  printf -v "$var" '%s' "$value"
}

prompt_secret() {
  local var="$1" label="$2" instructions="$3" value=""
  while [[ -z "$value" ]]; do
    echo -e "\n${BOLD}${label}${NC}"
    echo -e "${YELLOW}${instructions}${NC}"
    read -r -s -p "  → " value
    echo ""
    [[ -z "$value" ]] && echo -e "${RED}  This field is required.${NC}"
  done
  printf -v "$var" '%s' "$value"
}

prompt_default() {
  local var="$1" label="$2" default="$3" instructions="$4" value=""
  echo -e "\n${BOLD}${label}${NC}"
  echo -e "${YELLOW}${instructions}${NC}"
  echo -e "  (press Enter to use default: ${BOLD}${default}${NC})"
  read -r -p "  → " value
  printf -v "$var" '%s' "${value:-$default}"
}

# ── Root check ────────────────────────────────────────────────────────────────
[[ "$(id -u)" -ne 0 ]] && die "Please run as root: sudo bash setup.sh"

# ── Screen/tmux check ─────────────────────────────────────────────────────────
if [[ -z "${STY:-}" ]] && [[ -z "${TMUX:-}" ]]; then
  echo -e "\n${YELLOW}${BOLD}  WARNING: You are not inside screen or tmux.${NC}"
  echo -e "${YELLOW}  If your SSH session drops, this script will be killed mid-install.${NC}"
  echo -e "${YELLOW}  It will resume from where it stopped if you re-run it.${NC}"
  echo ""
  echo -e "  ${BOLD}Recommended: cancel now and run inside screen:${NC}"
  echo -e "    screen -S setup"
  echo -e "    sudo bash setup.sh"
  echo ""
  echo -e "  If connection drops, reconnect and run:  ${BOLD}screen -r setup${NC}"
  echo ""
  read -r -p "  Continue anyway without screen? (yes/no): " SCREEN_CONFIRM
  [[ "$SCREEN_CONFIRM" != "yes" ]] && die "Aborted. Run inside screen and try again."
fi

# ══════════════════════════════════════════════════════════════════════════════
#  GATHER CONFIG
# ══════════════════════════════════════════════════════════════════════════════

# If a previous run saved config, load it and skip prompts
if [[ -f "${CONFIG_FILE}" ]]; then
  echo -e "\n${GREEN}${BOLD}  Resuming previous setup — loading saved configuration.${NC}"
  echo -e "  (Delete ${CONFIG_FILE} to start fresh with new values)\n"
  # shellcheck source=/dev/null
  source "${CONFIG_FILE}"
else
  clear
  echo -e "${CYAN}${BOLD}"
  echo "  ╔══════════════════════════════════════════════════════╗"
  echo "  ║       TrueNAS Dev Container Setup                   ║"
  echo "  ║       github.com/pdsykes2512/dev-setup              ║"
  echo "  ╚══════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo "  This script will set up a complete Node.js dev environment."
  echo "  You'll be asked for a few details before anything is installed."
  echo ""

  # ── Tailscale auth key ──────────────────────────────────────────────────────
  prompt_secret TAILSCALE_AUTH_KEY \
    "Tailscale Auth Key" \
    "  1. Go to https://login.tailscale.com/admin/settings/keys
  2. Click 'Generate auth key'
  3. Tick 'Reusable' if you may re-run this script
  4. Copy and paste the key below (input is hidden)"

  # ── Cloudflared token ───────────────────────────────────────────────────────
  echo -e "\n${BOLD}Cloudflare Tunnel Token${NC}"
  echo -e "${YELLOW}  1. Go to https://one.dash.cloudflare.com → Networks → Tunnels
  2. Create a new tunnel (or open an existing one)
  3. Choose Linux as the environment
  4. Copy the full install command shown (e.g. 'sudo cloudflared service install eyJ...')
     or just the token on its own — either is fine
  5. Paste it below (input is hidden)${NC}"
  CLOUDFLARED_RAW=""
  while [[ -z "$CLOUDFLARED_RAW" ]]; do
    read -r -s -p "  → " CLOUDFLARED_RAW
    echo ""
    [[ -z "$CLOUDFLARED_RAW" ]] && echo -e "${RED}  This field is required.${NC}"
  done
  CLOUDFLARED_TOKEN="${CLOUDFLARED_RAW##* }"
  [[ -z "$CLOUDFLARED_TOKEN" ]] && die "Could not extract a token from what you pasted."

  # ── SSH public key ──────────────────────────────────────────────────────────
  prompt_required SSH_PUBLIC_KEY \
    "Your SSH Public Key (id_ed25519.pub)" \
    "  Run this on your local machine to get it:
    cat ~/.ssh/id_ed25519.pub
  Then paste the full line below (starts with 'ssh-ed25519 ...')"

  # ── Developer username ──────────────────────────────────────────────────────
  prompt_default DEV_USER \
    "Developer Username" \
    "developer" \
    "  The local user account that will own all project files."

  # ── Prototype name ──────────────────────────────────────────────────────────
  prompt_default PROTOTYPE_NAME \
    "Prototype Name" \
    "my-brand-prototype" \
    "  The name for your new prototype site.
  Use lowercase letters, numbers, and hyphens only."

  # ── MongoDB ─────────────────────────────────────────────────────────────────
  prompt_default MONGO_DB_NAME \
    "MongoDB Database Name" \
    "prototype_db" \
    "  The name of the MongoDB database for this prototype."

  prompt_default MONGO_USER \
    "MongoDB Username" \
    "prototype_user" \
    "  The MongoDB user that the app will connect as."

  echo -e "\n${BOLD}MongoDB Password${NC}"
  echo -e "${YELLOW}  Leave blank to auto-generate a secure random password (recommended).${NC}"
  read -r -s -p "  → " MONGO_PASSWORD_INPUT
  echo ""
  if [[ -z "$MONGO_PASSWORD_INPUT" ]]; then
    MONGO_PASSWORD="$(openssl rand -base64 24 | tr -d '=+/')"
    warn "MongoDB password auto-generated — will be saved to .env.local"
  else
    MONGO_PASSWORD="$MONGO_PASSWORD_INPUT"
  fi

  # ── Confirm ─────────────────────────────────────────────────────────────────
  echo ""
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  Please confirm your settings:${NC}"
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  Developer user:     ${BOLD}${DEV_USER}${NC}"
  echo -e "  Prototype name:     ${BOLD}${PROTOTYPE_NAME}${NC}"
  echo -e "  MongoDB database:   ${BOLD}${MONGO_DB_NAME}${NC}"
  echo -e "  MongoDB user:       ${BOLD}${MONGO_USER}${NC}"
  echo -e "  Tailscale key:      ${BOLD}$(echo "$TAILSCALE_AUTH_KEY" | cut -c1-6)…${NC} (hidden)"
  echo -e "  Cloudflare token:   ${BOLD}$(echo "$CLOUDFLARED_TOKEN"  | cut -c1-6)…${NC} (hidden)"
  echo -e "  SSH key:            ${BOLD}$(echo "$SSH_PUBLIC_KEY"     | cut -c1-20)…${NC} (truncated)"
  echo ""
  read -r -p "  Looks good? Type 'yes' to begin installation: " CONFIRM
  [[ "$CONFIRM" != "yes" ]] && die "Aborted. Nothing was installed."

  # ── Save config for resumption ───────────────────────────────────────────────
  cat > "${CONFIG_FILE}" <<CONFIGEOF
TAILSCALE_AUTH_KEY=$(printf '%q' "$TAILSCALE_AUTH_KEY")
CLOUDFLARED_TOKEN=$(printf '%q' "$CLOUDFLARED_TOKEN")
SSH_PUBLIC_KEY=$(printf '%q' "$SSH_PUBLIC_KEY")
DEV_USER=$(printf '%q' "$DEV_USER")
PROTOTYPE_NAME=$(printf '%q' "$PROTOTYPE_NAME")
MONGO_DB_NAME=$(printf '%q' "$MONGO_DB_NAME")
MONGO_USER=$(printf '%q' "$MONGO_USER")
MONGO_PASSWORD=$(printf '%q' "$MONGO_PASSWORD")
CONFIGEOF
  chmod 600 "${CONFIG_FILE}"
fi

# ══════════════════════════════════════════════════════════════════════════════
#  INSTALLATION
# ══════════════════════════════════════════════════════════════════════════════

GITHUB_REPO="pdsykes2512/clean-prototype"
WORK_DIR="/home/${DEV_USER}/dev"
REPO_DIR="${WORK_DIR}/clean-prototype"
PROTOTYPE_DIR="${WORK_DIR}/${PROTOTYPE_NAME}"
NVM_DIR="/home/${DEV_USER}/.nvm"
MONGO_URI="mongodb://${MONGO_USER}:${MONGO_PASSWORD}@127.0.0.1:27017/${MONGO_DB_NAME}"

# ── 1. System update + packages ───────────────────────────────────────────────
if step_done "system-packages"; then
  skip "System update and packages"
else
  info "Running full system update..."
  apt-get update -qq
  apt-get upgrade -y -qq
  apt-get autoremove -y -qq
  info "Installing system packages..."
  apt-get install -y -qq \
    curl wget gnupg ca-certificates lsb-release \
    git openssh-server ufw build-essential screen
  mark_done "system-packages"
  success "System packages installed."
fi

# ── 2. Developer user ─────────────────────────────────────────────────────────
if step_done "dev-user"; then
  skip "Developer user '${DEV_USER}'"
else
  info "Setting up user '${DEV_USER}'..."
  if ! id "${DEV_USER}" &>/dev/null; then
    useradd -m -s /bin/bash "${DEV_USER}"
  fi
  SSH_DIR="/home/${DEV_USER}/.ssh"
  mkdir -p "${SSH_DIR}"
  grep -qxF "${SSH_PUBLIC_KEY}" "${SSH_DIR}/authorized_keys" 2>/dev/null \
    || echo "${SSH_PUBLIC_KEY}" >> "${SSH_DIR}/authorized_keys"
  chmod 700 "${SSH_DIR}"
  chmod 600 "${SSH_DIR}/authorized_keys"
  chown -R "${DEV_USER}:${DEV_USER}" "${SSH_DIR}"
  mark_done "dev-user"
  success "User '${DEV_USER}' configured."
fi

# ── 3. SSH server ─────────────────────────────────────────────────────────────
if step_done "ssh-server"; then
  skip "SSH server"
else
  info "Configuring SSH server..."
  sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  service ssh start || true
  mark_done "ssh-server"
  success "SSH running (key-only auth enforced)."
fi

# ── 4. GitHub CLI ─────────────────────────────────────────────────────────────
if step_done "github-cli"; then
  skip "GitHub CLI"
else
  info "Installing GitHub CLI (gh)..."
  if ! command -v gh &>/dev/null; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
      https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list
    apt-get update -qq
    apt-get install -y -qq gh
  fi
  mark_done "github-cli"
  success "gh $(gh --version | head -1 | awk '{print $3}') installed."
fi

# ── 5. Node.js via nvm ────────────────────────────────────────────────────────
if step_done "nodejs"; then
  skip "Node.js"
else
  info "Installing Node.js LTS via nvm..."
  if [[ ! -d "${NVM_DIR}" ]]; then
    sudo -u "${DEV_USER}" bash -c \
      "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash"
  fi
  sudo -u "${DEV_USER}" bash -c "
    export NVM_DIR=\"${NVM_DIR}\"
    source \"\${NVM_DIR}/nvm.sh\"
    nvm install --lts --no-progress
    nvm alias default 'lts/*'
    echo \"  Node: \$(node --version)   npm: \$(npm --version)\"
  "
  mark_done "nodejs"
  success "Node.js installed."
fi

# Expose node/npm to root for subsequent steps
NODE_BIN="$(sudo -u "${DEV_USER}" bash -c "
  export NVM_DIR=\"${NVM_DIR}\"
  source \"\${NVM_DIR}/nvm.sh\" --silent
  dirname \$(which node)
")"
export PATH="${NODE_BIN}:${PATH}"

# ── 6. Tailscale ──────────────────────────────────────────────────────────────
if step_done "tailscale"; then
  skip "Tailscale"
else
  info "Installing Tailscale..."
  if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
  fi
  systemctl enable tailscaled 2>/dev/null || true
  systemctl start tailscaled 2>/dev/null || service tailscaled start || true
  info "Connecting to Tailscale..."
  for i in {1..10}; do
    tailscale up --authkey="${TAILSCALE_AUTH_KEY}" --accept-routes && break
    [[ $i -eq 10 ]] && die "Tailscale failed to connect. Check: journalctl -u tailscaled"
    warn "Not ready yet, retrying in 3 seconds... (attempt ${i}/10)"
    sleep 3
  done
  mark_done "tailscale"
  success "Tailscale connected — IP: $(tailscale ip -4 2>/dev/null || echo '<pending>')"
fi

TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || echo '<pending>')"

# ── 7. Cloudflared ────────────────────────────────────────────────────────────
if step_done "cloudflared"; then
  skip "Cloudflared"
else
  info "Installing Cloudflared..."
  if ! command -v cloudflared &>/dev/null; then
    ARCH="$(dpkg --print-architecture)"
    curl -fsSL \
      "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb" \
      -o /tmp/cloudflared.deb
    dpkg -i /tmp/cloudflared.deb
    rm /tmp/cloudflared.deb
  fi
  cloudflared service install "${CLOUDFLARED_TOKEN}"
  systemctl start cloudflared 2>/dev/null || service cloudflared start || true
  mark_done "cloudflared"
  success "Cloudflared tunnel running."
fi

# ── 8. MongoDB ────────────────────────────────────────────────────────────────
if step_done "mongodb"; then
  skip "MongoDB"
else
  info "Installing MongoDB 8..."
  # Always remove stale MongoDB repo files before adding the correct one
  rm -f /etc/apt/sources.list.d/mongodb-org-*.list
  rm -f /usr/share/keyrings/mongodb-server-*.gpg
  curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc \
    | gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
  echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] \
https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse" \
    > /etc/apt/sources.list.d/mongodb-org-8.0.list
  apt-get update -qq
  if ! command -v mongod &>/dev/null; then
    apt-get install -y -qq mongodb-org
  fi
  systemctl enable mongod 2>/dev/null || true
  systemctl start mongod 2>/dev/null || service mongod start
  info "Waiting for MongoDB to be ready..."
  for i in {1..20}; do
    mongosh --quiet --eval "db.adminCommand('ping')" &>/dev/null && break
    [[ $i -eq 20 ]] && die "MongoDB did not start. Check: journalctl -u mongod"
    sleep 2
  done
  info "Creating MongoDB user..."
  mongosh --quiet <<MONGOEOF
use ${MONGO_DB_NAME}
db.createUser({
  user: "${MONGO_USER}",
  pwd:  "${MONGO_PASSWORD}",
  roles: [{ role: "readWrite", db: "${MONGO_DB_NAME}" }]
})
MONGOEOF
  mark_done "mongodb"
  success "MongoDB configured."
fi

# ── 9. GitHub auth ────────────────────────────────────────────────────────────
if step_done "github-auth"; then
  skip "GitHub authentication"
else
  info "Authenticating with GitHub..."
  echo ""
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}  ACTION REQUIRED — GitHub login${NC}"
  echo -e "${YELLOW}  A one-time code will appear below. Visit:${NC}"
  echo -e "${YELLOW}    https://github.com/login/device${NC}"
  echo -e "${YELLOW}  …and enter the code to authorise this machine.${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  sudo -u "${DEV_USER}" bash -c \
    "gh auth login --hostname github.com --git-protocol https --web"
  mark_done "github-auth"
  success "GitHub authenticated."
fi

# ── 10. Clone repo ────────────────────────────────────────────────────────────
if step_done "clone-repo"; then
  skip "Clone ${GITHUB_REPO}"
else
  info "Cloning ${GITHUB_REPO}..."
  mkdir -p "${WORK_DIR}"
  chown "${DEV_USER}:${DEV_USER}" "${WORK_DIR}"
  sudo -u "${DEV_USER}" bash -c "
    export NVM_DIR=\"${NVM_DIR}\"
    source \"\${NVM_DIR}/nvm.sh\"
    gh repo clone ${GITHUB_REPO} ${REPO_DIR}
  "
  mark_done "clone-repo"
  success "Cloned to ${REPO_DIR}."
fi

# ── 11. Template dependencies ─────────────────────────────────────────────────
if step_done "template-deps"; then
  skip "Template npm dependencies"
else
  info "Installing template npm dependencies..."
  sudo -u "${DEV_USER}" bash -c "
    export NVM_DIR=\"${NVM_DIR}\"
    source \"\${NVM_DIR}/nvm.sh\"
    cd ${REPO_DIR} && npm install
  "
  mark_done "template-deps"
  success "Template dependencies installed."
fi

# ── 12. Scaffold prototype ────────────────────────────────────────────────────
if step_done "scaffold-prototype"; then
  skip "Scaffold prototype '${PROTOTYPE_NAME}'"
else
  info "Configuring git identity for '${DEV_USER}'..."
  sudo -u "${DEV_USER}" bash -c "
    git config --global user.email '${DEV_USER}@dev.local'
    git config --global user.name '${DEV_USER}'
    git config --global init.defaultBranch main
  "
  info "Scaffolding prototype '${PROTOTYPE_NAME}'..."
  sudo -u "${DEV_USER}" bash -c "
    export NVM_DIR=\"${NVM_DIR}\"
    source \"\${NVM_DIR}/nvm.sh\"
    cd ${REPO_DIR}
    npm run prototype:new -- --name '${PROTOTYPE_NAME}' --no-up
  "
  [[ -d "${PROTOTYPE_DIR}" ]] \
    || die "Prototype not found at ${PROTOTYPE_DIR} — check the output above."
  mark_done "scaffold-prototype"
  success "Prototype created at ${PROTOTYPE_DIR}."
fi

# ── 13. Prototype dependencies ────────────────────────────────────────────────
if step_done "prototype-deps"; then
  skip "Prototype npm dependencies"
else
  info "Installing prototype npm dependencies..."
  sudo -u "${DEV_USER}" bash -c "
    export NVM_DIR=\"${NVM_DIR}\"
    source \"\${NVM_DIR}/nvm.sh\"
    cd ${PROTOTYPE_DIR} && npm install
  "
  mark_done "prototype-deps"
  success "Prototype dependencies installed."
fi

# ── 14. Write .env.local ──────────────────────────────────────────────────────
if step_done "env-local"; then
  skip ".env.local"
else
  info "Writing .env.local..."
  ENV_FILE="${PROTOTYPE_DIR}/.env.local"
  cat > "${ENV_FILE}" <<ENVEOF
# ── MongoDB ───────────────────────────────────────────────────────────────────
MONGODB_URI=${MONGO_URI}
MONGODB_DB=${MONGO_DB_NAME}

# ── Next.js ───────────────────────────────────────────────────────────────────
# Update this to your Cloudflare tunnel hostname once it is known.
NEXT_PUBLIC_SITE_URL=http://localhost:3000

# ── App ───────────────────────────────────────────────────────────────────────
NODE_ENV=development
ENVEOF
  chown "${DEV_USER}:${DEV_USER}" "${ENV_FILE}"
  chmod 600 "${ENV_FILE}"
  mark_done "env-local"
  success ".env.local written."
fi

# ── 15. Patch next.config ─────────────────────────────────────────────────────
if step_done "next-config"; then
  skip "next.config allowedDevOrigins"
else
  info "Patching next.config to allow Tailscale dev origins..."
  # Find whichever config file the prototype uses (.ts or .js)
  NEXT_CONFIG=""
  for f in "${PROTOTYPE_DIR}/next.config.ts" "${PROTOTYPE_DIR}/next.config.js" "${PROTOTYPE_DIR}/next.config.mjs"; do
    [[ -f "$f" ]] && NEXT_CONFIG="$f" && break
  done

  if [[ -z "$NEXT_CONFIG" ]]; then
    warn "Could not find next.config file — skipping. Add allowedDevOrigins manually."
  else
    # If the file already has a nextConfig export, inject allowedDevOrigins into it.
    # Otherwise write a minimal config file.
    if grep -q 'allowedDevOrigins' "${NEXT_CONFIG}"; then
      warn "allowedDevOrigins already present in ${NEXT_CONFIG} — skipping."
    elif grep -q 'nextConfig' "${NEXT_CONFIG}"; then
      # Insert allowedDevOrigins after the opening brace of the config object
      sed -i 's/nextConfig = {/nextConfig = {\n  allowedDevOrigins: ["100.*", "*.ts.net"],/' "${NEXT_CONFIG}"
    else
      # Fallback: append a fresh export
      cat >> "${NEXT_CONFIG}" <<'CONFIGEOF'

const nextConfig = {
  allowedDevOrigins: ["100.*", "*.ts.net"],
};

export default nextConfig;
CONFIGEOF
    fi
    chown "${DEV_USER}:${DEV_USER}" "${NEXT_CONFIG}"
    success "next.config updated — Tailscale origins allowed."
  fi
  mark_done "next-config"
fi

# ── 16. Claude Code ───────────────────────────────────────────────────────────
if step_done "claude-code"; then
  skip "Claude Code"
else
  info "Installing Claude Code..."
  sudo -u "${DEV_USER}" bash -c "curl -fsSL https://claude.ai/install.sh | bash"
  BASHRC="/home/${DEV_USER}/.bashrc"
  if ! grep -q 'claude/bin\|\.local/bin' "${BASHRC}" 2>/dev/null; then
    cat >> "${BASHRC}" <<'BASHRCEOF'

# ── Claude Code ───────────────────────────────────────────────────────────────
export PATH="$HOME/.claude/bin:$HOME/.local/bin:$PATH"
BASHRCEOF
  fi
  chown "${DEV_USER}:${DEV_USER}" "${BASHRC}"
  CLAUDE_BIN="$(sudo -u "${DEV_USER}" bash -c '
    for p in "$HOME/.claude/bin/claude" "$HOME/.local/bin/claude"; do
      [[ -x "$p" ]] && echo "$p" && exit 0
    done
    exit 1
  ' 2>/dev/null || true)"
  mark_done "claude-code"
  if [[ -n "$CLAUDE_BIN" ]]; then
    success "Claude Code installed at ${CLAUDE_BIN}."
  else
    warn "Claude Code installer ran but binary not found — check manually with: which claude"
  fi
fi

# ── 16. Firewall ──────────────────────────────────────────────────────────────
if step_done "firewall"; then
  skip "Firewall"
else
  info "Configuring firewall..."
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow ssh
  ufw allow 3000:3010/tcp
  ufw --force enable
  mark_done "firewall"
  success "Firewall configured."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
# Clean up config file now that we're done (it contains secrets)
rm -f "${CONFIG_FILE}"

echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  ✔  All done! Your dev environment is ready.${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Prototype:${NC}      ${PROTOTYPE_DIR}"
echo -e "  ${BOLD}Template repo:${NC}  ${REPO_DIR}"
echo -e "  ${BOLD}Tailscale IP:${NC}   ${TAILSCALE_IP}"
echo -e "  ${BOLD}MongoDB URI:${NC}    ${MONGO_URI}"
echo ""
echo -e "  ${BOLD}To start developing, SSH in and run:${NC}"
echo -e "    ssh ${DEV_USER}@${TAILSCALE_IP}"
echo -e "    cd ${PROTOTYPE_DIR}"
echo -e "    npm run dev"
echo ""
echo -e "  ${BOLD}Then open in your browser:${NC}"
echo -e "    http://${TAILSCALE_IP}:3000"
echo ""
echo -e "${YELLOW}  NEXT STEPS:${NC}"
echo -e "  1. Update NEXT_PUBLIC_SITE_URL in .env.local with your"
echo -e "     Cloudflare tunnel hostname once it is assigned."
echo -e "  2. To use MongoDB in the app, install the driver:"
echo -e "       cd ${PROTOTYPE_DIR} && npm install mongodb"
echo -e "  3. Test the DB connection:"
echo -e "       mongosh \"${MONGO_URI}\""
echo ""
