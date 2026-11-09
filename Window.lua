-- Ledger, Dates, Export, and Settings. One window, white on navy.

GBLF = GBLF or {}
GBLF.UI = GBLF.UI or {}

local UI = GBLF.UI
local Widgets = GBLF.Widgets
local Theme = GBLF.Theme

local ACTION_LABEL = {
	deposit = "Deposit",
	withdraw = "Withdraw",
	move = "Move",
	repair = "Repair",
	buyTab = "Buy tab",
	withdrawForTab = "Buy tab",
	depositSummary = "Summary",
}

local KIND_LABEL = {
	deposit = "Deposits",
	withdraw = "Withdrawals",
	repair = "Repairs",
	move = "Moves",
	gold = "Gold",
	items = "Items",
}

local NOTES = {
	ledger = "The day is fixed the first time a line is seen. An hour is shown only when the log sent one. Out includes tab purchases. Summary lines are not added into the totals.",
	dates = "Pick a day to see the lines pinned to it. A mark in front of a day means the log only gave a month or a year.",
	export = "Click the box and press Ctrl+C. Signed copper and counts are negative when something left the bank. Moves and summaries are zero in the signed columns.",
	settings = "Each guild keeps its own ledger on this account. Other accounts do not see it.",
}

local frame
local pages
local tabButtons
local current = "ledger"
local titleText
local scanButton
local footer
local minimapButton

local function lower(text)
	return string.lower(text or "")
end

local function scanStamp(stamp)
	if type(stamp) ~= "table" or not stamp.year then
		return "not scanned"
	end
	local packed = GBLF.Time.Pack(stamp.year, stamp.month, stamp.day)
	return string.format("%s %02d:%02d", GBLF.Time.FormatDayLong(packed), stamp.hour or 0, stamp.min or 0)
end

local function actionText(action)
	return ACTION_LABEL[action] or action or ""
end

local function detailText(guild, txn)
	if txn.itemName or txn.itemID then
		local name = txn.itemName or ("Item " .. tostring(txn.itemID))
		local where = GBLF.TabLabel(guild, txn.tab)
		if txn.action == "move" and txn.dest then
			return string.format("%s · %s → %s", name, where, GBLF.TabLabel(guild, txn.dest))
		end
		if where ~= "" then
			return name .. " · " .. where
		end
		return name
	end
	if txn.summary then
		return "Grouped deposits, not added to totals"
	end
	return "Gold"
end

local function amountText(txn)
	if txn.copper and txn.copper > 0 and not txn.itemID and not txn.itemName then
		if txn.action == "deposit" or txn.summary then
			return GBLF.FormatMoneyCompact(txn.copper)
		end
		return GBLF.FormatMoneyCompact(-txn.copper)
	end
	if txn.count and txn.count > 0 then
		return "x" .. tostring(txn.count)
	end
	return ""
end

local function sortRows(rows, key, desc)
	table.sort(rows, function(a, b)
		local av = a._sort[key]
		local bv = b._sort[key]
		if av == bv then
			if key == "day" and a._hour ~= b._hour then
				if desc then
					return (a._hour or -1) > (b._hour or -1)
				end
				return (a._hour or -1) < (b._hour or -1)
			end
			local ao = a._ord or 0
			local bo = b._ord or 0
			if ao ~= bo then
				if desc then
					return ao > bo
				end
				return ao < bo
			end
			return (a._tie or "") < (b._tie or "")
		end
		if type(av) ~= type(bv) then
			return tostring(av or "") < tostring(bv or "")
		end
		if desc then
			return av > bv
		end
		return av < bv
	end)
end

local function txnRow(guild, txn)
	local name = txn.itemName or ""
	return {
		day = GBLF.Time.FormatDay(txn.day, txn.hour, txn.precision),
		who = txn.who or "",
		action = actionText(txn.action),
		detail = detailText(guild, txn),
		amount = amountText(txn),
		itemID = txn.itemID,
		packed = txn.day,
		_hour = txn.hour or -1,
		_ord = txn.ord or txn.id or 0,
		_tie = txn.who or "",
		_sort = {
			day = txn.day or 0,
			who = lower(txn.who),
			action = lower(actionText(txn.action)),
			detail = lower(name ~= "" and name or detailText(guild, txn)),
			amount = txn.copper or txn.count or 0,
		},
	}
end

local function matches(txn, state)
	if state.who and txn.who ~= state.who then
		return false
	end
	if state.itemKey then
		local key
		if txn.itemID then
			key = "id:" .. txn.itemID
		else
			key = "name:" .. (txn.itemName or "?")
		end
		if key ~= state.itemKey then
			return false
		end
	end
	if state.kind == "deposit" or state.kind == "withdraw" or state.kind == "repair" or state.kind == "move" then
		if txn.action ~= state.kind then
			return false
		end
	elseif state.kind == "gold" then
		if not txn.copper then
			return false
		end
	elseif state.kind == "items" then
		if not txn.itemID and not txn.itemName then
			return false
		end
	end
	if state.tab == "money" and txn.stream ~= "money" then
		return false
	elseif type(state.tab) == "number" and txn.tab ~= state.tab and txn.dest ~= state.tab then
		return false
	end
	local search = lower(state.search)
	search = string.gsub(search, "^%s+", "")
	search = string.gsub(search, "%s+$", "")
	if search ~= "" then
		local hay = lower((txn.who or "") .. " " .. (txn.itemName or "") .. " " .. actionText(txn.action))
		if not string.find(hay, search, 1, true) then
			return false
		end
	end
	return true
end

local function filteredTxns(guild, state)
	local rows = {}
	if not guild then
		return rows
	end
	for index = 1, #guild.txns do
		local txn = guild.txns[index]
		if matches(txn, state) then
			rows[#rows + 1] = txnRow(guild, txn)
		end
	end
	sortRows(rows, state.txnSort or "day", state.txnDesc ~= false)
	return rows
end

local function refreshChrome()
	local key, guild = GBLF.ViewGuild()
	local name = "No guild"
	if guild and guild.name then
		name = guild.name
	elseif key then
		name = key
	end
	titleText:SetText(name)
	if GBLF.Scan.IsRunning() then
		scanButton:SetText("Scanning")
		scanButton:SetEnabled(false)
	else
		scanButton:SetText("Scan")
		scanButton:SetEnabled(true)
	end
	if footer then
		footer:SetText(NOTES[current] or "")
	end
end

local function showPage(id)
	current = id
	Widgets.CloseMenu()
	for key, page in pairs(pages) do
		if key == id then
			page.frame:Show()
		else
			page.frame:Hide()
		end
	end
	for key, button in pairs(tabButtons) do
		Widgets.SetActive(button, key == id)
	end
	refreshChrome()
	if pages[id] then
		pages[id]:Refresh()
	end
end

local function summaryCell(parent, caption)
	local block = CreateFrame("Frame", nil, parent)
	block:SetHeight(52)
	local label = Widgets.Label(block, "small", Theme.muted)
	label:SetPoint("TOPLEFT", 8, -6)
	label:SetText(caption)
	local value = Widgets.Label(block, "body", Theme.text)
	value:SetPoint("TOPLEFT", 8, -24)
	value:SetPoint("RIGHT", -6, 0)
	value:SetText("0")
	block.value = value
	return block
end

local function buildLedger(parent)
	local state = {
		mode = "characters",
		who = nil,
		itemKey = nil,
		itemName = nil,
		kind = nil,
		tab = nil,
		search = "",
		charSort = "goldOut",
		charDesc = true,
		itemSort = "itemOut",
		itemDesc = true,
		txnSort = "day",
		txnDesc = true,
	}
	local page = { frame = parent, state = state }

	local summary = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	summary:SetPoint("TOPLEFT", 0, 0)
	summary:SetPoint("TOPRIGHT", 0, 0)
	summary:SetHeight(64)
	Widgets.Paint(summary, "inset")

	local captions = { "In", "Out", "Repairs", "Tabs", "Net" }
	local cells = {}
	for index, caption in ipairs(captions) do
		local cell = summaryCell(summary, caption)
		cell:SetPoint("TOPLEFT", (index - 1) * 118, -4)
		cell:SetWidth(114)
		cells[index] = cell
	end
	local status = Widgets.Label(summary, "small", Theme.muted)
	status:SetPoint("BOTTOMLEFT", 8, 6)
	status:SetPoint("BOTTOMRIGHT", -8, 6)
	status:SetText("")

	local charactersButton = Widgets.Button(parent, "Characters", 96, 22)
	charactersButton:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -8)
	local itemsButton = Widgets.Button(parent, "Items", 72, 22)
	itemsButton:SetPoint("LEFT", charactersButton, "RIGHT", 6, 0)

	local characterList = Widgets.List(parent, 460, 700, {
		{ key = "who", text = "Character", width = 120 },
		{ key = "goldIn", text = "In", width = 84, align = "RIGHT", money = true },
		{ key = "goldOut", text = "Out", width = 84, align = "RIGHT", money = true },
		{ key = "repair", text = "Repair", width = 76, align = "RIGHT", money = true },
		{ key = "net", text = "Net", flex = true, align = "RIGHT", money = true },
	})
	characterList.frame:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -36)
	characterList.frame:SetPoint("BOTTOMLEFT", 0, 0)
	characterList.frame:SetWidth(460)

	local itemList = Widgets.List(parent, 400, 700, {
		{ key = "who", text = "Item", width = 190 },
		{ key = "itemIn", text = "In", width = 60, align = "RIGHT" },
		{ key = "itemOut", text = "Out", width = 60, align = "RIGHT" },
		{ key = "net", text = "Net", flex = true, align = "RIGHT" },
	})
	itemList.frame:SetPoint("TOPLEFT", characterList.frame, "TOPLEFT")
	itemList.frame:SetPoint("BOTTOMRIGHT", characterList.frame, "BOTTOMRIGHT")

	local kindButton = Widgets.Button(parent, "All actions", 110, 22)
	kindButton:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 468, -8)
	local tabButton = Widgets.Button(parent, "All tabs", 110, 22)
	tabButton:SetPoint("LEFT", kindButton, "RIGHT", 6, 0)
	local clearButton = Widgets.Button(parent, "Clear", 52, 22)
	clearButton:SetPoint("LEFT", tabButton, "RIGHT", 6, 0)
	local search = Widgets.Edit(parent, 180, 22)
	search:SetPoint("LEFT", clearButton, "RIGHT", 6, 0)
	search:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	search:SetHeight(22)

	local txnList = Widgets.List(parent, 500, 700, {
		{ key = "day", text = "Day", width = 108 },
		{ key = "who", text = "Character", width = 90 },
		{ key = "action", text = "Action", width = 72 },
		{ key = "detail", text = "Detail", flex = true },
		{ key = "amount", text = "Amount", width = 74, align = "RIGHT" },
	})
	txnList.frame:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 468, -36)
	txnList.frame:SetPoint("BOTTOMRIGHT", 0, 0)

	local empty = Widgets.Label(txnList.frame, "body", Theme.muted)
	empty:SetPoint("CENTER", 0, -8)
	empty:SetText("")

	local quiet = false
	local function setSearch(text)
		quiet = true
		search:SetText(text or "")
		quiet = false
		state.search = text or ""
	end

	local function tabChoices(guild)
		local choices = {
			{ text = "All tabs", value = nil },
			{ text = "Money", value = "money" },
		}
		local seen = {}
		if guild then
			for index = 1, #guild.txns do
				local tab = guild.txns[index].tab
				if type(tab) == "number" then
					seen[tab] = true
				end
			end
		end
		local indexes = {}
		for tab in pairs(seen) do
			indexes[#indexes + 1] = tab
		end
		table.sort(indexes)
		for index = 1, #indexes do
			local tab = indexes[index]
			choices[#choices + 1] = { text = GBLF.TabLabel(guild, tab), value = tab }
		end
		return choices
	end

	local function applyMode()
		if state.mode == "items" then
			characterList.frame:Hide()
			itemList.frame:Show()
			Widgets.SetActive(itemsButton, true)
			Widgets.SetActive(charactersButton, false)
		else
			itemList.frame:Hide()
			characterList.frame:Show()
			Widgets.SetActive(charactersButton, true)
			Widgets.SetActive(itemsButton, false)
		end
	end

	local function paintLists(resetScroll)
		local key, guild = GBLF.ViewGuild()
		local cache = key and GBLF.CacheFor(key) or nil
		local characters = {}
		local items = {}
		if cache then
			for _, row in pairs(cache.characters) do
				local net = row.goldIn - row.goldOut - row.repair
				characters[#characters + 1] = {
					who = row.who,
					goldIn = row.goldIn,
					goldOut = row.goldOut,
					repair = row.repair,
					net = net,
					_sort = {
						who = lower(row.who),
						goldIn = row.goldIn,
						goldOut = row.goldOut,
						repair = row.repair,
						net = net,
					},
					_ord = net,
					_tie = lower(row.who),
				}
			end
			for _, row in pairs(cache.items) do
				local net = row.itemIn - row.itemOut
				items[#items + 1] = {
					who = row.itemName,
					itemIn = row.itemIn,
					itemOut = row.itemOut,
					net = net,
					itemID = row.itemID,
					key = row.key,
					_sort = {
						who = lower(row.itemName),
						itemIn = row.itemIn,
						itemOut = row.itemOut,
						net = net,
					},
					_ord = row.itemOut,
					_tie = lower(row.itemName),
				}
			end
		end
		sortRows(characters, state.charSort, state.charDesc)
		sortRows(items, state.itemSort, state.itemDesc)
		characterList:SetMark(state.charSort, state.charDesc)
		itemList:SetMark(state.itemSort, state.itemDesc)
		characterList:SetItems(characters)
		itemList:SetItems(items)

		local txns = filteredTxns(guild, state)
		txnList:SetMark(state.txnSort, state.txnDesc)
		if resetScroll then
			txnList:ScrollToTop()
		end
		txnList:SetItems(txns)
		if not guild then
			empty:SetText(key and "Open this guild's bank and press Scan." or "Join a guild, open its bank, and press Scan.")
		elseif #txns == 0 and (state.who or state.itemKey or state.kind or state.tab or state.search ~= "") then
			empty:SetText("Nothing matches this filter.")
		elseif #txns == 0 then
			empty:SetText("No lines yet. Open the guild bank and press Scan.")
		else
			empty:SetText("")
		end
		applyMode()
	end

	characterList.isSelected = function(item)
		return state.who == item.who and not state.itemKey
	end
	itemList.isSelected = function(item)
		return state.itemKey == item.key
	end
	characterList.onClick = function(item)
		if state.who == item.who and not state.itemKey then
			state.who = nil
		else
			state.who = item.who
			state.itemKey = nil
			state.itemName = nil
		end
		paintLists(true)
	end
	itemList.onClick = function(item)
		if state.itemKey == item.key then
			state.itemKey = nil
			state.itemName = nil
		else
			state.itemKey = item.key
			state.itemName = item.who
			state.who = nil
		end
		paintLists(true)
	end
	characterList.onHeader = function(key)
		if state.charSort == key then
			state.charDesc = not state.charDesc
		else
			state.charSort = key
			state.charDesc = key ~= "who"
		end
		paintLists(false)
	end
	itemList.onHeader = function(key)
		if state.itemSort == key then
			state.itemDesc = not state.itemDesc
		else
			state.itemSort = key
			state.itemDesc = key ~= "who"
		end
		paintLists(false)
	end
	txnList.onHeader = function(key)
		if state.txnSort == key then
			state.txnDesc = not state.txnDesc
		else
			state.txnSort = key
			state.txnDesc = key ~= "who" and key ~= "detail"
		end
		paintLists(false)
	end

	charactersButton.onClick = function()
		state.mode = "characters"
		applyMode()
	end
	itemsButton.onClick = function()
		state.mode = "items"
		applyMode()
	end
	kindButton.onClick = function()
		Widgets.OpenMenu(kindButton, {
			{ text = "All actions", value = nil },
			{ text = "Deposits", value = "deposit" },
			{ text = "Withdrawals", value = "withdraw" },
			{ text = "Repairs", value = "repair" },
			{ text = "Moves", value = "move" },
			{ text = "Gold", value = "gold" },
			{ text = "Items", value = "items" },
		}, function(value, text)
			state.kind = value
			kindButton:SetText(text)
			paintLists(true)
		end)
	end
	tabButton.onClick = function()
		local _, guild = GBLF.ViewGuild()
		Widgets.OpenMenu(tabButton, tabChoices(guild), function(value, text)
			state.tab = value
			tabButton:SetText(text)
			paintLists(true)
		end)
	end
	clearButton.onClick = function()
		state.who = nil
		state.itemKey = nil
		state.itemName = nil
		state.kind = nil
		state.tab = nil
		kindButton:SetText("All actions")
		tabButton:SetText("All tabs")
		setSearch("")
		paintLists(true)
	end
	search:SetScript("OnTextChanged", function(self)
		if quiet then
			return
		end
		state.search = self:GetText() or ""
		paintLists(true)
	end)

	function page:Refresh()
		local key, guild = GBLF.ViewGuild()
		local cache = key and GBLF.CacheFor(key) or nil
		local goldIn, goldOut, repairs, tabs, net = 0, 0, 0, 0, 0
		local itemIn, itemOut, lines, gaps = 0, 0, 0, 0
		if cache then
			goldIn = cache.goldIn
			goldOut = cache.goldOut
			repairs = cache.repairs
			tabs = cache.tabCost
			net = cache.net
			itemIn = cache.itemIn
			itemOut = cache.itemOut
			lines = cache.lines
			gaps = cache.gaps
		end
		local figures = { goldIn, goldOut, repairs, tabs, net }
		for index, cell in ipairs(cells) do
			cell.value:SetText(GBLF.FormatMoney(figures[index]))
		end
		local gapText = gaps > 0 and (gaps .. (gaps == 1 and " gap" or " gaps")) or "no gaps"
		local filterBits = {}
		if state.who then
			filterBits[#filterBits + 1] = state.who
		end
		if state.itemName then
			filterBits[#filterBits + 1] = state.itemName
		end
		if state.kind then
			filterBits[#filterBits + 1] = KIND_LABEL[state.kind] or state.kind
		end
		local filterText = ""
		if #filterBits > 0 then
			filterText = "  ·  " .. table.concat(filterBits, " · ")
		end
		status:SetText(string.format(
			"%d lines · items %d in / %d out · %s · %s%s",
			lines,
			itemIn,
			itemOut,
			guild and scanStamp(guild.lastScan) or "not scanned",
			gapText,
			filterText
		))
		if not search:HasFocus() and search:GetText() ~= (state.search or "") then
			setSearch(state.search or "")
		end
		paintLists(false)
	end

	page:Refresh()
	return page
end

local function buildDates(parent)
	local selected = nil
	local page = { frame = parent }

	local dayList = Widgets.List(parent, 300, 700, {
		{ key = "day", text = "Day", flex = true },
		{ key = "net", text = "Net", width = 80, align = "RIGHT" },
		{ key = "items", text = "Items", width = 64, align = "RIGHT" },
	})
	dayList.frame:SetPoint("TOPLEFT", 0, 0)
	dayList.frame:SetPoint("BOTTOMLEFT", 0, 0)
	dayList.frame:SetWidth(300)

	local heading = Widgets.Label(parent, "body", Theme.text)
	heading:SetPoint("TOPLEFT", 308, -2)
	heading:SetPoint("RIGHT", 0, 0)
	heading:SetText("No days yet")

	local txnList = Widgets.List(parent, 500, 700, {
		{ key = "who", text = "Character", width = 110 },
		{ key = "action", text = "Action", width = 72 },
		{ key = "detail", text = "Detail", flex = true },
		{ key = "amount", text = "Amount", width = 74, align = "RIGHT" },
	})
	txnList.frame:SetPoint("TOPLEFT", 308, -24)
	txnList.frame:SetPoint("BOTTOMRIGHT", 0, 0)

	local function newest(cache)
		local best = nil
		if not cache then
			return nil
		end
		for packed in pairs(cache.days) do
			if not best or packed > best then
				best = packed
			end
		end
		return best
	end

	dayList.onClick = function(item)
		selected = item.packed
		page:Refresh()
	end
	dayList.isSelected = function(item)
		return item.packed == selected
	end

	function page:Refresh()
		local key, guild = GBLF.ViewGuild()
		local cache = key and GBLF.CacheFor(key) or nil
		local rows = {}
		if cache then
			if not selected or not cache.days[selected] then
				selected = newest(cache)
			end
			for packed, row in pairs(cache.days) do
				local net = row.goldIn - row.goldOut - row.repair
				rows[#rows + 1] = {
					day = GBLF.Time.FormatDayLong(packed),
					net = GBLF.FormatMoneyCompact(net),
					items = tostring(row.itemIn + row.itemOut),
					packed = packed,
					_sort = { day = packed, net = net, items = row.itemIn + row.itemOut },
					_ord = packed,
					_tie = "",
				}
			end
		else
			selected = nil
		end
		sortRows(rows, "day", true)
		dayList:SetMark("day", true)
		dayList:SetItems(rows)
		local lines = {}
		if guild and selected then
			for index = 1, #guild.txns do
				local txn = guild.txns[index]
				if txn.day == selected then
					lines[#lines + 1] = txnRow(guild, txn)
				end
			end
			sortRows(lines, "day", true)
			heading:SetText(string.format("%s · %d lines", GBLF.Time.FormatDayLong(selected), #lines))
		elseif key then
			heading:SetText("No days saved yet")
		else
			heading:SetText("No guild")
		end
		txnList:SetItems(lines)
	end

	return page
end

local function buildExport(parent)
	local page = { frame = parent }
	local transactions = Widgets.Button(parent, "Transactions", 120, 22)
	transactions:SetPoint("TOPLEFT", 0, 0)
	local characters = Widgets.Button(parent, "Characters", 110, 22)
	characters:SetPoint("LEFT", transactions, "RIGHT", 6, 0)
	local items = Widgets.Button(parent, "Items", 80, 22)
	items:SetPoint("LEFT", characters, "RIGHT", 6, 0)
	local note = Widgets.Label(parent, "small", Theme.muted)
	note:SetPoint("LEFT", items, "RIGHT", 10, 0)
	note:SetPoint("RIGHT", 0, 0)
	note:SetText("Choose what to copy.")

	local scroll = CreateFrame("ScrollFrame", "GBLFExportScroll", parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -32)
	scroll:SetPoint("BOTTOMRIGHT", -24, 0)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(GameFontHighlightSmall)
	edit:SetTextColor(Theme.text[1], Theme.text[2], Theme.text[3])
	edit:SetWidth(640)
	edit:SetHeight(400)
	scroll:SetScrollChild(edit)
	edit:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	edit:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	scroll:SetScript("OnSizeChanged", function(self)
		edit:SetWidth(math.max(120, self:GetWidth() - 12))
	end)

	local function fill(kind)
		local key, guild = GBLF.ViewGuild()
		if not guild then
			edit:SetText("No ledger for this guild yet.")
			edit:SetHeight(80)
			note:SetText("Scan the bank first.")
			return
		end
		local cache = GBLF.CacheFor(key)
		local text
		if kind == "characters" then
			text = GBLF.Ledger.ExportCharacters(cache)
			note:SetText("Character totals. Ctrl+C copies the box.")
		elseif kind == "items" then
			text = GBLF.Ledger.ExportItems(cache)
			note:SetText("Item totals. Moves are not included. Ctrl+C copies the box.")
		else
			local csv, total, shown = GBLF.Ledger.ExportTransactions(guild)
			text = csv
			if shown < total then
				note:SetText(string.format("Newest %d of %d lines, oldest of those first. Ctrl+C copies the box.", shown, total))
			else
				note:SetText(string.format("%d lines, oldest first. Ctrl+C copies the box.", total))
			end
		end
		local _, breaks = string.gsub(text, "\n", "")
		edit:SetText(text)
		edit:SetHeight(math.max(200, (breaks + 2) * 14))
		edit:SetFocus()
		edit:HighlightText()
	end

	transactions.onClick = function()
		fill("transactions")
	end
	characters.onClick = function()
		fill("characters")
	end
	items.onClick = function()
		fill("items")
	end

	function page:Refresh()
	end

	return page
end

local function buildSettings(parent)
	local page = { frame = parent }
	local settings = nil

	local autoScan = Widgets.Check(parent, "Scan when the guild bank opens")
	autoScan:SetPoint("TOPLEFT", 0, -4)
	autoScan.label:SetPoint("LEFT", autoScan, "RIGHT", 8, 0)
	autoScan.onClick = function(on)
		GBLF.Settings().autoScan = on and true or false
	end

	local minimap = Widgets.Check(parent, "Show the minimap button")
	minimap:SetPoint("TOPLEFT", autoScan, "BOTTOMLEFT", 0, -10)
	minimap.label:SetPoint("LEFT", minimap, "RIGHT", 8, 0)
	minimap.onClick = function(on)
		GBLF.Settings().showMinimap = on and true or false
		UI.UpdateMinimap()
	end

	local rescanLabel = Widgets.Label(parent, "small", Theme.text)
	rescanLabel:SetPoint("TOPLEFT", minimap, "BOTTOMLEFT", 0, -14)
	rescanLabel:SetText("While the bank stays open, scan again every")
	local minutes = Widgets.Edit(parent, 42, 22)
	minutes:SetPoint("LEFT", rescanLabel, "RIGHT", 8, 0)
	minutes:SetJustifyH("CENTER")
	minutes:SetNumeric(true)
	minutes:SetMaxLetters(2)
	local minutesTail = Widgets.Label(parent, "small", Theme.muted)
	minutesTail:SetPoint("LEFT", minutes, "RIGHT", 8, 0)
	minutesTail:SetText("minutes. 0 scans only when the bank opens.")
	minutes.onCommit = function(text)
		local value = tonumber(text) or 0
		if value < 0 then
			value = 0
		end
		if value > 60 then
			value = 60
		end
		value = math.floor(value)
		GBLF.Settings().rescanMinutes = value
		if not minutes:HasFocus() then
			minutes:SetText(tostring(value))
		end
		if GBLF.IsBankOpen() then
			GBLF.Scan.StartTicker()
		end
	end

	local savedLabel = Widgets.Label(parent, "body", Theme.text)
	savedLabel:SetPoint("TOPLEFT", rescanLabel, "BOTTOMLEFT", 0, -18)
	savedLabel:SetText("Saved guilds")

	local watch = Widgets.Button(parent, "Watch my current guild", 180, 22)
	watch:SetPoint("TOPRIGHT", 0, -78)
	local deleteButton = Widgets.Button(parent, "Delete this ledger", 140, 22)
	deleteButton:SetPoint("RIGHT", watch, "LEFT", -6, 0)

	local guildList = Widgets.List(parent, 800, 700, {
		{ key = "name", text = "Guild", flex = true },
		{ key = "lines", text = "Lines", width = 70, align = "RIGHT" },
		{ key = "seen", text = "Last scan", width = 180, align = "RIGHT" },
	})
	guildList.frame:SetPoint("TOPLEFT", savedLabel, "BOTTOMLEFT", 0, -8)
	guildList.frame:SetPoint("BOTTOMRIGHT", 0, 28)

	local hint = Widgets.Label(parent, "small", Theme.muted)
	hint:SetPoint("BOTTOMLEFT", 0, 4)
	hint:SetPoint("BOTTOMRIGHT", 0, 4)
	hint:SetText("/ledger opens this window. /scan reads the bank. /gblf status prints how many lines are saved.")

	guildList.onClick = function(item)
		GBLF.Settings().viewKey = item.key
		UI.Refresh()
	end
	guildList.isSelected = function(item)
		return item.key == GBLF.ViewKey()
	end

	watch.onClick = function()
		GBLF.Settings().viewKey = nil
		local key = GBLF.PlayerGuild()
		if key then
			GBLF.Print("Watching " .. key .. ".")
		else
			GBLF.Print("You are not in a guild. Showing whatever you scan next.")
		end
		UI.Refresh()
	end
	deleteButton.onClick = function()
		local key, guild = GBLF.ViewGuild()
		if not guild then
			GBLF.Print("This guild has no saved ledger.")
			return
		end
		local name = guild.name or key
		StaticPopup_Show("GBLF_DELETE_GUILD", name, nil, key)
	end

	function page:Refresh()
		settings = GBLF.Settings()
		autoScan:SetChecked(settings.autoScan)
		minimap:SetChecked(settings.showMinimap)
		if not minutes:HasFocus() then
			minutes:SetText(tostring(settings.rescanMinutes or 0))
		end
		local rows = {}
		for _, guild in ipairs(GBLF.SavedGuilds()) do
			rows[#rows + 1] = {
				name = guild.realm ~= "" and (guild.name .. " · " .. guild.realm) or guild.name,
				lines = tostring(guild.lines),
				seen = scanStamp(guild.lastScan),
				key = guild.key,
				_sort = { name = lower(guild.name), lines = guild.lines, seen = guild.lastScan and GBLF.Time.Pack(guild.lastScan.year, guild.lastScan.month, guild.lastScan.day) or 0 },
				_ord = guild.lines,
				_tie = guild.key,
			}
		end
		sortRows(rows, "name", false)
		guildList:SetItems(rows)
	end

	return page
end

local function placeMinimap()
	if not minimapButton or not Minimap then
		return
	end
	local angle = GBLF.Settings().minimapAngle or 220
	local radius = (Minimap:GetWidth() / 2) + 8
	local rad = math.rad(angle)
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

function UI.UpdateMinimap()
	if not minimapButton then
		return
	end
	if GBLF.Settings().showMinimap then
		minimapButton:Show()
		placeMinimap()
	else
		minimapButton:Hide()
	end
end

local function createMinimap()
	if minimapButton or not Minimap then
		return
	end
	local button = CreateFrame("Button", "GBLFMinimapButton", Minimap, "BackdropTemplate")
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 5)
	Widgets.Paint(button, "button")
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 4, -4)
	icon:SetPoint("BOTTOMRIGHT", -4, 4)
	icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
	button:RegisterForDrag("LeftButton")
	button:RegisterForClicks("LeftButtonUp")
	button:SetScript("OnDragStart", function(self)
		self.moved = true
		self:SetScript("OnUpdate", function()
			if not Minimap then
				return
			end
			local mx, my = Minimap:GetCenter()
			local scale = Minimap:GetEffectiveScale()
			local cx, cy = GetCursorPosition()
			cx = cx / scale
			cy = cy / scale
			GBLF.Settings().minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
			placeMinimap()
		end)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnClick", function(self)
		if self.moved then
			self.moved = false
			return
		end
		UI.Toggle()
	end)
	button:SetScript("OnEnter", function(self)
		if not GameTooltip then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Guild Ledger", 1, 1, 1)
		GameTooltip:AddLine("Open the ledger. Drag to move.", Theme.muted[1], Theme.muted[2], Theme.muted[3])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	minimapButton = button
	UI.UpdateMinimap()
end

local function createWindow()
	frame = CreateFrame("Frame", "GBLFFrame", UIParent, "BackdropTemplate")
	frame:SetSize(960, 620)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	Widgets.Paint(frame, "window")
	local point = GBLF.Settings().point
	if point and point[1] and point[2] and type(point[3]) == "number" and type(point[4]) == "number" then
		frame:SetPoint(point[1], UIParent, point[2], point[3], point[4])
	else
		frame:SetPoint("CENTER")
	end
	tinsert(UISpecialFrames, "GBLFFrame")

	local drag = CreateFrame("Button", nil, frame)
	drag:SetPoint("TOPLEFT", 0, 0)
	drag:SetPoint("TOPRIGHT", -230, 0)
	drag:SetHeight(32)
	drag:RegisterForDrag("LeftButton")
	drag:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	drag:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		local anchor, _, relative, x, y = frame:GetPoint(1)
		GBLF.Settings().point = { anchor, relative, x, y }
	end)

	titleText = Widgets.Label(frame, "title", Theme.text)
	titleText:SetPoint("TOPLEFT", 14, -8)
	titleText:SetText("Guild Ledger")

	local closeButton = Widgets.Button(frame, "Close", 64, 22)
	closeButton:SetPoint("TOPRIGHT", -10, -8)
	closeButton.onClick = function()
		frame:Hide()
	end
	scanButton = Widgets.Button(frame, "Scan", 72, 22)
	scanButton:SetPoint("RIGHT", closeButton, "LEFT", -6, 0)
	scanButton.onClick = function()
		GBLF.Scan.Start("button")
	end

	tabButtons = {}
	local tabIds = { "ledger", "dates", "export", "settings" }
	local tabNames = { ledger = "Ledger", dates = "Dates", export = "Export", settings = "Settings" }
	for index, id in ipairs(tabIds) do
		local tabId = id
		local button = Widgets.Button(frame, tabNames[tabId], 88, 22)
		button:SetPoint("TOPLEFT", 12 + (index - 1) * 94, -36)
		button.onClick = function()
			showPage(tabId)
		end
		tabButtons[tabId] = button
	end

	footer = Widgets.Label(frame, "small", Theme.muted)
	footer:SetPoint("BOTTOMLEFT", 12, 8)
	footer:SetPoint("BOTTOMRIGHT", -12, 8)
	footer:SetText(NOTES.ledger)

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 12, -64)
	content:SetPoint("BOTTOMRIGHT", -12, 26)

	pages = {}
	for _, id in ipairs(tabIds) do
		local page = CreateFrame("Frame", nil, content)
		page:SetAllPoints()
		page:Hide()
		if id == "ledger" then
			pages[id] = buildLedger(page)
		elseif id == "dates" then
			pages[id] = buildDates(page)
		elseif id == "export" then
			pages[id] = buildExport(page)
		else
			pages[id] = buildSettings(page)
		end
	end

	frame:SetScript("OnShow", function()
		showPage(current)
	end)
	frame:SetScript("OnHide", function()
		Widgets.CloseMenu()
	end)
	frame:Hide()
end

function UI.Init()
	if not GBLF.dbReady then
		return
	end
	if not UI.ready then
		StaticPopupDialogs["GBLF_DELETE_GUILD"] = {
			text = "Delete the saved ledger for %s? This cannot be undone.",
			button1 = "Delete",
			button2 = "Cancel",
			OnAccept = function(self, data)
				local key = data
				if key == nil and self then
					key = self.data
				end
				if key then
					GBLF.DeleteGuild(key)
				end
			end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
		}
		createWindow()
		UI.ready = true
	end
	createMinimap()
end

function UI.Toggle()
	if not frame then
		UI.Init()
	end
	if not frame then
		return
	end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
	end
end

function UI.Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	showPage(current)
end
