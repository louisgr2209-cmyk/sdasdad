-- TradeLogService (ModuleScript) – ServerScriptService/Services/TradeLogService
-- Trade-Verlauf pro Spieler (nur Anzeige, kein Geld): die letzten 500 Trades mit Gewinn/Verlust.
-- Eigener DataStore "MoR_TradeLog_v1", damit die Geldbörse klein bleibt (32-KB-Grenze im Weltmarkt).
-- Neue Einträge werden gesammelt und jede Minute (und beim Verlassen) ANGEHÄNGT, nie überschrieben:
-- so gehen beim Server-Wechsel keine Einträge verloren. Im Zweifel fehlt mal ein Eintrag (Absturz),
-- am Geld ändert das nichts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ServerScriptService.Util.Remotes)
local RateLimiter = require(ServerScriptService.Util.RateLimiter)
local Store = require(ServerScriptService.Util.Store)

local KEEP = Config.Market.TradeLogKeep
local FLUSH_INTERVAL = 60

local TradeLogService = {}

local logStore = Store.Data("MoR_TradeLog_v1")
local logs = {} -- [player] = { Loaded, List = gesamt (für die Anzeige), Unsaved = noch nicht gespeichert }
local limiter = RateLimiter.new(1, 2)

local function key(player: Player): string
	return "u_" .. player.UserId
end

local function trim(list)
	while #list > KEEP do
		table.remove(list, 1)
	end
end

-- Eintrag hinzufügen. entry = { C = coinId, T = Ticker, I = Icon, S = "Buy"/"Sell"/"Rug"/"Dev"/"SL", M = Cash, P = Gewinn? }
function TradeLogService.Add(player: Player, entry)
	local log = logs[player]
	if not log then
		return
	end
	entry.At = math.floor(workspace:GetServerTimeNow())
	table.insert(log.List, entry)
	trim(log.List)
	table.insert(log.Unsaved, entry)
end

local function flush(player: Player)
	local log = logs[player]
	if not log or #log.Unsaved == 0 then -- nur Anhängen: geht auch, wenn das Laden noch fehlt
		return
	end
	local batch = log.Unsaved
	log.Unsaved = {}
	local ok = logStore:Update(key(player), function(old)
		local list = if type(old) == "table" then old else {}
		for _, entry in batch do
			table.insert(list, entry)
		end
		trim(list)
		return list
	end)
	if not ok then
		-- nicht gespeichert: beim nächsten Mal nochmal (vorne einreihen)
		for i = #batch, 1, -1 do
			table.insert(log.Unsaved, 1, batch[i])
		end
	end
end

local function load(player: Player)
	local log = { Loaded = false, List = {}, Unsaved = {} }
	logs[player] = log
	local ok, stored = logStore:Get(key(player))
	if logs[player] ~= log then
		return
	end
	local list = if ok and type(stored) == "table" then stored else {}
	-- schon während des Ladens hinzugekommene Einträge hinten anhängen
	for _, entry in log.List do
		table.insert(list, entry)
	end
	trim(list)
	log.List = list
	log.Loaded = ok
	if not ok then -- Laden fehlgeschlagen: in 30 Sek. nochmal (nur für die Anzeige)
		task.delay(30, function()
			if logs[player] == log and player.Parent then
				local okRetry, storedRetry = logStore:Get(key(player))
				if okRetry then
					local merged = if type(storedRetry) == "table" then storedRetry else {}
					for _, entry in log.Unsaved do
						table.insert(merged, entry)
					end
					trim(merged)
					log.List = merged
					log.Loaded = true
				end
			end
		end)
	end
end

-- Client fragt seinen Verlauf ab (nur den eigenen)
local function onGet(player: Player)
	if not limiter:Allow(player) then
		return nil
	end
	local log = logs[player]
	return if log then log.List else nil
end

function TradeLogService.Init()
	Remotes.Function("TradeLog").OnServerInvoke = onGet
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		limiter:Remove(player)
		pcall(flush, player)
		logs[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(FLUSH_INTERVAL)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(flush, player)
				if not ok then
					warn("[TradeLog] flush: " .. tostring(err))
				end
			end
		end
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(pcall, flush, player)
		end
		task.wait(3)
	end)
end

return TradeLogService
