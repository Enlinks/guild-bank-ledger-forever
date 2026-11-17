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

Out includes withdrawals and tab purchases. Repairs stay separate. Moves and deposit summaries are listed and left out of the totals. The day is fixed the first time a line is seen.

## Checks

For ledger or time changes, run this from the repository root with Lua 5.1:

```sh
lua5.1 tests/merge_test.lua
```

A passing run prints nothing and exits 0. Add a regression check to `tests/merge_test.lua` when the merge or the day math changes. The test does not load the game client.

Do not claim an in-game check passed unless it was actually done. Say when a change still needs a scan at the guild bank.

## Boundaries

- Import accepts a transaction export. Lines already saved stay as they are, and an export that names another guild is refused. Character and item totals are not imported.
- A transaction export keeps the newest 5,000 lines.
- There is no sync between accounts. Characters on the same WoW account share one save.
- Prefer the `C_CurrencyInfo` and `C_Item` fallbacks already in `Core.lua` and `Scan.lua` when a removed global is missing.
