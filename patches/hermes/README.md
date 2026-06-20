# Quill/Nako Hermes patch stack

This directory contains Quill/Nako downstream patches for Hermes Agent.

The patch repo is the source of truth. Hermes source is not vendored here; scripts create ignored local worktrees under `.work/` and apply this `series` on top of the configured upstream target in `targets/hermes.yaml`.

Daily workflow:

```bash
scripts/apply-patches
# edit .work/hermes-patched
scripts/rebuild-patches
scripts/check-patches --verify
```

Update workflow:

```bash
scripts/update-upstream --dry-run
scripts/update-upstream --yes --verify
```

Do not hand-edit generated `.patch` files unless deliberately repairing a broken patch. Prefer editing commits in `.work/hermes-patched`, then run `scripts/rebuild-patches`.
