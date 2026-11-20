Notes follow Cisco caveat style. A bug found in a shipped release is added to that release as an open caveat. When a later release fixes it, that earlier note stays and names the release that resolved it. The fixing release lists the same caveat under resolved caveats.

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
