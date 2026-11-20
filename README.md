# Guild Bank Ledger (Forever)

A guild bank ledger for World of Warcraft: Forever. Open the bank, scan the log, and keep one running total per guild: who put gold and items in, who took them out, repairs, and tab purchases.

## Install

Copy this folder to:

`World of Warcraft/_classic_beta_/Interface/AddOns/guild-bank-ledger-forever/`

The folder name has to be `guild-bank-ledger-forever`, the same name as the TOC file. Log in, and the minimap coin button opens the window.

## Warning

A recent game update left the realm name blank. The addon then started a second ledger, and the window follows that one. The older lines are still saved under the previous realm. Nothing is merged on its own.

## Use

Open the guild bank and press Scan, or type `/scan`. With the default settings the addon scans when the bank opens, then again every 2 minutes while it stays open.

| Command | What it does |
| --- | --- |
| `/ledger` or `/gblf` | Open or close the window |
| `/gblf scan` or `/scan` | Read the log. The bank has to be open |
| `/gblf status` | Print how many lines are saved |

`/scan` is a short command. Another addon can claim it.

### Ledger

The main view. The strip across the top is the guild total. The list under it is each character, or each item. Click a name or an item to filter the lines on the right.

### Dates

The same ledger, one day at a time.

### Export

This tab fills a box you can copy with Ctrl+C. Opening it clears the box. Press Transactions, Characters, or Items for the guild you are viewing. More than 5,000 lines keeps the newest 5,000, oldest of those first.

#### Import

A button on the Export page. Press Transactions once and copy the header row. Under it, paste only the lines you want to add, then press Import. The whole log can be pasted again. Lines already saved stay as they are.

The lines join the guild open in the window. Leave `guild` and `realm` blank. Those cells are not stored on the line. The next Transactions export fills them from that guild. If you do fill them in, every row has to name that same guild, and it has to be the guild on screen. The realm is the game realm with the spaces removed. Log into that guild on this account once before the first import. Every line needs a character. A blank name is refused, and nothing from that paste is saved. Character totals and item totals cannot be imported.

A line with the same person, action, and amount on the same day is kept as that saved line. The same amount on another day is added. A later reading with no time does not replace a saved line that has a clock.

| Column | Allowed values |
| --- | --- |
| `day` | Required. `YYYY-MM-DD`, a real calendar day. |
| `hour` | Blank, or a whole number from 0 to 23. 0 is midnight. |
| `precision` | `hour`, `day`, `month`, or `year`. Blank means `day`. Use `hour` when the hour is filled in. |
| `character` | Required. The character who did it. Blank is refused. |
| `action` | `deposit`, `withdraw`, `move`, `repair`, `withdrawForTab`, or `depositSummary`. `withdrawal` is also accepted and means a withdrawal. Do not use `buyTab`. That is the purchase sentence. A tab purchase is `withdrawForTab`. |
| `item_id` | Blank for gold. For an item, a whole number of 1 or more. |
| `item_name` | Blank, or the item's name. |
| `count` | Blank for gold. For an item, a whole number of how many. |
| `copper` | Blank for an item line. For gold, a whole number of copper. 1 gold is 10000. 1 silver is 100. Words such as `25s` are refused. |
| `tab` | Blank for a money line. For an item, the guild bank tab, a whole number of 1 or more. |
| `destination_tab` | Blank, except a `move`, which names the tab the stack moved to. A whole number of 1 or more. |
| `stream` | `money`, or `tab:` plus the tab number, such as `tab:1`. This chooses which log the line joins. |
| `guild` | Optional. Blank uses the guild open in the window. |
| `realm` | Optional. Blank uses that same guild. |
| `count_signed`, `copper_signed` | Written by Export and ignored by Import. Leave them out. |

A deposit summary is listed and left out of the totals. A move is listed and left out of the item totals. `withdrawForTab` counts as gold out and as a tab purchase.

### Settings

This tab holds auto-scan, the minimap button, the rescan interval, and the saved guilds. Click a guild to view it. Watch my current guild shows the guild this character is in.

#### Backup this ledger

Saves a copy of the guild you are viewing. The copy keeps the guild name. Its realm is `backup-` plus the date and time, down to the second, such as `backup-2026-11-20-14:05:09`. A second backup in the same second gets a number on the end.

#### Merge into this one

Folds another saved ledger into the guild you are viewing. To put the older lines back, choose the short ledger, the one with no realm. Leave "Delete the other ledger" unchecked until the lines look right. That box starts unchecked, so both ledgers stay. A repeated amount on another day is kept. When one line has a clock and the other has only a date, the clock stays. The name and realm you are viewing stay as they are.

#### Delete this ledger

Removes the ledger you are viewing from this account.

## How the log is kept

Each item tab, and the money log, is its own list. A scan is the slice the game still has, usually a few dozen lines. A line is saved only when it has a character name. The scan waits for the log to fill that name in, and leaves the line out if the name never arrives. The next login removes lines already saved with no name, including the placeholder Unknown. Those lines repeated ones that already named the character. A character who is actually named Unknown can be added after that. A line already saved stays when the line above it and the line below it are the same. Lines after that overlap are added. The first scan of a tab is not treated as a hole.

The game usually says "3 days ago", not the hour. A clock time is kept when the log's age was in hours. A later scan is the same line when the line above it and the line below it are the same people, actions, and amounts, even if the clock time moved. Money and each item tab are matched as their own log. The lines at the two ends of a scan have only one neighbor, so a re-read there stays on the time already saved. History that has scrolled off the log is left as it was captured. A `≈` in front of a date means the log only gave a month or a year.

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
git tag 0.2.0-beta
git push origin main 0.2.0-beta
```

A tag whose name contains `beta` is filed as a beta. A tag whose name contains `alpha` is an alpha. Any other tag is a release. A push to `main` without a tag does not publish a file.

## License

MIT. Copyright (c) 2026 Enlinks. See [LICENSE](LICENSE).
