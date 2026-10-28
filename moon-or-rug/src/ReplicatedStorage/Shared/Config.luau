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
	BroadcastInterval = 0.5, -- Sekunden zwischen Kurs-Updates an alle Clients
	ChartInterval = 5, -- Sekunden pro Chart-Punkt
	ChartPoints = 60, -- Punkte pro Chart
	RecentTrades = 20, -- gespeicherte Live-Trades pro Coin
	DeadAfter = 30 * 60, -- Sekunden ohne Trade, dann "Dead" (verschwindet aus den Listen)
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
	StartCoins = 3, -- so viele Coins gibt es direkt beim Serverstart
	CreateEvery = { 60, 180 }, -- alle 1 bis 3 Min. ein neuer NPC-Coin
	MaxLiveCoins = 40, -- Obergrenze für lebende Coins pro Server
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
