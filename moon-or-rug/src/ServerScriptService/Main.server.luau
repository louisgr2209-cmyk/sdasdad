-- Main (Script) – ServerScriptService/Main
-- Startet alle Server-Services in der richtigen Reihenfolge.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local MarketService = require(ServerScriptService.Services.MarketService)
local NpcTraderService = require(ServerScriptService.Services.NpcTraderService)

-- Reines Terminal: kein Avatar
Players.CharacterAutoLoads = false

PlayerDataService.Init()
MarketService.Init({ PlayerData = PlayerDataService })
NpcTraderService.Init()

-- Verbindungen zwischen den Services
PlayerDataService.PositionsProvider = MarketService.GetPositions
MarketService.WalletForKey = function(key)
	if string.sub(key, 1, 4) == "npc:" then
		return NpcTraderService.Wallet(key)
	end
	local player = PlayerDataService.GetPlayerByKey(key)
	return player and PlayerDataService.Wallet(player)
end

MarketService.Start()
NpcTraderService.Start()
print("[MoonOrRug] Server ready")
