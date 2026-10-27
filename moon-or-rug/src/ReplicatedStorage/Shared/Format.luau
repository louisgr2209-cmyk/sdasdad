-- Format (ModuleScript) – ReplicatedStorage/Shared/Format
-- Zahlen lesbar machen: 12.5K, 1,234.50, 0.00225, +12.3%

local Format = {}

local SUFFIXES = {
	{ 1e12, "T" },
	{ 1e9, "B" },
	{ 1e6, "M" },
	{ 1e3, "K" },
}

local function trimZeros(text: string): string
	return (text:gsub("%.?0+$", ""))
end

local function withCommas(text: string): string
	local sign, int, rest = text:match("^([%-]?)(%d+)(.*)$")
	if not int then
		return text
	end
	int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	int = int:gsub("^,", "")
	return sign .. int .. rest
end

-- 950 -> "950", 12500 -> "12.5K", 3400000 -> "3.4M"
function Format.Short(n: number): string
	local a = math.abs(n)
	for _, entry in SUFFIXES do
		if a >= entry[1] then
			return trimZeros(string.format("%.2f", n / entry[1])) .. entry[2]
		end
	end
	return trimZeros(string.format("%.2f", n))
end

-- Cash: unter 100K mit Komma und 2 Nachkommastellen, darüber kurz
function Format.Cash(n: number): string
	if math.abs(n) >= 100_000 then
		return Format.Short(n)
	end
	return withCommas(string.format("%.2f", n))
end

-- Preise: immer ca. 3 wichtige Stellen, auch bei 0.000123
function Format.Price(p: number): string
	if p <= 0 then
		return "0"
	end
	local decimals = math.clamp(2 - math.floor(math.log10(p)), 2, 10)
	return string.format("%." .. decimals .. "f", p)
end

-- 0.123 -> "+12.3%"
function Format.Percent(x: number): string
	local sign = if x > 0 then "+" else ""
	return sign .. string.format("%.1f", x * 100) .. "%"
end

-- 45 -> "45s", 200 -> "3m", 3900 -> "1h 5m"
function Format.Duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return seconds .. "s"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. "m"
	end
	return math.floor(seconds / 3600) .. "h " .. math.floor(seconds % 3600 / 60) .. "m"
end

return Format
