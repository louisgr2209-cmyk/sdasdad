-- ProtectionService (ModuleScript) – ServerScriptService/Services/ProtectionService
-- Schutz vor Bankrott (Phase 5):
--  * Mindestgeld: Vermögen unter 100 -> alle 10 Min. 250 Cash (Zeit in der Geldbörse: Rejoin hilft nicht)
--  * Daily Reward: Tag 1..7 (500 bis 5.000), Lücke -> Tag 1
--  * Stop-Loss (ab Level 3): online verkauft der eigene Server sofort,
--    offline verkauft der Host (wenn der Stop seit 15 Sek. erreicht ist), Cash ins Postfach
--  * Rug-Versicherung (ab Level 5, Schalter pro Coin) + Anfänger-Erstattung (unter Level 5):
--    nach einem Rugpull aus den Töpfen bezahlt, ins Postfach der Spieler
-- Alle Geldbuchungen laufen über den Ledger: nie doppelt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ServerScriptService.Util.Remotes)
local RateLimiter = require(ServerScriptService.Util.RateLimiter)
local Store = require(ServerScriptService.Util.Store)
local Ledger = require(ServerScriptService.Util.Ledger)
local WorldService = require(ServerScriptService.Services.WorldService)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local MarketService = require(ServerScriptService.Services.MarketService)
local LeaderboardService = require(ServerScriptService.Services.LeaderboardService)

local P = Config.Protection
local W = Config.World

local ProtectionService = {}
ProtectionService.HasPass = nil :: ((Player, string) -> boolean)? -- vom MonetizationService (Doppelter Daily)

local marketMap = Store.Map(W.MarketMap, W.Expiration)
local inboxMap = Store.Map(W.InboxMap, W.CoinExpiration)
local limiter = RateLimiter.new(3)
local pendingStops = {} -- [player] = { [coinId] = true }: Stop-Loss-Verkauf läuft schon
local hitSince = {} -- Host: ["coinId|key"] = Zeit, seit der Stop erreicht ist

local function now(): number
	return workspace:GetServerTimeNow()
end

local function level(player: Player): number
	return PlayerDataService.GetStats(player).Level
end

------------------------------------------------------------------------
-- Anfragen vom Client
------------------------------------------------------------------------

local function onClaimDaily(player: Player)
	if not limiter:Allow(player) or not PlayerDataService.GetWallet(player) then
		return
	end
	local day = Ledger.PeriodKeys(now())
	local ok, result = PlayerDataService.WalletUpdate(player, Ledger.WalletDaily, {
		Job = WorldService.JobId,
		Day = day,
		Multiplier = if ProtectionService.HasPass and ProtectionService.HasPass(player, "DoubleDaily") then 2 else 1,
	})
	if ok and result and result.Ok then
		PlayerDataService.Notify(
			player,
			true,
			string.format("🎁 Day %d reward: +%s Cash", result.Streak, tostring(result.Amount))
		)
	else
		PlayerDataService.Notify(player, false, (result and result.Error) or "Please try again")
	end
	PlayerDataService.PushState(player)
end

-- index: 0 = aus, 1..4 = Config.Protection.StopLossLevels
local function onSetStopLoss(player: Player, coinId: any, index: any)
	if not limiter:Allow(player) or not PlayerDataService.GetWallet(player) then
		return
	end
	if typeof(coinId) ~= "string" or #coinId > 20 or typeof(index) ~= "number" then
		return
	end
	index = math.floor(index)
	if index < 0 or index > #P.StopLossLevels then
		return
	end
	if level(player) < P.StopLossMinLevel then
		PlayerDataService.Notify(player, false, "Stop-loss unlocks at level " .. P.StopLossMinLevel)
		return
	end
	if not PlayerDataService.GetHolding(player, coinId) then
		PlayerDataService.Notify(player, false, "You don't own this coin")
		return
	end
	local value = if index == 0 then nil else P.StopLossLevels[index]
	local ok, err = MarketService.SetStopLoss(player, coinId, value)
	if ok then
		PlayerDataService.SetStopLossLocal(player, coinId, value)
		PlayerDataService.Notify(
			player,
			true,
			if value then string.format("🛑 Stop-loss set: sells all at -%d%%", math.floor(value * 100 + 0.5)) else "Stop-loss off"
		)
	else
		PlayerDataService.Notify(player, false, err or "Please try again")
	end
	PlayerDataService.PushState(player)
end

local function onSetInsurance(player: Player, coinId: any, on: any)
	if not limiter:Allow(player) or not PlayerDataService.GetWallet(player) then
		return
	end
	if typeof(coinId) ~= "string" or #coinId > 20 or typeof(on) ~= "boolean" then
		return
	end
	if level(player) < P.InsuranceMinLevel then
		PlayerDataService.Notify(player, false, "Rug insurance unlocks at level " .. P.InsuranceMinLevel)
		return
	end
	local ok = PlayerDataService.WalletUpdate(player, Ledger.WalletSetInsure, {
		Job = WorldService.JobId,
		Coin = coinId,
		On = on,
	})
	if ok then
		PlayerDataService.Notify(
			player,
			true,
			if on
				then string.format(
					"🛡 Insurance ON: +%d%% on buys, %d%% back if rugged",
					math.floor(P.InsurancePremium * 100 + 0.5),
					math.floor(P.InsurancePayout * 100 + 0.5)
				)
				else "🛡 Insurance off"
		)
	end
	PlayerDataService.PushState(player)
end

------------------------------------------------------------------------
-- Mindestgeld
------------------------------------------------------------------------

local function stipendTick()
	for _, player in PlayerDataService.LoadedPlayers() do
		if LeaderboardService.Wealth(player) < P.StipendBelow then
			local ok, result = PlayerDataService.WalletUpdate(player, Ledger.WalletStipend, {
				Job = WorldService.JobId,
				Now = now(),
				Amount = P.StipendAmount,
				Interval = P.StipendInterval,
			})
			if ok and result and result.Ok then
				PlayerDataService.Notify(player, true, string.format("💸 Starter help: +%d Cash", P.StipendAmount))
				PlayerDataService.PushState(player)
			end
		end
	end
end

------------------------------------------------------------------------
-- Stop-Loss
------------------------------------------------------------------------

-- Online: eigener Server prüft jede Sekunde die Positionen seiner Spieler
local function onlineStopTick()
	local coins = MarketService.GetCoins()
	for _, player in PlayerDataService.LoadedPlayers() do
		for coinId, holding in PlayerDataService.GetHoldings(player) do
			local coin = coins[coinId]
			if holding.SL and coin and holding.Cost > 0 then
				local value = MarketService.PositionValue(coin, holding.Amount)
				local pending = pendingStops[player] or {}
				pendingStops[player] = pending
				if value <= holding.Cost * (1 - holding.SL) and not pending[coinId] then
					pending[coinId] = true
					local queued = MarketService.QueueSell(player, coinId, "🛑 Stop-loss: ")
					if queued then
						task.delay(5, function()
							pending[coinId] = nil
						end)
					else
						pending[coinId] = nil
					end
				end
			end
		end
	end
end

-- Offline: Host prüft Coins mit Stop-Loss-Aufträgen und verkauft, wenn der Stop seit 15 Sek. erreicht ist
-- (online-Spieler verkauft ihr eigener Server schon nach ca. 1 Sek.)
local function hostStopTick()
	if not WorldService.IsHost() then
		hitSince = {}
		return
	end
	local ids = {}
	for id, coin in MarketService.GetCoins() do
		if (coin.StopLossCount or 0) > 0 then
			table.insert(ids, id)
		end
	end
	local t = now()
	local stillHit = {}
	for _, coinId in ids do
		local value = MarketService.ReadCoin(coinId)
		if value and value.SL then
			for key in value.SL do
				if Ledger.StopLossHit(value, key) then
					local id = coinId .. "|" .. key
					stillHit[id] = hitSince[id] or t
					if t - stillHit[id] >= P.StopLossOfflineDelay then
						stillHit[id] = nil
						local result = MarketService.StopLossExec(coinId, key)
						if result then
							-- ohne Wiederholung: im Zweifel nichts, aber nie doppelt
							inboxMap:UpdateOnce("u_" .. key, Ledger.InboxAdd, {
								Adds = { Cash = result.Cash, Profit = result.Profit, SL = result.Cash },
							})
						end
					end
				end
			end
		end
	end
	hitSince = stillHit
end

------------------------------------------------------------------------
-- Rug: Versicherung + Anfänger-Erstattung
------------------------------------------------------------------------

local function onRug(_coin, result)
	local comp = result.Comp or {}
	-- Spieler-Rug: Anteil schon im Ledger abgezogen (result.Pot); NPC-Rug: 30 % vom Erlös
	local share = result.Pot or (result.Cash or 0) * P.RugPotShare
	if next(comp) == nil and share <= 0 then
		return
	end
	local day = Ledger.PeriodKeys(now())
	-- ohne Wiederholung: Töpfe werden nie doppelt belastet
	local ok, payouts = marketMap:UpdateOnce("Pots", Ledger.PotsPay, {
		Comp = comp,
		AddRef = share,
		Day = day,
		TopUp = P.DailyTopUp,
	})
	if not ok or type(payouts) ~= "table" then
		return
	end
	for key, amount in payouts do
		inboxMap:UpdateOnce("u_" .. key, Ledger.InboxAdd, { Adds = { Cash = amount, Refund = amount } })
		local player = PlayerDataService.GetPlayerByKey(key)
		if player then
			task.delay(1, function()
				-- online auf diesem Server: Postfach gleich leeren (sonst spätestens nach 1 Min.)
				PlayerDataService.DrainInbox(player)
			end)
		end
	end
end

------------------------------------------------------------------------

local function loop(name: string, interval: number, fn: () -> ())
	task.spawn(function()
		while true do
			task.wait(interval)
			local ok, err = pcall(fn)
			if not ok then
				warn("[Protection] " .. name .. ": " .. tostring(err))
			end
		end
	end)
end

function ProtectionService.Init()
	Remotes.Event("ClaimDaily").OnServerEvent:Connect(onClaimDaily)
	Remotes.Event("SetStopLoss").OnServerEvent:Connect(onSetStopLoss)
	Remotes.Event("SetInsurance").OnServerEvent:Connect(onSetInsurance)
	MarketService.RugHandler = onRug
	Players.PlayerRemoving:Connect(function(player)
		limiter:Remove(player)
		pendingStops[player] = nil
	end)
end

function ProtectionService.Start()
	loop("stipend", 30, stipendTick)
	loop("stop-loss", 1, onlineStopTick)
	loop("host stop-loss", P.StopLossHostInterval, hostStopTick)
end

return ProtectionService
