# computer_ansible_playbooks

Pull-configuration for Arch Linux via `ansible-pull`. Each managed machine
periodically re-clones this repo and applies the playbook against itself.
Successor to the [dcli-based `arch-config`](https://github.com/soundfox99/dcli_config).

## Fresh-install bootstrap

On a freshly-installed Arch box:

```bash
# Prereqs: pacman working, a user account with sudo, an SSH key GitHub trusts.
curl -fsSL https://raw.githubusercontent.com/soundfox99/computer_ansible_playbooks/main/bootstrap.sh -o bootstrap.sh
chmod +x bootstrap.sh
./bootstrap.sh
```

`bootstrap.sh` installs `ansible`, `git`, `base-devel`, bootstraps `yay`, runs
the playbook once, then installs the `ansible-pull@<user>.service` systemd
unit so the playbook re-applies at every boot.

## Layout

```
ansible.cfg                     defaults (inventory path, roles path, callbacks)
local.yml                       ansible-pull default entrypoint (loops enabled_roles)
bootstrap.sh                    one-shot installer for a fresh Arch box
inventory/hosts.yml             per-machine inventory
host_vars/<hostname>.yml        per-machine config (roles, services, theming)
group_vars/all.yml              cross-host defaults
collections/requirements.yml    community.general + kewlfft.aur + community.crypto
roles/<name>/                   one role per module — tasks + defaults + files
systemd/ansible-pull@.service   template unit: `systemctl enable ansible-pull@user`
```

Full role structure (used where dotfiles / handlers / vars are needed):

```
roles/<name>/
├── tasks/main.yml
├── handlers/main.yml
├── files/                 static copy sources
├── templates/             jinja-templated dotfiles
├── defaults/main.yml      overridable variables
├── vars/main.yml          role-scoped constants
└── meta/main.yml          role dependencies
```

## Adding a host

1. Add an entry under `all.hosts` in `inventory/hosts.yml`.
2. Copy `host_vars/arch-desktop.yml` → `host_vars/<new-hostname>.yml` and edit
   `enabled_roles`, `services_enabled`, `theming` for the new machine.
3. Run `bootstrap.sh` on the new machine.

`local.yml` matches on `ansible_hostname` (the machine's short hostname), so
the host_vars filename must equal the actual hostname.

## Running ad-hoc

```bash
# Apply now (uses the on-disk repo, no pull)
ansible-playbook -i inventory/hosts.yml local.yml

# Force a pull + apply
sudo systemctl start ansible-pull@$(id -un).service

# Preview changes without applying
ansible-playbook -i inventory/hosts.yml local.yml --check --diff

# Only touch a single role (add `tags:` to that role's tasks first)
ansible-playbook -i inventory/hosts.yml local.yml --tags theming
```

## Boot-time behavior

`systemd/ansible-pull@.service` is a **template unit** — you enable it per
user with `systemctl enable ansible-pull@<user>.service`. `bootstrap.sh`
does this for you. On every boot after `network-online.target`, the unit
re-runs `ansible-pull` as that user, applying whatever's in `main` on the
remote.

To disable temporarily:

```bash
sudo systemctl disable ansible-pull@$(id -un).service
```

## Prerequisites the bootstrap does NOT set up

- **Passwordless sudo for the pull-user.** Many tasks need `become: true`;
  the systemd unit runs unattended so it can't prompt. Add a rule at
  `/etc/sudoers.d/ansible-pull`:

  ```
  hestia ALL=(ALL) NOPASSWD: ALL
  ```

  (Or scope this to `/usr/bin/pacman`, `/usr/bin/systemctl`, etc., if you
  want tighter control.)

- **SSH key registered with GitHub.** `ansible-pull` clones over SSH.
  If your key is only in an agent-based keychain, the boot-time run will
  fail — put a file-based key at `~/.ssh/id_ed25519` (or reference one
  via `~/.ssh/config`).

## Role coverage

Fully ported today: `base`, `hardware`, `comfyui`.

Everything else is a stub that installs the package list from the
corresponding `arch-config/modules/<x>/module.lua` and leaves a TODO
comment where dotfiles / hook scripts still need to be brought over.
Fill each role in as you touch it.

## Concept mapping (dcli → Ansible)

| dcli                          | Ansible                                              |
|-------------------------------|------------------------------------------------------|
| `hosts/<host>.lua`            | `host_vars/<host>.yml` + inventory entry             |
| `enabled_modules = {...}`     | `enabled_roles: [...]` looped by `include_role`      |
| `modules/<x>/module.lua`      | `roles/<x>/tasks/main.yml`                           |
| `dotfiles/`                   | `roles/<x>/files/` (copy) or `templates/`            |
| `pre_install_hook`            | pre-task or handler                                  |
| `post_install_hook`           | post-task or handler                                 |
| `dcli.hardware.has_nvidia()`  | `nvidia_present` fact set by `roles/hardware/`       |
| `services.enabled`            | `services_enabled` list looped in `local.yml`        |
| `flatpak_scope = "user"`      | `community.general.flatpak` with `method: user`      |
| `git-crypt` bookmarks         | keep git-crypt, OR migrate to ansible-vault          |
| `dcli install <pkg>`          | edit host_vars → re-run `local.yml`                  |
| `state/*.yaml`                | *(none — Ansible reports per-run, no persistent ledger)* |

## Gaps vs dcli

- **No `dcli status`.** Closest equivalent is
  `ansible-playbook local.yml --check --diff`.
- **No dotfile backup ledger.** Ansible's `backup: true` on `copy`/`template`
  writes per-task backups but doesn't accumulate them.
- **No auto-managed `declared-packages`.** `dcli install` mutated
  `modules/declared-packages.lua`; here you edit `host_vars` yourself.
