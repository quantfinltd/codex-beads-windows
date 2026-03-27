#!/usr/bin/env bash
set -euo pipefail

# Set CODEX_BEAD_ACTIVATE_POETRY=1 to opt into Poetry environment activation.
# Leave it unset to run the launcher without Poetry installed.

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

should_activate_poetry() {
  case "${CODEX_BEAD_ACTIVATE_POETRY:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

activate_poetry_env() {
  require_cmd poetry

  local poetry_env
  poetry_env="$(poetry env info --path 2>/dev/null)" || fail "Poetry activation was requested via CODEX_BEAD_ACTIVATE_POETRY, but the environment could not be resolved. Leave it unset to run without Poetry."
  if [[ "$poetry_env" =~ ^[A-Za-z]:\\ ]] && command -v cygpath >/dev/null 2>&1; then
    poetry_env="$(cygpath -u "$poetry_env")"
  fi
  [[ -d "$poetry_env" ]] || fail "Poetry activation was requested via CODEX_BEAD_ACTIVATE_POETRY, but the environment does not exist: $poetry_env"

  local venv_bin
  if [[ -d "$poetry_env/bin" ]]; then
    venv_bin="$poetry_env/bin"
  elif [[ -d "$poetry_env/Scripts" ]]; then
    venv_bin="$poetry_env/Scripts"
  else
    fail "Poetry activation was requested via CODEX_BEAD_ACTIVATE_POETRY, but no executable directory exists under $poetry_env"
  fi

  export VIRTUAL_ENV="$poetry_env"
  export POETRY_ACTIVE=1
  export PATH="$venv_bin:$PATH"
}

require_cmd git
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "Not inside a git repository."
cd "$REPO_ROOT"

for cmd in bd codex; do
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

if should_activate_poetry; then
  activate_poetry_env
fi

export BEADS_DIR="$REPO_ROOT"

codex --cd "$WORKTREE_REL" "bead $CLAIMED_ID has been claimed for you to work on in the current git branch and worktree, please work on it"
