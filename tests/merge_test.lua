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
	line("Warpig", "deposit", d7, { copper = 200 }),
	line("Enlinks", "withdraw", d7, { copper = 95000 }),
	line("Holi", "deposit", d7, { copper = 500 }),
})
added, gap = Ledger.MergeStream(messy, "money", {
	line("Holi", "deposit", d7, { copper = 500 }),
	line("Enlinks", "withdraw", d7, { copper = 95000 }),
	line("Warpig", "deposit", d7, { copper = 200 }),
})
eq(added, 0, "reordered rescan adds nothing")
eq(gap, false, "reorder is not a gap")
eq(#messy.txns, 3, "reorder does not duplicate the withdrawal")

local d9 = Time.Pack(2026, 11, 9)
local agedLine = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(agedLine, "money", {
	line("Enlinks", "deposit", d9, { copper = 10000, precision = "hour", hour = 12 }),
})
added, gap = Ledger.MergeStream(agedLine, "money", {
	line("Enlinks", "deposit", d9, { copper = 10000, precision = "day" }),
})
eq(added, 0, "a day-old reread matches the pinned hour")
eq(#agedLine.txns, 1, "aging a line does not duplicate it")

local doubled = Ledger.NewGuild("OLYMPUS", "Realm")
Ledger.MergeStream(doubled, "money", {
	line("Enlinks", "withdraw", d7, { copper = 95000 }),
	line("Enlinks", "withdraw", d7, { copper = 95000 }),
	line("Enlinks", "deposit", d7, { copper = 10000 }),
})
eq(#doubled.txns, 3, "one read keeps two identical withdrawals")
local removed = Ledger.CollapseDuplicates(doubled)
eq(removed, 1, "collapse drops the copied withdrawal")
eq(#doubled.txns, 2, "the deposit stays beside one withdrawal")
eq(doubled.txns[2].copper, 10000, "collapse keeps the other amount")

if failed > 0 then
	io.stderr:write(string.format("%d failed\n", failed))
	os.exit(1)
end
print("ok")
