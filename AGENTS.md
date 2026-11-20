# Working on Guild Bank Ledger (Forever)

Guild bank ledger for World of Warcraft: Forever (interface 16001). It scans the guild bank log and keeps one running ledger per guild. Read `README.md` before changing behaviour.

## Layout

- `Core.lua` holds saved variables, the guild key, slash commands, and events.
- `Time.lua` turns a log age into a day. It does not call the WoW API.
- `Ledger.lua` merges a new scan, rebuilds totals, and writes CSV. It does not call the WoW API.
- `Scan.lua` reads the open bank and appends lines to the guild the current character is in.
- `Widgets.lua` and `Window.lua` draw the navy window.
- `tests/merge_test.lua` covers `Time.lua` and `Ledger.lua` offline.

The TOC files load in that same order: Core, Time, Ledger, Scan, Widgets, Window.

## Data

Ledgers live in `GuildBankLedgerForeverDB`, one entry per `GuildName-Realm`. A finished scan writes only to the guild returned by `GetGuildInfo("player")`. The window's `viewKey` chooses what is shown. It does not choose where new lines are saved.

Closing the bank aborts a scan that has not finished, and those captured lines are discarded. Tab names can be saved during the scan, before the lines are merged.

A saved line has a character name. Scan does not store a row whose name is still blank. It waits for a later log update, and the query timeout saves only the rows that have names. Import refuses a blank character. The first load drops lines whose name is missing, blank, or the placeholder `Unknown`, then sets `requiredNames` so a later character literally named Unknown is kept.

Out includes withdrawals and tab purchases. The log's purchase notice is not stored. The withdrawal for the tab is kept. Repairs stay separate. Moves and deposit summaries are listed and left out of the totals. Money and each item tab are separate streams in one saved list. A line matches the saved line with the same line above it and the same line below it, in that stream. A scan and a merge use the same deposit check: the same day, a clock that crossed midnight, or a date-only reading of a timed line on that day or the next day. The line with a clock is the one kept. A deposit on a later day stays. The first clock time saved stays. Lines that have scrolled off the log stay as captured.

## Checks

For ledger or time changes, run this from the repository root with Lua 5.1:

```sh
lua5.1 tests/merge_test.lua
```

A passing run prints nothing and exits 0. Add a regression check to `tests/merge_test.lua` when the merge or the day math changes. The test does not load the game client.

Do not claim an in-game check passed unless it was actually done. Say when a change still needs a scan at the guild bank.

## Boundaries

- Import accepts a Transactions export, including a hand-written one. Guild and realm may be blank, and the guild open in the window receives the lines. Character is required. Lines already saved stay as they are, and an export that names another guild is refused. Character and item totals are not imported.
- Two saved ledgers can be merged by hand from Settings. The ledger on screen keeps its name, realm, and key. The other ledger's lines are matched into it. An older line is kept when its day is different, even if the person and amount match a later line. A scan follows that same rule. A date-only reading on the next day does not replace a line that has a clock. Both ledgers stay unless the merge pop-up's checkbox is checked. Backup saves a copy whose realm is `backup-YYYY-MM-DD-HH:MM:SS`, using the guild name in the key. A second backup in that same second gets `-2` on the end. A blank realm does not retarget a scan or a watch onto an older key.
- Release notes in `CHANGELOG.md` follow Cisco caveat style. A bug found in a shipped release is added to that release as an open caveat. When a later release fixes it, the earlier note stays and names the release that resolved it.
- A transaction export keeps the newest 5,000 lines.
- There is no sync between accounts. Characters on the same WoW account share one save.
- Prefer the `C_CurrencyInfo` and `C_Item` fallbacks already in `Core.lua` and `Scan.lua` when a removed global is missing.
