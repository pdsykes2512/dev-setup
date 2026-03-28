#!/usr/bin/env bash
# =============================================================================
#  setup.sh — TrueNAS Ubuntu container bootstrap
#  github.com/pdsykes2512/dev-setup
#
#  Run with:
#    curl -fsSL https://raw.githubusercontent.com/pdsykes2512/dev-setup/main/setup.sh | sudo bash
# =============================================================================

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "\n${CYAN}${BOLD}▶  $*${NC}"; }
success() { echo -e "${GREEN}✔  $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠  $*${NC}"; }
die()     { echo -e "\n${RED}✘  ERROR: $*${NC}\n"; exit 1; }

# ── Prompt helpers ────────────────────────────────────────────────────────────

# prompt_required <var_name> <label> <instructions>
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

# prompt_secret <var_name> <label> <instructions>
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

# prompt_default <var_name> <label> <default> <instructions>
prompt_default() {
  local var="$1" label="$2" default="$3" instructions="$4" value=""
  echo -e "\n${BOLD}${label}${NC}"
  echo -e "${YELLOW}${instructions}${NC}"
  echo -e "  (press Enter to use default: ${BOLD}${default}${NC})"
  read -r -p "  → " value
  printf -v "$var" '%s' "${value:-$default}"
}

# ── Root check ────────────────────────────────────────────────────────────────
[[ "$(id -u)" -ne 0 ]] && die "Please run as root:\n  curl -fsSL <url> | sudo bash"

# ══════════════════════════════════════════════════════════════════════════════
#  GATHER CONFIG
# ══════════════════════════════════════════════════════════════════════════════

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

# ── Tailscale auth key ────────────────────────────────────────────────────────
prompt_secret TAILSCALE_AUTH_KEY \
  "Tailscale Auth Key" \
  "  1. Go to https://login.tailscale.com/admin/settings/keys
  2. Click 'Generate auth key'
  3. Tick 'Reusable' if you may re-run this script
  4. Copy and paste the key below (input is hidden)"

# ── Cloudflared token ─────────────────────────────────────────────────────────
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
# Extract just the token — last whitespace-separated word in whatever was pasted
CLOUDFLARED_TOKEN="${CLOUDFLARED_RAW##* }"
if [[ -z "$CLOUDFLARED_TOKEN" ]]; then
  die "Could not extract a token from what you pasted. Please try again."
fi

# ── SSH public key ────────────────────────────────────────────────────────────
prompt_required SSH_PUBLIC_KEY \
  "Your SSH Public Key (id_ed25519.pub)" \
  "  Run this on your local machine to get it:
    cat ~/.ssh/id_ed25519.pub
  Then paste the full line below (starts with 'ssh-ed25519 ...')"

# ── Developer username ────────────────────────────────────────────────────────
prompt_default DEV_USER \
  "Developer Username" \
  "developer" \
  "  The local user account that will own all project files."

# ── Prototype name ────────────────────────────────────────────────────────────
prompt_default PROTOTYPE_NAME \
  "Prototype Name" \
  "my-brand-prototype" \
  "  The name for your new prototype site.
  Use lowercase letters, numbers, and hyphens only."

# ── MongoDB ───────────────────────────────────────────────────────────────────
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
  warn "MongoDB password will be auto-generated and saved to .env.local"
else
  MONGO_PASSWORD="$MONGO_PASSWORD_INPUT"
fi

# ── Confirm ───────────────────────────────────────────────────────────────────
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

# ══════════════════════════════════════════════════════════════════════════════
#  INSTALLATION
# ══════════════════════════════════════════════════════════════════════════════

GITHUB_REPO="pdsykes2512/clean-prototype"
WORK_DIR="/home/${DEV_USER}/dev"
REPO_DIR="${WORK_DIR}/clean-prototype"
PROTOTYPE_DIR="${WORK_DIR}/${PROTOTYPE_NAME}"
NVM_DIR="/home/${DEV_USER}/.nvm"

# ── 1. System packages ────────────────────────────────────────────────────────
info "Installing system packages..."
apt-get update -qq
apt-get install -y -qq \
  curl wget gnupg ca-certificates lsb-release \
  git openssh-server ufw build-essential
success "System packages installed."

# ── 2. Developer user ─────────────────────────────────────────────────────────
info "Setting up user '${DEV_USER}'..."
if ! id "${DEV_USER}" &>/dev/null; then
  useradd -m -s /bin/bash "${DEV_USER}"
  success "User '${DEV_USER}' created."
else
  success "User '${DEV_USER}' already exists, skipping."
fi

SSH_DIR="/home/${DEV_USER}/.ssh"
mkdir -p "${SSH_DIR}"
grep -qxF "${SSH_PUBLIC_KEY}" "${SSH_DIR}/authorized_keys" 2>/dev/null \
  || echo "${SSH_PUBLIC_KEY}" >> "${SSH_DIR}/authorized_keys"
chmod 700 "${SSH_DIR}"
chmod 600 "${SSH_DIR}/authorized_keys"
chown -R "${DEV_USER}:${DEV_USER}" "${SSH_DIR}"
success "SSH public key installed."

# ── 3. SSH server ─────────────────────────────────────────────────────────────
info "Configuring SSH server..."
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
service ssh start || true
success "SSH running (key-only auth enforced)."

# ── 4. GitHub CLI ─────────────────────────────────────────────────────────────
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
success "gh $(gh --version | head -1 | awk '{print $3}') installed."

# ── 5. Node.js via nvm ────────────────────────────────────────────────────────
info "Installing Node.js LTS via nvm..."
if [[ ! -d "${NVM_DIR}" ]]; then
  sudo -u "${DEV_USER}" bash -c \
    "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash"
fi

sudo -u "${DEV_USER}" bash -c "
  export NVM_DIR=\"${NVM_DIR}\"
  source \"\${NVM_DIR}/nvm.sh\"
  nvm install --lts
  nvm alias default 'lts/*'
  echo \"  Node: \$(node --version)   npm: \$(npm --version)\"
"

# Expose node/npm to root for subsequent steps
NODE_BIN="$(sudo -u "${DEV_USER}" bash -c "
  export NVM_DIR=\"${NVM_DIR}\"
  source \"\${NVM_DIR}/nvm.sh\" --silent
  dirname \$(which node)
")"
export PATH="${NODE_BIN}:${PATH}"
success "Node.js installed."

# ── 6. Tailscale ──────────────────────────────────────────────────────────────
info "Installing Tailscale..."
if ! command -v tailscale &>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
tailscale up --authkey="${TAILSCALE_AUTH_KEY}" --accept-routes
TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || echo '<pending>')"
success "Tailscale connected — IP: ${TAILSCALE_IP}"

# ── 7. Cloudflared ────────────────────────────────────────────────────────────
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
success "Cloudflared tunnel running."

# ── 8. MongoDB ────────────────────────────────────────────────────────────────
info "Installing MongoDB 7..."
if ! command -v mongod &>/dev/null; then
  UBUNTU_CODENAME="$(lsb_release -cs)"
  curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc \
    | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
  echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] \
    https://repo.mongodb.org/apt/ubuntu ${UBUNTU_CODENAME}/mongodb-org/7.0 multiverse" \
    > /etc/apt/sources.list.d/mongodb-org-7.0.list
  apt-get update -qq
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

info "Creating MongoDB database and user..."
mongosh --quiet <<MONGOEOF
use ${MONGO_DB_NAME}
db.createUser({
  user: "${MONGO_USER}",
  pwd:  "${MONGO_PASSWORD}",
  roles: [{ role: "readWrite", db: "${MONGO_DB_NAME}" }]
})
MONGOEOF
success "MongoDB configured."

MONGO_URI="mongodb://${MONGO_USER}:${MONGO_PASSWORD}@127.0.0.1:27017/${MONGO_DB_NAME}"

# ── 9. GitHub auth ────────────────────────────────────────────────────────────
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
success "GitHub authenticated."

# ── 10. Clone repo ────────────────────────────────────────────────────────────
info "Cloning ${GITHUB_REPO}..."
mkdir -p "${WORK_DIR}"
chown "${DEV_USER}:${DEV_USER}" "${WORK_DIR}"
sudo -u "${DEV_USER}" bash -c "
  export NVM_DIR=\"${NVM_DIR}\"
  source \"\${NVM_DIR}/nvm.sh\"
  gh repo clone ${GITHUB_REPO} ${REPO_DIR}
"
success "Cloned to ${REPO_DIR}."

# ── 11. Install template dependencies ─────────────────────────────────────────
info "Installing template npm dependencies..."
sudo -u "${DEV_USER}" bash -c "
  export NVM_DIR=\"${NVM_DIR}\"
  source \"\${NVM_DIR}/nvm.sh\"
  cd ${REPO_DIR} && npm install
"
success "Template dependencies installed."

# ── 12. Scaffold prototype ────────────────────────────────────────────────────
info "Scaffolding prototype '${PROTOTYPE_NAME}'..."
sudo -u "${DEV_USER}" bash -c "
  export NVM_DIR=\"${NVM_DIR}\"
  source \"\${NVM_DIR}/nvm.sh\"
  cd ${REPO_DIR}
  npm run prototype:new -- --name '${PROTOTYPE_NAME}' --no-up
"
[[ -d "${PROTOTYPE_DIR}" ]] \
  || die "Prototype not found at ${PROTOTYPE_DIR} — check the output above."
success "Prototype created at ${PROTOTYPE_DIR}."

# ── 13. Install prototype dependencies ────────────────────────────────────────
info "Installing prototype npm dependencies..."
sudo -u "${DEV_USER}" bash -c "
  export NVM_DIR=\"${NVM_DIR}\"
  source \"\${NVM_DIR}/nvm.sh\"
  cd ${PROTOTYPE_DIR} && npm install
"
success "Prototype dependencies installed."

# ── 14. Write .env.local ──────────────────────────────────────────────────────
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
success ".env.local written."

# ── 15. Firewall ──────────────────────────────────────────────────────────────
info "Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 3000:3010/tcp
ufw --force enable
success "Firewall configured."

# ── Done ──────────────────────────────────────────────────────────────────────
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
