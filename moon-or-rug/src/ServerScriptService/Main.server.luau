-- Main (Script) – ServerScriptService/Main
-- Startet alle Server-Services in der richtigen Reihenfolge.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldService = require(ServerScriptService.Services.WorldService)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local MarketService = require(ServerScriptService.Services.MarketService)
local NpcTraderService = require(ServerScriptService.Services.NpcTraderService)
local LeaderboardService = require(ServerScriptService.Services.LeaderboardService)
local ProtectionService = require(ServerScriptService.Services.ProtectionService)
local LaunchService = require(ServerScriptService.Services.LaunchService)

-- Reines Terminal: kein Avatar
Players.CharacterAutoLoads = false

-- Verbindungen zwischen den Services (ohne gegenseitige requires)
PlayerDataService.RecoverPending = MarketService.RecoverPending
PlayerDataService.WaitIdle = MarketService.WaitIdle

WorldService.Start() -- meldet den Server in der Welt, wählt den NPC-Host
MarketService.Init({ PlayerData = PlayerDataService })
MarketService.Start() -- lädt den Weltmarkt
NpcTraderService.Init()
NpcTraderService.Start() -- NPCs laufen nur auf dem Host
LeaderboardService.Init()
ProtectionService.Init()
LaunchService.Init()
PlayerDataService.Init() -- erst jetzt Spieler laden: Markt ist bereit
LeaderboardService.Start()
ProtectionService.Start()

print("[MoonOrRug] Server ready")
