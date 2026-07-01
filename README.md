# Match Room

Native macOS ATP tennis room for Magnus' MariaDB ATP database.

This is a separate project from `tennis.egelberg.se`. It must not rely on that
site/API at runtime; the ATP database is the source and is open for direct
queries from the app.

First cut:

- direct database connection to `pi-sql` / `atp`
- live and upcoming ATP-family matches from Kambi/Svenska Spel Oddset
- recent completed/imported matches
- computed SQL model odds from `PLAYER_WIN_FACTOR`
- model surface switcher
- ATP ranking context
- shared tennis themes with `Broker Explorer` and `LAN Scanner`

Oddset fetching is implemented directly in this app. The project may borrow
knowledge from `atp-tennis` and `oddset-mqtt`, but it does not depend on either
repository at runtime.

## Build

```bash
swift build
Scripts/build-app.sh debug
```

The app bundle is written to:

```text
dist/Match Room.app
```
