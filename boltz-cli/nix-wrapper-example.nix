# SSH-tunnel CLI wrappers for remote Lightning/Boltz nodes
#
# This is a sanitized, self-contained example extracted from a real NixOS
# configuration. All hostnames, usernames, and paths are replaced with
# descriptive placeholders. See WRAPPERS.md for full documentation.
#
# How to use: paste the relevant sections into your own NixOS configuration,
# replacing all <placeholders> with real values.

{ config, lib, pkgs, ... }:

let
  # ──────────────────────────────────────────────────────────────────────
  # Adjust these to match your system.  In a real config these might come
  # from a shared module option (e.g. config.mySystem.user.name).
  # ──────────────────────────────────────────────────────────────────────
  userName  = "<your-username>";          # e.g. "alice"
  userHome  = "<your-home-directory>";    # e.g. "/home/alice"
  userGroup = "<your-primary-group>";     # e.g. "users"

  # ──────────────────────────────────────────────────────────────────────
  # boltzcli wrapper
  #
  # Transparently tunnels to the remote Boltz daemon's gRPC port (9002)
  # and injects TLS + password auth.  The caller just runs:
  #
  #   boltzcli-<node> getinfo
  #   boltzcli-<node> listswaps
  #
  # No manual SSH, no auth flags required.
  # ──────────────────────────────────────────────────────────────────────
  boltzcli-mynode = pkgs.writeShellScriptBin "boltzcli-mynode" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # --- Credential paths (must be provisioned manually, not by Nix) ---
    config_file="${userHome}/.config/secrets/boltz-client/boltz.toml"
    tls_cert="${userHome}/.config/secrets/boltz-client/mynode-boltzd-tls.cert"
    ssh_target="<your-node-ssh-hostname>"   # e.g. a Tailscale or SSH config alias

    # --- Validate credentials exist ---
    if [[ ! -r "$config_file" ]]; then
      echo "boltzcli-mynode: missing readable config: $config_file" >&2
      echo "Create the client config there before using this wrapper." >&2
      exit 1
    fi

    if [[ ! -r "$tls_cert" ]]; then
      echo "boltzcli-mynode: missing readable TLS cert: $tls_cert" >&2
      echo "Copy the remote node's boltzd TLS cert there before using this wrapper." >&2
      exit 1
    fi

    # --- Parse password from boltz.toml ---
    password=""
    while IFS= read -r line; do
      if [[ "$line" =~ ^password[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
        password="''${BASH_REMATCH[1]}"
        break
      fi
    done < "$config_file"

    if [[ -z "$password" ]]; then
      echo "boltzcli-mynode: missing password entry in $config_file" >&2
      exit 1
    fi

    # --- Pick a random ephemeral local port ---
    local_port="$(${pkgs.python3}/bin/python3 - <<'PY'
    import socket
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    print(s.getsockname()[1])
    s.close()
    PY
    )"

    # --- Open SSH tunnel: local random port -> remote 9002 (boltzd gRPC) ---
    ${pkgs.openssh}/bin/ssh \
      -o ExitOnForwardFailure=yes \
      -o ServerAliveInterval=30 \
      -N \
      -L "127.0.0.1:''${local_port}:127.0.0.1:9002" \
      "$ssh_target" &
    ssh_pid=$!
    trap 'kill "$ssh_pid" 2>/dev/null || true' EXIT

    sleep 1

    # --- Invoke boltzcli through the tunnel ---
    ${pkgs.boltz-client}/bin/boltzcli \
      --host 127.0.0.1 \
      --port "$local_port" \
      --tlscert "$tls_cert" \
      --no-macaroons \
      --password "$password" \
      "$@"

    status=$?
    kill "$ssh_pid" 2>/dev/null || true
    wait "$ssh_pid" 2>/dev/null || true
    exit "$status"
  '';

  # ──────────────────────────────────────────────────────────────────────
  # lncli wrapper
  #
  # Transparently tunnels to the remote LND gRPC port (10009)
  # and injects TLS cert + admin macaroon auth.  The caller just runs:
  #
  #   lncli-<node> getinfo
  #   lncli-<node> channelbalance
  #
  # No manual SSH, no auth flags required.
  # ──────────────────────────────────────────────────────────────────────
  lncli-mynode = pkgs.writeShellScriptBin "lncli-mynode" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # --- Credential paths (must be provisioned manually, not by Nix) ---
    tls_cert="${userHome}/.config/secrets/lnd-mynode/tls.cert"
    admin_macaroon="${userHome}/.config/secrets/lnd-mynode/admin.macaroon"
    ssh_target="<your-node-ssh-hostname>"   # same SSH alias as the boltz wrapper

    # --- Validate credentials exist ---
    if [[ ! -r "$tls_cert" ]]; then
      echo "lncli-mynode: missing readable TLS cert: $tls_cert" >&2
      echo "Copy the remote node's LND TLS cert there before using this wrapper." >&2
      exit 1
    fi

    if [[ ! -r "$admin_macaroon" ]]; then
      echo "lncli-mynode: missing readable admin macaroon: $admin_macaroon" >&2
      echo "Copy the remote node's LND admin macaroon there before using this wrapper." >&2
      exit 1
    fi

    # --- Pick a random ephemeral local port ---
    local_port="$(${pkgs.python3}/bin/python3 - <<'PY'
    import socket
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    print(s.getsockname()[1])
    s.close()
    PY
    )"

    # --- Open SSH tunnel: local random port -> remote 10009 (LND gRPC) ---
    ${pkgs.openssh}/bin/ssh \
      -o ExitOnForwardFailure=yes \
      -o ServerAliveInterval=30 \
      -N \
      -L "127.0.0.1:''${local_port}:127.0.0.1:10009" \
      "$ssh_target" &
    ssh_pid=$!
    trap 'kill "$ssh_pid" 2>/dev/null || true' EXIT

    sleep 1

    # --- Invoke lncli through the tunnel ---
    ${pkgs.lnd}/bin/lncli \
      --network=mainnet \
      --rpcserver="127.0.0.1:''${local_port}" \
      --tlscertpath="$tls_cert" \
      --macaroonpath="$admin_macaroon" \
      "$@"

    status=$?
    kill "$ssh_pid" 2>/dev/null || true
    wait "$ssh_pid" 2>/dev/null || true
    exit "$status"
  '';

in
{
  # ──────────────────────────────────────────────────────────────────────
  # Flake input (add to your flake.nix inputs):
  #
  #   boltz-client-flake = {
  #     url = "github:noblepayne/boltz-client-flake";
  #     inputs.nixpkgs.follows = "nixpkgs";
  #   };
  #
  # Overlay entry (add to your nixpkgs overlays):
  #
  #   boltz-client = boltz-client-flake.packages.${system}.default;
  #
  # This makes pkgs.boltz-client available system-wide.
  # lnd/lncli comes from nixpkgs directly -- no overlay needed.
  # ──────────────────────────────────────────────────────────────────────

  # --- Bootstrap secret directories on every nixos-rebuild switch ---
  #
  # This only creates directories and a symlink.  It never writes secret
  # file contents.  The operator must provision the actual credential
  # files manually (see WRAPPERS.md for details).
  system.activationScripts.boltz-client-bootstrap = lib.stringAfter [ "users" ] ''
    install -d -m 0755 -o ${userName} -g ${userGroup} "${userHome}/.config/boltz-client"
    install -d -m 0700 -o ${userName} -g ${userGroup} "${userHome}/.config/secrets/boltz-client"
    install -d -m 0700 -o ${userName} -g ${userGroup} "${userHome}/.config/secrets/lnd-mynode"
    install -d -m 0700 -o ${userName} -g ${userGroup} "${userHome}/.boltz"

    ln -sfn "${userHome}/.config/secrets/boltz-client/boltz.toml" "${userHome}/.boltz/boltz.toml"
    chown -h ${userName}:${userGroup} "${userHome}/.boltz/boltz.toml"
  '';

  # --- Install packages + wrappers ---
  environment.systemPackages = [
    pkgs.lnd              # LND daemon + lncli (from nixpkgs)
    pkgs.boltz-client     # Boltz client + boltzcli (from flake overlay)
    lncli-mynode          # SSH-tunnel wrapper for lncli
    boltzcli-mynode       # SSH-tunnel wrapper for boltzcli
  ];
}
