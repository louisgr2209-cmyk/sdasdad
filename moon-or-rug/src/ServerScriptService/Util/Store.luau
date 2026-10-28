-- Store (ModuleScript) – ServerScriptService/Util/Store
-- Zugriff auf MemoryStore (Weltmarkt, alle Server) und DataStore (dauerhaft speichern),
-- jeweils mit Wiederholungen bei Fehlern.
--
-- Lokaler Testmodus: Ist das Spiel nicht veröffentlicht oder in Studio der API-Zugriff aus,
-- läuft alles nur im Speicher dieses Servers (nichts wird gespeichert). Steht dann als Warnung im Output.

local MemoryStoreService = game:GetService("MemoryStoreService")
local DataStoreService = game:GetService("DataStoreService")

local Store = {}

local RETRIES = 4

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = deepCopy(item)
	end
	return copy
end

------------------------------------------------------------------------
-- Lokaler Ersatz (gleiche Schnittstelle wie die echten Dienste)
------------------------------------------------------------------------
local LocalMap = {}
LocalMap.__index = LocalMap

function LocalMap.new()
	return setmetatable({ data = {} }, LocalMap)
end

function LocalMap:GetAsync(key: string)
	return deepCopy(self.data[key])
end

function LocalMap:SetAsync(key: string, value: any)
	self.data[key] = deepCopy(value)
	return true
end

function LocalMap:UpdateAsync(key: string, transform: (any) -> any)
	local new = transform(deepCopy(self.data[key]))
	if new == nil then
		return nil
	end
	self.data[key] = deepCopy(new)
	return deepCopy(new)
end

function LocalMap:RemoveAsync(key: string)
	self.data[key] = nil
end

------------------------------------------------------------------------
-- Testmodus erkennen (echte Dienste einmal ausprobieren)
------------------------------------------------------------------------
local memoryOk = pcall(function()
	MemoryStoreService:GetHashMap("MoR_Probe"):GetAsync("probe")
end)
local dataOk = pcall(function()
	DataStoreService:GetDataStore("MoR_Probe"):GetAsync("probe")
end)
Store.LocalMode = not (memoryOk and dataOk)
if Store.LocalMode then
	warn(
		"[Store] MemoryStore/DataStore not available -> LOCAL TEST MODE (nothing is saved, only this server). "
			.. "For the real world market: publish the game and enable "
			.. "Game Settings > Security > 'Enable Studio Access to API Services'."
	)
end

local localMaps = {}

-- Wiederholt fn bei Fehlern (0,2 / 0,4 / 0,8 Sek. warten)
local function retry(label: string, fn)
	local delay = 0.2
	for attempt = 1, RETRIES do
		local ok, a, b = pcall(fn)
		if ok then
			return true, a, b
		end
		if attempt == RETRIES then
			warn(string.format("[Store] %s failed: %s", label, tostring(a)))
			return false, nil, nil
		end
		task.wait(delay)
		delay *= 2
	end
	return false, nil, nil
end

------------------------------------------------------------------------
-- Öffentliche Schnittstelle
------------------------------------------------------------------------
local Map = {}
Map.__index = Map

-- HashMap im MemoryStore (Weltmarkt). expiration in Sekunden (max. 45 Tage).
function Store.Map(name: string, expiration: number)
	local backend
	if Store.LocalMode then
		backend = localMaps[name] or LocalMap.new()
		localMaps[name] = backend
	else
		backend = MemoryStoreService:GetHashMap(name)
	end
	return setmetatable({ name = name, backend = backend, expiration = expiration }, Map)
end

-- -> ok, Wert
function Map:Get(key: string)
	local ok, value = retry(self.name .. ":Get " .. key, function()
		return self.backend:GetAsync(key)
	end)
	return ok, value
end

-- Atomar ändern mit einer Ledger-Funktion fn(alt, args) -> neu, ergebnis
-- -> ok, ergebnis, neuerWert (neuerWert = nil, wenn nichts geschrieben wurde)
-- expiration (optional): eigene Ablaufzeit für diesen Schreibvorgang
function Map:Update(key: string, fn, args, expiration: number?)
	local result
	local ok, newValue = retry(self.name .. ":Update " .. key, function()
		return self.backend:UpdateAsync(key, function(old)
			local new, r = fn(old, args)
			result = r
			return new
		end, expiration or self.expiration)
	end)
	return ok, result, newValue
end

-- Wie Update, aber OHNE Wiederholung. Für Buchungen, die keine eigene Nummer haben
-- (NPC-Trades, Gebühren): eine Wiederholung nach verlorener Antwort würde doppelt buchen.
-- -> ok, ergebnis, neuerWert. ok = false heißt: unklar, ob geschrieben wurde.
function Map:UpdateOnce(key: string, fn, args)
	local result
	local ok, newValue = pcall(function()
		return self.backend:UpdateAsync(key, function(old)
			local new, r = fn(old, args)
			result = r
			return new
		end, self.expiration)
	end)
	if not ok then
		warn(string.format("[Store] %s:UpdateOnce %s failed: %s", self.name, key, tostring(newValue)))
		return false, result, nil
	end
	return true, result, newValue
end

function Map:Set(key: string, value: any): boolean
	local ok = retry(self.name .. ":Set " .. key, function()
		return self.backend:SetAsync(key, value, self.expiration)
	end)
	return ok
end

function Map:Remove(key: string): boolean
	local ok = retry(self.name .. ":Remove " .. key, function()
		return self.backend:RemoveAsync(key)
	end)
	return ok
end

-- DataStore (dauerhaft). Gleiche Methoden Get/Update wie oben.
local Data = {}
Data.__index = Data

function Store.Data(name: string)
	local backend
	if Store.LocalMode then
		backend = localMaps["DS:" .. name] or LocalMap.new()
		localMaps["DS:" .. name] = backend
	else
		backend = DataStoreService:GetDataStore(name)
	end
	return setmetatable({ name = name, backend = backend }, Data)
end

function Data:Get(key: string)
	local ok, value = retry(self.name .. ":Get " .. key, function()
		return self.backend:GetAsync(key)
	end)
	return ok, value
end

-- fn(alt) -> neu
function Data:Update(key: string, fn)
	local ok, newValue = retry(self.name .. ":Update " .. key, function()
		return self.backend:UpdateAsync(key, function(old)
			return fn(old)
		end)
	end)
	return ok, newValue
end

return Store
