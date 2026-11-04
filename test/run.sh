#!/usr/bin/env bash
#
# Test runner for clayok. Feeds each fixture via CLAYOK_FEED and asserts the
# derived state (a substring of stdout) and the exit code.
#
set -u

here="$(cd "$(dirname "$0")" && pwd)"
clayok="$here/../clayok"
fixtures="$here/fixtures"

pass=0
fail=0

# run <description> <fixture> <expected_exit> <expected_substring>
run() {
  local desc="$1" fx="$2" want_code="$3" want_str="$4"
  local out code
  out="$(CLAYOK_FEED="$fixtures/$fx" "$clayok" 2>/dev/null)"
  code=$?
  if [ "$code" -eq "$want_code" ] && printf '%s' "$out" | grep -qF "$want_str"; then
    printf 'PASS  %s\n' "$desc"
    pass=$(( pass + 1 ))
  else
    printf 'FAIL  %s\n' "$desc"
    printf '      expected exit %s + substring "%s"; got exit %s\n' "$want_code" "$want_str" "$code"
    printf '%s\n' "$out" | sed 's/^/        | /'
    fail=$(( fail + 1 ))
  fi
}

echo "Running clayok fixture tests..."
echo

run "old active incident + newer resolved -> incident (order-independent)" \
    01-old-active.rss    1 "Active incident"
run "concurrent active incidents -> incident"                              \
    02-concurrent.rss    1 "Active incident: 2 open"
run "only scheduled future maintenance -> operational + upcoming note"     \
    03-scheduled.rss     0 "Upcoming maintenance scheduled"
run "maintenance in progress -> maintenance"                               \
    04-maintenance.rss   1 "Maintenance in progress"
run "unrecognized status token -> unknown"                                 \
    05-unknown-token.rss 2 "Status unknown"
run "empty feed (no items) -> unknown"                                     \
    06-empty.rss         2 "Status unknown"
run "malformed XML -> unknown"                                             \
    06-malformed.xml     2 "Status unknown"
run "titles with XML entities & quotes render decoded"                     \
    07-entities.rss      0 'Ads & "Meta" <integration> issues'
run "reversed (newest-first) ordering still detects active"                \
    08-reversed.rss      1 "Active incident"
run "operational baseline (scheduled fixture exits 0)"                     \
    03-scheduled.rss     0 "No active incidents found"

echo
. "$here/regressions.sh"

echo "-----------------------------------------"
printf 'Results: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
