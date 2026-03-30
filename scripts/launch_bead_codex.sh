#!/usr/bin/env bash
set -euo pipefail

# Automatically activate a Poetry-managed environment when one can be
# resolved for the current repository. Repositories without Poetry stay on the
# normal PATH.

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

activate_poetry_env_if_available() {
  [[ -f "$REPO_ROOT/pyproject.toml" ]] || return 0
  command -v poetry >/dev/null 2>&1 || return 0

  local poetry_env
  poetry_env="$(poetry env info --path 2>/dev/null)" || return 0
  if [[ "$poetry_env" =~ ^[A-Za-z]:\\ ]] && command -v cygpath >/dev/null 2>&1; then
    poetry_env="$(cygpath -u "$poetry_env")"
  fi
  [[ -n "$poetry_env" && -d "$poetry_env" ]] || return 0

  local venv_bin
  if [[ -d "$poetry_env/bin" ]]; then
    venv_bin="$poetry_env/bin"
  elif [[ -d "$poetry_env/Scripts" ]]; then
    venv_bin="$poetry_env/Scripts"
  else
    return 0
  fi

  export VIRTUAL_ENV="$poetry_env"
  export POETRY_ACTIVE=1
  export PATH="$venv_bin:$PATH"
}

require_cmd git
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "Not inside a git repository."
cd "$REPO_ROOT"

for cmd in bd codex jq; do
  require_cmd "$cmd"
done

BASE_BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)" || fail "Detached HEAD detected. Check out a branch before launching Codex."

CLAIMED_ID=""
LAST_ERROR=""

for attempt in 1 2 3; do
  READY_STDERR_FILE="$(mktemp)" || fail "Failed to allocate temporary file for bd ready stderr."
  if ! READY_JSON="$(bd ready --json 2>"$READY_STDERR_FILE")"; then
    READY_ERROR="$(<"$READY_STDERR_FILE")"
    rm -f "$READY_STDERR_FILE"
    fail "bd ready --json failed: ${READY_ERROR:-$READY_JSON}"
  fi
  if [[ -s "$READY_STDERR_FILE" ]]; then
    cat "$READY_STDERR_FILE" >&2
  fi
  rm -f "$READY_STDERR_FILE"

  CANDIDATE_IDS=()
  while IFS= read -r candidate_id; do
    [[ -n "$candidate_id" ]] && CANDIDATE_IDS+=("$candidate_id")
  done < <(
    printf '%s\n' "$READY_JSON" |
      jq -r '
        if type == "array" then .[]
        elif type == "object" then .
        else empty
        end
        | .id? // empty
      '
  )

  if ((${#CANDIDATE_IDS[@]} == 0)); then
    if [[ -n "$LAST_ERROR" ]]; then
      fail "No bead could be claimed after $((attempt - 1)) retries. Last claim error: $LAST_ERROR"
    fi
    fail "No ready beads available to claim."
  fi

  CANDIDATE_ID="${CANDIDATE_IDS[0]}"
  CLAIM_STDERR_FILE="$(mktemp)" || fail "Failed to allocate temporary file for bd update stderr."
  if CLAIM_OUTPUT="$(bd update "$CANDIDATE_ID" --claim --json 2>"$CLAIM_STDERR_FILE")"; then
    if [[ -s "$CLAIM_STDERR_FILE" ]]; then
      cat "$CLAIM_STDERR_FILE" >&2
    fi
    rm -f "$CLAIM_STDERR_FILE"
    CLAIMED_ID="$CANDIDATE_ID"
    break
  fi

  CLAIM_ERROR="$(<"$CLAIM_STDERR_FILE")"
  rm -f "$CLAIM_STDERR_FILE"
  LAST_ERROR="${CLAIM_ERROR:-$CLAIM_OUTPUT}"
  echo "Claim attempt $attempt/3 failed for bead $CANDIDATE_ID: $LAST_ERROR" >&2
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

bd worktree create "$WORKTREE_REL" --branch "$TASK_BRANCH"

echo "Claimed bead: $CLAIMED_ID"
echo "Base branch: $BASE_BRANCH"
echo "Worktree: $WORKTREE_PATH"

activate_poetry_env_if_available

export BEADS_DIR="$REPO_ROOT"

codex --cd "$WORKTREE_REL" "bead $CLAIMED_ID has been claimed for you to work on in the current git branch and worktree, please work on it, close the bead when you're done"
