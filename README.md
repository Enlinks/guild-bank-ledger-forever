# **Guild Bank Snapshots (WoW Forever)**

Compatibility copy of [nikkisaurus/GuildBankSnapshots](https://github.com/nikkisaurus/GuildBankSnapshots) for WoW Forever (interface 16001, the 12.1.5 API).

WoW Forever removed the old currency and item globals. Opening Analyze and selecting a money tab called `GetCoinTextureString`, which is nil on this client, and the tab died at `Modules/Analyze.lua:148`. The same removal breaks money export (`GetCoinText`) and bank scans (`GetItemInfoInstant`). `Compat.lua` points those names at `C_CurrencyInfo` and `C_Item` when the globals are missing, and leaves them alone on clients that still have them.

## Install

Copy the `GuildBankSnapshots` folder into:

`World of Warcraft/_classic_beta_/Interface/AddOns/`

The folder name has to stay `GuildBankSnapshots`. Saved snapshots live under that name. Replace an existing copy, then `/reload`. If the CurseForge app manages this addon, it will overwrite this folder on the next update.

Visit your guild bank and type **/scan**. Open the window with **/gbs**.

## Upstream

Guild Bank Snapshots documents and analyzes guild bank logs. A snapshot records guild bank transactions and can be broken down by player, item, and money.

## **Feedback and Issues**

All feature requests and issue reports should be addressed through the [issue tracker](https://github.com/nikkisaurus/guildbanksnapshots/issues).

## **Links**

-   [Curseforge](https://www.curseforge.com/wow/addons/guild-bank-snapshots)
-   [Discord](https://discord.gg/tSeVUJaM3u)
-   [Github](https://github.com/nikkisaurus/GuildBankSnapshots)
-   [Wago](https://addons.wago.io/addons/guild-bank-snapshots)
-   [WoW Interface](https://www.wowinterface.com/downloads/info22913-GuildBankSnapshots.html)

## **Donate**

Any [donations](https://www.paypal.com/donate/?business=NYN3WUR4A68SE&no_recurring=0&currency_code=USD) are much appreciated!
