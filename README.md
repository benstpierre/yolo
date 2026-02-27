# yolo

Terminal launcher for managing multi-project git worktrees with [Claude Code](https://claude.ai/code).

## Setup

1. Clone this repo:
   ```bash
   git clone https://github.com/benstpierre/yolo.git /usr/local/code/claude-native/yolo
   ```

2. Add to your `~/.bash_profile`:
   ```bash
   yolo() {
     if [ -z "$ITERM_SESSION_ID" ]; then
       echo "Not in iTerm2. Refusing to yolo."
       return 1
     fi
     source "/usr/local/code/claude-native/yolo/yolo.sh" "$@"
   }
   ```

3. Edit `projects.conf` to register your projects.

## Usage

```bash
yolo          # pick a project, then pick a branch
yolo wc       # jump straight to waste-coordinator branches
yolo pg       # jump straight to planglobal branches
```

### Inside the branch menu

- **Number** — open that worktree in Claude Code
- **i** — create a new branch from a GitHub issue number
- **d** — delete a worktree

## projects.conf format

```
# alias|github_repo|holder_dir
wc|galateatech/waste-coordinator|/usr/local/code/sferion/galatea/waste-coordinator-holder
pg|sferioncorp/planglobal|/usr/local/code/sferion/planglobal/planglobal-holder
```
