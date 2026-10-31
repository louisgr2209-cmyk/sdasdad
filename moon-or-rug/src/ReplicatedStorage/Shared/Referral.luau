-- Referral (ModuleScript) – ReplicatedStorage/Shared/Referral
-- Persönlicher Teil-Code aus der Roblox-UserId: "LNR" + UserId in Basis 36 (z. B. LNR1A2B3C).
-- Eindeutig, ohne Speicher. Creator-Codes dürfen nicht mit "LNR" beginnen (sonst Verwechslung).

local Config = require(script.Parent.Config)

local DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local PREFIX = Config.Referral.Prefix

local Referral = {}

function Referral.Code(userId: number): string
	local n = math.floor(math.abs(userId))
	local out = ""
	repeat
		local d = n % 36
		out = string.sub(DIGITS, d + 1, d + 1) .. out
		n = math.floor(n / 36)
	until n == 0
	return PREFIX .. out
end

-- Code -> UserId oder nil (nur Format, ob es den Spieler gibt, prüft der Server nicht – reicht für die Belohnung)
function Referral.Decode(code: string): number?
	if string.sub(code, 1, #PREFIX) ~= PREFIX then
		return nil
	end
	local rest = string.sub(code, #PREFIX + 1)
	if #rest < 1 or #rest > 9 then
		return nil
	end
	local n = 0
	for i = 1, #rest do
		local d = string.find(DIGITS, string.sub(rest, i, i), 1, true)
		if not d then
			return nil
		end
		n = n * 36 + (d - 1)
	end
	return if n > 0 then n else nil
end

function Referral.IsReferralCode(code: string): boolean
	return string.sub(code, 1, #PREFIX) == PREFIX
end

return Referral
