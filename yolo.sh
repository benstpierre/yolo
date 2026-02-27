#!/usr/bin/env bash

YOLO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$YOLO_DIR/projects.conf"

# --- Colors ---
BOLD=$'\033[1m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RESET=$'\033[0m'

# --- Load projects from conf ---
declare -a PROJ_ALIAS=() PROJ_REPO=() PROJ_HOLDER=()

section=""
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  if [[ "$line" =~ ^\[projects\] ]]; then section="projects"; continue; fi
  if [[ "$line" =~ ^\[ ]]; then section=""; continue; fi

  if [ "$section" = "projects" ]; then
    IFS='|' read -r alias repo holder <<< "$line"
    [ -z "$alias" ] && continue
    PROJ_ALIAS+=("$alias")
    PROJ_REPO+=("$repo")
    PROJ_HOLDER+=("$holder")
  fi
done < "$CONF"

# --- Helper: launch claude in a directory ---
launch() {
  local dir="$1"
  shift
  local branch
  branch=$(git -C "$dir" branch --show-current 2>/dev/null || basename "$dir")
  printf "\nLaunching Claude in ${BOLD}%s${RESET}...\n" "$branch"
  cd "$dir" && claude --dangerously-skip-permissions "$@"
}

# --- Helper: resolve flexible input ---
resolve_input() {
  local input="$1" holder="$2" repo="$3" bare="$4"
  shift 4

  # Strip GitHub URL to extract issue # or branch name
  if [[ "$input" =~ github\.com/.*/issues/([0-9]+) ]]; then
    input="${BASH_REMATCH[1]}"
  elif [[ "$input" =~ github\.com/.*/tree/(.+) ]]; then
    input="${BASH_REMATCH[1]}"
  fi

  # Check existing worktrees for prefix match
  for dir in "$holder"/*/; do
    [ -e "$dir/.git" ] || continue
    local name
    name=$(basename "$dir")
    [ "$name" = ".repo" ] && continue
    if [[ "$name" == "$input"* ]]; then
      launch "$dir" "$@"
      return
    fi
  done

  # Try as issue number
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    local title
    title=$(gh issue view "$input" --repo "$repo" --json title -q .title 2>/dev/null)
    if [ -n "$title" ]; then
      local slug branch
      slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-60 | sed 's/-$//')
      branch="${input}-${slug}"
      echo "Creating worktree for issue #${input}: ${title}"
      git -C "$bare" fetch origin main:main 2>/dev/null
      git -C "$bare" worktree add "$holder/$branch" -b "$branch" main
      if [ -d "$holder/$branch" ]; then
        launch "$holder/$branch" "$@"
        return
      fi
    fi
  fi

  # Try as remote branch name
  echo "Trying as remote branch: $input"
  git -C "$bare" fetch origin "$input" 2>/dev/null
  git -C "$bare" worktree add "$holder/$input" "$input" 2>/dev/null
  if [ -d "$holder/$input" ]; then
    launch "$holder/$input" "$@"
    return
  fi

  echo "Could not resolve: $input"
  return 1
}

# --- Helper: show project action menu ---
show_project_menu() {
  local alias="$1" repo="$2" holder="$3"
  shift 3
  # remaining args passed to claude

  local bare="$holder/.repo"
  local display_name
  display_name=$(echo "$alias" | tr '[:lower:]' '[:upper:]')

  # Scan worktrees
  declare -a wt_path=() wt_branch=() wt_dirty=() wt_title=() wt_pr=() wt_epoch=()

  while IFS='|' read -r type palias path branch dirty title pr epoch; do
    [ "$type" = "WT" ] || continue
    [ "$palias" = "$alias" ] || continue
    wt_path+=("$path")
    wt_branch+=("$branch")
    wt_dirty+=("$dirty")
    wt_title+=("$title")
    wt_pr+=("$pr")
    wt_epoch+=("$epoch")
  done < <(bash "$YOLO_DIR/yolo-scan.sh")

  # Sort by epoch (newest first)
  declare -a sorted=()
  if [ ${#wt_epoch[@]} -gt 0 ]; then
    while read -r i; do
      sorted+=("$i")
    done < <(
      for idx in "${!wt_epoch[@]}"; do
        echo "${wt_epoch[$idx]} $idx"
      done | sort -rn | awk '{print $2}'
    )
  fi

  # Display
  echo ""
  printf "${BOLD}%s${RESET}  ${DIM}%s${RESET}\n" "$display_name" "$repo"
  echo ""

  local count=0
  declare -a pick_path=()

  for pos in "${sorted[@]}"; do
    count=$((count + 1))
    local branch="${wt_branch[$pos]}"
    local title="${wt_title[$pos]}"
    local pr="${wt_pr[$pos]}"

    [ ${#branch} -gt 30 ] && branch="${branch:0:27}..."
    [ ${#title} -gt 40 ] && title="${title:0:37}..."

    local pr_display=""
    case "$pr" in
      open)   pr_display="${GREEN}PR${RESET}" ;;
      draft)  pr_display="${YELLOW}Draft${RESET}" ;;
      merged) pr_display="${DIM}Merged${RESET}" ;;
    esac

    printf "  ${CYAN}%2d)${RESET} %-32s %-42s %s\n" \
      "$count" "$branch" "$title" "$pr_display"

    pick_path+=("${wt_path[$pos]}")
  done

  if [ "$count" -eq 0 ]; then
    printf "  ${DIM}No worktrees found.${RESET}\n"
  fi

  echo ""
  printf "  ${GREEN} m)${RESET} Work on main\n"
  printf "  ${GREEN} t)${RESET} New temp branch\n"
  printf "  ${DIM} b)${RESET} Back\n"
  echo ""
  printf "  ${DIM}Or enter issue #, branch name, or GitHub URL${RESET}\n"
  echo ""

  # Prompt
  printf "> "
  read -r choice

  case "$choice" in
    b|B)
      return 2  # signal to restart project picker
      ;;
    m|M)
      git -C "$bare" fetch origin main:main 2>/dev/null
      if [ -d "$holder/main" ]; then
        launch "$holder/main" "$@"
      else
        git -C "$bare" worktree add "$holder/main" main 2>/dev/null
        if [ -d "$holder/main" ]; then
          launch "$holder/main" "$@"
        else
          echo "Failed to check out main."
          return 1
        fi
      fi
      ;;
    t|T)
      local tmp_branch="tmp-$(date +%Y%m%d-%H%M%S)"
      echo "Creating temp branch: $tmp_branch"
      git -C "$bare" fetch origin main:main 2>/dev/null
      git -C "$bare" worktree add "$holder/$tmp_branch" -b "$tmp_branch" main
      if [ -d "$holder/$tmp_branch" ]; then
        launch "$holder/$tmp_branch" "$@"
      else
        echo "Failed to create temp branch."
        return 1
      fi
      ;;
    *)
      # Numbered pick
      if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
        local pick=$((choice - 1))
        launch "${pick_path[$pick]}" "$@"
      elif [ -n "$choice" ]; then
        # Smart resolve
        resolve_input "$choice" "$holder" "$repo" "$bare" "$@"
      else
        echo "No selection."
        return 1
      fi
      ;;
  esac
}

# --- Main ---

# Parse args: yolo [alias] [input]
ARG_ALIAS=""
ARG_INPUT=""
EXTRA_ARGS=()

if [ $# -ge 1 ]; then
  # Check if first arg is a known project alias
  for idx in "${!PROJ_ALIAS[@]}"; do
    if [ "$1" = "${PROJ_ALIAS[$idx]}" ]; then
      ARG_ALIAS="$1"
      shift
      break
    fi
  done
fi

if [ -n "$ARG_ALIAS" ] && [ $# -ge 1 ]; then
  ARG_INPUT="$1"
  shift
fi

EXTRA_ARGS=("$@")

# If alias + input given, skip all menus and resolve directly
if [ -n "$ARG_ALIAS" ] && [ -n "$ARG_INPUT" ]; then
  for idx in "${!PROJ_ALIAS[@]}"; do
    if [ "$ARG_ALIAS" = "${PROJ_ALIAS[$idx]}" ]; then
      resolve_input "$ARG_INPUT" "${PROJ_HOLDER[$idx]}" "${PROJ_REPO[$idx]}" "${PROJ_HOLDER[$idx]}/.repo" "${EXTRA_ARGS[@]}"
      exit $?
    fi
  done
fi

# If alias given (no input), skip project picker
if [ -n "$ARG_ALIAS" ]; then
  for idx in "${!PROJ_ALIAS[@]}"; do
    if [ "$ARG_ALIAS" = "${PROJ_ALIAS[$idx]}" ]; then
      show_project_menu "${PROJ_ALIAS[$idx]}" "${PROJ_REPO[$idx]}" "${PROJ_HOLDER[$idx]}" "${EXTRA_ARGS[@]}"
      exit $?
    fi
  done
fi

# Level 1: Project picker (loops on back)
while true; do
  echo ""
  printf "${BOLD}PROJECTS${RESET}\n"
  echo ""
  for idx in "${!PROJ_ALIAS[@]}"; do
    printf "  ${CYAN}%d)${RESET} %-6s ${DIM}%s${RESET}\n" $((idx + 1)) "${PROJ_ALIAS[$idx]}" "${PROJ_REPO[$idx]}"
  done
  echo ""

  printf "Pick: "
  read -r proj_choice

  local_idx=-1
  if [[ "$proj_choice" =~ ^[0-9]+$ ]] && [ "$proj_choice" -ge 1 ] && [ "$proj_choice" -le "${#PROJ_ALIAS[@]}" ]; then
    local_idx=$((proj_choice - 1))
  else
    for idx in "${!PROJ_ALIAS[@]}"; do
      if [ "$proj_choice" = "${PROJ_ALIAS[$idx]}" ]; then
        local_idx=$idx
        break
      fi
    done
  fi

  if [ "$local_idx" -ge 0 ] 2>/dev/null; then
    show_project_menu "${PROJ_ALIAS[$local_idx]}" "${PROJ_REPO[$local_idx]}" "${PROJ_HOLDER[$local_idx]}" "${EXTRA_ARGS[@]}"
    rc=$?
    [ "$rc" -eq 2 ] && continue  # back was pressed
    exit $rc
  else
    echo "Invalid selection."
    exit 1
  fi
done
