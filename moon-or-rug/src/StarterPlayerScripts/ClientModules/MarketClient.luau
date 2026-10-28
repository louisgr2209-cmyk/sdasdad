-- MarketClient (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/MarketClient
-- Empfängt alle Markt-Daten vom Server und hält sie für die Bildschirme bereit.
-- Rechnet nichts Echtes: Werte hier sind nur Anzeige. Trades entscheidet der Server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Curve = require(ReplicatedStorage.Shared.BondingCurve)

local FEE_TOTAL = Config.Fees.Creator + Config.Fees.Burn
local MAX_TRADES = Config.Market.RecentTrades

local MarketClient = {}

MarketClient.Coins = {} -- [coinId] = Info vom Server (+ Chart, Trades)
MarketClient.Me = { Cash = 0, Positions = {}, Stats = nil }
MarketClient.Leaderboard = { World = nil, Server = nil } -- Ranglisten vom Server

-- Signale für die Bildschirme
MarketClient.Changed = Instance.new("BindableEvent") -- Markt oder eigene Daten geändert
MarketClient.TradeResult = Instance.new("BindableEvent") -- (ok, message)
MarketClient.News = Instance.new("BindableEvent") -- (news) z. B. Rugpull, großer Gewinn

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

function MarketClient.SetInsurance(coinId: string, on: boolean)
	local remote = remotes:WaitForChild("SetInsurance") :: RemoteEvent
	remote:FireServer(coinId, on)
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
				MarketClient.Changed:Fire()
				return
			end
			task.wait(1)
		end
	end)
end

return MarketClient
