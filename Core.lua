local addonName = ...

GBLF = GBLF or {}
GBLF.name = addonName

local DEFAULTS = {
	autoScan = true,
	rescanMinutes = 2,
	showMinimap = true,
	minimapAngle = 220,
	viewKey = nil,
	point = nil,
}

function GBLF.Print(text)
	local message = "|cffd6e2f5Guild Bank Ledger:|r " .. tostring(text)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(message)
	end
end

function GBLF.DB()
	return GuildBankLedgerForeverDB
end

local function fillDefaults(into, defaults)
	for key, value in pairs(defaults) do
		if into[key] == nil then
			if type(value) == "table" then
				into[key] = {}
				fillDefaults(into[key], value)
			else
				into[key] = value
			end
		end
	end
end

function GBLF.InitDB()
	if GBLF.dbReady then
		return
	end
	GuildBankLedgerForeverDB = GuildBankLedgerForeverDB or {}
	local db = GuildBankLedgerForeverDB
	db.version = 1
	db.settings = db.settings or {}
	fillDefaults(db.settings, DEFAULTS)
	db.guilds = db.guilds or {}
	for key, guild in pairs(db.guilds) do
		if type(guild) ~= "table" or type(key) ~= "string" then
			db.guilds[key] = nil
		else
			guild.txns = type(guild.txns) == "table" and guild.txns or {}
			guild.gaps = type(guild.gaps) == "table" and guild.gaps or {}
			guild.tabNames = type(guild.tabNames) == "table" and guild.tabNames or {}
			guild.nextId = guild.nextId or (#guild.txns + 1)
			guild.nextOrd = guild.nextOrd or guild.nextId
			if not guild.deduped then
				local removed = GBLF.Ledger.CollapseDuplicates(guild)
				guild.deduped = true
				if removed > 0 then
					GBLF.Print("Removed " .. removed .. " duplicated lines from " .. (guild.name or key) .. ".")
				end
			end
			local paired = GBLF.Ledger.CollapseTabPairs(guild)
			if paired > 0 then
				local noun = paired == 1 and "tab purchase" or "tab purchases"
				GBLF.Print("Removed " .. paired .. " duplicated " .. noun .. " from " .. (guild.name or key) .. ".")
			end
			local faded = GBLF.Ledger.PreferTimestamps(guild)
			if faded > 0 then
				local noun = faded == 1 and "date-only copy of a timed line" or "date-only copies of timed lines"
				GBLF.Print("Removed " .. faded .. " " .. noun .. " from " .. (guild.name or key) .. ".")
			end
			if not guild.requiredNames then
				local removed = GBLF.Ledger.DropNameless(guild)
				guild.requiredNames = true
				if removed > 0 then
					local noun = removed == 1 and "line with no character name" or "lines with no character name"
					GBLF.Print("Removed " .. removed .. " " .. noun .. " from " .. (guild.name or key) .. ".")
				end
			end
		end
	end
	GBLF.caches = {}
	for key, guild in pairs(db.guilds) do
		GBLF.caches[key] = GBLF.Ledger.Rebuild(guild)
	end
	local blank = GBLF.BlankRealmWarning(db.guilds)
	for i = 1, #blank do
		GBLF.Print("A recent game update left the realm name blank, so " .. blank[i] .. " started a second ledger. The older lines are still saved. In Settings, back up the ledger you want to keep, then use Merge into this one.")
	end
	GBLF.dbReady = true
end

function GBLF.BlankRealmWarning(guilds)
	local named = {}
	local blank = {}
	if type(guilds) ~= "table" then
		return blank
	end
	for _, guild in pairs(guilds) do
		if type(guild) == "table" then
			local name = guild.name
			local realm = guild.realm or ""
			if type(name) == "string" and name ~= "" then
				if realm == "" then
					blank[name] = true
				elseif string.sub(realm, 1, 7) ~= "backup-" then
					named[name] = true
				end
			end
		end
	end
	local found = {}
	for name in pairs(blank) do
		if named[name] then
			found[#found + 1] = name
		end
	end
	table.sort(found)
	return found
end

function GBLF.Settings()
	return GuildBankLedgerForeverDB.settings
end

function GBLF.Invalidate(key)
	if GBLF.caches then
		GBLF.caches[key] = nil
	end
end

function GBLF.CacheFor(key)
	local guild = GuildBankLedgerForeverDB.guilds[key]
	if not guild then
		return nil
	end
	local cache = GBLF.caches[key]
	if not cache then
		cache = GBLF.Ledger.Rebuild(guild)
		GBLF.caches[key] = cache
	end
	return cache
end

function GBLF.PlayerGuild()
	if not GetGuildInfo then
		return nil
	end
	local name = GetGuildInfo("player")
	if not name or name == "" then
		return nil
	end
	local realm = GetRealmName() or "Unknown"
	if GetNormalizedRealmName then
		realm = GetNormalizedRealmName() or realm
	end
	realm = string.gsub(realm, "%s+", "")
	return name .. "-" .. realm, name, realm
end

function GBLF.ViewKey()
	local settings = GBLF.Settings()
	if settings.viewKey and GuildBankLedgerForeverDB.guilds[settings.viewKey] then
		return settings.viewKey
	end
	return GBLF.PlayerGuild()
end

function GBLF.ViewGuild()
	local key = GBLF.ViewKey()
	if not key then
		return nil, nil
	end
	return key, GuildBankLedgerForeverDB.guilds[key]
end

function GBLF.TouchGuild(key, name, realm)
	local guild = GuildBankLedgerForeverDB.guilds[key]
	if not guild then
		guild = GBLF.Ledger.NewGuild(name, realm)
		GuildBankLedgerForeverDB.guilds[key] = guild
	end
	guild.name = name or guild.name
	guild.realm = realm or guild.realm
	return guild
end

local function ledgerTitle(guild, key)
	local name = (guild and guild.name) or key or ""
	local realm = guild and guild.realm or ""
	if realm ~= "" then
		return name .. " · " .. realm
	end
	return name
end

function GBLF.MergeGuilds(targetKey, sourceKey, removeSource)
	local db = GBLF.DB()
	if not db or type(db.guilds) ~= "table" then
		return nil, "There is no ledger to merge into."
	end
	if targetKey == sourceKey then
		return nil, "A ledger cannot be merged into itself."
	end
	local target = db.guilds[targetKey]
	local source = db.guilds[sourceKey]
	if not target or not source then
		return nil, "That ledger is no longer saved."
	end
	local added, seen = GBLF.Ledger.MergeGuild(target, source)
	if not added then
		return nil, seen
	end
	if removeSource then
		db.guilds[sourceKey] = nil
		GBLF.Invalidate(sourceKey)
		if db.settings and db.settings.viewKey == sourceKey then
			db.settings.viewKey = targetKey
		end
	end
	GBLF.Invalidate(targetKey)
	GBLF.CacheFor(targetKey)
	local kept = ledgerTitle(target, targetKey)
	local tail = removeSource and "The other ledger was removed." or "Both ledgers were kept."
	local message
	if added == 0 then
		message = string.format("No new lines for %s. %s", kept, tail)
	elseif added == 1 then
		message = string.format("Merged 1 line into %s. %s", kept, tail)
	else
		message = string.format("Merged %d lines into %s. %s", added, kept, tail)
	end
	GBLF.Print(message)
	if GBLF.UI and GBLF.UI.Refresh then
		GBLF.UI.Refresh()
	end
	return added, seen
end

function GBLF.BackupGuild(key)
	local db = GBLF.DB()
	if not db or type(db.guilds) ~= "table" or not db.guilds[key] then
		return nil, "This guild has no saved ledger."
	end
	local guild = db.guilds[key]
	local name = guild.name
	if type(name) ~= "string" or name == "" then
		return nil, "That ledger has no guild name to back up."
	end
	local stamp = GBLF.Now()
	local day = GBLF.Time.IsoDay(GBLF.Time.Pack(stamp.year, stamp.month, stamp.day))
	local base = string.format("backup-%s-%02d:%02d:%02d", day, stamp.hour or 0, stamp.min or 0, stamp.sec or 0)
	local realm = base
	local try = 1
	while db.guilds[name .. "-" .. realm] do
		try = try + 1
		realm = base .. "-" .. try
	end
	local backupKey = name .. "-" .. realm
	local copy = GBLF.Ledger.CopyGuild(guild, realm)
	db.guilds[backupKey] = copy
	GBLF.Invalidate(backupKey)
	GBLF.CacheFor(backupKey)
	GBLF.Print("Saved a backup as " .. ledgerTitle(copy, backupKey) .. ".")
	if GBLF.UI and GBLF.UI.Refresh then
		GBLF.UI.Refresh()
	end
	return backupKey
end

function GBLF.DeleteGuild(key)
	local db = GuildBankLedgerForeverDB
	if not db.guilds[key] then
		return
	end
	db.guilds[key] = nil
	GBLF.Invalidate(key)
	if db.settings.viewKey == key then
		db.settings.viewKey = nil
	end
	GBLF.Print("Deleted the ledger for " .. key .. ".")
	if GBLF.UI and GBLF.UI.Refresh then
		GBLF.UI.Refresh()
	end
end

local function secondsFromServer()
	local unix = GetServerTime and GetServerTime() or nil
	if not unix and time then
		local ok, value = pcall(time)
		if ok then
			unix = value
		end
	end
	if date and unix then
		local stamp = date("*t", unix)
		if stamp and stamp.sec then
			return stamp.sec
		end
	end
	return nil
end

function GBLF.Now()
	if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
		local stamp = C_DateAndTime.GetCurrentCalendarTime()
		if stamp and stamp.year and stamp.month and stamp.monthDay then
			local sec = stamp.second or stamp.seconds or stamp.sec
			if sec == nil then
				sec = secondsFromServer() or 0
			end
			return {
				year = stamp.year,
				month = stamp.month,
				day = stamp.monthDay,
				hour = stamp.hour or 0,
				min = stamp.minute or 0,
				sec = sec,
			}
		end
	end
	local unix = GetServerTime and GetServerTime() or nil
	if date and unix then
		local stamp = date("*t", unix)
		if stamp then
			return {
				year = stamp.year,
				month = stamp.month,
				day = stamp.day,
				hour = stamp.hour or 0,
				min = stamp.min or 0,
				sec = stamp.sec or 0,
			}
		end
	end
	return { year = 2026, month = 1, day = 1, hour = 0, min = 0, sec = 0 }
end

function GBLF.TabLabel(guild, tab)
	if not tab then
		return ""
	end
	local name = guild and guild.tabNames and guild.tabNames[tab]
	if type(name) == "string" and name ~= "" then
		return name
	end
	return "Tab " .. tostring(tab)
end

function GBLF.FormatMoneyCompact(copper)
	copper = math.floor(tonumber(copper) or 0)
	local negative = copper < 0
	if negative then
		copper = -copper
	end
	local gold = math.floor(copper / 10000)
	local silver = math.floor((copper % 10000) / 100)
	local rest = copper % 100
	local text
	if gold > 0 then
		text = string.format("%dg %02ds %02dc", gold, silver, rest)
	elseif silver > 0 then
		text = string.format("%ds %02dc", silver, rest)
	else
		text = string.format("%dc", rest)
	end
	if negative and copper > 0 then
		return "-" .. text
	end
	return text
end

function GBLF.FormatMoney(copper)
	copper = math.floor(tonumber(copper) or 0)
	local negative = copper < 0
	local amount = negative and -copper or copper
	local text
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		text = C_CurrencyInfo.GetCoinTextureString(amount)
	elseif GetCoinTextureString then
		text = GetCoinTextureString(amount)
	else
		text = GBLF.FormatMoneyCompact(amount)
	end
	if negative and amount > 0 then
		return "-" .. text
	end
	return text
end

function GBLF.IsBankOpen()
	if GuildBankFrame and GuildBankFrame.IsShown and GuildBankFrame:IsShown() then
		return true
	end
	local kinds = Enum and Enum.PlayerInteractionType
	local manager = C_PlayerInteractionManager
	if kinds and manager and manager.IsInteractingWithNpcOfType then
		local kind = kinds.GuildBanker or kinds.GuildBank
		if kind then
			local ok, interacting = pcall(manager.IsInteractingWithNpcOfType, kind)
			if ok and interacting then
				return true
			end
		end
	end
	return false
end

function GBLF.SavedGuilds()
	local rows = {}
	for key, guild in pairs(GuildBankLedgerForeverDB.guilds) do
		rows[#rows + 1] = {
			key = key,
			name = guild.name or key,
			realm = guild.realm or "",
			lines = guild.txns and #guild.txns or 0,
			lastScan = guild.lastScan,
		}
	end
	table.sort(rows, function(a, b)
		return a.key < b.key
	end)
	return rows
end

local function slashMain(message)
	message = string.lower(message or "")
	message = string.match(message, "^%s*(.-)%s*$") or ""
	if not GBLF.UI or not GBLF.UI.Toggle then
		return
	end
	if message == "" or message == "show" or message == "toggle" then
		GBLF.UI.Toggle()
	elseif message == "scan" then
		GBLF.Scan.Start("slash")
	elseif message == "status" then
		local key, guild = GBLF.ViewGuild()
		if not guild then
			GBLF.Print(key and (key .. " has no saved lines yet.") or "No guild ledger yet.")
		else
			local gaps = guild.gaps and #guild.gaps or 0
			GBLF.Print(string.format("%s: %d lines, %d gaps.", key, #guild.txns, gaps))
		end
	else
		GBLF.Print("Commands: /ledger, /gblf scan, /scan, /gblf status.")
	end
end

SLASH_GUILDBANKLEDGERFOREVER1 = "/gblf"
SLASH_GUILDBANKLEDGERFOREVER2 = "/ledger"
SlashCmdList.GUILDBANKLEDGERFOREVER = slashMain

SLASH_GUILDBANKLEDGERFOREVERSCAN1 = "/scan"
SlashCmdList.GUILDBANKLEDGERFOREVERSCAN = function()
	GBLF.Scan.Start("slash")
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GUILDBANKFRAME_OPENED")
events:RegisterEvent("GUILDBANKFRAME_CLOSED")
events:RegisterEvent("GUILDBANKLOG_UPDATE")
events:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
events:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")

local function interactionIsBank(kind)
	local kinds = Enum and Enum.PlayerInteractionType
	if not kinds or kind == nil then
		return false
	end
	return kind == kinds.GuildBanker or kind == kinds.GuildBank
end

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		GBLF.InitDB()
		GBLF.UI.Init()
	elseif event == "PLAYER_LOGIN" then
		GBLF.InitDB()
		GBLF.UI.Init()
	elseif event == "GUILDBANKFRAME_OPENED" then
		GBLF.Scan.OnBankOpened()
	elseif event == "GUILDBANKFRAME_CLOSED" then
		GBLF.Scan.OnBankClosed()
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and interactionIsBank(arg1) then
		GBLF.Scan.OnBankOpened()
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and interactionIsBank(arg1) then
		GBLF.Scan.OnBankClosed()
	elseif event == "GUILDBANKLOG_UPDATE" then
		GBLF.Scan.OnLogUpdate()
	end
end)
