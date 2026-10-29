-- LaunchService (ModuleScript) – ServerScriptService/Services/LaunchService
-- Coin erstellen (ab Level 10, 50.000 Cash, optional Dev-Buy bis 50 %) und Boost (ab Level 15, 25.000 Cash,
-- nur eigener Coin, 10 Min., max. 3 weltweit). Prüft die Anfrage, filtert Texte und übergibt an den
-- MarketService (dort laufen die Geldbuchungen mit Duplikat-Schutz in der Trade-Warteschlange des Spielers).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ServerScriptService.Util.Remotes)
local RateLimiter = require(ServerScriptService.Util.RateLimiter)
local TextFilter = require(ServerScriptService.Util.TextFilter)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local MarketService = require(ServerScriptService.Services.MarketService)

local L = Config.Launch

local LaunchService = {}

local limiter = RateLimiter.new(1, 2) -- 1 Anfrage pro 2 Sek.
local busy = {} -- [player] = true: Textprüfung läuft gerade

local function onCreateCoin(player: Player, name: any, ticker: any, desc: any, icon: any, devIndex: any)
	if not limiter:Allow(player) or busy[player] or not PlayerDataService.GetWallet(player) then
		return
	end
	if typeof(devIndex) ~= "number" or not L.DevBuyOptions[devIndex] then
		return
	end
	if PlayerDataService.GetStats(player).Level < L.CreateMinLevel then
		PlayerDataService.Notify(player, false, "Creating coins unlocks at level " .. L.CreateMinLevel)
		return
	end
	busy[player] = true
	local info, err = TextFilter.CheckCoin(player, name, ticker, desc, icon)
	busy[player] = nil
	if not info then
		PlayerDataService.Notify(player, false, err or "Invalid input")
		return
	end
	if not MarketService.Launch(player, info, L.DevBuyOptions[devIndex]) then
		PlayerDataService.Notify(player, false, "Please wait – your trades are still processing")
	end
end

local function onBoostCoin(player: Player, coinId: any)
	if not limiter:Allow(player) or not PlayerDataService.GetWallet(player) then
		return
	end
	if typeof(coinId) ~= "string" or #coinId > 20 then
		return
	end
	if not MarketService.Boost(player, coinId) then
		PlayerDataService.Notify(player, false, "Please wait – your trades are still processing")
	end
end

function LaunchService.Init()
	Remotes.Event("CreateCoin").OnServerEvent:Connect(onCreateCoin)
	Remotes.Event("BoostCoin").OnServerEvent:Connect(onBoostCoin)
	Players.PlayerRemoving:Connect(function(player)
		limiter:Remove(player)
		busy[player] = nil
	end)
end

return LaunchService
