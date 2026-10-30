-- WorldService (ModuleScript) – ServerScriptService/Services/WorldService
-- Weltmarkt-Verwaltung über alle Server:
--  * jeder Server meldet sich alle 10 Sek. (Spielerzahl)
--  * genau EIN Server ist "Host": nur er lässt NPCs handeln, erstellt NPC-Coins und räumt auf.
--    Fällt er aus, übernimmt nach max. 30 Sek. automatisch ein anderer.
--  * Spieler weltweit -> wie viele Coins gleichzeitig gelistet sein dürfen

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Store = require(ServerScriptService.Util.Store)
local Ledger = require(ServerScriptService.Util.Ledger)

local W = Config.World

local WorldService = {}

-- Eindeutige Server-Kennung (in Studio ist JobId leer)
WorldService.JobId = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

local market = Store.Map(W.MarketMap, W.Expiration)
local isHost = false
local totalPlayers = 1
local serverCount = 1

local function now(): number
	return workspace:GetServerTimeNow()
end

local function tick(release: boolean?)
	local ok, result = market:Update("World", Ledger.WorldTick, {
		Job = WorldService.JobId,
		Players = #Players:GetPlayers(),
		Now = now(),
		Lease = W.HostLease,
		Stale = W.ServerStale,
		Release = release,
	})
	if ok and result then
		isHost = result.IsHost
		totalPlayers = math.max(1, result.Players)
		serverCount = math.max(1, result.Servers or 1)
	elseif not ok then
		-- Speicher nicht erreichbar: lieber nicht Host sein (sonst könnten zwei Hosts gleichzeitig laufen)
		isHost = false
	end
end

function WorldService.IsHost(): boolean
	return isHost
end

function WorldService.TotalPlayers(): number
	return totalPlayers
end

-- Abstand zwischen zwei Abfragen von "requests" Schlüsseln, so dass dieser Server
-- höchstens SyncBudgetShare seines Anteils am Roblox-Budget (1000 + 120 pro Spieler pro Min.) nutzt.
function WorldService.SyncInterval(requests: number): number
	local players = math.max(1, #Players:GetPlayers())
	local budget = (1000 / serverCount + 120 * players) * W.SyncBudgetShare -- pro Minute
	local interval = requests * 60 / budget
	return math.clamp(interval, W.MinSyncInterval, W.MaxSyncInterval)
end

-- Wie viele Coins weltweit gelistet sein dürfen (wächst mit der Spielerzahl)
function WorldService.MaxLiveCoins(): number
	local count = W.CoinsBase + math.floor(totalPlayers * W.CoinsPerPlayer)
	return math.clamp(count, W.CoinsBase, W.CoinsMax)
end

function WorldService.Start()
	tick()
	task.spawn(function()
		while true do
			task.wait(W.TickInterval)
			local ok, err = pcall(tick)
			if not ok then
				isHost = false -- im Zweifel nicht Host (nie zwei Hosts gleichzeitig)
				warn("[World] tick: " .. tostring(err))
			end
		end
	end)
	game:BindToClose(function()
		tick(true) -- Host-Rolle sofort freigeben
	end)
end

return WorldService
