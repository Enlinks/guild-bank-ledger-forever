-- Run with Lua 5.1: lua tests/merge_test.lua
-- The ledger and the day math do not need the WoW client.

local root = arg[0]:match("^(.*)/") or "."
if root == "tests" or root == "./tests" then
	-- launched from the repo, arg[0] is tests/merge_test.lua
end
local dir = arg[0]:gsub("[^/]+$", "")
if dir == "" then
	dir = "./"
end
dofile(dir .. "../Time.lua")
dofile(dir .. "../Ledger.lua")

local failed = 0
local function eq(actual, expected, label)
	if actual ~= expected then
		failed = failed + 1
		io.stderr:write(string.format("FAIL %s\n  got: %s\n  want: %s\n", label, tostring(actual), tostring(expected)))
	end
end

local Time = GBLF.Time
local Ledger = GBLF.Ledger

local y, m, d = Time.AddDays(2026, 10, 1, 0)
eq(y, 2026, "same year")
eq(m, 10, "same month")
eq(d, 1, "same day")

y, m, d = Time.AddDays(2026, 3, 1, -1)
eq(string.format("%04d-%02d-%02d", y, m, d), "2026-02-28", "non-leap")

y, m, d = Time.AddDays(2024, 3, 1, -1)
eq(string.format("%04d-%02d-%02d", y, m, d), "2024-02-29", "leap day")

y, m, d = Time.AddDays(2026, 1, 1, -1)
eq(string.format("%04d-%02d-%02d", y, m, d), "2025-12-31", "year boundary")

eq(Time.CivilToSerial(1970, 1, 1), 0, "unix epoch")
eq(Time.ParseIso("2026-10-01"), Time.Pack(2026, 10, 1), "iso day")
eq(Time.ParseIso("2024-02-29"), Time.Pack(2024, 2, 29), "iso leap day")
eq(Time.ParseIso("2026-02-31"), nil, "iso rejects a day the month does not have")
eq(Time.ParseIso("2026-10-1"), nil, "iso requires two digits")

local scan = { year = 2026, month = 10, day = 1, hour = 0, min = 10 }
local aged = Time.FromAge(scan, 0, 0, 0, 1)
eq(Time.IsoDay(aged.day), "2026-09-30", "hour crosses midnight")
eq(aged.hour, 23, "clock hour after midnight")
eq(aged.precision, "hour", "hour precision")

scan = { year = 2026, month = 10, day = 1, hour = 15, min = 0 }
aged = Time.FromAge(scan, 0, 0, 3, 12)
eq(Time.IsoDay(aged.day), "2026-09-28", "day ignores hour field")
eq(aged.hour, nil, "no hour stored for a day-old line")
eq(aged.precision, "day", "day precision")

local function line(who, action, day, extra)
	extra = extra or {}
	return {
		action = action,
		who = who,
		day = day,
		hour = extra.hour,
		precision = extra.precision or "day",
		itemID = extra.itemID,
		itemName = extra.itemName,
		count = extra.count,
		copper = extra.copper,
		tab = extra.tab,
		dest = extra.dest,
		summary = extra.summary,
		ageRank = extra.ageRank or 0,
		apiIndex = extra.apiIndex or 1,
	}
end

local function names(guild, stream)
	local rows = Ledger.StreamRows(guild, stream)
	local out = {}
	for i = 1, #rows do
		out[i] = rows[i].who
	end
	return table.concat(out, ",")
end

local guild = Ledger.NewGuild("OLYMPUS", "Realm")
local day = Time.Pack(2026, 10, 1)
local added, gap = Ledger.MergeStream(guild, "tab:1", {
	line("A", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
	line("B", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
	line("C", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
})
eq(added, 3, "first scan adds all")
eq(gap, false, "first scan is not a gap")

added, gap = Ledger.MergeStream(guild, "tab:1", {
	line("B", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
	line("C", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
	line("D", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
})
eq(added, 1, "overlap appends only the new tail")
eq(gap, false, "overlap is not a gap")
eq(names(guild, "tab:1"), "A,B,C,D", "order after overlap")

added, gap = Ledger.MergeStream(guild, "tab:1", {
	line("B", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
	line("C", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
	line("D", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
})
eq(added, 0, "rescan adds nothing")
eq(#guild.txns, 4, "rescan does not duplicate")

-- Two identical deposits on the same day both stay when the window still holds both.
local twins = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(twins, "tab:1", {
	line("A", "deposit", day, { itemID = 5, count = 20, tab = 1 }),
	line("A", "deposit", day, { itemID = 5, count = 20, tab = 1 }),
	line("B", "withdraw", day, { itemID = 5, count = 1, tab = 1 }),
})
added = Ledger.MergeStream(twins, "tab:1", {
	line("A", "deposit", day, { itemID = 5, count = 20, tab = 1 }),
	line("B", "withdraw", day, { itemID = 5, count = 1, tab = 1 }),
	line("C", "deposit", day, { itemID = 9, count = 2, tab = 1 }),
})
eq(added, 1, "identical twins keep their sequence")
eq(names(twins, "tab:1"), "A,A,B,C", "twins then the new line")

local rolled = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(rolled, "tab:1", {
	line("A", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
	line("B", "deposit", day, { itemID = 2, count = 1, tab = 1 }),
})
added, gap = Ledger.MergeStream(rolled, "tab:1", {
	line("X", "deposit", day, { itemID = 3, count = 1, tab = 1 }),
	line("Y", "deposit", day, { itemID = 4, count = 1, tab = 1 }),
})
eq(gap, true, "a missed tail is a gap")
eq(added, 2, "gap still keeps the new lines")
eq(#rolled.gaps, 1, "one gap recorded")
eq(names(rolled, "tab:1"), "A,B,X,Y", "gap appends after history")

local partial = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(partial, "tab:1", {
	line("C", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
	line("D", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
})
added, gap = Ledger.MergeStream(partial, "tab:1", {
	line("A", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
	line("B", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
	line("C", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
	line("D", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
	line("E", "deposit", day, { itemID = 1, count = 1, tab = 1 }),
})
eq(gap, false, "recovering older lines is not a gap")
eq(added, 3, "older lines and the new tail")
eq(names(partial, "tab:1"), "A,B,C,D,E", "recovered prefix stays in order")

added, gap = Ledger.MergeStream(guild, "tab:1", {})
eq(added, 0, "empty read adds nothing")
eq(#guild.gaps, 0, "empty read is not a gap")

-- Hour pins that still describe the same clock hour match across scans.
local timed = Ledger.NewGuild("OLYMPUS", "Realm")
local morning = Time.Pack(2026, 10, 1)
Ledger.MergeStream(timed, "money", {
	line("A", "deposit", morning, { copper = 10000, precision = "hour", hour = 10 }),
})
added, gap = Ledger.MergeStream(timed, "money", {
	line("A", "deposit", morning, { copper = 10000, precision = "hour", hour = 11 }),
	line("B", "withdraw", morning, { copper = 500, precision = "hour", hour = 12 }),
})
eq(added, 1, "hour within two hours is the same line")
eq(gap, false, "hour match is not a gap")
eq(#timed.txns, 2, "withdrawal is new")

local rows = {
	line("new", "deposit", day, { ageRank = 1, apiIndex = 2, itemID = 1, count = 1 }),
	line("old-day", "deposit", day, { ageRank = 1000000001, apiIndex = 1, itemID = 1, count = 1 }),
	line("older-hour", "deposit", day, { ageRank = 5, apiIndex = 3, itemID = 1, count = 1 }),
}
Ledger.OrderScanRows(rows)
eq(rows[1].who, "old-day", "day-old line sorts before hours")
eq(rows[2].who, "older-hour", "larger hour age is older")
eq(rows[3].who, "new", "small hour age is newest")

local books = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(books, "tab:1", {
	line("Ada", "deposit", day, { itemID = 2589, itemName = "Linen Cloth", count = 20, tab = 1 }),
	line("Ada", "withdraw", day, { itemID = 2589, itemName = "Linen Cloth", count = 5, tab = 1 }),
	line("Ada", "move", day, { itemID = 2589, itemName = "Linen Cloth", count = 10, tab = 1, dest = 2 }),
})
Ledger.MergeStream(books, "money", {
	line("Ada", "deposit", day, { copper = 10000 }),
	line("Ada", "withdraw", day, { copper = 2500 }),
	line("Ada", "repair", day, { copper = 500 }),
	line("Ada", "buyTab", day, { copper = 1000 }),
	line("Ada", "depositSummary", day, { copper = 99999, summary = true }),
})
local other = Ledger.NewGuild("Other", "Realm")
Ledger.MergeStream(other, "money", {
	line("Bea", "deposit", day, { copper = 50 }),
})
local cache = Ledger.Rebuild(books)
eq(cache.goldIn, 10000, "gold in")
eq(cache.goldOut, 3500, "withdraw plus tab")
eq(cache.tabCost, 1000, "tab subset")
eq(books.txns[7].action, "withdrawForTab", "a purchase notice is stored as the withdrawal")
eq(cache.repairs, 500, "repairs")
eq(cache.net, 6000, "net gold")
eq(cache.itemIn, 20, "items in")
eq(cache.itemOut, 5, "items out")
eq(cache.characters.Ada.repair, 500, "repair on the character")
eq(cache.characters.Bea, nil, "guilds do not share totals")
eq(other.txns[1].who, "Bea", "other guild keeps its own line")

local csv, total, shown = Ledger.ExportTransactions(books)
eq(total, 8, "export counts every line")
eq(shown, 8, "export shows every line")
eq(type(string.find(csv, "Linen Cloth", 1, true)), "number", "item name is in the csv")
eq(type(string.find(csv, "depositSummary", 1, true)), "number", "summary line is exported")

local quoted = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(quoted, "tab:1", {
	line('Ada "Ace"', "deposit", day, { itemID = 1, itemName = "Linen, Cloth", count = 1, tab = 1 }),
})
csv = Ledger.ExportTransactions(quoted)
eq(type(string.find(csv, '"Ada ""Ace"""', 1, true)), "number", "quotes are escaped")
eq(type(string.find(csv, '"Linen, Cloth"', 1, true)), "number", "commas are quoted")

-- A later scan can return the same money lines in a different order.
-- That must not store the withdrawal a second time.
local d7 = Time.Pack(2026, 11, 7)
local messy = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(messy, "money", {
	line("Wes", "deposit", d7, { copper = 200 }),
	line("Mira", "withdraw", d7, { copper = 95000 }),
	line("Hope", "deposit", d7, { copper = 500 }),
})
added, gap = Ledger.MergeStream(messy, "money", {
	line("Hope", "deposit", d7, { copper = 500 }),
	line("Mira", "withdraw", d7, { copper = 95000 }),
	line("Wes", "deposit", d7, { copper = 200 }),
})
eq(added, 0, "reordered rescan adds nothing")
eq(gap, false, "reorder is not a gap")
eq(#messy.txns, 3, "reorder does not duplicate the withdrawal")

local d9 = Time.Pack(2026, 11, 9)
local agedLine = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(agedLine, "money", {
	line("Mira", "deposit", d9, { copper = 10000, precision = "hour", hour = 12 }),
})
added, gap = Ledger.MergeStream(agedLine, "money", {
	line("Mira", "deposit", d9, { copper = 10000, precision = "day" }),
})
eq(added, 0, "a day-old reread matches the pinned hour")
eq(#agedLine.txns, 1, "aging a line does not duplicate it")
eq(agedLine.txns[1].hour, 12, "the timed line keeps its hour")
eq(agedLine.txns[1].precision, "hour", "a date-only reread does not wipe the hour")

local d18 = Time.Pack(2026, 11, 18)
local d19 = Time.Pack(2026, 11, 19)
local d20 = Time.Pack(2026, 11, 20)
local faded = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(faded, "money", {
	line("Mira", "deposit", d19, { copper = 50000, precision = "hour", hour = 21 }),
	line("Mira", "withdrawForTab", d19, { copper = 10000000, precision = "hour", hour = 21 }),
})
added, gap = Ledger.MergeStream(faded, "money", {
	line("Mira", "deposit", d19, { copper = 50000, precision = "day" }),
	line("Mira", "withdrawForTab", d19, { copper = 10000000, precision = "day" }),
})
eq(added, 0, "a same-day date-only reread is ignored")
eq(gap, false, "a date-only reread of timed lines is not a gap")
eq(#faded.txns, 2, "the timed deposit and tab buy stay")
eq(faded.txns[1].hour, 21, "the deposit keeps its clock time")
eq(faded.txns[2].hour, 21, "the tab buy keeps its clock time")

added, gap = Ledger.MergeStream(faded, "money", {
	line("Mira", "deposit", d20, { copper = 50000, precision = "day" }),
	line("Mira", "deposit", d19, { copper = 50000, precision = "day" }),
})
eq(added, 0, "a cut-off re-read of the same deposit is not stored again")
eq(gap, false, "the same-day reread still overlaps")
eq(#faded.txns, 2, "the timed deposit stays the only copy")
eq(faded.txns[1].hour, 21, "the first clock time stays")

local datedFirst = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(datedFirst, "money", {
	line("Mira", "deposit", d19, { copper = 50000, precision = "day" }),
})
added, gap = Ledger.MergeStream(datedFirst, "money", {
	line("Mira", "deposit", d19, { copper = 50000, precision = "hour", hour = 21 }),
})
eq(added, 0, "a later clock time replaces the date-only line")
eq(#datedFirst.txns, 1, "the upgrade does not store a second deposit")
eq(datedFirst.txns[1].hour, 21, "the saved line takes the clock time")
eq(datedFirst.txns[1].precision, "hour", "the saved line becomes timed")
eq(datedFirst.txns[1].day, d19, "the saved day stays on that day")

local onlyDated = Ledger.NewGuild("OLYMPUS", "Realm")
added = Ledger.MergeStream(onlyDated, "money", {
	line("Mira", "deposit", d19, { copper = 50000, precision = "day" }),
	line("Mira", "deposit", d19, { copper = 50000, precision = "day" }),
})
eq(added, 2, "two date-only deposits are both kept")
eq(#onlyDated.txns, 2, "no timed line means nothing is dropped")

local oneScan = Ledger.NewGuild("OLYMPUS", "Realm")
added = Ledger.MergeStream(oneScan, "money", {
	line("Mira", "deposit", d19, { copper = 50000, precision = "hour", hour = 21 }),
	line("Mira", "deposit", d19, { copper = 50000, precision = "day" }),
	line("Mira", "deposit", d19, { copper = 10000, precision = "day" }),
})
eq(added, 2, "the same scan keeps the timed line and a different amount")
eq(oneScan.txns[1].hour, 21, "the timed deposit is the one stored")
eq(oneScan.txns[2].copper, 10000, "the other date-only deposit stays")

local beside = Ledger.NewGuild("OLYMPUS", "Realm")
added = Ledger.MergeStream(beside, "money", {
	line("Mira", "deposit", d18, { copper = 50000, precision = "day" }),
	line("Mira", "deposit", d19, { copper = 50000, precision = "hour", hour = 21 }),
})
eq(added, 2, "the previous day's deposit is not the timed line")
eq(beside.txns[1].precision, "day", "the previous day stays date-only")
eq(beside.txns[2].hour, 21, "the timed deposit stays timed")

local midnight = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(midnight, "money", {
	line("Mira", "deposit", d19, { copper = 100, precision = "hour", hour = 0 }),
})
added = Ledger.MergeStream(midnight, "money", {
	line("Mira", "deposit", d19, { copper = 100, precision = "hour", hour = 15 }),
})
eq(added, 1, "midnight and an afternoon deposit both stay")
eq(#midnight.txns, 2, "hour 0 is a real clock time")
added = Ledger.MergeStream(midnight, "money", {
	line("Mira", "deposit", d19, { copper = 100, precision = "day" }),
})
eq(added, 0, "a date-only reread matches the midnight line")
eq(#midnight.txns, 2, "the afternoon deposit stays beside midnight")

local savedEcho = Ledger.NewGuild("OLYMPUS", "Realm")
savedEcho.txns = {
	{ id = 1, ord = 1, stream = "money", action = "deposit", who = "Mira", day = d19, precision = "day", copper = 50000 },
	{ id = 2, ord = 2, stream = "money", action = "withdrawForTab", who = "Mira", day = d19, precision = "day", copper = 10000000 },
	{ id = 3, ord = 3, stream = "money", action = "deposit", who = "Mira", day = d19, precision = "hour", hour = 21, copper = 50000 },
	{ id = 4, ord = 4, stream = "money", action = "withdrawForTab", who = "Mira", day = d19, precision = "hour", hour = 21, copper = 10000000 },
	{ id = 5, ord = 5, stream = "tab:1", action = "deposit", who = "Mira", day = d19, precision = "hour", hour = 6, itemID = 4306, count = 1, tab = 1 },
	{ id = 6, ord = 6, stream = "money", action = "withdraw", who = "Mira", day = d18, precision = "day", copper = 2500 },
}
local echoRemoved = Ledger.PreferTimestamps(savedEcho)
eq(echoRemoved, 2, "saved date-only copies of timed lines are dropped")
eq(#savedEcho.txns, 4, "the timed lines and the unmatched withdrawal stay")
eq(savedEcho.txns[1].hour, 21, "the timed deposit is kept")
eq(savedEcho.txns[2].hour, 21, "the timed tab buy is kept")
eq(savedEcho.txns[3].hour, 6, "a timed item line with no date-only copy stays")
eq(savedEcho.txns[4].copper, 2500, "a date-only line with no timed match stays")
eq(Ledger.Rebuild(savedEcho).goldIn, 50000, "the deposit is counted once")
eq(Ledger.Rebuild(savedEcho).tabCost, 10000000, "the tab buy is counted once")
eq(Ledger.PreferTimestamps(savedEcho), 0, "a second pass finds nothing new")

local slipped = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(slipped, "money", {
	line("Theo", "deposit", d18, { copper = 5000, precision = "hour", hour = 10 }),
	line("Omar", "deposit", d18, { copper = 4000, precision = "hour", hour = 20 }),
	line("Mira", "deposit", d18, { copper = 50000, precision = "hour", hour = 21 }),
	line("Sol", "deposit", d18, { copper = 350000, precision = "hour", hour = 21 }),
	line("Mira", "buyTab", d18, { copper = 1000000, precision = "hour", hour = 21 }),
	line("Quin", "deposit", d18, { copper = 50000, precision = "hour", hour = 23 }),
	line("Vale", "deposit", d19, { copper = 2000, precision = "hour", hour = 6 }),
})
added, gap = Ledger.MergeStream(slipped, "money", {
	line("Theo", "deposit", d19, { copper = 5000, precision = "day" }),
	line("Omar", "deposit", d19, { copper = 4000, precision = "day" }),
	line("Mira", "deposit", d19, { copper = 50000, precision = "day" }),
	line("Sol", "deposit", d19, { copper = 350000, precision = "day" }),
	line("Mira", "buyTab", d19, { copper = 1000000, precision = "day" }),
	line("Quin", "deposit", d19, { copper = 50000, precision = "day" }),
	line("Tess", "deposit", d19, { copper = 50000, precision = "hour", hour = 17 }),
})
eq(added, 1, "a repeated stretch one day later adds nothing but the new deposit")
eq(gap, false, "a repeated stretch still overlaps the saved log")
eq(#slipped.txns, 8, "the timed stretch stays and the new deposit is kept")
eq(slipped.txns[4].who, "Sol", "Sol stays on the timed line")
eq(slipped.txns[4].hour, 21, "Sol keeps the clock time")
eq(slipped.txns[8].who, "Tess", "the deposit after the stretch is new")
eq(Ledger.Rebuild(slipped).goldIn, 5000 + 4000 + 50000 + 350000 + 50000 + 2000 + 50000, "the slipped deposits are not counted twice")

local alreadySlipped = Ledger.NewGuild("OLYMPUS", "Realm")
alreadySlipped.txns = {
	{ id = 1, ord = 1, stream = "money", action = "deposit", who = "Theo", day = d18, precision = "hour", hour = 10, copper = 5000 },
	{ id = 2, ord = 2, stream = "money", action = "deposit", who = "Omar", day = d18, precision = "hour", hour = 20, copper = 4000 },
	{ id = 3, ord = 3, stream = "money", action = "deposit", who = "Mira", day = d18, precision = "hour", hour = 21, copper = 50000 },
	{ id = 4, ord = 4, stream = "money", action = "deposit", who = "Sol", day = d18, precision = "hour", hour = 21, copper = 350000 },
	{ id = 5, ord = 5, stream = "money", action = "buyTab", who = "Mira", day = d18, precision = "hour", hour = 21, copper = 1000000 },
	{ id = 6, ord = 6, stream = "money", action = "deposit", who = "Quin", day = d18, precision = "hour", hour = 23, copper = 50000 },
	{ id = 7, ord = 7, stream = "money", action = "deposit", who = "Vale", day = d19, precision = "hour", hour = 6, copper = 2000 },
	{ id = 8, ord = 8, stream = "money", action = "deposit", who = "Theo", day = d19, precision = "day", copper = 5000 },
	{ id = 9, ord = 9, stream = "money", action = "deposit", who = "Omar", day = d19, precision = "day", copper = 4000 },
	{ id = 10, ord = 10, stream = "money", action = "deposit", who = "Mira", day = d19, precision = "day", copper = 50000 },
	{ id = 11, ord = 11, stream = "money", action = "deposit", who = "Sol", day = d19, precision = "day", copper = 350000 },
	{ id = 12, ord = 12, stream = "money", action = "buyTab", who = "Mira", day = d19, precision = "day", copper = 1000000 },
	{ id = 13, ord = 13, stream = "money", action = "deposit", who = "Quin", day = d19, precision = "day", copper = 50000 },
	{ id = 14, ord = 14, stream = "money", action = "deposit", who = "Tess", day = d19, precision = "hour", hour = 17, copper = 50000 },
}
eq(Ledger.PreferTimestamps(alreadySlipped), 6, "a saved repeated stretch is removed on load")
eq(#alreadySlipped.txns, 8, "the timed stretch and the unrelated deposits stay")
eq(alreadySlipped.txns[4].who, "Sol", "the timed Sol line is the one kept")
eq(alreadySlipped.txns[4].day, d18, "Sol stays on the day the clock time gave")
local slippedGold = Ledger.Rebuild(alreadySlipped)
eq(slippedGold.goldIn, 5000 + 4000 + 50000 + 350000 + 50000 + 2000 + 50000, "Sol is counted once")
eq(slippedGold.tabCost, 1000000, "the tab buy is counted once")

local loneNext = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(loneNext, "money", {
	line("Ada", "deposit", d18, { copper = 100, precision = "hour", hour = 9 }),
	line("Sol", "deposit", d18, { copper = 350000, precision = "hour", hour = 21 }),
	line("Bob", "withdraw", d18, { copper = 50, precision = "hour", hour = 22 }),
})
added, gap = Ledger.MergeStream(loneNext, "money", {
	line("Cara", "deposit", d19, { copper = 350000, precision = "day" }),
	line("Sol", "deposit", d20, { copper = 350000, precision = "day" }),
})
eq(added, 2, "a deposit with different neighbors is kept")
eq(#loneNext.txns, 5, "the timed Sol line is not a match for a different stretch")

-- Pia deposited 25s once. A later scan crossed midnight and stored 00:00 as well.
local pia = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(pia, "money", {
	line("Tess", "deposit", d19, { copper = 50000, precision = "hour", hour = 17 }),
	line("Pia", "deposit", d19, { copper = 2500, precision = "hour", hour = 23 }),
	line("Uma", "deposit", d20, { copper = 200, precision = "hour", hour = 0 }),
	line("Nia", "deposit", d20, { copper = 10000, precision = "hour", hour = 3 }),
	line("Pia", "deposit", d20, { copper = 2500, precision = "hour", hour = 0 }),
})
eq(#pia.txns, 5, "a first read keeps the extra tail it was given")
added, gap = Ledger.MergeStream(pia, "money", {
	line("Tess", "deposit", d19, { copper = 50000, precision = "hour", hour = 17 }),
	line("Pia", "deposit", d20, { copper = 2500, precision = "hour", hour = 0 }),
	line("Uma", "deposit", d20, { copper = 200, precision = "hour", hour = 0 }),
	line("Nia", "deposit", d20, { copper = 10000, precision = "hour", hour = 3 }),
	line("Vesper", "deposit", d20, { copper = 2500, precision = "hour", hour = 1 }),
})
eq(added, 1, "the new deposit after Pia is kept")
eq(gap, false, "Pia's stretch still overlaps")
local piaCount = 0
for i = 1, #pia.txns do
	if pia.txns[i].who == "Pia" then
		piaCount = piaCount + 1
		eq(pia.txns[i].hour, 23, "Pia keeps the first clock time")
		eq(pia.txns[i].day, d19, "Pia stays on the first day")
	end
end
eq(piaCount, 1, "Pia's midnight copy is one deposit")
eq(pia.txns[#pia.txns].who, "Vesper", "the newest deposit is appended")

-- The extra copy was saved, then a later scan stored the deposit after it.
-- The next read of the live log has to drop the copy that sits in between.
local piaBetween = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(piaBetween, "money", {
	line("Tess", "deposit", d19, { copper = 50000, precision = "hour", hour = 17 }),
	line("Pia", "deposit", d19, { copper = 2500, precision = "hour", hour = 23 }),
	line("Uma", "deposit", d20, { copper = 200, precision = "hour", hour = 0 }),
	line("Nia", "deposit", d20, { copper = 10000, precision = "hour", hour = 3 }),
	line("Pia", "deposit", d20, { copper = 2500, precision = "hour", hour = 0 }),
	line("Vesper", "deposit", d20, { copper = 2500, precision = "hour", hour = 9 }),
})
eq(#piaBetween.txns, 6, "the extra copy is already between two saved lines")
added, gap = Ledger.MergeStream(piaBetween, "money", {
	line("Tess", "deposit", d19, { copper = 50000, precision = "hour", hour = 17 }),
	line("Pia", "deposit", d20, { copper = 2500, precision = "hour", hour = 0 }),
	line("Uma", "deposit", d20, { copper = 200, precision = "hour", hour = 0 }),
	line("Nia", "deposit", d20, { copper = 10000, precision = "hour", hour = 3 }),
	line("Vesper", "deposit", d20, { copper = 2500, precision = "hour", hour = 9 }),
})
eq(added, 0, "the live log adds nothing once the copy is dropped")
eq(gap, false, "the live log still overlaps")
local betweenCount = 0
for i = 1, #piaBetween.txns do
	if piaBetween.txns[i].who == "Pia" then
		betweenCount = betweenCount + 1
		eq(piaBetween.txns[i].hour, 23, "the first Pia clock stays")
		eq(piaBetween.txns[i].day, d19, "the first Pia day stays")
	end
end
eq(betweenCount, 1, "the copy between Nia and Vesper is removed")
eq(piaBetween.txns[#piaBetween.txns].who, "Vesper", "Vesper stays the newest line")

local twoPias = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(twoPias, "money", {
	line("Ada", "deposit", d19, { copper = 100, precision = "hour", hour = 10 }),
	line("Pia", "deposit", d19, { copper = 2500, precision = "hour", hour = 23 }),
	line("Bob", "withdraw", d19, { copper = 50, precision = "hour", hour = 22 }),
	line("Pia", "deposit", d20, { copper = 2500, precision = "hour", hour = 0 }),
	line("Cara", "deposit", d20, { copper = 80, precision = "hour", hour = 2 }),
})
added = Ledger.MergeStream(twoPias, "money", {
	line("Ada", "deposit", d19, { copper = 100, precision = "hour", hour = 10 }),
	line("Pia", "deposit", d19, { copper = 2500, precision = "hour", hour = 23 }),
	line("Bob", "withdraw", d19, { copper = 50, precision = "hour", hour = 22 }),
	line("Pia", "deposit", d20, { copper = 2500, precision = "hour", hour = 0 }),
	line("Cara", "deposit", d20, { copper = 80, precision = "hour", hour = 2 }),
})
eq(added, 0, "two real Pia deposits are not a time window")
eq(#twoPias.txns, 5, "different neighbors keep both clock times")

local history = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(history, "money", {
	line("Old", "deposit", d18, { copper = 900, precision = "hour", hour = 8 }),
	line("Tess", "deposit", d19, { copper = 50000, precision = "hour", hour = 17 }),
	line("Pia", "deposit", d19, { copper = 2500, precision = "hour", hour = 23 }),
	line("Uma", "deposit", d20, { copper = 200, precision = "hour", hour = 0 }),
})
added = Ledger.MergeStream(history, "money", {
	line("Old", "deposit", d19, { copper = 900, precision = "day" }),
	line("Tess", "deposit", d19, { copper = 50000, precision = "hour", hour = 17 }),
	line("Pia", "deposit", d20, { copper = 2500, precision = "hour", hour = 0 }),
	line("Uma", "deposit", d20, { copper = 200, precision = "hour", hour = 0 }),
	line("Vesper", "deposit", d20, { copper = 2500, precision = "hour", hour = 1 }),
})
eq(added, 1, "the cut-off re-read is not a new line")
eq(history.txns[1].who, "Old", "scrolled-off history stays")
eq(history.txns[1].hour, 8, "the old line keeps its clock")
local oldCount = 0
for i = 1, #history.txns do
	if history.txns[i].who == "Old" then
		oldCount = oldCount + 1
	end
end
eq(oldCount, 1, "the cut-off line is not stored twice")

local items = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(items, "tab:1", {
	line("Ada", "deposit", d19, { itemID = 4306, count = 5, tab = 1, precision = "hour", hour = 6 }),
	line("Pia", "deposit", d19, { itemID = 4633, count = 1, tab = 1, precision = "hour", hour = 0 }),
	line("Bob", "withdraw", d19, { itemID = 4306, count = 1, tab = 1, precision = "hour", hour = 8 }),
})
added = Ledger.MergeStream(items, "tab:1", {
	line("Ada", "deposit", d19, { itemID = 4306, count = 5, tab = 1, precision = "hour", hour = 6 }),
	line("Pia", "deposit", d20, { itemID = 4633, count = 1, tab = 1, precision = "hour", hour = 1 }),
	line("Bob", "withdraw", d19, { itemID = 4306, count = 1, tab = 1, precision = "hour", hour = 8 }),
	line("Cara", "deposit", d20, { itemID = 2589, count = 1, tab = 1, precision = "hour", hour = 4 }),
})
eq(added, 1, "an item line uses the neighbors in its own tab")
eq(#items.txns, 4, "the shifted item line is not a second deposit")
eq(items.txns[2].hour, 0, "the item line keeps the first hour")
eq(items.txns[2].itemID, 4633, "the item stays the lockbox")

local doubled = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(doubled, "money", {
	line("Mira", "withdraw", d7, { copper = 95000 }),
	line("Mira", "withdraw", d7, { copper = 95000 }),
	line("Mira", "deposit", d7, { copper = 10000 }),
})
eq(#doubled.txns, 3, "one read keeps two identical withdrawals")
local removed = Ledger.CollapseDuplicates(doubled)
eq(removed, 1, "collapse drops the copied withdrawal")
eq(#doubled.txns, 2, "the deposit stays beside one withdrawal")
eq(doubled.txns[2].copper, 10000, "collapse keeps the other amount")

local clockCopy = Ledger.NewGuild("OLYMPUS", "Realm")
clockCopy.txns = {
	{ id = 1, ord = 1, stream = "money", action = "deposit", who = "Mira", day = d7, precision = "day", copper = 50000 },
	{ id = 2, ord = 2, stream = "money", action = "deposit", who = "Mira", day = d7, precision = "hour", hour = 21, copper = 50000 },
	{ id = 3, ord = 3, stream = "money", action = "withdraw", who = "Mira", day = d7, precision = "day", copper = 2500 },
}
removed = Ledger.CollapseDuplicates(clockCopy)
eq(removed, 1, "collapse drops the date-only copy")
eq(#clockCopy.txns, 2, "the timed deposit and the withdrawal stay")
eq(clockCopy.txns[1].hour, 21, "collapse keeps the clock time")

local function countAction(guild, action)
	local count = 0
	for i = 1, #guild.txns do
		if guild.txns[i].action == action then
			count = count + 1
		end
	end
	return count
end

local copy = Ledger.NewGuild("OLYMPUS", "Realm")
local added, seen, err = Ledger.ImportTransactions(copy, Ledger.ExportTransactions(books))
eq(err, nil, "round trip has no error")
eq(added, 8, "round trip adds every line")
eq(seen, 8, "round trip sees every line")
local imported = Ledger.Rebuild(copy)
eq(imported.goldIn, 10000, "import does not count the summary")
eq(imported.net, 6000, "imported net matches")
eq(imported.itemIn, 20, "imported items in")
eq(imported.itemOut, 5, "imported items out")
eq(countAction(copy, "depositSummary"), 1, "one summary line")
local summaryFlag = false
for i = 1, #copy.txns do
	if copy.txns[i].action == "depositSummary" then
		summaryFlag = copy.txns[i].summary == true
	end
end
eq(summaryFlag, true, "summary flag is restored")

added, seen = Ledger.ImportTransactions(copy, Ledger.ExportTransactions(books))
eq(added, 0, "a second import adds nothing")
eq(seen, 8, "a second import still sees every line")
eq(#copy.txns, 8, "a second import does not duplicate")
eq(Ledger.Rebuild(copy).goldIn, 10000, "a second import does not double gold")

local host = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(host, "money", {
	line("Ada", "deposit", day, { copper = 10000 }),
})
added = Ledger.ImportTransactions(host, Ledger.ExportTransactions(books))
eq(added, 7, "overlap imports only the missing lines")
eq(Ledger.Rebuild(host).goldIn, 10000, "the overlapping deposit is not doubled")
eq(#host.gaps, 0, "an overlapping import is not a gap")

local quotedCopy = Ledger.NewGuild("OLYMPUS", "Realm")
added = Ledger.ImportTransactions(quotedCopy, Ledger.ExportTransactions(quoted))
eq(added, 1, "quoted export imports")
eq(quotedCopy.txns[1].who, 'Ada "Ace"', "quoted character survives")
eq(quotedCopy.txns[1].itemName, "Linen, Cloth", "quoted item name survives")

local commaGuild = Ledger.NewGuild("OLYMPUS, Inc", "Area 52")
Ledger.MergeStream(commaGuild, "money", {
	line("Ada", "deposit", day, { copper = 50, precision = "hour", hour = 15 }),
})
local commaCopy = Ledger.NewGuild("OLYMPUS, Inc", "Area 52")
added = Ledger.ImportTransactions(commaCopy, Ledger.ExportTransactions(commaGuild))
eq(added, 1, "a guild name with a comma imports")
eq(commaCopy.txns[1].hour, 15, "hour survives import")
eq(commaCopy.txns[1].precision, "hour", "hour precision survives import")

local otherGuild = Ledger.NewGuild("Other", "Realm")
local before = #otherGuild.txns
added, seen, err = Ledger.ImportTransactions(otherGuild, Ledger.ExportTransactions(books))
eq(added, nil, "a different guild is refused")
eq(#otherGuild.txns, before, "a refused import writes nothing")
eq(type(string.find(err, "OLYMPUS", 1, true)), "number", "the error names the export guild")

before = #books.txns
added, seen, err = Ledger.ImportTransactions(books, Ledger.ExportCharacters(Ledger.Rebuild(books)))
eq(added, nil, "character totals are refused")
eq(#books.txns, before, "character totals write nothing")

local function joinRow(fields)
	return table.concat(fields, ",")
end

local sample = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(sample, "money", {
	line("Ada", "deposit", day, { copper = 10 }),
})
local sampleCsv = Ledger.ExportTransactions(sample)
local goodLine = string.match(sampleCsv, "\n([^\n]+)$")
local badLine = string.gsub(goodLine, "^%d%d%d%d%-%d%d%-%d%d", "2026-02-31", 1)
local brokenGuild = Ledger.NewGuild("OLYMPUS", "Realm")
added, seen, err = Ledger.ImportTransactions(brokenGuild, sampleCsv .. "\n" .. badLine)
eq(added, nil, "a bad row imports nothing")
eq(#brokenGuild.txns, 0, "a bad row does not keep earlier lines")
eq(type(string.find(err, "Line 3", 1, true)), "number", "the error names the bad line")

local function txnHeader()
	return joinRow({
		"day", "hour", "precision", "character", "action",
		"item_id", "item_name", "count", "copper", "tab",
		"destination_tab", "stream",
	})
end

local blankChar = Ledger.NewGuild("OLYMPUS", "Realm")
added, seen, err = Ledger.ImportTransactions(blankChar, txnHeader() .. "\n" .. joinRow({
	"2026-10-01", "", "day", "", "deposit",
	"", "", "", "10", "", "", "money",
}) .. "\n" .. joinRow({
	"2026-10-01", "", "day", "Ada", "deposit",
	"", "", "", "20", "", "", "money",
}))
eq(added, nil, "a blank character is refused")
eq(#blankChar.txns, 0, "a blank character writes nothing")
eq(type(string.find(err, "needs a character", 1, true)), "number", "the error asks for a character")

local spaceChar = Ledger.NewGuild("OLYMPUS", "Realm")
added, seen, err = Ledger.ImportTransactions(spaceChar, txnHeader() .. "\n" .. joinRow({
	"2026-10-01", "", "day", "   ", "deposit",
	"", "", "", "10", "", "", "money",
}))
eq(added, nil, "spaces are not a character")
eq(#spaceChar.txns, 0, "a blank character name writes nothing")

local namedUnknown = Ledger.NewGuild("OLYMPUS", "Realm")
added = Ledger.ImportTransactions(namedUnknown, txnHeader() .. "\n" .. joinRow({
	"2026-10-01", "", "day", "Unknown", "deposit",
	"", "", "", "10", "", "", "money",
}))
eq(added, 1, "a character named Unknown can be imported")
eq(namedUnknown.txns[1].who, "Unknown", "that name is kept as written")

local ghost = Ledger.NewGuild("OLYMPUS", "Realm")
ghost.txns = {
	{ id = 1, ord = 1, stream = "money", action = "deposit", who = "Ada", day = day, precision = "day", copper = 100 },
	{ id = 2, ord = 2, stream = "money", action = "deposit", who = nil, day = day, precision = "day", copper = 50 },
	{ id = 3, ord = 3, stream = "money", action = "deposit", who = "Unknown", day = day, precision = "day", copper = 25 },
	{ id = 4, ord = 4, stream = "money", action = "deposit", who = "", day = day, precision = "day", copper = 5 },
	{ id = 5, ord = 5, stream = "tab:1", action = "withdraw", who = "Unknown", day = day, precision = "day", itemID = 1, itemName = "Linen Cloth", count = 2 },
}
local ghostCache = Ledger.Rebuild(ghost)
eq(ghostCache.characters.Ada.goldIn, 100, "a named deposit stays on that character")
eq(ghostCache.characters.Unknown.goldIn, 25, "the placeholder still totals until it is removed")
eq(ghostCache.goldIn, 180, "a missing name does not drop the guild total")
eq(ghostCache.characters[""], nil, "a blank name is not a character")
removed = Ledger.DropNameless(ghost)
eq(removed, 4, "blank names and the placeholder are removed")
eq(#ghost.txns, 1, "the named line stays")
eq(ghost.txns[1].who, "Ada", "Ada is the line that stays")
eq(Ledger.Rebuild(ghost).goldIn, 100, "the removed lines leave the total")
eq(Ledger.Rebuild(ghost).characters.Unknown, nil, "Unknown is gone from the totals")
eq(Ledger.Rebuild(ghost).itemOut, 0, "the placeholder item line is gone")

local crlfGuild = Ledger.NewGuild("OLYMPUS", "Realm")
added = Ledger.ImportTransactions(crlfGuild, string.gsub(sampleCsv, "\n", "\r\n"))
eq(added, 1, "Windows line endings import")
eq(crlfGuild.txns[1].copper, 10, "Windows copper is kept")

local old = joinRow({
	"day", "hour", "precision", "character", "action",
	"item_id", "item_name", "count", "count_signed",
	"copper", "copper_signed", "tab", "destination_tab", "stream",
}) .. "\n" .. joinRow({
	"2026-10-01", "", "day", "Ada", "deposit",
	"", "", "1", "",
	"40", "", "", "", "money",
})
local legacy = Ledger.NewGuild("OLYMPUS", "Realm")
added = Ledger.ImportTransactions(legacy, old)
eq(added, 1, "an older export without a guild name imports")
eq(legacy.txns[1].copper, 40, "legacy copper is kept")
eq(legacy.txns[1].count, 1, "legacy count is kept")

local twinsCopy = Ledger.NewGuild("OLYMPUS", "Realm")
added = Ledger.ImportTransactions(twinsCopy, Ledger.ExportTransactions(twins))
eq(added, 4, "identical twins both import")
eq(names(twinsCopy, "tab:1"), "A,A,B,C", "twin order survives import")
added = Ledger.ImportTransactions(twinsCopy, Ledger.ExportTransactions(twins))
eq(added, 0, "importing twins again adds nothing")
eq(#twinsCopy.txns, 4, "twins stay two deposits")

local tabBuy = Ledger.NewGuild("OLYMPUS", "Realm")
added = Ledger.MergeStream(tabBuy, "money", {
	line("Ada", "withdrawForTab", day, { copper = 10000000 }),
	line("Ada", "buyTab", day, { copper = 10000000 }),
	line("Ada", "withdraw", day, { copper = 10000000 }),
})
eq(added, 2, "the withdrawal and a real withdrawal are both kept")
eq(#tabBuy.txns, 2, "the purchase notice is not stored")
eq(tabBuy.txns[1].action, "withdrawForTab", "the withdrawal for the tab is kept")
local tabCache = Ledger.Rebuild(tabBuy)
eq(tabCache.tabCost, 10000000, "the tab is counted once")
eq(tabCache.goldOut, 20000000, "the real withdrawal is still out")

added = Ledger.MergeStream(tabBuy, "money", {
	line("Ada", "withdrawForTab", day, { copper = 10000000 }),
	line("Ada", "buyTab", day, { copper = 10000000 }),
})
eq(added, 0, "a later scan does not store the purchase notice")
eq(#tabBuy.txns, 2, "the tab withdrawal stays one line")

local secondTab = Ledger.NewGuild("OLYMPUS", "Realm")
added = Ledger.MergeStream(secondTab, "money", {
	line("Ada", "buyTab", day, { copper = 10000000 }),
	line("Ada", "buyTab", day, { copper = 25000000 }),
})
eq(added, 2, "two tab prices are two withdrawals")
eq(secondTab.txns[1].action, "withdrawForTab", "the first notice is kept as a withdrawal")
eq(secondTab.txns[2].action, "withdrawForTab", "the next tab price is kept")
eq(Ledger.Rebuild(secondTab).tabCost, 35000000, "both tab prices count")

local savedPair = Ledger.NewGuild("OLYMPUS", "Realm")
savedPair.txns = {
	{ id = 1, ord = 1, stream = "money", action = "withdrawForTab", who = "Ada", day = day, precision = "day", copper = 10000000 },
	{ id = 2, ord = 2, stream = "money", action = "buyTab", who = "Ada", day = day, precision = "day", copper = 10000000 },
	{ id = 3, ord = 3, stream = "money", action = "withdraw", who = "Ada", day = day, precision = "day", copper = 500 },
}
local paired = Ledger.CollapseTabPairs(savedPair)
eq(paired, 1, "a saved purchase notice is dropped")
eq(#savedPair.txns, 2, "the withdrawal beside the tab stays")
eq(savedPair.txns[1].action, "withdrawForTab", "the saved withdrawal is kept")
eq(Ledger.Rebuild(savedPair).tabCost, 10000000, "a repaired ledger counts the tab once")
eq(Ledger.Rebuild(savedPair).goldOut, 10000500, "the notice is not a second 100 gold")

local onlyNotice = Ledger.NewGuild("OLYMPUS", "Realm")
onlyNotice.txns = {
	{ id = 1, ord = 1, stream = "money", action = "buyTab", who = "Ada", day = day, precision = "day", copper = 25000000 },
}
eq(Ledger.CollapseTabPairs(onlyNotice), 0, "a lone notice is not a second line")
eq(#onlyNotice.txns, 1, "a lone notice stays one line")
eq(onlyNotice.txns[1].action, "withdrawForTab", "a lone notice is kept as the withdrawal")
eq(Ledger.Rebuild(onlyNotice).goldOut, 25000000, "a lone notice still counts once")

local timedNotices = Ledger.NewGuild("OLYMPUS", "Realm")
timedNotices.txns = {
	{ id = 1, ord = 1, stream = "money", action = "buyTab", who = "Ada", day = d19, precision = "day", copper = 10000000 },
	{ id = 2, ord = 2, stream = "money", action = "buyTab", who = "Ada", day = d19, precision = "hour", hour = 21, copper = 10000000 },
}
eq(Ledger.CollapseTabPairs(timedNotices), 1, "the date-only tab notice is the extra line")
eq(#timedNotices.txns, 1, "one tab purchase remains")
eq(timedNotices.txns[1].action, "withdrawForTab", "the kept tab line is the withdrawal")
eq(timedNotices.txns[1].hour, 21, "the clock time is kept when the notice came first")

local timedFirst = Ledger.NewGuild("OLYMPUS", "Realm")
timedFirst.txns = {
	{ id = 1, ord = 1, stream = "money", action = "withdrawForTab", who = "Ada", day = d19, precision = "day", copper = 10000000 },
	{ id = 2, ord = 2, stream = "money", action = "buyTab", who = "Ada", day = d19, precision = "hour", hour = 21, copper = 10000000 },
}
eq(Ledger.CollapseTabPairs(timedFirst), 1, "a timed notice upgrades the saved withdrawal")
eq(#timedFirst.txns, 1, "the upgraded withdrawal is the only tab line")
eq(timedFirst.txns[1].hour, 21, "the withdrawal takes the clock time")
eq(timedFirst.txns[1].precision, "hour", "the withdrawal is timed after the upgrade")

local keeper = Ledger.NewGuild("Guild", "Realm")
Ledger.MergeStream(keeper, "money", {
	line("Ada", "deposit", day, { copper = 100 }),
	line("Bea", "withdraw", day, { copper = 50 }),
})
Ledger.MergeStream(keeper, "tab:1", {
	line("Ada", "deposit", day, { itemID = 1, itemName = "Linen", count = 2, tab = 1 }),
})
keeper.tabNames[1] = "Tab 1"
keeper.lastScan = { year = 2026, month = 11, day = 20, hour = 12, min = 29 }
local other = Ledger.NewGuild("Guild", "")
Ledger.MergeStream(other, "money", {
	line("Bea", "withdraw", day, { copper = 50 }),
	line("Cal", "deposit", day, { copper = 25 }),
})
other.tabNames[1] = "Herbs"
other.tabNames[2] = "Bank"
other.lastScan = { year = 2026, month = 11, day = 20, hour = 12, min = 48 }
local merged, seen = Ledger.MergeGuild(keeper, other)
eq(merged, 1, "merge adds only the new line")
eq(seen, 2, "merge sees the other ledger")
eq(names(keeper, "money"), "Ada,Bea,Cal", "merged money stays in order")
eq(names(keeper, "tab:1"), "Ada", "the kept item line stays one")
eq(keeper.name, "Guild", "merge keeps the ledger name")
eq(keeper.realm, "Realm", "merge keeps the ledger realm")
eq(keeper.tabNames[1], "Tab 1", "an existing tab name stays")
eq(keeper.tabNames[2], "Bank", "a missing tab name is filled")
eq(keeper.lastScan.min, 48, "the later scan time is kept")
eq(keeper.lastScan == other.lastScan, false, "the scan time is copied")
eq(names(other, "money"), "Bea,Cal", "the other ledger is left intact")
eq(Ledger.Rebuild(keeper).goldIn, 125, "merged gold counts once")
local snapshot = Ledger.CopyGuild(keeper, "backup-2026-11-20")
eq(snapshot.realm, "backup-2026-11-20", "a backup uses the realm it was given")
eq(snapshot.name, keeper.name, "a backup keeps the guild name")
eq(names(snapshot, "money"), "Ada,Bea,Cal", "a backup has the same lines")
eq(snapshot.txns[1] == keeper.txns[1], false, "a backup does not share the original lines")
snapshot.txns[1].copper = 1
eq(keeper.txns[1].copper, 100, "editing a backup leaves the original")
merged, seen = Ledger.MergeGuild(keeper, keeper)
eq(merged, nil, "a ledger is not merged into itself")

local nov9 = Time.Pack(2026, 11, 9)
local nov15 = Time.Pack(2026, 11, 15)
local nov17 = Time.Pack(2026, 11, 17)
local nov18 = Time.Pack(2026, 11, 18)
local nov19 = Time.Pack(2026, 11, 19)
local nov20 = Time.Pack(2026, 11, 20)
local recent = Ledger.NewGuild("Guild", "")
Ledger.MergeStream(recent, "money", {
	line("Mira", "deposit", nov17, { copper = 10000, hour = 13, precision = "hour" }),
	line("Nia", "deposit", nov20, { copper = 10000, hour = 2, precision = "hour" }),
})
Ledger.MergeStream(recent, "tab:1", {
	line("Opal", "deposit", nov19, { itemID = 1, itemName = "Page 10", count = 1, tab = 1, hour = 21, precision = "hour" }),
})
local olderLedger = Ledger.NewGuild("Guild", "Realm")
Ledger.MergeStream(olderLedger, "money", {
	line("Mira", "deposit", nov9, { copper = 10000, hour = 12, precision = "hour" }),
	line("Mira", "deposit", nov17, { copper = 10000, hour = 13, precision = "hour" }),
	line("Nia", "deposit", nov20, { copper = 10000, hour = 3, precision = "hour" }),
})
Ledger.MergeStream(olderLedger, "tab:1", {
	line("Opal", "deposit", nov18, { itemID = 2, itemName = "Page 27", count = 2, tab = 1, hour = 22, precision = "hour" }),
	line("Opal", "deposit", nov18, { itemID = 1, itemName = "Page 10", count = 1, tab = 1, hour = 22, precision = "hour" }),
	line("Opal", "deposit", nov19, { itemID = 1, itemName = "Page 10", count = 1, tab = 1, hour = 21, precision = "hour" }),
})
merged = Ledger.MergeGuild(recent, olderLedger)
eq(merged, 3, "an older amount on another day is imported")
local miraDays = {}
local nia = 0
local page10 = 0
local page27 = 0
for i = 1, #recent.txns do
	local row = recent.txns[i]
	if row.who == "Mira" and row.copper == 10000 then
		miraDays[#miraDays + 1] = row.day
	elseif row.who == "Nia" then
		nia = nia + 1
	elseif row.itemName == "Page 10" then
		page10 = page10 + 1
	elseif row.itemName == "Page 27" then
		page27 = page27 + 1
	end
end
eq(#miraDays, 2, "both Mira deposits stay")
eq(miraDays[1] == nov9 or miraDays[2] == nov9, true, "the earlier Mira deposit is kept")
eq(nia, 1, "the same deposit an hour later is not a second line")
eq(page10, 2, "page 10 on the next day is a second deposit")
eq(page27, 1, "the rest of the earlier trip is kept")
local scanGuild = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(scanGuild, "money", {
	line("Mira", "deposit", nov17, { copper = 10000, hour = 13, precision = "hour" }),
})
added = Ledger.MergeStream(scanGuild, "money", {
	line("Mira", "deposit", nov9, { copper = 10000, hour = 12, precision = "hour" }),
	line("Mira", "deposit", nov17, { copper = 10000, hour = 13, precision = "hour" }),
})
eq(added, 1, "a scan keeps an older deposit of the same amount")
eq(#scanGuild.txns, 2, "the older day stays beside the later one")
eq(scanGuild.txns[1].day, nov9, "the older deposit keeps its day")

local rescanned = Ledger.NewGuild("OLYMPUS", "Realm")
rescanned.txns = {
	{ id = 1, ord = 1, stream = "money", action = "deposit", who = "Ada", day = nov19, precision = "hour", hour = 8, copper = 100 },
	{ id = 2, ord = 2, stream = "money", action = "deposit", who = "Pia", day = nov19, precision = "hour", hour = 23, copper = 2500 },
	{ id = 3, ord = 3, stream = "money", action = "deposit", who = "Quin", day = nov19, precision = "day", copper = 50000 },
	{ id = 4, ord = 4, stream = "money", action = "deposit", who = "Bob", day = nov20, precision = "hour", hour = 9, copper = 200 },
	{ id = 5, ord = 5, stream = "tab:1", action = "deposit", who = "Opal", day = nov19, precision = "hour", hour = 21, itemID = 1, itemName = "Page 10", count = 1, tab = 1 },
	{ id = 6, ord = 6, stream = "money", action = "deposit", who = "Pia", day = nov15, precision = "day", copper = 2500 },
	{ id = 7, ord = 7, stream = "money", action = "deposit", who = "Quin", day = nov18, precision = "hour", hour = 23, copper = 50000 },
	{ id = 8, ord = 8, stream = "tab:1", action = "deposit", who = "Opal", day = nov18, precision = "hour", hour = 22, itemID = 1, itemName = "Page 10", count = 1, tab = 1 },
}
added = Ledger.MergeStream(rescanned, "money", {
	line("Ada", "deposit", nov19, { copper = 100, hour = 8, precision = "hour" }),
	line("Pia", "deposit", nov19, { copper = 2500, hour = 23, precision = "hour" }),
	line("Quin", "deposit", nov19, { copper = 50000, precision = "day" }),
	line("Bob", "deposit", nov20, { copper = 200, hour = 9, precision = "hour" }),
	line("Ren", "deposit", nov20, { copper = 300, hour = 15, precision = "hour" }),
})
added = added + Ledger.MergeStream(rescanned, "tab:1", {
	line("Opal", "deposit", nov19, { itemID = 1, itemName = "Page 10", count = 1, tab = 1, hour = 21, precision = "hour" }),
	line("Ren", "deposit", nov20, { itemID = 2, itemName = "Pattern", count = 1, tab = 1, hour = 15, precision = "hour" }),
})
local piaDays = 0
local quinClock = 0
local quinDate = 0
local opalDays = 0
local ren = 0
for i = 1, #rescanned.txns do
	local row = rescanned.txns[i]
	if row.who == "Pia" and row.copper == 2500 then
		piaDays = piaDays + 1
	elseif row.who == "Quin" and row.hour == 23 then
		quinClock = quinClock + 1
		eq(row.day, nov18, "Quin keeps the day that had a clock")
	elseif row.who == "Quin" then
		quinDate = quinDate + 1
	elseif row.who == "Opal" then
		opalDays = opalDays + 1
	elseif row.who == "Ren" then
		ren = ren + 1
	end
end
eq(added, 2, "the scan adds only the new lines")
eq(piaDays, 2, "Pia's older deposit stays beside the later one")
eq(quinClock, 1, "the timed Quin line stays")
eq(quinDate, 0, "the date-only Quin copy is dropped")
eq(opalDays, 2, "Opal's next-day trip stays")
eq(ren, 2, "a new money line and a new item line are kept")

CreateFrame = function()
	return {
		RegisterEvent = function() end,
		SetScript = function() end,
	}
end
SlashCmdList = {}
dofile(dir .. "../Core.lua")

eq(GBLF.FormatMoneyCompact(230000), "23g 00s 00c", "gold keeps silver and copper")
eq(GBLF.FormatMoneyCompact(1095500), "109g 55s 00c", "gold and silver keep the copper")
eq(GBLF.FormatMoneyCompact(96350), "9g 63s 50c", "copper stays beside the silver")
eq(GBLF.FormatMoneyCompact(15000), "1g 50s 00c", "silver is not the last coin")
eq(GBLF.FormatMoneyCompact(5000), "50s 00c", "silver without gold")
eq(GBLF.FormatMoneyCompact(0), "0c", "zero copper")
eq(GBLF.FormatMoneyCompact(-15000), "-1g 50s 00c", "a debit keeps every coin")

GuildBankLedgerForeverDB = {
	version = 1,
	settings = {},
	guilds = {
		["OLYMPUS-Realm"] = {
			name = "OLYMPUS",
			realm = "Realm",
			txns = {
				{ id = 1, ord = 1, stream = "money", action = "deposit", who = "Ada", day = day, precision = "day", copper = 100 },
				{ id = 2, ord = 2, stream = "money", action = "deposit", who = "Unknown", day = day, precision = "day", copper = 50 },
				{ id = 3, ord = 3, stream = "money", action = "deposit", who = nil, day = day, precision = "day", copper = 7 },
			},
			gaps = {},
			tabNames = {},
			nextId = 4,
			nextOrd = 4,
		},
	},
}
GBLF.dbReady = false
GBLF.InitDB()
local cleaned = GuildBankLedgerForeverDB.guilds["OLYMPUS-Realm"]
eq(#cleaned.txns, 1, "login drops the nameless lines once")
eq(cleaned.txns[1].who, "Ada", "the named line stays at login")
eq(cleaned.requiredNames, true, "the cleanup is marked done")
eq(GBLF.CacheFor("OLYMPUS-Realm").goldIn, 100, "the dropped gold leaves the total")
cleaned.txns[#cleaned.txns + 1] = {
	id = 4, ord = 4, stream = "money", action = "deposit", who = "Unknown", day = day, precision = "day", copper = 5,
}
GBLF.dbReady = false
GBLF.InitDB()
eq(#cleaned.txns, 2, "a later character named Unknown is kept")
eq(cleaned.txns[2].who, "Unknown", "that later name stays")

local keptGuild = Ledger.NewGuild("Guild", "Realm")
Ledger.MergeStream(keptGuild, "money", {
	line("Ada", "deposit", day, { copper = 100 }),
	line("Bea", "withdraw", day, { copper = 50 }),
})
local blankRealm = Ledger.NewGuild("Guild", "")
Ledger.MergeStream(blankRealm, "money", {
	line("Bea", "withdraw", day, { copper = 50 }),
	line("Cal", "deposit", day, { copper = 25 }),
})
GuildBankLedgerForeverDB = {
	version = 1,
	settings = { viewKey = "Guild-" },
	guilds = {
		["Guild-"] = blankRealm,
		["Guild-Realm"] = keptGuild,
	},
}
GBLF.caches = {}
local folded, foldSeen = GBLF.MergeGuilds("Guild-Realm", "Guild-")
eq(folded, 1, "the blank-realm lines fold into the kept ledger")
eq(foldSeen, 2, "both lines of the other ledger are seen")
eq(GuildBankLedgerForeverDB.guilds["Guild-"], blankRealm, "both ledgers stay unless asked")
eq(GuildBankLedgerForeverDB.settings.viewKey, "Guild-", "keeping both leaves the window where it was")
eq(keptGuild.realm, "Realm", "the kept realm is not replaced")
eq(names(keptGuild, "money"), "Ada,Bea,Cal", "the kept ledger holds both histories")
local originalNow = GBLF.Now
GBLF.Now = function()
	return { year = 2026, month = 11, day = 20, hour = 12, min = 0, sec = 9 }
end
local backupKey = GBLF.BackupGuild("Guild-Realm")
eq(backupKey, "Guild-backup-2026-11-20-12:00:09", "the backup key uses the date and time")
local backup = GuildBankLedgerForeverDB.guilds[backupKey]
eq(backup.realm, "backup-2026-11-20-12:00:09", "the backup realm is the date and time")
eq(backup.name, "Guild", "the backup keeps the guild name")
eq(names(backup, "money"), "Ada,Bea,Cal", "the backup holds the ledger")
eq(GuildBankLedgerForeverDB.settings.viewKey, "Guild-", "a backup does not change the window")
GBLF.Now = function()
	return { year = 2026, month = 11, day = 20, hour = 12, min = 0, sec = 10 }
end
eq(GBLF.BackupGuild("Guild-Realm"), "Guild-backup-2026-11-20-12:00:10", "the next second is another backup")
GBLF.Now = function()
	return { year = 2026, month = 11, day = 20, hour = 12, min = 0, sec = 10 }
end
eq(GBLF.BackupGuild("Guild-Realm"), "Guild-backup-2026-11-20-12:00:10-2", "the same second gets a number")
GBLF.Now = originalNow
local removed = GBLF.MergeGuilds("Guild-Realm", "Guild-", true)
eq(removed, 0, "merging again adds nothing new")
eq(GuildBankLedgerForeverDB.guilds["Guild-"], nil, "the checkbox removes the other ledger")
eq(GuildBankLedgerForeverDB.settings.viewKey, "Guild-Realm", "deleting the viewed ledger leaves the one that was kept")

local warned = GBLF.BlankRealmWarning({
	a = { name = "Guild", realm = "" },
	b = { name = "Guild", realm = "Realm" },
	c = { name = "Other", realm = "" },
})
eq(#warned, 1, "a blank realm warns when another realm is saved")
eq(warned[1], "Guild", "the warning names that guild")
local backupOnly = GBLF.BlankRealmWarning({
	a = { name = "Guild", realm = "" },
	b = { name = "Guild", realm = "backup-2026-11-20-12:00:09" },
})
eq(#backupOnly, 0, "a backup is not the other ledger")
eq(#GBLF.BlankRealmWarning({ a = { name = "Guild", realm = "Realm" } }), 0, "a filled realm does not warn")
eq(#GBLF.BlankRealmWarning(nil), 0, "no guilds does not warn")

if failed > 0 then
	io.stderr:write(string.format("%d failed\n", failed))
	os.exit(1)
end
print("ok")
