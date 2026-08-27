#!/bin/bash
# Status line derived from bash PS1: '[\u@\h \W]\$ '
# Top line : session name
# Bottom   : [user@host dir]  branch  context-bar  model (effort)
input=$(cat)

# --- ANSI colors ---
RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
RED=$'\033[31m'; MAGENTA=$'\033[35m'; BLUE=$'\033[34m'; GRAY=$'\033[90m'

user=$(whoami)
host=$(hostname -s)
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // empty')
[ -z "$cwd" ] && cwd=$(pwd)
dir=$(basename "$cwd")

model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty')
session=$(printf '%s' "$input" | jq -r '.session_name // empty')
ctx=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
# tokens currently in context (input-only, matching used_percentage)
ctok=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // empty')

# branch (via git; the JSON has no plain branch field for the main working tree)
branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
# dirty flag: * when the working tree has uncommitted changes
dirty=""
if [ -n "$branch" ] && [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ]; then
  dirty="*"
fi

# --- top line: session name ---
top=""
[ -n "$session" ] && top="${MAGENTA}${BOLD}${session}${RESET}"

# --- bottom line ---
bottom="${GRAY}[${RESET}${CYAN}${user}${GRAY}@${RESET}${CYAN}${host}${RESET} ${BOLD}${dir}${RESET}${GRAY}]${RESET}"

if [ -n "$branch" ]; then
  if [ -n "$dirty" ]; then bc=$YELLOW; else bc=$GREEN; fi
  bottom="${bottom}  ${bc} ${branch}${dirty}${RESET}"
fi

if [ -n "$ctx" ]; then
  pct=${ctx%.*}
  [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
  if   [ "$pct" -ge 80 ]; then c=$RED
  elif [ "$pct" -ge 50 ]; then c=$YELLOW
  else c=$GREEN; fi
  filled=$(( (pct + 6) / 12 )); [ "$filled" -gt 8 ] && filled=8
  bar=""; i=0
  while [ $i -lt 8 ]; do
    if [ $i -lt $filled ]; then bar="${bar}▓"; else bar="${bar}░"; fi
    i=$((i+1))
  done
  # compact token count: <1000 as-is, <10k one decimal K, else integer K
  tok=""
  if [[ "$ctok" =~ ^[0-9]+$ ]] && [ "$ctok" -gt 0 ]; then
    if   [ "$ctok" -lt 1000 ];  then tok="${ctok}"
    elif [ "$ctok" -lt 10000 ]; then tok="$(( ctok / 1000 )).$(( (ctok % 1000) / 100 ))K"
    else tok="$(( (ctok + 500) / 1000 ))K"; fi
  fi
  bottom="${bottom}  ${c}${bar} ${pct}%${RESET}"
  [ -n "$tok" ] && bottom="${bottom}${DIM} (${tok} Tokens)${RESET}"
  bottom="${bottom}${DIM} ctx${RESET}"
fi

[ -n "$model" ]  && bottom="${bottom}  ${BLUE}${model}${RESET}"
[ -n "$effort" ] && bottom="${bottom} ${DIM}(${effort})${RESET}"

# --- print (top line only when a session name exists) ---
if [ -n "$top" ]; then
  printf '%s\n%s' "$top" "$bottom"
else
  printf '%s' "$bottom"
fi
