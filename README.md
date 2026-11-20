# Guild Bank Ledger (Forever)

A guild bank ledger for World of Warcraft: Forever. Open the bank, scan the log, and keep one running total per guild: who put gold and items in, who took them out, repairs, and tab purchases.

## Install

Copy this folder to:

`World of Warcraft/_classic_beta_/Interface/AddOns/guild-bank-ledger-forever/`

The folder name has to be `guild-bank-ledger-forever`, the same name as the TOC file. Log in, and the minimap coin button opens the window.

## Use

Open the guild bank and press Scan, or type `/scan`. With the default settings the addon scans when the bank opens, then again every 2 minutes while it stays open.

| Command | What it does |
| --- | --- |
| `/ledger` or `/gblf` | Open or close the window |
| `/gblf scan` or `/scan` | Read the log. The bank has to be open |
| `/gblf status` | Print how many lines are saved |

`/scan` is a short command. Another addon can claim it.

**Ledger** is the main view. The strip across the top is the guild total. The list under it is each character, or each item. Click a name or an item to filter the lines on the right.

**Dates** is the same ledger, one day at a time.

**Export** fills a box you can copy with Ctrl+C. Transactions, character totals, or item totals. More than 5,000 lines keeps the newest 5,000, oldest of those first.

**Import** is on that same page. Paste a transaction export from the other computer and press Import. It adds those lines to the guild shown in the window. Lines already saved stay as they are, so the same export can be pasted again. An export from a different guild is refused. On a computer that has not scanned yet, log into that guild first. Character and item totals cannot be imported.

**Settings** holds auto-scan, the minimap button, the rescan interval, and the saved guilds. Delete removes that guild's ledger from this account.

## How the log is kept

Each item tab, and the money log, is its own list. A scan is the slice the game still has, usually a few dozen lines. Lines that match the end of what is already saved are skipped. Lines after that match are added. The first scan of a tab is not treated as a hole.

The game usually says "3 days ago", not the hour. The day is stored the first time a line is seen and is not moved later. An hour is stored only when the log's age was in hours. A `≈` in front of a date means the log only gave a month or a year.

If a later scan does not overlap the previous tail, the log rolled past between visits. Those missing lines cannot be recovered. The ledger records a gap and keeps going. Leaving the bank open, with the rescan timer on, is what keeps a busy tab complete.

Moves are stored once, on the tab they left, and are not counted in item totals. A deposit summary repeats gold that the individual lines already count, so it is listed and left out of the totals. The log also writes a purchase notice for that gold. The notice is not stored. The withdrawal is kept, so the gold counts once. Out includes withdrawals and tab purchases. Repairs stay separate. Net is gold in, minus gold out, minus repairs.

Guilds are stored apart, under `GuildName-Realm`. The window follows your current guild until you pick another saved guild in Settings. There is no sync between accounts. Characters on the same WoW account share one save.

## Development

The merge and the day math can be checked without the game client. From this folder, with Lua 5.1:

```sh
lua5.1 tests/merge_test.lua
```

The test exits 0 when every check passes, and it prints nothing on success. Scan, the window, and saved variables still have to be tried in game.

## Releasing

CurseForge builds a zip when a tag is pushed. The `## Version` line in both TOC files has to match that tag.

While the addon is in beta, use `0.MINOR.PATCH-beta`. A fix bumps the last number (`0.1.1-beta`). A feature bumps the middle number and resets the patch (`0.2.0-beta`).

After the beta, use `YYYY.MINOR.PATCH`. `2026.1.0` is the first release. A feature bumps the middle number. A fix bumps the last number. The next year starts at `2027.1.0`.

Release notes are in [CHANGELOG.md](CHANGELOG.md).

```sh
git tag 0.1.2-beta
git push origin main 0.1.2-beta
```

A tag whose name contains `beta` is filed as a beta. A tag whose name contains `alpha` is an alpha. Any other tag is a release. A push to `main` without a tag does not publish a file.

## License

MIT. Copyright (c) 2026 Enlinks. See [LICENSE](LICENSE).
