Notes follow Cisco caveat style. A bug found in a shipped release is added to that release as an open caveat. When a later release fixes it, that earlier note stays and names the release that resolved it. The fixing release lists the same caveat under resolved caveats.

## Release 0.2.0-beta

Backup this ledger saves a copy. The copy keeps the guild name, and its realm is `backup-` plus the date and time, down to the second. Merge into this one folds another saved ledger into the one on screen. Both ledgers stay unless Delete the other ledger is checked. Every line needs a character name.

A recent game update left the realm name blank and started a second ledger. The older lines stay saved. The addon does not merge them on its own. On login, and on the Settings page, it says to back up the ledger you want to keep and then use Merge into this one.

Resolved caveats. These were present in 0.1.3-beta and are fixed in 0.2.0-beta.

| Identifier | Affected release | Resolved in | Description |
| --- | --- | --- | --- |
| [#4](https://github.com/Enlinks/guild-bank-ledger-forever/issues/4) | 0.1.3-beta | 0.2.0-beta | Some tabs drew with no border. |
| [#5](https://github.com/Enlinks/guild-bank-ledger-forever/issues/5) | 0.1.3-beta | 0.2.0-beta | In and Out hid a coin when the total included gold. |
| [#6](https://github.com/Enlinks/guild-bank-ledger-forever/issues/6) | 0.1.3-beta | 0.2.0-beta | The character list included lines saved as Unknown. |
| [#7](https://github.com/Enlinks/guild-bank-ledger-forever/issues/7) | 0.1.3-beta | 0.2.0-beta | After a game update the window followed a new ledger and the older lines looked gone. |

**#4 Border is not loading on some tabs**

- **Symptom:** Some tabs draw with no border.
- **Conditions:** Seen in 0.1.3-beta.
- **Workaround:** None.
- **Resolution:** Fixed in 0.2.0-beta. Tab borders are drawn as textures.

**#5 In and out money hides a coin when gold is shown**

- **Symptom:** In and Out show three coin counts. A gold total drops one of the smaller coins.
- **Conditions:** Seen in 0.1.3-beta when the total includes gold.
- **Workaround:** None.
- **Resolution:** Fixed in 0.2.0-beta. A gold amount shows gold, silver, and copper, such as `23g 00s 00c`. Silver with no gold stays `50s 00c`.

**#6 Unknown entries in the character list**

- **Symptom:** The character list has entries named Unknown.
- **Conditions:** Seen in 0.1.3-beta. A log line was saved before the character name arrived.
- **Workaround:** None.
- **Resolution:** Fixed in 0.2.0-beta. A line is saved only with a character name. Lines already saved as Unknown are removed once on the next login. A character who is actually named Unknown can be added after that.

**#7 History is gone after a WoW update**

- **Symptom:** After a game update the ledger looks empty. Watch my current guild prints the guild with no realm.
- **Conditions:** Seen in 0.1.3-beta. The game left the realm name blank, so a second ledger was started. The older lines stayed under the previous realm.
- **Workaround:** In Settings, back up the ledger you want to keep, then use Merge into this one. Leave Delete the other ledger unchecked until the lines look right.
- **Resolution:** Fixed in 0.2.0-beta. The older ledger is still saved. Merge puts it back, including an older deposit of the same amount on another day. The addon does not merge by itself.

**Release 0.1.3-beta**

Resolved caveats. These were present in an earlier beta and are fixed in 0.1.3-beta.

| Identifier | Affected release | Resolved in | Description |
| --- | --- | --- | --- |
| [#3](https://github.com/Enlinks/guild-bank-ledger-forever/issues/3) | 0.1.1-beta | 0.1.3-beta | 0.1.2-beta stopped showing a tab purchase as two Buy tab lines. The purchase sentence was still stored, so the gold was counted twice. |
| Duplicate log line | 0.1.2-beta | 0.1.3-beta | A later scan stored one guild bank line again when the clock time moved, including a deposit that crossed midnight. |

**#3 Buying a guild bank tab stores the purchase twice**

- **Symptom:** One tab purchase adds the gold to Out twice. A 100g tab added 200g.
- **Conditions:** Seen in 0.1.1-beta. The money log reports the withdrawal and a purchase sentence for the same gold. 0.1.2-beta showed one Buy tab line and still stored both, so the total counted the gold twice. The issue stayed open.
- **Workaround:** None.
- **Resolution:** Fixed in 0.1.3-beta. The purchase sentence is not stored. The withdrawal stays, so the gold counts once. A purchase line already saved is removed the next time the addon loads.

**A scan stored the same log line twice**

- **Symptom:** One deposit or withdrawal appears twice after a later scan reads a different clock time. A 25s deposit was listed at 23:00 and again at midnight.
- **Conditions:** Seen in 0.1.2-beta. The ledger treated the moved clock time as a new line.
- **Workaround:** None.
- **Resolution:** Fixed in 0.1.3-beta. A line is the same one when the lines directly above and below it match. The first clock time stays. The next scan of that part of the log removes a copy already saved.

Open caveats. These were present in 0.1.3-beta. This release did not close them.

| Identifier | Found in | Resolved in | Description |
| --- | --- | --- | --- |
| [#4](https://github.com/Enlinks/guild-bank-ledger-forever/issues/4) | 0.1.3-beta | 0.2.0-beta | Some tabs drew with no border. |
| [#5](https://github.com/Enlinks/guild-bank-ledger-forever/issues/5) | 0.1.3-beta | 0.2.0-beta | In and Out hid a coin when the total included gold. |
| [#6](https://github.com/Enlinks/guild-bank-ledger-forever/issues/6) | 0.1.3-beta | 0.2.0-beta | The character list included lines saved as Unknown. |
| [#7](https://github.com/Enlinks/guild-bank-ledger-forever/issues/7) | 0.1.3-beta | 0.2.0-beta | After a game update the window followed a new ledger and the older lines looked gone. |

**#4 Border is not loading on some tabs**

- **Symptom:** Some tabs draw with no border.
- **Conditions:** Seen in 0.1.3-beta.
- **Workaround:** None.
- **Resolution:** Fixed in 0.2.0-beta. Tab borders are drawn as textures.

**#5 In and out money hides a coin when gold is shown**

- **Symptom:** In and Out show three coin counts. A gold total drops one of the smaller coins.
- **Conditions:** Seen in 0.1.3-beta when the total includes gold.
- **Workaround:** None.
- **Resolution:** Fixed in 0.2.0-beta. A gold amount shows gold, silver, and copper, such as `23g 00s 00c`.

**#6 Unknown entries in the character list**

- **Symptom:** The character list has entries named Unknown.
- **Conditions:** Seen in 0.1.3-beta. A log line was saved before the character name arrived.
- **Workaround:** None.
- **Resolution:** Fixed in 0.2.0-beta. A line is saved only with a character name. Lines already saved as Unknown are removed once on the next login.

**#7 History is gone after a WoW update**

- **Symptom:** After a game update the ledger looks empty. Watch my current guild prints the guild with no realm.
- **Conditions:** Seen in 0.1.3-beta. The game left the realm name blank, so a second ledger was started. The older lines stayed under the previous realm.
- **Workaround:** In Settings, back up the ledger you want to keep, then use Merge into this one.
- **Resolution:** Fixed in 0.2.0-beta. The older ledger is still saved. Merge puts it back. The addon does not merge by itself.

**Release 0.1.2-beta**

Open caveats. These were present in 0.1.2-beta. This release did not close them.

| Identifier | Found in | Resolved in | Description |
| --- | --- | --- | --- |
| [#3](https://github.com/Enlinks/guild-bank-ledger-forever/issues/3) | 0.1.1-beta | 0.1.3-beta | A tab purchase no longer appeared as two Buy tab lines. The purchase sentence was still stored, so the gold was counted twice. The issue stayed open. |
| Duplicate log line | 0.1.2-beta | 0.1.3-beta | A later scan stored one guild bank line again when the clock time moved, including a deposit that crossed midnight. |

**#3 Buying a guild bank tab stores the purchase twice**

- **Symptom:** One tab purchase appeared as two Buy tab lines, and the Tabs total counted that gold twice.
- **Conditions:** Seen in 0.1.1-beta. The money log reports the same gold as the purchase and as the withdrawal for the tab.
- **Workaround:** None.
- **Partial fix:** 0.1.2-beta stopped showing both lines. The purchase sentence was still stored, so Out and Tabs still counted the gold twice. The issue stayed open.
- **Resolution:** Fixed in 0.1.3-beta. The purchase sentence is not stored. The withdrawal stays, so the gold counts once.

**A scan stored the same log line twice**

- **Symptom:** One deposit or withdrawal appears twice after a later scan reads a different clock time. A 25s deposit was listed at 23:00 and again at midnight.
- **Conditions:** Seen in 0.1.2-beta. The ledger treated the moved clock time as a new line.
- **Workaround:** None.
- **Resolution:** Fixed in 0.1.3-beta. A line is the same one when the lines directly above and below it match. The first clock time stays.

No resolved caveats.

**Release 0.1.1-beta**

Open caveats. These were present in 0.1.1-beta. This release did not close them.

| Identifier | Found in | Resolved in | Description |
| --- | --- | --- | --- |
| [#3](https://github.com/Enlinks/guild-bank-ledger-forever/issues/3) | 0.1.1-beta | 0.1.3-beta | Buying a guild bank tab stored the purchase and the withdrawal. 0.1.2-beta stopped showing both lines. The gold was still counted twice until 0.1.3-beta. |

**#3 Buying a guild bank tab stores the purchase twice**

- **Symptom:** One tab purchase appears as two Buy tab lines, and the Tabs total counts that gold twice.
- **Conditions:** Seen in 0.1.1-beta when buying a guild bank tab. The money log reports the same gold as the purchase and as the withdrawal for the tab.
- **Workaround:** None.
- **Resolution:** Open in 0.1.1-beta. 0.1.2-beta fixed the two-line display only. Fixed in 0.1.3-beta, which stores the withdrawal and drops the purchase sentence.

Resolved caveats. These were present in 0.1.0-beta and are fixed in 0.1.1-beta.

| Identifier | Affected release | Resolved in | Description |
| --- | --- | --- | --- |
| [#2](https://github.com/Enlinks/guild-bank-ledger-forever/issues/2) | 0.1.0-beta | 0.1.1-beta | The copper icon on the ledger summary wrapped onto a second line. In, Out, Repairs, Tabs, and Net now stay on one line, including a gold total in the ten-thousands. |

**#2 Summary money wraps the copper icon onto a second line**

- **Symptom:** The copper coin on In, Out, Repairs, Tabs, and Net drops onto the status line.
- **Conditions:** Seen in 0.1.0-beta. Each total was drawn in a 114px cell.
- **Workaround:** None.
- **Resolution:** Fixed in 0.1.1-beta. The five totals share the summary bar.

**Release 0.1.0-beta**

Initial beta. No resolved caveats.
