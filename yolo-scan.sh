#!/usr/bin/env bash
# Scans all projects from projects.conf and outputs worktree data.
# Output format: WT|<proj_alias>|<path>|<branch>|<dirty>|<subject>|<relative_time>|<epoch>
# Also outputs: SC|<key>|<label>|<description> for shortcuts

YOLO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$YOLO_DIR/projects.conf"

section=""
while IFS= read -r line; do
  # Skip empty lines and comments
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

  # Detect section headers
  if [[ "$line" =~ ^\[projects\] ]]; then section="projects"; continue; fi
  if [[ "$line" =~ ^\[shortcuts\] ]]; then section="shortcuts"; continue; fi

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
      log=$(git -C "$dir" log -1 --format='%s|%cr|%ct' 2>/dev/null || echo "no commits|unknown|0")

      IFS='|' read -r subject rel_time epoch <<< "$log"
      echo "WT|$alias|$dir|$branch|${dirty:+dirty}|$subject|$rel_time|$epoch"
    done

  elif [ "$section" = "shortcuts" ]; then
    IFS='|' read -r key label desc <<< "$line"
    [ -z "$key" ] && continue
    echo "SC|$key|$label|$desc"
  fi
done < "$CONF"
