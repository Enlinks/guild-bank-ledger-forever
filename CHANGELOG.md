# Changelog

## 3.8.2-forever.1

* Load on WoW Forever (interface 16001) via `GuildBankSnapshots_Camelot.toc`.
* Restore `GetCoinTextureString`, `GetCoinText`, `GetItemInfoInstant`, and `GetItemInfo` from `C_CurrencyInfo` / `C_Item` after the 12.1.5 deprecation fallbacks were removed. This is the Analyze money-tab error at `Modules/Analyze.lua:148`.
* Vendor Ace3 and LibAddonUtils so a git checkout can be copied straight into AddOns.
