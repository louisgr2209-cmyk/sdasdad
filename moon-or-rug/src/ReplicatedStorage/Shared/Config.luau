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
	IdleText = "Fictional meme coins – just a game. Cash is not real money.",
}

-- Markt-Takt
Config.Market = {
	BroadcastInterval = 0.25, -- Sekunden zwischen Kurs-Updates an alle Clients (klein = wenig Verzögerung)
	ChartInterval = 5, -- Sekunden pro Chart-Punkt
	ChartPoints = 60, -- Punkte pro Chart
	RecentTrades = 20, -- gespeicherte Live-Trades pro Coin
	DeadAfter = 30 * 60, -- Sekunden ohne Trade, dann "Dead" (verschwindet aus den Listen)
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
	MaxHoldersPerCoin = 400, -- mehr Holder passen nicht sicher in einen Coin

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
	LicenseBluffChance = 0.2, -- auch ehrliche NPCs zeigen manchmal "Rug-Lizenz" (Warnung = Risiko, nicht Beweis)

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
