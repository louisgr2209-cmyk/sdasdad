-- Main (Script) – ServerScriptService/Main
-- Startet alle Server-Services in der richtigen Reihenfolge.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local MarketService = require(ServerScriptService.Services.MarketService)

-- Reines Terminal: kein Avatar
Players.CharacterAutoLoads = false

PlayerDataService.Init()
MarketService.Init({ PlayerData = PlayerDataService })

-- Verbindungen zwischen den Services
PlayerDataService.PositionsProvider = MarketService.GetPositions
MarketService.WalletForKey = function(key)
	local player = PlayerDataService.GetPlayerByKey(key)
	return player and PlayerDataService.Wallet(player)
end

-- Phase 1: ein Test-Coin ohne Ersteller
MarketService.CreateCoin({
	Name = Config.TestCoin.Name,
	Ticker = Config.TestCoin.Ticker,
	Icon = Config.TestCoin.Icon,
	CreatorName = "System",
})

MarketService.Start()
print("[MoonOrRug] Server ready")
