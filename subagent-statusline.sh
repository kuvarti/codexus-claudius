#!/bin/bash
# Renders each subagent row as: <title>  <Model> ·<effort>  <description>  <tokens>
# Input : JSON with a .tasks[] array. Per-task fields observed: id, label, description,
#         type, status, model, effort, tokenCount, contextWindowSize, cwd, startTime.
#         NOTE: .name is null for ad-hoc agents; the human-readable title lives in .label.
# Output: one JSON line per row -> {"id": "...", "content": "..."} (rendered as-is, ANSI ok)
input=$(cat)

# Session effort fallback: used when a task inherits the session effort (its own .effort is absent).
# Prefer the live session value from the input; fall back to the configured effortLevel.
sess=$(printf '%s' "$input" | jq -r '.effort.level // empty')
[ -z "$sess" ] && sess=$(jq -r '.effortLevel // empty' ~/.claude/settings.json 2>/dev/null)

printf '%s' "$input" | jq -rc --arg sess "$sess" '
  # claude-opus-4-8 -> "Opus 4.8", claude-haiku-4-5-20251001 -> "Haiku 4.5"
  def pretty:
    . as $m
    | ($m | ltrimstr("claude-") | split("-")) as $p
    | if ($p | length) >= 1 then
        (($p[0][0:1] | ascii_upcase) + $p[0][1:]) as $fam
        | ([ $p[1:][] | select(test("^[0-9]{1,2}$")) ] | join(".")) as $ver
        | if $ver == "" then $fam else $fam + " " + $ver end
      else $m end;

  def fmtok:
    if . == null or . == 0 then ""
    elif . < 1000 then (tostring) + "tok"
    else (((. / 100) | floor) / 10 | tostring) + "ktok" end;

  .tasks[]?
  # display title: .name is null for ad-hoc agents; human-readable text is in .label
  | ((.name // .label // .description // .type // "agent") | tostring)   as $title
  | ((.model // "") | if . == "" then "" else pretty end)               as $model
  # task effort as written; fall back to the session effort so it is always shown
  | ((.effort // $sess) | if type == "number" then tostring else . end) as $eff
  | (.tokenCount | fmtok)                                                as $tok
  # show description only when it adds something beyond the title
  | ((.description // "") | if . == $title then "" else . end)           as $desc
  | { id: .id,
      content: (
        "[1m" + $title + "[0m"
        + (if $model != "" then "  [34m" + $model + "[0m" else "" end)
        + (if $eff   != "" then " [2m·" + $eff + "[0m" else "" end)
        + (if $desc  != "" then "  [90m" + $desc + "[0m" else "" end)
        + (if $tok   != "" then "  [2m" + $tok + "[0m" else "" end)
      )
    }
'
