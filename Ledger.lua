-- Append-only guild bank ledger.
-- Each guild bank tab, and the money log, is its own ordered stream.
-- A new read is matched against lines already saved, in any order. A line
-- already stored is not added again. Lines the log no longer shows stay put.
-- A line that still has a clock time wins. The lines directly above and below
-- it, in that log, identify it. Money and item tabs are separate logs. A
-- later read with the same neighbors is the same transaction even when the
-- clock time moved. The day moves only when a clock time arrives for a line
-- that did not have one. Lines that have scrolled off the log stay put.

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
		requiredNames = true,
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

-- A clock time is kept only while the log's age was still in hours.
-- Hour 0 is midnight, so a missing hour is nil rather than a false hour.
local function hasClock(row)
	if row.precision == "hour" then
		return row.hour ~= nil
	end
	if not row.precision and row.hour ~= nil then
		return true
	end
	return false
end

local function isDateOnly(row)
	if row.precision == "month" or row.precision == "year" then
		return false
	end
	return not hasClock(row)
end

local function sameLine(a, b)
	local actionA = canonicalAction(a.action)
	local actionB = canonicalAction(b.action)
	if actionA ~= actionB then
		return false
	end
	if a.who ~= b.who then
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

-- Same calendar day for a timed line and a date-only line. Two timed lines
-- also have to agree within two hours. A month or year age is coarse, so
-- those lines may land further apart and still be the same event. A date
-- that landed on a different day is kept: after the hour is gone the log
-- cannot be matched with certainty.
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
	if hasClock(a) and hasClock(b) then
		return math.abs(a.hour - b.hour) <= 2
	end
	return true
end

-- A timed line is preferred over a date-only line of the same event.
-- Upgrading a date-only row is allowed only when no timed row already covers
-- it, so a second timed withdrawal is not written onto the first one's copy.
local function findUnused(stored, used, row)
	local datedIndex = nil
	for i = 1, #stored do
		if not used[i] and sameEvent(stored[i], row) then
			if hasClock(stored[i]) or not hasClock(row) then
				return i
			end
			if not datedIndex then
				datedIndex = i
			end
		end
	end
	if datedIndex then
		local dated = stored[datedIndex]
		for i = 1, #stored do
			if hasClock(stored[i]) and sameEvent(stored[i], dated) then
				return nil
			end
		end
	end
	return datedIndex
end

local function takeClock(stored, incoming)
	if hasClock(incoming) and not hasClock(stored) then
		stored.hour = incoming.hour
		stored.precision = incoming.precision or "hour"
		if incoming.day then
			stored.day = incoming.day
		end
	end
end

-- The log can move a line onto the next calendar day once the hour is gone.
-- One day is the slip seen in practice. A wider gap is a different visit.
local function daySlip(a, b)
	return GBLF.Time.DayDistance(a.day, b.day) <= 1
end

-- How many date-only lines at `dates`, starting at i, repeat the timed lines
-- at `times`, starting at j. The lines have to stay in log order. Comparing
-- who, action, and amount is enough; the day does not have to agree.
local function echoRunLength(dates, i, times, j, used)
	local len = 0
	while dates[i + len] and times[j + len] do
		if i + len == j and dates == times then
			break
		end
		if used and used[j + len] then
			break
		end
		local dated = dates[i + len]
		local timed = times[j + len]
		if not (isDateOnly(dated) and hasClock(timed) and sameLine(dated, timed) and daySlip(dated, timed)) then
			break
		end
		len = len + 1
	end
	return len
end

-- A date-only stretch of two or more lines that repeats a timed stretch.
-- One repeated line is not enough unless the lines on either side agree too.
local function echoMap(dates, times)
	local echo = {}
	local used = {}
	local i = 1
	while i <= #dates do
		local bestLen = 0
		local bestJ = nil
		if isDateOnly(dates[i]) then
			for j = 1, #times do
				if hasClock(times[j]) and not used[j] then
					local len = echoRunLength(dates, i, times, j, used)
					if len > bestLen then
						bestLen = len
						bestJ = j
					end
				end
			end
		end
		if bestLen >= 2 and bestJ then
			for k = 0, bestLen - 1 do
				echo[i + k] = bestJ + k
				used[bestJ + k] = true
			end
			i = i + bestLen
		else
			i = i + 1
		end
	end
	for i = 1, #dates do
		if not echo[i] and isDateOnly(dates[i]) then
			for j = 1, #times do
				if not used[j] and hasClock(times[j]) and sameLine(dates[i], times[j]) and daySlip(dates[i], times[j]) then
					local confirmed = false
					local ok = true
					if dates[i - 1] and times[j - 1] then
						if sameLine(dates[i - 1], times[j - 1]) then
							confirmed = true
						else
							ok = false
						end
					end
					if ok and dates[i + 1] and times[j + 1] then
						if sameLine(dates[i + 1], times[j + 1]) then
							confirmed = true
						else
							ok = false
						end
					end
					if ok and confirmed then
						echo[i] = j
						used[j] = true
						break
					end
				end
			end
		end
	end
	return echo
end

local function dropRepeatedRuns(rows)
	local echo = echoMap(rows, rows)
	local kept = {}
	for i = 1, #rows do
		if not echo[i] then
			kept[#kept + 1] = rows[i]
		end
	end
	return kept
end

-- One scan can hold a line twice while its age changes from hours to a date.
-- Keep the timed copy. A date-only line with no timed match in this scan stays.
local function dropDatedShadows(rows)
	local clocks = {}
	for i = 1, #rows do
		if hasClock(rows[i]) then
			clocks[#clocks + 1] = rows[i]
		end
	end
	if #clocks == 0 then
		return rows
	end
	local kept = {}
	for i = 1, #rows do
		local row = rows[i]
		local shadow = false
		if isDateOnly(row) then
			for j = 1, #clocks do
				if sameEvent(clocks[j], row) then
					shadow = true
					break
				end
			end
		end
		if not shadow then
			kept[#kept + 1] = row
		end
	end
	return kept
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

-- The money log writes a purchase notice ("purchased a guild bank tab") beside
-- the withdrawal. The notice is not a second payment. Drop it. The next tab
-- is a new amount, so this does not match on a fixed price. A notice with no
-- withdrawal beside it is kept once, as the withdrawal, so gold already saved
-- under that name is not thrown away.
local function samePurse(a, b)
	if a.who ~= b.who or a.copper ~= b.copper then
		return false
	end
	if a.stream and b.stream and a.stream ~= b.stream then
		return false
	end
	local ap = a.precision
	local bp = b.precision
	if ap == "year" or bp == "year" or ap == "month" or bp == "month" then
		return timeOk(a, b)
	end
	return GBLF.Time.DayDistance(a.day, b.day) == 0
end

local function isTabWithdrawal(action)
	action = canonicalAction(action)
	return action == "withdraw" or action == "withdrawForTab"
end

local function dropBuyTabNotices(rows)
	local withdrawals = {}
	for i = 1, #rows do
		if isTabWithdrawal(rows[i].action) then
			withdrawals[#withdrawals + 1] = rows[i]
		end
	end
	local kept = {}
	local removed = 0
	for i = 1, #rows do
		local row = rows[i]
		if canonicalAction(row.action) ~= "buyTab" then
			kept[#kept + 1] = row
		else
			local covered = false
			for j = 1, #withdrawals do
				if samePurse(row, withdrawals[j]) then
					covered = true
					break
				end
			end
			if covered then
				if hasClock(row) then
					for j = 1, #withdrawals do
						if samePurse(row, withdrawals[j]) and not hasClock(withdrawals[j]) then
							takeClock(withdrawals[j], row)
							break
						end
					end
				end
				removed = removed + 1
			else
				row.action = "withdrawForTab"
				withdrawals[#withdrawals + 1] = row
				kept[#kept + 1] = row
			end
		end
	end
	return kept, removed
end

function Ledger.CollapseTabPairs(guild)
	local kept, removed = dropBuyTabNotices(guild.txns)
	guild.txns = kept
	return removed
end

-- Drop a saved date-only line when a timed line already records it.
-- Same day is enough. A different day still counts when the lines beside it,
-- in log order, are the same people, actions, and amounts. Two date-only
-- lines are left alone. This runs on every load. CollapseDuplicates runs
-- once, so it cannot see a copy stored after that pass.
function Ledger.PreferTimestamps(guild)
	local streams = {}
	local order = {}
	for i = 1, #guild.txns do
		local txn = guild.txns[i]
		local stream = txn.stream or ""
		local list = streams[stream]
		if not list then
			list = {}
			streams[stream] = list
			order[#order + 1] = stream
		end
		list[#list + 1] = txn
	end
	local drop = {}
	for s = 1, #order do
		local rows = streams[order[s]]
		local echo = echoMap(rows, rows)
		for i = 1, #rows do
			if echo[i] then
				drop[rows[i]] = true
			end
		end
		for a = 1, #rows do
			if isDateOnly(rows[a]) and not drop[rows[a]] then
				for b = 1, #rows do
					if hasClock(rows[b]) and sameEvent(rows[b], rows[a]) then
						drop[rows[a]] = true
						break
					end
				end
			end
		end
	end
	local kept = {}
	local removed = 0
	for i = 1, #guild.txns do
		if drop[guild.txns[i]] then
			removed = removed + 1
		else
			kept[#kept + 1] = guild.txns[i]
		end
	end
	guild.txns = kept
	return removed
end

-- An interior line is the same transaction when the line above it and the
-- line below it are the same people, actions, and amounts. The clock does
-- not have to agree. The line at each end of a scan has only one neighbor,
-- so it is not identified this way.
local function findByNeighbors(stored, used, incoming, i)
	if i <= 1 or i >= #incoming then
		return nil
	end
	for j = 2, #stored - 1 do
		if not used[j]
			and sameLine(stored[j], incoming[i])
			and sameLine(stored[j - 1], incoming[i - 1])
			and sameLine(stored[j + 1], incoming[i + 1]) then
			return j
		end
	end
	return nil
end

local function sameLineAny(stored, row)
	for i = 1, #stored do
		if sameLine(stored[i], row) then
			return true
		end
	end
	return false
end

local function sameEventAny(stored, row)
	for i = 1, #stored do
		if sameEvent(stored[i], row) then
			return true
		end
	end
	return false
end

-- incoming is oldest-first. Returns how many lines were added, and whether
-- this read missed the previous tail (the log rolled past between scans).
-- fromSaved is a ledger or an import. A scan still skips a line above the
-- overlap when the person and amount already appear. A saved ledger skips
-- that line only when it is the same event.
function Ledger.MergeStream(guild, stream, incoming, fromSaved)
	if not incoming or #incoming == 0 then
		return 0, false
	end
	incoming = dropBuyTabNotices(incoming)
	incoming = dropDatedShadows(incoming)
	incoming = dropRepeatedRuns(incoming)
	if #incoming == 0 then
		Ledger.PreferTimestamps(guild)
		return 0, false
	end

	local stored = Ledger.StreamRows(guild, stream)
	if #stored == 0 then
		for i = 1, #incoming do
			appendRow(guild, stream, incoming[i])
		end
		Ledger.PreferTimestamps(guild)
		return #incoming, false
	end

	local echo = echoMap(incoming, stored)
	local used = {}
	local partner = {}
	for i = 1, #incoming do
		local index = findByNeighbors(stored, used, incoming, i)
		if not index then
			index = findUnused(stored, used, incoming[i])
		end
		if not index and echo[i] and not used[echo[i]] then
			index = echo[i]
		end
		if index then
			takeClock(stored[index], incoming[i])
			used[index] = true
			partner[i] = index
		end
	end
	local matched = false
	local firstJ = nil
	local lastJ = nil
	local continues = false
	local seenPartner = false
	for i = 1, #incoming do
		if partner[i] then
			matched = true
			seenPartner = true
			if not firstJ or partner[i] < firstJ then
				firstJ = partner[i]
			end
			if not lastJ or partner[i] > lastJ then
				lastJ = partner[i]
			end
		elseif seenPartner then
			continues = true
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
		Ledger.PreferTimestamps(guild)
		return #incoming, true
	end

	-- A saved line the scan did not use, sitting between two lines it did
	-- recognize, is an extra copy when it repeats one of those lines.
	-- The same applies past the last recognized line when the scan has
	-- moved on. Lines before the overlap have scrolled off and stay.
	-- An identical line sitting directly beside its match stays: one read
	-- can hold two real deposits of the same amount.
	local function repeatCopy(j)
		if used[j] then
			return false
		end
		for u = 1, #stored do
			if used[u] and sameLine(stored[u], stored[j]) and math.abs(u - j) > 1 then
				return true
			end
		end
		return false
	end
	local covered = {}
	if firstJ and lastJ then
		for j = firstJ + 1, lastJ - 1 do
			if repeatCopy(j) then
				covered[stored[j]] = true
			end
		end
	end
	if continues and lastJ then
		for j = lastJ + 1, #stored do
			if repeatCopy(j) then
				covered[stored[j]] = true
			end
		end
	end
	if next(covered) then
		local kept = {}
		for i = 1, #guild.txns do
			if not covered[guild.txns[i]] then
				kept[#kept + 1] = guild.txns[i]
			end
		end
		guild.txns = kept
	end

	local older = {}
	local newer = {}
	local seen = false
	for i = 1, #incoming do
		if partner[i] then
			seen = true
		elseif not seen then
			-- The log is cut off above this line. A drifted re-read of a line
			-- already saved is not stored again. A line we have never saved is.
			-- A saved ledger can hold the same amount on another day.
			local already
			if fromSaved then
				already = sameEventAny(stored, incoming[i])
			else
				already = sameLineAny(stored, incoming[i])
			end
			if not already then
				older[#older + 1] = incoming[i]
			end
		else
			newer[#newer + 1] = incoming[i]
		end
	end

	prependRows(guild, stream, older)
	for i = 1, #newer do
		appendRow(guild, stream, newer[i])
	end
	Ledger.PreferTimestamps(guild)
	return #older + #newer, false
end

local function copyScanRow(txn)
	return {
		action = txn.action,
		who = txn.who,
		day = txn.day,
		hour = txn.hour,
		precision = txn.precision,
		itemID = txn.itemID,
		itemName = txn.itemName,
		count = txn.count,
		copper = txn.copper,
		tab = txn.tab,
		dest = txn.dest,
		summary = txn.summary,
		stream = txn.stream,
	}
end

local function stampRank(stamp)
	if type(stamp) ~= "table" then
		return -1
	end
	return ((stamp.year or 0) * 10000000000)
		+ ((stamp.month or 0) * 100000000)
		+ ((stamp.day or 0) * 1000000)
		+ ((stamp.hour or 0) * 10000)
		+ ((stamp.min or 0) * 100)
		+ (stamp.sec or 0)
end

local function copyStamp(stamp)
	if type(stamp) ~= "table" then
		return nil
	end
	return {
		year = stamp.year,
		month = stamp.month,
		day = stamp.day,
		hour = stamp.hour,
		min = stamp.min,
		sec = stamp.sec,
	}
end

-- Fold source into target. Target keeps its name and realm. Source is left
-- as it was. Returns added, seen. On failure added is nil.
function Ledger.MergeGuild(target, source)
	if type(target) ~= "table" or type(target.txns) ~= "table" then
		return nil, "There is no ledger to merge into."
	end
	if type(source) ~= "table" or type(source.txns) ~= "table" then
		return nil, "That ledger has nothing to merge."
	end
	if target == source then
		return nil, "A ledger cannot be merged into itself."
	end

	local byStream = {}
	local order = {}
	for i = 1, #source.txns do
		local txn = source.txns[i]
		local stream = txn.stream or ""
		local list = byStream[stream]
		if not list then
			list = {}
			byStream[stream] = list
			order[#order + 1] = stream
		end
		list[#list + 1] = copyScanRow(txn)
	end

	local added = 0
	for i = 1, #order do
		local gained = Ledger.MergeStream(target, order[i], byStream[order[i]], true)
		added = added + (gained or 0)
	end

	if type(source.tabNames) == "table" then
		target.tabNames = type(target.tabNames) == "table" and target.tabNames or {}
		for tab, name in pairs(source.tabNames) do
			local have = target.tabNames[tab]
			if type(name) == "string" and name ~= "" and (type(have) ~= "string" or have == "") then
				target.tabNames[tab] = name
			end
		end
	end

	if stampRank(source.lastScan) > stampRank(target.lastScan) then
		target.lastScan = copyStamp(source.lastScan)
	end
	return added, #source.txns
end

local function copyFields(row)
	local out = {}
	for key, value in pairs(row) do
		if type(value) ~= "table" then
			out[key] = value
		end
	end
	return out
end

-- A separate ledger with the same lines. Later edits do not change the original.
function Ledger.CopyGuild(guild, realm)
	local copy = Ledger.NewGuild(guild.name, realm)
	for i = 1, #guild.txns do
		copy.txns[i] = copyFields(guild.txns[i])
	end
	copy.nextId = guild.nextId or (#copy.txns + 1)
	copy.nextOrd = guild.nextOrd or copy.nextId
	if type(guild.gaps) == "table" then
		for i = 1, #guild.gaps do
			copy.gaps[i] = copyFields(guild.gaps[i])
		end
	end
	if type(guild.tabNames) == "table" then
		for tab, name in pairs(guild.tabNames) do
			copy.tabNames[tab] = name
		end
	end
	copy.lastScan = copyStamp(guild.lastScan)
	return copy
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
				if hasClock(txn) and not hasClock(kept[j]) then
					kept[j] = txn
				end
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

-- Older scans stored a blank log name as "Unknown". The name never matched
-- the real line, so the gold and items were counted twice. This runs once.
-- A character who is actually named Unknown is kept after that.
function Ledger.DropNameless(guild)
	local kept = {}
	local removed = 0
	for i = 1, #guild.txns do
		local who = guild.txns[i].who
		local blank = type(who) ~= "string" or string.match(who, "^%s*$") ~= nil
		if blank or who == "Unknown" then
			removed = removed + 1
		else
			kept[#kept + 1] = guild.txns[i]
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

local function namedRow(cache, who)
	if type(who) ~= "string" or string.match(who, "^%s*$") then
		return nil
	end
	return charRow(cache, who)
end

local function give(row, field, amount)
	if row then
		row[field] = row[field] + amount
	end
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
			local who = namedRow(cache, txn.who)
			if txn.action == "deposit" then
				cache.goldIn = cache.goldIn + txn.copper
				give(who, "goldIn", txn.copper)
				day.goldIn = day.goldIn + txn.copper
			elseif txn.action == "repair" then
				cache.repairs = cache.repairs + txn.copper
				give(who, "repair", txn.copper)
				day.repair = day.repair + txn.copper
			elseif txn.action == "withdrawForTab" or txn.action == "buyTab" then
				cache.goldOut = cache.goldOut + txn.copper
				cache.tabCost = cache.tabCost + txn.copper
				give(who, "goldOut", txn.copper)
				day.goldOut = day.goldOut + txn.copper
				day.tabCost = day.tabCost + txn.copper
			elseif txn.action == "withdraw" then
				cache.goldOut = cache.goldOut + txn.copper
				give(who, "goldOut", txn.copper)
				day.goldOut = day.goldOut + txn.copper
			end
		end
		if not txn.summary and txn.count and txn.count ~= 0 and txn.action ~= "move" then
			local who = namedRow(cache, txn.who)
			local item = itemRow(cache, txn)
			if txn.action == "deposit" then
				cache.itemIn = cache.itemIn + txn.count
				give(who, "itemIn", txn.count)
				item.itemIn = item.itemIn + txn.count
				day.itemIn = day.itemIn + txn.count
			elseif txn.action == "withdraw" then
				cache.itemOut = cache.itemOut + txn.count
				give(who, "itemOut", txn.count)
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

		local who = trim(cell(fields, header.character))
		if who == "" then
			return nil, nil, fail("needs a character.")
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
		local gained = Ledger.MergeStream(guild, stream, byStream[stream], true)
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
