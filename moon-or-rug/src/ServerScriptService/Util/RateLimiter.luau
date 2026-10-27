-- RateLimiter (ModuleScript) – ServerScriptService/Util/RateLimiter
-- Erlaubt max. N Aktionen pro Sekunde pro Schlüssel (z. B. pro Spieler).

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(maxPerSecond: number)
	return setmetatable({ max = maxPerSecond, hits = {} }, RateLimiter)
end

function RateLimiter:Allow(key: any): boolean
	local now = os.clock()
	local list = self.hits[key]
	if not list then
		list = {}
		self.hits[key] = list
	end
	while list[1] and now - list[1] >= 1 do
		table.remove(list, 1)
	end
	if #list >= self.max then
		return false
	end
	table.insert(list, now)
	return true
end

function RateLimiter:Remove(key: any)
	self.hits[key] = nil
end

return RateLimiter
