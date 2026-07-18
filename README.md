# Match Point

Native macOS ATP tennis client for `tennis.egelberg.se` — conceptually a Mac
version of Vitel.

The app must use the backend API at `https://tennis.egelberg.se/api` for all
tennis data. It must never connect directly to Magnus' MariaDB ATP database or
ship database credentials. Database access and tennis-domain calculations are
backend responsibilities.

The API base can be overridden for local backend development with
`TENNIS_API_URL`; production is the default. The first migration uses the
backend's read-only query endpoint for existing detailed views and dedicated
endpoints for Oddset and odds.

First cut:

- backend-only tennis data through `https://tennis.egelberg.se/api`
- live and upcoming ATP-family matches from Kambi/Svenska Spel Oddset
- recent completed/imported matches
- Tennis Abstract odds derived from TA Elo ratings
- ATP ranking context
- shared tennis themes with `Broker Explorer` and `LAN Scanner`

Oddset and Tennis Abstract access should also move behind the backend so the
Mac app has one tennis-data boundary and does not duplicate server-owned data
integration logic.

## Build

```bash
swift build
Scripts/build-app.sh debug
Scripts/build-app.sh debug --install
```

The app bundle is written to:

```text
dist/Match Point.app
~/Applications/Match Point.app
```
