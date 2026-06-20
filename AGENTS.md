# Hermes Patches Agent Guide

This repository is the canonical Quill/Nako downstream patch repository for Hermes Agent. It is intentionally a Paper/Spigot-style patch repo: it stores target metadata, patch files, and tooling. It must not become a Hermes source fork.

## Non-negotiable rules

1. Do not commit Hermes source into this repo.
2. Do not edit `.work/` files and call the job done. `.work/` is ignored scratch state. Durable changes must become commits in `.work/hermes-patched`, then patch files via `scripts/rebuild-patches`, then a normal commit in this repo.
3. Do not hand-edit `patches/hermes/*.patch` unless you are deliberately repairing patch metadata and then immediately verify with `scripts/check-patches`.
4. Do not change `targets/hermes.yaml` `base_commit` by hand during an upstream update. Use `scripts/update-upstream --yes` after a clean dry-run.
5. Do not use the old `/tmp/hermes-patch-stack` or `/Users/quill/.hermes/hermes-agent` fork workflow for new work unless the user explicitly asks to inspect or recover old state.
6. Before claiming success, run patch application verification and at least targeted tests or a smoke run from patched Hermes.
7. Commit messages for Quill/Nako work must include:

```text
Co-authored-by: Nako <280596805+nakoagent@users.noreply.github.com>
```

## Repository layout

```text
AGENTS.md                 # This guide.
README.md                 # User-facing quick reference.
targets/hermes.yaml       # Upstream URL, branch, base commit, worktree paths, default commands.
patches/hermes/series     # Ordered list of patch files to apply.
patches/hermes/*.patch    # Downstream Hermes changes as git-format patches.
scripts/lib/common.sh     # Shared script config and safety helpers.
scripts/sync-upstream     # Fetch/cache upstream.
scripts/apply-patches     # Create `.work/hermes-patched` and apply `series`.
scripts/rebuild-patches   # Export patches from commits in `.work/hermes-patched`.
scripts/check-patches     # Validate scripts, series, patch application, optional tests.
scripts/update-upstream   # Dry-run or accept a new upstream base.
scripts/edit-patch        # Print the edit workflow.
scripts/run-hermes        # Install/sync deps and run patched Hermes.
.work/                    # Ignored local cache/worktrees. Never commit.
```

## Target model

The current target is `targets/hermes.yaml`:

```text
upstream_url: https://github.com/NousResearch/hermes-agent.git
upstream_branch: main
base_commit: <current upstream commit patches are based on>
patch_dir: patches/hermes
upstream_cache: .work/upstream.git
patched_worktree: .work/hermes-patched
run_cmd: uv run hermes
```

Treat `base_commit` as the exact upstream commit that `patches/hermes/series` is known to apply to. `scripts/update-upstream` is responsible for changing it.

## Fresh checkout bootstrap

From the repository root:

```bash
cd /Users/quill/projects/hermes-patches

git status --short --branch
scripts/sync-upstream
scripts/apply-patches
scripts/check-patches --skip-verify
```

Expected behavior:

1. `.work/upstream.git` is cloned or fetched from upstream.
2. `.work/hermes-patched` is created from `targets/hermes.yaml` `base_commit`.
3. Every patch listed in `patches/hermes/series` applies with `git am -3`.
4. `scripts/check-patches --skip-verify` reports script syntax ok, series matches patch files, and patch series applies.

If `scripts/apply-patches` refuses because `.work/hermes-patched` has tracked changes, inspect it first:

```bash
cd .work/hermes-patched
git status --short
git log --oneline --decorate --max-count=20
```

Do not delete or reset dirty work unless the user confirms it is disposable.

## Run patched Hermes

Use the wrapper from the patch repo root:

```bash
scripts/run-hermes "--version"
scripts/run-hermes "chat -Q --toolsets safe -q 'Reply with exactly: OK'"
scripts/run-hermes
```

What `scripts/run-hermes` does:

1. Creates `.work/hermes-patched` with `scripts/apply-patches` if missing.
2. Runs `uv sync --extra dev --extra messaging` in `.work/hermes-patched` when `uv` is available.
3. Executes the configured `run_cmd` from `targets/hermes.yaml`, currently `uv run hermes`.

Do not run stock Hermes from `/Users/quill/.hermes/hermes-agent` when the user asks to run the patched instance from this repo.

## Add a new downstream patch

Use this when implementing a new Quill/Nako Hermes change.

1. Start clean in the patch repo:

```bash
cd /Users/quill/projects/hermes-patches
git status --short --branch
scripts/apply-patches
```

2. Move into the patched source worktree:

```bash
cd .work/hermes-patched
git status --short --branch
git log --oneline --reverse $(cd ../.. && python3 - <<'PY'
import re
text=open('targets/hermes.yaml').read()
print(re.search(r'^base_commit:\s*(\S+)', text, re.M).group(1))
PY
)..HEAD
```

3. Make the source/test changes inside `.work/hermes-patched` only.

4. Run focused tests from `.work/hermes-patched` before committing the patch commit:

```bash
uv run --extra dev --extra messaging python -m pytest <focused tests> -q -o addopts=
```

5. Commit the new downstream patch in `.work/hermes-patched`:

```bash
git add <changed source and tests>
git commit -m "feat(scope): concise patch subject" \
  -m "Co-authored-by: Nako <280596805+nakoagent@users.noreply.github.com>"
```

6. Return to the patch repo and rebuild patch files:

```bash
cd /Users/quill/projects/hermes-patches
scripts/rebuild-patches
```

7. Verify the generated patch stack:

```bash
scripts/check-patches --verify
```

If the default verify command is too broad or too narrow for the change, use an explicit command:

```bash
scripts/check-patches --verify-cmd 'uv run --extra dev --extra messaging python -m pytest <focused tests> -q -o addopts='
```

8. Commit the patch repo update:

```bash
git status --short
git add patches/hermes targets/hermes.yaml README.md AGENTS.md scripts
git commit -m "feat(scope): add Hermes downstream patch" \
  -m "Co-authored-by: Nako <280596805+nakoagent@users.noreply.github.com>"
git push
```

Only stage files that actually changed. Do not stage `.work/`.

## Modify an existing patch

Use this when a patch needs a small correction or cleanup.

1. Recreate the patched worktree:

```bash
cd /Users/quill/projects/hermes-patches
scripts/apply-patches
```

2. Inspect patch commits:

```bash
cd .work/hermes-patched
BASE=$(cd ../.. && python3 - <<'PY'
import re
text=open('targets/hermes.yaml').read()
print(re.search(r'^base_commit:\s*(\S+)', text, re.M).group(1))
PY
)
git log --oneline --reverse "$BASE..HEAD"
```

3. Start an interactive rebase from the base commit:

```bash
git rebase -i "$BASE"
```

4. Mark the target patch commit as `edit`.

5. Make the correction, stage it, and amend the patch commit:

```bash
git add <files>
git commit --amend --no-edit
```

6. Continue the rebase:

```bash
git rebase --continue
```

7. Run focused tests in `.work/hermes-patched`:

```bash
uv run --extra dev --extra messaging python -m pytest <focused tests> -q -o addopts=
```

8. Rebuild and verify from the patch repo root:

```bash
cd /Users/quill/projects/hermes-patches
scripts/rebuild-patches
scripts/check-patches --verify-cmd 'uv run --extra dev --extra messaging python -m pytest <focused tests> -q -o addopts='
```

9. Commit and push the changed patch files:

```bash
git add patches/hermes
git commit -m "fix(scope): update Hermes downstream patch" \
  -m "Co-authored-by: Nako <280596805+nakoagent@users.noreply.github.com>"
git push
```

## Rebuild patches after worktree commits

Run this only after `.work/hermes-patched` has committed downstream changes and no tracked working-tree changes:

```bash
cd /Users/quill/projects/hermes-patches
scripts/rebuild-patches
```

The script:

1. Confirms `.work/hermes-patched` exists.
2. Refuses to run if `.work/hermes-patched` has uncommitted tracked changes.
3. Confirms `targets/hermes.yaml` `base_commit` is an ancestor of patched `HEAD`.
4. Runs `git format-patch --no-stat --zero-commit base_commit..HEAD`.
5. Replaces `patches/hermes/*.patch` and `patches/hermes/series`.

After rebuilding, always run:

```bash
scripts/check-patches --skip-verify
```

Then run focused tests with `--verify` or `--verify-cmd` before finalizing.

## Check patches

Fast structural check:

```bash
scripts/check-patches --skip-verify
```

Full default check:

```bash
scripts/check-patches --verify
```

Focused check:

```bash
scripts/check-patches --verify-cmd 'uv run --extra dev --extra messaging python -m pytest <tests> -q -o addopts='
```

What the checker verifies:

1. Patch scripts parse with `bash -n`.
2. `patches/hermes/series` exactly matches the patch files present.
3. A fresh temp worktree can be created at `base_commit`.
4. The series applies cleanly with `git am -3`.
5. If `.work/hermes-patched` exists and is clean, the checked tree is compared with it outside `.git`.
6. Optional verification command passes.

Known caveat: broad TUI tests may be environment/flakiness-sensitive. Prefer patch-relevant focused tests plus a patched-Hermes smoke run unless the change specifically touches TUI behavior.

## Update to latest upstream

Always dry-run first:

```bash
cd /Users/quill/projects/hermes-patches
scripts/update-upstream --dry-run --verify
```

If the default verify command is not appropriate, use:

```bash
scripts/update-upstream --dry-run --verify-cmd 'uv run --extra dev --extra messaging python -m pytest <focused tests> -q -o addopts='
```

If dry-run passes and the user wants to accept the new upstream base:

```bash
scripts/update-upstream --yes --verify
scripts/rebuild-patches
scripts/check-patches --verify
```

Then commit and push:

```bash
git add targets/hermes.yaml patches/hermes
git commit -m "chore: update Hermes patches to latest upstream" \
  -m "Co-authored-by: Nako <280596805+nakoagent@users.noreply.github.com>"
git push
```

What `scripts/update-upstream --yes` does:

1. Fetches upstream.
2. Finds latest `upstream_branch` from the local upstream cache.
3. Applies the current patch series onto that latest commit in a temp worktree.
4. Runs optional verification.
5. Updates `targets/hermes.yaml` `base_commit`.
6. Moves the successful temp worktree to `.work/hermes-patched`.

Run `scripts/rebuild-patches` afterward so patch metadata reflects the new base and any conflict-resolution changes.

## Repair patch conflicts during upstream update

If `scripts/update-upstream` fails, it prints and preserves the temp worktree path. Do not start over blindly.

1. Enter the printed worktree:

```bash
cd /path/printed/by/script
```

2. Inspect the failure:

```bash
git status
git am --show-current-patch=diff | sed -n '1,200p'
```

3. Resolve conflicted files. Preserve both upstream intent and downstream patch intent. Do not choose one side without reading the surrounding code.

4. Stage resolutions and continue:

```bash
git add <resolved files>
git am --continue
```

5. Repeat until all patches apply.

6. Run focused tests in the repaired worktree:

```bash
uv run --extra dev --extra messaging python -m pytest <focused tests> -q -o addopts=
```

7. Replace `.work/hermes-patched` with the repaired worktree only after confirming it is the intended result. If doing this manually, preserve any existing `.work/hermes-patched` dirty work first.

8. Update `targets/hermes.yaml` `base_commit` to the upstream commit used by the repaired worktree only if the update is accepted. Prefer rerunning `scripts/update-upstream --yes` after `git rerere` learned the conflict resolution.

9. Rebuild, verify, commit, and push:

```bash
cd /Users/quill/projects/hermes-patches
scripts/rebuild-patches
scripts/check-patches --verify-cmd 'uv run --extra dev --extra messaging python -m pytest <focused tests> -q -o addopts='
git add targets/hermes.yaml patches/hermes
git commit -m "chore: refresh Hermes patches for upstream update" \
  -m "Co-authored-by: Nako <280596805+nakoagent@users.noreply.github.com>"
git push
```

## Repair patch conflicts during normal apply

If `scripts/apply-patches` fails, it leaves `.work/hermes-patched` in the failed state.

1. Inspect:

```bash
cd /Users/quill/projects/hermes-patches/.work/hermes-patched
git status
git am --show-current-patch=diff | sed -n '1,200p'
```

2. Resolve conflicts, then continue:

```bash
git add <resolved files>
git am --continue
```

3. When all patches are applied, run tests:

```bash
uv run --extra dev --extra messaging python -m pytest <focused tests> -q -o addopts=
```

4. Rebuild and verify patch files:

```bash
cd /Users/quill/projects/hermes-patches
scripts/rebuild-patches
scripts/check-patches --verify-cmd 'uv run --extra dev --extra messaging python -m pytest <focused tests> -q -o addopts='
```

## Verification before final response

Before telling the user work is complete, collect real output for:

```bash
git status --short --branch
scripts/check-patches --skip-verify
scripts/check-patches --verify-cmd 'uv run --extra dev --extra messaging python -m pytest <focused tests> -q -o addopts='
scripts/run-hermes "--version"
scripts/run-hermes "chat -Q --toolsets safe -q 'Reply with exactly: OK'"
```

For documentation-only changes in this repo, at minimum run:

```bash
bash -n scripts/{sync-upstream,apply-patches,rebuild-patches,check-patches,update-upstream,edit-patch,run-hermes} scripts/lib/common.sh
git status --short --branch
```

## Push policy

This repo has remote `origin` at `git@github.com:QuillDev/hermes-patches.git`.

After successful verification:

```bash
git push
```

Never force-push this patch repo unless the user explicitly asks and you have shown the current remote state and local divergence. Normal patch updates should be ordinary commits on `main`.
