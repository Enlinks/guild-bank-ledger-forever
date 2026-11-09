-- Append-only guild bank ledger.
-- Each guild bank tab, and the money log, is its own ordered stream.
-- A new read is the last N lines still in that log. Overlap with the tail we
-- already stored is skipped. Lines past that overlap are appended.
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

local function sameLine(a, b)
	if a.action ~= b.action or a.who ~= b.who then
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

local function aligns(stored, start, incoming, j, n)
	for k = 0, n - 1 do
		local old = stored[start + k]
		local new = incoming[j + k]
		if not sameLine(old, new) or not timeOk(old, new) then
			return false
		end
	end
	return true
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
		action = row.action,
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

	local bestN = 0
	local bestJ = 1
	local maxN = #stored
	if #incoming < maxN then
		maxN = #incoming
	end
	for n = maxN, 1, -1 do
		local start = #stored - n + 1
		local jLast = 1
		if start == 1 then
			jLast = #incoming - n + 1
		end
		local found = false
		for j = 1, jLast do
			if aligns(stored, start, incoming, j, n) then
				bestN = n
				bestJ = j
				found = true
				break
			end
		end
		if found then
			break
		end
	end

	if bestN == 0 then
		guild.gaps[#guild.gaps + 1] = {
			stream = stream,
			beforeId = guild.nextId,
		}
		for i = 1, #incoming do
			appendRow(guild, stream, incoming[i])
		end
		return #incoming, true
	end

	local added = 0
	local start = #stored - bestN + 1
	if bestJ > 1 and start == 1 then
		local older = {}
		for i = 1, bestJ - 1 do
			older[#older + 1] = incoming[i]
		end
		prependRows(guild, stream, older)
		added = added + #older
	end
	for i = bestJ + bestN, #incoming do
		appendRow(guild, stream, incoming[i])
		added = added + 1
	end
	return added, false
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
		})
	end
	return table.concat(lines, "\n"), #guild.txns, shown
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
