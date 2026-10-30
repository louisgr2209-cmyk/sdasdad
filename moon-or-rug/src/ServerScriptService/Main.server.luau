-- Main (Script) – ServerScriptService/Main
-- Startet alle Server-Services in der richtigen Reihenfolge.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local WorldService = require(ServerScriptService.Services.WorldService)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local MarketService = require(ServerScriptService.Services.MarketService)
local NpcTraderService = require(ServerScriptService.Services.NpcTraderService)
local LeaderboardService = require(ServerScriptService.Services.LeaderboardService)
local ProtectionService = require(ServerScriptService.Services.ProtectionService)
local LaunchService = require(ServerScriptService.Services.LaunchService)
local CreatorService = require(ServerScriptService.Services.CreatorService)
local MonetizationService = require(ServerScriptService.Services.MonetizationService)

-- Reines Terminal: kein Avatar
Players.CharacterAutoLoads = false

-- Verbindungen zwischen den Services (ohne gegenseitige requires)
PlayerDataService.RecoverPending = MarketService.RecoverPending
PlayerDataService.WaitIdle = MarketService.WaitIdle
-- Ticker-Namen: 🎬 Creator, ⭐ VIP
MarketService.DecorateName = function(key: string, name: string): string
	local player = PlayerDataService.GetPlayerByKey(key)
	local vip = player ~= nil and MonetizationService.HasPass(player, "Vip")
	local legend = player ~= nil and PlayerDataService.GetStats(player).Level >= Config.Prestige.LegendLevel
	return CreatorService.DisplayName(key, name, vip, legend)
end
MarketService.HasPass = MonetizationService.HasPass
ProtectionService.HasPass = MonetizationService.HasPass
LeaderboardService.HasPass = MonetizationService.HasPass
LeaderboardService.IsVipUserId = MonetizationService.IsVipUserId
MarketService.FreeCoinMonth = CreatorService.FreeCoinMonth

WorldService.Start() -- meldet den Server in der Welt, wählt den NPC-Host
MarketService.Init({ PlayerData = PlayerDataService })
MarketService.Start() -- lädt den Weltmarkt
NpcTraderService.Init()
NpcTraderService.Start() -- NPCs laufen nur auf dem Host
LeaderboardService.Init()
ProtectionService.Init()
LaunchService.Init()
CreatorService.Init() -- vor PlayerData: Zusatz-Infos im Spieler-Zustand
MonetizationService.Init() -- vor PlayerData: Gamepässe im Spieler-Zustand, ProcessReceipt
PlayerDataService.Init() -- erst jetzt Spieler laden: Markt ist bereit
LeaderboardService.Start()
ProtectionService.Start()
CreatorService.Start()

print("[MoonOrRug] Server ready")
