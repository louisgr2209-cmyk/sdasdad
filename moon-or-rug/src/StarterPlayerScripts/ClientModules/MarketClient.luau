-- MarketClient (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/MarketClient
-- Empfängt alle Markt-Daten vom Server und hält sie für die Bildschirme bereit.
-- Rechnet nichts Echtes: Werte hier sind nur Anzeige. Trades entscheidet der Server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Curve = require(ReplicatedStorage.Shared.BondingCurve)

local FEE_TOTAL = Config.Fees.Creator + Config.Fees.Burn
local MAX_TRADES = Config.Market.RecentTrades

local MarketClient = {}

MarketClient.Coins = {} -- [coinId] = Info vom Server (+ Chart, Trades)
MarketClient.Me = { Cash = 0, Positions = {}, Stats = nil }
MarketClient.Leaderboard = { World = nil, Server = nil } -- Ranglisten vom Server
MarketClient.Boosts = {} -- [coinId] = bis (Server-Zeit)
MarketClient.MyKey = tostring(Players.LocalPlayer.UserId) -- vergleichbar mit coin.CreatorId
MarketClient.Creators = {} -- [Spieler-Schlüssel] = Creator-Stufe (1-4), vom Server

-- Signale für die Bildschirme
MarketClient.Changed = Instance.new("BindableEvent") -- Markt oder eigene Daten geändert
MarketClient.TradeResult = Instance.new("BindableEvent") -- (ok, message)
MarketClient.News = Instance.new("BindableEvent") -- (news) z. B. Rugpull, großer Gewinn
MarketClient.AdminResult = Instance.new("BindableEvent") -- ({ Ok, Message, Log }) nur für Admins

local tradeRequest: RemoteEvent
local remotes: Instance

local function addTrade(coin, trade)
	coin.Trades = coin.Trades or {}
	table.insert(coin.Trades, trade)
	if #coin.Trades > MAX_TRADES then
		table.remove(coin.Trades, 1)
	end
end

-- Neue Chart-Punkte anhängen (T = laufende Nummer, doppelte werden ignoriert)
local function addPoints(coin, points)
	coin.Chart = coin.Chart or {}
	for _, point in points do
		local last = coin.Chart[#coin.Chart]
		if not last or point.T > last.T then
			table.insert(coin.Chart, point)
		end
	end
	while #coin.Chart > Config.Market.ChartPoints do
		table.remove(coin.Chart, 1)
	end
end

local function applyUpdate(update)
	for _, info in update.Coins do
		local coin = MarketClient.Coins[info.Id]
		if not coin then
			coin = { Chart = {}, Trades = {} }
			MarketClient.Coins[info.Id] = coin
		end
		addPoints(coin, info.NewPoints or {})
		for key, value in info do
			if key ~= "NewPoints" then
				coin[key] = value
			end
		end
	end
	for _, id in update.Removed or {} do
		MarketClient.Coins[id] = nil
	end
	for _, trade in update.Trades or {} do
		local coin = MarketClient.Coins[trade.CoinId]
		if coin then
			addTrade(coin, trade)
		end
	end
	if update.Boosts then
		MarketClient.Boosts = update.Boosts
	end
	for _, news in update.News or {} do
		MarketClient.News:Fire(news)
	end
end

------------------------------------------------------------------------
-- Hilfen für die Bildschirme
------------------------------------------------------------------------

function MarketClient.Trade(coinId: string, side: string, fraction: number)
	tradeRequest:FireServer(coinId, side, fraction)
end

-- Schutz (Phase 5): der Server prüft Level und Besitz
function MarketClient.ClaimDaily()
	local remote = remotes:WaitForChild("ClaimDaily") :: RemoteEvent
	remote:FireServer()
end

-- index: 0 = aus, 1..4 = Config.Protection.StopLossLevels
function MarketClient.SetStopLoss(coinId: string, index: number)
	local remote = remotes:WaitForChild("SetStopLoss") :: RemoteEvent
	remote:FireServer(coinId, index)
end

-- Coin erstellen / boosten (Server prüft Level, Cash, Namen, Filter)
function MarketClient.CreateCoin(name: string, ticker: string, desc: string, icon: string, devIndex: number)
	local remote = remotes:WaitForChild("CreateCoin") :: RemoteEvent
	remote:FireServer(name, ticker, desc, icon, devIndex)
end

function MarketClient.Boost(coinId: string)
	local remote = remotes:WaitForChild("BoostCoin") :: RemoteEvent
	remote:FireServer(coinId)
end

-- Rugpull (Phase 7): ein Klick, Server prüft Lizenz, Level, Alter, Cooldown
function MarketClient.RugPull(coinId: string)
	local remote = remotes:WaitForChild("RugPull") :: RemoteEvent
	remote:FireServer(coinId)
end

function MarketClient.BuyLicense()
	local remote = remotes:WaitForChild("BuyLicense") :: RemoteEvent
	remote:FireServer()
end

-- Restzeit eines Boosts in Sek. (0 = nicht geboostet)
function MarketClient.BoostLeft(coinId: string): number
	local untilTime = MarketClient.Boosts[coinId]
	return if untilTime then math.max(0, untilTime - workspace:GetServerTimeNow()) else 0
end

function MarketClient.SetInsurance(coinId: string, on: boolean)
	local remote = remotes:WaitForChild("SetInsurance") :: RemoteEvent
	remote:FireServer(coinId, on)
end

-- Creator-Programm (der Server prüft alles: Admin, Gold-Stufe, Konto-Alter, Spielzeit, einmal pro Spieler)
function MarketClient.CreatorTier(key: any): number
	return if key ~= nil then MarketClient.Creators[tostring(key)] or 0 else 0
end

function MarketClient.RedeemCode(code: string)
	local remote = remotes:WaitForChild("RedeemCode") :: RemoteEvent
	remote:FireServer(code)
end

function MarketClient.SetCreatorCode(code: string)
	local remote = remotes:WaitForChild("SetCreatorCode") :: RemoteEvent
	remote:FireServer(code)
end

-- action: "grant" / "revoke"
function MarketClient.AdminAction(action: string, name: string, tier: number?, video: string?)
	local remote = remotes:WaitForChild("AdminAction") :: RemoteEvent
	remote:FireServer(action, name, tier, video)
end

-- letzte 10 Admin-Aktionen (nil, wenn kein Admin)
function MarketClient.AdminLog()
	local remote = remotes:WaitForChild("AdminLog") :: RemoteFunction
	local ok, log = pcall(remote.InvokeServer, remote)
	return if ok then log else nil
end

-- Wert einer Position = was man jetzt beim Verkaufen bekäme (nach Gebühr)
function MarketClient.PositionValue(coin, position): number
	return Curve.CashForTokens(Config.Curve, coin.Supply, position.Amount) * (1 - FEE_TOTAL)
end

-- Kursänderung über den ganzen Chart (ca. 5 Min.)
function MarketClient.ChartChange(coin): number
	local first = coin.Chart and coin.Chart[1]
	local base = if first then first.O else (coin.Candle and coin.Candle.O)
	if not base or base <= 0 then
		return 0
	end
	return coin.Price / base - 1
end

function MarketClient.Age(coin): number
	return workspace:GetServerTimeNow() - coin.CreatedAt
end

------------------------------------------------------------------------

function MarketClient.Start()
	remotes = ReplicatedStorage:WaitForChild("Remotes")
	tradeRequest = remotes:WaitForChild("TradeRequest") :: RemoteEvent
	local getSnapshot = remotes:WaitForChild("GetMarketSnapshot") :: RemoteFunction
	local marketUpdate = remotes:WaitForChild("MarketUpdate") :: RemoteEvent
	local playerState = remotes:WaitForChild("PlayerState") :: RemoteEvent
	local tradeResult = remotes:WaitForChild("TradeResult") :: RemoteEvent
	local leaderboard = remotes:WaitForChild("Leaderboard") :: RemoteEvent

	leaderboard.OnClientEvent:Connect(function(data)
		if data.World then
			MarketClient.Leaderboard.World = data.World
		end
		if data.Server then
			MarketClient.Leaderboard.Server = data.Server
		end
		MarketClient.Changed:Fire()
	end)

	marketUpdate.OnClientEvent:Connect(function(update)
		applyUpdate(update)
		MarketClient.Changed:Fire()
	end)
	playerState.OnClientEvent:Connect(function(state)
		MarketClient.Me = state
		MarketClient.Changed:Fire()
	end)
	tradeResult.OnClientEvent:Connect(function(result)
		MarketClient.TradeResult:Fire(result.Ok, result.Message)
	end)
	local creators = remotes:WaitForChild("Creators") :: RemoteEvent
	creators.OnClientEvent:Connect(function(tiers)
		MarketClient.Creators = if type(tiers) == "table" then tiers else {}
		MarketClient.Changed:Fire()
	end)
	local adminResult = remotes:WaitForChild("AdminResult") :: RemoteEvent
	adminResult.OnClientEvent:Connect(function(result)
		MarketClient.AdminResult:Fire(result)
	end)

	-- Erste Daten holen (mit Wiederholung, falls der Server noch startet)
	task.spawn(function()
		for _ = 1, 5 do
			local ok, snapshot = pcall(getSnapshot.InvokeServer, getSnapshot)
			if ok and snapshot then
				for _, info in snapshot.Coins do
					local coin = MarketClient.Coins[info.Id] or {}
					for key, value in info do
						coin[key] = value
					end
					coin.NewPoints = nil
					MarketClient.Coins[info.Id] = coin
				end
				if snapshot.Me then
					MarketClient.Me = snapshot.Me
				end
				MarketClient.Boosts = snapshot.Boosts or {}
				MarketClient.Changed:Fire()
				return
			end
			task.wait(1)
		end
	end)
end

return MarketClient
