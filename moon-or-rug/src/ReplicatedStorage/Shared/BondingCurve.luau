-- BondingCurve (ModuleScript) – ReplicatedStorage/Shared/BondingCurve
-- Reine Mathematik, keine Roblox-APIs. Server rechnet damit die echten Trades,
-- der Client darf damit nur Vorschauen anzeigen.
--
-- Bis zur Migrationsgrenze: P(s) = P0 * (1 + s/S)^2
-- Danach: gerade Linie mit kleinerer Steigung (flacher, aber ohne Obergrenze)
-- Kosten eines Kaufs = Fläche unter der Kurve zwischen alter und neuer Menge.

local BondingCurve = {}

export type Params = {
	TotalSupply: number,
	P0: number,
	S: number,
	MigrationMarketCap: number,
	AlmostDoneRatio: number,
	MigratedSlopeFactor: number,
}

-- Menge, Preis und Steigung an der Migrationsgrenze
local function migrationPoint(c: Params): (number, number, number)
	local pm = c.MigrationMarketCap / c.TotalSupply
	local sm = math.max(0, c.S * (math.sqrt(pm / c.P0) - 1))
	pm = c.P0 * (1 + sm / c.S) ^ 2
	local k = c.MigratedSlopeFactor * 2 * c.P0 * (1 + sm / c.S) / c.S
	return sm, pm, k
end

-- Preis bei Menge s
function BondingCurve.Price(c: Params, s: number): number
	local sm, pm, k = migrationPoint(c)
	if s <= sm then
		return c.P0 * (1 + s / c.S) ^ 2
	end
	return pm + k * (s - sm)
end

-- Fläche unter der Kurve von 0 bis s (= Cash, das in der Kurve steckt)
function BondingCurve.Area(c: Params, s: number): number
	local sm, pm, k = migrationPoint(c)
	if s <= sm then
		return c.P0 * c.S / 3 * ((1 + s / c.S) ^ 3 - 1)
	end
	local d = s - sm
	return c.P0 * c.S / 3 * ((1 + sm / c.S) ^ 3 - 1) + pm * d + k * d * d / 2
end

-- Umkehrung: zu welcher Menge gehört diese Fläche?
function BondingCurve.SupplyForArea(c: Params, area: number): number
	local sm, pm, k = migrationPoint(c)
	local areaAtMigration = BondingCurve.Area(c, sm)
	if area <= areaAtMigration then
		local x = 3 * area / (c.P0 * c.S) + 1
		return c.S * (x ^ (1 / 3) - 1)
	end
	local rest = area - areaAtMigration
	if k <= 0 then
		return sm + rest / pm
	end
	return sm + (-pm + math.sqrt(pm * pm + 2 * k * rest)) / k
end

-- Wie viele Coins bekommt man für "cash" (ohne Gebühr), ausgehend von Menge s?
function BondingCurve.TokensForCash(c: Params, s: number, cash: number): number
	if cash <= 0 then
		return 0
	end
	local newSupply = BondingCurve.SupplyForArea(c, BondingCurve.Area(c, s) + cash)
	return math.max(0, newSupply - s)
end

-- Wie viel Cash (ohne Gebühr) bringt der Verkauf von "tokens", ausgehend von Menge s?
function BondingCurve.CashForTokens(c: Params, s: number, tokens: number): number
	tokens = math.clamp(tokens, 0, s)
	return math.max(0, BondingCurve.Area(c, s) - BondingCurve.Area(c, s - tokens))
end

function BondingCurve.MarketCap(c: Params, s: number): number
	return BondingCurve.Price(c, s) * c.TotalSupply
end

-- "New", "AlmostDone" oder "Migrated"
function BondingCurve.Stage(c: Params, marketCap: number, migrated: boolean): string
	if migrated or marketCap >= c.MigrationMarketCap then
		return "Migrated"
	elseif marketCap >= c.MigrationMarketCap * c.AlmostDoneRatio then
		return "AlmostDone"
	end
	return "New"
end

return BondingCurve
