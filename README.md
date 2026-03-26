# codex-nft-forward

Docker-safe replacement for the old `nfter` domain-sync + save flow.

## Why this exists

- `nfter` updates rules incrementally by stored handle.
- If old rules are left behind, they can keep winning even after the domain resolves to a new IP.
- `nfter save_rules()` writes the whole live ruleset back into `/etc/nftables.conf`.
- On Docker hosts that can freeze Docker's dynamic rules into the wrong state or break them after reload.

## Design

- Remote state: `/etc/codex-nft-forward/mappings.json`
- Remote binary: `/usr/local/bin/codex-nft-forward`
- Managed nft tables:
  - `table ip codex_forward`
  - `table ip6 codex_forward`
- Managed chains:
  - `codex_prerouting`
  - `codex_postrouting`
- Persistence:
  - `codex-nft-forward.service` re-applies rules from state
  - `codex-nft-forward.timer` re-resolves domain targets on a fixed interval

This tool never saves the full ruleset to `/etc/nftables.conf`.
It deletes and rebuilds only its own tables.

## Local wrapper

Install helper + timer on a host:

```bash
bash ./codex-nft-forward.sh install my-host --interval 300
```

The wrapper uses standard `ssh` and respects `SSH_CONFIG_FILE` (default: `~/.ssh/config`).

Add or update a mapping:

```bash
bash ./codex-nft-forward.sh upsert \
  my-host tw-exit 32097 example.com 24997 all --family auto
```

Remove a mapping:

```bash
bash ./codex-nft-forward.sh remove my-host tw-exit
```

List configured mappings:

```bash
bash ./codex-nft-forward.sh list my-host
```

Re-apply immediately:

```bash
bash ./codex-nft-forward.sh apply my-host
```

Status:

```bash
bash ./codex-nft-forward.sh status my-host
```

## Migration note

- This tool uses an earlier nat priority than the old default chain, so it can coexist during migration.
- After verifying traffic is normal, delete the old `nfter` rules for the same local port to avoid long-term confusion.
