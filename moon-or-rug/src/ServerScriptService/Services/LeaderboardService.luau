-- LeaderboardService (ModuleScript) – ServerScriptService/Services/LeaderboardService
-- Ranglisten (nur echte Spieler, keine NPCs):
--   Gesamt: Vermögen, PNL (realisierter Gewinn), bester Trade
--   Woche / Tag: PNL, bester Trade (starten jeden Montag / jeden Tag neu, UTC)
-- Server-Liste: Spieler auf diesem Server, alle 5 Sek.
-- Weltweit: jeder Server schreibt die Werte seiner Spieler (OrderedDataStore, alle 2 Min.),
-- nur der Host liest die Top 50 und verteilt sie über den Weltmarkt-Speicher an alle Server.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local UserService = game:GetService("UserService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Curve = require(ReplicatedStorage.Shared.BondingCurve)
local Remotes = require(ServerScriptService.Util.Remotes)
local Store = require(ServerScriptService.Util.Store)
local Ledger = require(ServerScriptService.Util.Ledger)
local WorldService = require(ServerScriptService.Services.WorldService)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local MarketService = require(ServerScriptService.Services.MarketService)

local L = Config.Leaderboard
local W = Config.World
local C = Config.Curve
local FEE_TOTAL = Config.Fees.Creator + Config.Fees.Burn

-- Rangliste -> Wert aus den Statistiken
local BOARDS = { "Wealth", "Pnl", "Best", "WeekPnl", "WeekBest", "DayPnl", "DayBest" }

local LeaderboardService = {}
LeaderboardService.HasPass = nil :: ((Player, string) -> boolean)? -- vom MonetizationService (VIP)
LeaderboardService.IsVipUserId = nil :: ((number) -> boolean)?

local marketMap = Store.Map(W.MarketMap, W.Expiration)
local event: RemoteEvent
local worldBoards = nil -- letzte weltweite Listen
local sentWorld = {} -- [player] = true: hat die aktuelle weltweite Liste schon
local lastSubmitted = {} -- [player] = { [Speichername] = Wert }
local orderedStores = {}
local nameCache = {} -- [userId] = Anzeigename
local LEGEND = Config.Prestige.LegendLevel
-- [userId] = true ab Level 40 (pcall: unveröffentlichte Place in Studio hat keinen DataStore)
local okLegend, legendStore = pcall(DataStoreService.GetDataStore, DataStoreService, "MoR_Legends_v1")
if not okLegend then
	legendStore = nil
end
local legendCache = {} -- [userId] = { Is, At }
local legendLookups = 0 -- pro Lesedurchgang begrenzt (DataStore-Budget)

-- Legend-Status beliebiger Spieler (weltweite Rangliste), Zwischenspeicher 30 Min., Legend bleibt Legend
local function isLegend(userId: number): boolean
	local player = Players:GetPlayerByUserId(userId)
	if player and PlayerDataService.GetWallet(player) then
		return PlayerDataService.GetStats(player).Level >= LEGEND
	end
	local cached = legendCache[userId]
	if cached and (cached.Is or os.clock() - cached.At < 1800) then
		return cached.Is
	end
	if not legendStore or legendLookups >= 40 then
		return if cached then cached.Is else false
	end
	legendLookups += 1
	local ok, value = pcall(function()
		return legendStore:GetAsync(tostring(userId))
	end)
	if not ok then
		return if cached then cached.Is else false
	end
	legendCache[userId] = { Is = value == true, At = os.clock() }
	return value == true
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Vermögen = Cash + Verkaufswert aller Coins (nach Gebühr)
local function wealth(player: Player): number
	local wallet = PlayerDataService.GetWallet(player)
	if not wallet then
		return 0
	end
	local total = wallet.Cash
	local coins = MarketService.GetCoins()
	for coinId, holding in PlayerDataService.GetHoldings(player) do
		local coin = coins[coinId]
		if coin then
			total += Curve.CashForTokens(C, coin.Supply, holding.Amount) * (1 - FEE_TOTAL)
		end
	end
	return total
end

LeaderboardService.Wealth = wealth

local function values(player: Player)
	local stats = PlayerDataService.GetStats(player)
	return {
		Wealth = wealth(player),
		Pnl = stats.Pnl,
		Best = stats.Best,
		WeekPnl = stats.WeekPnl,
		WeekBest = stats.WeekBest,
		DayPnl = stats.DayPnl,
		DayBest = stats.DayBest,
	}
end

-- Name der weltweiten Rangliste (Woche/Tag bekommen eine eigene Liste pro Zeitraum)
local function storeName(board: string): string
	local day, week = Ledger.PeriodKeys(now())
	if string.sub(board, 1, 4) == "Week" then
		return "MoR_LB_" .. board .. "_" .. week
	elseif string.sub(board, 1, 3) == "Day" then
		return "MoR_LB_" .. board .. "_" .. day
	end
	return "MoR_LB_" .. board
end

local function ordered(name: string)
	local store = orderedStores[name]
	if not store then
		store = DataStoreService:GetOrderedDataStore(name)
		orderedStores[name] = store
	end
	return store
end

------------------------------------------------------------------------
-- Server-Liste
------------------------------------------------------------------------

local function serverBoards()
	local boards = {}
	for _, board in BOARDS do
		boards[board] = {}
	end
	for _, player in PlayerDataService.LoadedPlayers() do
		local v = values(player)
		for _, board in BOARDS do
			table.insert(boards[board], {
				N = player.DisplayName,
				U = player.UserId,
				P = if LeaderboardService.HasPass and LeaderboardService.HasPass(player, "Vip") then true else nil,
				G = if PlayerDataService.GetStats(player).Level >= LEGEND then true else nil, -- Legend (👑)
				V = math.floor(v[board]),
			})
		end
	end
	for _, list in boards do
		table.sort(list, function(a, b)
			return a.V > b.V
		end)
		while #list > L.Size do
			table.remove(list)
		end
	end
	return boards
end

------------------------------------------------------------------------
-- Weltweit
------------------------------------------------------------------------

-- Eigene Werte schreiben (nur geänderte, nur positive)
local function submit(player: Player)
	if Store.LocalMode or not PlayerDataService.GetWallet(player) then
		return
	end
	local v = values(player)
	local sent = lastSubmitted[player] or {}
	lastSubmitted[player] = sent
	-- Legend-Status für die weltweite Liste (nur einmal, wenn erreicht)
	if legendStore and PlayerDataService.GetStats(player).Level >= LEGEND and not sent.Legend then
		local ok = pcall(function()
			legendStore:SetAsync(tostring(player.UserId), true)
		end)
		sent.Legend = ok
	end
	for _, board in BOARDS do
		local value = math.max(0, math.floor(v[board]))
		local name = storeName(board)
		if value > 0 and sent[name] ~= value then
			local ok = pcall(function()
				ordered(name):SetAsync(tostring(player.UserId), value)
			end)
			if ok then
				sent[name] = value
			end
		end
	end
end

-- Host: Top 50 aller Ranglisten lesen, Namen holen, im Weltmarkt-Speicher teilen
local function readWorld()
	legendLookups = 0
	local boards, missing = {}, {}
	for _, board in BOARDS do
		local ok, page = pcall(function()
			return ordered(storeName(board)):GetSortedAsync(false, L.Size):GetCurrentPage()
		end)
		local list = {}
		if ok then
			for _, entry in page do
				local userId = tonumber(entry.key)
				if userId then
					table.insert(list, { U = userId, V = entry.value })
					if not nameCache[userId] then
						missing[userId] = true
					end
				end
			end
		end
		boards[board] = list
	end
	local ids = {}
	for userId in missing do
		table.insert(ids, userId)
	end
	if #ids > 0 then
		local ok, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync(ids)
		end)
		if ok then
			for _, info in infos do
				nameCache[info.Id] = info.DisplayName
			end
		end
	end
	for _, list in boards do
		for _, entry in list do
			entry.N = nameCache[entry.U] or ("Player " .. entry.U) -- U bleibt: Creator-Abzeichen im Client
			if LeaderboardService.IsVipUserId and LeaderboardService.IsVipUserId(entry.U) then
				entry.P = true -- VIP (⭐)
			end
			if isLegend(entry.U) then
				entry.G = true -- Legend (👑)
			end
		end
	end
	marketMap:Set("Leaderboards", { Boards = boards, At = now() })
end

local function fetchWorld()
	local ok, data = marketMap:Get("Leaderboards")
	if ok and type(data) == "table" and data.Boards then
		worldBoards = data.Boards
		sentWorld = {} -- alle bekommen die neue Liste
	end
end

------------------------------------------------------------------------

local function loop(name: string, interval: number, fn: () -> ())
	task.spawn(function()
		while true do
			task.wait(interval)
			local ok, err = pcall(fn)
			if not ok then
				warn("[Leaderboard] " .. name .. ": " .. tostring(err))
			end
		end
	end)
end

function LeaderboardService.Init()
	event = Remotes.Event("Leaderboard")
	Players.PlayerRemoving:Connect(function(player)
		pcall(submit, player) -- letzter Stand (läuft, solange die Daten noch geladen sind)
		lastSubmitted[player] = nil
		sentWorld[player] = nil
	end)
end

function LeaderboardService.Start()
	-- Server-Liste an alle; weltweite Liste an alle, die sie noch nicht haben
	loop("server", L.ServerInterval, function()
		event:FireAllClients({ Server = serverBoards() })
		if worldBoards then
			for _, player in PlayerDataService.LoadedPlayers() do
				if not sentWorld[player] then
					sentWorld[player] = true
					event:FireClient(player, { World = worldBoards })
				end
			end
		end
	end)
	loop("submit", L.SubmitInterval, function()
		for _, player in PlayerDataService.LoadedPlayers() do
			submit(player)
			task.wait(0.2) -- verteilt, nicht alle auf einmal
		end
	end)
	if not Store.LocalMode then
		loop("world read", L.WorldReadInterval, function()
			if WorldService.IsHost() then
				readWorld()
			end
		end)
		loop("world share", L.WorldShareInterval, fetchWorld)
		task.spawn(fetchWorld)
	end
end

return LeaderboardService
