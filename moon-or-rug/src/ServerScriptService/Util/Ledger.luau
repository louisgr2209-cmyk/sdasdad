-- Ledger (ModuleScript) – ServerScriptService/Util/Ledger
-- Reine Buchungs-Funktionen für den Weltmarkt (keine Roblox-APIs, keine Wartezeiten).
-- Jede Funktion bekommt den alten Wert eines Speicher-Schlüssels und gibt zurück:
--   neuerWert (oder nil = nichts schreiben), ergebnis
-- Sie werden in MemoryStore:UpdateAsync benutzt. Dort können sie mehrfach laufen,
-- deshalb dürfen sie NUR den übergebenen Wert verändern und sonst nichts.
--
-- Duplikat-Schutz bei Spieler-Trades (3 Schritte):
--   1. WalletBegin:  Geldbörse merkt sich den Trade (P) mit fortlaufender Nummer, Kauf-Geld wird reserviert
--   2. CoinTrade:    Coin bucht den Trade genau EINMAL (Q[Spieler].S = letzte gebuchte Nummer)
--   3. WalletFinish: Geldbörse schließt den Trade ab (Auszahlung oder Erstattung), genau EINMAL (P.S)
-- Bricht etwas zwischen den Schritten ab, werden 2 und 3 später einfach wiederholt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Curve = require(ReplicatedStorage.Shared.BondingCurve)

local C = Config.Curve
local FEE_TOTAL = Config.Fees.Creator + Config.Fees.Burn
local DUST = 1e-9
local MAX_TRADES = 5 -- letzte Trades pro Coin (für Live-Trades auf allen Servern)

local Ledger = {}

local function floorCents(n: number): number
	return math.floor(n * 100 + 1e-6) / 100
end
Ledger.FloorCents = floorCents

------------------------------------------------------------------------
-- Coins
------------------------------------------------------------------------

-- Neuer Coin. info = { Id, Name, Ticker, Icon, Desc, CreatorKey?, CreatorName, License }
function Ledger.NewCoin(info, now: number)
	local devAmount = C.TotalSupply * Config.DevShare
	local coin = {
		V = 1, -- Version, steigt bei jeder Änderung
		Id = info.Id,
		Name = info.Name,
		Ticker = info.Ticker,
		Icon = info.Icon,
		Desc = info.Desc or "",
		CK = info.CreatorKey, -- Ersteller-Schlüssel (Spieler-UserId oder "npc:3")
		CN = info.CreatorName or "System",
		Lic = info.License == true,
		At = now, -- erstellt
		LT = now, -- letzter Trade
		Sup = devAmount, -- Dev-Anteil zählt als schon verkauft
		Mig = false,
		Dead = false,
		Rug = false,
		Vol = 0,
		H = {}, -- Holder: [Schlüssel] = { A = Menge, C = Kosten }
		E = {}, -- Früh-Käufer: [Schlüssel] = true
		Q = {}, -- Duplikat-Schutz: [Spieler] = { S = letzte Nummer, R = Ergebnis }
		T = {}, -- letzte Trades
	}
	if info.CreatorKey then
		coin.H[info.CreatorKey] = { A = devAmount, C = 0 }
	end
	return coin
end

local function fail(message: string, holding)
	return { Ok = false, Error = message, Amount = if holding then holding.A else 0, Cost = if holding then holding.C else 0 }
end

local function addTrade(coin, side: string, a, tokens: number, cash: number)
	table.insert(coin.T, {
		I = coin.V + 1, -- eindeutig pro Coin (= neue Version)
		S = side,
		N = a.Name,
		B = a.IsNpc == true,
		K = tokens,
		M = cash,
		At = a.Now,
	})
	while #coin.T > MAX_TRADES do
		table.remove(coin.T, 1)
	end
end

local function buy(coin, a)
	local holding = coin.H[a.Key]
	if coin.Dead then
		return fail("This coin is dead", holding)
	end
	if not holding then
		local count = 0
		for _ in coin.H do
			count += 1
		end
		if count >= Config.World.MaxHoldersPerCoin then
			return fail("Too many holders right now – try again later", nil)
		end
	end
	local cash = floorCents(a.Cash)
	if cash < Config.Trade.MinCash then
		return fail("Amount too small", holding)
	end
	local tokens = Curve.TokensForCash(C, coin.Sup, cash * (1 - FEE_TOTAL))
	if tokens <= DUST then
		return fail("Amount too small", holding)
	end
	coin.Sup += tokens
	if a.Now - coin.At <= Config.Indicators.EarlyWindow and a.Key ~= coin.CK then
		coin.E[a.Key] = true
	end
	local amount = (if holding then holding.A else 0) + tokens
	local cost = (if holding then holding.C else 0) + cash
	coin.H[a.Key] = { A = amount, C = cost }
	coin.Vol += cash
	coin.LT = a.Now
	addTrade(coin, "Buy", a, tokens, cash)
	if not coin.Mig and Curve.MarketCap(C, coin.Sup) >= C.MigrationMarketCap then
		coin.Mig = true
	end
	return {
		Ok = true,
		Tokens = tokens,
		Cash = cash,
		Amount = amount,
		Cost = cost,
		Profit = 0,
		Fee = cash * Config.Fees.Creator,
		CreatorKey = coin.CK,
	}
end

local function sell(coin, a)
	local holding = coin.H[a.Key]
	if not holding then
		return fail("You don't own this coin", nil)
	end
	local frac = a.Frac
	local tokens = if frac >= 1 then holding.A else holding.A * frac
	tokens = math.min(tokens, holding.A, coin.Sup)
	if tokens <= DUST then
		return fail("Amount too small", holding)
	end
	local gross = Curve.CashForTokens(C, coin.Sup, tokens)
	local payout = floorCents(gross * (1 - FEE_TOTAL))
	if payout <= 0 then
		return fail("Amount too small", holding)
	end
	local costPart = holding.C * (tokens / holding.A)
	local rest = holding.A - tokens
	local restCost = holding.C - costPart
	if rest <= DUST then
		coin.H[a.Key] = nil
		rest, restCost = 0, 0
	else
		coin.H[a.Key] = { A = rest, C = math.max(0, restCost) }
	end
	coin.Sup = math.max(0, coin.Sup - tokens)
	coin.Vol += payout
	coin.LT = a.Now
	addTrade(coin, "Sell", a, tokens, payout)
	if a.Rug then
		coin.Rug = true -- Rugpull im selben Schritt wie der Verkauf
	end
	return {
		Ok = true,
		Tokens = tokens,
		Cash = payout,
		Amount = rest,
		Cost = math.max(0, restCost),
		Profit = payout - costPart,
		Fee = gross * Config.Fees.Creator,
		CreatorKey = coin.CK,
	}
end

-- Ältere volle Belege auf ihre Nummer verkleinern (Speicher-Grenze 32 KB).
-- Die Nummer reicht, damit nie doppelt gebucht wird.
local function compactReceipts(coin)
	local full = {}
	for key, entry in coin.Q do
		if type(entry) == "table" then
			table.insert(full, key)
		end
	end
	local limit = Config.World.FullReceipts
	if #full <= limit then
		return
	end
	table.sort(full, function(x, y)
		return coin.Q[x].At < coin.Q[y].At
	end)
	for i = 1, #full - limit do
		coin.Q[full[i]] = coin.Q[full[i]].S
	end
end

-- Kurzer Beleg (nur was für eine Wiederholung gebraucht wird)
local function receipt(result)
	return {
		Ok = result.Ok,
		Error = result.Error,
		Tokens = result.Tokens,
		Cash = result.Cash,
		Amount = result.Amount,
		Cost = result.Cost,
	}
end

-- Trade im Coin buchen.
-- a = { Key, Name, IsNpc, Seq (nur Spieler), Side "Buy"/"Sell", Cash (Kauf), Frac (Verkauf), Rug?, Now }
function Ledger.CoinTrade(coin, a)
	if not coin then
		return nil, fail("Coin not found", nil)
	end
	if a.Seq then
		local done = coin.Q[a.Key]
		local doneSeq = if type(done) == "number" then done elseif done then done.S else nil
		if doneSeq and doneSeq >= a.Seq then
			-- schon gebucht: nichts ändern, altes Ergebnis zurückgeben
			if type(done) == "table" then
				return nil, done.R
			end
			-- nur noch die Nummer bekannt: als erledigt behandeln (lieber 0 auszahlen als doppelt)
			local holding = coin.H[a.Key]
			return nil, {
				Ok = true,
				Unknown = true,
				Tokens = 0,
				Cash = 0,
				Amount = if holding then holding.A else 0,
				Cost = if holding then holding.C else 0,
			}
		end
	end
	local result = if a.Side == "Buy" then buy(coin, a) else sell(coin, a)
	if a.Seq then
		-- auch Fehlschläge merken (Wiederholung = gleiches Ergebnis)
		coin.Q[a.Key] = { S = a.Seq, R = receipt(result), At = a.Now }
		compactReceipts(coin)
	elseif not result.Ok then
		return nil, result -- NPC-Fehlschlag: nichts schreiben
	end
	coin.V += 1
	return coin, result
end

-- Coin als "Dead" markieren (30 Min. ohne Trade)
function Ledger.CoinMarkDead(coin, a)
	if not coin or coin.Dead or a.Now - coin.LT < a.DeadAfter then
		return nil, false
	end
	coin.Dead = true
	coin.V += 1
	return coin, true
end

-- Delisteten Coin schließen: alle Reste zum Kurvenwert verkaufen (größte zuerst).
-- -> Coin (leer, geschlossen), { [Spieler-Schlüssel] = Auszahlung }. NPC-Reste verfallen.
function Ledger.CoinCloseOut(coin, a)
	if not coin or not coin.Dead or coin.Closed or a.Now - coin.LT < a.KeepSeconds then
		return nil, nil
	end
	local list = {}
	for key, holding in coin.H do
		table.insert(list, { Key = key, A = holding.A })
	end
	table.sort(list, function(x, y)
		return x.A > y.A
	end)
	local payouts = {}
	for _, entry in list do
		local tokens = math.min(entry.A, coin.Sup)
		local payout = floorCents(Curve.CashForTokens(C, coin.Sup, tokens) * (1 - FEE_TOTAL))
		coin.Sup = math.max(0, coin.Sup - tokens)
		if string.sub(entry.Key, 1, 4) ~= "npc:" and payout > 0 then
			payouts[entry.Key] = payout
		end
	end
	coin.H = {}
	coin.Closed = true
	coin.V += 1
	return coin, payouts
end

-- Hält noch ein Spieler (kein NPC) diesen Coin?
function Ledger.HasPlayerHolders(coin): boolean
	for key in coin.H do
		if string.sub(key, 1, 4) ~= "npc:" then
			return true
		end
	end
	return false
end

------------------------------------------------------------------------
-- Geldbörse (Wallet) eines Spielers
-- { Cash, Seq, P = offener Trade oder nil, Coins = { [coinId] = true }, Owner = Server, HB = Lebenszeichen }
------------------------------------------------------------------------

-- Server übernimmt die Geldbörse (Session-Lock). Gehört sie einem anderen, lebenden Server: abbrechen.
function Ledger.WalletClaim(wallet, a)
	if not wallet then
		return nil, { Missing = true }
	end
	if wallet.Owner and wallet.Owner ~= a.Job and a.Now - (wallet.HB or 0) < a.Stale then
		return nil, { Locked = true }
	end
	wallet.Owner = a.Job
	wallet.HB = a.Now
	return wallet, { Ok = true }
end

-- Neue Geldbörse aus dem gespeicherten Profil (nur wenn es noch keine gibt)
function Ledger.WalletCreate(wallet, a)
	if wallet then
		return nil, { Exists = true }
	end
	local profile = a.Profile
	return {
		Cash = profile.Cash,
		Seq = profile.Seq or 0,
		P = profile.P,
		Coins = profile.Coins or {},
		Owner = a.Job,
		HB = a.Now,
	}, { Ok = true }
end

-- Schritt 1: Trade anmelden. Kauf: Geld sofort reservieren.
-- a = { Job, Side, Coin, Cash (Kauf), Frac (Verkauf), Now }
function Ledger.WalletBegin(wallet, a)
	if not wallet or wallet.Owner ~= a.Job then
		return nil, { Error = "Session lost – please rejoin" }
	end
	if wallet.P then
		return nil, { Error = "Previous trade still processing", Pending = true }
	end
	if a.Side == "Buy" then
		if a.Cash < Config.Trade.MinCash then
			return nil, { Error = "Amount too small" }
		end
		if wallet.Cash < a.Cash then
			return nil, { Error = "Not enough cash" }
		end
		wallet.Cash = floorCents(wallet.Cash - a.Cash)
		wallet.Coins[a.Coin] = true
	end
	wallet.Seq += 1
	wallet.P = { S = wallet.Seq, Side = a.Side, Coin = a.Coin, Cash = a.Cash, Frac = a.Frac, At = a.Now }
	return wallet, { Ok = true, Seq = wallet.Seq }
end

-- Schritt 3: Trade abschließen (genau einmal, egal welcher Server es tut).
-- a = { Seq, Result }
function Ledger.WalletFinish(wallet, a)
	if not wallet or not wallet.P or wallet.P.S ~= a.Seq then
		return nil, { Already = true }
	end
	local p = wallet.P
	local r = a.Result
	wallet.P = nil
	if r.Ok then
		if p.Side == "Sell" then
			wallet.Cash = floorCents(wallet.Cash + r.Cash)
		end
	elseif p.Side == "Buy" then
		wallet.Cash = floorCents(wallet.Cash + p.Cash) -- Kauf fehlgeschlagen: Geld zurück
	end
	if (r.Amount or 0) <= 0 then
		wallet.Coins[p.Coin] = nil
	end
	return wallet, { Ok = true }
end

-- Lebenszeichen. Gehört die Geldbörse nicht mehr diesem Server: melden (Spieler wird gekickt).
function Ledger.WalletHeartbeat(wallet, a)
	if not wallet or wallet.Owner ~= a.Job then
		return nil, { Lost = true }
	end
	wallet.HB = a.Now
	return wallet, { Ok = true }
end

-- Geld gutschreiben/abziehen (Daily Reward usw.). Nie unter 0.
-- a.Id = eindeutige Nummer der Buchung: wird sie wiederholt, passiert nichts (kein Doppel-Geld).
function Ledger.WalletAddCash(wallet, a)
	if not wallet or wallet.Owner ~= a.Job then
		return nil, { Ok = false }
	end
	if wallet.Op == a.Id then
		return nil, { Ok = true, Already = true }
	end
	wallet.Op = a.Id
	local newCash = floorCents(wallet.Cash + a.Delta)
	if newCash < 0 then
		return nil, { Ok = false }
	end
	wallet.Cash = newCash
	return wallet, { Ok = true }
end

-- Coins entfernen, die es nicht mehr gibt
function Ledger.WalletForget(wallet, a)
	if not wallet or wallet.Owner ~= a.Job then
		return nil
	end
	for _, coinId in a.Coins do
		wallet.Coins[coinId] = nil
	end
	return wallet
end

-- Server gibt die Geldbörse frei (Spieler hat den Server verlassen)
function Ledger.WalletRelease(wallet, a)
	if not wallet or wallet.Owner ~= a.Job then
		return nil
	end
	wallet.Owner = nil
	return wallet
end

-- Gespeichertes Profil (DataStore) aus der Geldbörse
function Ledger.ProfileFromWallet(wallet)
	return { Cash = wallet.Cash, Seq = wallet.Seq, P = wallet.P, Coins = wallet.Coins, Version = 1 }
end

------------------------------------------------------------------------
-- Sammel-Schlüssel (Shards): Kurzinfos aller Coins für alle Server
------------------------------------------------------------------------

-- a = { Updates = { [coinId] = Kurzinfo }, Removes = { [coinId] = true } }
function Ledger.ShardMerge(shard, a)
	shard = shard or {}
	for id, info in a.Updates do
		local old = shard[id]
		if not old or old.V < info.V then
			shard[id] = info
		end
	end
	for id in a.Removes do
		shard[id] = nil
	end
	return shard, true
end

------------------------------------------------------------------------
-- Welt: welche Server laufen, wie viele Spieler, wer ist NPC-Host
------------------------------------------------------------------------

-- a = { Job, Players, Now, Lease, Stale, Release? }
function Ledger.WorldTick(world, a)
	world = world or { Servers = {} }
	if a.Release then
		world.Servers[a.Job] = nil
		if world.Host and world.Host.Job == a.Job then
			world.Host = nil
		end
	else
		world.Servers[a.Job] = { P = a.Players, T = a.Now }
	end
	local total = 0
	for job, server in world.Servers do
		if a.Now - server.T > a.Stale then
			world.Servers[job] = nil
		else
			total += server.P
		end
	end
	local host = world.Host
	if not a.Release and (not host or host.Until < a.Now or host.Job == a.Job) then
		world.Host = { Job = a.Job, Until = a.Now + a.Lease }
	end
	local servers = 0
	for _ in world.Servers do
		servers += 1
	end
	return world, { IsHost = world.Host ~= nil and world.Host.Job == a.Job, Players = total, Servers = servers }
end

------------------------------------------------------------------------
-- Meldungen (Ticker) und Gebühren-Postfach
------------------------------------------------------------------------

function Ledger.NewsAdd(news, a)
	news = news or { Seq = 0, Items = {} }
	for _, item in a.Items do
		news.Seq += 1
		table.insert(news.Items, { S = news.Seq, K = item.Kind, X = item.Text })
	end
	while #news.Items > 10 do
		table.remove(news.Items, 1)
	end
	return news, true
end

-- Postfach: { [Schlüssel] = Betrag }. a = { Adds = { [Schlüssel] = Betrag } }
function Ledger.InboxAdd(inbox, a)
	inbox = inbox or {}
	for key, amount in a.Adds do
		inbox[key] = (inbox[key] or 0) + amount
	end
	return inbox, true
end

-- Postfach leeren, Inhalt zurückgeben
function Ledger.InboxDrain(inbox, _a)
	if not inbox or next(inbox) == nil then
		return nil, {}
	end
	return {}, inbox
end

return Ledger
