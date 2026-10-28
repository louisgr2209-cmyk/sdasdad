-- Levels (ModuleScript) – ReplicatedStorage/Shared/Levels
-- XP -> Level -> Rang. Gemeinsam für Server (Freischaltungen) und Client (Anzeige).

local Config = require(script.Parent.Config)

local X = Config.Xp

local Levels = {}

-- Gesamt-XP aus den Statistiken: Trade-XP + 1 XP pro 100 Cash Gewinn
function Levels.Xp(stats): number
	stats = stats or {}
	return (stats.TXp or 0) + math.floor((stats.PP or 0) / X.ProfitPerXp)
end

-- XP, ab denen ein Level erreicht ist
function Levels.XpForLevel(level: number): number
	return X.LevelFactor * (level - 1) ^ 2
end

function Levels.LevelForXp(xp: number): number
	return math.floor(math.sqrt(math.max(0, xp) / X.LevelFactor)) + 1
end

-- Rang für ein Level (höchster Eintrag, der erreicht ist)
function Levels.Rank(level: number)
	local best = Config.Levels[1]
	for _, entry in Config.Levels do
		if level >= entry.Level then
			best = entry
		end
	end
	return best
end

-- Freischaltung genau auf diesem Level (oder nil)
function Levels.UnlockAt(level: number)
	for _, entry in Config.Levels do
		if entry.Level == level then
			return entry
		end
	end
	return nil
end

-- -> level, Fortschritt zum nächsten Level (0..1), XP bis zum nächsten Level
function Levels.Progress(xp: number): (number, number, number)
	local level = Levels.LevelForXp(xp)
	local from = Levels.XpForLevel(level)
	local to = Levels.XpForLevel(level + 1)
	return level, (xp - from) / (to - from), to - xp
end

return Levels
