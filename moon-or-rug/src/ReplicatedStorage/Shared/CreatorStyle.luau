-- CreatorStyle (ModuleScript) – ReplicatedStorage/Shared/CreatorStyle
-- Wie Creator angezeigt werden (Terminal, Leaderboard, Ticker). Stufe: 0 = keiner, 1 Starter, 2 Bronze, 3 Silber, 4 Gold.
--   Starter: Titel "Creator"   Bronze: + Abzeichen 🎬   Silber: + lila Name, Rahmen, Coin-Highlight   Gold: Gold statt lila

local CreatorStyle = {}

CreatorStyle.Badge = "🎬"
CreatorStyle.Silver = Color3.fromRGB(192, 132, 252)
CreatorStyle.Gold = Color3.fromRGB(250, 204, 21)

-- Name mit Abzeichen (ab Bronze)
function CreatorStyle.Name(name: string, tier: number?): string
	if (tier or 0) >= 2 then
		return CreatorStyle.Badge .. " " .. name
	end
	return name
end

-- Titel (ab Starter)
function CreatorStyle.Title(tier: number?): string?
	return if (tier or 0) >= 1 then "Creator" else nil
end

-- Namensfarbe / Rahmenfarbe / Coin-Highlight (ab Silber), sonst nil
function CreatorStyle.Color(tier: number?): Color3?
	if (tier or 0) >= 4 then
		return CreatorStyle.Gold
	elseif (tier or 0) >= 3 then
		return CreatorStyle.Silver
	end
	return nil
end

return CreatorStyle
