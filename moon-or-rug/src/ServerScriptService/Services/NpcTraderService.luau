-- NpcTraderService (ModuleScript) – ServerScriptService/Services/NpcTraderService
-- 20 NPC-Trader halten den Markt am Leben. Sie handeln über dieselben Regeln wie Spieler
-- (MarketService.Buy/Sell, gleiche Gebühren). Sie erstellen alle 1–3 Min. einen Coin,
-- ca. 10 % davon sind NPC-Rugs.
--
-- Typen:
--   Sniper   kauft ganz neue Coins (< 30 Sek.), verkauft bei +50 %, -30 % oder nach 2 Min.
--   Momentum kauft, was gerade steigt, verkauft, wenn es fällt
--   Panik    kauft beliebte Coins, verkauft alles bei schnellem Fall
--   Zufall   kauft/verkauft zufällig kleine Beträge
-- Alle: kaufen nur Coins < 15 Min. und steigen danach aus (so sterben alte Coins).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Curve = require(ReplicatedStorage.Shared.BondingCurve)
local MarketService = require(ServerScriptService.Services.MarketService)

local Npc = Config.Npc
local C = Config.Curve
local FEE_TOTAL = Config.Fees.Creator + Config.Fees.Burn

local NpcTraderService = {}

local npcs = {} -- [key] = npc
local npcList = {}
local rugPlans = {} -- [coinId] = { CreatorKey, StartPrice, MinGain } (geheim, nur Server)
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
-- Geldbörse (gleiche Form wie bei Spielern)
------------------------------------------------------------------------

local function createNpc(index: number, kind: string)
	local npc = {
		Key = "npc:" .. index,
		Name = Npc.Names[index] or ("Trader" .. index),
		Kind = kind,
		Cash = Npc.StartCash,
		BoughtAt = {}, -- [coinId] = Zeit des ersten Kaufs
	}
	npc.Wallet = {
		Key = npc.Key,
		Name = npc.Name,
		IsNpc = true,
		GetCash = function()
			return npc.Cash
		end,
		AddCash = function(delta: number)
			local newCash = math.floor((npc.Cash + delta) * 100 + 1e-6) / 100
			if newCash < 0 then
				return false
			end
			npc.Cash = newCash
			return true
		end,
	}
	return npc
end

function NpcTraderService.Wallet(key: string)
	local npc = npcs[key]
	return npc and npc.Wallet
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

-- NPCs kaufen nur lebende, nicht gerugte, fremde und nicht zu alte Coins
local function canBuy(npc, coin, t: number): boolean
	return not coin.Dead
		and not coin.Rugged
		and coin.CreatorKey ~= npc.Key
		and t - coin.CreatedAt <= Npc.MaxBuyAge
end

local function buy(npc, coin, minShare: number, maxShare: number): boolean
	local ok = MarketService.Buy(npc.Wallet, coin.Id, npc.Cash * rng:NextNumber(minShare, maxShare))
	if ok and not npc.BoughtAt[coin.Id] then
		npc.BoughtAt[coin.Id] = now()
	end
	return ok
end

local function sell(npc, coin, share: number): boolean
	local holding = coin.Holders[npc.Key]
	if not holding then
		return false
	end
	local amount = if share >= 1 then holding.Amount else holding.Amount * share
	local ok = MarketService.Sell(npc.Wallet, coin.Id, amount)
	if ok and not coin.Holders[npc.Key] then
		npc.BoughtAt[coin.Id] = nil
	end
	return ok
end

-- Geht alle Positionen durch. rule(coin, pnl, heldFor) gibt Anteil zum Verkaufen zurück (oder nil).
local function trySell(npc, t: number, rule): boolean
	for _, coin in MarketService.GetCoins() do
		local holding = coin.Holders[npc.Key]
		if holding and not coin.Dead and coin.CreatorKey ~= npc.Key then
			local share = rule(coin, pnlOf(coin, holding), t - (npc.BoughtAt[coin.Id] or t))
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
	for _, coin in MarketService.GetCoins() do
		local tooOld = t - coin.CreatedAt > Npc.MaxBuyAge
		if tooOld and coin.Holders[npc.Key] and not coin.Dead and coin.CreatorKey ~= npc.Key then
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
		local coin = pick(buyable(npc, t, function(c)
			return t - c.CreatedAt <= 30 and not c.Holders[npc.Key]
		end))
		if coin then
			buy(npc, coin, 0.10, 0.25)
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
			return c.HolderCount >= 3
		end))
		if coin then
			buy(npc, coin, 0.05, 0.15)
		end
	end,

	Random = function(npc, t)
		if rng:NextNumber() < 0.5 then
			local held = {}
			for _, coin in MarketService.GetCoins() do
				if coin.Holders[npc.Key] and not coin.Dead and coin.CreatorKey ~= npc.Key then
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
	if MarketService.LiveCoinCount() >= Npc.MaxLiveCoins then
		return
	end
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
		Description = pick(Npc.Descriptions),
		CreatorKey = creator.Key,
		CreatorName = creator.Name,
		CreatorHasLicense = isRug or rng:NextNumber() < Npc.LicenseBluffChance,
	})

	if isRug then
		-- Rug-Dev kauft am Anfang viel dazu, das er später auf einmal verkauft
		local share = rng:NextNumber(Npc.Rug.DevBuy[1], Npc.Rug.DevBuy[2])
		MarketService.Buy(creator.Wallet, coin.Id, creator.Cash * share)
		rugPlans[coin.Id] = {
			CreatorKey = creator.Key,
			StartPrice = MarketService.Price(coin),
			MinGain = rng:NextNumber(Npc.Rug.MinGain[1], Npc.Rug.MinGain[2]),
		}
	end
end

local function checkRugs(t: number)
	for coinId, plan in rugPlans do
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
			-- Ein Klick: alles auf einmal verkaufen, Kurs fällt auf der Kurve
			if sell(npc, coin, 1) then
				MarketService.MarkRugged(coinId, npc.Name)
			end
		end
	end
end

------------------------------------------------------------------------
-- Takt
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
	for _ = 1, Npc.StartCoins do
		createNpcCoin()
	end

	task.spawn(function()
		local nextCoinAt = now() + rng:NextNumber(Npc.CreateEvery[1], Npc.CreateEvery[2])
		while true do
			task.wait(Npc.TickInterval)
			local t = now()
			for _, npc in npcList do
				refill(npc, Npc.TickInterval)
				if rng:NextNumber() < Npc.ActChance then
					local ok, err = pcall(act, npc, t)
					if not ok then
						warn("[NpcTrader] " .. npc.Name .. ": " .. tostring(err))
					end
				end
			end
			-- pcall: ein Fehler darf nie die NPC-Schleife anhalten
			local ok, err = pcall(checkRugs, t)
			if not ok then
				warn("[NpcTrader] rugs: " .. tostring(err))
			end
			if t >= nextCoinAt then
				nextCoinAt = t + rng:NextNumber(Npc.CreateEvery[1], Npc.CreateEvery[2])
				ok, err = pcall(createNpcCoin)
				if not ok then
					warn("[NpcTrader] new coin: " .. tostring(err))
				end
			end
		end
	end)
end

return NpcTraderService
