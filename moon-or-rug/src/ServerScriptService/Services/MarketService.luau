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

local coins = {} -- lokale Kopie: [coinId] = coin
local dirty = {} -- [coinId] = true: an Clients schicken
local pendingTrades = {} -- neue Trades seit dem letzten Update (alle Server)
local pendingNews = {} -- neue Meldungen seit dem letzten Update
local removedIds = {} -- gelöschte Coins seit dem letzten Update
local flushQueue = {} -- [shard] = { Updates = {}, Removes = {} }: noch in die Sammel-Schlüssel schreiben
local newsOut = {} -- eigene Meldungen, noch nicht an andere Server geschickt
local npcFees = {} -- [npcKey] = Betrag, gesammelt
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
		end
		-- Gebühren an Spieler-Ersteller: kommt mit Phase 6 (Coins von Spielern)
	end
	if rug then
		MarketService.Announce("Rug", string.format("RUG PULL! %s dumped $%s", wallet.Name, coin.Ticker))
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

-- Schritte 2 + 3 für einen angemeldeten Trade p = { S, Side, Coin, Cash, Frac }
-- -> ok, nachricht
local function settle(player: Player, p)
	local key = PlayerData.Key(player)
	local okCoin, result, newValue = coinsMap:Update(p.Coin, Ledger.CoinTrade, {
		Key = key,
		Name = player.DisplayName,
		Seq = p.S,
		Side = p.Side,
		Cash = p.Cash,
		Frac = p.Frac,
		Now = now(),
	})
	if not okCoin or not result then
		return false, "Trade pending – it finishes automatically"
	end
	local coin = nil
	if newValue then
		coin = onCoinValue(newValue)
	end
	local okFinish =
		PlayerData.WalletUpdate(player, Ledger.WalletFinish, { Seq = p.S, Result = result, Now = now() })
	if not okFinish then
		return false, "Trade pending – it finishes automatically"
	end
	PlayerData.SetHolding(player, p.Coin, result.Amount or 0, result.Cost or 0)
	-- Gebühren/Meldungen nur bei frischer Buchung (bei Wiederholung nie doppelt)
	if result.Ok and newValue and coin then
		afterTrade({ Key = key, Name = player.DisplayName, IsNpc = false }, coin, result, false)
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
	local cash = nil
	if side == "Buy" then
		cash = Ledger.FloorCents(wallet.Cash * fraction)
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
	return settle(player, { S = begin.Seq, Side = side, Coin = coinId, Cash = cash, Frac = fraction })
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
	return { Coins = list, Me = PlayerData.BuildState(player) }
end

------------------------------------------------------------------------
-- Für den NPC-Host
------------------------------------------------------------------------

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

-- Neuer Coin. info = { Name, Ticker, Icon, Desc, CreatorKey, CreatorName, License } -> lokaler Coin oder nil
function MarketService.CreateCoin(info)
	info.Id = string.sub((string.gsub(HttpService:GenerateGUID(false), "-", "")), 1, 12)
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

local function flushFees()
	if next(npcFees) == nil then
		return
	end
	local adds = npcFees
	npcFees = {}
	-- ohne Wiederholung: im Fehlerfall verfällt die Gebühr, sie wird aber nie doppelt gutgeschrieben
	marketMap:UpdateOnce("InboxNpc", Ledger.InboxAdd, { Adds = adds })
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
	if next(dirty) == nil and #pendingTrades == 0 and #pendingNews == 0 and #removedIds == 0 then
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
	updateEvent:FireAllClients({ Coins = list, Trades = pendingTrades, News = pendingNews, Removed = removedIds })
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
	loop("fees", every(W.FeeFlushInterval), flushFees)
	game:BindToClose(function()
		pcall(flush)
		pcall(flushFees)
	end)
end

return MarketService
