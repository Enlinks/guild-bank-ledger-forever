-- WoW Forever uses the 12.1.5 interface. That patch removed
-- Blizzard_DeprecatedCurrencyScript and Blizzard_DeprecatedItemScript,
-- so the old global names are nil there. Classic clients still define them.
local function restore(name, namespace, method)
    if _G[name] == nil and type(namespace) == "table" and namespace[method] then
        _G[name] = namespace[method]
    end
end

restore("GetCoinTextureString", C_CurrencyInfo, "GetCoinTextureString")
restore("GetCoinText", C_CurrencyInfo, "GetCoinText")
restore("GetCoinIcon", C_CurrencyInfo, "GetCoinIcon")
restore("GetItemInfoInstant", C_Item, "GetItemInfoInstant")
restore("GetItemInfo", C_Item, "GetItemInfo")
