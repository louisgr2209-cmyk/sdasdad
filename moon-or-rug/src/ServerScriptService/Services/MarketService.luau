-- MarketService (ModuleScript) – ServerScriptService/Services/MarketService
-- Coins, Bonding-Curve, Kaufen/Verkaufen, Gebühren, Charts, Kurs-Updates.
-- Nur der Server ändert Kurse und Cash. Der Client schickt nur Wünsche.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Curve = require(ReplicatedStorage.Shared.BondingCurve)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ServerScriptService.Util.Remotes)
local RateLimiter = require(ServerScriptService.Util.RateLimiter)

local C = Config.Curve
local FEE_TOTAL = Config.Fees.Creator + Config.Fees.Burn
local DUST = 1e-9 -- Restmengen darunter zählen als 0

local MarketService = {}

local PlayerData -- wird in Init gesetzt
local coins = {} -- [coinId] = coin
local nextId = 0
local dirty = {} -- [coinId] = true, Coins mit Änderungen seit dem letzten Update
local pendingTrades = {} -- Trades seit dem letzten Update (für Live-Trades/Ticker)
local tradeLimiter = RateLimiter.new(Config.Trade.MaxPerSecond)
local snapshotLimiter = RateLimiter.new(2)

local updateEvent: RemoteEvent
local resultEvent: RemoteEvent

local function now(): number
	return workspace:GetServerTimeNow()
end

local function floorCents(n: number): number
	return math.floor(n * 100 + 1e-6) / 100
end

local function isValidNumber(n: any): boolean
	return typeof(n) == "number" and n == n and n > -math.huge and n < math.huge
end

------------------------------------------------------------------------
-- Coin-Daten
------------------------------------------------------------------------

local function priceOf(coin): number
	return Curve.Price(C, coin.Supply)
end

local function updateCandle(coin)
	local p = priceOf(coin)
	local candle = coin.Candle
	candle.C = p
	candle.H = math.max(candle.H, p)
	candle.L = math.min(candle.L, p)
end

local function setHolding(coin, key: string, amount: number, cost: number)
	local had = coin.Holders[key] ~= nil
	if amount <= DUST then
		coin.Holders[key] = nil
		if had then
			coin.HolderCount -= 1
		end
		return
	end
	coin.Holders[key] = { Amount = amount, Cost = math.max(0, cost) }
	if not had then
		coin.HolderCount += 1
	end
end

-- Kurzinfo für alle Clients (wird alle 0,5 Sek. gebündelt verschickt)
local function summary(coin)
	local price = priceOf(coin)
	local marketCap = price * C.TotalSupply
	local creatorHolding = coin.CreatorKey and coin.Holders[coin.CreatorKey]
	return {
		Id = coin.Id,
		Name = coin.Name,
		Ticker = coin.Ticker,
		Icon = coin.Icon,
		CreatorName = coin.CreatorName,
		CreatedAt = coin.CreatedAt,
		Supply = coin.Supply,
		Price = price,
		MarketCap = marketCap,
		Stage = Curve.Stage(C, marketCap, coin.Migrated),
		Holders = coin.HolderCount,
		DevShare = if creatorHolding then creatorHolding.Amount / C.TotalSupply else 0,
		Volume = coin.Volume,
		Candle = coin.Candle,
		NewPoints = coin.NewPoints,
	}
end

-- Volle Info inkl. Chart und letzten Trades (für neue Clients)
local function fullInfo(coin)
	local info = summary(coin)
	info.Chart = coin.Chart
	info.Trades = coin.Trades
	return info
end

local function recordTrade(coin, side: string, traderName: string, tokens: number, cash: number)
	local trade = {
		CoinId = coin.Id,
		Ticker = coin.Ticker,
		Side = side,
		Trader = traderName,
		Tokens = tokens,
		Cash = cash,
		Price = priceOf(coin),
		Time = now(),
	}
	table.insert(coin.Trades, trade)
	if #coin.Trades > Config.Market.RecentTrades then
		table.remove(coin.Trades, 1)
	end
	table.insert(pendingTrades, trade)

	coin.LastTradeAt = trade.Time
	coin.Volume += cash
	updateCandle(coin)
	if not coin.Migrated and priceOf(coin) * C.TotalSupply >= C.MigrationMarketCap then
		coin.Migrated = true
	end
	dirty[coin.Id] = true
end

-- Creator-Gebühr auszahlen. Ist der Ersteller nicht da, verfällt sie (Geld-Senke).
local function payCreator(coin, amount: number)
	if not coin.CreatorKey or amount <= 0 then
		return
	end
	local wallet = MarketService.WalletForKey(coin.CreatorKey)
	if wallet then
		wallet.AddCash(floorCents(amount))
	end
end

------------------------------------------------------------------------
-- Öffentliche API
------------------------------------------------------------------------

-- Wird von Main gesetzt: function(key) -> wallet | nil
function MarketService.WalletForKey(_key: string)
	return nil
end

-- info = { Name, Ticker, Icon, Description, CreatorKey?, CreatorName }
function MarketService.CreateCoin(info)
	nextId += 1
	local id = "C" .. nextId
	local devAmount = C.TotalSupply * Config.DevShare
	local startPrice = Curve.Price(C, devAmount)

	local coin = {
		Id = id,
		Name = info.Name,
		Ticker = info.Ticker,
		Icon = info.Icon,
		Description = info.Description or "",
		CreatorKey = info.CreatorKey,
		CreatorName = info.CreatorName or "System",
		CreatedAt = now(),
		LastTradeAt = now(),
		Supply = devAmount, -- Dev-Anteil zählt als schon verkauft
		Migrated = false,
		Holders = {},
		HolderCount = 0,
		Volume = 0,
		Chart = {}, -- fertige Chart-Punkte { T, O, H, L, C } (T = laufende Nummer)
		PointCount = 0,
		Candle = { O = startPrice, H = startPrice, L = startPrice, C = startPrice },
		NewPoints = {}, -- seit dem letzten Update fertig gewordene Punkte
		Trades = {},
	}
	if info.CreatorKey then
		setHolding(coin, info.CreatorKey, devAmount, 0)
	end
	coins[id] = coin
	dirty[id] = true
	return coin
end

function MarketService.GetCoin(coinId: string)
	return coins[coinId]
end

-- Kaufen für genau "cash" (inkl. Gebühr). wallet = { Key, Name, GetCash, AddCash }
function MarketService.Buy(wallet, coinId: string, cash: number)
	local coin = coins[coinId]
	if not coin then
		return false, "Coin not found"
	end
	if not isValidNumber(cash) then
		return false, "Invalid amount"
	end
	cash = floorCents(cash)
	if cash < Config.Trade.MinCash then
		return false, "Amount too small"
	end
	if wallet.GetCash() < cash then
		return false, "Not enough cash"
	end

	local creatorFee = cash * Config.Fees.Creator
	local tokens = Curve.TokensForCash(C, coin.Supply, cash * (1 - FEE_TOTAL))
	if tokens <= DUST then
		return false, "Amount too small"
	end
	if not wallet.AddCash(-cash) then
		return false, "Not enough cash"
	end

	coin.Supply += tokens
	local holding = coin.Holders[wallet.Key]
	setHolding(
		coin,
		wallet.Key,
		(holding and holding.Amount or 0) + tokens,
		(holding and holding.Cost or 0) + cash
	)
	payCreator(coin, creatorFee)
	recordTrade(coin, "Buy", wallet.Name, tokens, cash)
	return true, { Tokens = tokens, Cash = cash }
end

-- Verkaufen von "tokens". Auszahlung = Kurvenwert minus Gebühr.
function MarketService.Sell(wallet, coinId: string, tokens: number)
	local coin = coins[coinId]
	if not coin then
		return false, "Coin not found"
	end
	local holding = coin.Holders[wallet.Key]
	if not holding then
		return false, "You don't own this coin"
	end
	if not isValidNumber(tokens) or tokens <= DUST then
		return false, "Amount too small"
	end
	tokens = math.min(tokens, holding.Amount, coin.Supply)

	local gross = Curve.CashForTokens(C, coin.Supply, tokens)
	local payout = floorCents(gross * (1 - FEE_TOTAL))
	if payout <= 0 then
		return false, "Amount too small"
	end

	coin.Supply = math.max(0, coin.Supply - tokens)
	local rest = holding.Amount - tokens
	setHolding(coin, wallet.Key, rest, holding.Cost * (rest / holding.Amount))
	wallet.AddCash(payout)
	payCreator(coin, gross * Config.Fees.Creator)
	recordTrade(coin, "Sell", wallet.Name, tokens, payout)
	return true, { Tokens = tokens, Cash = payout }
end

-- Alle Positionen eines Spielers/NPCs: { [coinId] = { Amount, Cost } }
function MarketService.GetPositions(key: string)
	local result = {}
	for id, coin in coins do
		local holding = coin.Holders[key]
		if holding then
			result[id] = { Amount = holding.Amount, Cost = holding.Cost }
		end
	end
	return result
end

------------------------------------------------------------------------
-- Anfragen vom Client
------------------------------------------------------------------------

local function reply(player: Player, ok: boolean, message: string)
	resultEvent:FireClient(player, { Ok = ok, Message = message })
end

-- Client schickt: coinId (string), side ("Buy"/"Sell"), fraction (0 < f <= 1)
local function onTradeRequest(player: Player, coinId: any, side: any, fraction: any)
	if not tradeLimiter:Allow(player) then
		reply(player, false, "Too fast! Max " .. Config.Trade.MaxPerSecond .. " trades per second.")
		return
	end
	if typeof(coinId) ~= "string" or #coinId > 20 or (side ~= "Buy" and side ~= "Sell") then
		reply(player, false, "Invalid request")
		return
	end
	if not isValidNumber(fraction) or fraction <= 0 or fraction > 1 then
		reply(player, false, "Invalid amount")
		return
	end
	local wallet = PlayerData.Wallet(player)
	local coin = coins[coinId]
	if not wallet or not coin then
		reply(player, false, "Coin not found")
		return
	end

	local ok, result
	if side == "Buy" then
		ok, result = MarketService.Buy(wallet, coinId, wallet.GetCash() * fraction)
	else
		local holding = coin.Holders[wallet.Key]
		local amount = holding and (if fraction == 1 then holding.Amount else holding.Amount * fraction) or 0
		ok, result = MarketService.Sell(wallet, coinId, amount)
	end

	if ok then
		local verb = if side == "Buy" then "Bought" else "Sold"
		reply(player, true, string.format("%s %s %s for %.2f Cash", verb, Format.Short(result.Tokens), coin.Ticker, result.Cash))
	else
		reply(player, false, result)
	end
	PlayerData.PushState(player)
end

local function onSnapshotRequest(player: Player)
	if not snapshotLimiter:Allow(player) then
		return nil
	end
	local list = {}
	for _, coin in coins do
		table.insert(list, fullInfo(coin))
	end
	return { Coins = list, Me = PlayerData.BuildState(player) }
end

------------------------------------------------------------------------
-- Takt: Chart-Punkte + gebündelte Kurs-Updates
------------------------------------------------------------------------

local function closeChartPoints()
	for _, coin in coins do
		local point = coin.Candle
		coin.PointCount += 1
		point.T = coin.PointCount
		table.insert(coin.Chart, point)
		if #coin.Chart > Config.Market.ChartPoints then
			table.remove(coin.Chart, 1)
		end
		table.insert(coin.NewPoints, point)
		coin.Candle = { O = point.C, H = point.C, L = point.C, C = point.C }
		dirty[coin.Id] = true
	end
end

local function broadcast()
	if next(dirty) == nil and #pendingTrades == 0 then
		return
	end
	local list = {}
	for id in dirty do
		local coin = coins[id]
		if coin then
			table.insert(list, summary(coin))
			coin.NewPoints = {}
		end
	end
	updateEvent:FireAllClients({ Coins = list, Trades = pendingTrades })
	dirty = {}
	pendingTrades = {}
end

function MarketService.Init(deps)
	PlayerData = deps.PlayerData
	updateEvent = Remotes.Event("MarketUpdate")
	resultEvent = Remotes.Event("TradeResult")
	Remotes.Event("TradeRequest").OnServerEvent:Connect(onTradeRequest)
	Remotes.Function("GetMarketSnapshot").OnServerInvoke = onSnapshotRequest
	Players.PlayerRemoving:Connect(function(player)
		tradeLimiter:Remove(player)
		snapshotLimiter:Remove(player)
	end)
end

function MarketService.Start()
	task.spawn(function()
		local lastChart = os.clock()
		while true do
			task.wait(Config.Market.BroadcastInterval)
			if os.clock() - lastChart >= Config.Market.ChartInterval then
				lastChart = os.clock()
				closeChartPoints()
			end
			broadcast()
		end
	end)
end

return MarketService
