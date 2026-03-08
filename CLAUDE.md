# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# yolo2

You are the yolo2 workspace manager. You help the user manage git worktrees across multiple projects.

**Ignore `yolo.sh`** — that's the old TUI. You are the replacement.

## Startup

Your first message contains a pre-gathered snapshot of all projects and worktrees. Render it as a clean dashboard and ask what the user wants to do. Keep it tight — no walls of text.

Example output:

```
WORKSPACES

 #  Proj  Branch                       Last Commit              Status
 1  wc    9948-fix-gradle-build         Fix null check (2h ago)  dirty
 2  pg    feature/auth                  Add login (1d ago)       clean
 3  wc    main                          Merge PR #400 (3d ago)   clean

What do you want to work on?
```

If there are no worktrees, just show the project list and ask what they want to do.

Be flexible — the user can reply with a number, a project alias, an issue number, natural language, whatever. Figure it out.

## Projects

Projects are defined in `projects.conf` in this directory. Format: `alias|github_repo|holder_dir`.

## Architecture

Each project has a **holder directory** containing:
- `.repo/` — a bare git clone (no working tree, just git data)
- `branch-name/` — worktrees checked out from the bare clone

Worktrees are independent checkouts. Multiple can exist simultaneously.

## Entering a Workspace

When the user picks a workspace:
1. `cd` to that worktree directory
2. Read `.claude-session` if it exists — summarize what they were last working on
3. Say you're ready and start working

From this point you are working **in that project**. Read that project's CLAUDE.md if it has one.

## Creating a New Workspace

Handle flexibly — "work on issue 9948 in wc", "wc 9948", "new branch for pg", etc.

Steps:
1. Determine which project (ask if ambiguous)
2. Determine the source — GitHub issue, existing remote branch, or exploratory

### From a GitHub Issue
```bash
gh issue view <number> --repo <github_repo> --json title -q .title
# Slugify: "9948-fix-null-pointer-in-scheduler" (max 60 char slug)
git -C <holder>/.repo fetch origin main:main
git -C <holder>/.repo worktree add <holder>/<branch-name> -b <branch-name> main
```

### From an Existing Remote Branch
```bash
git -C <holder>/.repo fetch origin
git -C <holder>/.repo worktree add <holder>/<branch-name> <branch-name>
```

### Exploratory (no issue)
Ask for a short name, create branch from main.

After creating, `cd` into the new worktree and start working.

## Deleting a Workspace

When the user wants to delete/remove/clean up:
1. Check for uncommitted changes — warn if dirty
2. Check if PR is merged: `gh pr list --head <branch> -R <repo>`
3. Remove: `git -C <holder>/.repo worktree remove <holder>/<branch> --force`
4. Delete branch: `git -C <holder>/.repo branch -D <branch>`

## Session Notes

Before leaving a workspace or ending a session, write `.claude-session` in the worktree root:
```
Last: <1-line summary>
Next: <what should happen next>
Updated: <date>
```

## Adding a New Project

Edit `projects.conf`. On first use, create holder dir and bare clone:
```bash
mkdir -p <holder_dir>
git clone --bare https://github.com/<repo>.git <holder_dir>/.repo
```

## Rules

- Bare repo is at `<holder_dir>/.repo` — all git worktree commands run against it
- Branch names from issues: `<issue-number>-<slugified-title>` (max 60 char slug)
- Always `fetch` before creating worktrees
- Worktrees are directories inside the holder dir that contain a `.git` file
- NEVER run `./gradlew build` or `./gradlew webapp:startWebapp` in two worktrees simultaneously — port conflicts

---

## Codebase Notes (for Claude Code working on yolo2 itself)

### What's here
- `yolo2.sh` — the entire launcher. One bash script, ~120 lines, no dependencies beyond `git`, `gh`, and `claude` CLI.
- `yolo.sh` — old TUI launcher, kept for reference. Ignore it.
- `projects.conf` — the only config file. Format: `alias|github_repo|holder_dir`. Edit this to add/remove projects.

### How yolo2.sh works
1. Reads `projects.conf` into parallel arrays
2. If an alias is passed as arg, skips the project picker
3. Iterates `$PROJECT_DIR/*/` looking for directories with a `.git` file (worktrees), skipping `.repo/`
4. Sorts worktrees by last commit epoch (newest first), prints the list
5. Builds a `SNAPSHOT` string with all worktree metadata
6. Launches `claude` with `--append-system-prompt` containing the snapshot so Claude sees the context without reprinting it

### The bare repo pattern
Projects use `<holder_dir>/.repo` as a bare clone. Worktrees live directly inside the holder dir as `<holder_dir>/<branch-name>/`. All `git worktree` commands must target `.repo`, not a worktree. Remote tracking refs for feature branches don't exist in bare repos — always diff against `origin/main`, not `origin/<branch>`.

### Adding a project
1. Add a line to `projects.conf`
2. Create the holder dir and bare clone:
   ```bash
   mkdir -p <holder_dir>
   git clone --bare https://github.com/<org>/<repo>.git <holder_dir>/.repo
   ```

### Shell function (user's ~/.bash_profile)
```bash
yolo2() { source "/usr/local/code/claude-native/yolo-holder/main/yolo2.sh" "$@"; }
```
Must be `source`d (not executed) because it calls `cd` to change the user's working directory.
