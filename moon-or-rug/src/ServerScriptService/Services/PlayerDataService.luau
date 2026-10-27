-- PlayerDataService (ModuleScript) – ServerScriptService/Services/PlayerDataService
-- Phase 1: Cash nur im Speicher. Speichern (DataStore, Retry, Session-Lock) kommt in Phase 4.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ServerScriptService.Util.Remotes)

local PlayerDataService = {}

-- Wird von Main gesetzt: function(key) -> { [coinId] = { Amount, Cost } }
PlayerDataService.PositionsProvider = nil :: ((string) -> any)?

local profiles = {} -- [Player] = { Cash = number }
local stateEvent: RemoteEvent

-- Cash immer auf 2 Nachkommastellen, abrunden (so entsteht nie Geld aus Rundung)
local function floorCents(n: number): number
	return math.floor(n * 100 + 1e-6) / 100
end
PlayerDataService.FloorCents = floorCents

function PlayerDataService.Key(player: Player): string
	return tostring(player.UserId)
end

function PlayerDataService.GetPlayerByKey(key: string): Player?
	local userId = tonumber(key)
	return if userId then Players:GetPlayerByUserId(userId) else nil
end

function PlayerDataService.GetCash(player: Player): number?
	local profile = profiles[player]
	return profile and profile.Cash
end

-- Ändert Cash. Gibt false zurück, wenn der Spieler nicht genug hat.
function PlayerDataService.AddCash(player: Player, delta: number): boolean
	local profile = profiles[player]
	if not profile or delta ~= delta then
		return false
	end
	local newCash = floorCents(profile.Cash + delta)
	if newCash < 0 then
		return false
	end
	profile.Cash = newCash
	return true
end

-- Geldbörse für MarketService (Spieler und später NPCs haben dieselbe Form)
function PlayerDataService.Wallet(player: Player)
	if not profiles[player] then
		return nil
	end
	return {
		Key = PlayerDataService.Key(player),
		Name = player.DisplayName,
		GetCash = function()
			return PlayerDataService.GetCash(player) or 0
		end,
		AddCash = function(delta: number)
			return PlayerDataService.AddCash(player, delta)
		end,
	}
end

function PlayerDataService.BuildState(player: Player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local provider = PlayerDataService.PositionsProvider
	return {
		Cash = profile.Cash,
		Positions = if provider then provider(PlayerDataService.Key(player)) else {},
	}
end

-- Schickt Cash + Positionen an den Client
function PlayerDataService.PushState(player: Player)
	local state = PlayerDataService.BuildState(player)
	if state then
		stateEvent:FireClient(player, state)
	end
end

local function onPlayerAdded(player: Player)
	profiles[player] = { Cash = Config.StartCash }
	PlayerDataService.PushState(player)
end

function PlayerDataService.Init()
	stateEvent = Remotes.Event("PlayerState")
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		profiles[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerDataService
