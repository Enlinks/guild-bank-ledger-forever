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
