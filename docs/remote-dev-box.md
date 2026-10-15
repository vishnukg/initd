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
- **Personal machines only.** Both dev box files are linked only when
  `local.gitconfig` holds the personal email: the SSH config, and
  `~/.config/kitty-dev-box.conf` (the kitty shortcuts, from
  `shared/configs/kitty/dev-box.conf`). A work machine gets neither; its
  `~/.ssh/config` stays its own, and kitty skips the missing include.
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
3. Nothing to do for Colima: the linked SSH config already carries its
   `Include ~/.colima/ssh_config`, so Colima finds it and never writes there.
4. Link the configs with `shared/lib/link.sh macos` (or `linux`). Any existing
   `~/.ssh/config` is moved to `~/.config/initd-backups/`. Check it for hosts
   still in use and add them to `shared/configs/ssh/.ssh/config`.
5. Create this machine's exe.dev key: `shared/lib/exe-dev-key.sh`. Bootstrap runs it
   right after linking, so a bootstrapped machine already has
   `~/.ssh/id_ed25519_exe`; it does nothing without the personal SSH config link.
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
