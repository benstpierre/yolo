# yolo

A terminal launcher for managing multi-project worktrees with Claude Code.

## What this is

`yolo` is a bash script that manages git bare-repo worktrees across multiple projects. It provides a TUI menu to:
- Pick a project (from `projects.conf`)
- Pick a branch/worktree (sorted by most recent commit)
- Create a new worktree from a GitHub issue
- Delete old worktrees
- Launch `claude --dangerously-skip-permissions` in the selected worktree

## Files

| File | Purpose |
|------|---------|
| `yolo.sh` | Main script — sourced by the bash_profile `yolo()` function |
| `projects.conf` | Project registry: `alias\|github_repo\|holder_dir` per line |
| `CLAUDE.md` | This file |
| `README.md` | User-facing docs |

## How it works

Each project has a **holder directory** containing:
- `.repo/` — a bare git clone
- `branch-name/` — worktrees created from the bare clone

The script reads `projects.conf` to know which projects exist and where they live.

## Usage

```bash
yolo          # project picker → branch picker → claude
yolo wc       # jump straight to waste-coordinator branches
yolo pg       # jump straight to planglobal branches
```

## Adding a project

Edit `projects.conf` and add a line:
```
alias|github_org/repo_name|/path/to/holder/dir
```

## Conventions

- Keep `yolo.sh` compatible with bash 3.2+ (macOS default) and bash 5+
- The script is `source`d (not executed) so `cd` affects the caller's shell
- Use `return` for early exits (not `exit`) since it runs in the caller's shell
