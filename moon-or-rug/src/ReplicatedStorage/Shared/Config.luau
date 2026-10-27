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
}

-- Markt-Takt
Config.Market = {
	BroadcastInterval = 0.5, -- Sekunden zwischen Kurs-Updates an alle Clients
	ChartInterval = 5, -- Sekunden pro Chart-Punkt
	ChartPoints = 60, -- Punkte pro Chart
	RecentTrades = 20, -- gespeicherte Live-Trades pro Coin
}

-- Test-Coin (Phase 1)
Config.TestCoin = {
	Name = "Moon Test Dog",
	Ticker = "MTD",
	Icon = "🐶",
}

-- UI (Handy zuerst)
Config.UI = {
	DesignWidth = 1000, -- Layout ist für 1000 x 560 gebaut und wird skaliert
	DesignHeight = 560,
	MinScale = 0.5,
	MaxScale = 1.5,
}

return Config
