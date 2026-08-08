# Colima primer

Colima ("Container Linux on Mac") runs a lightweight Linux VM in the
background and gives you a standard Docker CLI on top of it — no Docker
Desktop required or installed on this repo's machines. `macos/Brewfile`
installs four formulas for this: `colima` (the VM/runtime manager),
`docker` (the CLI client only — not Docker Desktop), `docker-compose`
(the compose plugin), and `docker-credential-helper` (the `osxkeychain`
credential helper, see below).

Docker Desktop and Colima both ultimately provide the same thing: a Docker
daemon reachable at a socket, wired up to the `docker` CLI via a "context."
Colima supplies its own daemon inside its VM, so no separate app is needed —
if you ever install Docker Desktop for another reason, don't run it at the
same time as Colima, since both fight over the default Docker context/socket.

## Daily use

```bash
colima start                # boot the VM + Docker daemon (first run pulls the VM image)
docker ps                   # normal docker CLI, now talking to Colima
docker compose up           # docker-compose formula wires this in
colima stop                 # shut the VM down when you're done
colima status                # check if it's running
```

Colima persists state between `start`/`stop`, so stopping it doesn't lose
images or containers — it just frees the CPU/RAM the VM was holding.

## Configuring resources

Colima's built-in defaults are modest (2 CPU / 2GiB memory / 100GiB disk,
`qemu` VM type). This repo manages the *template* Colima reads when
creating a brand-new profile, so `colima start` on a fresh machine already
comes up sized at 4 CPU / 4GiB memory / 60GiB disk, using `vz` (Apple's
native Virtualization.framework, macOS 13+) instead of `qemu` — faster,
no extra Homebrew dependency, and pairs with `virtiofs` for the fastest
mount driver. Rosetta is also enabled for amd64 emulation. No flags needed.

- Managed file: `shared/configs/colima/.colima/_templates/default.yaml`
- Linked to: `~/.colima/_templates/default.yaml` (via `MANAGED_LINKS` in
  `shared/managed-links.sh`, same mechanism as the nvim/git/fish configs)

Edit the repo file and re-run `colima start` on any profile that doesn't
exist yet to pick up changes — the template only applies at profile
*creation* time, not to an already-running instance. To resize an existing
instance, pass flags directly: `colima start --cpu 6 --memory 12`. To see
the current profile's live config: `colima list`.

## Registry credentials

`bootstrap.sh` runs `ensure_docker_creds_store` on every bootstrap, which
sets `"credsStore": "osxkeychain"` in `~/.docker/config.json` (merging it in
without touching `currentContext`, plugin hints, or existing `auths` —
that file isn't a `MANAGED_LINKS` symlink, since it can hold live
credentials and shouldn't ever end up in git). This means `docker login`
stores registry credentials in the macOS Keychain instead of writing them
to that JSON file in plaintext. It's idempotent — safe to re-run bootstrap
any time — and requires no manual step, on this machine or a new one.

## Multiple profiles

Colima supports named profiles if you want isolated environments (e.g. one
with Kubernetes enabled, one without):

```bash
colima start --profile k8s --kubernetes
docker --context colima-k8s ps
```

Most single-machine dev setups never need this — the default profile
(`colima start` with no `--profile`) is enough.

## Troubleshooting

- `docker` commands hang or say "Cannot connect to the Docker daemon" →
  `colima start` (the VM isn't running).
- `docker` seems to be talking to the wrong daemon → check
  `docker context ls` and `docker context use colima` (Colima sets this
  automatically on start, but Docker Desktop launching afterward can steal
  it back).
- Full reset: `colima delete` (destroys the VM and all containers/images
  inside it), then `colima start` again.
