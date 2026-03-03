#!/usr/bin/env bash
# NOTE: This script is sourced, not executed. Do NOT use set -e/-u/-o pipefail
# as they would affect the caller's shell and crash the terminal on any failure.

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
  printf "Pick [1-%d] or Enter for pwd: " "${#P_ALIASES[@]}"
  read -r proj_choice

  if [ -z "$proj_choice" ]; then
    printf "\nLaunching Claude in ${BOLD}%s${RESET}...\n" "$(pwd)"
    claude --dangerously-skip-permissions "$@"
    return 2>/dev/null || exit 0
  fi

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
  printf "  ${DIM}No branches yet. Type an issue number to get started.${RESET}\n"
else
  for pos in "${!SORTED_INDICES[@]}"; do
    idx="${SORTED_INDICES[$pos]}"
    num=$((pos + 1))
    printf "  ${CYAN}%d)${RESET} %-50s ${DIM}%s${RESET}\n" "$num" "${WT_NAMES[$idx]}" "${WT_AGES[$idx]}"
  done
fi

echo ""
printf "  ${GREEN}i)${RESET} New branch from GitHub issue\n"
printf "  ${RED}rm)${RESET} Remove a branch\n"
echo ""

# --- Prompt ---
max=${#WT_DIRS[@]}
if [ "$max" -gt 0 ]; then
  printf "Pick [1-%d], issue #, or rm: " "$max"
else
  printf "Pick issue # or i: "
fi
read -r choice

# Normalize whitespace and lowercase
choice=$(echo "$choice" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')
# Strip leading # (e.g. "#9999" → "9999")
choice="${choice#\#}"
# "remove 12" / "rm 12" / "delete 12" → "rm12"
choice=$(echo "$choice" | sed 's/^remove[[:space:]]*/rm/; s/^delete[[:space:]]*/rm/; s/^rm[[:space:]]*/rm/')

# --- "i" means prompt for issue number, then treat same as typing the number ---
if [ "$choice" = "i" ]; then
  printf "Issue number: "
  read -r choice
  if [ -z "$choice" ]; then
    echo "No issue number provided."
    return 2>/dev/null || exit 1
  fi
fi

case "$choice" in
  # --- Remove a branch (rm, rm5, remove 12, delete 3, etc.) ---
  rm*)
    if [ "$max" -eq 0 ]; then
      echo "No branches to delete."
      return 2>/dev/null || exit 1
    fi

    del_num="${choice#rm}"

    if [ -z "$del_num" ]; then
      # Bare "rm" — ask which one
      printf "Remove which branch? [1-%d]: " "$max"
      read -r del_num
    fi

    if ! [[ "$del_num" =~ ^[0-9]+$ ]] || [ "$del_num" -lt 1 ] || [ "$del_num" -gt "$max" ]; then
      echo "Invalid selection."
      return 2>/dev/null || exit 1
    fi

    del_pos=$((del_num - 1))
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

  # --- Number: menu pick, existing worktree match, or new issue ---
  *)
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
      echo "Invalid selection."
      return 2>/dev/null || exit 1
    fi

    # 1) If it's a valid menu pick (1..max), use it
    if [ "$max" -gt 0 ] && [ "$choice" -ge 1 ] && [ "$choice" -le "$max" ]; then
      pick_pos=$((choice - 1))
      pick_idx="${SORTED_INDICES[$pick_pos]}"
      printf "\nLaunching Claude in ${BOLD}%s/${RESET}...\n" "${WT_NAMES[$pick_idx]}"
      cd "${WT_DIRS[$pick_idx]}"
      claude --dangerously-skip-permissions "$@"
      return 2>/dev/null || exit 0
    fi

    # 2) Check if an existing worktree starts with this number
    _found_idx=""
    for _i in "${!WT_NAMES[@]}"; do
      case "${WT_NAMES[$_i]}" in
        "${choice}"-*|"${choice}")
          _found_idx="$_i"
          break
          ;;
      esac
    done

    if [ -n "$_found_idx" ]; then
      printf "\nFound existing branch: ${BOLD}%s${RESET}\n" "${WT_NAMES[$_found_idx]}"
      printf "Launching Claude in ${BOLD}%s/${RESET}...\n" "${WT_NAMES[$_found_idx]}"
      cd "${WT_DIRS[$_found_idx]}"
      claude --dangerously-skip-permissions "$@"
      return 2>/dev/null || exit 0
    fi

    # 3) No existing worktree — check if branch already exists in bare repo
    _existing_branch=$(git -C "$BARE_REPO" for-each-ref --format='%(refname:short)' "refs/heads/${choice}-*" "refs/heads/${choice}" 2>/dev/null | head -1)

    if [ -n "$_existing_branch" ]; then
      # Branch exists in bare repo but no worktree — create worktree from it
      printf "\nFound existing branch: ${BOLD}%s${RESET}\n" "$_existing_branch"
      printf "Creating worktree...\n"
      git -C "$BARE_REPO" worktree add "$PROJECT_DIR/$_existing_branch" "$_existing_branch" || {
        printf "${RED}Failed to create worktree${RESET}\n"
        return 2>/dev/null || exit 1
      }
      printf "${GREEN}Done ✓${RESET}\n\n"
      printf "Launching Claude in ${BOLD}%s/${RESET}...\n" "$_existing_branch"
      cd "$PROJECT_DIR/$_existing_branch"
      claude --dangerously-skip-permissions "$@"
      return 2>/dev/null || exit 0
    fi

    # 4) No branch at all — fetch GitHub issue and create new branch
    printf "Fetching issue #%s... " "$choice"
    _title=$(gh issue view "$choice" --repo "$PROJECT_REPO" --json title -q .title 2>/dev/null) || true

    if [ -z "$_title" ]; then
      printf "\n${RED}Could not fetch issue #%s from %s${RESET}\n" "$choice" "$PROJECT_REPO"
      return 2>/dev/null || exit 1
    fi

    printf "\"${BOLD}%s${RESET}\"\n" "$_title"

    # Slugify: lowercase, replace non-alphanum with dash, collapse, trim
    _slug=$(echo "$_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')
    _slug=$(echo "$_slug" | cut -c1-60 | sed 's/-$//')
    _branch="${choice}-${_slug}"

    echo ""
    printf "Creating branch: ${BOLD}%s${RESET}\n" "$_branch"

    # Fetch latest default branch
    _default=$(git -C "$BARE_REPO" remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p')
    _default="${_default:-main}"
    git -C "$BARE_REPO" fetch origin "$_default:$_default" || {
      printf "\n${RED}Failed to fetch origin/%s${RESET}\n" "$_default"
      return 2>/dev/null || exit 1
    }

    git -C "$BARE_REPO" worktree add "$PROJECT_DIR/$_branch" -b "$_branch" "$_default" || {
      printf "\n${RED}Failed to create worktree${RESET}\n"
      return 2>/dev/null || exit 1
    }

    printf "${GREEN}Done ✓${RESET}\n\n"
    printf "Launching Claude in ${BOLD}%s/${RESET}...\n" "$_branch"
    cd "$PROJECT_DIR/$_branch"
    claude --dangerously-skip-permissions "$@"
    ;;
esac
