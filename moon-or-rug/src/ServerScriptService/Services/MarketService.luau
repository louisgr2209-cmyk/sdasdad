-- MarketService (ModuleScript) – ServerScriptService/Services/MarketService
-- Weltmarkt: alle Server teilen dieselben Coins.
--  * Wahrheit: ein MemoryStore-Schlüssel pro Coin (Trades atomar über Ledger.CoinTrade)
--  * Verbreitung: jeder Server schreibt Kurzinfos in 4 Sammel-Schlüssel und liest sie alle 0,5–1 Sek.
--  * Lokal: Kopie aller Coins für Anzeige, Charts und Kurs-Updates an die Clients (alle 0,25 Sek.)
-- Spieler-Trades laufen in 3 Schritten mit Nummer (siehe Ledger) -> nie doppelt, auch bei Absturz.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage.Shared.Config)
local Curve = require(ReplicatedStorage.Shared.BondingCurve)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ServerScriptService.Util.Remotes)
local RateLimiter = require(ServerScriptService.Util.RateLimiter)
local Store = require(ServerScriptService.Util.Store)
local Ledger = require(ServerScriptService.Util.Ledger)
local WorldService = require(ServerScriptService.Services.WorldService)

local C = Config.Curve
local W = Config.World

local MarketService = {}

local PlayerData -- wird in Init gesetzt
local coinsMap = Store.Map(W.CoinsMap, W.CoinExpiration)
local marketMap = Store.Map(W.MarketMap, W.Expiration)
local inboxMap = Store.Map(W.InboxMap, W.CoinExpiration)
local LC = Config.Launch

local coins = {} -- lokale Kopie: [coinId] = coin
local dirty = {} -- [coinId] = true: an Clients schicken
local pendingTrades = {} -- neue Trades seit dem letzten Update (alle Server)
local pendingNews = {} -- neue Meldungen seit dem letzten Update
local removedIds = {} -- gelöschte Coins seit dem letzten Update
local flushQueue = {} -- [shard] = { Updates = {}, Removes = {} }: noch in die Sammel-Schlüssel schreiben
local newsOut = {} -- eigene Meldungen, noch nicht an andere Server geschickt
local npcFees = {} -- [npcKey] = Betrag, gesammelt
local potAdds = { Ins = 0 } -- Versicherungsprämien, gesammelt (alle 10 Sek. in den Topf)
local playerFees = {} -- [Spieler-Schlüssel] = Betrag: Ersteller-Gebühren (alle 10 Sek. ins Postfach)
local boosts = {} -- [coinId] = bis (Server-Zeit): aktuelle Boosts (alle Server)
local boostsChanged = false
local lastNewsSeq = nil -- zuletzt gesehene Meldung (nil = noch nie gelesen)
local queues = {} -- [player] = { Busy, Items }: Trades eines Spielers nacheinander

local tradeLimiter = RateLimiter.new(Config.Trade.MaxPerSecond)
local minuteLimiter = RateLimiter.new(Config.Trade.MaxPerMinute, 60)
local warnLimiter = RateLimiter.new(1) -- "Too fast" höchstens 1x pro Sek.
local snapshotLimiter = RateLimiter.new(Config.Security.SnapshotsPer30s, 30)

local updateEvent: RemoteEvent
local resultEvent: RemoteEvent

local function now(): number
	return workspace:GetServerTimeNow()
end

local function isValidNumber(n: any): boolean
	return typeof(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- Neue, weltweit eindeutige Coin-Id (12 Zeichen)
local function newCoinId(): string
	return string.sub((string.gsub(HttpService:GenerateGUID(false), "-", "")), 1, 12)
end

-- Sammel-Schlüssel für einen Coin (1..Shards)
local function shardOf(coinId: string): number
	local sum = 0
	for i = 1, #coinId do
		sum += string.byte(coinId, i)
	end
	return sum % W.Shards + 1
end

------------------------------------------------------------------------
-- Kurzinfo (aus dem Coin-Wert) und lokale Kopie
------------------------------------------------------------------------

-- Öffentliche Kurzinfo eines Coins (wird in die Sammel-Schlüssel geschrieben). Keine Holder-Liste.
local function publicInfo(value)
	local amounts, early, count = {}, 0, 0
	for key, holding in value.H do
		count += 1
		table.insert(amounts, holding.A)
		if value.E[key] then
			early += holding.A
		end
	end
	table.sort(amounts, function(a, b)
		return a > b
	end)
	local top = 0
	for i = 1, math.min(10, #amounts) do
		top += amounts[i]
	end
	local dev = value.CK and value.H[value.CK]
	local lastTrades = {} -- nur die letzten 3 Trades (spart Platz), ohne Lücken in der Liste
	for i = math.max(1, #value.T - 2), #value.T do
		table.insert(lastTrades, value.T[i])
	end
	return {
		V = value.V,
		Id = value.Id,
		Name = value.Name,
		Ticker = value.Ticker,
		Icon = value.Icon,
		CN = value.CN,
		CK = value.CK,
		Lic = value.Lic,
		At = value.At,
		LT = value.LT,
		Sup = value.Sup,
		Mig = value.Mig,
		Dead = value.Dead,
		Rug = value.Rug,
		Vol = value.Vol,
		HC = count,
		Dev = (if dev then dev.A else 0) / C.TotalSupply,
		Top = top / C.TotalSupply,
		Ear = early / C.TotalSupply,
		T = lastTrades,
		SLC = (function() -- Anzahl Stop-Loss-Aufträge (nur Anzahl, keine Preise: sonst könnte man sie jagen)
			local count = 0
			for _ in value.SL or {} do
				count += 1
			end
			return count
		end)(),
	}
end

local function updateCandle(coin)
	local p = Curve.Price(C, coin.Supply)
	local candle = coin.Candle
	candle.C = p
	candle.H = math.max(candle.H, p)
	candle.L = math.min(candle.L, p)
end

-- Kurzinfo in die lokale Kopie übernehmen (nur wenn neuer)
local function applyInfo(info)
	local coin = coins[info.Id]
	if coin and coin.V >= info.V then
		return coin
	end
	if not coin then
		local p = Curve.Price(C, info.Sup)
		coin = {
			Chart = {},
			PointCount = 0,
			NewPoints = {},
			Trades = {},
			LastTradeId = 0,
			Candle = { O = p, H = p, L = p, C = p },
		}
		coins[info.Id] = coin
	end
	coin.V = info.V
	coin.Info = info
	coin.Id = info.Id
	coin.Name = info.Name
	coin.Ticker = info.Ticker
	coin.Icon = info.Icon
	coin.CreatorName = info.CN
	coin.CreatorKey = info.CK
	coin.CreatorHasLicense = info.Lic == true
	coin.CreatedAt = info.At
	coin.LastTradeAt = info.LT
	coin.Supply = info.Sup
	coin.Migrated = info.Mig == true
	coin.Dead = info.Dead == true
	coin.Rugged = info.Rug == true
	coin.Volume = info.Vol
	coin.Holders = info.HC
	coin.DevShare = info.Dev
	coin.Top10 = info.Top
	coin.EarlyShare = info.Ear
	coin.StopLossCount = info.SLC or 0
	updateCandle(coin)

	for _, t in info.T or {} do
		if t.I > coin.LastTradeId then
			coin.LastTradeId = t.I
			local trade = {
				CoinId = coin.Id,
				Ticker = coin.Ticker,
				Side = t.S,
				Trader = t.N,
				IsNpc = t.B,
				Tokens = t.K,
				Cash = t.M,
				Time = t.At,
			}
			table.insert(coin.Trades, trade)
			if #coin.Trades > Config.Market.RecentTrades then
				table.remove(coin.Trades, 1)
			end
			table.insert(pendingTrades, trade)
		end
	end
	dirty[coin.Id] = true
	return coin
end

local function queueFlush(info)
	local shard = shardOf(info.Id)
	local q = flushQueue[shard] or { Updates = {}, Removes = {} }
	q.Updates[info.Id] = info
	q.Removes[info.Id] = nil
	flushQueue[shard] = q
end

-- Nach eigenem Schreiben: lokale Kopie + Sammel-Schlüssel aktualisieren
local function onCoinValue(value)
	local info = publicInfo(value)
	local coin = applyInfo(info)
	queueFlush(info)
	return coin
end

local function removeLocal(coinId: string)
	if coins[coinId] then
		coins[coinId] = nil
		dirty[coinId] = nil
		table.insert(removedIds, coinId)
	end
end

------------------------------------------------------------------------
-- Kurzinfo für die Clients (gleiches Format wie vorher)
------------------------------------------------------------------------

local function summary(coin)
	local price = Curve.Price(C, coin.Supply)
	local marketCap = price * C.TotalSupply
	return {
		Id = coin.Id,
		Name = coin.Name,
		Ticker = coin.Ticker,
		Icon = coin.Icon,
		CreatorName = coin.CreatorName,
		CreatorId = coin.CreatorKey, -- damit der Client "mein Coin" erkennt
		CreatedAt = coin.CreatedAt,
		Supply = coin.Supply,
		Price = price,
		MarketCap = marketCap,
		Stage = if coin.Dead then "Dead" else Curve.Stage(C, marketCap, coin.Migrated),
		Rugged = coin.Rugged,
		CreatorHasLicense = coin.CreatorHasLicense,
		Holders = coin.Holders,
		DevShare = coin.DevShare,
		Top10 = coin.Top10,
		EarlyShare = coin.EarlyShare,
		Volume = coin.Volume,
		Candle = coin.Candle,
		NewPoints = coin.NewPoints,
	}
end

local function fullInfo(coin)
	local info = summary(coin)
	info.Chart = coin.Chart
	info.Trades = coin.Trades
	return info
end

------------------------------------------------------------------------
-- Meldungen und Gebühren
------------------------------------------------------------------------

-- Meldung an alle Server (Ticker unten)
function MarketService.Announce(kind: string, text: string)
	table.insert(newsOut, { Kind = kind, Text = text })
end

-- Nach einem frisch gebuchten Trade: Gebühr sammeln, Meldungen, Sicherheits-Log
local function afterTrade(wallet, coin, result, rug: boolean)
	if result.Fee and result.Fee > 0 and result.CreatorKey then
		if string.sub(result.CreatorKey, 1, 4) == "npc:" then
			npcFees[result.CreatorKey] = (npcFees[result.CreatorKey] or 0) + result.Fee
		elseif result.CreatorKey ~= wallet.Key then
			playerFees[result.CreatorKey] = (playerFees[result.CreatorKey] or 0) + result.Fee
		end
	end
	if rug then
		MarketService.Announce("Rug", string.format("RUG PULL! %s dumped $%s", wallet.Name, coin.Ticker))
		if MarketService.RugHandler then
			task.spawn(MarketService.RugHandler, coin, result) -- Versicherung/Anfänger-Erstattung (ProtectionService)
		end
	elseif (result.Profit or 0) >= Config.Ticker.BigProfit then
		MarketService.Announce(
			"Profit",
			string.format(
				"%s%s made %s Cash on $%s",
				if wallet.IsNpc then "🤖 " else "",
				wallet.Name,
				Format.Cash(result.Profit),
				coin.Ticker
			)
		)
	end
	if not wallet.IsNpc and (result.Profit or 0) >= Config.Security.LogProfitAbove then
		print(
			string.format(
				"[Security] big profit: %s (%s) +%.2f on %s ($%s)",
				wallet.Name,
				wallet.Key,
				result.Profit,
				coin.Id,
				coin.Ticker
			)
		)
	end
end

------------------------------------------------------------------------
-- Spieler-Trades (3 Schritte, siehe Ledger)
------------------------------------------------------------------------

-- Schritte 2 + 3 für einen angemeldeten Trade p = { S, Side, Coin, Cash, Frac, Prem, Ins, L }
-- -> ok, nachricht
local function settle(player: Player, p)
	local key = PlayerData.Key(player)
	local isLaunch = p.Side == "Launch"
	local okCoin, result, newValue
	if isLaunch then
		okCoin, result, newValue = coinsMap:Update(p.Coin, Ledger.CoinLaunch, {
			Id = p.Coin,
			Info = p.Info,
			Key = key,
			Name = player.DisplayName,
			Seq = p.S,
			DevCash = p.Cash,
			Level = p.L,
			Now = now(),
		})
	else
		okCoin, result, newValue = coinsMap:Update(p.Coin, Ledger.CoinTrade, {
			Key = key,
			Name = player.DisplayName,
			Seq = p.S,
			Side = p.Side,
			Cash = p.Cash,
			Frac = p.Frac,
			Insure = p.Ins,
			Level = p.L,
			Now = now(),
		})
	end
	if not okCoin or not result then
		return false, "Trade pending – it finishes automatically"
	end
	local coin = nil
	if newValue then
		coin = onCoinValue(newValue)
		if isLaunch then
			coin.LocalCreatedAt = os.clock()
		end
	end
	local okFinish =
		PlayerData.WalletUpdate(player, Ledger.WalletFinish, { Seq = p.S, Result = result, Now = now() })
	if not okFinish then
		return false, "Trade pending – it finishes automatically"
	end
	PlayerData.SetHolding(player, p.Coin, result.Amount or 0, result.Cost or 0)
	-- Gebühren/Meldungen nur bei frischer Buchung (bei Wiederholung nie doppelt)
	if isLaunch then
		if not result.Ok then
			return false, result.Error or "Launch failed – your cash was refunded"
		end
		local devText = if (result.Cash or 0) > 0 then " (dev buy " .. Format.Cash(result.Cash) .. ")" else ""
		return true, string.format("🚀 $%s launched!%s", p.Info.Ticker, devText)
	end
	if result.Ok and newValue and coin then
		afterTrade({ Key = key, Name = player.DisplayName, IsNpc = false }, coin, result, false)
		if p.Prem then
			potAdds.Ins += p.Prem -- Versicherungsprämie in den Topf
		end
	end
	if not result.Ok then
		return false, result.Error or "Trade failed"
	end
	if result.Unknown then
		return true, "Trade completed"
	end
	local ticker = if coins[p.Coin] then coins[p.Coin].Ticker else "?"
	local verb = if p.Side == "Buy" then "Bought" else "Sold"
	return true,
		string.format("%s %s %s for %s Cash", verb, Format.Short(result.Tokens), ticker, Format.Cash(result.Cash))
end

-- Offenen Trade eines Spielers fertig buchen (nach Absturz, verlorener Antwort usw.)
function MarketService.RecoverPending(player: Player): boolean
	local wallet = PlayerData.GetWallet(player)
	if not wallet or not wallet.P then
		return true
	end
	settle(player, wallet.P)
	local after = PlayerData.GetWallet(player)
	return after ~= nil and after.P == nil
end

local function executeTrade(player: Player, coinId: string, side: string, fraction: number)
	local wallet = PlayerData.GetWallet(player)
	if not wallet then
		return false, "Still loading your data…"
	end
	if wallet.P then
		if not MarketService.RecoverPending(player) then
			return false, "Previous trade still processing – try again"
		end
		wallet = PlayerData.GetWallet(player)
		if not wallet then
			return false, "Still loading your data…"
		end
	end
	if side == "Sell" and not PlayerData.GetHolding(player, coinId) then
		return false, "You don't own this coin"
	end
	local cash, premium, insure = nil, nil, nil
	local level = PlayerData.GetStats(player).Level
	if side == "Buy" then
		-- Versicherung (Schalter pro Coin, ab Level 5): 5 % zusätzlich, Einsatz so, dass beides ins Cash passt
		insure = wallet.Ins ~= nil and wallet.Ins[coinId] == true and level >= Config.Protection.InsuranceMinLevel
		local rate = if insure then Config.Protection.InsurancePremium else 0
		cash = Ledger.FloorCents(wallet.Cash * fraction / (1 + rate))
		premium = if insure then Ledger.FloorCents(cash * rate) else nil
		if cash < Config.Trade.MinCash then
			return false, if wallet.Cash < Config.Trade.MinCash then "Not enough cash" else "Amount too small"
		end
	end
	local okBegin, begin = PlayerData.WalletUpdate(player, Ledger.WalletBegin, {
		Job = WorldService.JobId,
		Side = side,
		Coin = coinId,
		Cash = cash,
		Frac = fraction,
		Premium = premium,
		Insure = insure or nil,
		Level = level,
		Now = now(),
	})
	if not okBegin or not begin then
		return false, "Market busy – please try again"
	end
	if not begin.Ok then
		if begin.Pending then
			MarketService.RecoverPending(player)
		end
		return false, begin.Error or "Trade failed"
	end
	return settle(player, {
		S = begin.Seq,
		Side = side,
		Coin = coinId,
		Cash = cash,
		Frac = fraction,
		Prem = premium,
		Ins = insure or nil,
		L = level,
	})
end

local function reply(player: Player, ok: boolean, message: string)
	resultEvent:FireClient(player, { Ok = ok, Message = message })
end

-- Trades eines Spielers nacheinander abarbeiten (max. MaxQueued wartend)
local function enqueue(player: Player, job: () -> ()): boolean
	local q = queues[player]
	if not q then
		q = { Busy = false, Items = {} }
		queues[player] = q
	end
	if #q.Items >= Config.Trade.MaxQueued then
		return false
	end
	table.insert(q.Items, job)
	if not q.Busy then
		q.Busy = true
		task.spawn(function()
			while #q.Items > 0 do
				local nextJob = table.remove(q.Items, 1)
				local ok, err = pcall(nextJob)
				if not ok then
					warn("[Market] trade error: " .. tostring(err))
				end
			end
			q.Busy = false
		end)
	end
	return true
end

-- Wartet, bis alle Trades eines Spielers fertig sind (beim Verlassen, vor dem Speichern)
function MarketService.WaitIdle(player: Player, timeout: number)
	local started = os.clock()
	while queues[player] and queues[player].Busy and os.clock() - started < timeout do
		task.wait(0.1)
	end
	queues[player] = nil
end

-- Spieler-Coin erstellen (3 Schritte wie ein Trade: Gebühr + Dev-Buy reservieren, anlegen, abschließen)
local function executeLaunch(player: Player, info, devFraction: number)
	local wallet = PlayerData.GetWallet(player)
	if not wallet then
		return false, "Still loading your data…"
	end
	if wallet.P and not MarketService.RecoverPending(player) then
		return false, "Previous trade still processing – try again"
	end
	wallet = PlayerData.GetWallet(player)
	local level = PlayerData.GetStats(player).Level
	if level < LC.CreateMinLevel then
		return false, "Creating coins unlocks at level " .. LC.CreateMinLevel
	end
	local mine = wallet.MyCoin and coins[wallet.MyCoin]
	if mine and not mine.Dead then
		return false, "You already have an active coin ($" .. mine.Ticker .. ")"
	end
	if MarketService.TickerTaken(info.Ticker) then
		return false, "Ticker $" .. info.Ticker .. " is taken – pick another"
	end
	if wallet.Cash < LC.CreateCost then
		return false, "You need " .. Format.Cash(LC.CreateCost) .. " Cash"
	end
	local devCash = Ledger.FloorCents((wallet.Cash - LC.CreateCost) * devFraction)
	if devCash < Config.Trade.MinCash then
		devCash = 0
	end
	local coinId = newCoinId()
	local okBegin, begin = PlayerData.WalletUpdate(player, Ledger.WalletLaunchBegin, {
		Job = WorldService.JobId,
		Coin = coinId,
		Fee = LC.CreateCost,
		Cash = devCash,
		Info = info,
		Level = level,
		Now = now(),
	})
	if not okBegin or not begin then
		return false, "Market busy – please try again"
	end
	if not begin.Ok then
		if begin.Pending then
			MarketService.RecoverPending(player)
		end
		return false, begin.Error or "Launch failed"
	end
	return settle(player, {
		S = begin.Seq,
		Side = "Launch",
		Coin = coinId,
		Fee = LC.CreateCost,
		Cash = devCash,
		Info = info,
		L = level,
	})
end

function MarketService.Launch(player: Player, info, devFraction: number): boolean
	return enqueue(player, function()
		local ok, message = executeLaunch(player, info, devFraction)
		if player.Parent then
			reply(player, ok, message)
			PlayerData.PushState(player)
		end
	end)
end

-- Boost: nur eigener Coin. Erst bezahlen (mit Buchungsnummer), dann Platz nehmen, sonst Geld zurück.
local function executeBoost(player: Player, coinId: string)
	local wallet = PlayerData.GetWallet(player)
	local coin = coins[coinId]
	if not wallet or not coin then
		return false, "Coin not found"
	end
	if coin.CreatorKey ~= PlayerData.Key(player) then
		return false, "You can only boost your own coin"
	end
	if coin.Dead then
		return false, "This coin is dead"
	end
	if PlayerData.GetStats(player).Level < LC.BoostMinLevel then
		return false, "Boost unlocks at level " .. LC.BoostMinLevel
	end
	-- schnelle Vorprüfung mit der lokalen Liste (spart Hin-und-her-Buchungen)
	local t = now()
	local active, nextFree = 0, math.huge
	for id, untilTime in boosts do
		if untilTime > t then
			active += 1
			nextFree = math.min(nextFree, untilTime - t)
			if id == coinId then
				return false, string.format("Already boosted (%dm left)", math.ceil((untilTime - t) / 60))
			end
		end
	end
	if active >= LC.BoostSlots then
		return false, string.format("Boost slots full – next free in %dm", math.ceil(nextFree / 60))
	end
	if wallet.Cash < LC.BoostCost then
		return false, "You need " .. Format.Cash(LC.BoostCost) .. " Cash"
	end
	local payId = HttpService:GenerateGUID(false)
	local okPay, paid = PlayerData.WalletUpdate(player, Ledger.WalletAddCash, {
		Job = WorldService.JobId,
		Id = payId,
		Delta = -LC.BoostCost,
	})
	if not okPay or not paid or not paid.Ok then
		return false, "Not enough cash"
	end
	local okClaim, claim, newBoosts = marketMap:Update("Boosts", Ledger.BoostClaim, {
		Coin = coinId,
		Id = payId,
		Now = now(),
		Seconds = LC.BoostSeconds,
		Slots = LC.BoostSlots,
	})
	if okClaim and claim and claim.Ok then
		if newBoosts then
			boosts = {}
			for id, entry in newBoosts do
				boosts[id] = entry.U
			end
			boostsChanged = true
		end
		return true, string.format("🚀 $%s boosted for %d min!", coin.Ticker, math.floor(LC.BoostSeconds / 60))
	end
	-- kein Platz (oder Fehler): Geld zurück, mit eigener Buchungsnummer (nie doppelt)
	PlayerData.WalletUpdate(player, Ledger.WalletAddCash, {
		Job = WorldService.JobId,
		Id = HttpService:GenerateGUID(false),
		Delta = LC.BoostCost,
	})
	if claim and claim.Full then
		return false, string.format("Boost slots full – next free in %dm (refunded)", math.ceil(claim.NextFree / 60))
	end
	return false, ((claim and claim.Error) or "Boost failed") .. " (refunded)"
end

function MarketService.Boost(player: Player, coinId: string): boolean
	return enqueue(player, function()
		local ok, message = executeBoost(player, coinId)
		if player.Parent then
			reply(player, ok, message)
			PlayerData.PushState(player)
		end
	end)
end

-- Verkauf im Auftrag des Spielers einreihen (Stop-Loss, solange er online ist)
function MarketService.QueueSell(player: Player, coinId: string, prefix: string): boolean
	return enqueue(player, function()
		local ok, message = executeTrade(player, coinId, "Sell", 1)
		if player.Parent then
			reply(player, ok, prefix .. message)
			PlayerData.PushState(player)
		end
	end)
end

-- Stop-Loss im Coin setzen (level = 0.1 .. 0.5 oder nil = aus) -> ok, fehler
function MarketService.SetStopLoss(player: Player, coinId: string, level: number?)
	local ok, result, newValue = coinsMap:Update(coinId, Ledger.CoinSetStopLoss, {
		Key = PlayerData.Key(player),
		Level = level,
	})
	if not ok or not result then
		return false, "Market busy – please try again"
	end
	if newValue then
		onCoinValue(newValue)
	end
	return result.Ok, result.Error
end

-- Coin-Wert direkt lesen (Host: Stop-Loss von Offline-Spielern prüfen)
function MarketService.ReadCoin(coinId: string)
	local ok, value = coinsMap:Get(coinId)
	return if ok then value else nil
end

-- Host: Stop-Loss für einen Offline-Spieler ausführen -> ergebnis oder nil.
-- Ohne Wiederholung: im Zweifel bekommt der Spieler nichts, aber nie doppelt.
function MarketService.StopLossExec(coinId: string, key: string)
	local ok, result, newValue = coinsMap:UpdateOnce(coinId, Ledger.CoinStopLossExec, { Key = key, Now = now() })
	if ok and newValue and result then
		onCoinValue(newValue)
		return result
	end
	return nil
end

function MarketService.Reply(player: Player, ok: boolean, message: string)
	reply(player, ok, message)
end

-- Client schickt: coinId (string), side ("Buy"/"Sell"), fraction (0 < f <= 1)
local function onTradeRequest(player: Player, coinId: any, side: any, fraction: any)
	if not tradeLimiter:Allow(player) or not minuteLimiter:Allow(player) then
		if warnLimiter:Allow(player) then
			reply(player, false, "Too fast! Slow down a little.")
		end
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
	if not coins[coinId] then
		reply(player, false, "Coin not found")
		return
	end
	local queued = enqueue(player, function()
		local ok, message = executeTrade(player, coinId, side, fraction)
		if player.Parent then
			reply(player, ok, message)
			PlayerData.PushState(player)
		end
	end)
	if not queued then
		reply(player, false, "Please wait – your trades are still processing")
	end
end

local function onSnapshotRequest(player: Player)
	if not snapshotLimiter:Allow(player) then
		return nil
	end
	local list = {}
	for _, coin in coins do
		table.insert(list, fullInfo(coin))
	end
	return { Coins = list, Me = PlayerData.BuildState(player), Boosts = boosts }
end

------------------------------------------------------------------------
-- Für den NPC-Host
------------------------------------------------------------------------

-- Wird vom ProtectionService gesetzt: function(coin, ergebnis) nach einem Rugpull
MarketService.RugHandler = nil :: ((any, any) -> ())?

function MarketService.GetCoins()
	return coins
end

function MarketService.LiveCoinCount(): number
	local count = 0
	for _, coin in coins do
		if not coin.Dead then
			count += 1
		end
	end
	return count
end

-- Verkaufswert einer Menge (nach Gebühr)
function MarketService.PositionValue(coin, amount: number): number
	return Curve.CashForTokens(C, coin.Supply, amount) * (1 - Config.Fees.Creator - Config.Fees.Burn)
end

function MarketService.Price(coin): number
	return Curve.Price(C, coin.Supply)
end

-- Kursänderung der letzten "seconds" Sekunden (0.1 = +10 %)
function MarketService.PriceChange(coin, seconds: number): number
	local n = math.max(1, math.ceil(seconds / Config.Market.ChartInterval))
	local ref = coin.Chart[#coin.Chart - n + 1] or coin.Chart[1] or coin.Candle
	if ref.O <= 0 then
		return 0
	end
	return Curve.Price(C, coin.Supply) / ref.O - 1
end

-- Ist dieser Ticker gerade bei einem gelisteten Coin vergeben?
function MarketService.TickerTaken(ticker: string): boolean
	for _, coin in coins do
		if coin.Ticker == ticker and not coin.Dead then
			return true
		end
	end
	return false
end

-- Neuer Coin (NPC). info = { Name, Ticker, Icon, Desc, CreatorKey, CreatorName, License } -> lokaler Coin oder nil
function MarketService.CreateCoin(info)
	info.Id = newCoinId()
	local value = Ledger.NewCoin(info, now())
	if not coinsMap:Set(info.Id, value) then
		return nil
	end
	local coin = onCoinValue(value)
	coin.LocalCreatedAt = os.clock()
	return coin
end

-- NPC-Trade (nur Host, ohne Nummer -> ohne automatische Wiederholung).
-- a = { Side, Cash (Kauf), Frac (Verkauf), Rug? }
-- -> ok, ergebnis. Bei ok = false steht in ergebnis.Amount (falls bekannt) der echte Bestand.
function MarketService.NpcTrade(wallet, coinId: string, a)
	local args = {
		Key = wallet.Key,
		Name = wallet.Name,
		IsNpc = true,
		Side = a.Side,
		Cash = a.Cash,
		Frac = a.Frac,
		Rug = a.Rug,
		Now = now(),
	}
	local ok, result, newValue = coinsMap:UpdateOnce(coinId, Ledger.CoinTrade, args)
	if ok then
		if newValue and result and result.Ok then
			local coin = onCoinValue(newValue)
			afterTrade(wallet, coin, result, a.Rug == true)
			return true, result
		end
		return false, result
	end
	-- Unklar, ob gebucht wurde: echten Bestand nachlesen
	local okGet, value = coinsMap:Get(coinId)
	if not okGet then
		return false, nil
	end
	if value then
		onCoinValue(value)
	end
	local holding = value and value.H[wallet.Key]
	local amount = if holding then holding.A else 0
	if result and result.Ok and math.abs(amount - result.Amount) < 1e-6 then
		local coin = coins[coinId]
		if coin then
			afterTrade(wallet, coin, result, a.Rug == true)
		end
		return true, result -- wurde gebucht
	end
	return false, { Ok = false, Error = "unknown", Amount = amount, Cost = if holding then holding.C else 0 }
end

-- Gesammelte Gebühren der NPC-Ersteller abholen (Host). -> { [npcKey] = Betrag }
function MarketService.DrainNpcFees()
	local ok, result = marketMap:Update("InboxNpc", Ledger.InboxDrain, {})
	return if ok and result then result else {}
end

local function removeCoinEverywhere(id: string)
	local shard = shardOf(id)
	local q = flushQueue[shard] or { Updates = {}, Removes = {} }
	q.Updates[id] = nil
	q.Removes[id] = true
	flushQueue[shard] = q
	removeLocal(id)
end

-- Host: tote Coins markieren, tote Coins ohne Spieler löschen,
-- nach DeadKeepHours ohne Trade Reste automatisch verkaufen (Cash ins Postfach der Spieler)
function MarketService.HostMaintenance()
	local t = now()
	local ids = {} -- Kopie der Liste: während der Speicherzugriffe kann sich "coins" ändern
	for id in coins do
		table.insert(ids, id)
	end
	for _, id in ids do
		local coin = coins[id]
		if not coin then
			continue
		end
		if not coin.Dead and t - coin.LastTradeAt >= Config.Market.DeadAfter then
			local ok, _, newValue =
				coinsMap:Update(id, Ledger.CoinMarkDead, { Now = t, DeadAfter = Config.Market.DeadAfter })
			if ok and newValue then
				onCoinValue(newValue)
			end
		elseif coin.Dead then
			local ok, value = coinsMap:Get(id)
			if ok and (value == nil or not Ledger.HasPlayerHolders(value)) then
				if value == nil or coinsMap:Remove(id) then
					removeCoinEverywhere(id)
				end
			elseif ok and t - value.LT >= W.DeadKeepHours * 3600 then
				local okClose, payouts = coinsMap:Update(id, Ledger.CoinCloseOut, {
					Now = t,
					KeepSeconds = W.DeadKeepHours * 3600,
				})
				if okClose and payouts then
					-- ohne Wiederholung: im Fehlerfall verfällt die Auszahlung, sie kommt aber nie doppelt
					for key, payout in payouts do
						inboxMap:UpdateOnce("u_" .. key, Ledger.InboxAdd, { Adds = { Cash = payout } })
					end
					coinsMap:Remove(id)
					removeCoinEverywhere(id)
				end
			end
		end
	end
end

-- Host: Charts speichern, damit neue Server sofort Verlauf zeigen (Preis/P0*100 als ganze Zahlen)
function MarketService.SaveCharts()
	local byShard = {}
	for id, coin in coins do
		if not coin.Dead then
			local parts = {}
			for _, point in coin.Chart do
				table.insert(parts, tostring(math.floor(point.C / C.P0 * 100 + 0.5)))
			end
			local shard = shardOf(id)
			byShard[shard] = byShard[shard] or {}
			byShard[shard][id] = table.concat(parts, ",")
		end
	end
	for shard = 1, W.Shards do
		marketMap:Set("C" .. shard, byShard[shard] or {})
	end
end

local function loadCharts()
	for shard = 1, W.Shards do
		local ok, data = marketMap:Get("C" .. shard)
		if ok and data then
			for id, text in data do
				local coin = coins[id]
				if coin and #coin.Chart == 0 then
					for part in string.gmatch(text, "%d+") do
						local p = tonumber(part) * C.P0 / 100
						coin.PointCount += 1
						table.insert(coin.Chart, { T = coin.PointCount, O = p, H = p, L = p, C = p })
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Takt: lesen, schreiben, Charts, Updates an Clients
------------------------------------------------------------------------

-- Kurzinfos aller Server lesen
local function poll()
	local seen, allOk = {}, true
	for shard = 1, W.Shards do
		local ok, data = marketMap:Get("S" .. shard)
		if ok then
			for id, info in data or {} do
				seen[id] = true
				applyInfo(info)
			end
		else
			allOk = false
		end
	end
	if not allOk then
		return -- unvollständig: nichts löschen
	end
	for id, coin in coins do
		local q = flushQueue[shardOf(id)]
		local waiting = q ~= nil and q.Updates[id] ~= nil
		local fresh = coin.LocalCreatedAt ~= nil and os.clock() - coin.LocalCreatedAt < 10
		if not seen[id] and not waiting and not fresh then
			removeLocal(id)
		end
	end
end

-- Eigene Änderungen in die Sammel-Schlüssel schreiben
local function flush()
	-- Kopie nehmen: während des Schreibens (Wartezeit) kommen neue Änderungen in eine frische Warteschlange
	local batch = flushQueue
	flushQueue = {}
	for shard, q in batch do
		local ok = marketMap:Update("S" .. shard, Ledger.ShardMerge, q)
		if not ok then
			-- später nochmal (neuere Einträge nicht überschreiben)
			local again = flushQueue[shard] or { Updates = {}, Removes = {} }
			for id, info in q.Updates do
				if not again.Updates[id] and not again.Removes[id] then
					again.Updates[id] = info
				end
			end
			for id in q.Removes do
				if not again.Updates[id] then
					again.Removes[id] = true
				end
			end
			flushQueue[shard] = again
		end
	end
end

local function syncNews()
	if #newsOut > 0 then
		local items = newsOut
		newsOut = {}
		marketMap:UpdateOnce("News", Ledger.NewsAdd, { Items = items }) -- ohne Wiederholung: nie doppelt
	end
	local ok, news = marketMap:Get("News")
	if not ok then
		return
	end
	news = news or { Seq = 0, Items = {} }
	if lastNewsSeq == nil then
		lastNewsSeq = news.Seq -- alte Meldungen beim Start nicht zeigen
		return
	end
	for _, item in news.Items do
		if item.S > lastNewsSeq then
			table.insert(pendingNews, { Kind = item.K, Text = item.X })
		end
	end
	lastNewsSeq = math.max(lastNewsSeq, news.Seq)
end

local function flushPots()
	if potAdds.Ins <= 0 then
		return
	end
	local adds = { Ins = potAdds.Ins }
	potAdds.Ins = 0
	marketMap:UpdateOnce("Pots", Ledger.PotsAdd, adds) -- ohne Wiederholung: nie doppelt
end

local function flushFees()
	if next(npcFees) == nil and next(playerFees) == nil then
		return
	end
	local adds = npcFees
	npcFees = {}
	-- ohne Wiederholung: im Fehlerfall verfällt die Gebühr, sie wird aber nie doppelt gutgeschrieben
	if next(adds) then
		marketMap:UpdateOnce("InboxNpc", Ledger.InboxAdd, { Adds = adds })
	end
	local forPlayers = playerFees
	playerFees = {}
	for key, amount in forPlayers do
		inboxMap:UpdateOnce("u_" .. key, Ledger.InboxAdd, { Adds = { Cash = amount, Fee = amount } })
	end
end

local function syncBoosts()
	local ok, data = marketMap:Get("Boosts")
	if not ok then
		return
	end
	local fresh = {}
	for id, entry in data or {} do
		if type(entry) == "table" and type(entry.U) == "number" then
			fresh[id] = entry.U
		end
	end
	for id, untilTime in fresh do
		if boosts[id] ~= untilTime then
			boostsChanged = true
		end
	end
	for id in boosts do
		if not fresh[id] then
			boostsChanged = true
		end
	end
	boosts = fresh
end

local function closeChartPoints()
	for _, coin in coins do
		if coin.Dead then
			continue
		end
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
	if next(dirty) == nil and #pendingTrades == 0 and #pendingNews == 0 and #removedIds == 0 and not boostsChanged then
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
	updateEvent:FireAllClients({
		Coins = list,
		Trades = pendingTrades,
		News = pendingNews,
		Removed = removedIds,
		Boosts = if boostsChanged then boosts else nil,
	})
	boostsChanged = false
	dirty = {}
	pendingTrades = {}
	pendingNews = {}
	removedIds = {}
end

-- Endlosschleife mit Fehlerschutz (ein Fehler hält nie den Markt an)
local function loop(name: string, interval: () -> number, fn: () -> ())
	task.spawn(function()
		while true do
			task.wait(interval())
			local ok, err = pcall(fn)
			if not ok then
				warn("[Market] " .. name .. ": " .. tostring(err))
			end
		end
	end)
end

local function every(seconds: number): () -> number
	return function()
		return seconds
	end
end

function MarketService.Init(deps)
	PlayerData = deps.PlayerData
	updateEvent = Remotes.Event("MarketUpdate")
	resultEvent = Remotes.Event("TradeResult")
	Remotes.Event("TradeRequest").OnServerEvent:Connect(onTradeRequest)
	Remotes.Function("GetMarketSnapshot").OnServerInvoke = onSnapshotRequest
	Players.PlayerRemoving:Connect(function(player)
		tradeLimiter:Remove(player)
		minuteLimiter:Remove(player)
		warnLimiter:Remove(player)
		snapshotLimiter:Remove(player)
	end)
end

function MarketService.Start()
	-- Erst den Weltmarkt laden, dann Charts, dann laufen lassen
	pcall(poll)
	pcall(loadCharts)
	pcall(syncNews)

	local lastChart = os.clock()
	loop("broadcast", every(Config.Market.BroadcastInterval), function()
		if os.clock() - lastChart >= Config.Market.ChartInterval then
			lastChart = os.clock()
			closeChartPoints()
		end
		broadcast()
	end)
	loop("poll", function()
		return WorldService.SyncInterval(W.Shards)
	end, poll)
	loop("flush", function()
		return WorldService.SyncInterval(W.Shards * 2) -- Schreiben kostet 2 Einheiten, nur wenn sich etwas geändert hat
	end, flush)
	loop("news", every(W.NewsInterval), syncNews)
	loop("boosts", every(LC.BoostSyncInterval), syncBoosts)
	loop("fees", every(W.FeeFlushInterval), function()
		flushFees()
		flushPots()
	end)
	game:BindToClose(function()
		pcall(flush)
		pcall(flushFees)
		pcall(flushPots)
	end)
end

return MarketService
