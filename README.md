# Match Room

Native macOS ATP tennis room for `tennis.egelberg.se`.

First cut:

- live and upcoming ATP/Oddset matches
- bookmaker odds next to computed model odds
- model surface switcher
- ATP ranking context
- shared tennis themes with `Broker Explorer` and `LAN Scanner`

## Build

```bash
swift build
Scripts/build-app.sh debug
```

The app bundle is written to:

```text
dist/Match Room.app
```
