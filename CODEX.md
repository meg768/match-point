# Codex Context

## Handoff July 10, 2026

Match Point has found a strong personal workflow around `Favoriter`. Preserve
this as a product core and resist adding broad navigation until real use shows
what is missing.

Current main navigation pills are `Matcher`, `Spelare`, and `Favoriter`.
The older `Jämför` mode remains available through `Cmd+3`, but its visible pill
was removed because the favorite workflow supersedes it for normal use.
`Favoriter` is available through `Cmd+4`.

Favorite workflow:

- Players are starred from any player overview and persisted locally in
  `UserDefaults`.
- Clicking a favorite row marks it for comparison. The two most recently
  selected players remain marked; selecting a third replaces the oldest.
- Comparison starts automatically as soon as two players are marked. There is
  intentionally no extra `JÄMFÖR` button and no A/B terminology.
- Clicking the player name opens drill-down in the right panel. Hover color and
  a pointing cursor communicate that the name is a link; the rest of the row
  is the comparison selection target.
- Removing a favorite is a two-step inline action: the star animates into a red
  `Ta bort` button, requires a second click, and resets after three seconds.

The favorite comparison reuses the dense right-side comparison surface:
profiles, ranking history, and previous meetings. It also shows hypothetical
GPT odds for arbitrary player pairs. The odds UI intentionally contains three
sources:

- `Oddset`: shown only when the selected pair matches an actual current
  live or upcoming Oddset match; otherwise the market column remains empty.
- `TA`: Tennis Abstract-derived odds and Magnus' most trusted baseline.
- `GPT`: calculated locally in Match Point's Swift code.

Do not restore an `MP` column or make Match Point depend on database odds
routines. TA remains an independent external baseline.

Database/model convergence confirmed on 2026-07-12:

- `atp-service`, Vitel, and Match Point now expose the same TA-calibrated GPT
  odds model. The canonical server implementation is `PLAYER_WIN_FACTOR` in
  `atp-tennis`; Match Point keeps a matching local Swift implementation.
- The former Vitel model and its factor-specific ELO/form/rating/ranking/HTH
  functions were retired. `PLAYER_STATS` was also removed.
- Match Point remains independent: Svenska Spel comes from its local Oddset
  client, TA comes directly from Tennis Abstract, and GPT is calculated in
  Swift from direct ATP database reads.
- For a hypothetical favorite H2H with no current match, both TA and GPT use
  total ELO only. A separately optimized neutral model using total ELO,
  ranking, last-12 form, and 365-day form was tested but lost to pure total ELO
  on the untouched 2023+ test period (`0.632010` vs `0.631415` log loss and
  `0.220970` vs `0.220601` Brier). Therefore no surface, ranking, or form
  adjustment is used without a real match. If an actual live/upcoming match
  exists, GPT uses that match's inferred surface and full matchup context.
- The full match-context GPT model was backtested chronologically on 450,276
  completed matches and optimized on pre-2019 data. On the untouched 2023+
  test period (99,310 oriented examples), it improved log loss from `0.631071`
  for the previous GPT formula to `0.627236`, and Brier score from `0.220309`
  to `0.218889`. Its signals, in descending fitted importance, are total ELO,
  surface ELO, ranking, surface record, last-12 form, and 365-day form. The
  reproducible research tool and generated artifacts live under
  `codex-chat/sandbox/codex-odds-backtest`.
- After database ELO changed to Tennis Abstract on 2026-07-11, the historical
  reconstruction was linearly calibrated to the current TA scale and the model
  was regenerated. On the untouched 2023+ test period, TA-calibrated GPT
  reached `0.627253` log loss and `0.218899` Brier versus `0.633843` and
  `0.221287` for calibrated overall ELO. This remains an approximation because
  Tennis Abstract does not publish a complete historical ELO snapshot archive.

Player-name drill-down from match and comparison contexts stays inside the
right panel. The left list, selected match/mode, and navigation history remain
intact. `Spelare` is the place to begin a database-wide player search, not the
mandatory destination for every player click.

## Handoff July 9, 2026

Latest product/design state: Magnus is undecided about the best navigation
model, and that uncertainty is intentional. Preserve the current experiment
rather than over-committing. The app is trying to become a fast native ATP
workbench, not simply "an app with views".

Current UI experiment:

- The visible left navigator/tree was removed.
- Main window is now two resizable panels: content/list on the left, details on
  the right.
- Main modes are selected from the macOS `View` menu:
  - `Cmd+1` Matcher
  - `Cmd+2` Spelare
  - `Cmd+3` Jämför
  - `Cmd+4` Visa logg
- This may be kept, backed out, or combined with a small visible segmented
  control. Do not assume the View-menu approach is final.

The working mental model right now is three daily work modes:

1. `Matcher`: Oddset/live/upcoming match list on the left, match overview on
   the right.
2. `Spelare`: searchable player list on the left, player overview on the
   right.
3. `Jämför`: searchable player list on the left, choose temporary `Spelare A`
   and `Spelare B`, then compare them on the right.

The A/B comparison concept is promising now that search works in `Jämför`.
Search is shared between `Spelare` and `Jämför`; switching into either mode
should run a player search with the current toolbar search text. A good future
polish path is clearer A/B slots, swap/clear controls, and keyboard flow for
assigning selected search results to A or B.

Navigation is still a product question. The old Mail-like tree felt useful for
orientation, but took space and added visual weight. The current two-panel
version is cleaner and worth trying in real use before deciding. If Magnus says
it feels hidden or hard to orient, consider adding a compact in-window mode
segmented control before restoring the full navigator tree.

Odds/model state:

- `Oddset`: live market odds from Oddset/Kambi.
- `TA`: Tennis Abstract-derived odds.
- `MP`: Magnus' own Match Point database model, backed by the database
  `PLAYER_WIN_FACTOR(...)`.
- `GPT`: local lightweight direction model in Swift. It uses surface ELO
  first, then ranking, current-surface win rate, recent form, and broader form.
  The score is turned into a probability with a sigmoid, clamped to 8-92%, then
  priced with a 5% margin. It is intentionally not trained/backtested yet.

GPT odds weights as currently implemented:

```text
score =
  ((surfaceEloA - surfaceEloB) / 520) * 0.62
+ log(rankB / rankA)                  * 0.28
+ (surfaceWinPctA - surfaceWinPctB)   * 0.38
+ (recentWinPctA - recentWinPctB)     * 0.22
+ (formWinPctA - formWinPctB)         * 0.18

pA = clamp(1 / (1 + exp(-(scoreA - scoreB))), 0.08, 0.92)
oddsA = 1 / (pA * 1.05)
oddsB = 1 / ((1 - pA) * 1.05)
```

Kelly state:

- The `ODDS` section includes a Kelly recommendation block with bankroll
  currently set to `1,000 kr`.
- It chooses the best positive Kelly candidate across available model sources
  and displays full Kelly plus `1/4`, `1/8`, `1/16`, and `1/32`.
- Keep it visually quiet and exploratory; do not frame it as financial advice.

## Handoff July 7, 2026

Latest product direction: continue with the native Mac app as Magnus' primary
analysis tool. Treat it as a dense local ATP instrument/cockpit, not a public
website. A web version can later become a distilled/shareable surface if the
native workflows prove valuable.

Current active UI work has focused on a redesigned `PlayerInspectorView` sheet.
Despite earlier notes saying sheets were not preferred, the current working
direction is that a player sheet is useful for deeper drill-down from the match
overview and the left match list. Keep it native, compact, and visually aligned
with the match overview.

Player inspector current behavior:

- Opens from player names in the right match overview.
- Left-list clicks should only select the match, even when clicking directly on
  a player name.
- Supports browser-like drill-down inside the same sheet: clicking winner/loser
  names in the inspector's match table navigates to that opponent, with a back
  button next to the close button.
- Header uses a compact flag/name/country/rank look, while the avatar lives in
  the overview grid.
- Sheet is intentionally wide; do not make it cramped.

Player inspector sections:

- `ÖVERSIKT`: avatar spanning three rows, then compact profile cells.
- `TITLAR`: normal grid cells for Grand Slam, Masters, ATP-500, ATP-250.
- `RANKING`: single-player ranking chart with the shared `1Y/2Y/3Y/4Y/5Y`
  picker, default `2Y`.
- `MATCHER`: fixed-height internally scrolling table, horizontal scroll,
  sortable columns, and pill filters.

Inspector match pills:

- `KARRIÄR`, `VINSTER`, `FINALER`, `GRAND SLAMS`, `MASTERS`, `ATP-500`,
  `ATP-250`, `SKRÄLLAR`, `VARNINGSFLAGGOR`.
- Empty pills should not be shown.
- `SKRÄLLAR` and `VARNINGSFLAGGOR` should be recent, roughly one year back.
- The crash on July 6 was caused by MySQLNIO asserting in `MySQLQueryCommand`
  while the inspector was loading multiple tab SQL queries. The fix was to load
  the player career matches once and filter tabs locally in Swift.

Shared UI components and formatting:

- Use `ProfileGridCell` for the compact label/value cells. Label and value use
  the same system font family; vary only size/weight. No monospaced font in
  these cells.
- All SwiftUI font declarations should use one font family. We removed
  `design: .monospaced` and `design: .rounded` from the app.
- Use `AppPill` as the shared pill base. Pills render text in CAPS and use a
  smaller default font. `PillLabel`, match filters, ranking range pills,
  surface picker, and inspector match pills should go through this shared style
  unless there is a strong reason not to.
- Use `AppFormat.dollars(_:)` for money. Desired format is `$13,698,562`; do
  not show `US$`, spaces, or ungrouped values like `$13698562`.

Build and verification habit:

```bash
swift build
Scripts/build-app.sh debug
xattr -c "dist/Match Point.app"
codesign --verify --deep --strict --verbose=2 "dist/Match Point.app"
```

`dist/Match Point.app` sometimes receives `com.apple.FinderInfo` on the app
directory. If strict codesign verification complains, clear xattrs on the app
directory and verify again.

The working tree may be dirty with intentional local changes across
`ATPDatabase.swift`, `ContentView.swift`, `Models.swift`,
`PlayerInspectorView.swift`, and `ScoreboardWindow.swift`. Do not revert them
unless Magnus explicitly asks.

## Project

`Match Point` is a native macOS SwiftUI app for ATP tennis data from Magnus'
MariaDB database.

It is a separate project from `tennis.egelberg.se` and must not rely on
`tennis.egelberg.se` at runtime. The app is meant to be a local instrument, not
a web product: open the app, read the ATP database directly, inspect recent
matches, compare Tennis Abstract odds, and keep ranking context close at hand.

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
- Tennis Abstract odds derived from TA Elo ratings

Tennis Abstract integration note:

- Match Point now reads Tennis Abstract directly from
  `https://tennisabstract.com/reports/atp_elo_ratings.html`.
- This is intentionally implemented locally in Swift. Do not call Vitel,
  `atp-tennis`, `tennis.egelberg.se`, localhost, or `/api/odds` at runtime.
- The TA report is a static HTML table. The app parses the player row, picks the
  surface Elo (`hard`, `clay`, `grass`), converts Elo difference to probability,
  then converts that probability to decimal odds with a 5% margin.
- The UI label should be `TA`, not `Modell`. Conceptually this is TA-based
  baseline odds, while Oddset is the live market.
- If Tennis Abstract changes layout, TA odds may disappear, but the app should
  keep working: Oddset, database stats, ranking, ELO, titles, profile, previous
  meetings, avatars, and other sections must not depend on TA succeeding.

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

`Match Point` is Magnus' controlled main track. In parallel, Codex may explore
ideas independently in the separate repository
`/Users/magnus/Documents/GitHub/match-point-gpt`. Treat that as a friendly
race: Magnus drives `match-point`, Codex drives `match-point-gpt`, and useful
ideas can be discussed or borrowed intentionally. Do not couple the projects at
runtime, do not read private files from the sibling project, and do not let GPT
experiments automatically steer this app unless Magnus asks for that change.

The current first cut is deliberately exploratory and may show too much at once.
When continuing, prefer shaping the first screen around the smallest useful
daily tennis workflow instead of adding more panels by default. Good next steps
are likely about deciding what Magnus wants to inspect first, then simplifying
the visible surface around that.

Current native app direction: keep one main window with a Mail/Finder-like
three-column structure, not many windows or modal flows: a narrow navigator
sidebar, a list/search column, and a right inspector. The first navigator items
are `Matcher`, `Spelare`, `Jämför`, plus a `Databas` disclosure group with
`Visa logg`. `Matcher` keeps the Oddset/live workflow. `Spelare` is an inline
player workspace: searchable player list in the middle column, selected player
overview on the right with current ranking/profile/titles/ranking
history/matches. `Jämför` uses the same player search results to fill two
comparison slots and shows HTH, profile metrics, ranking history, and previous
meetings on the right. `Databas > Visa logg` shows store-level data operation
logs for Oddset, ATP dashboard loads, player search/profile loads, comparison
loads, duration, status, and cache hits. All three main columns should be
resizable in width through split dividers.

Visual shell direction: the three main columns should feel like Mail columns,
not separate cards. Keep the outer navigator/list/detail surfaces flat with
thin vertical separators; reserve rounded bordered panels/cards for content
inside the inspector where they improve scanning.

Evening product conclusion from July 5: the right-side match overview is the
main product surface. It should act like the player's/match's inspector in
context instead of opening a separate `Player Inspector` sheet/dialog/window.
Keep the workflow KISS:

1. Select a match in the left mail-like list.
2. Read the player comparison in the right panel.
3. Scroll vertically through compact sections when more depth is needed.
4. Avoid extra modal layers unless there is a very clear reason.

Current right-panel direction as of July 6: keep a vertically scrolling match
overview with compact comparison sections. The right panel is the main place to
compare the two selected players; separate player sheets/windows were explored
but are not the preferred direction right now.

The current section stack is:

- `ÖVERSIKT`
- `ODDS`
- `TITLAR`
- `PROFIL`
- `RANKING`
- `TIDIGARE MÖTEN`

`PROFIL` is currently the favored compact layout for player facts: two
player cards with cell labels in CAPS and values beneath. It includes age,
height/weight/BMI, ranking, current-surface ELO/total ELO, best ranking with
date (`#3 (2017-11-20)` style), and pro-since. BMI should be rounded, not shown
with decimals.

`ODDS` is a full-width table with the columns `Namn`, `Oddset`, `TA`, `MP`,
and `GPT`. `Oddset` is live market odds. `TA` is Tennis Abstract-derived
odds. `MP` is Magnus' own Match Point model/database odds. `GPT` is GPT's local
lightweight direction model using ELO, rank, surface record, and
recent form. Positive edge can be shown in the model cells as `(+15%)`; keep
this quiet and readable, not a betting engine claim.

`TITLAR` is a full-width table with player name and title counts: total, Grand
Slam, Masters, ATP-500, and ATP-250. SVG icons for headers were tried and
reverted; plain text was calmer.

`SKRÄLLAR` and `VARNINGSFLAGGOR` were useful conceptually but too expensive in
the match overview for now. They were removed from the live dashboard flow
because they contributed to long delays. Keep the idea parked; if reintroduced,
make it staged, cached, or user-triggered.

Treat these sections as the primary comparison model. If deeper player detail
is needed later, first consider adding or refining a section in the right panel
before introducing a new sheet.

Keep database credentials out of the repository. Runtime database settings may
come from app defaults, launch environment variables, or
`~/Library/Application Support/Match Point/.env`, but Match Point must not read
private files from sibling projects.

## Loading And Performance Notes

The match overview is intentionally moving toward a staged loading model. When a
match is selected, show the useful ATP database overview first, then let heavier
sections fill in afterwards. The user experience should be:

1. Oddset selection changes immediately.
2. Player overview data appears as soon as possible: name, country, rank, odds,
   TA odds, ELO, titles, profile, and form.
3. Heavier context follows: ranking graph, previous meetings, upset signals, and
   warning flags.
4. Avatar loading must never block database text or stats. Headshots come from
   ATP image URLs and may be slow or blocked; treat them as optional visual
   enrichment.

Avoid aggressive parallel MySQL connection fan-out for now. It caused unstable
dashboard behavior and made it harder to reason about selection state. Prefer
smaller SQL changes, staged dashboard data, and visible status/error reporting.

Caching is allowed, but keep it conservative:

- Good candidates for in-memory session cache: player profile/stat summaries,
  ranking history, previous meetings, headshots, and other mostly static ATP
  database reads.
- Do not cache live match state: score, server, Oddset odds, selected match, or
  current status.
- Start with memory-only cache if needed. No disk cache or clever invalidation
  until the behavior is proven stable.
- If cached data is introduced, stale or partial cache entries must not make the
  right panel show the wrong match or hide fresh data.

The current delay when switching matches is understandable because several SQL
queries run for both players. The next performance work should optimize
`loadPlayerStats` and section-level loading rather than changing broad UI
structure.

Next likely improvement: add a small memory cache for non-live ATP data. Keep
Oddset uncached. Good first targets are player stats, profile facts, titles,
ranking history, previous meetings, TA odds, MP/model odds, and avatar image
URLs/images. The goal is to make switching back and forth between matches feel
instant without ever showing the wrong selected match.

When loading, prefer honest intermediate states:

- Show already available database text before avatars finish.
- Show "Läser in..." while a heavy section is still loading.
- Show "Ingen info" only after the app actually knows that no data exists.

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
