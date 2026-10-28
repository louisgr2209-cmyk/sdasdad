-- NpcTraderService (ModuleScript) – ServerScriptService/Services/NpcTraderService
-- 20 NPC-Trader halten den Weltmarkt am Leben. Sie handeln über dieselben Regeln und Gebühren wie Spieler.
-- Nur der Host-Server (WorldService) lässt sie handeln – egal wie viele Server laufen, es gibt sie nur einmal.
-- Ihr Zustand (Cash, Positionen, Rug-Pläne) wird alle 10 Sek. gespeichert; ein neuer Host macht weiter.
-- Weltweit alle 1–3 Min. ein neuer NPC-Coin, ca. 10 % davon sind NPC-Rugs.
--
-- Typen:
--   Sniper   kauft neue Coins – zufällig OB (40 %) und WANN (5–120 Sek.), damit niemand sie vorhersagen
--            und „melken“ kann. Verkauft bei +50 %, -30 % oder nach 2 Min.
--   Momentum kauft, was gerade steigt, verkauft, wenn es fällt
--   Panik    kauft beliebte Coins, verkauft alles bei schnellem Fall
--   Zufall   kauft/verkauft zufällig kleine Beträge
-- Alle: kaufen nur Coins < 15 Min. und steigen danach aus (so sterben alte Coins).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Curve = require(ReplicatedStorage.Shared.BondingCurve)
local Store = require(ServerScriptService.Util.Store)
local Ledger = require(ServerScriptService.Util.Ledger)
local MarketService = require(ServerScriptService.Services.MarketService)
local WorldService = require(ServerScriptService.Services.WorldService)

local Npc = Config.Npc
local C = Config.Curve
local W = Config.World
local FEE_TOTAL = Config.Fees.Creator + Config.Fees.Burn

local NpcTraderService = {}

local marketMap = Store.Map(W.MarketMap, W.Expiration)
local npcs = {} -- [key] = npc
local npcList = {}
local rugPlans = {} -- [coinId] = { CreatorKey, StartPrice, MinGain } (geheim, nur Server)
local nextCoinAt = 0
local rng = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function pick(list)
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

------------------------------------------------------------------------
-- NPCs und ihr gespeicherter Zustand
------------------------------------------------------------------------

local function createNpc(index: number, kind: string)
	local npc = {
		Key = "npc:" .. index,
		Name = Npc.Names[index] or ("Trader" .. index),
		Kind = kind,
		Cash = Npc.StartCash,
		Holdings = {}, -- [coinId] = { Amount, Cost }
		BoughtAt = {}, -- [coinId] = Zeit des ersten Kaufs
		SnipePlans = {}, -- [coinId] = Verzögerung in Sek. oder false (kauft nicht) – nur Sniper
	}
	npc.Wallet = { Key = npc.Key, Name = npc.Name, IsNpc = true }
	return npc
end

local function saveState()
	local state = { N = {}, R = rugPlans, Next = nextCoinAt }
	for key, npc in npcs do
		state.N[key] = { Cash = npc.Cash, H = npc.Holdings, B = npc.BoughtAt, P = npc.SnipePlans }
	end
	marketMap:Set("Npcs", state)
end

-- Neuer Host: gespeicherten Zustand übernehmen (falls vorhanden)
local function loadState()
	local ok, state = marketMap:Get("Npcs")
	if not ok or type(state) ~= "table" then
		return
	end
	for key, saved in state.N or {} do
		local npc = npcs[key]
		if npc and type(saved) == "table" and type(saved.Cash) == "number" then
			npc.Cash = saved.Cash
			npc.Holdings = saved.H or {}
			npc.BoughtAt = saved.B or {}
			npc.SnipePlans = saved.P or {}
		end
	end
	rugPlans = state.R or {}
	nextCoinAt = state.Next or 0
end

------------------------------------------------------------------------
-- Handeln
------------------------------------------------------------------------

local function pnlOf(coin, holding): number
	if holding.Cost <= 0 then
		return 0
	end
	local value = Curve.CashForTokens(C, coin.Supply, holding.Amount) * (1 - FEE_TOTAL)
	return value / holding.Cost - 1
end

-- Bestand nach einem Trade (oder unklarem Ausgang) übernehmen
local function setHolding(npc, coinId: string, result)
	if result and result.Amount ~= nil then
		npc.Holdings[coinId] = if result.Amount > 0 then { Amount = result.Amount, Cost = result.Cost or 0 } else nil
		if not npc.Holdings[coinId] then
			npc.BoughtAt[coinId] = nil
		end
	end
end

-- NPCs kaufen nur lebende, nicht gerugte, fremde und nicht zu alte Coins
local function canBuy(npc, coin, t: number): boolean
	return not coin.Dead and not coin.Rugged and coin.CreatorKey ~= npc.Key and t - coin.CreatedAt <= Npc.MaxBuyAge
end

local function buy(npc, coin, minShare: number, maxShare: number): boolean
	local cash = Ledger.FloorCents(npc.Cash * rng:NextNumber(minShare, maxShare))
	if cash < Config.Trade.MinCash then
		return false
	end
	local ok, result = MarketService.NpcTrade(npc.Wallet, coin.Id, { Side = "Buy", Cash = cash })
	if ok then
		npc.Cash = Ledger.FloorCents(npc.Cash - result.Cash)
		npc.BoughtAt[coin.Id] = npc.BoughtAt[coin.Id] or now()
	end
	setHolding(npc, coin.Id, result)
	return ok
end

local function sell(npc, coin, share: number, rug: boolean?): boolean
	if not npc.Holdings[coin.Id] then
		return false
	end
	local ok, result = MarketService.NpcTrade(npc.Wallet, coin.Id, { Side = "Sell", Frac = share, Rug = rug })
	if ok then
		-- Rugpull: 30 % des Erlöses gehen in den Erstattungstopf (bucht der ProtectionService)
		local keep = if rug then 1 - Config.Protection.RugPotShare else 1
		npc.Cash = Ledger.FloorCents(npc.Cash + result.Cash * keep)
	end
	setHolding(npc, coin.Id, result)
	return ok
end

-- Geht alle Positionen durch. rule(coin, pnl, heldFor) gibt Anteil zum Verkaufen zurück (oder nil).
local function trySell(npc, t: number, rule): boolean
	for coinId, holding in npc.Holdings do
		local coin = MarketService.GetCoins()[coinId]
		if coin and not coin.Dead and coin.CreatorKey ~= npc.Key then
			local share = rule(coin, pnlOf(coin, holding), t - (npc.BoughtAt[coinId] or t))
			if share then
				return sell(npc, coin, share)
			end
		end
	end
	return false
end

local function buyable(npc, t: number, filter)
	local list = {}
	for _, coin in MarketService.GetCoins() do
		if canBuy(npc, coin, t) and filter(coin) then
			table.insert(list, coin)
		end
	end
	return list
end

-- Zu alte Coins: NPCs steigen komplett aus, damit alte Coins auslaufen und sterben
local function dumpOldCoin(npc, t: number): boolean
	for coinId in npc.Holdings do
		local coin = MarketService.GetCoins()[coinId]
		if coin and not coin.Dead and coin.CreatorKey ~= npc.Key and t - coin.CreatedAt > Npc.MaxBuyAge then
			return sell(npc, coin, 1)
		end
	end
	return false
end

local STRATEGIES = {
	Sniper = function(npc, t)
		local sold = trySell(npc, t, function(_, pnl, heldFor)
			return if pnl >= 0.5 or pnl <= -0.3 or heldFor >= 120 then 1 else nil
		end)
		if sold then
			return
		end
		local cfg = Npc.Sniper
		local ready = {}
		for _, coin in buyable(npc, t, function(c)
			return t - c.CreatedAt <= cfg.MaxAge and not npc.Holdings[c.Id]
		end) do
			local plan = npc.SnipePlans[coin.Id]
			if plan == nil then
				-- einmal pro Coin würfeln: kaufen ja/nein und nach wie vielen Sekunden
				plan = if rng:NextNumber() < cfg.Chance then rng:NextNumber(cfg.Delay[1], cfg.Delay[2]) else false
				npc.SnipePlans[coin.Id] = plan
			end
			if plan and t - coin.CreatedAt >= plan then
				table.insert(ready, coin)
			end
		end
		local coin = pick(ready)
		if coin then
			npc.SnipePlans[coin.Id] = false -- nur einmal kaufen
			buy(npc, coin, cfg.Share[1], cfg.Share[2])
		end
	end,

	Momentum = function(npc, t)
		local sold = trySell(npc, t, function(coin, pnl)
			return if MarketService.PriceChange(coin, 30) <= -0.08 or pnl >= 1 then 1 else nil
		end)
		if sold then
			return
		end
		local best, bestChange = nil, 0.10
		for _, coin in buyable(npc, t, function()
			return true
		end) do
			local change = MarketService.PriceChange(coin, 30)
			if change >= bestChange then
				best, bestChange = coin, change
			end
		end
		if best then
			buy(npc, best, 0.10, 0.20)
		end
	end,

	Panic = function(npc, t)
		local sold = trySell(npc, t, function(coin, pnl)
			if MarketService.PriceChange(coin, 15) <= -0.10 then
				return 1
			end
			return if pnl >= 0.3 then 0.5 else nil
		end)
		if sold then
			return
		end
		local coin = pick(buyable(npc, t, function(c)
			return c.Holders >= 3
		end))
		if coin then
			buy(npc, coin, 0.05, 0.15)
		end
	end,

	Random = function(npc, t)
		if rng:NextNumber() < 0.5 then
			local held = {}
			for coinId in npc.Holdings do
				local coin = MarketService.GetCoins()[coinId]
				if coin and not coin.Dead and coin.CreatorKey ~= npc.Key then
					table.insert(held, coin)
				end
			end
			local coin = pick(held)
			if coin then
				sell(npc, coin, rng:NextNumber(0.25, 1))
				return
			end
		end
		local coin = pick(buyable(npc, t, function()
			return true
		end))
		if coin then
			buy(npc, coin, 0.05, 0.15)
		end
	end,
}

------------------------------------------------------------------------
-- NPC-Coins und NPC-Rugs
------------------------------------------------------------------------

local function tickerTaken(ticker: string): boolean
	for _, coin in MarketService.GetCoins() do
		if coin.Ticker == ticker then
			return true
		end
	end
	return false
end

local function createNpcCoin()
	local creator = pick(npcList)
	local prefix, noun, ticker
	for _ = 1, 10 do
		prefix = pick(Npc.Prefixes)
		noun = pick(Npc.Nouns)
		ticker = string.upper(string.sub(prefix, 1, 2) .. string.sub(noun[1], 1, 3))
		if not tickerTaken(ticker) then
			break
		end
	end

	local isRug = rng:NextNumber() < Npc.RugChance
	local coin = MarketService.CreateCoin({
		Name = prefix .. " " .. noun[1],
		Ticker = ticker,
		Icon = noun[2],
		Desc = pick(Npc.Descriptions),
		CreatorKey = creator.Key,
		CreatorName = creator.Name,
		License = isRug or rng:NextNumber() < Npc.LicenseBluffChance,
	})
	if not coin then
		return
	end
	creator.Holdings[coin.Id] = { Amount = C.TotalSupply * Config.DevShare, Cost = 0 }

	if isRug then
		-- Rug-Dev kauft am Anfang viel dazu, das er später auf einmal verkauft
		local share = rng:NextNumber(Npc.Rug.DevBuy[1], Npc.Rug.DevBuy[2])
		buy(creator, coin, share, share)
		rugPlans[coin.Id] = {
			CreatorKey = creator.Key,
			StartPrice = MarketService.Price(coin),
			MinGain = rng:NextNumber(Npc.Rug.MinGain[1], Npc.Rug.MinGain[2]),
		}
	end
end

local function checkRugs(t: number)
	local ids = {}
	for coinId in rugPlans do
		table.insert(ids, coinId)
	end
	for _, coinId in ids do
		local plan = rugPlans[coinId]
		local coin = MarketService.GetCoins()[coinId]
		local npc = npcs[plan.CreatorKey]
		if not coin or coin.Dead or not npc then
			rugPlans[coinId] = nil
			continue
		end
		local age = t - coin.CreatedAt
		local gain = MarketService.Price(coin) / plan.StartPrice
		if (age >= Npc.Rug.MinAge and gain >= plan.MinGain) or age >= Npc.Rug.MaxAge then
			rugPlans[coinId] = nil
			-- Ein Klick: alles auf einmal verkaufen, Kurs fällt auf der Kurve (Meldung macht MarketService)
			sell(npc, coin, 1, true)
		end
	end
end

------------------------------------------------------------------------
-- Takt (nur auf dem Host)
------------------------------------------------------------------------

local function act(npc, t: number)
	if not dumpOldCoin(npc, t) then
		STRATEGIES[npc.Kind](npc, t)
	end
end

local function refill(npc, seconds: number)
	if npc.Cash < Npc.StartCash then
		npc.Cash = math.min(Npc.StartCash, npc.Cash + Npc.RefillPerMinute * seconds / 60)
	elseif npc.Cash > Npc.MaxCash then
		npc.Cash = Npc.MaxCash -- Überschuss verschwindet (Geld-Senke)
	end
end

-- Einträge zu gelöschten Coins entfernen (sonst wächst der Speicher bei langen Servern)
local function cleanup(npc)
	local coins = MarketService.GetCoins()
	for _, list in { npc.Holdings, npc.BoughtAt, npc.SnipePlans } do
		for coinId in list do
			if not coins[coinId] then
				list[coinId] = nil
			end
		end
	end
end

local function safe(name: string, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[NpcTrader] " .. name .. ": " .. tostring(err))
	end
end

function NpcTraderService.Init()
	local index = 0
	for _, kind in { "Sniper", "Momentum", "Panic", "Random" } do
		for _ = 1, Npc.Types[kind] or 0 do
			index += 1
			local npc = createNpc(index, kind)
			npcs[npc.Key] = npc
			table.insert(npcList, npc)
		end
	end
end

function NpcTraderService.Start()
	task.spawn(function()
		local wasHost = false
		local lastSave, lastMaintenance, lastCharts, lastFees, lastCleanup = 0, 0, 0, 0, 0
		while true do
			task.wait(Npc.TickInterval)
			if not WorldService.IsHost() then
				wasHost = false
				continue
			end
			local t = now()
			if not wasHost then
				-- gerade Host geworden: Zustand des alten Hosts übernehmen
				wasHost = true
				safe("load", loadState)
				print("[NpcTrader] this server is now the NPC host")
			end

			for _, npc in npcList do
				refill(npc, Npc.TickInterval)
				if rng:NextNumber() < Npc.ActChance then
					safe(npc.Name, act, npc, t)
				end
			end
			safe("rugs", checkRugs, t)

			-- genug gelistete Coins? (mind. StartCoins, neue alle 1–3 Min., Obergrenze wächst mit Spielern)
			local live = MarketService.LiveCoinCount()
			if live < WorldService.MaxLiveCoins() and (live < Npc.StartCoins or t >= nextCoinAt) then
				nextCoinAt = t + rng:NextNumber(Npc.CreateEvery[1], Npc.CreateEvery[2])
				safe("new coin", createNpcCoin)
			end

			if t - lastFees >= W.FeeFlushInterval then
				lastFees = t
				safe("fees", function()
					for key, amount in MarketService.DrainNpcFees() do
						local npc = npcs[key]
						if npc and type(amount) == "number" then
							npc.Cash = Ledger.FloorCents(npc.Cash + amount)
						end
					end
				end)
			end
			if t - lastMaintenance >= W.MaintenanceInterval then
				lastMaintenance = t
				safe("maintenance", MarketService.HostMaintenance)
			end
			if t - lastCharts >= W.ChartSaveInterval then
				lastCharts = t
				safe("charts", MarketService.SaveCharts)
			end
			if t - lastCleanup >= 60 then
				lastCleanup = t
				for _, npc in npcList do
					cleanup(npc)
				end
			end
			if t - lastSave >= W.NpcSaveInterval then
				lastSave = t
				safe("save", saveState)
			end
		end
	end)
	game:BindToClose(function()
		if WorldService.IsHost() then
			pcall(saveState)
		end
	end)
end

return NpcTraderService
