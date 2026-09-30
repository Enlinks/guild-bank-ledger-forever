local addonName, private = ...
local addon = LibStub("AceAddon-3.0"):GetAddon(addonName)
local L = LibStub("AceLocale-3.0"):GetLocale(addonName, true)
local AceGUI = LibStub("AceGUI-3.0")

-- The log stores age in whole hours, and the minutes on the reconstructed time
-- come from the scan clock. The same line can land on either side of a clock
-- hour, so match on the other fields when the times are less than an hour apart.
local function EventTime(scanTime, info)
    return private:GetTransactionDate(scanTime, info.year or 0, info.month or 0, info.day or 0, info.hour or 0)
end

local function Seen(seen, identity, when)
    local times = seen[identity]
    if not times then
        seen[identity] = { when }
        return false
    end
    for i = 1, #times do
        if math.abs(times[i] - when) < 3600 then
            return true
        end
    end
    times[#times + 1] = when
    return false
end

local function Key(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    return table.concat(parts, "\31")
end

local function ItemSortName(link)
    local _, _, name = strfind(select(3, strfind(link or "", "|H(.+)|h")) or "", "%[(.+)%]")
    return name or link or ""
end

local function NewCharacter()
    return {
        withdraw = {},
        deposit = {},
        move = {},
        money = {
            buyTab = 0,
            repair = 0,
            deposit = 0,
            withdraw = 0,
        },
    }
end

local function NewItem()
    return {
        withdraw = {},
        deposit = {},
        move = {},
    }
end

local function EnsureCharacter(ledger, name)
    local character = ledger.byCharacter[name]
    if not character then
        character = NewCharacter()
        ledger.byCharacter[name] = character
        ledger.names[name] = name
    end
    return character
end

local function EnsureItem(ledger, itemLink)
    local item = ledger.byItem[itemLink]
    if not item then
        item = NewItem()
        ledger.byItem[itemLink] = item
        ledger.items[itemLink] = itemLink
    end
    return item
end

local function AddCount(map, key, count)
    map[key] = count + (map[key] or 0)
end

local function BuildLedger(guildKey)
    local guild = guildKey and private.db.global.guilds[guildKey]
    local scans = guild and guild.scans
    if not scans or not next(scans) then
        return
    end

    local ledger = {
        totalMoney = 0,
        money = {
            totalMoney = 0,
            buyTab = {},
            repair = {},
            deposit = {},
            withdraw = {},
        },
        byItem = {},
        byCharacter = {},
        names = {},
        items = {},
    }
    local seen = {}

    for scanTime, scan in
        addon.pairs(scans, function(a, b)
            return a < b
        end)
    do
        scanTime = tonumber(scanTime)
        if scanTime then
            if type(scan.totalMoney) == "number" then
                ledger.totalMoney = scan.totalMoney
                ledger.money.totalMoney = scan.totalMoney
            end

            for tab, tabInfo in pairs(scan.tabs or {}) do
                for _, transaction in pairs(tabInfo.transactions or {}) do
                    local info = private:GetTransactionInfo(transaction)
                    if info and info.transactionType and type(info.count) == "number" then
                        info.name = info.name or L["Unknown"]
                        local identity = Key("item", tab, info.transactionType, info.name, info.itemLink, info.count, info.moveOrigin or 0, info.moveDestination or 0)
                        if not Seen(seen, identity, EventTime(scanTime, info)) then
                            local character = EnsureCharacter(ledger, info.name)
                            local item = EnsureItem(ledger, info.itemLink)
                            local itemMap = item[info.transactionType]
                            local characterMap = character[info.transactionType]
                            if itemMap then
                                AddCount(itemMap, info.name, info.count)
                            end
                            if characterMap then
                                AddCount(characterMap, info.itemLink, info.count)
                            end
                        end
                    end
                end
            end

            for _, transaction in pairs(scan.moneyTransactions or {}) do
                local info = private:GetMoneyTransactionInfo(transaction)
                if info and info.transactionType and type(info.amount) == "number" then
                    info.name = info.name or L["Unknown"]
                    local identity = Key("money", info.transactionType, info.name, info.amount)
                    if not Seen(seen, identity, EventTime(scanTime, info)) then
                        local character = EnsureCharacter(ledger, info.name)
                        local moneyMap = ledger.money[info.transactionType]
                        if moneyMap then
                            AddCount(moneyMap, info.name, info.amount)
                        end
                        character.money[info.transactionType] = (character.money[info.transactionType] or 0) + info.amount
                    end
                end
            end
        end
    end

    return ledger
end

local function NameOrder(names)
    local sorting = {}
    for name in
        addon.pairs(names, function(a, b)
            return a < b
        end)
    do
        tinsert(sorting, name)
    end
    return sorting
end

local function ItemOrder(items)
    local sorting = {}
    for itemLink in
        addon.pairs(items, function(a, b)
            return ItemSortName(a) < ItemSortName(b)
        end)
    do
        tinsert(sorting, itemLink)
    end
    return sorting
end

local function moneyTabGroupList(moneyInfo)
    return {
        {
            value = "summary",
            text = L["Summary"],
        },
        {
            value = "roster",
            text = L["All Characters"],
            disabled = not private:HasMoneyRoster(moneyInfo),
        },
        {
            value = "deposit",
            text = L["Deposits"],
            disabled = addon.tcount(moneyInfo.deposit) == 0,
        },
        {
            value = "withdraw",
            text = L["Withdrawals"],
            disabled = addon.tcount(moneyInfo.withdraw) == 0,
        },
        {
            value = "repair",
            text = L["Repairs"],
            disabled = addon.tcount(moneyInfo.repair) == 0,
        },
    }
end

local function itemTabGroupList(itemInfo)
    return {
        {
            value = "deposit",
            text = L["Deposits"],
            disabled = addon.tcount(itemInfo.deposit) == 0,
        },
        {
            value = "withdraw",
            text = L["Withdrawals"],
            disabled = addon.tcount(itemInfo.withdraw) == 0,
        },
    }
end

local function charTabGroupList(charInfo)
    return {
        {
            value = "summary",
            text = L["Summary"],
        },
        {
            value = "deposit",
            text = L["Deposits"],
            disabled = addon.tcount(charInfo.deposit) == 0,
        },
        {
            value = "withdraw",
            text = L["Withdrawals"],
            disabled = addon.tcount(charInfo.withdraw) == 0,
        },
    }
end

local tabGroupList = {
    {
        value = "Character",
        text = L["Character"],
    },
    {
        value = "Item",
        text = L["Item"],
    },
    {
        value = "Money",
        text = L["Money"],
    },
}

local function SelectMoneyGroupTab(moneyTabGroup, tab, moneyInfo)
    private.selectedLedgerMoneyTab = tab
    moneyTabGroup:ReleaseChildren()

    local scrollFrame = AceGUI:Create("ScrollFrame")
    scrollFrame:SetLayout("List")
    moneyTabGroup:AddChild(scrollFrame)

    if tab == "summary" then
        local money = AceGUI:Create("InlineGroup")
        money:SetLayout("Flow")
        money:SetFullWidth(true)
        money:SetTitle(L["Money"])
        scrollFrame:AddChild(money)

        local totalMoney = AceGUI:Create("Label")
        totalMoney:SetFullWidth(true)
        totalMoney:SetText(format("%s: %s|r", L["Total Money"], GetCoinTextureString(math.abs(moneyInfo.totalMoney))))
        money:AddChild(totalMoney)

        local deposits = 0
        for _, count in pairs(moneyInfo.deposit) do
            deposits = deposits + count
        end
        for _, count in pairs(moneyInfo.buyTab) do
            deposits = deposits + count
        end
        local moneyDeposits = AceGUI:Create("Label")
        moneyDeposits:SetFullWidth(true)
        moneyDeposits:SetText(format("%s: %s", L["Deposits"], GetCoinTextureString(deposits)))
        money:AddChild(moneyDeposits)

        local withdrawals = 0
        for _, count in pairs(moneyInfo.withdraw) do
            withdrawals = withdrawals + count
        end
        local moneyWithdrawals = AceGUI:Create("Label")
        moneyWithdrawals:SetFullWidth(true)
        moneyWithdrawals:SetText(format("%s: %s", L["Withdrawals"], GetCoinTextureString(withdrawals)))
        money:AddChild(moneyWithdrawals)

        local repairs = 0
        for _, count in pairs(moneyInfo.repair) do
            repairs = repairs + count
        end
        local moneyRepairs = AceGUI:Create("Label")
        moneyRepairs:SetFullWidth(true)
        moneyRepairs:SetText(format("%s: %s", L["Repairs"], GetCoinTextureString(repairs)))
        money:AddChild(moneyRepairs)

        local netCount = deposits - withdrawals - repairs
        local red = LibStub("LibAddonUtils-1.0").ChatColors["RED"]
        local white = LibStub("LibAddonUtils-1.0").ChatColors["WHITE"]

        local netMoney = AceGUI:Create("Label")
        netMoney:SetFullWidth(true)
        netMoney:SetText(format("%s: %s%s|r", L["Net"], netCount < 0 and red or white, GetCoinTextureString(math.abs(netCount))))
        money:AddChild(netMoney)
    elseif tab == "roster" then
        private:FillMoneyRoster(scrollFrame, moneyInfo)
    elseif tab == "deposit" then
        for character, count in addon.pairs(moneyInfo.deposit) do
            local line = AceGUI:Create("GuildBankSnapshotsTransaction")
            line:SetFullWidth(true)
            line:SetText(format("%s: %s", character, GetCoinTextureString(count)))
            scrollFrame:AddChild(line)
        end
    elseif tab == "withdraw" then
        for character, count in addon.pairs(moneyInfo.withdraw) do
            local line = AceGUI:Create("GuildBankSnapshotsTransaction")
            line:SetFullWidth(true)
            line:SetText(format("%s: %s", character, GetCoinTextureString(count)))
            scrollFrame:AddChild(line)
        end
    elseif tab == "repair" then
        for character, count in addon.pairs(moneyInfo.repair) do
            local line = AceGUI:Create("GuildBankSnapshotsTransaction")
            line:SetFullWidth(true)
            line:SetText(format("%s: %s", character, GetCoinTextureString(count)))
            scrollFrame:AddChild(line)
        end
    end
end

local function SelectMoneyTab(tabGroup, ledger)
    local moneyTabGroup = AceGUI:Create("TabGroup")
    moneyTabGroup:SetLayout("Flow")
    moneyTabGroup:SetTabs(moneyTabGroupList(ledger.money))
    moneyTabGroup:SetCallback("OnGroupSelected", function(moneyTabGroup, _, tab)
        SelectMoneyGroupTab(moneyTabGroup, tab, ledger.money)
    end)
    tabGroup:AddChild(moneyTabGroup)
    moneyTabGroup:SelectTab(private.selectedLedgerMoneyTab or "summary")
end

local function SelectItemGroupTab(itemTabGroup, tab, itemInfo)
    private.selectedLedgerItemTab = tab
    itemTabGroup:ReleaseChildren()

    local scrollFrame = AceGUI:Create("ScrollFrame")
    scrollFrame:SetLayout("List")
    itemTabGroup:AddChild(scrollFrame)

    if tab == "deposit" then
        for character, count in addon.pairs(itemInfo.deposit) do
            local line = AceGUI:Create("GuildBankSnapshotsTransaction")
            line:SetFullWidth(true)
            line:SetText(format("%s x%d", character, count))
            scrollFrame:AddChild(line)
        end
    elseif tab == "withdraw" then
        for character, count in addon.pairs(itemInfo.withdraw) do
            local line = AceGUI:Create("GuildBankSnapshotsTransaction")
            line:SetFullWidth(true)
            line:SetText(format("%s x%d", character, count))
            scrollFrame:AddChild(line)
        end
    end
end

local function SelectItem(itemGroup, _, item, ledger)
    private.selectedLedgerItem = item
    private.selectedLedgerItemTab = nil
    itemGroup:ReleaseChildren()

    if not item or not ledger.byItem[item] then
        return
    end

    local itemInfo = ledger.byItem[item]
    local itemTabGroup = AceGUI:Create("TabGroup")
    itemTabGroup:SetLayout("Flow")
    itemTabGroup:SetTabs(itemTabGroupList(itemInfo))
    itemTabGroup:SetCallback("OnGroupSelected", function(itemTabGroup, _, tab)
        SelectItemGroupTab(itemTabGroup, tab, itemInfo)
    end)
    itemGroup:AddChild(itemTabGroup)
    itemTabGroup:SelectTab(private.selectedLedgerItemTab or "deposit")
end

local function SelectItemTab(tabGroup, ledger)
    tabGroup:SetLayout("Fill")

    local itemGroup = AceGUI:Create("DropdownGroup")
    itemGroup:SetLayout("Fill")
    itemGroup:SetGroupList(ledger.items, ItemOrder(ledger.items))
    itemGroup:SetCallback("OnGroupSelected", function(itemGroup, _, item)
        SelectItem(itemGroup, _, item, ledger)
    end)
    tabGroup:AddChild(itemGroup)
    local item = ledger.items[private.selectedLedgerItem] and private.selectedLedgerItem or nil
    itemGroup:SetGroup(item)
end

local function SelectCharacterGroupTab(charTabGroup, tab, charInfo)
    private.selectedLedgerCharTab = tab
    charTabGroup:ReleaseChildren()

    local scrollFrame = AceGUI:Create("ScrollFrame")
    scrollFrame:SetLayout("List")
    charTabGroup:AddChild(scrollFrame)

    if tab == "summary" then
        local items = AceGUI:Create("InlineGroup")
        items:SetLayout("Flow")
        items:SetFullWidth(true)
        items:SetTitle(L["Items"])
        scrollFrame:AddChild(items)

        local total = 0
        for _, count in pairs(charInfo.deposit) do
            total = total + count
        end

        local deposits = AceGUI:Create("Label")
        deposits:SetFullWidth(true)
        deposits:SetText(format("%s: %d (%d)", L["Deposits"], addon.tcount(charInfo.deposit), total))
        items:AddChild(deposits)

        total = 0
        for _, count in pairs(charInfo.withdraw) do
            total = total + count
        end

        local withdrawals = AceGUI:Create("Label")
        withdrawals:SetFullWidth(true)
        withdrawals:SetText(format("%s: %d (%d)", L["Withdrawals"], addon.tcount(charInfo.withdraw), total))
        items:AddChild(withdrawals)

        local money = AceGUI:Create("InlineGroup")
        money:SetLayout("Flow")
        money:SetFullWidth(true)
        money:SetTitle(L["Money"])
        scrollFrame:AddChild(money)

        local moneyDeposits = AceGUI:Create("Label")
        moneyDeposits:SetFullWidth(true)
        moneyDeposits:SetText(format("%s: %s", L["Deposits"], GetCoinTextureString(charInfo.money.deposit + charInfo.money.buyTab)))
        money:AddChild(moneyDeposits)

        local moneyWithdrawals = AceGUI:Create("Label")
        moneyWithdrawals:SetFullWidth(true)
        moneyWithdrawals:SetText(format("%s: %s", L["Withdrawals"], GetCoinTextureString(charInfo.money.withdraw)))
        money:AddChild(moneyWithdrawals)

        local repairs = AceGUI:Create("Label")
        repairs:SetFullWidth(true)
        repairs:SetText(format("%s: %s", L["Repairs"], GetCoinTextureString(charInfo.money.repair)))
        money:AddChild(repairs)

        local netCount = charInfo.money.deposit + charInfo.money.buyTab - charInfo.money.withdraw - charInfo.money.repair
        local red = LibStub("LibAddonUtils-1.0").ChatColors["RED"]
        local white = LibStub("LibAddonUtils-1.0").ChatColors["WHITE"]

        local netMoney = AceGUI:Create("Label")
        netMoney:SetFullWidth(true)
        netMoney:SetText(format("%s: %s%s|r", L["Net"], netCount < 0 and red or white, GetCoinTextureString(math.abs(netCount))))
        money:AddChild(netMoney)
    elseif tab == "deposit" then
        for itemLink, count in
            addon.pairs(charInfo.deposit, function(a, b)
                return ItemSortName(a) < ItemSortName(b)
            end)
        do
            local line = AceGUI:Create("GuildBankSnapshotsTransaction")
            line:SetFullWidth(true)
            line:SetText(format("%s x%d", itemLink, count))
            scrollFrame:AddChild(line)
        end
    elseif tab == "withdraw" then
        for itemLink, count in
            addon.pairs(charInfo.withdraw, function(a, b)
                return ItemSortName(a) < ItemSortName(b)
            end)
        do
            local line = AceGUI:Create("GuildBankSnapshotsTransaction")
            line:SetFullWidth(true)
            line:SetText(format("%s x%d", itemLink, count))
            scrollFrame:AddChild(line)
        end
    end
end

local function SelectCharacter(characterGroup, _, character, ledger)
    private.selectedLedgerCharacter = character
    private.selectedLedgerCharTab = nil
    characterGroup:ReleaseChildren()

    if not character or not ledger.byCharacter[character] then
        return
    end

    local charInfo = ledger.byCharacter[character]
    local charTabGroup = AceGUI:Create("TabGroup")
    charTabGroup:SetLayout("Flow")
    charTabGroup:SetTabs(charTabGroupList(charInfo))
    charTabGroup:SetCallback("OnGroupSelected", function(charTabGroup, _, tab)
        SelectCharacterGroupTab(charTabGroup, tab, charInfo)
    end)
    characterGroup:AddChild(charTabGroup)
    charTabGroup:SelectTab(private.selectedLedgerCharTab or "summary")
end

local function SelectCharacterTab(tabGroup, ledger)
    tabGroup:SetLayout("Fill")

    local characterGroup = AceGUI:Create("DropdownGroup")
    characterGroup:SetLayout("Fill")
    characterGroup:SetGroupList(ledger.names, NameOrder(ledger.names))
    characterGroup:SetCallback("OnGroupSelected", function(characterGroup, _, character)
        SelectCharacter(characterGroup, _, character, ledger)
    end)
    tabGroup:AddChild(characterGroup)
    local character = ledger.names[private.selectedLedgerCharacter] and private.selectedLedgerCharacter or nil
    characterGroup:SetGroup(character)
end

local function SelectTab(tabGroup, _, tab, ledger)
    private.selectedLedgerTab = tab
    tabGroup:ReleaseChildren()

    if tab == "Character" then
        SelectCharacterTab(tabGroup, ledger)
    elseif tab == "Item" then
        SelectItemTab(tabGroup, ledger)
    elseif tab == "Money" then
        SelectMoneyTab(tabGroup, ledger)
    end
end

local function ShowLedger(parent, ledger)
    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetLayout("Fill")
    tabGroup:SetTabs(tabGroupList)
    tabGroup:SetCallback("OnGroupSelected", function(tabGroup, _, tab)
        SelectTab(tabGroup, _, tab, ledger)
    end)
    parent:AddChild(tabGroup)
    tabGroup:SelectTab(private.selectedLedgerTab or "Character")
end

function private:GetLedgerOptions(content)
    content:SetLayout("Fill")

    local guildGroup = AceGUI:Create("DropdownGroup")
    guildGroup:SetLayout("Fill")
    guildGroup:SetGroupList(private:GetGuildList())
    guildGroup:SetCallback("OnGroupSelected", function(guildGroup, _, guildKey)
        if guildKey then
            private.selectedGuild = guildKey
        end
        guildGroup:ReleaseChildren()

        local ledger = BuildLedger(private.selectedGuild)
        if not ledger then
            return
        end
        ShowLedger(guildGroup, ledger)
    end)
    content:AddChild(guildGroup)
    guildGroup:SetGroup(private.selectedGuild or private.db.global.settings.preferences.defaultGuild)
end
