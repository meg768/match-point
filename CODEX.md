# Codex Context

## Project

`Match Room` is a native macOS SwiftUI app for ATP tennis data from
`https://tennis.egelberg.se`.

It is meant to be a local instrument, not a web product: open the app, see live
and upcoming matches, compare bookmaker odds to Magnus' model odds, and keep
ranking context close at hand.

## Repository

- Local path: `/Users/magnus/Documents/GitHub/match-room`
- GitHub repository: `meg768/match-room`
- Swift package product: `MatchRoom`
- Minimum platform: macOS 14
- App bundle output: `dist/Match Room.app`

## Data Sources

Default API base URL:

```text
https://tennis.egelberg.se
```

Current first-cut endpoints:

- `GET /api/ping`
- `GET /api/oddset?states=STARTED,NOT_STARTED`
- `GET /api/player/rankings?top=30`
- `GET /api/odds?playerA=...&playerB=...&surface=...`

The service endpoint catalog is available at `GET /api/meta/endpoints`.

## Visual Design

`Match Room`, `/Users/magnus/Documents/GitHub/broker-explorer`, and
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
