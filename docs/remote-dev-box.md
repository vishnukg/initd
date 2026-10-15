# Remote dev box (exe.dev)

A remote Linux VM for dev work and Claude sessions, reached over SSH from the
personal laptops. Work machines are deliberately left out.

| | |
|---|---|
| Provider | [exe.dev](https://exe.dev), Personal plan, region `syd` |
| VM name | `videv` (`videv.exe.xyz`), image `exeuntu` (Ubuntu 24.04) |
| Login user | `exedev`, passwordless sudo |
| Local shortcut | `ssh dev`, or kitty `ctrl+shift+d` / `cmd+shift+d` |
| Web | `https://videv.exe.xyz` (port 8000); ports 3000–9999 at `https://videv.exe.xyz:<port>/`, private by default |

## How it fits together

- **`~/.ssh/config`** is linked from `shared/configs/ssh/.ssh/config`, on
  machines whose `local.gitconfig` holds the personal email only. It maps
  `dev` → `videv.exe.xyz`, uses `~/.ssh/id_ed25519_exe`, and shares one
  connection, so new windows open in ~0.06s.
- **Keys:** each machine has its own exe.dev key, `~/.ssh/id_ed25519_exe`,
  kept separate from the GitHub key `~/.ssh/id_ed25519`. The VM has its own
  GitHub key, registered on GitHub as "videv (exe.dev)".
- **One tmux:** the kitty shortcut runs `ssh dev` in a new OS window without
  starting fish, so the laptop's tmux never starts in it. Typing `ssh dev`
  inside the local tmux nests two tmuxes on the same `C-a` prefix instead.
- **The VM itself** is built by `vm/bootstrap.sh`: CLI tools, fish 4, the
  shared configs, the full mise toolchain, gh auth and the GitHub SSH key.

## Set up a new personal Mac (or Linux laptop)

Run these from `~/.config/initd` on the new machine. An agent can do all of
them except registering the key in step 5.

1. `git pull`
2. Confirm the profile is personal:
   `git config --file shared/configs/git/local.gitconfig user.email` must
   print `vishnukg@gmail.com`. If not: `node shared/lib/git-profile.mjs personal`.
3. **macOS only:** stop an existing Colima VM writing into the linked SSH config
   (the template's `sshConfig: false` only reaches newly created ones):
   `sed -i '' 's/^sshConfig: true/sshConfig: false/' ~/.colima/default/colima.yaml`
4. Link the configs with `shared/lib/link.sh macos` (or `linux`). Any existing
   `~/.ssh/config` is moved to `~/.config/initd-backups/`. Check it for hosts
   still in use and add them to `shared/configs/ssh/.ssh/config`.
5. Create this machine's exe.dev key, unless `~/.ssh/id_ed25519_exe` already exists:
   `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_exe -N "" -C "$(hostname) exe.dev"`
   Then register it with the existing account, any one of:
   - **From this machine:** run `ssh exe.dev` and, when it asks you to
     register, give the same email (`vishnukg@gmail.com`). That adds the key
     to the existing account; a *different* email creates a new one.
   - **On the web:** paste the `.pub` line into https://exe.dev/user/security.
   - **From a registered machine:**
     `echo '<pub key line>' | ssh exe.dev ssh-key add`
6. Verify: `ssh dev hostname` prints `videv`. The first connection asks to
   trust the VM's host key; accept it. Then reload kitty (`ctrl+shift+F5`) and
   try `cmd+shift+d`.

## Rebuild the VM from scratch

```bash
ssh exe.dev "new --name=videv --disk=60GB --no-email"   # names: 5+ chars, globally unique
ssh dev 'git clone https://github.com/vishnukg/initd ~/.config/initd'
ssh -t dev 'bash ~/.config/initd/vm/bootstrap.sh'     # interactive: gh login, git email, GitHub key
```

Then remove the old VM's GitHub key ("videv (exe.dev)") from
github.com/settings/keys. The new run registers its own.

## Day to day

- Update the VM: `ssh -t dev '~/.config/initd/vm/update.sh'`
- exe.dev commands: `ssh exe.dev help`, `ssh exe.dev ls`, `ssh exe.dev rm <vm>`.
  Arguments with spaces need the whole command quoted:
  `ssh exe.dev "new --comment='a b'"`
- Plan limits (`ssh exe.dev billing plan`): 2 vCPU / 4 GB RAM / 100 GB disk
  shared across all VMs.
