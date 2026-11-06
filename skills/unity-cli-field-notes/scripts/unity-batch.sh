#!/usr/bin/env bash
# usage: unity-batch.sh <project> <op>...   op: compile | EditMode | PlayMode | method:Ns.Class.Method
# env:   UNITY=<editor binary> (default: from ProjectVersion.txt)  OUT=<log dir> (default /tmp/unity-batch)  FILTER=<test filter>
set -uo pipefail
project="$(cd "${1:?project path}" && pwd)"; shift
version="$(awk '/m_EditorVersion:/{print $2}' "$project/ProjectSettings/ProjectVersion.txt")"
unity="${UNITY:-$HOME/Unity/Hub/Editor/$version/Editor/Unity}"
out="${OUT:-/tmp/unity-batch}"; mkdir -p "$out"
[ -x "$unity" ] || { echo "no Unity $version at $unity; set UNITY" >&2; exit 1; }
if pgrep -af 'Unity' | grep -F -- "$project" | grep -vq 'unity-batch'; then
  echo "an Editor already has $project open; use the live Editor or a different project" >&2; exit 1
fi
status=0
for op in "$@"; do
  tag="$(basename "$project")-${op//[:.\/]/_}"; log="$out/$tag.log"; xml="$out/$tag.xml"; rm -f "$xml"
  case "$op" in
    EditMode|PlayMode) "$unity" -batchmode -nographics -projectPath "$project" -runTests -testPlatform "$op" -testResults "$xml" ${FILTER:+-testFilter "$FILTER"} -logFile "$log" ;;
    compile) "$unity" -batchmode -nographics -quit -projectPath "$project" -logFile "$log" ;;
    method:*) "$unity" -batchmode -nographics -quit -projectPath "$project" -executeMethod "${op#method:}" -logFile "$log" ;;
    *) echo "unknown op $op" >&2; exit 1 ;;
  esac
  code=$?; [ "$code" -ne 0 ] && status=$code
  errors="$(grep -c 'error CS' "$log" 2>/dev/null || true)"
  counts=""; [ -f "$xml" ] && counts="$(grep -o '<test-run [^>]*' "$xml" | grep -oE '(total|passed|failed|skipped)="[0-9]+"' | tr '\n' ' ')"
  echo "$op exit=$code errorCS=${errors:-0} $counts log=$log"
done
exit $status
