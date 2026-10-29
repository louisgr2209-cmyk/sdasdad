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
local P = Config.Protection
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
		SL = {}, -- Stop-Loss-Aufträge: [Spieler] = 0.1 / 0.2 / 0.3 / 0.5
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
		U = if a.IsNpc then nil else a.Key, -- Spieler (für Creator-Abzeichen)
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
	local insured = (if holding then holding.I or 0 else 0) + (if a.Insure then cash else 0)
	coin.H[a.Key] = {
		A = amount,
		C = cost,
		I = if insured > 0 then insured else nil, -- versicherter Einsatz
		T = math.floor(a.Now), -- letzter Kauf (für die 60-Sek.-Regel), ganze Sekunden sparen Platz
		L = a.Level, -- Level beim Kauf (Anfänger-Erstattung)
	}
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
		if coin.SL then
			coin.SL[a.Key] = nil
		end
		rest, restCost = 0, 0
	else
		coin.H[a.Key] = {
			A = rest,
			C = math.max(0, restCost),
			I = if holding.I then holding.I * (rest / holding.A) else nil,
			T = holding.T,
			L = holding.L,
		}
	end
	coin.Sup = math.max(0, coin.Sup - tokens)
	coin.Vol += payout
	coin.LT = a.Now
	addTrade(coin, "Sell", a, tokens, payout)
	local comp = nil
	if a.Rug then
		coin.Rug = true -- Rugpull im selben Schritt wie der Verkauf
		comp = Ledger.RugCompensation(coin, a.Now)
	end
	return {
		Comp = comp,
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

-- Erstattungen nach einem Rugpull (Wert jetzt, nach dem Crash) -> { [Spieler] = { Ins = x } oder { Beg = x } }
-- Versicherung: 60 % des versicherten Verlusts. Anfänger (Level < 5): 50 % des Verlusts. Der höhere zählt.
-- Nur wenn der letzte Kauf mind. 60 Sek. vor dem Rug war. NPCs bekommen nichts.
function Ledger.RugCompensation(coin, now: number)
	local comp = {}
	for key, h in coin.H do
		if string.sub(key, 1, 4) ~= "npc:" and h.C > 0 and now - (h.T or 0) >= P.MinHoldSeconds then
			local value = Curve.CashForTokens(C, coin.Sup, h.A) * (1 - FEE_TOTAL)
			local loss = math.max(0, h.C - value)
			local ins = if (h.I or 0) > 0 then loss * math.min(1, h.I / h.C) * P.InsurancePayout else 0
			local beg = if (h.L or 99) < P.BeginnerBelowLevel then loss * P.BeginnerPayout else 0
			ins, beg = floorCents(ins), floorCents(beg)
			if ins > 0 and ins >= beg then
				comp[key] = { Ins = ins }
			elseif beg > 0 then
				comp[key] = { Beg = beg }
			end
		end
	end
	return comp
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

-- Stop-Loss eines Spielers setzen (Level = 0.1 .. 0.5) oder löschen (nil). Nur mit Position.
function Ledger.CoinSetStopLoss(coin, a)
	if not coin or not coin.H[a.Key] then
		return nil, { Ok = false, Error = "You don't own this coin" }
	end
	coin.SL = coin.SL or {}
	if coin.SL[a.Key] == a.Level then
		return nil, { Ok = true }
	end
	coin.SL[a.Key] = a.Level
	coin.V += 1
	return coin, { Ok = true }
end

-- Ist der Stop-Loss eines Holders erreicht? (Verkaufswert nach Gebühr <= Einsatz * (1 - Level))
function Ledger.StopLossHit(coin, key: string): boolean
	local level = coin.SL and coin.SL[key]
	local h = coin.H[key]
	if not level or not h or h.C <= 0 then
		return false
	end
	local value = Curve.CashForTokens(C, coin.Sup, h.A) * (1 - FEE_TOTAL)
	return value <= h.C * (1 - level)
end

-- Host verkauft für einen Offline-Spieler (nur wenn der Stop wirklich erreicht ist).
-- a = { Key, Now } -> Coin, Ergebnis (Cash, Profit) oder nil
function Ledger.CoinStopLossExec(coin, a)
	if not coin or not Ledger.StopLossHit(coin, a.Key) then
		return nil, nil
	end
	local result = sell(coin, { Key = a.Key, Name = "🛑 Stop-loss", IsNpc = false, Frac = 1, Now = a.Now })
	if not result.Ok then
		return nil, nil
	end
	coin.SL[a.Key] = nil
	coin.V += 1
	return coin, result
end

-- Spieler-Coin anlegen (Schritt 2 von "Coin erstellen"), optional mit Dev-Buy im selben Schritt.
-- a = { Id, Info = { Name, Ticker, Icon, Desc }, Key, Name, Seq, DevCash, Level, License, Now }
function Ledger.CoinLaunch(coin, a)
	if coin then
		local done = coin.Q[a.Key]
		local doneSeq = if type(done) == "number" then done elseif done then done.S else nil
		if doneSeq and doneSeq >= a.Seq then
			if type(done) == "table" then
				return nil, done.R -- schon angelegt
			end
			local holding = coin.H[a.Key]
			return nil, { Ok = true, Unknown = true, Tokens = 0, Cash = 0, Amount = if holding then holding.A else 0 }
		end
		return nil, { Ok = false, Error = "Please try again", Amount = 0 } -- Id schon vergeben (praktisch unmöglich)
	end
	local info = a.Info
	coin = Ledger.NewCoin({
		Id = a.Id,
		Name = info.Name,
		Ticker = info.Ticker,
		Icon = info.Icon,
		Desc = info.Desc,
		CreatorKey = a.Key,
		CreatorName = a.Name,
		License = a.License,
	}, a.Now)
	local holding = coin.H[a.Key]
	local result = { Ok = true, Tokens = 0, Cash = 0, Amount = holding.A, Cost = 0 }
	if (a.DevCash or 0) >= Config.Trade.MinCash then
		local bought = buy(coin, { Key = a.Key, Name = a.Name, Cash = a.DevCash, Level = a.Level, Now = a.Now })
		if bought.Ok then
			result = bought
		end
	end
	coin.Q[a.Key] = { S = a.Seq, R = receipt(result), At = a.Now }
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
		St = profile.St or {},
		Ins = profile.Ins or {},
		Cr = profile.Cr,
		FB = profile.FB,
		FCM = profile.FCM,
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
	local premium = a.Premium or 0 -- Versicherung: 5 % zusätzlich
	if a.Side == "Buy" then
		if a.Cash < Config.Trade.MinCash then
			return nil, { Error = "Amount too small" }
		end
		if wallet.Cash < a.Cash + premium then
			return nil, { Error = "Not enough cash" }
		end
		wallet.Cash = floorCents(wallet.Cash - a.Cash - premium)
		wallet.Coins[a.Coin] = true
	end
	wallet.Seq += 1
	wallet.P = {
		S = wallet.Seq,
		Side = a.Side,
		Coin = a.Coin,
		Cash = a.Cash,
		Frac = a.Frac,
		Prem = if premium > 0 then premium else nil,
		Ins = a.Insure,
		L = a.Level,
		At = a.Now,
	}
	return wallet, { Ok = true, Seq = wallet.Seq }
end

-- Tag- und Wochen-Nummer (UTC; Woche beginnt Montag) für Tages-/Wochen-Ranglisten
function Ledger.PeriodKeys(now: number): (number, number)
	local day = math.floor(now / 86400)
	local week = math.floor((day + 3) / 7) -- 1.1.1970 war ein Donnerstag
	return day, week
end

-- Statistiken nach einem abgeschlossenen Trade (XP, PNL, bester Trade – gesamt, Woche, Tag)
local function updateStats(wallet, p, r, now: number)
	local st = wallet.St or {}
	wallet.St = st
	local xp = Config.Xp
	if (r.Cash or 0) >= xp.MinTradeCash and now - (st.LXT or 0) >= xp.TradeCooldown then
		st.TXp = (st.TXp or 0) + xp.PerTrade
		st.LXT = now
	end
	if p.Side == "Sell" and r.Profit then
		local profit = r.Profit
		local day, week = Ledger.PeriodKeys(now)
		if st.DK ~= day then
			st.DK, st.DPnl, st.DBest = day, 0, 0
		end
		if st.WK ~= week then
			st.WK, st.WPnl, st.WBest = week, 0, 0
		end
		st.Pnl = (st.Pnl or 0) + profit
		st.DPnl += profit
		st.WPnl += profit
		if profit > 0 then
			st.PP = (st.PP or 0) + profit -- für Gewinn-XP
		end
		st.Best = math.max(st.Best or 0, profit)
		st.DBest = math.max(st.DBest, profit)
		st.WBest = math.max(st.WBest, profit)
	end
end

-- Schritt 1 von "Coin erstellen": Gebühr + Dev-Buy reservieren.
-- a = { Job, Coin, Fee, Cash (Dev-Buy), Info, Level, Now }
function Ledger.WalletLaunchBegin(wallet, a)
	if not wallet or wallet.Owner ~= a.Job then
		return nil, { Error = "Session lost – please rejoin" }
	end
	if wallet.P then
		return nil, { Error = "Previous trade still processing", Pending = true }
	end
	if wallet.Cash < a.Fee + a.Cash then
		return nil, { Error = "Not enough cash" }
	end
	if a.FreeMonth then
		if wallet.FCM == a.FreeMonth then
			return nil, { Error = "Free coin already used this month" }
		end
		wallet.FCM = a.FreeMonth -- Gold-Creator: Gratis-Coin dieses Monats verbraucht
	end
	wallet.Cash = floorCents(wallet.Cash - a.Fee - a.Cash)
	wallet.Seq += 1
	wallet.P = {
		S = wallet.Seq,
		Side = "Launch",
		Coin = a.Coin,
		Fee = a.Fee,
		Cash = a.Cash,
		Info = a.Info,
		L = a.Level,
		FM = a.FreeMonth,
		At = a.Now,
	}
	return wallet, { Ok = true, Seq = wallet.Seq }
end

-- Schritt 3: Trade abschließen (genau einmal, egal welcher Server es tut).
-- a = { Seq, Result, Now }
function Ledger.WalletFinish(wallet, a)
	if not wallet or not wallet.P or wallet.P.S ~= a.Seq then
		return nil, { Already = true }
	end
	local p = wallet.P
	local r = a.Result
	wallet.P = nil
	if p.Side == "Launch" then
		if r.Ok then
			wallet.MyCoin = p.Coin
			wallet.Coins[p.Coin] = true
			-- nicht benutzter Dev-Buy zurück (bei unbekanntem Ergebnis nicht: lieber nichts als doppelt)
			local unused = if r.Unknown then 0 else (p.Cash or 0) - (r.Cash or 0)
			if unused > 0 then
				wallet.Cash = floorCents(wallet.Cash + unused)
			end
		else
			wallet.Cash = floorCents(wallet.Cash + (p.Fee or 0) + (p.Cash or 0)) -- alles zurück
			if p.FM and wallet.FCM == p.FM then
				wallet.FCM = nil -- Gratis-Coin nicht verbraucht
			end
		end
		return wallet, { Ok = true }
	end
	if r.Ok then
		if p.Side == "Sell" then
			wallet.Cash = floorCents(wallet.Cash + r.Cash)
		end
	elseif p.Side == "Buy" then
		wallet.Cash = floorCents(wallet.Cash + p.Cash + (p.Prem or 0)) -- Kauf fehlgeschlagen: Geld + Prämie zurück
	end
	if (r.Amount or 0) <= 0 then
		wallet.Coins[p.Coin] = nil
	end
	if r.Ok and not r.Unknown then
		updateStats(wallet, p, r, a.Now or 0)
	end
	return wallet, { Ok = true }
end

-- Lebenszeichen. Gehört die Geldbörse nicht mehr diesem Server: melden (Spieler wird gekickt).
function Ledger.WalletHeartbeat(wallet, a)
	if not wallet or wallet.Owner ~= a.Job then
		return nil, { Lost = true }
	end
	wallet.HB = a.Now
	if a.Add then
		local st = wallet.St or {}
		wallet.St = st
		st.PT = (st.PT or 0) + a.Add -- Spielzeit in Sek. (Creator-Code erst ab 30 Min.)
	end
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

-- Versicherung für einen Coin an/aus (nur Einstellung, kein Geld)
function Ledger.WalletSetInsure(wallet, a)
	if not wallet or wallet.Owner ~= a.Job then
		return nil, { Ok = false }
	end
	wallet.Ins = wallet.Ins or {}
	wallet.Ins[a.Coin] = if a.On then true else nil
	return wallet, { Ok = true }
end

-- Mindestgeld: höchstens alle Interval Sek. (Zeit in der Geldbörse -> Rejoin hilft nicht)
function Ledger.WalletStipend(wallet, a)
	if not wallet or wallet.Owner ~= a.Job then
		return nil, { Ok = false }
	end
	local st = wallet.St or {}
	wallet.St = st
	if a.Now - (st.LS or 0) < a.Interval then
		return nil, { Ok = false }
	end
	st.LS = a.Now
	wallet.Cash = floorCents(wallet.Cash + a.Amount)
	return wallet, { Ok = true, Amount = a.Amount }
end

-- Daily Reward abholen. a = { Job, Day, Multiplier? }. Einmal pro Tag (Wiederholung = nichts doppelt).
function Ledger.WalletDaily(wallet, a)
	if not wallet or wallet.Owner ~= a.Job then
		return nil, { Ok = false, Error = "Session lost – please rejoin" }
	end
	local st = wallet.St or {}
	wallet.St = st
	if st.DD == a.Day then
		return nil, { Ok = false, Error = "Already claimed today – come back tomorrow" }
	end
	local streak = if st.DD == a.Day - 1 then (st.DS or 0) % #P.Daily + 1 else 1
	local amount = P.Daily[streak] * (a.Multiplier or 1)
	st.DD, st.DS = a.Day, streak
	wallet.Cash = floorCents(wallet.Cash + amount)
	return wallet, { Ok = true, Streak = streak, Amount = amount }
end

-- Postfach in die Geldbörse buchen (Stop-Loss offline, Erstattungen, geschlossene Coins).
-- a = { Job, Id, Cash, Profit, Now }. Gleiche Id nochmal = nichts doppelt.
function Ledger.WalletInbox(wallet, a)
	if not wallet or wallet.Owner ~= a.Job then
		return nil, { Ok = false }
	end
	if wallet.Op == a.Id then
		return nil, { Ok = true, Already = true }
	end
	wallet.Op = a.Id
	wallet.Cash = floorCents(wallet.Cash + math.max(0, a.Cash or 0))
	if a.Fee and a.Fee > 0 then
		local st = wallet.St or {}
		wallet.St = st
		st.FE = (st.FE or 0) + a.Fee -- verdiente Ersteller-Gebühren (Anzeige im Portfolio)
	end
	if a.Profit then
		updateStats(wallet, { Side = "Sell" }, { Cash = 0, Profit = a.Profit }, a.Now)
	end
	return wallet, { Ok = true }
end

-- Creator-Stufe auszahlen: nur wenn höher als alles bisher Bezahlte (jede Stufe einmal, keine Nachzahlung
-- übersprungener Stufen, nach Gold keine niedrigere). a = { Job, Tier, Cash, FreeBoosts }
function Ledger.WalletCreatorGrant(wallet, a)
	if not wallet or wallet.Owner ~= a.Job then
		return nil, { Ok = false }
	end
	wallet.Cr = wallet.Cr or {}
	if (wallet.Cr.Max or 0) >= a.Tier then
		return nil, { Ok = false, Already = true }
	end
	wallet.Cr.Max = a.Tier
	wallet.Cash = floorCents(wallet.Cash + (a.Cash or 0))
	wallet.FB = (wallet.FB or 0) + (a.FreeBoosts or 0)
	return wallet, { Ok = true }
end

-- Creator-Code einlösen: einmal im ganzen Spiel. a = { Job, Code, Cash }
function Ledger.WalletRedeem(wallet, a)
	if not wallet or wallet.Owner ~= a.Job then
		return nil, { Ok = false, Error = "Session lost – please rejoin" }
	end
	local st = wallet.St or {}
	wallet.St = st
	if st.RC then
		return nil, { Ok = false, Error = "You already used a creator code" }
	end
	st.RC = a.Code
	wallet.Cash = floorCents(wallet.Cash + a.Cash)
	return wallet, { Ok = true }
end

-- Gratis-Boosts (Bronze-Creator) verbrauchen (-1) oder zurückgeben (+1). a = { Job, Id, Delta }
function Ledger.WalletFreeBoost(wallet, a)
	if not wallet or wallet.Owner ~= a.Job then
		return nil, { Ok = false }
	end
	if wallet.Op == a.Id then
		return nil, { Ok = true, Already = true }
	end
	local count = (wallet.FB or 0) + a.Delta
	if count < 0 then
		return nil, { Ok = false }
	end
	wallet.Op = a.Id
	wallet.FB = count
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
	return {
		Cash = wallet.Cash,
		Seq = wallet.Seq,
		P = wallet.P,
		Coins = wallet.Coins,
		St = wallet.St,
		Ins = wallet.Ins,
		Cr = wallet.Cr,
		FB = wallet.FB,
		FCM = wallet.FCM,
		Version = 1,
	}
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

-- Töpfe: { Ins = Versicherungstopf, Ref = Erstattungstopf, D = { Day, Used = { [Spieler] = Betrag } } }
function Ledger.PotsAdd(pots, a)
	pots = pots or { Ins = 0, Ref = 0 }
	pots.Ins = (pots.Ins or 0) + (a.Ins or 0)
	pots.Ref = (pots.Ref or 0) + (a.Ref or 0)
	return pots, true
end

-- Rug-Erstattungen bezahlen: erst aus dem Topf, fehlt etwas, legt das Spiel max. TopUp pro Spieler und Tag drauf.
-- a = { Comp = { [Spieler] = { Ins | Beg } }, AddRef = Rug-Anteil für den Topf, Day, TopUp } -> { [Spieler] = Betrag }
function Ledger.PotsPay(pots, a)
	pots = pots or { Ins = 0, Ref = 0 }
	pots.Ins = pots.Ins or 0
	pots.Ref = (pots.Ref or 0) + (a.AddRef or 0)
	if not pots.D or pots.D.Day ~= a.Day then
		pots.D = { Day = a.Day, Used = {} }
	end
	local payouts = {}
	for key, c in a.Comp do
		local want = c.Ins or c.Beg or 0
		local potName = if c.Ins then "Ins" else "Ref"
		local fromPot = math.min(want, pots[potName])
		pots[potName] = floorCents(pots[potName] - fromPot)
		local used = pots.D.Used[key] or 0
		local topUp = math.max(0, math.min(want - fromPot, a.TopUp - used))
		pots.D.Used[key] = used + topUp
		local total = floorCents(fromPot + topUp)
		if total > 0 then
			payouts[key] = total
		end
	end
	return pots, payouts
end

-- Boost-Plätze: { [coinId] = { U = bis, Id = Buchungsnummer } }
-- a = { Coin, Id, Now, Seconds, Slots }. Gleiche Id nochmal = schon gebucht (kein Doppel-Boost, keine falsche Erstattung).
function Ledger.BoostClaim(boosts, a)
	boosts = boosts or {}
	local active, nextFree = 0, math.huge
	for coinId, entry in boosts do
		if entry.U <= a.Now then
			boosts[coinId] = nil
		else
			active += 1
			nextFree = math.min(nextFree, entry.U - a.Now)
		end
	end
	local mine = boosts[a.Coin]
	if mine then
		if mine.Id == a.Id then
			return nil, { Ok = true, Until = mine.U }
		end
		return nil, { Ok = false, Error = string.format("Already boosted (%dm left)", math.ceil((mine.U - a.Now) / 60)) }
	end
	if active >= a.Slots then
		return nil, { Ok = false, Full = true, NextFree = nextFree }
	end
	boosts[a.Coin] = { U = a.Now + a.Seconds, Id = a.Id }
	return boosts, { Ok = true, Until = a.Now + a.Seconds }
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
