-- Reads the guild bank log while the bank is open and appends new lines.
-- Item tabs and the money log are separate streams. A move is stored once,
-- from the tab it left. An unfinished scan is thrown away if the bank closes.

GBLF = GBLF or {}
GBLF.Scan = {}

local Scan = GBLF.Scan

local scan = {
	running = false,
	token = 0,
	query = 0,
	waiting = nil,
	index = 1,
	queue = {},
	captured = {},
	attempt = 0,
}

local function later(seconds, fn)
	if C_Timer and C_Timer.After then
		C_Timer.After(seconds, fn)
		return
	end
	local waiter = CreateFrame("Frame")
	local elapsed = 0
	waiter:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta
		if elapsed >= seconds then
			self:SetScript("OnUpdate", nil)
			fn()
		end
	end)
end

local function absolute(value)
	value = math.floor(tonumber(value) or 0)
	if value < 0 then
		return -value
	end
	return value
end

local function person(name)
	if type(name) ~= "string" or name == "" then
		return "Unknown"
	end
	return name
end

local function itemIdOf(link)
	if type(link) ~= "string" or link == "" then
		return nil
	end
	if C_Item and C_Item.GetItemInfoInstant then
		local id = C_Item.GetItemInfoInstant(link)
		if id then
			return id
		end
	end
	if GetItemInfoInstant then
		local id = GetItemInfoInstant(link)
		if id then
			return id
		end
	end
	local id = string.match(link, "item:(%d+)")
	return id and tonumber(id) or nil
end

local function itemNameOf(link, itemID)
	if type(link) == "string" then
		local name = string.match(link, "%[(.-)%]")
		if name and name ~= "" then
			return name
		end
	end
	if itemID and C_Item and C_Item.GetItemNameByID then
		local name = C_Item.GetItemNameByID(itemID)
		if name and name ~= "" then
			return name
		end
	end
	return nil
end

local function stampRow(now, years, months, days, hours, apiIndex)
	local when = GBLF.Time.FromAge(now, years, months, days, hours)
	return {
		day = when.day,
		hour = when.hour,
		precision = when.precision,
		ageRank = when.ageRank,
		apiIndex = apiIndex,
	}
end

local function readItems(tab, now)
	local count = 0
	if GetNumGuildBankTransactions then
		count = GetNumGuildBankTransactions(tab) or 0
	end
	local rows = {}
	for index = 1, count do
		local ok, kind, name, link, stack, origin, destination, years, months, days, hours =
			pcall(GetGuildBankTransaction, tab, index)
		if ok and kind and kind ~= "" then
			local fromOrigin = kind == "move" and origin and origin > 0 and origin ~= tab
			if not fromOrigin then
				local itemID = itemIdOf(link)
				local row = stampRow(now, years, months, days, hours, index)
				row.action = kind
				row.who = person(name)
				row.itemID = itemID
				row.itemName = itemNameOf(link, itemID)
				if stack then
					row.count = absolute(stack)
				end
				if origin and origin > 0 then
					row.tab = origin
				else
					row.tab = tab
				end
				if kind == "move" then
					row.dest = destination
				end
				rows[#rows + 1] = row
			end
		end
	end
	return GBLF.Ledger.OrderScanRows(rows)
end

local function readMoney(now)
	local count = 0
	if GetNumGuildBankMoneyTransactions then
		count = GetNumGuildBankMoneyTransactions() or 0
	end
	local rows = {}
	for index = 1, count do
		local ok, kind, name, amount, years, months, days, hours = pcall(GetGuildBankMoneyTransaction, index)
		if ok and kind and kind ~= "" then
			local row = stampRow(now, years, months, days, hours, index)
			row.action = kind
			row.who = person(name)
			row.copper = absolute(amount)
			if kind == "depositSummary" then
				row.summary = true
			end
			rows[#rows + 1] = row
		end
	end
	return GBLF.Ledger.OrderScanRows(rows)
end

local function streamLabel(stream)
	if stream == "money" then
		return "the money log"
	end
	local tab = string.match(stream, "^tab:(%d+)$")
	if tab then
		return "tab " .. tab
	end
	return stream
end

local function finish(token)
	if scan.token ~= token or not scan.running then
		return
	end
	scan.running = false
	scan.waiting = nil

	local key, name, realm = GBLF.PlayerGuild()
	if not key then
		GBLF.Print("Scan stopped. You are not in a guild.")
		if GBLF.UI then
			GBLF.UI.Refresh()
		end
		return
	end

	local guild = GBLF.TouchGuild(key, name, realm)
	local added = 0
	local gapStreams = {}
	local sawLines = false
	for stream, rows in pairs(scan.captured) do
		if rows and #rows > 0 then
			sawLines = true
		end
		local gained, gap = GBLF.Ledger.MergeStream(guild, stream, rows)
		added = added + gained
		if gap then
			gapStreams[#gapStreams + 1] = streamLabel(stream)
		end
	end
	guild.lastScan = GBLF.Now()
	GBLF.Settings().viewKey = key
	GBLF.Invalidate(key)
	GBLF.CacheFor(key)

	if not sawLines and added == 0 then
		GBLF.Print("Scan finished. The bank returned no log lines. You may not be allowed to view them.")
	elseif #gapStreams > 0 then
		GBLF.Print(string.format(
			"%s: added %d lines. The log rolled past on %s, so some older lines are missing. The ledger holds %d.",
			name,
			added,
			table.concat(gapStreams, ", "),
			#guild.txns
		))
	elseif added == 0 then
		GBLF.Print(string.format("%s: no new lines. The ledger holds %d.", name, #guild.txns))
	else
		GBLF.Print(string.format("%s: added %d lines. The ledger holds %d.", name, added, #guild.txns))
	end
	if GBLF.UI then
		GBLF.UI.Refresh()
	end
end

local function acceptAndAdvance()
	local token = scan.token
	local entry = scan.queue[scan.index]
	if not scan.running or scan.token ~= token or not entry or not scan.waiting then
		return
	end
	scan.captured[entry.stream] = scan.latest or {}
	scan.waiting = nil
	scan.query = scan.query + 1
	scan.index = scan.index + 1
	if scan.index > #scan.queue then
		finish(token)
		return
	end
	later(0.35, function()
		if scan.token ~= token or not scan.running then
			return
		end
		Scan.QueryCurrent()
	end)
end

function Scan.QueryCurrent()
	local entry = scan.queue[scan.index]
	if not scan.running or not entry then
		return
	end
	if not GBLF.IsBankOpen() then
		Scan.Abort("closed")
		return
	end
	local token = scan.token
	scan.query = scan.query + 1
	local qid = scan.query
	scan.waiting = entry
	scan.latest = {}
	scan.sawRows = false
	local queried = pcall(QueryGuildBankLog, entry.tab)
	if not queried then
		GBLF.Print("Could not read " .. streamLabel(entry.stream) .. ".")
		acceptAndAdvance()
		return
	end
	later(2.5, function()
		if scan.token ~= token or not scan.running or scan.query ~= qid or not scan.waiting then
			return
		end
		acceptAndAdvance()
	end)
end

function Scan.OnLogUpdate()
	if not scan.running or not scan.waiting then
		return
	end
	local now = GBLF.Now()
	local entry = scan.waiting
	local rows
	if entry.stream == "money" then
		rows = readMoney(now)
	else
		rows = readItems(entry.tab, now)
		local guildKey, guildName, realm = GBLF.PlayerGuild()
		if guildKey and GetGuildBankTabInfo then
			local ok, tabName = pcall(GetGuildBankTabInfo, entry.tab)
			if ok and type(tabName) == "string" and tabName ~= "" then
				local guild = GBLF.TouchGuild(guildKey, guildName, realm)
				guild.tabNames[entry.tab] = tabName
			end
		end
	end
	scan.latest = rows
	if #rows > 0 then
		scan.sawRows = true
		acceptAndAdvance()
		return
	end
	if scan.sawRows then
		return
	end
	local qid = scan.query
	later(0.8, function()
		if not scan.running or scan.query ~= qid or not scan.waiting then
			return
		end
		if scan.latest and #scan.latest > 0 then
			acceptAndAdvance()
			return
		end
		acceptAndAdvance()
	end)
end

local function begin(token, attempt)
	if scan.token ~= token or not scan.running then
		return
	end
	if not GBLF.IsBankOpen() then
		Scan.Abort("closed")
		return
	end
	local purchased = 0
	if GetNumGuildBankTabs then
		purchased = GetNumGuildBankTabs() or 0
	end
	if purchased == 0 and attempt < 5 then
		later(0.4, function()
			begin(token, attempt + 1)
		end)
		return
	end
	local maxTabs = MAX_GUILDBANK_TABS or purchased
	if maxTabs < purchased then
		maxTabs = purchased
	end
	if maxTabs < 1 then
		maxTabs = 6
	end
	local queue = {}
	for tab = 1, purchased do
		queue[#queue + 1] = { tab = tab, stream = "tab:" .. tab }
	end
	queue[#queue + 1] = { tab = maxTabs + 1, stream = "money" }
	scan.queue = queue
	scan.captured = {}
	scan.index = 1
	Scan.QueryCurrent()
end

function Scan.IsRunning()
	return scan.running
end

function Scan.Abort(reason)
	if not scan.running then
		return
	end
	scan.running = false
	scan.waiting = nil
	scan.token = scan.token + 1
	if reason == "closed" then
		GBLF.Print("Scan stopped because the bank closed before the log finished.")
	end
	if GBLF.UI then
		GBLF.UI.Refresh()
	end
end

local function stopTicker()
	if scan.ticker then
		scan.ticker:Cancel()
		scan.ticker = nil
	end
end

function Scan.StartTicker()
	stopTicker()
	local minutes = tonumber(GBLF.Settings().rescanMinutes) or 0
	if minutes <= 0 then
		return
	end
	if not C_Timer or not C_Timer.NewTicker then
		return
	end
	scan.ticker = C_Timer.NewTicker(minutes * 60, function()
		if GBLF.IsBankOpen() and not scan.running then
			Scan.Start("timer")
		end
	end)
end

function Scan.OnBankOpened()
	if not GBLF.dbReady then
		return
	end
	Scan.StartTicker()
	if GBLF.Settings().autoScan and not scan.running then
		later(0.6, function()
			if GBLF.IsBankOpen() and not scan.running then
				Scan.Start("open")
			end
		end)
	end
end

function Scan.OnBankClosed()
	stopTicker()
	if scan.running then
		Scan.Abort("closed")
	end
end

function Scan.Start(reason)
	if not GBLF.dbReady then
		GBLF.InitDB()
	end
	if scan.running then
		if reason == "slash" then
			GBLF.Print("A scan is already running.")
		end
		return
	end
	if not QueryGuildBankLog or not GetGuildBankTransaction then
		GBLF.Print("This client has no guild bank log to read.")
		return
	end
	if not GBLF.IsBankOpen() then
		if reason ~= "open" and reason ~= "timer" then
			GBLF.Print("Open the guild bank, then scan.")
		end
		return
	end
	local key = GBLF.PlayerGuild()
	if not key then
		GBLF.Print("You are not in a guild.")
		return
	end
	scan.running = true
	scan.token = scan.token + 1
	scan.waiting = nil
	local token = scan.token
	if reason ~= "timer" then
		GBLF.Print("Reading the guild bank log.")
	end
	if GBLF.UI then
		GBLF.UI.Refresh()
	end
	begin(token, 0)
end
