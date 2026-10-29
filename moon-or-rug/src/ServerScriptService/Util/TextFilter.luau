-- TextFilter (ModuleScript) – ServerScriptService/Util/TextFilter
-- Spieler-Texte (Coin-Name, Ticker, Beschreibung) prüfen:
--  1. eigene Regeln (Länge, erlaubte Zeichen, Sperrliste echter Krypto-Namen)
--  2. Roblox-Textfilter (Pflicht). Wird etwas weggefiltert (####), lehnen wir den Text ab.

local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local L = Config.Launch

local TextFilter = {}

local blocked = {}
for _, word in L.Blocked do
	blocked[word] = true
end

-- Enthält der Text ein gesperrtes Wort (als ganzes Wort, Groß/klein egal)?
local function hasBlockedWord(text: string): boolean
	local upper = string.upper(text)
	for word in string.gmatch(upper, "%a+") do
		if blocked[word] then
			return true
		end
	end
	-- auch zusammengeschrieben, z. B. "BabyBitcoin" (nur lange Wörter, sonst zu viele Fehlalarme)
	for word in blocked do
		if #word >= 4 and string.find(upper, word, 1, true) then
			return true
		end
	end
	return false
end

-- Roblox-Filter. -> ok, gefilterter Text
local function robloxFilter(text: string, userId: number): (boolean, string?)
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
	end)
	if not ok then
		return false, nil
	end
	local ok2, filtered = pcall(function()
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok2 then
		return false, nil
	end
	return true, filtered
end

local function clean(text: any): string?
	if typeof(text) ~= "string" or #text > 200 then
		return nil -- kein Text oder absurd lang (Exploiter)
	end
	-- Leerzeichen am Rand weg, mehrere Leerzeichen zu einem (gsub gibt 2 Werte zurück -> Klammern)
	local trimmed = (string.gsub(text, "^%s+", ""))
	trimmed = (string.gsub(trimmed, "%s+$", ""))
	return (string.gsub(trimmed, "%s+", " "))
end

-- Prüft alle Felder für einen neuen Coin. -> info oder nil, fehlertext
function TextFilter.CheckCoin(player: Player, name: any, ticker: any, desc: any, icon: any)
	name, ticker, desc = clean(name), clean(ticker), clean(desc or "")
	if not name or not ticker or not desc then
		return nil, "Invalid input"
	end
	ticker = string.upper(ticker)

	if #name < L.NameMin or #name > L.NameMax then
		return nil, string.format("Name: %d to %d characters", L.NameMin, L.NameMax)
	end
	if not string.match(name, "^[%w ]+$") then
		return nil, "Name: only letters, numbers and spaces"
	end
	if #ticker < L.TickerMin or #ticker > L.TickerMax or not string.match(ticker, "^%u+$") then
		return nil, string.format("Ticker: %d to %d letters A-Z", L.TickerMin, L.TickerMax)
	end
	if #desc > L.DescMax then
		return nil, string.format("Description: max. %d characters", L.DescMax)
	end
	if typeof(icon) ~= "string" or not table.find(Config.CoinIcons, icon) then
		return nil, "Please pick an icon"
	end
	if blocked[ticker] or hasBlockedWord(name) or hasBlockedWord(desc) then
		return nil, "Real coin names and brands are not allowed – use a fictional name"
	end

	-- Roblox-Filter für alles, was andere sehen
	for _, text in { name, ticker, desc } do
		if text ~= "" then
			local ok, filtered = robloxFilter(text, player.UserId)
			if not ok then
				return nil, "Text check failed – please try again"
			end
			if filtered ~= text then
				return nil, "That text is not allowed"
			end
		end
	end
	return { Name = name, Ticker = ticker, Desc = desc, Icon = icon }, nil
end

-- Creator-Code prüfen (4–12 Zeichen A–Z/0–9, Sperrliste, Roblox-Filter). -> Code (groß) oder nil, fehlertext
function TextFilter.CheckCode(player: Player, code: any)
	if typeof(code) ~= "string" or #code > 50 then
		return nil, "Invalid code"
	end
	code = string.upper((string.gsub(code, "%s", "")))
	local C = Config.Creator
	if #code < C.CodeMin or #code > C.CodeMax or not string.match(code, "^[%u%d]+$") then
		return nil, string.format("Code: %d to %d letters/numbers", C.CodeMin, C.CodeMax)
	end
	if blocked[code] or hasBlockedWord(code) then
		return nil, "That code is not allowed"
	end
	local ok, filtered = robloxFilter(code, player.UserId)
	if not ok then
		return nil, "Text check failed – please try again"
	end
	if filtered ~= code then
		return nil, "That code is not allowed"
	end
	return code, nil
end

-- Nur Format prüfen (beim Einlösen: der Code wurde beim Anlegen schon gefiltert)
function TextFilter.NormalizeCode(code: any): string?
	if typeof(code) ~= "string" or #code > 50 then
		return nil
	end
	code = string.upper((string.gsub(code, "%s", "")))
	local C = Config.Creator
	if #code < C.CodeMin or #code > C.CodeMax or not string.match(code, "^[%u%d]+$") then
		return nil
	end
	return code
end

return TextFilter
