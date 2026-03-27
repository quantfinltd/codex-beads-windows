# AGENTS.md

## Interactive Sessions

* **NEVER** git push to remote
* **NEVER** git branch, you will be started in the branch you work in
* **ALWAYS** make intermediate commits if appropriate
* **ALWAYS** use detailed commit messages including context of why you made changes
* **NEVER** request escalated/out-of-sandbox execution just to bypass normal repo restrictions or gain broader access than needed.
   * If a command that should be safe inside the workspace fails due to a sandbox/runtime issue, you may retry with escalation only for the minimum command needed to continue
   * On Windows you will often encounter `windows sandbox: CreateProcessWithLogonW failed` errors which can be resolved with sandbox_permissions set to require_escalated
   * sandbox_permissions set to require_escalated is the only type of escalation allowed, and does not require explicit approval
* **NEVER** try and run commands to delete files or folders if you've encountered a permissions issue, flag these for manual cleanup
* **NEVER** try and use MCP tools to read files
* **ALWAYS** look for an appropriate agent to make any changes, built-in agents do not count
* **NEVER** try and claim a bead, you will always be told which one has been claimed for you
* **WHEN ASKED TO CREATE BEADS, ONLY CREATE THEM** - do not claim, take, or start working any bead unless the user explicitly asks for that.
* **WHEN WORKING ON A BEAD AND YOU FIND UNEXPECTED LOCAL MODIFICATIONS** - they are not your changes, ignore them

### Cleanup

- **ALWAYS** Cleanup after task completion
- **NEVER** throw away uncommitted changes
- **ALWAYS** Remove the task worktree after completion:

```
git worktree remove .worktrees/<task-id>
```
