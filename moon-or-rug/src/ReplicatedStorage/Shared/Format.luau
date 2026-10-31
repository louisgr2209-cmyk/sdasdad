-- Format (ModuleScript) – ReplicatedStorage/Shared/Format
-- Zahlen lesbar machen: 12.5K, 1,234.50, 0.00225, +12.3%
-- Geld: intern "Cash" (Spiel-Dollar-Basis). Angezeigt als Lunar (LNR) oder Spiel-Dollar ($) – je nach Einstellung.
--   1 LNR = Config.Currency.CashPerUnit intern, $-Kurs = Format.Rate() (fiktiv, schwankt langsam, überall gleich).
-- Am Server gibt Format.Cash einen Platzhalter "{$:123.45}" zurück; jeder Client setzt ihn in SEINER Anzeige ein
-- (Format.Resolve), damit Meldungen zur gewählten Währung passen.

local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)

local CUR = Config.Currency
local IS_SERVER = RunService:IsServer()

local Format = {}
Format.Unit = "LNR" -- "LNR" oder "USD" (Client stellt um)

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

-- Fiktiver Kurs: $ pro LNR. Nur Anzeige, hängt nur von der Server-Zeit ab -> auf allen Geräten gleich.
function Format.Rate(t: number?): number
	t = t or workspace:GetServerTimeNow()
	local rate = CUR.RateBase
	for _, wave in CUR.RateWaves do
		rate += wave.Amp * math.sin(t / wave.Period * 2 * math.pi + wave.Phase)
	end
	return rate
end

-- Kleine Zahl mit ca. 3 wichtigen Stellen (0.00225), große mit 2 Nachkommastellen
local function significant(x: number): string
	local a = math.abs(x)
	if a == 0 then
		return "0"
	end
	if a >= 1 then
		return withCommas(string.format("%.2f", x))
	end
	local decimals = math.clamp(2 - math.floor(math.log10(a)), 2, 10)
	return string.format("%." .. decimals .. "f", x)
end

-- Betrag in der gewünschten Einheit: "12.50 LNR" / "$2,000.00"
function Format.Money(n: number, unit: string?): string
	unit = unit or Format.Unit
	local lnr = n / CUR.CashPerUnit
	if unit == "USD" then
		local usd = lnr * Format.Rate()
		local sign = if usd < 0 then "-" else ""
		local a = math.abs(usd)
		return sign .. "$" .. (if a >= 100_000 then Format.Short(a) else withCommas(string.format("%.2f", a)))
	end
	return (if math.abs(lnr) >= 100_000 then Format.Short(lnr) else significant(lnr)) .. " " .. CUR.Symbol
end

-- Geld (überall im Spiel). Server: Platzhalter, den der Client in seiner Einheit einsetzt.
function Format.Cash(n: number): string
	if IS_SERVER then
		return string.format("{$:%.4f}", n)
	end
	return Format.Money(n)
end

-- Geld kurz (Marktkapital, Kosten): "690 LNR" / "$110.4K"
function Format.ShortMoney(n: number, unit: string?): string
	unit = unit or Format.Unit
	local lnr = n / CUR.CashPerUnit
	if unit == "USD" then
		local usd = lnr * Format.Rate()
		return (if usd < 0 then "-$" else "$") .. Format.Short(math.abs(usd))
	end
	return Format.Short(lnr) .. " " .. CUR.Symbol
end

-- Platzhalter "{$:123.45}" in einem Text durch Beträge in der eigenen Einheit ersetzen (Client)
function Format.Resolve(text: string): string
	return (string.gsub(text, "{%$:([%-%d%.]+)}", function(value)
		local n = tonumber(value)
		return if n then Format.Money(n) else value
	end))
end

-- Preis pro Coin (intern Cash pro Token) in der gewünschten Einheit, ca. 3 wichtige Stellen
function Format.Price(p: number, unit: string?): string
	unit = unit or Format.Unit
	if p <= 0 then
		return "0"
	end
	local value = p / CUR.CashPerUnit
	if unit == "USD" then
		value *= Format.Rate()
	end
	local decimals = math.clamp(2 - math.floor(math.log10(value)), 2, 12)
	local text = string.format("%." .. decimals .. "f", value)
	return if unit == "USD" then "$" .. text else text .. " " .. CUR.Symbol
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
