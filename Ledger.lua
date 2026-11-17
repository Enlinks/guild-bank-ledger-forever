-- Append-only guild bank ledger.
-- Each guild bank tab, and the money log, is its own ordered stream.
-- A new read is matched against lines already saved, in any order. A line
-- already stored is not added again. Lines the log no longer shows stay put.
-- The day is pinned the first time a line is seen and is not moved later.

GBLF = GBLF or {}
GBLF.Ledger = {}

local Ledger = GBLF.Ledger

function Ledger.NewGuild(name, realm)
	return {
		name = name,
		realm = realm,
		txns = {},
		gaps = {},
		nextId = 1,
		nextOrd = 1,
		tabNames = {},
		lastScan = nil,
		deduped = true,
	}
end

local function timeOk(a, b)
	local dist = GBLF.Time.DayDistance(a.day, b.day)
	local ap = a.precision
	local bp = b.precision
	if ap == "year" or bp == "year" then
		return dist <= 400
	end
	if ap == "month" or bp == "month" then
		return dist <= 35
	end
	if ap == "hour" and bp == "hour" then
		if dist > 1 then
			return false
		end
		if a.hour and b.hour and dist == 0 then
			return math.abs(a.hour - b.hour) <= 2
		end
		return true
	end
	return dist <= 1
end

local function identity(row)
	if row.itemID then
		return row.itemID
	end
	return row.itemName
end

local function canonicalAction(action)
	if action == "withdrawal" then
		return "withdraw"
	end
	return action
end

local function sameLine(a, b)
	if canonicalAction(a.action) ~= canonicalAction(b.action) or a.who ~= b.who then
		return false
	end
	if a.count ~= b.count or a.copper ~= b.copper then
		return false
	end
	if a.tab ~= b.tab or a.dest ~= b.dest then
		return false
	end
	local aSummary = a.summary and true or false
	local bSummary = b.summary and true or false
	if aSummary ~= bSummary then
		return false
	end
	return identity(a) == identity(b)
end

-- Same calendar day for hour and day lines. A month or year age is coarse,
-- so those lines may land a few days apart and still be the same event.
local function sameEvent(a, b)
	if not sameLine(a, b) then
		return false
	end
	local ap = a.precision
	local bp = b.precision
	if ap == "year" or bp == "year" or ap == "month" or bp == "month" then
		return timeOk(a, b)
	end
	if GBLF.Time.DayDistance(a.day, b.day) ~= 0 then
		return false
	end
	if a.hour and b.hour then
		return math.abs(a.hour - b.hour) <= 2
	end
	return true
end

local function findUnused(stored, used, row)
	for i = 1, #stored do
		if not used[i] and sameEvent(stored[i], row) then
			return i
		end
	end
	return nil
end

-- Oldest first. Larger ageRank is older. Equal ages keep the log's own order:
-- a lower index is the older line.
function Ledger.OrderScanRows(rows)
	table.sort(rows, function(a, b)
		if a.ageRank ~= b.ageRank then
			return a.ageRank > b.ageRank
		end
		return (a.apiIndex or 0) < (b.apiIndex or 0)
	end)
	return rows
end

function Ledger.StreamRows(guild, stream)
	local out = {}
	for i = 1, #guild.txns do
		local txn = guild.txns[i]
		if txn.stream == stream then
			out[#out + 1] = txn
		end
	end
	return out
end

local function storeFrom(guild, stream, row, ord)
	local txn = {
		id = guild.nextId,
		ord = ord,
		stream = stream,
		action = canonicalAction(row.action),
		who = row.who,
		day = row.day,
		hour = row.hour,
		precision = row.precision,
		itemID = row.itemID,
		itemName = row.itemName,
		count = row.count,
		copper = row.copper,
		tab = row.tab,
		dest = row.dest,
	}
	if row.summary then
		txn.summary = true
	end
	guild.nextId = guild.nextId + 1
	return txn
end

local function appendRow(guild, stream, row)
	local txn = storeFrom(guild, stream, row, guild.nextOrd)
	guild.nextOrd = guild.nextOrd + 1
	guild.txns[#guild.txns + 1] = txn
	return txn
end

local function prependRows(guild, stream, rows)
	if #rows == 0 then
		return
	end
	local index = #guild.txns + 1
	local firstOrd = guild.nextOrd
	for i = 1, #guild.txns do
		if guild.txns[i].stream == stream then
			index = i
			firstOrd = guild.txns[i].ord or guild.txns[i].id
			break
		end
	end
	local base = firstOrd - #rows
	for r = 1, #rows do
		local txn = storeFrom(guild, stream, rows[r], base + r - 1)
		table.insert(guild.txns, index + r - 1, txn)
	end
end

-- incoming is oldest-first. Returns how many lines were added, and whether
-- this read missed the previous tail (the log rolled past between scans).
function Ledger.MergeStream(guild, stream, incoming)
	if not incoming or #incoming == 0 then
		return 0, false
	end

	local stored = Ledger.StreamRows(guild, stream)
	if #stored == 0 then
		for i = 1, #incoming do
			appendRow(guild, stream, incoming[i])
		end
		return #incoming, false
	end

	local used = {}
	local older = {}
	local newer = {}
	local matched = false
	for i = 1, #incoming do
		local index = findUnused(stored, used, incoming[i])
		if index then
			used[index] = true
			matched = true
		elseif matched then
			newer[#newer + 1] = incoming[i]
		else
			older[#older + 1] = incoming[i]
		end
	end

	if not matched then
		guild.gaps[#guild.gaps + 1] = {
			stream = stream,
			beforeId = guild.nextId,
		}
		for i = 1, #incoming do
			appendRow(guild, stream, incoming[i])
		end
		return #incoming, true
	end

	prependRows(guild, stream, older)
	for i = 1, #newer do
		appendRow(guild, stream, newer[i])
	end
	return #older + #newer, false
end

-- Drop a later line that is the same event as an earlier one in that stream.
-- One read can still record two identical actions. This only repairs a copy
-- that a later scan stored again.
function Ledger.CollapseDuplicates(guild)
	local kept = {}
	local removed = 0
	for i = 1, #guild.txns do
		local txn = guild.txns[i]
		txn.action = canonicalAction(txn.action)
		local duplicate = false
		for j = 1, #kept do
			if kept[j].stream == txn.stream and sameEvent(kept[j], txn) then
				duplicate = true
				break
			end
		end
		if duplicate then
			removed = removed + 1
		else
			kept[#kept + 1] = txn
		end
	end
	guild.txns = kept
	return removed
end

local function charRow(cache, who)
	local row = cache.characters[who]
	if not row then
		row = {
			who = who,
			goldIn = 0,
			goldOut = 0,
			repair = 0,
			itemIn = 0,
			itemOut = 0,
		}
		cache.characters[who] = row
	end
	return row
end

local function itemRow(cache, txn)
	local key
	if txn.itemID then
		key = "id:" .. txn.itemID
	else
		key = "name:" .. (txn.itemName or "?")
	end
	local row = cache.items[key]
	if not row then
		row = {
			key = key,
			itemID = txn.itemID,
			itemName = txn.itemName or "Unknown item",
			itemIn = 0,
			itemOut = 0,
		}
		cache.items[key] = row
	elseif txn.itemName and txn.itemName ~= "" then
		row.itemName = txn.itemName
	end
	return row
end

local function dayRow(cache, packed)
	local row = cache.days[packed]
	if not row then
		row = {
			day = packed,
			goldIn = 0,
			goldOut = 0,
			repair = 0,
			tabCost = 0,
			itemIn = 0,
			itemOut = 0,
			lines = 0,
		}
		cache.days[packed] = row
	end
	return row
end

-- Out includes withdrawals and tab purchases. Repairs stay separate.
-- Moves and deposit summaries are listed but not added into the totals.
function Ledger.Rebuild(guild)
	local cache = {
		goldIn = 0,
		goldOut = 0,
		repairs = 0,
		tabCost = 0,
		itemIn = 0,
		itemOut = 0,
		characters = {},
		items = {},
		days = {},
		lines = #guild.txns,
		gaps = #guild.gaps,
	}
	for i = 1, #guild.txns do
		local txn = guild.txns[i]
		local day = dayRow(cache, txn.day)
		day.lines = day.lines + 1
		if txn.summary then
			-- A deposit summary repeats money that individual lines already count.
		elseif txn.copper and txn.copper ~= 0 then
			local who = charRow(cache, txn.who or "Unknown")
			if txn.action == "deposit" then
				cache.goldIn = cache.goldIn + txn.copper
				who.goldIn = who.goldIn + txn.copper
				day.goldIn = day.goldIn + txn.copper
			elseif txn.action == "repair" then
				cache.repairs = cache.repairs + txn.copper
				who.repair = who.repair + txn.copper
				day.repair = day.repair + txn.copper
			elseif txn.action == "withdrawForTab" or txn.action == "buyTab" then
				cache.goldOut = cache.goldOut + txn.copper
				cache.tabCost = cache.tabCost + txn.copper
				who.goldOut = who.goldOut + txn.copper
				day.goldOut = day.goldOut + txn.copper
				day.tabCost = day.tabCost + txn.copper
			elseif txn.action == "withdraw" then
				cache.goldOut = cache.goldOut + txn.copper
				who.goldOut = who.goldOut + txn.copper
				day.goldOut = day.goldOut + txn.copper
			end
		end
		if not txn.summary and txn.count and txn.count ~= 0 and txn.action ~= "move" then
			local who = charRow(cache, txn.who or "Unknown")
			local item = itemRow(cache, txn)
			if txn.action == "deposit" then
				cache.itemIn = cache.itemIn + txn.count
				who.itemIn = who.itemIn + txn.count
				item.itemIn = item.itemIn + txn.count
				day.itemIn = day.itemIn + txn.count
			elseif txn.action == "withdraw" then
				cache.itemOut = cache.itemOut + txn.count
				who.itemOut = who.itemOut + txn.count
				item.itemOut = item.itemOut + txn.count
				day.itemOut = day.itemOut + txn.count
			end
		end
	end
	cache.net = cache.goldIn - cache.goldOut - cache.repairs
	return cache
end

local function csvEscape(value)
	if value == nil then
		return ""
	end
	local text = tostring(value)
	if string.find(text, '[,"\r\n]') then
		return '"' .. string.gsub(text, '"', '""') .. '"'
	end
	return text
end

local function csvJoin(fields)
	return table.concat(fields, ",")
end

local function signedAmount(action, amount)
	if amount == nil then
		return ""
	end
	if action == "deposit" then
		return amount
	end
	if action == "withdraw" or action == "repair" or action == "withdrawForTab" or action == "buyTab" then
		return -amount
	end
	return 0
end

function Ledger.ExportTransactions(guild, cap)
	cap = cap or 5000
	local rows = {}
	for i = 1, #guild.txns do
		rows[i] = guild.txns[i]
	end
	table.sort(rows, function(a, b)
		local ad = a.day or 0
		local bd = b.day or 0
		if ad ~= bd then
			return ad < bd
		end
		local ah = a.hour or -1
		local bh = b.hour or -1
		if ah ~= bh then
			return ah < bh
		end
		local ao = a.ord or a.id or 0
		local bo = b.ord or b.id or 0
		if ao ~= bo then
			return ao < bo
		end
		return (a.id or 0) < (b.id or 0)
	end)
	local startAt = 1
	if #rows > cap then
		startAt = #rows - cap + 1
	end
	local lines = {
		csvJoin({
			"day", "hour", "precision", "character", "action",
			"item_id", "item_name", "count", "count_signed",
			"copper", "copper_signed", "tab", "destination_tab", "stream",
			"guild", "realm",
		}),
	}
	local shown = 0
	for i = startAt, #rows do
		shown = shown + 1
		local txn = rows[i]
		lines[#lines + 1] = csvJoin({
			csvEscape(GBLF.Time.IsoDay(txn.day)),
			csvEscape(txn.hour or ""),
			csvEscape(txn.precision or ""),
			csvEscape(txn.who or ""),
			csvEscape(txn.action or ""),
			csvEscape(txn.itemID or ""),
			csvEscape(txn.itemName or ""),
			csvEscape(txn.count or ""),
			csvEscape(txn.count and signedAmount(txn.action, txn.count) or ""),
			csvEscape(txn.copper or ""),
			csvEscape(txn.copper and signedAmount(txn.action, txn.copper) or ""),
			csvEscape(txn.tab or ""),
			csvEscape(txn.dest or ""),
			csvEscape(txn.stream or ""),
			csvEscape(guild.name or ""),
			csvEscape(guild.realm or ""),
		})
	end
	return table.concat(lines, "\n"), #guild.txns, shown
end

local IMPORT_COLUMNS = {
	"day", "hour", "precision", "character", "action",
	"item_id", "item_name", "count", "copper", "tab",
	"destination_tab", "stream",
}

local IMPORT_ACTIONS = {
	deposit = true,
	withdraw = true,
	withdrawal = true,
	move = true,
	repair = true,
	buyTab = true,
	withdrawForTab = true,
	depositSummary = true,
}

local IMPORT_PRECISIONS = {
	hour = true,
	day = true,
	month = true,
	year = true,
}

local function trim(text)
	return string.match(text or "", "^%s*(.-)%s*$") or ""
end

local function parseCsv(text)
	if string.byte(text, 1) == 239 and string.byte(text, 2) == 187 and string.byte(text, 3) == 191 then
		text = string.sub(text, 4)
	end
	text = string.gsub(text, "\r\n", "\n")
	text = string.gsub(text, "\r", "\n")

	local rows = {}
	local row = {}
	local field = {}
	local quoted = false
	local lineNo = 1
	local rowLine = 1
	local len = string.len(text)

	local function pushField()
		row[#row + 1] = table.concat(field)
		field = {}
	end

	local function pushRow()
		if not (#row == 1 and row[1] == "") then
			if #row > 0 then
				rows[#rows + 1] = { line = rowLine, fields = row }
			end
		end
		row = {}
	end

	local i = 1
	while i <= len do
		local char = string.sub(text, i, i)
		if quoted then
			if char == '"' then
				if string.sub(text, i + 1, i + 1) == '"' then
					field[#field + 1] = '"'
					i = i + 1
				else
					quoted = false
				end
			else
				if char == "\n" then
					lineNo = lineNo + 1
				end
				field[#field + 1] = char
			end
		elseif char == '"' and #field == 0 then
			quoted = true
		elseif char == "," then
			pushField()
		elseif char == "\n" then
			pushField()
			pushRow()
			lineNo = lineNo + 1
			rowLine = lineNo
		else
			field[#field + 1] = char
		end
		i = i + 1
	end
	if quoted then
		return nil, "A quote is still open at the end of the text."
	end
	if #field > 0 or #row > 0 then
		pushField()
		pushRow()
	end
	return rows
end

local function cell(fields, index)
	if not index then
		return ""
	end
	return fields[index] or ""
end

local function parseWhole(text)
	if text == "" then
		return nil
	end
	if not string.match(text, "^%d+$") then
		return nil, true
	end
	return tonumber(text)
end

local function guildLabel(name, realm)
	if realm and realm ~= "" then
		return (name or "") .. "-" .. realm
	end
	return name or ""
end

local function parseStream(text)
	if text == "money" then
		return "money"
	end
	local tab = string.match(text, "^tab:(%d+)$")
	tab = tab and tonumber(tab)
	if tab and tab > 0 then
		return "tab:" .. tab
	end
	return nil
end

-- text is a transaction export. Lines already saved are left in place.
-- An export that names another guild is refused, and nothing is written.
-- Returns added, seen, err. On failure added is nil and the guild is unchanged.
function Ledger.ImportTransactions(guild, text)
	if type(guild) ~= "table" or type(guild.txns) ~= "table" then
		return nil, nil, "There is no ledger to import into."
	end
	if type(text) ~= "string" or string.match(text, "^%s*$") then
		return nil, nil, "Paste a transaction export first."
	end

	local rows, err = parseCsv(text)
	if not rows then
		return nil, nil, err
	end
	if #rows == 0 then
		return nil, nil, "Paste a transaction export first."
	end

	local header = {}
	local headerFields = rows[1].fields
	for index = 1, #headerFields do
		local name = string.lower(trim(headerFields[index]))
		if name ~= "" and not header[name] then
			header[name] = index
		end
	end
	for index = 1, #IMPORT_COLUMNS do
		if not header[IMPORT_COLUMNS[index]] then
			return nil, nil, "Paste the Transactions export."
		end
	end
	if #rows == 1 then
		return nil, nil, "The export has no lines."
	end

	local records = {}
	local fileName, fileRealm
	for r = 2, #rows do
		local source = rows[r]
		local fields = source.fields
		local function fail(message)
			return string.format("Line %d %s", source.line, message)
		end

		local day = GBLF.Time.ParseIso(cell(fields, header.day))
		if not day then
			return nil, nil, fail("needs a day in the form YYYY-MM-DD.")
		end

		local hour, bad = parseWhole(cell(fields, header.hour))
		if bad or (hour and hour > 23) then
			return nil, nil, fail("has an hour that is not 0 to 23.")
		end

		local precision = cell(fields, header.precision)
		if precision == "" then
			precision = "day"
		elseif not IMPORT_PRECISIONS[precision] then
			return nil, nil, fail("has a precision this ledger does not keep.")
		end

		local action = cell(fields, header.action)
		if action == "" then
			return nil, nil, fail("needs an action.")
		end
		if not IMPORT_ACTIONS[action] then
			return nil, nil, fail("has an action this ledger does not keep.")
		end

		local itemID
		itemID, bad = parseWhole(cell(fields, header.item_id))
		if bad or (itemID and itemID < 1) then
			return nil, nil, fail("has an item id that is not a whole number.")
		end

		local count
		count, bad = parseWhole(cell(fields, header.count))
		if bad then
			return nil, nil, fail("has a count that is not a whole number.")
		end

		local copper
		copper, bad = parseWhole(cell(fields, header.copper))
		if bad then
			return nil, nil, fail("has a copper amount that is not a whole number.")
		end

		local tab
		tab, bad = parseWhole(cell(fields, header.tab))
		if bad or (tab and tab < 1) then
			return nil, nil, fail("has a tab that is not a whole number.")
		end

		local dest
		dest, bad = parseWhole(cell(fields, header.destination_tab))
		if bad or (dest and dest < 1) then
			return nil, nil, fail("has a destination tab that is not a whole number.")
		end

		local stream = parseStream(cell(fields, header.stream))
		if not stream then
			return nil, nil, fail("has a stream this ledger does not keep.")
		end

		local named = header.guild and cell(fields, header.guild) or ""
		local realm = header.realm and cell(fields, header.realm) or ""
		if named ~= "" or realm ~= "" then
			if not fileName then
				fileName = named
				fileRealm = realm
			elseif fileName ~= named or fileRealm ~= realm then
				return nil, nil, "The export names more than one guild."
			end
		end

		local who = cell(fields, header.character)
		if who == "" then
			who = nil
		end
		local itemName = cell(fields, header.item_name)
		if itemName == "" then
			itemName = nil
		end

		records[#records + 1] = {
			stream = stream,
			action = action,
			who = who,
			day = day,
			hour = hour,
			precision = precision,
			itemID = itemID,
			itemName = itemName,
			count = count,
			copper = copper,
			tab = tab,
			dest = dest,
			summary = action == "depositSummary",
		}
	end

	if fileName then
		if fileName ~= (guild.name or "") or fileRealm ~= (guild.realm or "") then
			return nil, nil, string.format(
				"That export is for %s. This ledger is %s.",
				guildLabel(fileName, fileRealm),
				guildLabel(guild.name, guild.realm)
			)
		end
	end

	local byStream = {}
	local order = {}
	for index = 1, #records do
		local record = records[index]
		local list = byStream[record.stream]
		if not list then
			list = {}
			byStream[record.stream] = list
			order[#order + 1] = record.stream
		end
		list[#list + 1] = record
	end

	local added = 0
	for index = 1, #order do
		local stream = order[index]
		local gained = Ledger.MergeStream(guild, stream, byStream[stream])
		added = added + gained
	end
	return added, #records
end

function Ledger.ExportCharacters(cache)
	local rows = {}
	for _, row in pairs(cache.characters) do
		rows[#rows + 1] = row
	end
	table.sort(rows, function(a, b)
		return a.who < b.who
	end)
	local lines = {
		csvJoin({ "character", "copper_in", "copper_out", "copper_repair", "copper_net", "items_in", "items_out" }),
	}
	for i = 1, #rows do
		local row = rows[i]
		local net = row.goldIn - row.goldOut - row.repair
		lines[#lines + 1] = csvJoin({
			csvEscape(row.who),
			tostring(row.goldIn),
			tostring(row.goldOut),
			tostring(row.repair),
			tostring(net),
			tostring(row.itemIn),
			tostring(row.itemOut),
		})
	end
	return table.concat(lines, "\n")
end

function Ledger.ExportItems(cache)
	local rows = {}
	for _, row in pairs(cache.items) do
		rows[#rows + 1] = row
	end
	table.sort(rows, function(a, b)
		return a.itemName < b.itemName
	end)
	local lines = {
		csvJoin({ "item_id", "item_name", "count_in", "count_out", "count_net" }),
	}
	for i = 1, #rows do
		local row = rows[i]
		lines[#lines + 1] = csvJoin({
			csvEscape(row.itemID or ""),
			csvEscape(row.itemName),
			tostring(row.itemIn),
			tostring(row.itemOut),
			tostring(row.itemIn - row.itemOut),
		})
	end
	return table.concat(lines, "\n")
end
