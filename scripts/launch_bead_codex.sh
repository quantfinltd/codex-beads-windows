#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

require_cmd git
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "Not inside a git repository."
cd "$REPO_ROOT"

for cmd in bd codex poetry; do
  require_cmd "$cmd"
done

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN=python
else
  fail "Missing required command: python3 (or python) for parsing bd JSON output."
fi

BASE_BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)" || fail "Detached HEAD detected. Check out a branch before launching Codex."
POETRY_ENV="$(poetry env info --path 2>/dev/null)" || fail "Unable to resolve the Poetry environment for this repo."
if [[ "$POETRY_ENV" =~ ^[A-Za-z]:\\ ]] && command -v cygpath >/dev/null 2>&1; then
  POETRY_ENV="$(cygpath -u "$POETRY_ENV")"
fi
[[ -d "$POETRY_ENV" ]] || fail "Poetry environment does not exist: $POETRY_ENV"

if [[ -d "$POETRY_ENV/bin" ]]; then
  VENV_BIN="$POETRY_ENV/bin"
elif [[ -d "$POETRY_ENV/Scripts" ]]; then
  VENV_BIN="$POETRY_ENV/Scripts"
else
  fail "Poetry environment executable directory does not exist under $POETRY_ENV"
fi

CLAIMED_ID=""
LAST_ERROR=""

for attempt in 1 2 3; do
  READY_JSON="$(bd ready --json 2>&1)" || fail "bd ready --json failed: $READY_JSON"

  CANDIDATE_IDS=()
  while IFS= read -r candidate_id; do
    [[ -n "$candidate_id" ]] && CANDIDATE_IDS+=("$candidate_id")
  done < <(
    "$PYTHON_BIN" -c 'import json, sys
data = json.load(sys.stdin)
if isinstance(data, list):
    for item in data:
        if isinstance(item, dict) and item.get("id"):
            print(item["id"])' <<<"$READY_JSON"
  )

  if ((${#CANDIDATE_IDS[@]} == 0)); then
    if [[ -n "$LAST_ERROR" ]]; then
      fail "No bead could be claimed after $((attempt - 1)) retries. Last claim error: $LAST_ERROR"
    fi
    fail "No ready beads available to claim."
  fi

  CANDIDATE_ID="${CANDIDATE_IDS[0]}"
  if CLAIM_OUTPUT="$(bd update "$CANDIDATE_ID" --claim --json 2>&1)"; then
    CLAIMED_ID="$CANDIDATE_ID"
    break
  fi

  LAST_ERROR="$CLAIM_OUTPUT"
  echo "Claim attempt $attempt/3 failed for bead $CANDIDATE_ID: $CLAIM_OUTPUT" >&2
done

[[ -n "$CLAIMED_ID" ]] || fail "Unable to claim a bead after 3 attempts. Last claim error: $LAST_ERROR"

WORKTREES_DIR="$REPO_ROOT/.worktrees"
WORKTREE_REL=".worktrees/$CLAIMED_ID"
WORKTREE_PATH="$WORKTREES_DIR/$CLAIMED_ID"
TASK_BRANCH="agent/$CLAIMED_ID"

mkdir -p "$WORKTREES_DIR"
[[ ! -e "$WORKTREE_PATH" ]] || fail "Worktree path already exists: $WORKTREE_PATH"

# Fail instead of guessing whether reusing an existing agent branch is safe.
if git show-ref --verify --quiet "refs/heads/$TASK_BRANCH"; then
  fail "Branch already exists: $TASK_BRANCH"
fi

git worktree add "$WORKTREE_REL" -b "$TASK_BRANCH" "$BASE_BRANCH"

echo "Claimed bead: $CLAIMED_ID"
echo "Base branch: $BASE_BRANCH"
echo "Worktree: $WORKTREE_PATH"

export VIRTUAL_ENV="$POETRY_ENV"
export POETRY_ACTIVE=1
export PATH="$VENV_BIN:$PATH"

codex --cd "$WORKTREE_REL" "bead $CLAIMED_ID has been claimed for you to work on in the current git branch and worktree, please work on it"
