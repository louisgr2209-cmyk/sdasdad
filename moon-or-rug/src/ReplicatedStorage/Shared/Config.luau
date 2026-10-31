-- Config (ModuleScript) – ReplicatedStorage/Shared/Config
-- ALLE Spielwerte an einem Ort. Hier anpassen, nicht im Code.

local Config = {}

-- Spieler
Config.StartCash = 1000

-- Bonding-Curve: P(s) = P0 * (1 + s/S)^2, nach Migration lineare (flachere) Fortsetzung
Config.Curve = {
	TotalSupply = 1_000_000, -- Referenzmenge: Marktkapital = Preis * TotalSupply
	P0 = 0.001, -- Startpreis bei s = 0
	S = 100_000, -- Kurven-Größe (größer = Preis steigt langsamer)
	MigrationMarketCap = 69_000, -- ab hier "Migrated"
	AlmostDoneRatio = 0.5, -- ab 50 % der Grenze "Almost done"
	MigratedSlopeFactor = 0.5, -- Steigung nach Migration (0.5 = halb so steil wie an der Grenze)
}

-- Dev-Anteil: Ersteller bekommt beim Erstellen 5 % (zählt als schon verkauft)
Config.DevShare = 0.05

-- Gebühren pro Trade (vom Trade-Betrag)
Config.Fees = {
	Creator = 0.005, -- an den Ersteller
	Burn = 0.005, -- verschwindet (Geld-Senke)
}

-- Trades
Config.Trade = {
	MaxPerSecond = 5, -- Rate-Limit pro Spieler
	MaxPerMinute = 30, -- zusätzlich pro Minute (schont das Roblox-Budget des Weltmarkts)
	MaxQueued = 3, -- so viele Trades eines Spielers dürfen gleichzeitig in der Warteschlange sein
	MinCash = 1, -- kleinster Trade in Cash
	Fractions = { 0.10, 0.25, 0.50, 1.00 }, -- Kauf-/Verkauf-Buttons
	QuickBuyFraction = 0.10, -- Schnellkauf in der Pulse-Liste: 10 % des Cash
}

-- Ticker unten im Terminal
Config.Ticker = {
	BigProfit = 1000, -- Gewinn ab dem ein Verkauf gemeldet wird ("X made 1,234 Cash on $ABC")
	ShowSeconds = 5, -- so lange bleibt eine Meldung stehen
	IdleText = "Fictional meme coins – just a game. LNR and $ here are not real money.",
}

-- Markt-Takt
Config.Market = {
	BroadcastInterval = 0.25, -- Sekunden zwischen Kurs-Updates an alle Clients (klein = wenig Verzögerung)
	ChartInterval = 5, -- Sekunden pro Chart-Punkt
	ChartPoints = 60, -- Punkte pro Chart
	RecentTrades = 20, -- gespeicherte Live-Trades pro Coin
	MaxFavorites = 30, -- Favoriten ⭐ pro Spieler (voll: ältester fällt raus)
	TradeLogKeep = 500, -- Trade-Verlauf pro Spieler (DataStore)
	DeadAfter = 30 * 60, -- Sekunden ohne Trade, dann "Dead" (verschwindet aus den Listen)
}

-- XP und Level (Tempo "schnell": Level 5 ca. 15 Min., Level 10 ca. 1,5 Std., Level 25 ca. 10 Std.)
Config.Xp = {
	PerTrade = 1, -- XP pro Trade ...
	MinTradeCash = 100, -- ... aber nur ab dieser Trade-Größe (sonst XP-Farmen mit Mini-Trades)
	TradeCooldown = 10, -- ... und höchstens alle 10 Sek.
	ProfitPerXp = 100, -- +1 XP pro 100 Cash Gewinn
	LevelFactor = 3, -- XP für Level L = LevelFactor * (L - 1)^2
}

-- Ränge (Level ab dem sie gelten) und was freigeschaltet wird
Config.Levels = {
	{ Level = 1, Rank = "Rookie", Unlock = "Buy, sell, portfolio" },
	{ Level = 3, Rank = "Trader", Unlock = "Stop-loss" },
	{ Level = 5, Rank = "Degen", Unlock = "Rug insurance" },
	{ Level = 10, Rank = "Whale", Unlock = "Create your own coin" },
	{ Level = 15, Rank = "Shark", Unlock = "Coin boost" },
	{ Level = 25, Rank = "Dev", Unlock = "Rug pull license" },
	{ Level = 40, Rank = "Legend", Unlock = "Cosmetics, prestige frame" },
}

-- Legend (ab Level 40): 👑 vor dem Namen + roter Prestige-Rahmen um die Wallet-Box (nur Optik)
Config.Prestige = {
	LegendLevel = 40,
}

-- Schutz vor Bankrott (Phase 5)
Config.Protection = {
	-- Mindestgeld: Vermögen (Cash + Coins) unter 100 -> alle 10 Min. 250 Cash, solange man online ist
	StipendBelow = 100,
	StipendAmount = 250,
	StipendInterval = 600,

	-- Daily Reward: Tag 1..7 (danach wieder Tag 1). Einen Tag verpasst -> zurück auf Tag 1. Tage in UTC.
	Daily = { 500, 750, 1000, 1500, 2000, 3000, 5000 },

	-- Stop-Loss (ab Level 3): verkauft alles, wenn der Wert so weit unter dem Einstieg liegt
	StopLossLevels = { 0.10, 0.20, 0.30, 0.50 },
	StopLossMinLevel = 3,
	StopLossOfflineDelay = 15, -- Host verkauft für Offline-Spieler, wenn der Stop seit 15 Sek. erreicht ist
	StopLossHostInterval = 10,

	-- Rug-Versicherung (ab Level 5): Schalter pro Coin, kostet 5 % jedes Kaufs, zahlt 60 % des Verlusts
	InsurancePremium = 0.05,
	InsurancePayout = 0.60,
	InsuranceMinLevel = 5,

	-- Anfänger-Erstattung: unter Level 5 gibt es bei einem Rugpull 50 % des Verlusts zurück.
	-- Mit Versicherung zählt der höhere Wert (nicht beides).
	BeginnerBelowLevel = 5,
	BeginnerPayout = 0.50,

	MinHoldSeconds = 60, -- Kauf muss mind. 60 Sek. vor dem Rugpull sein (gegen Tricks)
	RugPotShare = 0.30, -- 30 % des Rug-Erlöses gehen in den Erstattungstopf
	DailyTopUp = 500, -- ist ein Topf leer, legt das Spiel max. 500 Cash pro Spieler und Tag drauf
}

-- Coin erstellen + Boost (Phase 6)
Config.Launch = {
	CreateCost = 50_000, -- Cash (Robux-Variante kommt in Phase 8)
	CreateMinLevel = 10,
	MaxActiveCoins = 1, -- pro Spieler gleichzeitig gelistet
	DevBuyOptions = { 0, 0.10, 0.25, 0.50 }, -- optional direkt mitkaufen (Anteil des restlichen Cash), max. 50 %

	BoostCost = 25_000,
	BoostMinLevel = 15,
	BoostSeconds = 600, -- 10 Min. oben in der BOOSTED-Leiste
	BoostSlots = 3, -- weltweit gleichzeitig
	BoostSyncInterval = 5, -- so oft holt jeder Server die Boost-Liste

	-- Regeln für Namen (zusätzlich Roblox-Textfilter)
	NameMin = 3,
	NameMax = 20,
	TickerMin = 3,
	TickerMax = 5,
	DescMax = 60,
	-- Echte Krypto-Namen/Marken sind verboten (Plan: nur fiktive Coins). Ticker: exakt; Name: als Wort.
	Blocked = {
		"BITCOIN", "BTC", "ETHEREUM", "ETH", "SOLANA", "SOL", "DOGECOIN", "DOGE", "SHIBA", "SHIB",
		"PEPE", "BONK", "FLOKI", "WIF", "XRP", "RIPPLE", "BNB", "BINANCE", "COINBASE", "TETHER",
		"USDT", "USDC", "CARDANO", "ADA", "LITECOIN", "LTC", "MONERO", "XMR", "TRON", "TRX",
		"POLYGON", "MATIC", "AVAX", "CRYPTO", "KRYPTO", "AXIOM", "PUMPFUN", "NFT", "ROBUX",
	},
}

-- Rugpull (Phase 7): Lizenz im Create-Fenster, ein Klick verkauft alles. Keine Warnung, kein Abzeichen.
-- Ohne Rugpull verkauft der Ersteller seinen eigenen Coin nur stufenweise.
Config.Rug = {
	MinLevel = 25,
	LicenseCost = 250_000, -- Cash (Robux-Variante kommt in Phase 8)
	LicenseUses = 3, -- eine Lizenz gilt für 3 Rugpulls
	Cooldown = 24 * 3600, -- 1 Rugpull pro 24 Std. pro Spieler
	MinCoinAge = 600, -- Coin muss mind. 10 Min. alt sein
	-- Erlös: 70 % an den Rugpuller, 30 % in den Erstattungstopf (Config.Protection.RugPotShare)
	DevSellMax = 0.25, -- normaler Verkauf des Erstellers im eigenen Coin: max. 25 % pro Verkauf …
	DevSellCooldown = 60, -- … und max. 1 Verkauf pro Minute (alles raus dauert mind. ca. 4 Min.)
}

-- Robux (Phase 8): Developer Products geben Gutscheine (nie verloren, nie doppelt), Gamepässe schalten Extras frei.
-- Id = 0: noch nicht im Creator Dashboard angelegt -> im echten Spiel nicht kaufbar, in Studio Test-Kauf.
-- Robux überspringt Level-Pflichten (Entscheidung Phase 8). Cash ist nie gegen Robux zurücktauschbar.
Config.Shop = {
	Products = {
		CreateCoin = { Id = 0, Robux = 99, Grant = "CT", Title = "Create a coin", Info = "No level, no LNR needed" },
		Boost = { Id = 0, Robux = 49, Grant = "FB", Title = "Boost 10 min", Info = "Your coin on top (no level needed)" },
		Highlight = { Id = 0, Robux = 25, Grant = "HT", Title = "Highlight 30 min", Info = "Glowing frame for your coin" },
		License = { Id = 0, Robux = 299, Grant = "RL", Title = "Rug pull license", Info = "3 rug pulls, no level needed" },
	},
	Passes = {
		Pro = { Id = 0, Robux = 249, Title = "Pro Terminal", Info = "Top 10 names, candle chart, dev sells live" },
		HalfInsurance = { Id = 0, Robux = 149, Title = "Insurance ½ price", Info = "Rug insurance costs 2.5% instead of 5%" },
		DoubleDaily = { Id = 0, Robux = 99, Title = "Double daily reward", Info = "Every daily reward x2" },
		Vip = { Id = 0, Robux = 99, Title = "VIP", Info = "⭐ name, turquoise color and frame" },
	},
	Order = { "CreateCoin", "Boost", "Highlight", "License", "Pro", "HalfInsurance", "DoubleDaily", "Vip" },
	HighlightSeconds = 1800, -- 30 Min.
	ReceiptsKept = 30, -- so viele Kauf-Nummern merkt sich die Geldbörse (Schutz gegen doppelte Gutschrift)
	ProInfoCooldown = 2, -- Top-10-Namen höchstens alle 2 Sek. abfragen
	VipCacheSeconds = 1800, -- Host merkt sich VIP-Status für die weltweite Rangliste 30 Min.
}

-- Spielwährung Lunar (LNR) – ersetzt SOL. Fiktiv, nie gegen Robux/Echtgeld tauschbar.
-- Intern rechnet alles in "Cash"; 1 LNR = CashPerUnit Cash (Start 1.000 Cash = 10 LNR).
-- Spiel-Dollar-Anzeige: fiktiver Kurs, schwankt langsam um RateBase (ca. 140–180 $), nur Anzeige.
Config.Currency = {
	Name = "Lunar",
	Symbol = "LNR",
	CashPerUnit = 100,
	RateBase = 160,
	RateWaves = { -- Summe von Sinuswellen: langsam (Woche), mittel (6 Std.), schnell (15 Min.)
		{ Amp = 12, Period = 7 * 86400, Phase = 0 },
		{ Amp = 6, Period = 6 * 3600, Phase = 1.3 },
		{ Amp = 2, Period = 900, Phase = 2.1 },
	},
}

-- Teil-Link / Teil-Code (PNL-Karte teilen): wer über den Link kommt oder den Code eingibt, und der Teilende
-- bekommen je Reward (300 Cash = 3 LNR, ca. 500 $). Gleicher Schutz wie beim Creator-Code. Getrennt vom
-- Creator-Code: jeder Spieler kann EINMAL über einen Freund kommen und EINMAL einen Creator-Code eingeben.
Config.Referral = {
	Prefix = "LNR",
	Reward = 300,
	MinAccountAgeDays = 7,
	MinPlaytimeMinutes = 30,
	CheckInterval = 30, -- so oft prüft der Server, ob eine wartende Belohnung fällig ist
}

-- Sounds (dezent, im Portfolio abschaltbar). Eingebaute Roblox-Dateien; bei Bedarf durch "rbxassetid://…" ersetzen.
Config.Sounds = {
	Volume = 0.35,
	Click = { Id = "rbxasset://sounds/button.wav", Speed = 1.2 },
	Success = { Id = "rbxasset://sounds/electronicpingshort.wav", Speed = 1.2 },
	Error = { Id = "rbxasset://sounds/electronicpingshort.wav", Speed = 0.7 },
	LevelUp = { Id = "rbxasset://sounds/electronicpingshort.wav", Speed = 1.6 },
	Rug = { Id = "rbxasset://sounds/electronicpingshort.wav", Speed = 0.45 },
}

-- Creator-Programm (eigenes Dokument „Moon or Rug – Creator-Programm“)
Config.Creator = {
	-- Roblox-UserIds der Admins (nur sie sehen das Admin-Panel). In Roblox Studio ist jeder Admin (nur zum Testen).
	AdminIds = {
		-- 123456789, -- Beispiel: eure UserId hier eintragen
	},
	-- Stufen: jede gibt es pro Spieler nur einmal; höhere ersetzt die Anzeige; übersprungene Stufen zahlen nichts nach
	Tiers = {
		{ Name = "Starter", Cash = 10_000 }, -- Titel "Creator"
		{ Name = "Bronze", Cash = 25_000, FreeBoosts = 1 }, -- + Abzeichen 🎬
		{ Name = "Silver", Cash = 50_000 }, -- + farbiger Name, Rahmen, Highlight auf eigenen Coins
		{ Name = "Gold", Cash = 0, FreeCoinMonthly = true }, -- + Creator-Code, Gold-Rahmen, 1 Gratis-Coin pro Monat
	},
	CodeReward = 2_000, -- Spieler, der einen Code eingibt (einmal im ganzen Spiel)
	CreatorPerRedeem = 500, -- Creator pro Einlösung (ins Postfach)
	CreatorDailyCap = 50, -- max. bezahlte Einlösungen pro Creator und Tag
	MinAccountAgeDays = 7, -- gegen Zweit-Accounts
	MinPlaytimeMinutes = 30,
	CodeMin = 4,
	CodeMax = 12,
	ListRefresh = 60, -- Server holen die Creator-Liste jede Minute (Freischaltungen kommen überall an)
	LogKeep = 200, -- so viele Admin-Aktionen bleiben im Log
}

-- Ranglisten (nur echte Spieler)
Config.Leaderboard = {
	Size = 50, -- Top 50 weltweit
	ServerInterval = 5, -- Server-Liste aktualisieren (Sek.)
	SubmitInterval = 120, -- eigene Werte in die weltweite Liste schreiben (Sek.)
	WorldReadInterval = 90, -- Host liest die weltweite Liste (Sek.)
	WorldShareInterval = 60, -- alle Server holen die weltweite Liste (Sek.)
}

-- Weltmarkt: alle Server teilen dieselben Coins (MemoryStore), Spielstände im DataStore.
-- Budget-Grenzen von Roblox: Speicher 64 KB + 1,2 KB pro Spieler, Anfragen 1000 + 120 pro Spieler und Minute.
Config.World = {
	CoinsMap = "MoR_Coins_v1", -- MemoryStore: ein Schlüssel pro Coin (die Wahrheit)
	MarketMap = "MoR_Market_v1", -- MemoryStore: Sammel-Schlüssel, Welt, Meldungen, NPCs, Charts
	WalletsMap = "MoR_Wallets_v1", -- MemoryStore: Geldbörsen der Spieler, die gerade spielen
	InboxMap = "MoR_Inbox_v1", -- MemoryStore: Postfach pro Spieler (z. B. Auszahlung geschlossener Coins)
	ProfileStore = "MoR_Players_v1", -- DataStore: dauerhafte Spielstände

	CoinExpiration = 45 * 24 * 3600, -- Coin ohne Änderung wird nach 45 Tagen gelöscht (Roblox-Maximum)
	Expiration = 2 * 24 * 3600, -- übrige Weltmarkt-Schlüssel
	WalletExpiration = 30 * 24 * 3600, -- Geldbörse, solange gespielt wird
	WalletReleasedExpiration = 600, -- nach dem Verlassen (und gespeichert): noch 10 Min. im Weltmarkt

	Shards = 4, -- Sammel-Schlüssel mit den Kurzinfos aller Coins
	-- Lesen/Schreiben der Sammel-Schlüssel passt sich dem Budget an: so schnell wie möglich (0,5 Sek.),
	-- bei winzigen Servern langsamer (bis 2 Sek.), damit das Roblox-Limit nie gerissen wird.
	MinSyncInterval = 0.5,
	MaxSyncInterval = 2,
	SyncBudgetShare = 0.4, -- Anteil des Anfrage-Budgets eines Servers für Lesen der Kurse
	NewsInterval = 2, -- Ticker-Meldungen zwischen Servern
	FeeFlushInterval = 10, -- gesammelte Creator-Gebühren ins Postfach
	InboxInterval = 60, -- Spieler-Postfach prüfen
	ChartSaveInterval = 30, -- Host speichert Charts für neue Server
	MaintenanceInterval = 30, -- Host prüft tote Coins
	NpcSaveInterval = 10, -- Host speichert NPC-Zustand

	TickInterval = 10, -- Server meldet sich in der Welt
	HostLease = 30, -- Host-Rolle gilt so lange ohne Erneuerung
	ServerStale = 45, -- Server ohne Meldung gilt als weg
	WalletStale = 45, -- Geldbörse eines Servers ohne Lebenszeichen darf übernommen werden
	HeartbeatInterval = 15,
	AutosaveInterval = 60,

	-- Ein Speicher-Wert darf max. 32 KB groß sein:
	FullReceipts = 30, -- volle Buchungsbelege pro Coin (ältere schrumpfen auf ihre Nummer, Schutz bleibt)
	MaxHoldersPerCoin = 200, -- je Holder ca. 90 Byte (Menge, Einsatz, Versicherung, Kaufzeit, Level) -> ca. 18 KB

	CoinsBase = 20, -- gelistete Coins weltweit bei wenigen Spielern
	CoinsPerPlayer = 0.2, -- +1 Coin pro 5 Spieler online (Speicher wächst nur 1,2 KB pro Spieler)
	CoinsMax = 120, -- Obergrenze

	-- Delistete Coins: Besitzer können weiter verkaufen. Nach so vielen Stunden ohne Trade verkauft
	-- das Spiel den Rest automatisch zum Kurvenwert, das Cash kommt ins Postfach (beim nächsten Join).
	DeadKeepHours = 72,
}

-- Feste Icon-Auswahl für Coins (NPCs jetzt, Spieler ab Phase 6)
Config.CoinIcons = {
	"🐱", "🐶", "🐹", "🐧", "🦆", "🐢", "🐙", "🦊", "🐼", "🐨",
	"🦄", "🍞", "🍌", "🥔", "🍩", "🍔", "🌮", "🍕", "🧀", "🌵",
}

-- NPC-Trader: halten den Markt am Leben
Config.Npc = {
	Types = { Sniper = 5, Momentum = 5, Panic = 5, Random = 5 }, -- Anzahl pro Typ (zusammen 20)
	StartCash = 2500, -- Geld pro NPC
	RefillPerMinute = 25, -- NPC unter StartCash bekommt langsam Geld nach (klein halten: sonst melken Spieler die NPCs)
	MaxCash = 6000, -- mehr Geld verschwindet -> NPCs pumpen nicht endlos
	TickInterval = 1, -- Sekunden zwischen NPC-Runden
	ActChance = 0.1, -- Chance pro NPC und Runde, etwas zu tun (20 NPCs -> ca. 2 Trades/Sek.)
	MaxBuyAge = 15 * 60, -- NPCs kaufen nur Coins, die jünger sind (Sekunden)

	-- Sniper: jeder entscheidet pro neuem Coin einmal zufällig, OB und WANN er kauft.
	-- So kann kein Spieler sicher vor den Snipern kaufen und an sie verkaufen.
	Sniper = {
		Chance = 0.4, -- 40 % der Sniper kaufen einen neuen Coin überhaupt
		Delay = { 5, 120 }, -- und zwar nach 5 bis 120 Sek.
		MaxAge = 180, -- Coins älter als 3 Min. sind für Sniper uninteressant
		Share = { 0.05, 0.15 }, -- 5–15 % ihres Geldes
	},

	-- NPC-Coins
	StartCoins = 3, -- so viele gelistete Coins gibt es mindestens (Host erstellt sofort welche)
	CreateEvery = { 60, 180 }, -- alle 1 bis 3 Min. ein neuer NPC-Coin

	-- NPC-Rug (ca. 10 % der NPC-Coins)
	RugChance = 0.10,
	Rug = {
		DevBuy = { 0.3, 0.5 }, -- Ersteller kauft am Anfang 30–50 % seines Geldes dazu
		MinAge = 120, -- frühestens nach 2 Min.
		MaxAge = 600, -- spätestens nach 10 Min.
		MinGain = { 1.5, 3 }, -- rugged, sobald der Kurs x1,5 bis x3 gestiegen ist
	},

	Names = {
		"MoonWalker", "PaperHands", "DiamondPaws", "PumpKing", "DipBuyer", "BagHolder", "ChartWizard",
		"FomoFred", "NoSleepNina", "GreenCandle", "RedCandle", "TinyWhale", "ApeLord", "LuckyLarry",
		"HodlHank", "RocketRita", "SniperSam", "CopeTrader", "WenMoon", "ExitLiquid",
	},
	Prefixes = {
		"Moon", "Turbo", "Baby", "Giga", "Space", "Lil", "Super", "Hyper", "Sleepy", "Angry",
		"Happy", "Golden", "Tiny", "Mega", "Cosmic", "Sir", "Based", "Wild", "Lazy", "Rich",
	},
	Nouns = { -- { Name, Icon } – Icons aus Config.CoinIcons
		{ "Cat", "🐱" }, { "Dog", "🐶" }, { "Hamster", "🐹" }, { "Penguin", "🐧" }, { "Duck", "🦆" },
		{ "Turtle", "🐢" }, { "Octo", "🐙" }, { "Fox", "🦊" }, { "Panda", "🐼" }, { "Koala", "🐨" },
		{ "Unicorn", "🦄" }, { "Toast", "🍞" }, { "Banana", "🍌" }, { "Potato", "🥔" }, { "Donut", "🍩" },
		{ "Burger", "🍔" }, { "Taco", "🌮" }, { "Pizza", "🍕" }, { "Cheese", "🧀" }, { "Cactus", "🌵" },
	},
	Descriptions = {
		"To the moon!", "Community coin. No plan, just vibes.", "The next big thing (probably not).",
		"Made at 3am.", "Diamond paws only.", "Buy high, sell higher.", "100% meme, 0% utility.",
	},
}

-- Indikatoren auf der Coin-Seite (Ampel: grün = gut, gelb = vorsichtig, rot = riskant)
-- Werte sind Anteile an allen Coins (1.000.000). Startwerte aus der Simulation, im Test anpassen.
Config.Indicators = {
	Top10 = { Good = 0.15, Bad = 0.30 }, -- bis 15 % grün, bis 30 % gelb, darüber rot
	Dev = { Good = 0.05, Bad = 0.10 }, -- Startanteil 5 % = grün, mehr = Dev hat dazugekauft
	Early = { Good = 0.10, Bad = 0.20 }, -- Anteil der Früh-Käufer (erste 30 Sek.)
	Holders = { Good = 8, Bad = 3 }, -- ab 8 grün, ab 3 gelb, darunter rot (mehr = besser)
	EarlyWindow = 30, -- Sekunden nach dem Erstellen, in denen ein Kauf als "früh" zählt
}

-- Sicherheit
Config.Security = {
	LogProfitAbove = 10_000, -- Spieler-Gewinn pro Verkauf ab hier wird im Server-Output geloggt
	SnapshotsPer30s = 3, -- so oft darf ein Client die kompletten Marktdaten holen
}

-- UI (Handy zuerst)
Config.UI = {
	DesignWidth = 1000, -- Layout ist für 1000 x 520 gebaut und wird skaliert
	DesignHeight = 520, -- 520 statt 560: auf Handys Buttons ca. 44 pt, Text ca. 12 pt
	MinScale = 0.5,
	MaxScale = 1.5,
}

return Config
