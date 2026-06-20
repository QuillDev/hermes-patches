# Hermes Patches

Paper/Spigot-style downstream patch repository for Quill/Nako Hermes Agent changes.

This repo intentionally does not contain a Hermes source checkout. It records:

- the upstream target in `targets/hermes.yaml`
- ordered patch files in `patches/hermes/`
- scripts for applying, rebuilding, checking, updating, and running the patched tree

Local source worktrees are created under `.work/` and ignored by git.

## Daily commands

```bash
# Fetch/cache upstream
scripts/sync-upstream

# Create .work/hermes-patched from configured upstream base + patches
scripts/apply-patches

# Edit a patch
scripts/edit-patch
cd .work/hermes-patched
# modify files, amend/rebase/create commits
cd ../..
scripts/rebuild-patches
scripts/check-patches --verify

# Update against latest upstream/main without changing metadata
scripts/update-upstream --dry-run --verify

# Update target metadata and patched worktree after a clean dry-run
scripts/update-upstream --yes --verify
scripts/rebuild-patches
scripts/check-patches --verify

# Run patched Hermes
scripts/run-hermes
```

## Conflict repair

If `scripts/update-upstream` or `scripts/apply-patches` fails, the script leaves the failing worktree in place and prints its path. Repair there with normal Git commands (`git status`, edit files, `git add`, `git am --continue`), then rebuild patches from the repaired commits.

`git rerere` is enabled in generated worktrees so repeated upstream conflicts can be reused.

## Current target

See `targets/hermes.yaml`. The initial patch set was ported from `/tmp/hermes-patch-stack/patches/hermes`. The old in-source patch-stack tooling patch was intentionally not kept as a Hermes runtime patch; this external repo owns that tooling now.
