# Guild Bank Ledger Forever

An original guild bank ledger for World of Warcraft: Forever. Open the bank, scan the log, and keep one running total per guild: who put gold and items in, who took them out, repairs, and tab purchases.

This is not a copy of Guild Bank Snapshots, and it does not read that addon's saved data. Old snapshot saves stay where they are.

## Install

Copy this folder to:

`World of Warcraft/_classic_beta_/Interface/AddOns/guild-bank-ledger-forever/`

The folder name has to be `guild-bank-ledger-forever`, the same name as the TOC file. Log in, and the minimap coin button opens the window.

The client this was written for is Forever beta, interface `16001` (game 1.60.1). Saved variables on builds older than 70009 were unreliable. If a scan looks fine and then vanishes on relog, the client did not write the save file.

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

**Settings** holds auto-scan, the minimap button, the rescan interval, and the saved guilds. Delete removes that guild's ledger from this account.

## How the log is kept

Each item tab, and the money log, is its own list. A scan is the slice the game still has, usually a few dozen lines. Lines that match the end of what is already saved are skipped. Lines after that match are added. The first scan of a tab is not treated as a hole.

The game usually says "3 days ago", not the hour. The day is stored the first time a line is seen and is not moved later. An hour is stored only when the log's age was in hours. A `≈` in front of a date means the log only gave a month or a year.

If a later scan does not overlap the previous tail, the log rolled past between visits. Those missing lines cannot be recovered. The ledger records a gap and keeps going. Leaving the bank open, with the rescan timer on, is what keeps a busy tab complete.

Moves are stored once, on the tab they left, and are not counted in item totals. A deposit summary repeats gold that the individual lines already count, so it is listed and left out of the totals. Out includes withdrawals and tab purchases. Repairs stay separate. Net is gold in, minus gold out, minus repairs.

Guilds are stored apart, under `GuildName-Realm`. The window follows your current guild until you pick another saved guild in Settings. There is no sync between accounts. Characters on the same WoW account share one save.

## Development

The merge and the day math can be checked without the game client. From this folder, with Lua 5.1:

```sh
lua5.1 tests/merge_test.lua
```

The test exits 0 when every check passes, and it prints nothing on success. Scan, the window, and saved variables still have to be tried in game.

## License

MIT. Copyright (c) 2026 Enlinks. See [LICENSE](LICENSE).
