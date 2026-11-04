# Sourced by run.sh; generated feeds and tool doubles live only in a temp dir.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

check() {
  local desc="$1"; shift
  if "$@"; then
    printf 'PASS  %s\n' "$desc"; pass=$(( pass + 1 ))
  else
    printf 'FAIL  %s\n' "$desc"; fail=$(( fail + 1 ))
    printf '%s\n' "${out:-}" "${err:-}"
  fi
}
capture() {
  local feed="$1"; shift
  out="$(CLAYOK_FEED="$feed" "$clayok" "$@" 2>"$scratch/stderr")"; code=$?
  err="$(cat "$scratch/stderr")"
}
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
absent() { ! contains "$1" "$2"; }
recent() { printf '%s\n' "$out" | sed -n '/^Recent incidents /,$p'; }
body() { printf '%s\n' "$out" | sed '1,2d'; }
item() {
  printf '<item><title>%s</title><description>%s</description><pubDate>%s</pubDate><link>%s</link></item>\n' "$1" "$2" "$3" "$4"
}
feed() { printf '<rss><channel>\n'; cat; printf '</channel></rss>\n'; }

# The same records with different XML formatting must render identically.
capture "$fixtures/08-reversed.rss"
pretty="$(body)"
tr -d '\n' <"$fixtures/08-reversed.rss" >"$scratch/minified.rss"
capture "$scratch/minified.rss"
check 'minified XML preserves all records and classification' test "$code:$(body)" = "1:$pretty"
check 'freshness uses newest timestamp in reversed feed' contains "$out" 'Feed last updated: 2026-07-25'
check 'reversed feed recent chronology' contains "$(recent)" "Newest, and it is active
      https://status.clay.com/incidents/newest
  ✅  Resolved"

item 'Ads &amp; &quot;Meta&quot; &lt;integration&gt; issues' '[Resolved] Done' 'Sat, 25 Jul 2026 18:00:00 -0700' 'https://example.test/?a=1&amp;b=2' | feed >"$scratch/entities.rss"
capture "$scratch/entities.rss"
check 'escaped title entities decode' contains "$out" 'Ads & "Meta" <integration> issues'
check 'escaped link entities decode' contains "$out" 'https://example.test/?a=1&b=2'
check 'decoded terminal status remains operational' test "$code:$err" = '0:'
item 'one&#10;two&#9;three' ' &#10;[Resolved] Done ' '' '' | feed >"$scratch/whitespace.rss"
capture "$scratch/whitespace.rss"
check 'embedded newlines and tabs normalize safely' contains "$out" 'one two three'
check 'all-invalid dates omit freshness' absent "$out" 'Feed last updated:'

for field in description title pubDate link; do
  title=MissingField; description='[Resolved] Done'; pubDate='Sat, 25 Jul 2026 18:00:00 -0700'; link='https://example.test/missing'
  case "$field" in description) description='' ;; title) title='' ;; pubDate) pubDate='' ;; link) link='' ;; esac
  item "$title" "$description" "$pubDate" "$link" | feed >"$scratch/missing.rss"
  # Remove the element entirely, rather than merely leave an empty element.
  sed "s#<$field></$field>##" "$scratch/missing.rss" >"$scratch/absent.rss"
  capture "$scratch/absent.rss"
  want=0; [ "$field" != description ] || want=2
  check "missing $field preserves exit semantics" test "$code" -eq "$want"
  if [ "$field" = description ]; then
    check 'missing status diagnostic' contains "$err" 'no recognizable status prefix'
    check 'missing status preserves title and date columns' contains "$out" '2026-07-25  MissingField'
  else
    check "missing $field keeps status column" contains "$out" '✅  Resolved'
    check "missing $field has no status warning" test -z "$err"
  fi
  [ "$field" = link ] || check "missing $field keeps link column" contains "$out" $'\n      https://example.test/missing'
done

# Dates use timezone offsets; equal instants retain input order. Unknown dates
# follow valid dates, even when they appear earlier in the input.
item Invalid '[Resolved]' 'not-a-date' invalid >"$scratch/invalid.item"
item Old '[Resolved]' 'Wed, 01 Jan 2025 00:00:00 +0000' old >"$scratch/old.item"
item TieA '[Monitoring]' 'Sun, 26 Jul 2026 01:00:00 +0000' tie-a >"$scratch/a.item"
item TieB '[In Progress]' 'Sat, 25 Jul 2026 18:00:00 -0700' tie-b >"$scratch/b.item"
item New '[Investigating]' 'Sat, 25 Jul 2026 23:00:00 -0700' new >"$scratch/new.item"
item Missing '[Resolved]' '' missing >"$scratch/missing.item"
for sequence in 'old a b new invalid missing' 'new a b old invalid missing' 'invalid a old b missing new'; do
  for name in $sequence; do cat "$scratch/$name.item"; done | feed >"$scratch/order.rss"
  capture "$scratch/order.rss" -n 50
  records="$(recent | sed -n 's/^      //p')"
  check "chronology with input order: $sequence" test "$records" = $'new\ntie-a\ntie-b\nold\ninvalid\nmissing'
  check 'active incident takes precedence over maintenance' test "$code" -eq 1
  check 'freshness follows greatest instant' contains "$out" 'Feed last updated: 2026-07-25'
  check 'invalid date renders raw' contains "$out" 'not-a-date'
  active_records="$(printf '%s\n' "$out" | sed -n '/^Active:/,/^Recent incidents /p' | sed -n 's/^      //p')"
  check 'active entries use chronological order' test "$active_records" = $'new\ntie-a\ntie-b'
done

{
  item OldActive '[Investigating]' 'Wed, 01 Jan 2025 00:00:00 +0000' active
  item Unknown '' '' unknown
  item Latest '[Resolved]' 'Sat, 25 Jul 2026 18:00:00 -0700' latest
} | feed >"$scratch/limited.rss"
capture "$scratch/limited.rss" -n 1
check 'active outside display limit overrides unknown' test "$code" -eq 1
check 'display limit applies only to recent section' test "$(recent | sed -n 's/^      //p')" = latest
check 'hidden active item remains in active section' contains "$out" 'OldActive'
check 'unknown warning remains alongside known active state' contains "$err" 'no recognizable status prefix'

{
 item Earlier '[Scheduled]' 'Wed, 01 Jan 2025 00:00:00 +0000' earlier
 item Latest '[Scheduled]' 'Sat, 25 Jul 2026 18:00:00 -0700' latest
} | feed >"$scratch/scheduled.rss"
capture "$scratch/scheduled.rss"
check 'upcoming note chooses newest scheduled publication' contains "$out" 'Upcoming maintenance scheduled: Latest (2026-07-25)'

# A 100-item feed must require exactly two extraction batches, plus the count.
{
 i=1
 while [ "$i" -le 100 ]; do
   status=Resolved; [ "$i" -ne 100 ] || status=Investigating
   item "Item$i" "[$status]" 'Sat, 25 Jul 2026 18:00:00 -0700' "https://example.test/$i"
   i=$(( i + 1 ))
 done
} | feed >"$scratch/100.rss"
mkdir "$scratch/bin"
REAL_XMLLINT="$(command -v xmllint)"; export REAL_XMLLINT
XML_CALLS="$scratch/xml-calls"; export XML_CALLS
cat >"$scratch/bin/xmllint" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$2" >>"$XML_CALLS"
case "${XML_MODE:-}:$2:$3" in
  count:--xpath:count*) echo 'injected count failure' >&2; exit 1 ;;
  late:--xpath:concat*)
    if [ "$(grep -c -- --xpath "$XML_CALLS")" -eq 3 ]; then
      echo 'injected second-batch failure' >&2; exit 1
    fi ;;
  fail:--xpath:concat*) echo 'injected extraction failure' >&2; exit 1 ;;
  short:--xpath:concat*) printf 'truncated\n'; exit 0 ;;
esac
"$REAL_XMLLINT" "$@"
EOF
chmod +x "$scratch/bin/xmllint"
original_path="$PATH"; PATH="$scratch/bin:$PATH"; export PATH
capture "$scratch/100.rss" -n 50
check 'second batch active item affects status' test "$code" -eq 1
check 'second batch active item renders' contains "$out" 'Item100'
check '100 items use count plus two XPath batches' test "$(grep -c -- --xpath "$XML_CALLS")" -eq 3
check 'recent limit stays capped at 50' test "$(recent | grep -c '^      ')" -eq 50
for mode in count fail short late; do
  : >"$XML_CALLS"
  XML_MODE="$mode"; export XML_MODE
  capture "$scratch/100.rss"
  check "$mode extraction reports unknown" test "$code" -eq 2
  check "$mode extraction has no partial report" absent "$out" 'Recent incidents'
  check "$mode extraction emits diagnostics" test -n "$err"
done
unset XML_MODE
PATH="$original_path"; export PATH

capture "$scratch/no-such-feed"
check 'missing source reports unknown' test "$code" -eq 2
check 'missing source emits diagnostic' contains "$err" 'feed file not found'
capture "$fixtures/06-malformed.xml"
check 'malformed XML emits diagnostic' contains "$err" 'parser error'

# Exercise calendar boundaries directly, independently of sorting and rendering.
# Load helpers without running main; isolate shell options from the test runner.
sed "/^main /d" "$clayok" >"$scratch/helpers.sh"
check 'date arithmetic validates calendar boundaries and timezone offsets' bash -c '
  source "$1"
  expect() {
    to_epoch "$1"
    if [ "$EPOCH" != "$2" ]; then
      printf "date %s: expected %s, got %s\n" "$1" "$2" "$EPOCH" >&2
      exit 1
    fi
  }
  expect "Thu, 01 Jan 1970 00:00:00 +0000" 0
  expect "Wed, 31 Dec 1969 23:59:59 +0000" -1
  expect "Thu, 01 Jan 1970 05:30:00 +0530" 0
  expect "Wed, 31 Dec 1969 20:30:00 -0330" 0
  expect "Tue, 29 Feb 2000 00:00:00 GMT" 951782400
  expect "Fri, 01 Mar 1900 00:00:00 UTC" -2203891200
  expect "1 Jan 1970 00:00 UT" 0
  expect "Wed, 31 Dec 1969 19:00:00 EST" 0
  for invalid in \
    "Mon, 29 Feb 1900 00:00:00 +0000" \
    "Mon, 29 Feb 2100 00:00:00 +0000" \
    "Mon, 31 Apr 2026 00:00:00 +0000" \
    "Mon, 00 Jan 2026 00:00:00 +0000" \
    "Mon, 01 Jan 2026 24:00:00 +0000" \
    "Mon, 01 Jan 2026 00:60:00 +0000" \
    "Mon, 01 Jan 2026 00:00:60 +0000" \
    "Mon, 01 Jan 2026 00:00:00 +2400" \
    "Mon, 01 Jan 2026 00:00:00 +0060" \
    "Mon, 01 Jan 2026 00:00:00 XYZ"; do
    expect "$invalid" ""
  done
' bash "$scratch/helpers.sh"
