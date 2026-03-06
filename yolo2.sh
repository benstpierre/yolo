#!/usr/bin/env bash
# yolo2 — bash picks project + shows branches, Claude handles everything after.
#
# Add to ~/.bash_profile:
#   yolo2() { source "/usr/local/code/claude-native/yolo-holder/main/yolo2.sh" "$@"; }

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
      shift
      break
    fi
  done
  if [ -z "$PROJECT_ALIAS" ]; then
    printf "\033[31mUnknown project: %s\033[0m\n" "$1"
    printf "Known projects: %s\n" "${P_ALIASES[*]}"
    return 2>/dev/null || exit 1
  fi
else
  echo ""
  printf "${BOLD}yolo2 — pick a project${RESET}\n"
  echo ""
  for idx in "${!P_ALIASES[@]}"; do
    num=$((idx + 1))
    printf "  ${CYAN}%d)${RESET} ${BOLD}%-6s${RESET} ${DIM}%s${RESET}\n" "$num" "${P_ALIASES[$idx]}" "${P_REPOS[$idx]}"
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

# --- Gather worktrees for this project ---
SNAPSHOT="PROJECT: ${PROJECT_ALIAS} | ${PROJECT_REPO} | ${PROJECT_DIR}"
declare -a ROW_EPOCH=()
declare -a ROW_NAME=()
declare -a ROW_MSG=()
declare -a ROW_AGE=()
declare -a ROW_STATUS=()

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
  done
fi

# --- Print branch list (sorted by recency) and build snapshot in same order ---
echo ""
printf "${BOLD}${PROJECT_ALIAS}${RESET}  ${DIM}${PROJECT_REPO}${RESET}\n"
echo ""

if [ ${#ROW_EPOCH[@]} -eq 0 ]; then
  printf "  ${DIM}No branches yet.${RESET}\n"
else
  sorted=$(for i in "${!ROW_EPOCH[@]}"; do echo "${ROW_EPOCH[$i]} $i"; done | sort -rn | awk '{print $2}')
  num=1
  while read -r idx; do
    printf "  ${CYAN}%d)${RESET} %-40s ${DIM}%s${RESET}" "$num" "${ROW_NAME[$idx]}" "${ROW_AGE[$idx]}"
    [ "${ROW_STATUS[$idx]}" = "dirty" ] && printf "  ${BOLD}*${RESET}"
    echo ""
    SNAPSHOT="${SNAPSHOT}\nWORKTREE: #${num} ${ROW_NAME[$idx]} | ${ROW_MSG[$idx]} | ${ROW_AGE[$idx]} | ${ROW_STATUS[$idx]} | ${PROJECT_DIR}/${ROW_NAME[$idx]}/"
    num=$((num + 1))
  done <<< "$sorted"
fi

echo ""
printf "${DIM}Tell Claude what you want to do...${RESET}\n"
echo ""

# --- Launch Claude with context ---
cd "$YOLO2_DIR"
claude --dangerously-skip-permissions --model sonnet --append-system-prompt "$(printf "The user just saw branches for project '${PROJECT_ALIAS}' printed by bash. Do NOT reprint the list. Just respond to whatever they say next.\n\n${SNAPSHOT}")" "$@"
