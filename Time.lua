-- Day math for guild bank lines.
-- The log reports an age, not a timestamp, and usually only the day is filled in.
-- Hour is recorded only when the log did not send a year, month, or day.

GBLF = GBLF or {}
GBLF.Time = {}

local Time = GBLF.Time

local MONTHS = {
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

-- Howard Hinnant's civil date conversion. The serial is days since 1970-01-01.
-- Only modern positive years are used, where floor division matches truncation.
function Time.CivilToSerial(year, month, day)
	local y = year
	local m = month
	if m <= 2 then
		y = y - 1
	end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp
	if m > 2 then
		mp = m - 3
	else
		mp = m + 9
	end
	local doy = math.floor((153 * mp + 2) / 5) + day - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

function Time.SerialToCivil(serial)
	local z = serial + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m
	if mp < 10 then
		m = mp + 3
	else
		m = mp - 9
	end
	if m <= 2 then
		y = y + 1
	end
	return y, m, d
end

function Time.AddDays(year, month, day, delta)
	return Time.SerialToCivil(Time.CivilToSerial(year, month, day) + delta)
end

function Time.Pack(year, month, day)
	return year * 10000 + month * 100 + day
end

function Time.Unpack(packed)
	local year = math.floor(packed / 10000)
	local month = math.floor(packed / 100) % 100
	local day = packed % 100
	return year, month, day
end

function Time.DayDistance(a, b)
	local ay, am, ad = Time.Unpack(a)
	local by, bm, bd = Time.Unpack(b)
	local left = Time.CivilToSerial(ay, am, ad)
	local right = Time.CivilToSerial(by, bm, bd)
	if left > right then
		return left - right
	end
	return right - left
end

function Time.FormatDay(packed, hour, precision)
	local _, month, day = Time.Unpack(packed)
	local label = string.format("%s %d", MONTHS[month] or "?", day)
	if precision == "hour" and hour then
		return string.format("%s %02d:00", label, hour)
	end
	if precision == "month" or precision == "year" then
		return "≈ " .. label
	end
	return label
end

function Time.FormatDayLong(packed)
	local year, month, day = Time.Unpack(packed)
	return string.format("%s %d, %d", MONTHS[month] or "?", day, year)
end

function Time.IsoDay(packed)
	local year, month, day = Time.Unpack(packed)
	return string.format("%04d-%02d-%02d", year, month, day)
end

-- scan: { year, month, day, hour, min }
-- years/months/days/hours: age reported by the guild bank log.
-- The coarsest non-zero unit wins. A line that says "3 days ago" does not
-- get an hour, even if the hour field came back as 0 or as leftover noise.
function Time.FromAge(scan, years, months, days, hours)
	years = years or 0
	months = months or 0
	days = days or 0
	hours = hours or 0

	local precision
	local y, m, d
	local hour
	if years > 0 then
		precision = "year"
		y, m, d = Time.AddDays(scan.year, scan.month, scan.day, -years * 365)
	elseif months > 0 then
		precision = "month"
		y, m, d = Time.AddDays(scan.year, scan.month, scan.day, -months * 30)
	elseif days > 0 then
		precision = "day"
		y, m, d = Time.AddDays(scan.year, scan.month, scan.day, -days)
	else
		precision = "hour"
		local mins = (scan.hour or 0) * 60 + (scan.min or 0) - hours * 60
		local dayDelta = 0
		while mins < 0 do
			mins = mins + 1440
			dayDelta = dayDelta - 1
		end
		while mins >= 1440 do
			mins = mins - 1440
			dayDelta = dayDelta + 1
		end
		y, m, d = Time.AddDays(scan.year, scan.month, scan.day, dayDelta)
		hour = math.floor(mins / 60)
	end

	local ageRank
	if years > 0 then
		ageRank = 3000000000 + years
	elseif months > 0 then
		ageRank = 2000000000 + months
	elseif days > 0 then
		ageRank = 1000000000 + days
	else
		ageRank = hours
	end

	return {
		day = Time.Pack(y, m, d),
		hour = hour,
		precision = precision,
		ageRank = ageRank,
	}
end
