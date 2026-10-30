-- Indicators (ModuleScript) – ReplicatedStorage/Shared/Indicators
-- Einfache Risiko-Ampeln für einen Coin (wie bei Trading-Terminals, aber für jeden verständlich).
-- Jede Ampel: Wert, Bewertung (Good/Ok/Bad), kurze Erklärung und ab wann grün/gelb/rot.
-- Grenzen stehen in Config.Indicators.

local Config = require(script.Parent.Config)

local T = Config.Indicators
local EPSILON = 1e-6 -- Rundungsluft (z. B. genau 5 % Dev-Anteil)

local Indicators = {}

-- Reihenfolge = Reihenfolge der Kacheln auf der Coin-Seite
Indicators.List = {
	{
		Id = "Top10",
		Label = "Top 10",
		Title = "Top 10 holders",
		Kind = "Percent",
		LowerIsBetter = true,
		Explain = "How much of all coins the 10 biggest holders own. "
			.. "If a few people own a lot, they can crash the price by selling.",
	},
	{
		Id = "Dev",
		Label = "Dev",
		Title = "Dev holds",
		Kind = "Percent",
		LowerIsBetter = true,
		Explain = "How much the creator still owns. Every creator starts with 5%. "
			.. "More means the dev bought extra coins – and could dump them.",
	},
	{
		Id = "Early",
		Label = "Early",
		Title = "Early buyers",
		Kind = "Percent",
		LowerIsBetter = true,
		Explain = "Coins held by traders who bought in the first "
			.. T.EarlyWindow
			.. " seconds. They often sell fast for a quick profit.",
	},
	{
		Id = "Holders",
		Label = "Holders",
		Title = "Holders",
		Kind = "Count",
		LowerIsBetter = false,
		Explain = "How many different traders own this coin. "
			.. "More holders = harder for one person to crash the price.",
	},
}
-- Keine Rug-Lizenz-Ampel (Entscheidung Phase 7): niemand sieht, wer ruggen darf.

-- Wert aus den Coin-Daten (Server-Kurzinfo)
function Indicators.Value(coin, id: string): any
	if id == "Top10" then
		return coin.Top10 or 0
	elseif id == "Dev" then
		return coin.DevShare or 0
	elseif id == "Early" then
		return coin.EarlyShare or 0
	end
	return coin.Holders or 0
end

-- "Good", "Ok" oder "Bad"
function Indicators.Rate(id: string, value: any): string
	local limits = T[id]
	if id == "Holders" then -- mehr ist besser
		if value >= limits.Good then
			return "Good"
		end
		return if value >= limits.Bad then "Ok" else "Bad"
	end
	if value <= limits.Good + EPSILON then
		return "Good"
	end
	return if value <= limits.Bad + EPSILON then "Ok" else "Bad"
end

local function percent(x: number): string
	return string.format(if x < 0.1 then "%.1f%%" else "%.0f%%", x * 100)
end

-- Anzeige-Text des Werts: "12%", "7"
function Indicators.Display(id: string, value: any): string
	if id == "Holders" then
		return tostring(value)
	end
	return percent(value)
end

-- Drei Zeilen "ab wann" für die Erklärung
function Indicators.Rules(id: string): { string }
	local limits = T[id]
	if id == "Holders" then
		return {
			string.format("🟢 %d or more = good", limits.Good),
			string.format("🟡 %d to %d = careful", limits.Bad, limits.Good - 1),
			string.format("🔴 under %d = risky", limits.Bad),
		}
	end
	return {
		string.format("🟢 up to %s = good", percent(limits.Good)),
		string.format("🟡 %s to %s = careful", percent(limits.Good), percent(limits.Bad)),
		string.format("🔴 over %s = risky", percent(limits.Bad)),
	}
end

return Indicators
