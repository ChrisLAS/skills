# SSH-Tunnel CLI Wrappers for Remote Lightning/Boltz Nodes

This document explains the NixOS wrapper pattern used to give a local machine
transparent CLI access to `boltzcli` and `lncli` running on a remote Lightning
node. It is written for a future agentic LLM session that needs to understand,
operate, or extend these wrappers.

See `nix-wrapper-example.nix` in this directory for the complete sanitized Nix
code.

---

## Problem

Lightning and Boltz daemons bind their gRPC interfaces to `127.0.0.1` on the
remote node. There is no way to reach them directly from the local machine. You
also need TLS certificates, macaroons, or passwords to authenticate -- and those
credentials live on the local machine (copied once from the remote node).

Manually wiring up SSH tunnels and passing auth flags every time is tedious and
error-prone. The wrappers eliminate all of that.

## Solution: `writeShellScriptBin` Wrappers

Each wrapper is a Nix-generated shell script (`pkgs.writeShellScriptBin`) that:

1. **Validates credentials** -- checks that required secret files exist and are
   readable. Exits with a descriptive error if anything is missing.
2. **Opens an SSH tunnel** -- picks a random ephemeral local port and forwards
   it to the remote daemon's gRPC port via `ssh -N -L`.
3. **Invokes the real CLI** -- runs `boltzcli` or `lncli` pointed at the local
   tunnel endpoint, with all auth flags (TLS cert, macaroon/password) pre-filled.
4. **Cleans up** -- kills the SSH tunnel process on exit via a `trap`.

Because Nix interpolates the full store paths for `ssh`, `python3`, `boltzcli`,
and `lncli`, the wrappers are fully self-contained and don't depend on `$PATH`
at runtime.

### Naming convention

The wrapper name encodes the target node:

| Wrapper | Target node | What it wraps |
|---------|-------------|---------------|
| `boltzcli-<node>` | `<node>` (SSH hostname) | `boltzcli` (Boltz client CLI) |
| `lncli-<node>` | `<node>` (SSH hostname) | `lncli` (LND CLI) |

To add a second node, duplicate the wrapper definitions with a different name
suffix and different SSH target / credential paths.

---

## Secret File Layout

Secrets are **not** managed by Nix. They must be placed manually by the
operator. Nix only creates the directories (via an activation script) and the
wrappers read from them at runtime.

```
~/.config/secrets/
├── boltz-client/
│   ├── boltz.toml                  # Contains password = "..." line
│   └── <node>-boltzd-tls.cert     # Boltz daemon TLS certificate
└── lnd-<node>/
    ├── tls.cert                    # LND TLS certificate
    └── admin.macaroon              # LND admin macaroon
```

### How to provision secrets

1. SSH into the remote node.
2. Copy the files to the local paths above:
   - **Boltz TLS cert**: typically at `~/.boltz/boltzd-tls.cert` on the remote.
   - **Boltz config (password)**: create a `boltz.toml` with a single
     `password = "..."` line matching the remote daemon's password.
   - **LND TLS cert**: typically at `~/.lnd/tls.cert` on the remote.
   - **LND admin macaroon**: typically at
     `~/.lnd/data/chain/bitcoin/mainnet/admin.macaroon` on the remote.
3. Verify permissions: the secret directories should be `0700`, files `0600` or
   `0644` (certs are not sensitive on their own, but keeping them restricted is
   fine).

### Activation script

Nix bootstraps the directory structure on every `nixos-rebuild switch`:

```nix
system.activationScripts.boltz-client-bootstrap = lib.stringAfter [ "users" ] ''
  install -d -m 0755 -o <user> -g <group> "<home>/.config/boltz-client"
  install -d -m 0700 -o <user> -g <group> "<home>/.config/secrets/boltz-client"
  install -d -m 0700 -o <user> -g <group> "<home>/.config/secrets/lnd-<node>"
  install -d -m 0700 -o <user> -g <group> "<home>/.boltz"

  ln -sfn "<home>/.config/secrets/boltz-client/boltz.toml" "<home>/.boltz/boltz.toml"
  chown -h <user>:<group> "<home>/.boltz/boltz.toml"
'';
```

This is idempotent -- it runs every rebuild and never touches existing file
contents.

---

## Remote Port Map

| Service | Remote bind | gRPC port |
|---------|-------------|-----------|
| Boltz daemon (`boltzd`) | `127.0.0.1` | `9002` |
| LND (`lnd`) | `127.0.0.1` | `10009` |

The wrappers forward these to a random local port each invocation.

## Auth Methods

| Wrapper | Auth mechanism |
|---------|---------------|
| `boltzcli-<node>` | Password (parsed from `boltz.toml`) + TLS cert, `--no-macaroons` |
| `lncli-<node>` | Admin macaroon + TLS cert |

---

## How the Flake Provides `boltz-client`

`boltz-client` (which contains the `boltzcli` binary) is not in nixpkgs. It
comes from an external flake:

```nix
# flake.nix inputs
boltz-client-flake = {
  url = "github:noblepayne/boltz-client-flake";
  inputs.nixpkgs.follows = "nixpkgs";
};

# In the overlay
boltz-client = boltz-client-flake.packages.${system}.default;
```

`lnd` (which contains `lncli`) comes directly from nixpkgs -- no overlay needed.

Both the raw packages (`pkgs.boltz-client`, `pkgs.lnd`) and the wrappers are
installed in `environment.systemPackages`. The raw packages are needed because
the wrappers reference their store paths (e.g.,
`${pkgs.boltz-client}/bin/boltzcli`).

---

## Adding a Wrapper for a New Node

To add wrappers for a second node (e.g., `nodebeta`):

1. **Create the wrapper definitions** in your `system.nix` `let` block:
   - Duplicate `boltzcli-<existingnode>` as `boltzcli-nodebeta`.
   - Change `ssh_target` to the new node's SSH hostname.
   - Change `config_file` / `tls_cert` paths to point at
     `~/.config/secrets/boltz-client/nodebeta-*` files.
   - Repeat for `lncli-nodebeta` with the appropriate LND secret paths.

2. **Add secret directories** to the activation script:
   ```nix
   install -d -m 0700 -o <user> -g <group> "<home>/.config/secrets/lnd-nodebeta"
   ```

3. **Install the wrappers** in `environment.systemPackages`:
   ```nix
   boltzcli-nodebeta
   lncli-nodebeta
   ```

4. **Provision the secrets** on the local machine for the new node.

5. **Rebuild**: `sudo nixos-rebuild switch`

6. **Update the agent skill** (if applicable) to include the new wrapper names
   in the `bins` metadata and wrapper selection logic.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `missing readable config` / `missing readable TLS cert` | Secret files not provisioned | Copy files from remote node (see provisioning above) |
| `missing password entry` | `boltz.toml` doesn't have `password = "..."` line | Check file format: `password = "yourpassword"` |
| SSH tunnel fails / hangs | SSH key not authorized, hostname not resolvable | Verify `ssh <node> hostname` works interactively |
| `connection refused` after tunnel starts | Remote daemon not running | SSH in and check the daemon: `systemctl status boltzd` / `systemctl status lnd` |
| Wrapper not found | Not in `environment.systemPackages` or haven't rebuilt | Add to package list and `sudo nixos-rebuild switch` |

---

## Key Design Decisions

- **Random ephemeral ports**: avoids conflicts if multiple wrapper invocations
  run concurrently.
- **Store-path pinned binaries**: `${pkgs.openssh}/bin/ssh` etc. means the
  wrapper doesn't depend on the user's `$PATH`.
- **Secrets outside Nix**: Nix store is world-readable. Credentials must never
  be interpolated into Nix derivations. The wrappers read them at runtime from
  `~/.config/secrets/`.
- **Activation scripts for directories only**: Nix creates the directory
  structure but never touches secret file contents, so rebuilds are safe.
- **`--no-macaroons` for Boltz**: Boltz client uses password auth, not
  macaroons. This flag is required to suppress macaroon-related errors.
