-- CreatorService (ModuleScript) – ServerScriptService/Services/CreatorService
-- Creator-Programm:
--  * Admins (Config.Creator.AdminIds, in Studio jeder) vergeben/entziehen Stufen per Roblox-Name.
--    Jede Aktion wird geloggt (Zeit, Admin, Ziel, Stufe). Server prüft JEDE Anfrage.
--  * Creator-Liste im DataStore; alle Server holen sie jede Minute -> Freischaltung kommt überall an,
--    auch für Spieler, die offline waren (Auszahlung beim nächsten Join).
--  * Belohnung je Stufe genau einmal (Ledger.WalletCreatorGrant), übersprungene Stufen zahlen nichts nach.
--  * Gold: eigener Creator-Code (einmal wählbar, gefiltert, eindeutig). Einlösen: jeder Spieler einmal,
--    Konto mind. 7 Tage, mind. 30 Min. gespielt, nie eigener Code. Spieler +2.000, Creator +500 (max. 50/Tag).
--  * Entziehen: Titel/Abzeichen/Farben/Highlight/Code weg, ausgezahltes Cash bleibt.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local CreatorStyle = require(ReplicatedStorage.Shared.CreatorStyle)
local Remotes = require(ServerScriptService.Util.Remotes)
local RateLimiter = require(ServerScriptService.Util.RateLimiter)
local Store = require(ServerScriptService.Util.Store)
local Ledger = require(ServerScriptService.Util.Ledger)
local TextFilter = require(ServerScriptService.Util.TextFilter)
local WorldService = require(ServerScriptService.Services.WorldService)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)

local CR = Config.Creator
local W = Config.World

local CreatorService = {}

local listStore = Store.Data("MoR_Creators_v1") -- "list": { [userId] = Eintrag }, "log": Admin-Aktionen
local codeStore = Store.Data("MoR_CreatorCodes_v1") -- [CODE] = { U = userId }
local inboxMap = Store.Map(W.InboxMap, W.CoinExpiration)
local limiter = RateLimiter.new(1, 2)

local creators = {} -- [userId-String] = { T = Stufe, N, V, C = Code, R = Einlösungen, RD, RC, At, By }
local creatorsEvent: RemoteEvent
local adminResult: RemoteEvent

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Monats-Nummer (UTC) für den Gratis-Coin der Gold-Creator
local function monthKey(t: number): number
	local date = os.date("!*t", math.floor(t))
	return date.year * 12 + date.month
end

function CreatorService.IsAdmin(player: Player): boolean
	return RunService:IsStudio() or table.find(CR.AdminIds, player.UserId) ~= nil
end

function CreatorService.TierOf(key: string?): number
	local entry = key and creators[key]
	return if entry then entry.T or 0 else 0
end

-- Name mit Creator-Abzeichen (für Ticker-Meldungen)
function CreatorService.DisplayName(key: string?, name: string): string
	return CreatorStyle.Name(name, CreatorService.TierOf(key))
end

-- Gold-Creator: Monat für den Gratis-Coin (oder nil, wenn kein Gold oder schon benutzt)
function CreatorService.FreeCoinMonth(player: Player, wallet): number?
	if CreatorService.TierOf(tostring(player.UserId)) < 4 then
		return nil
	end
	local month = monthKey(now())
	return if wallet.FCM ~= month then month else nil
end

-- Zusatz-Infos für den Client (Teil des PlayerState)
function CreatorService.ExtraState(player: Player)
	local key = tostring(player.UserId)
	local entry = creators[key]
	local wallet = PlayerDataService.GetWallet(player)
	local st = (wallet and wallet.St) or {}
	local tier = CreatorService.TierOf(key)
	return {
		Tier = tier,
		Code = if tier >= 4 and entry then entry.C else nil,
		Uses = if entry then entry.R or 0 else 0,
		Redeemed = st.RC,
		PlaytimeLeft = math.max(0, CR.MinPlaytimeMinutes * 60 - (st.PT or 0)),
		AccountOk = player.AccountAge >= CR.MinAccountAgeDays,
		IsAdmin = CreatorService.IsAdmin(player),
		FreeCoin = wallet ~= nil and CreatorService.FreeCoinMonth(player, wallet) ~= nil,
	}
end

------------------------------------------------------------------------
-- Liste laden, Stufen auszahlen, an Clients schicken
------------------------------------------------------------------------

local function publicTiers()
	local tiers = {}
	for key, entry in creators do
		if (entry.T or 0) > 0 then
			tiers[key] = entry.T
		end
	end
	return tiers
end

-- Stufe auszahlen, falls noch nicht geschehen (genau einmal, siehe Ledger)
local function applyGrant(player: Player)
	local wallet = PlayerDataService.GetWallet(player)
	local tier = CreatorService.TierOf(tostring(player.UserId))
	if not wallet or tier <= 0 or ((wallet.Cr and wallet.Cr.Max) or 0) >= tier then
		return
	end
	local cfg = CR.Tiers[tier]
	local ok, result = PlayerDataService.WalletUpdate(player, Ledger.WalletCreatorGrant, {
		Job = WorldService.JobId,
		Tier = tier,
		Cash = cfg.Cash,
		FreeBoosts = cfg.FreeBoosts,
	})
	if ok and result and result.Ok then
		PlayerDataService.Notify(
			player,
			true,
			string.format("🎬 Creator %s unlocked!%s", cfg.Name, if cfg.Cash > 0 then " +" .. cfg.Cash .. " Cash" else "")
		)
		PlayerDataService.PushState(player)
	end
end

local function refresh()
	local ok, list = listStore:Get("list")
	if not ok then
		return
	end
	creators = if type(list) == "table" then list else {}
	creatorsEvent:FireAllClients(publicTiers())
	for _, player in PlayerDataService.LoadedPlayers() do
		task.spawn(applyGrant, player)
	end
end

local function appendLog(entry)
	listStore:Update("log", function(log)
		log = if type(log) == "table" then log else {}
		table.insert(log, entry)
		while #log > CR.LogKeep do
			table.remove(log, 1)
		end
		return log
	end)
end

local function lastLog(count: number)
	local ok, log = listStore:Get("log")
	local result = {}
	if ok and type(log) == "table" then
		for i = #log, math.max(1, #log - count + 1), -1 do
			table.insert(result, log[i])
		end
	end
	return result
end

------------------------------------------------------------------------
-- Admin
------------------------------------------------------------------------

-- action: "grant" / "revoke", name: Roblox-Name, tier: 1..4, video: Link (optional, nur Admins sehen ihn)
local function onAdminAction(player: Player, action: any, name: any, tier: any, video: any)
	if not CreatorService.IsAdmin(player) then
		warn("[Creator] non-admin tried an admin action: " .. player.Name .. " (" .. player.UserId .. ")")
		return
	end
	if not limiter:Allow(player) then
		return
	end
	local function reply(ok: boolean, message: string)
		adminResult:FireClient(player, { Ok = ok, Message = message, Log = lastLog(10) })
	end
	if (action ~= "grant" and action ~= "revoke") or typeof(name) ~= "string" then
		return reply(false, "Invalid request")
	end
	name = string.gsub(name, "%s", "")
	if not string.match(name, "^[%w_]+$") or #name < 3 or #name > 20 then
		return reply(false, "Enter a valid Roblox name")
	end
	if action == "grant" and (typeof(tier) ~= "number" or not CR.Tiers[tier]) then
		return reply(false, "Pick a tier")
	end
	if video ~= nil and (typeof(video) ~= "string" or #video > 200) then
		return reply(false, "Video link too long")
	end
	local okId, userId = pcall(function()
		return Players:GetUserIdFromNameAsync(name)
	end)
	if not okId or not userId then
		return reply(false, "Roblox user not found: " .. name)
	end
	local key = tostring(userId)
	local okSave = listStore:Update("list", function(list)
		list = if type(list) == "table" then list else {}
		local entry = list[key] or {}
		entry.N = name
		entry.At = now()
		entry.By = player.Name
		if action == "grant" then
			entry.T = tier
			if video and video ~= "" then
				entry.V = video
			end
		else
			entry.T = 0 -- entzogen: Anzeige + Code weg, ausgezahltes Cash bleibt
		end
		list[key] = entry
		return list
	end)
	if not okSave then
		return reply(false, "Saving failed – please try again")
	end
	local tierName = if action == "grant" then CR.Tiers[tier].Name else "-"
	appendLog({ At = now(), A = player.Name, T = name, U = userId, Act = action, Tier = tierName, V = video })
	print(string.format("[Creator] %s: %s -> %s (%s) by %s", action, name, tierName, key, player.Name))
	refresh()
	reply(true, if action == "grant" then name .. " is now " .. tierName else name .. " revoked")
end

local function onAdminLog(player: Player)
	if not CreatorService.IsAdmin(player) or not limiter:Allow(player) then
		return nil
	end
	return lastLog(10)
end

------------------------------------------------------------------------
-- Creator-Code
------------------------------------------------------------------------

local function onSetCode(player: Player, code: any)
	if not limiter:Allow(player) or not PlayerDataService.GetWallet(player) then
		return
	end
	local key = tostring(player.UserId)
	local entry = creators[key]
	if CreatorService.TierOf(key) < 4 then
		return PlayerDataService.Notify(player, false, "Creator codes are for Gold creators")
	end
	if entry and entry.C then
		return PlayerDataService.Notify(player, false, "You already chose your code: " .. entry.C)
	end
	local clean, err = TextFilter.CheckCode(player, code)
	if not clean then
		return PlayerDataService.Notify(player, false, err or "Invalid code")
	end
	local taken = false
	local ok = codeStore:Update(clean, function(old)
		if type(old) == "table" and old.U ~= player.UserId then
			taken = true
			return nil -- gehört schon jemand anderem: nichts ändern
		end
		taken = false
		return { U = player.UserId }
	end)
	if not ok then
		return PlayerDataService.Notify(player, false, "Please try again")
	end
	if taken then
		return PlayerDataService.Notify(player, false, "Code " .. clean .. " is taken – pick another")
	end
	listStore:Update("list", function(list)
		list = if type(list) == "table" then list else {}
		if list[key] then
			list[key].C = clean
		end
		return list
	end)
	refresh()
	PlayerDataService.Notify(player, true, "🎬 Your creator code is " .. clean)
	PlayerDataService.PushState(player)
end

local function onRedeem(player: Player, code: any)
	if not limiter:Allow(player) then
		return
	end
	local wallet = PlayerDataService.GetWallet(player)
	if not wallet then
		return
	end
	local st = wallet.St or {}
	local clean = TextFilter.NormalizeCode(code)
	if not clean then
		return PlayerDataService.Notify(player, false, "Code not found")
	end
	if st.RC then
		return PlayerDataService.Notify(player, false, "You already used a creator code")
	end
	if player.AccountAge < CR.MinAccountAgeDays then
		return PlayerDataService.Notify(
			player,
			false,
			string.format("Your Roblox account must be at least %d days old", CR.MinAccountAgeDays)
		)
	end
	local left = CR.MinPlaytimeMinutes * 60 - (st.PT or 0)
	if left > 0 then
		return PlayerDataService.Notify(player, false, string.format("Play %d more minutes first", math.ceil(left / 60)))
	end
	local ok, owner = codeStore:Get(clean)
	if not ok then
		return PlayerDataService.Notify(player, false, "Please try again")
	end
	if type(owner) ~= "table" or not owner.U then
		return PlayerDataService.Notify(player, false, "Code not found")
	end
	local creatorKey = tostring(owner.U)
	if creatorKey == tostring(player.UserId) then
		return PlayerDataService.Notify(player, false, "You can't use your own code")
	end
	if CreatorService.TierOf(creatorKey) < 4 then
		return PlayerDataService.Notify(player, false, "This code is not active")
	end

	-- 1) Spieler: einmal im ganzen Spiel (Ledger), 2) Creator zählen + bezahlen (max. 50 pro Tag)
	local okRedeem, result = PlayerDataService.WalletUpdate(player, Ledger.WalletRedeem, {
		Job = WorldService.JobId,
		Code = clean,
		Cash = CR.CodeReward,
	})
	if not okRedeem or not result or not result.Ok then
		return PlayerDataService.Notify(player, false, (result and result.Error) or "Please try again")
	end
	PlayerDataService.Notify(player, true, string.format("🎬 Code %s redeemed: +%d Cash", clean, CR.CodeReward))
	PlayerDataService.PushState(player)

	local day = Ledger.PeriodKeys(now())
	local pay = false
	listStore:Update("list", function(list)
		list = if type(list) == "table" then list else {}
		local entry = list[creatorKey]
		pay = false
		if not entry then
			return list
		end
		if entry.RD ~= day then
			entry.RD, entry.RC = day, 0
		end
		entry.R = (entry.R or 0) + 1
		if (entry.RC or 0) < CR.CreatorDailyCap then
			entry.RC = (entry.RC or 0) + 1
			pay = true
		end
		return list
	end)
	if pay then
		-- ohne Wiederholung: im Zweifel bekommt der Creator diese 500 nicht, aber nie doppelt
		inboxMap:UpdateOnce("u_" .. creatorKey, Ledger.InboxAdd, {
			Adds = { Cash = CR.CreatorPerRedeem, Code = CR.CreatorPerRedeem },
		})
	end
end

------------------------------------------------------------------------

function CreatorService.Init()
	creatorsEvent = Remotes.Event("Creators")
	adminResult = Remotes.Event("AdminResult")
	Remotes.Event("AdminAction").OnServerEvent:Connect(onAdminAction)
	Remotes.Function("AdminLog").OnServerInvoke = onAdminLog
	Remotes.Event("SetCreatorCode").OnServerEvent:Connect(onSetCode)
	Remotes.Event("RedeemCode").OnServerEvent:Connect(onRedeem)
	PlayerDataService.ExtraState = CreatorService.ExtraState
	Players.PlayerRemoving:Connect(function(player)
		limiter:Remove(player)
	end)
end

function CreatorService.Start()
	refresh()
	-- Neue Spieler: Creator-Liste schicken und Stufe auszahlen, sobald die Daten geladen sind
	local function onJoin(player: Player)
		creatorsEvent:FireClient(player, publicTiers())
		for _ = 1, 60 do
			if not player.Parent then
				return
			end
			if PlayerDataService.GetWallet(player) then
				applyGrant(player)
				PlayerDataService.PushState(player)
				return
			end
			task.wait(1)
		end
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do -- schon da (Studio: Spieler kann vor dem Skript joinen)
		task.spawn(onJoin, player)
	end
	task.spawn(function()
		while true do
			task.wait(CR.ListRefresh)
			local ok, err = pcall(refresh)
			if not ok then
				warn("[Creator] refresh: " .. tostring(err))
			end
		end
	end)
end

return CreatorService
