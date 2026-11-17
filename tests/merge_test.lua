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

if failed > 0 then
	io.stderr:write(string.format("%d failed\n", failed))
	os.exit(1)
end
print("ok")
