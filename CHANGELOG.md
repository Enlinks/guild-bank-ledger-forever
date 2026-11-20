**Release 0.1.3-beta**

Resolved caveats. These were present in 0.1.2-beta and are fixed in 0.1.3-beta.

| Identifier | Affected release | Resolved in | Description |
| --- | --- | --- | --- |
| [#3](https://github.com/Enlinks/guild-bank-ledger-forever/issues/3) | 0.1.2-beta | 0.1.3-beta | Buying a guild bank tab still counted the gold twice. The purchase sentence was stored along with the withdrawal. |
| Duplicate log line | 0.1.2-beta | 0.1.3-beta | A later scan stored one guild bank line again when the clock time moved, including a deposit that crossed midnight. |

**#3 Buying a guild bank tab stores the purchase twice**

- **Symptom:** One tab purchase adds the gold to Out twice. A 100g tab added 200g.
- **Conditions:** Seen in 0.1.2-beta. The money log reports the withdrawal and a purchase sentence for the same gold. 0.1.2-beta kept both.
- **Workaround:** None.
- **Resolution:** Fixed in 0.1.3-beta. The purchase sentence is not stored. The withdrawal stays, so the gold counts once. A purchase line already saved is removed the next time the addon loads.

**A scan stored the same log line twice**

- **Symptom:** One deposit or withdrawal appears twice after a later scan reads a different clock time. A 25s deposit was listed at 23:00 and again at midnight.
- **Conditions:** Seen in 0.1.2-beta. The ledger treated the moved clock time as a new line.
- **Workaround:** None.
- **Resolution:** Fixed in 0.1.3-beta. A line is the same one when the lines directly above and below it match. The first clock time stays. The next scan of that part of the log removes a copy already saved.

**Release 0.1.2-beta**

Resolved caveats. These were present in 0.1.1-beta and are fixed in 0.1.2-beta.

| Identifier | Affected release | Resolved in | Description |
| --- | --- | --- | --- |
| [#3](https://github.com/Enlinks/guild-bank-ledger-forever/issues/3) | 0.1.1-beta | 0.1.2-beta | Buying a guild bank tab stored the purchase twice. The money log lists it as the purchase and as the withdrawal for the tab. Both showed as Buy tab, and the Tabs total counted the gold twice. |

**#3 Buying a guild bank tab stores the purchase twice**

- **Symptom:** One tab purchase appears as two Buy tab lines, and the Tabs total counts that gold twice.
- **Conditions:** Seen in 0.1.1-beta when buying a guild bank tab. The money log reports the same gold as the purchase and as the withdrawal for the tab.
- **Workaround:** None.
- **Resolution:** Fixed in 0.1.2-beta. The purchase is stored once. An extra line already saved is removed the next time the addon loads.

**Release 0.1.1-beta**

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
