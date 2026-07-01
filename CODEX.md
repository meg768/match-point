# Codex Context

## Project

`Match Point` is a native macOS SwiftUI app for ATP tennis data from Magnus'
MariaDB database.

It is a separate project from `tennis.egelberg.se` and must not rely on
`tennis.egelberg.se` at runtime. The app is meant to be a local instrument, not
a web product: open the app, read the ATP database directly, inspect recent
matches, compare SQL model odds, and keep ranking context close at hand.

## Repository

- Local path: `/Users/magnus/Documents/GitHub/match-point`
- GitHub repository: `meg768/match-point`
- Swift package product: `MatchPoint`
- Minimum platform: macOS 14
- App bundle output: `dist/Match Point.app`

## Data Source

Default database settings:

```text
host: pi-sql
port: 3306
database: atp
```

Current first-cut database reads:

- recent rows from `matches` joined to `events` and `players`
- top rankings from `players`
- model odds through `PLAYER_WIN_FACTOR(...)`

Oddset/Kambi is allowed as a separate runtime source for live and upcoming
tennis matches. Keep that client implemented locally inside Match Point; do not
add runtime dependencies on `atp-tennis`, `oddset-mqtt`, or `tennis.egelberg.se`
for this pilot.

Do not make the app depend on `tennis.egelberg.se` for core data access. That
site/API can remain useful elsewhere, but Match Point's primary path is direct
database access.

The ATP database is intentionally open to Match Point for all kinds of read
questions. Prefer adding direct SQL-backed app features over routing through the
web/API service.

## Product Direction

Match Point should feel like a native Mac instrument for ATP tennis: Codex, the
database, and a Mac window. It is not a frontend for `tennis.egelberg.se`, not a
wrapper around the public site, and not dependent on the web API for runtime
data.

The current first cut is deliberately exploratory and may show too much at once.
When continuing, prefer shaping the first screen around the smallest useful
daily tennis workflow instead of adding more panels by default. Good next steps
are likely about deciding what Magnus wants to inspect first, then simplifying
the visible surface around that.

Keep database credentials out of the repository. Runtime database settings may
come from app defaults, launch environment variables, or
`~/Library/Application Support/Match Point/.env`, but Match Point must not read
private files from sibling projects.

## Visual Design

`Match Point`, `/Users/magnus/Documents/GitHub/broker-explorer`, and
`/Users/magnus/Documents/GitHub/lan-scanner` are sister tools. Keep their
`hard`, `grass`, and `clay` themes visually synchronized: same RGB palette, same
8px panel radius, same panel border treatment, and the same tennis-surface theme
naming (`US Open`, `Wimbledon`, `Roland Garros`).

Use `Fn+F3` to cycle themes and `Fn+F6` to toggle light/dark.

## Build

Useful commands:

```bash
swift build
Scripts/build-app.sh debug
```
