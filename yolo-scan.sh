#!/usr/bin/env bash
# Scans all projects from projects.conf and outputs worktree data.
# Output format: WT|<proj_alias>|<path>|<branch>|<dirty>|<issue_title>|<pr_status>|<epoch>

YOLO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$YOLO_DIR/projects.conf"

# Collect worktrees first, then fetch GitHub data in parallel
declare -a entries=()

section=""
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  if [[ "$line" =~ ^\[projects\] ]]; then section="projects"; continue; fi
  if [[ "$line" =~ ^\[ ]]; then section=""; continue; fi

  if [ "$section" = "projects" ]; then
    IFS='|' read -r alias repo holder_dir <<< "$line"
    [ -z "$alias" ] && continue
    [ -d "$holder_dir" ] || continue

    for dir in "$holder_dir"/*/; do
      [ -d "$dir" ] || continue
      [ -e "$dir/.git" ] || continue
      name=$(basename "$dir")
      [ "$name" = ".repo" ] && continue

      branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "$name")
      dirty=$(git -C "$dir" status --porcelain 2>/dev/null | head -1)
      epoch=$(git -C "$dir" log -1 --format='%ct' 2>/dev/null || echo "0")

      # Extract issue number from branch name (leading digits)
      issue_num=""
      if [[ "$branch" =~ ^([0-9]+) ]]; then
        issue_num="${BASH_REMATCH[1]}"
      fi

      entries+=("$alias|$repo|$dir|$branch|${dirty:+dirty}|$epoch|$issue_num")
    done
  fi
done < "$CONF"

# Fetch issue titles and PR statuses in parallel
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

for i in "${!entries[@]}"; do
  IFS='|' read -r alias repo dir branch dirty epoch issue_num <<< "${entries[$i]}"

  # Fetch issue title
  if [ -n "$issue_num" ]; then
    (gh issue view "$issue_num" --repo "$repo" --json title -q .title 2>/dev/null > "$tmpdir/issue_$i") &
  fi

  # Fetch PR status for this branch
  (gh pr list --repo "$repo" --head "$branch" --json state,isDraft -q '.[0] | if .isDraft then "draft" elif .state == "OPEN" then "open" elif .state == "MERGED" then "merged" else .state end' 2>/dev/null > "$tmpdir/pr_$i") &
done
wait

# Output results
for i in "${!entries[@]}"; do
  IFS='|' read -r alias repo dir branch dirty epoch issue_num <<< "${entries[$i]}"

  issue_title=""
  if [ -f "$tmpdir/issue_$i" ]; then
    issue_title=$(cat "$tmpdir/issue_$i")
  fi
  # For main/tmp branches with no issue, use branch name as title
  if [ -z "$issue_title" ]; then
    if [ "$branch" = "main" ]; then
      issue_title="main"
    else
      issue_title="$branch"
    fi
  fi

  pr_status=""
  if [ -f "$tmpdir/pr_$i" ]; then
    pr_status=$(cat "$tmpdir/pr_$i")
  fi

  echo "WT|$alias|$dir|$branch|$dirty|$issue_title|$pr_status|$epoch"
done
