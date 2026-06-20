#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET_FILE="${TARGET_FILE:-$REPO_ROOT/targets/hermes.yaml}"

step() { printf '==> %s\n' "$*"; }
ok() { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

cfg() {
  local key="$1"
  python3 - "$TARGET_FILE" "$key" <<'PY'
import re, sys
path, key = sys.argv[1], sys.argv[2]
pat = re.compile(rf'^{re.escape(key)}:\s*(.*)\s*$')
with open(path, 'r', encoding='utf-8') as f:
    for line in f:
        m = pat.match(line)
        if m:
            val = m.group(1).strip()
            if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
                val = val[1:-1]
            print(val)
            sys.exit(0)
sys.exit(1)
PY
}

repo_path() {
  local p="$1"
  case "$p" in
    /*) printf '%s\n' "$p" ;;
    *) printf '%s/%s\n' "$REPO_ROOT" "$p" ;;
  esac
}

safe_relative_dir() {
  local p="$1"
  case "$p" in
    ''|'.'|'/'|'..'|../*|*/../*) die "refusing unsafe path: $p" ;;
  esac
}

UPSTREAM_URL="$(cfg upstream_url)"
UPSTREAM_BRANCH="$(cfg upstream_branch)"
BASE_COMMIT="$(cfg base_commit)"
PATCH_DIR_REL="$(cfg patch_dir)"
WORK_DIR_REL="$(cfg work_dir)"
UPSTREAM_CACHE_REL="$(cfg upstream_cache)"
UPSTREAM_WORKTREE_REL="$(cfg upstream_worktree)"
PATCHED_WORKTREE_REL="$(cfg patched_worktree)"
DEFAULT_VERIFY_CMD="$(cfg default_verify_cmd || true)"
RUN_CMD="$(cfg run_cmd || true)"

PATCH_DIR="$(repo_path "$PATCH_DIR_REL")"
WORK_DIR="$(repo_path "$WORK_DIR_REL")"
UPSTREAM_CACHE="$(repo_path "$UPSTREAM_CACHE_REL")"
UPSTREAM_WORKTREE="$(repo_path "$UPSTREAM_WORKTREE_REL")"
PATCHED_WORKTREE="$(repo_path "$PATCHED_WORKTREE_REL")"

safe_relative_dir "$PATCH_DIR_REL"
safe_relative_dir "$WORK_DIR_REL"
safe_relative_dir "$UPSTREAM_CACHE_REL"
safe_relative_dir "$UPSTREAM_WORKTREE_REL"
safe_relative_dir "$PATCHED_WORKTREE_REL"

ensure_upstream_cache() {
  mkdir -p "$WORK_DIR"
  if [[ ! -d "$UPSTREAM_CACHE" ]]; then
    step "Cloning upstream mirror"
    git clone --bare --single-branch --branch "$UPSTREAM_BRANCH" "$UPSTREAM_URL" "$UPSTREAM_CACHE"
  else
    git --git-dir="$UPSTREAM_CACHE" remote set-url origin "$UPSTREAM_URL" >/dev/null 2>&1 || true
    step "Fetching upstream branch"
    git --git-dir="$UPSTREAM_CACHE" fetch --prune origin "+refs/heads/$UPSTREAM_BRANCH:refs/heads/$UPSTREAM_BRANCH" "+refs/tags/*:refs/tags/*"
  fi
  git --git-dir="$UPSTREAM_CACHE" config rerere.enabled true
  git --git-dir="$UPSTREAM_CACHE" config rerere.autoupdate true
}

ensure_clean_or_remove_worktree() {
  local path="$1"
  if [[ -d "$path/.git" || -f "$path/.git" ]]; then
    if [[ -n "$(git -C "$path" status --porcelain --untracked-files=no 2>/dev/null || true)" ]]; then
      die "tracked changes present in $path; commit/stash them or remove the worktree yourself"
    fi
    git --git-dir="$UPSTREAM_CACHE" worktree remove --force "$path" >/dev/null 2>&1 || rm -rf "$path"
  elif [[ -e "$path" ]]; then
    die "$path exists but is not a git worktree; refusing to overwrite"
  fi
}

add_detached_worktree() {
  local path="$1" ref="$2"
  ensure_clean_or_remove_worktree "$path"
  mkdir -p "$(dirname "$path")"
  git --git-dir="$UPSTREAM_CACHE" worktree add --detach "$path" "$ref"
  git -C "$path" config rerere.enabled true
  git -C "$path" config rerere.autoupdate true
}

apply_series_in() {
  local worktree="$1"
  [[ -f "$PATCH_DIR/series" ]] || die "missing $PATCH_DIR/series"
  while IFS= read -r patch_name || [[ -n "$patch_name" ]]; do
    [[ -z "$patch_name" || "$patch_name" == \#* ]] && continue
    [[ -f "$PATCH_DIR/$patch_name" ]] || die "series references missing patch: $patch_name"
  done < "$PATCH_DIR/series"
  (cd "$worktree" && git am -3 $(sed '/^\s*#/d;/^\s*$/d' "$PATCH_DIR/series" | sed "s#^#$PATCH_DIR/#"))
}

current_upstream_ref() {
  git --git-dir="$UPSTREAM_CACHE" rev-parse "refs/heads/$UPSTREAM_BRANCH"
}

update_base_commit_in_target() {
  local new_base="$1"
  python3 - "$TARGET_FILE" "$new_base" <<'PY'
import re, sys
path, new_base = sys.argv[1], sys.argv[2]
text = open(path, 'r', encoding='utf-8').read()
text2 = re.sub(r'^base_commit:\s*.*$', f'base_commit: {new_base}', text, flags=re.M)
if text2 == text:
    raise SystemExit('base_commit not found')
open(path, 'w', encoding='utf-8').write(text2)
PY
}
