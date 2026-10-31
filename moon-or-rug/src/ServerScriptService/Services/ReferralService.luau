-- ReferralService (ModuleScript) – ServerScriptService/Services/ReferralService
-- Teil-Link / Teil-Code (von der PNL-Karte):
--  * Wer über den geteilten Link kommt (LaunchData "ref=<UserId>") oder den Code eingibt, wird einmal im ganzen
--    Spiel einem Werber zugeordnet (getrennt vom Creator-Code).
--  * Ausgezahlt wird erst, wenn Konto ≥ 7 Tage alt und ≥ 30 Min. gespielt (gegen Zweit-Accounts):
--    der Neue +Reward, der Werber +Reward (übers Postfach, auch wenn er offline ist).
--  * Nie doppelt: Ledger merkt St.RB (bezahlt); Werber-Gutschrift ohne Wiederholung.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Referral = require(ReplicatedStorage.Shared.Referral)
local Store = require(ServerScriptService.Util.Store)
local Ledger = require(ServerScriptService.Util.Ledger)
local WorldService = require(ServerScriptService.Services.WorldService)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)

local RF = Config.Referral
local W = Config.World

local ReferralService = {}

local inboxMap = Store.Map(W.InboxMap, W.CoinExpiration)

-- Werber merken. -> ok, Meldung
local function setReferrer(player: Player, refId: number): (boolean, string)
	if refId == player.UserId then
		return false, "You can't use your own share code"
	end
	-- nur Codes von Spielern, die wirklich schon gespielt haben (sonst könnte man sich einen ausdenken)
	local exists = PlayerDataService.HasProfile(refId)
	if exists == nil then
		return false, "Please try again"
	elseif not exists and not Store.LocalMode then
		return false, "Code not found"
	end
	local ok, result = PlayerDataService.WalletUpdate(player, Ledger.WalletReferPending, {
		Job = WorldService.JobId,
		Ref = refId,
	})
	if not ok or not result then
		return false, "Please try again"
	end
	if not result.Ok then
		return false, result.Error or "Please try again"
	end
	return true, "🔗 Friend code saved!"
end

-- Belohnung fällig? (Konto alt genug, genug gespielt)
local function tryPay(player: Player)
	local wallet = PlayerDataService.GetWallet(player)
	local st = wallet and wallet.St
	if not st or not st.RP or st.RB then
		return
	end
	if player.AccountAge < RF.MinAccountAgeDays or (st.PT or 0) < RF.MinPlaytimeMinutes * 60 then
		return
	end
	local ok, result = PlayerDataService.WalletUpdate(player, Ledger.WalletReferPay, {
		Job = WorldService.JobId,
		Cash = RF.Reward,
	})
	if not ok or not result or not result.Ok then
		return
	end
	PlayerDataService.Notify(player, true, "🔗 Friend bonus: +" .. Format.Cash(RF.Reward))
	PlayerDataService.PushState(player)
	-- Werber: ohne Wiederholung (im Zweifel fehlt die Gutschrift einmal, aber nie doppelt)
	inboxMap:UpdateOnce("u_" .. tostring(result.Ref), Ledger.InboxAdd, {
		Adds = { Cash = RF.Reward, Ref = RF.Reward },
	})
end

-- Code eingegeben (aus dem Code-Feld im 🎁-Fenster, vom CreatorService weitergereicht)
function ReferralService.Redeem(player: Player, code: string)
	local refId = Referral.Decode(code)
	if not refId then
		return PlayerDataService.Notify(player, false, "Code not found")
	end
	local ok, message = setReferrer(player, refId)
	if ok then
		local wallet = PlayerDataService.GetWallet(player)
		local st = (wallet and wallet.St) or {}
		local left = RF.MinPlaytimeMinutes * 60 - (st.PT or 0)
		if player.AccountAge < RF.MinAccountAgeDays then
			message ..= string.format(" Bonus once your account is %d days old.", RF.MinAccountAgeDays)
		elseif left > 0 then
			message ..= string.format(" Bonus after %d more minutes of play.", math.ceil(left / 60))
		end
		tryPay(player)
	end
	PlayerDataService.Notify(player, ok, message)
	PlayerDataService.PushState(player)
end

-- Zusatz-Infos für den Client
function ReferralService.State(player: Player)
	local wallet = PlayerDataService.GetWallet(player)
	local st = (wallet and wallet.St) or {}
	return {
		Code = Referral.Code(player.UserId),
		Status = if st.RB then "done" elseif st.RP then "pending" else "none",
	}
end

-- Über einen geteilten Link gekommen? (LaunchData "ref=<UserId>")
local function checkJoinData(player: Player)
	local ok, joinData = pcall(player.GetJoinData, player)
	local launch = ok and type(joinData) == "table" and joinData.LaunchData
	if type(launch) ~= "string" or #launch > 200 then
		return
	end
	local refId = tonumber(string.match(launch, "^ref=(%d+)$"))
	if refId then
		setReferrer(player, refId) -- Fehler (schon zugeordnet usw.) still ignorieren
	end
end

function ReferralService.Init()
	local function onJoin(player: Player)
		for _ = 1, 60 do -- warten, bis die Geldbörse geladen ist
			if not player.Parent then
				return
			end
			if PlayerDataService.GetWallet(player) then
				checkJoinData(player)
				tryPay(player)
				PlayerDataService.PushState(player)
				return
			end
			task.wait(1)
		end
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	task.spawn(function()
		while true do
			task.wait(RF.CheckInterval)
			for _, player in PlayerDataService.LoadedPlayers() do
				local ok, err = pcall(tryPay, player)
				if not ok then
					warn("[Referral] " .. tostring(err))
				end
			end
		end
	end)
end

return ReferralService
