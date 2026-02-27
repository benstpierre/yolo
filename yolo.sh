#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
YOLO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$YOLO_DIR/projects.conf"

# Colors
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
CYAN='\033[36m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

# --- Read projects.conf ---
declare -a P_ALIASES=()
declare -a P_REPOS=()
declare -a P_DIRS=()

while IFS='|' read -r alias repo dir; do
  [[ "$alias" =~ ^#.*$ || -z "$alias" ]] && continue
  P_ALIASES+=("$alias")
  P_REPOS+=("$repo")
  P_DIRS+=("$dir")
done < "$CONF"

# --- Resolve which project we're working with ---
PROJECT_ALIAS=""
PROJECT_REPO=""
PROJECT_DIR=""

if [ $# -ge 1 ]; then
  # Alias provided as argument
  for idx in "${!P_ALIASES[@]}"; do
    if [ "${P_ALIASES[$idx]}" = "$1" ]; then
      PROJECT_ALIAS="${P_ALIASES[$idx]}"
      PROJECT_REPO="${P_REPOS[$idx]}"
      PROJECT_DIR="${P_DIRS[$idx]}"
      shift
      break
    fi
  done

  if [ -z "$PROJECT_ALIAS" ]; then
    printf "${RED}Unknown project: %s${RESET}\n" "$1"
    printf "Known projects: %s\n" "${P_ALIASES[*]}"
    return 2>/dev/null || exit 1
  fi
else
  # No args — show project picker
  echo ""
  printf "${BOLD}yolo — pick a project${RESET}\n"
  echo ""

  for idx in "${!P_ALIASES[@]}"; do
    num=$((idx + 1))
    printf "  ${CYAN}%d)${RESET} ${BOLD}%s${RESET}  ${DIM}%s${RESET}\n" "$num" "${P_ALIASES[$idx]}" "${P_REPOS[$idx]}"
  done

  echo ""
  printf "Pick [1-%d]: " "${#P_ALIASES[@]}"
  read -r proj_choice

  if ! [[ "$proj_choice" =~ ^[0-9]+$ ]] || [ "$proj_choice" -lt 1 ] || [ "$proj_choice" -gt "${#P_ALIASES[@]}" ]; then
    echo "Invalid selection."
    return 2>/dev/null || exit 1
  fi

  pick=$((proj_choice - 1))
  PROJECT_ALIAS="${P_ALIASES[$pick]}"
  PROJECT_REPO="${P_REPOS[$pick]}"
  PROJECT_DIR="${P_DIRS[$pick]}"
fi

# --- First-time setup: bare clone if needed ---
BARE_REPO="$PROJECT_DIR/.repo"

if [ ! -d "$PROJECT_DIR" ]; then
  printf "Creating holder directory: ${BOLD}%s${RESET}\n" "$PROJECT_DIR"
  mkdir -p "$PROJECT_DIR"
fi

if [ ! -d "$BARE_REPO" ]; then
  printf "First run for ${BOLD}%s${RESET} — cloning bare repo...\n" "$PROJECT_ALIAS"
  git clone --bare "https://github.com/${PROJECT_REPO}.git" "$BARE_REPO"
fi

# --- Collect worktrees sorted by most recent commit ---
declare -a WT_DIRS=()
declare -a WT_NAMES=()
declare -a WT_TIMES=()
declare -a WT_AGES=()

for dir in "$PROJECT_DIR"/*/; do
  [ -e "$dir/.git" ] || continue
  name=$(basename "$dir")
  # epoch of most recent commit
  epoch=$(git -C "$dir" log -1 --format='%ct' 2>/dev/null || echo "0")
  age=$(git -C "$dir" log -1 --format='%cr' 2>/dev/null || echo "unknown")
  WT_DIRS+=("$dir")
  WT_NAMES+=("$name")
  WT_TIMES+=("$epoch")
  WT_AGES+=("$age")
done

# Sort by commit time (newest first)
if [ ${#WT_DIRS[@]} -gt 0 ]; then
  # Build sortable lines, sort, then re-read
  declare -a SORTED_INDICES=()
  sorted=$(
    for idx in "${!WT_TIMES[@]}"; do
      echo "${WT_TIMES[$idx]} $idx"
    done | sort -rn | awk '{print $2}'
  )
  while read -r i; do
    SORTED_INDICES+=("$i")
  done <<< "$sorted"
fi

# --- Display menu ---
echo ""
printf "${BOLD}🚀 %s${RESET}  ${DIM}(%s)${RESET}\n" "$PROJECT_ALIAS" "$PROJECT_REPO"
echo ""

if [ ${#WT_DIRS[@]} -eq 0 ]; then
  printf "  ${DIM}No branches yet. Use 'i' to create one from a GitHub issue.${RESET}\n"
else
  for pos in "${!SORTED_INDICES[@]}"; do
    idx="${SORTED_INDICES[$pos]}"
    num=$((pos + 1))
    printf "  ${CYAN}%d)${RESET} %-50s ${DIM}%s${RESET}\n" "$num" "${WT_NAMES[$idx]}" "${WT_AGES[$idx]}"
  done
fi

echo ""
printf "  ${GREEN}i)${RESET} New branch from GitHub issue\n"
printf "  ${RED}d)${RESET} Delete a branch\n"
echo ""

# --- Prompt ---
max=${#WT_DIRS[@]}
if [ "$max" -gt 0 ]; then
  printf "Pick [1-%d, i, d]: " "$max"
else
  printf "Pick [i, d]: "
fi
read -r choice

case "$choice" in
  # --- New branch from GitHub issue ---
  i|I)
    printf "Issue number: "
    read -r issue_num

    if [ -z "$issue_num" ]; then
      echo "No issue number provided."
      return 2>/dev/null || exit 1
    fi

    printf "Fetching issue #%s... " "$issue_num"
    title=$(gh issue view "$issue_num" --repo "$PROJECT_REPO" --json title -q .title 2>/dev/null)

    if [ -z "$title" ]; then
      printf "\n${RED}Could not fetch issue #%s${RESET}\n" "$issue_num"
      return 2>/dev/null || exit 1
    fi

    printf "\"${BOLD}%s${RESET}\"\n" "$title"

    # Slugify: lowercase, replace non-alphanum with dash, collapse, trim
    slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')
    slug=$(echo "$slug" | cut -c1-60 | sed 's/-$//')
    branch_name="${issue_num}-${slug}"

    echo ""
    printf "Creating branch: ${BOLD}%s${RESET}\n" "$branch_name"

    # Fetch latest main
    git -C "$BARE_REPO" fetch origin main:main 2>/dev/null

    # Create worktree
    git -C "$BARE_REPO" worktree add "$PROJECT_DIR/$branch_name" -b "$branch_name" main

    printf "${GREEN}Done ✓${RESET}\n\n"
    printf "Launching Claude in ${BOLD}%s/${RESET}...\n" "$branch_name"
    cd "$PROJECT_DIR/$branch_name"
    claude --dangerously-skip-permissions "$@"
    ;;

  # --- Delete a branch ---
  d|D)
    if [ "$max" -eq 0 ]; then
      echo "No branches to delete."
      return 2>/dev/null || exit 1
    fi

    printf "Delete which branch? [1-%d]: " "$max"
    read -r del_choice

    if ! [[ "$del_choice" =~ ^[0-9]+$ ]] || [ "$del_choice" -lt 1 ] || [ "$del_choice" -gt "$max" ]; then
      echo "Invalid selection."
      return 2>/dev/null || exit 1
    fi

    del_pos=$((del_choice - 1))
    del_idx="${SORTED_INDICES[$del_pos]}"
    del_dir="${WT_DIRS[$del_idx]}"
    del_name="${WT_NAMES[$del_idx]}"

    printf "Remove ${BOLD}%s${RESET}? [y/N]: " "$del_name"
    read -r confirm

    if [[ "$confirm" =~ ^[yY]$ ]]; then
      git -C "$BARE_REPO" worktree remove "$del_dir" --force 2>/dev/null || rm -rf "$del_dir"
      git -C "$BARE_REPO" branch -D "$del_name" 2>/dev/null || true
      printf "${GREEN}Removed ✓${RESET}\n"
    else
      echo "Cancelled."
    fi
    ;;

  # --- Pick an existing worktree ---
  *)
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$max" ]; then
      echo "Invalid selection."
      return 2>/dev/null || exit 1
    fi

    pick_pos=$((choice - 1))
    pick_idx="${SORTED_INDICES[$pick_pos]}"
    pick_dir="${WT_DIRS[$pick_idx]}"
    pick_name="${WT_NAMES[$pick_idx]}"

    printf "\nLaunching Claude in ${BOLD}%s/${RESET}...\n" "$pick_name"
    cd "$pick_dir"
    claude --dangerously-skip-permissions "$@"
    ;;
esac
