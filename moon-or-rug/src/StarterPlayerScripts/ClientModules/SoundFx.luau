-- SoundFx (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/SoundFx
-- Wenige, dezente Sounds: Klick, Erfolg, Fehler, Level-Up, Rugpull-Alarm. Nur auf diesem Gerät.
-- Aus/an im Portfolio (wird gespeichert). Fehlt eine Datei, bleibt es einfach still.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)

local SoundFx = {}
SoundFx.Muted = false

local sounds = {} -- [Name] = Sound

local function get(name: string): Sound?
	local def = Config.Sounds[name]
	if type(def) ~= "table" then
		return nil
	end
	local sound = sounds[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "MoR_" .. name
		sound.SoundId = def.Id
		sound.PlaybackSpeed = def.Speed or 1
		sound.Volume = Config.Sounds.Volume
		sound.Parent = SoundService
		sounds[name] = sound
	end
	return sound
end

function SoundFx.Play(name: string)
	if SoundFx.Muted then
		return
	end
	local sound = get(name)
	if sound then
		pcall(SoundService.PlayLocalSound, SoundService, sound)
	end
end

return SoundFx
