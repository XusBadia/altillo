#!/bin/zsh
# Measures Altillo's CPU while nothing happens and fails if it exceeds a budget (PLAN.md: < 0.1 % at rest).
#
#   script/idle-cpu.sh                                  # the Altillo that's running now, 20 s
#   script/idle-cpu.sh --launch build/dd/Build/Products/Debug/Altillo.app --scenario idleWithEars
#   script/idle-cpu.sh --seconds 60 --max 0.2
#
# Run it in the states that stay on screen for hours: notch closed, an agent waiting (knocking hand in the ear),
# music playing (equaliser), a timer ear. A looping animation shows up here as a steady few percent.
set -euo pipefail

app="" scenario="" seconds=20 max=0.5 settle=5
while (( $# )); do
  case $1 in
    --launch) app=$2; shift 2 ;;
    --scenario) scenario=$2; shift 2 ;;
    --seconds) seconds=$2; shift 2 ;;
    --max) max=$2; shift 2 ;;
    --settle) settle=$2; shift 2 ;;
    *) print -u2 "unknown option: $1"; exit 2 ;;
  esac
done

launched=""
if [[ -n $app ]]; then
  if pgrep -x Altillo >/dev/null; then
    print -u2 "Another Altillo is running; quit it first (two notches would skew the numbers)."
    exit 2
  fi
  args=()
  [[ -n $scenario ]] && args=(--args -designScenario "$scenario")
  open -n -g "$app" $args
  launched=1
  sleep 2
fi

pid=$(pgrep -x Altillo | head -1 || true)
if [[ -z $pid ]]; then
  print -u2 "Altillo isn't running."
  exit 2
fi
trap '[[ -n $launched ]] && kill $pid 2>/dev/null || true' EXIT

print "Altillo pid $pid: settling ${settle}s, then sampling ${seconds}s…"
sleep $settle
# top's first sample has no delta to compare with, so take one more and drop it.
samples=(${(f)"$(top -l $((seconds + 1)) -s 1 -pid $pid -stats cpu | awk '/^[0-9.]+$/ { print }' | tail -n +2)"})
if (( ${#samples} == 0 )); then
  print -u2 "top returned no samples."
  exit 2
fi
average=$(print -l $samples | awk '{ s += $1 } END { printf "%.2f", s / NR }')
peak=$(print -l $samples | sort -n | tail -1)
print "average ${average} %, peak ${peak} % over ${#samples} samples (budget ${max} %)"
if awk -v a=$average -v m=$max 'BEGIN { exit !(a > m) }'; then
  print -u2 "Over budget: something keeps animating or polling at rest."
  exit 1
fi
