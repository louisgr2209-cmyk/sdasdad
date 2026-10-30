-- CreatorStyle (ModuleScript) – ReplicatedStorage/Shared/CreatorStyle
-- Wie Creator angezeigt werden (Terminal, Leaderboard, Ticker). Stufe: 0 = keiner, 1 Starter, 2 Bronze, 3 Silber, 4 Gold.
--   Starter: Titel "Creator"   Bronze: + Abzeichen 🎬   Silber: + lila Name, Rahmen, Coin-Highlight   Gold: Gold statt lila

local CreatorStyle = {}

CreatorStyle.Badge = "🎬"
CreatorStyle.Silver = Color3.fromRGB(192, 132, 252)
CreatorStyle.Gold = Color3.fromRGB(250, 204, 21)
CreatorStyle.Vip = Color3.fromRGB(45, 212, 191) -- VIP-Gamepass (Phase 8): ⭐ + türkis
CreatorStyle.Legend = Color3.fromRGB(239, 68, 68) -- Legend (Level 40): 👑 + roter Rahmen

-- Name mit Abzeichen (🎬 ab Bronze, 👑 Legend, ⭐ VIP)
function CreatorStyle.Name(name: string, tier: number?, vip: boolean?, legend: boolean?): string
	if vip then
		name = "⭐ " .. name
	end
	if legend then
		name = "👑 " .. name
	end
	if (tier or 0) >= 2 then
		return CreatorStyle.Badge .. " " .. name
	end
	return name
end

-- Titel (ab Starter)
function CreatorStyle.Title(tier: number?): string?
	return if (tier or 0) >= 1 then "Creator" else nil
end

-- Namensfarbe / Rahmenfarbe / Coin-Highlight (ab Silber, Creator-Farbe vor VIP), sonst nil
function CreatorStyle.Color(tier: number?, vip: boolean?): Color3?
	if (tier or 0) >= 4 then
		return CreatorStyle.Gold
	elseif (tier or 0) >= 3 then
		return CreatorStyle.Silver
	elseif vip then
		return CreatorStyle.Vip
	end
	return nil
end

return CreatorStyle
