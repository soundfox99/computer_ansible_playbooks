# Command runner for computer_ansible_playbooks. `just` with no args lists targets.

set shell := ["bash", "-cu"]
set positional-arguments

# Default target: list available recipes
_default:
    @just --list --unsorted

# ─── Linting (pipx-installed) ──────────────────────────────────────────────

# One-time: install ansible-core + ansible-lint + yamllint via pipx
install-linters:
    pipx install --force ansible-core
    pipx install --force ansible-lint
    pipx install --force yamllint

# Run every lint check (yamllint → syntax → ansible-lint, fails fast)
lint: lint-yaml syntax lint-ansible

# YAML style + parse
lint-yaml:
    yamllint .

# Ansible playbook YAML / Jinja parse check
syntax:
    ansible-playbook local.yml --syntax-check

# Full ansible-lint (style, best-practice, deprecation)
lint-ansible:
    ansible-lint

# ─── Ansible operations ────────────────────────────────────────────────────

# Install collections declared in collections/requirements.yml
install-collections:
    ansible-galaxy collection install -r collections/requirements.yml

# Apply the playbook locally (no pull)
apply *FLAGS:
    ansible-playbook -i inventory/hosts.yml local.yml {{FLAGS}}

# Dry-run: preview what would change
apply-check:
    ansible-playbook -i inventory/hosts.yml local.yml --check --diff

# List every task the playbook would run
list-tasks:
    ansible-playbook -i inventory/hosts.yml local.yml --list-tasks

# Trigger the boot-time ansible-pull systemd unit now
pull-now:
    sudo systemctl start ansible-pull@$(id -un).service

# Tail journal for the ansible-pull unit
pull-log:
    journalctl -u ansible-pull@$(id -un).service -f
