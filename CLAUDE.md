# yolo — worktree launcher

A bash-driven workspace launcher for multi-project worktree workflows. It provides a two-level menu (project picker → project action menu) and smart input resolution.

## How it works

- `yolo` → project picker → project action menu
- `yolo wc` → skip picker, straight to wc's action menu
- `yolo wc 9958` → skip both menus, resolve `9958` in wc context

The action menu shows existing worktrees and accepts:
- **Number** → open that worktree
- **`t`** → create temp branch from main
- **Issue number** (e.g. `9958`) → find matching worktree or create from GitHub issue
- **GitHub URL** → extract issue # or branch name and resolve

## Config

`projects.conf` has one section:

```
[projects]
alias|github_repo|holder_dir
```

## Holder directory structure

Each project's `holder_dir` contains:
- `.repo/` — bare git clone
- `<branch-name>/` — worktrees checked out from the bare clone

### First-time setup

If a project's `holder_dir` doesn't exist, create it and clone:
```bash
mkdir -p <holder_dir>
git clone --bare https://github.com/<github_repo>.git <holder_dir>/.repo
```

## Session notes

Before ending a session, write `.claude-session` in the worktree root:

```
Last: <1-line summary>
Next: <what should happen next>
Updated: <YYYY-MM-DD>
```

On entering a worktree, read this file and greet with context.

## Build safety

NEVER run `./gradlew build` or `./gradlew webapp:startWebapp` in two worktrees of the same project simultaneously — embedded Postgres and webapp ports will conflict.
