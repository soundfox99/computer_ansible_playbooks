#!/usr/bin/env bash
# Bootstrap an Arch Linux machine into ansible-pull management.
#
# Actions:
#   1. Refreshes pacman DB and installs ansible + git + base-devel
#   2. Bootstraps yay from AUR if missing
#   3. Installs the Ansible collections this repo needs
#   4. Trusts github.com's SSH host key (idempotent)
#   5. Runs ansible-pull once (first apply of the playbook)
#   6. Installs and enables systemd/ansible-pull@<user>.service (re-runs on boot)
#
# Prerequisites (script does NOT set these up for you):
#   - Passwordless sudo for the invoking user, OR you're OK typing your password
#     several times.
#   - An SSH key registered with GitHub that can read the private playbook repo.
#
# Usage:
#   ./bootstrap.sh [--no-service]     # skip installing the boot-time systemd unit

set -euo pipefail

REPO_URL="git@github.com:soundfox99/computer_ansible_playbooks.git"
REPO_DIR="${HOME}/computer_ansible_playbooks"
INSTALL_SERVICE=1

for arg in "$@"; do
    case "$arg" in
        --no-service) INSTALL_SERVICE=0 ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0
            ;;
        *) printf 'Unknown flag: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; }

if [[ ${EUID} -eq 0 ]]; then
    err "Run as your regular user (sudo is invoked where needed)."
    exit 1
fi

log "Refreshing pacman database"
sudo pacman -Sy --noconfirm

log "Installing ansible + git + base-devel"
sudo pacman -S --needed --noconfirm ansible git base-devel

if ! command -v yay >/dev/null 2>&1; then
    log "Bootstrapping yay from AUR"
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT
    git clone https://aur.archlinux.org/yay.git "${tmp}/yay"
    (cd "${tmp}/yay" && makepkg -si --noconfirm)
    trap - EXIT
    rm -rf "${tmp}"
else
    log "yay already installed"
fi

log "Trusting github.com SSH host key"
mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"
if ! ssh-keygen -F github.com >/dev/null 2>&1; then
    ssh-keyscan -H github.com >> "${HOME}/.ssh/known_hosts" 2>/dev/null
fi

log "Cloning / updating dev checkout at ${REPO_DIR}"
if [[ -d "${REPO_DIR}/.git" ]]; then
    git -C "${REPO_DIR}" pull --ff-only
else
    git clone "${REPO_URL}" "${REPO_DIR}"
fi

log "Installing required Ansible collections"
ansible-galaxy collection install -r "${REPO_DIR}/collections/requirements.yml"

log "Running ansible-pull for the first time (this may take a while)"
ansible-pull \
    -U "${REPO_URL}" \
    -d "${HOME}/.ansible/pull/$(hostname -s)" \
    -i inventory/hosts.yml \
    local.yml

if [[ ${INSTALL_SERVICE} -eq 1 ]]; then
    unit_src="${REPO_DIR}/systemd/ansible-pull@.service"
    unit_dst="/etc/systemd/system/ansible-pull@.service"
    log "Installing systemd unit → ${unit_dst}"
    sudo install -m 644 "${unit_src}" "${unit_dst}"
    sudo systemctl daemon-reload
    sudo systemctl enable "ansible-pull@$(id -un).service"
    log "Enabled ansible-pull@$(id -un).service — will re-apply on every boot."
    log "To trigger it now:  sudo systemctl start ansible-pull@$(id -un).service"
else
    log "Skipping systemd unit install (--no-service)"
fi

log "Bootstrap complete."
