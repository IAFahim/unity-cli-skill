#!/usr/bin/env bash
set -euo pipefail

project="${1:-$PWD}"
limit="${2:-240}"
deadline=$((SECONDS + limit))
cmd=(unity --no-banner)

state() { "${cmd[@]}" status --project-path "$project" 2>/dev/null | tail -n +2 | awk 'NR==1{print $2}'; }
recompile() { "${cmd[@]}" command --caller plugin --skill unity-cli-field-notes --project-path "$project" script recompile_status 2>/dev/null | tail -1 | awk '{print $NF}'; }

failed() { "${cmd[@]}" command --caller plugin --skill unity-cli-field-notes --project-path "$project" console status 2>/dev/null | grep -q '"compilationFailed":true'; }

while [ "$SECONDS" -lt "$deadline" ]; do
  if [ "$(state)" = ready ]; then
    if failed; then echo "compilation failed: run console get --level error" >&2; exit 2; fi
    case "$(recompile)" in idle|completed|up_to_date) echo ready; exit 0 ;; esac
  fi
  sleep 4
done
echo "timeout after ${limit}s waiting for a ready Editor at $project" >&2
exit 1
