#!/usr/bin/env bash
# yolo2 — jump to a project worktree and launch Claude there.
#
# Add to ~/.bash_profile:
#   yolo2() { source "/usr/local/code/claude-native/yolo-holder/main/yolo2.sh" "$@"; }
#
# Usage:
#   yolo2              → pick project, then pick branch
#   yolo2 sfc          → pick branch in sfc
#   yolo2 sfc main     → jump directly to sfc/main

YOLO2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$YOLO2_DIR/projects.conf"

BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
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

# --- Project history (tracks last-used time per alias) ---
HISTORY_FILE="$YOLO2_DIR/.project_history"

_yolo2_record_project() {
  local a="$1"
  local epoch
  epoch=$(date +%s)
  local tmp
  tmp=$(mktemp)
  grep -v "^${a}|" "$HISTORY_FILE" 2>/dev/null > "$tmp" || true
  echo "${a}|${epoch}" >> "$tmp"
  mv "$tmp" "$HISTORY_FILE"
}

_yolo2_last_used() {
  local a="$1"
  grep "^${a}|" "$HISTORY_FILE" 2>/dev/null | cut -d'|' -f2 || echo "0"
}

# Build display order: sort project indices by last-used desc
declare -a P_DISPLAY_ORDER=()
while read -r idx; do
  P_DISPLAY_ORDER+=("$idx")
done < <(
  for i in "${!P_ALIASES[@]}"; do
    lu=$(_yolo2_last_used "${P_ALIASES[$i]}")
    echo "$lu ${P_REPOS[$i]} $i"
  done | sort -k1,1rn -k2,2 | awk '{print $NF}'
)

# --- Resolve project ---
PROJECT_ALIAS=""
PROJECT_REPO=""
PROJECT_DIR=""

if [ $# -ge 1 ]; then
  for idx in "${!P_ALIASES[@]}"; do
    if [ "${P_ALIASES[$idx]}" = "$1" ]; then
      PROJECT_ALIAS="${P_ALIASES[$idx]}"
      PROJECT_REPO="${P_REPOS[$idx]}"
      PROJECT_DIR="${P_DIRS[$idx]}"
      _yolo2_record_project "$PROJECT_ALIAS"
      shift
      break
    fi
  done
  if [ -z "$PROJECT_ALIAS" ]; then
    printf "\033[31mUnknown project: %s\033[0m\n" "$1"
    printf "Known projects: %s\n" "${P_REPOS[*]}"
    return 2>/dev/null || exit 1
  fi
else
  echo ""
  printf "${BOLD}yolo2 — pick a project${RESET}\n"
  echo ""
  num=1
  for idx in "${P_DISPLAY_ORDER[@]}"; do
    printf "  ${CYAN}%d)${RESET} ${DIM}%s${RESET}\n" "$num" "${P_REPOS[$idx]}"
    num=$((num + 1))
  done
  echo ""
  printf "Pick [1-%d]: " "${#P_ALIASES[@]}"
  read -r proj_choice

  if ! [[ "$proj_choice" =~ ^[0-9]+$ ]] || [ "$proj_choice" -lt 1 ] || [ "$proj_choice" -gt "${#P_ALIASES[@]}" ]; then
    echo "Invalid selection."
    return 2>/dev/null || exit 1
  fi

  pick_display=$((proj_choice - 1))
  pick="${P_DISPLAY_ORDER[$pick_display]}"
  PROJECT_ALIAS="${P_ALIASES[$pick]}"
  PROJECT_REPO="${P_REPOS[$pick]}"
  PROJECT_DIR="${P_DIRS[$pick]}"
  _yolo2_record_project "$PROJECT_ALIAS"
fi

# --- Gather worktrees for this project ---
declare -a ROW_EPOCH=()
declare -a ROW_NAME=()
declare -a ROW_MSG=()
declare -a ROW_AGE=()
declare -a ROW_STATUS=()
declare -a ROW_PATH=()

if [ -d "$PROJECT_DIR" ]; then
  for wt in "$PROJECT_DIR"/*/; do
    [ -e "$wt/.git" ] || continue
    name=$(basename "$wt")
    [ "$name" = ".repo" ] && continue
    epoch=$(git -C "$wt" log -1 --format='%ct' 2>/dev/null || echo "0")
    age=$(git -C "$wt" log -1 --format='%cr' 2>/dev/null || echo "unknown")
    msg=$(git -C "$wt" log -1 --format='%s' 2>/dev/null || echo "")
    dirty=$(git -C "$wt" status --porcelain 2>/dev/null | head -1)
    [ -n "$dirty" ] && s="dirty" || s="clean"
    ROW_EPOCH+=("$epoch")
    ROW_NAME+=("$name")
    ROW_MSG+=("$msg")
    ROW_AGE+=("$age")
    ROW_STATUS+=("$s")
    ROW_PATH+=("$wt")
  done
fi

# --- Build sorted index ---
declare -a SORTED_NAMES=()
declare -a SORTED_PATHS=()
declare -a SORTED_AGES=()
declare -a SORTED_STATUSES=()

if [ ${#ROW_EPOCH[@]} -gt 0 ]; then
  while read -r idx; do
    SORTED_NAMES+=("${ROW_NAME[$idx]}")
    SORTED_PATHS+=("${ROW_PATH[$idx]}")
    SORTED_AGES+=("${ROW_AGE[$idx]}")
    SORTED_STATUSES+=("${ROW_STATUS[$idx]}")
  done < <(for i in "${!ROW_EPOCH[@]}"; do echo "${ROW_EPOCH[$i]} $i"; done | sort -rn | awk '{print $2}')
fi

# --- If branch passed as arg, jump directly ---
TARGET_PATH=""
TARGET_NAME=""

if [ $# -ge 1 ]; then
  branch_arg="$1"
  candidate="$PROJECT_DIR/$branch_arg"
  if [ -d "$candidate" ] && [ -e "$candidate/.git" ]; then
    TARGET_PATH="$candidate"
    TARGET_NAME="$branch_arg"
  else
    printf "\033[31mBranch not found: %s\033[0m\n" "$branch_arg"
    return 2>/dev/null || exit 1
  fi
fi

# --- If only one branch and no arg, jump directly ---
if [ -z "$TARGET_PATH" ] && [ ${#SORTED_NAMES[@]} -eq 1 ]; then
  TARGET_PATH="${SORTED_PATHS[0]}"
  TARGET_NAME="${SORTED_NAMES[0]}"
fi

# --- Otherwise show menu and prompt ---
if [ -z "$TARGET_PATH" ]; then
  echo ""
  printf "${BOLD}${PROJECT_ALIAS}${RESET}  ${DIM}${PROJECT_REPO}${RESET}\n"
  echo ""

  if [ ${#SORTED_NAMES[@]} -eq 0 ]; then
    printf "  ${DIM}No branches yet.${RESET}\n"
    echo ""
    return 2>/dev/null || exit 0
  fi

  for i in "${!SORTED_NAMES[@]}"; do
    num=$((i + 1))
    printf "  ${CYAN}%d)${RESET} %-40s ${DIM}%s${RESET}" "$num" "${SORTED_NAMES[$i]}" "${SORTED_AGES[$i]}"
    [ "${SORTED_STATUSES[$i]}" = "dirty" ] && printf "  ${BOLD}*${RESET}"
    echo ""
  done

  echo ""
  printf "Pick branch [1-%d]: " "${#SORTED_NAMES[@]}"
  read -r branch_choice

  if [[ "$branch_choice" =~ ^[0-9]+$ ]] && [ "$branch_choice" -ge 1 ] && [ "$branch_choice" -le "${#SORTED_NAMES[@]}" ]; then
    idx=$((branch_choice - 1))
    TARGET_PATH="${SORTED_PATHS[$idx]}"
    TARGET_NAME="${SORTED_NAMES[$idx]}"
  elif [ -d "$PROJECT_DIR/$branch_choice" ] && [ -e "$PROJECT_DIR/$branch_choice/.git" ]; then
    TARGET_PATH="$PROJECT_DIR/$branch_choice"
    TARGET_NAME="$branch_choice"
  else
    echo "Invalid selection."
    return 2>/dev/null || exit 1
  fi
fi

# --- Jump there and launch Claude ---
echo ""
printf "${DIM}→ %s${RESET}\n" "$TARGET_PATH"
echo ""

cd "$TARGET_PATH"
claude --dangerously-skip-permissions --model sonnet || true
# Re-cd after claude exits (including Ctrl+C) so the shell lands here
cd "$TARGET_PATH"
printf "${DIM}pwd: %s${RESET}\n" "$TARGET_PATH"
