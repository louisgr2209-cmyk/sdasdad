-- PlayerDataService (ModuleScript) – ServerScriptService/Services/PlayerDataService
-- Spielstand jedes Spielers:
--  * Geldbörse (Cash, offener Trade, Liste gehaltener Coins) liegt im Weltmarkt-Speicher (MemoryStore),
--    solange der Spieler spielt. Nur EIN Server darf sie halten (Session-Lock mit Lebenszeichen).
--  * Dauerhaft gespeichert im DataStore: alle 60 Sek., beim Verlassen und beim Herunterfahren.
--  * Coins (Mengen) liegen in den Coins selbst (MarketService) – so gibt es sie nur einmal.
-- Laden: erst Weltmarkt (neuester Stand), sonst DataStore, sonst neuer Spieler mit Startgeld.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Levels = require(ReplicatedStorage.Shared.Levels)
local Remotes = require(ServerScriptService.Util.Remotes)
local Store = require(ServerScriptService.Util.Store)
local Ledger = require(ServerScriptService.Util.Ledger)
local WorldService = require(ServerScriptService.Services.WorldService)

local W = Config.World

local PlayerDataService = {}

-- Werden von Main gesetzt (MarketService), damit es keine gegenseitigen requires gibt
PlayerDataService.RecoverPending = nil :: ((Player) -> boolean)?
PlayerDataService.WaitIdle = nil :: ((Player, number) -> ())?

local walletsMap = Store.Map(W.WalletsMap, W.WalletExpiration)
local coinsMap = Store.Map(W.CoinsMap, W.CoinExpiration)
local profileStore = Store.Data(W.ProfileStore)
local inboxMap = Store.Map(W.InboxMap, W.CoinExpiration)

local profiles = {} -- [Player] = { Wallet, Holdings = { [coinId] = { Amount, Cost } }, Loaded, Dirty }
local stateEvent: RemoteEvent

local function now(): number
	return workspace:GetServerTimeNow()
end

local function isValidNumber(n: any): boolean
	return typeof(n) == "number" and n == n and n > -math.huge and n < math.huge
end

function PlayerDataService.Key(player: Player): string
	return tostring(player.UserId)
end

local function profileKey(player: Player): string
	return "u_" .. player.UserId
end

function PlayerDataService.GetPlayerByKey(key: string): Player?
	local userId = tonumber(key)
	return if userId then Players:GetPlayerByUserId(userId) else nil
end

-- Lokale Kopie der Geldbörse (nur lesen!). nil = noch nicht geladen.
function PlayerDataService.GetWallet(player: Player)
	local profile = profiles[player]
	return if profile and profile.Loaded then profile.Wallet else nil
end

-- Alle gehaltenen Coins (nur lesen!): { [coinId] = { Amount, Cost } }
function PlayerDataService.GetHoldings(player: Player)
	local profile = profiles[player]
	return if profile then profile.Holdings else {}
end

function PlayerDataService.GetHolding(player: Player, coinId: string)
	local profile = profiles[player]
	return profile and profile.Holdings[coinId]
end

-- Geldbörse atomar ändern (Ledger-Funktion). -> ok, ergebnis
function PlayerDataService.WalletUpdate(player: Player, fn, args)
	local profile = profiles[player]
	if not profile then
		return false, nil
	end
	local ok, result, newValue = walletsMap:Update(PlayerDataService.Key(player), fn, args)
	if ok and newValue then
		profile.Wallet = newValue
		profile.Dirty = true
	elseif ok and result and result.Already then
		-- ein anderer Schritt war schneller (z. B. Wiederholung): aktuellen Stand holen
		local okGet, value = walletsMap:Get(PlayerDataService.Key(player))
		if okGet and value then
			profile.Wallet = value
		end
	end
	return ok, result
end

function PlayerDataService.SetHolding(player: Player, coinId: string, amount: number, cost: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	local old = profile.Holdings[coinId]
	profile.Holdings[coinId] = if amount > 0 then { Amount = amount, Cost = cost, SL = old and old.SL } else nil
end

-- Stop-Loss-Stufe in der lokalen Kopie merken (Wahrheit liegt im Coin)
function PlayerDataService.SetStopLossLocal(player: Player, coinId: string, level: number?)
	local holding = PlayerDataService.GetHolding(player, coinId)
	if holding then
		holding.SL = level
	end
end

-- Hinweis oben im Terminal (gleicher Weg wie Trade-Meldungen)
function PlayerDataService.Notify(player: Player, ok: boolean, message: string)
	Remotes.Event("TradeResult"):FireClient(player, { Ok = ok, Message = message })
end

-- Geld gutschreiben/abziehen (für spätere Phasen: Daily Reward usw.). Nie doppelt.
function PlayerDataService.AddCash(player: Player, delta: number): boolean
	if not isValidNumber(delta) or not PlayerDataService.GetWallet(player) then
		return false
	end
	local ok, result = PlayerDataService.WalletUpdate(player, Ledger.WalletAddCash, {
		Job = WorldService.JobId,
		Id = HttpService:GenerateGUID(false),
		Delta = delta,
	})
	if ok and result and result.Ok then
		PlayerDataService.PushState(player)
		return true
	end
	return false
end

-- Statistiken (XP, PNL, bester Trade). Tag/Woche zählen nur, wenn sie zum aktuellen Tag/zur Woche gehören.
function PlayerDataService.GetStats(player: Player)
	local wallet = PlayerDataService.GetWallet(player)
	local st = (wallet and wallet.St) or {}
	local day, week = Ledger.PeriodKeys(now())
	local xp = Levels.Xp(st)
	return {
		Xp = xp,
		Level = Levels.LevelForXp(xp),
		Pnl = st.Pnl or 0,
		Best = st.Best or 0,
		DayPnl = if st.DK == day then st.DPnl else 0,
		DayBest = if st.DK == day then st.DBest else 0,
		WeekPnl = if st.WK == week then st.WPnl else 0,
		WeekBest = if st.WK == week then st.WBest else 0,
		FeesEarned = st.FE or 0, -- verdiente Ersteller-Gebühren
	}
end

-- Alle geladenen Spieler (für Ranglisten)
function PlayerDataService.LoadedPlayers(): { Player }
	local list = {}
	for player, profile in profiles do
		if profile.Loaded then
			table.insert(list, player)
		end
	end
	return list
end

function PlayerDataService.BuildState(player: Player)
	local profile = profiles[player]
	if not profile or not profile.Loaded then
		return nil
	end
	-- Daily Reward: heute schon abgeholt? Welcher Tag ist als Nächstes dran?
	local st = profile.Wallet.St or {}
	local today = Ledger.PeriodKeys(now())
	local claimed = st.DD == today
	local nextStreak = if claimed or st.DD == today - 1 then (st.DS or 0) % #Config.Protection.Daily + 1 else 1
	return {
		Cash = profile.Wallet.Cash,
		Positions = profile.Holdings,
		Stats = PlayerDataService.GetStats(player),
		Insured = profile.Wallet.Ins or {},
		MyCoin = profile.Wallet.MyCoin,
		Daily = {
			CanClaim = not claimed,
			Streak = if claimed then st.DS else nextStreak - 1, -- bereits geschaffte Tage in Folge
			Next = nextStreak, -- dieser Tag ist als Nächstes dran
		},
	}
end

function PlayerDataService.PushState(player: Player)
	local state = PlayerDataService.BuildState(player)
	if state then
		stateEvent:FireClient(player, state)
	end
end

------------------------------------------------------------------------
-- Speichern
------------------------------------------------------------------------

-- Gespeichertes Profil prüfen (kaputte oder manipulierte Daten nie übernehmen)
local function cleanProfile(data)
	if type(data) ~= "table" or not isValidNumber(data.Cash) or data.Cash < 0 then
		return nil
	end
	local coins = {}
	if type(data.Coins) == "table" then
		for coinId, flag in data.Coins do
			if type(coinId) == "string" and flag == true then
				coins[coinId] = true
			end
		end
	end
	local stats = {}
	if type(data.St) == "table" then
		for key, value in data.St do
			if type(key) == "string" and isValidNumber(value) then
				stats[key] = value
			end
		end
	end
	return {
		Cash = Ledger.FloorCents(data.Cash),
		Seq = if isValidNumber(data.Seq) then data.Seq else 0,
		P = if type(data.P) == "table" then data.P else nil,
		Coins = coins,
		St = stats,
	}
end

local function save(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile.Loaded then
		return false
	end
	local snapshot = Ledger.ProfileFromWallet(profile.Wallet)
	local ok = profileStore:Update(profileKey(player), function()
		return snapshot
	end)
	if ok then
		profile.Dirty = false
	end
	return ok
end

-- Postfach leeren (z. B. Auszahlung automatisch geschlossener Coins) und gutschreiben.
-- Erst leeren, dann gutschreiben: bei Absturz dazwischen verfällt der Betrag, er kommt nie doppelt.
local refreshHoldings -- unten definiert

local function drainInbox(player: Player)
	local ok, content = inboxMap:Update("u_" .. player.UserId, Ledger.InboxDrain, {})
	if not ok or type(content) ~= "table" then
		return
	end
	local cash = if isValidNumber(content.Cash) then math.max(0, content.Cash) else 0
	local profit = if isValidNumber(content.Profit) then content.Profit else nil
	if cash <= 0 and not profit then
		return
	end
	local okWallet, result = PlayerDataService.WalletUpdate(player, Ledger.WalletInbox, {
		Job = WorldService.JobId,
		Id = HttpService:GenerateGUID(false),
		Cash = Ledger.FloorCents(cash),
		Profit = profit,
		Fee = if isValidNumber(content.Fee) then content.Fee else nil,
		Now = now(),
	})
	if not (okWallet and result and result.Ok) then
		return
	end
	-- Hinweise, woher das Geld kommt
	if isValidNumber(content.Refund) and content.Refund > 0 then
		PlayerDataService.Notify(player, true, string.format("🛡 Rug refund: +%.2f Cash", content.Refund))
	end
	if isValidNumber(content.SL) and content.SL > 0 then
		PlayerDataService.Notify(player, true, string.format("🛑 Stop-loss sold while you were away: +%.2f Cash", content.SL))
		refreshHoldings(player)
	end
	PlayerDataService.PushState(player)
end

PlayerDataService.DrainInbox = drainInbox

------------------------------------------------------------------------
-- Laden
------------------------------------------------------------------------

local function load(player: Player)
	local profile = { Wallet = nil, Holdings = {}, Loaded = false, Dirty = false }
	profiles[player] = profile
	local key = PlayerDataService.Key(player)

	-- 1) Geldbörse übernehmen. Hält sie noch ein anderer Server (Spieler hat gerade gewechselt): warten.
	local claimed = false
	for _ = 1, 25 do
		if not player.Parent then
			return
		end
		local ok, result, value = walletsMap:Update(key, Ledger.WalletClaim, {
			Job = WorldService.JobId,
			Now = now(),
			Stale = W.WalletStale,
		})
		if ok and result and result.Ok then
			profile.Wallet = value
			claimed = true
			break
		elseif ok and result and result.Missing then
			-- 2) Nicht im Weltmarkt: aus dem DataStore laden (oder neuer Spieler)
			local okData, data = profileStore:Get(profileKey(player))
			if not okData then
				break -- DataStore nicht erreichbar: lieber nicht spielen als Fortschritt verlieren
			end
			local saved = cleanProfile(data)
				or { Cash = Config.StartCash, Seq = 0, Coins = {} }
			local okCreate, created, newValue = walletsMap:Update(key, Ledger.WalletCreate, {
				Job = WorldService.JobId,
				Now = now(),
				Profile = saved,
			})
			if okCreate and created and created.Ok then
				profile.Wallet = newValue
				claimed = true
				break
			end
			-- jemand war schneller: nochmal übernehmen
		end
		task.wait(2)
	end
	if not claimed then
		profiles[player] = nil
		if player.Parent then
			player:Kick("Your data is still saving on another server. Please rejoin in a moment.")
		end
		return
	end
	if not player.Parent then
		return -- schon wieder weg: Freigabe übernimmt onPlayerRemoving
	end
	profile.Loaded = true

	-- 3) Offenen Trade fertig buchen (z. B. nach Server-Absturz)
	if profile.Wallet.P and PlayerDataService.RecoverPending then
		PlayerDataService.RecoverPending(player)
	end

	-- 4) Mengen der gehaltenen Coins aus den Coins lesen
	local gone = {}
	for coinId in profile.Wallet.Coins do
		local ok, coin = coinsMap:Get(coinId)
		if ok then
			local holding = coin and coin.H[key]
			if holding then
				profile.Holdings[coinId] = { Amount = holding.A, Cost = holding.C, SL = coin.SL and coin.SL[key] }
			else
				table.insert(gone, coinId)
			end
		end
	end
	if #gone > 0 then
		PlayerDataService.WalletUpdate(player, Ledger.WalletForget, { Job = WorldService.JobId, Coins = gone })
	end
	drainInbox(player)
	PlayerDataService.PushState(player)
end

-- Mengen aller gehaltenen Coins neu lesen (z. B. nachdem der Host per Stop-Loss verkauft hat)
refreshHoldings = function(player: Player)
	local profile = profiles[player]
	if not profile or not profile.Loaded then
		return
	end
	local key = PlayerDataService.Key(player)
	for coinId in profile.Wallet.Coins do
		local ok, coin = coinsMap:Get(coinId)
		if ok then
			local holding = coin and coin.H[key]
			profile.Holdings[coinId] = if holding
				then { Amount = holding.A, Cost = holding.C, SL = coin.SL and coin.SL[key] }
				else nil
		end
	end
end

-- Spieler geht: Trades fertig, speichern, Geldbörse freigeben
local function unload(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	if PlayerDataService.WaitIdle then
		PlayerDataService.WaitIdle(player, 15)
	end
	if profile.Loaded then
		local saved = save(player)
		-- Gespeichert und kein offener Trade: Geldbörse läuft im Weltmarkt nach 10 Min. ab.
		-- Sonst bleibt sie 30 Tage, damit nichts verloren geht.
		local expiration = if saved and not profile.Wallet.P then W.WalletReleasedExpiration else W.WalletExpiration
		walletsMap:Update(PlayerDataService.Key(player), Ledger.WalletRelease, { Job = WorldService.JobId }, expiration)
	end
	profiles[player] = nil
end

------------------------------------------------------------------------

function PlayerDataService.Init()
	stateEvent = Remotes.Event("PlayerState")
	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(unload)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	-- Lebenszeichen: zeigt allen Servern, dass dieser Server die Geldbörse noch hält
	task.spawn(function()
		while true do
			task.wait(W.HeartbeatInterval)
			-- Kopie der Liste: während der Speicherzugriffe kommen/gehen Spieler
			local list = {}
			for player, profile in profiles do
				table.insert(list, { player, profile })
			end
			for _, entry in list do
				local player, profile = entry[1], entry[2]
				if profile.Loaded and profiles[player] == profile then
					local ok, result = PlayerDataService.WalletUpdate(player, Ledger.WalletHeartbeat, {
						Job = WorldService.JobId,
						Now = now(),
					})
					if ok and result and result.Lost and player.Parent then
						-- Geldbörse gehört inzwischen einem anderen Server: sicherheitshalber raus
						profiles[player] = nil
						player:Kick("Your session moved to another server. Please rejoin.")
					end
				end
			end
		end
	end)

	-- Postfach der Spieler regelmäßig prüfen
	task.spawn(function()
		while true do
			task.wait(W.InboxInterval)
			for _, player in Players:GetPlayers() do
				local profile = profiles[player]
				if profile and profile.Loaded then
					task.spawn(drainInbox, player)
				end
			end
		end
	end)

	-- Automatisch speichern
	task.spawn(function()
		while true do
			task.wait(W.AutosaveInterval)
			for player, profile in profiles do
				if profile.Loaded and profile.Dirty then
					task.spawn(save, player)
				end
			end
		end
	end)

	-- Server fährt herunter: alle speichern und freigeben (Roblox wartet max. 30 Sek.)
	game:BindToClose(function()
		local remaining = 0
		for _, player in Players:GetPlayers() do
			remaining += 1
			task.spawn(function()
				unload(player)
				remaining -= 1
			end)
		end
		local started = os.clock()
		while remaining > 0 and os.clock() - started < 25 do
			task.wait(0.2)
		end
	end)
end

return PlayerDataService
