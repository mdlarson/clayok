# clayok

Check [Clay's status](https://status.clay.com/) from your terminal.

`clayok` is a tiny, dependency-light command-line tool that reports whether Clay
is currently having an incident and lists the most recent entries from Clay's
status page. It's inspired by [`dacharyc/clok`](https://github.com/dacharyc/clok)
(an Anthropic-status checker), reworked for Clay and built to sit comfortably
alongside [Clay's developer tools](https://developers.clay.com/).

```
$ clayok
Clay status — checked 2026-07-27 09:37 EDT
Source: https://status.clay.com/history.rss

✅ No active incidents found in the status feed

Recent incidents (newest first):
  ✅  Completed      2026-07-25  Scheduled Maintenance
      https://status.clay.com/incidents/9f817254-a573-40ba-b5a1-44012267bc15
  ✅  Resolved       2026-07-25  AI Columns currently not running as expected
      https://status.clay.com/incidents/03c005f0-95ba-461b-880c-60f5f62acaac
  ...

Feed last updated: 2026-07-25 (1 day(s) ago)
```

## Why not a JSON API?

`clok` reads Statuspage.io's JSON API. Clay's status page runs on Rootly, which
exposes no public JSON API, and the "All Systems Operational" banner on the HTML
page is gated behind Cloudflare. The one reliable machine-readable source is the
public RSS incident feed (`https://status.clay.com/history.rss`), so that's what
`clayok` reads and derives status from.

## Install

`clayok` is a single Bash script (targets Bash 3.2, macOS's default). It needs
`curl`, `xmllint`, `date`, and `sort`, plus standard shell utilities such as
`mktemp`, all preinstalled on macOS.
(On Debian/Ubuntu: `apt install curl libxml2-utils` — `date` and `sort` are provided by coreutils.)

```bash
git clone https://github.com/mdlarson/clayok.git
cd clayok
chmod +x clayok

# Put it on your PATH by symlinking into a directory that's already there.
# ~/.local/bin is a good choice (no sudo needed); create it if missing:
mkdir -p "$HOME/.local/bin"
ln -sf "$PWD/clayok" "$HOME/.local/bin/clayok"
```

Then run `clayok` from anywhere. If your shell doesn't find it immediately,
run `rehash` (zsh) or open a new terminal — shells cache command locations.

> If you move the project later, the symlink stores an absolute path and will
> dangle. Just recreate it: `ln -sf /new/path/to/clayok "$HOME/.local/bin/clayok"`.
> (Not sure whether `~/.local/bin` is on your `PATH`? Check with
> `echo "$PATH" | tr ':' '\n' | grep -F "$HOME/.local/bin"`.)

## Usage

```
clayok [-n N] [--help] [--version]
```

| Option | Description |
| --- | --- |
| `-n, --limit N` | Number of recent incidents to list (default 5, max 50) |
| `-h, --help` | Show help and exit |
| `-v, --version` | Show version and exit |

### Exit codes

`clayok` is designed to be useful in scripts and monitoring, not just to read:

| Code | State | Meaning |
| --- | --- | --- |
| `0` | operational | No active incidents found in the feed |
| `1` | active | An incident or maintenance is currently in progress |
| `2` | unknown | Could not fetch/parse the feed, or status is indeterminate |

Example:

```bash
if ! clayok >/dev/null 2>&1; then
  echo "Clay may be having issues — check https://status.clay.com/"
fi
```

### Environment

| Variable | Description |
| --- | --- |
| `CLAYOK_FEED` | Override the feed source with a URL or a local file path. Used by the test suite to run offline against saved fixtures. |

## How status is derived

The RSS feed is Clay's incident history — one entry per incident, carrying that
incident's latest update. Each update's body is prefixed with a bracketed
lifecycle status (`[Investigating]`, `[Identified]`, `[Monitoring]`,
`[Resolved]` for incidents; `[Scheduled]`, `[In Progress]`, `[Verifying]`,
`[Completed]` for maintenance).

`clayok` scans every entry (not just the newest — a completed maintenance can be
newer than a still-open incident) and classifies it:

- Active incident — `Investigating`, `Identified`, `Monitoring` → exit `1`
- Active maintenance — `In Progress`, `Verifying` → exit `1`
- Upcoming maintenance — `Scheduled` → shown as a note, stays operational
- Terminal — `Resolved`, `Completed` → healthy
- Unrecognized — anything else → treated as `unknown` (exit `2`), never silently
  assumed healthy

Recent incidents and active entries are ordered by publication timestamp, newest
first, regardless of feed order. The upcoming-maintenance note selects the most
recently published scheduled entry. Equal timestamps retain their input order.
Publication dates are parsed with Bash arithmetic, without per-item subprocesses.
Supported dates use English month names, four-digit years, and numeric timezone
offsets or standard UTC/GMT and US timezone abbreviations.
Items with missing, unsupported, or invalid dates follow dated items in input order and display
the original date text; date problems do not change lifecycle classification.
Freshness uses the greatest valid publication timestamp and is omitted if none
can be parsed.

XML extraction uses `xmllint` XPath in batches of up to 50 items. CDATA and XML
entities are decoded, whitespace is normalized, and missing fields remain empty.

## Limitations

- The feed is incident history, not an authoritative component-status API.
  "Operational" means no active incidents were found in the feed — not a
  guarantee that every subsystem is healthy.
- The live overall-status banner (`status.clay.com`) is Cloudflare-gated and
  isn't used.
- Severity/impact is not published in the feed, so status is reported by
  incident *lifecycle*, not by severity.

## Tests

```bash
bash test/run.sh
```

The suite runs `clayok` against checked-in XML fixtures (via `CLAYOK_FEED`), so
it needs no network. Cases cover order-independence, concurrent incidents,
scheduled vs. in-progress maintenance, unknown tokens, empty/malformed feeds,
CDATA and escaped XML entities, missing fields, chronological ordering and date
fallbacks, multi-batch feeds, extraction failures, and active incidents beyond the
recent display limit. The runner also checks output sections and diagnostics.
Run it on macOS Bash 3.2 and Linux Bash when changing portability-sensitive code.

## License

MIT — see [LICENSE](LICENSE).
