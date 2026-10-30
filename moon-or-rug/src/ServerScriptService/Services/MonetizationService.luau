-- MonetizationService (ModuleScript) – ServerScriptService/Services/MonetizationService
-- Robux (Phase 8):
--  * Developer Products (ProcessReceipt) geben Gutscheine: Coin erstellen, Boost, Highlight, Rug-Lizenz.
--    Gutschrift nur mit geladener Geldbörse auf DIESEM Server, Kauf-Nummer wird gemerkt -> nie doppelt,
--    erst danach "PurchaseGranted" (sonst wiederholt Roblox später, nichts geht verloren).
--  * Gamepässe: Pro-Terminal, Versicherung ½ Preis, Doppelter Daily, VIP. Besitz wird beim Join geprüft.
--  * Id = 0 (noch nicht angelegt): in Studio Test-Kauf über "ShopTestBuy", im echten Spiel nicht kaufbar.
--  * Pro: Top-10-Holder mit Namen (Server liest den Coin, max. 1 Anfrage pro 2 Sek.).
-- Keine Zufalls-Käufe, fester Inhalt, Cash nie zurück in Robux.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local UserService = game:GetService("UserService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ServerScriptService.Util.Remotes)
local RateLimiter = require(ServerScriptService.Util.RateLimiter)
local Ledger = require(ServerScriptService.Util.Ledger)
local WorldService = require(ServerScriptService.Services.WorldService)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local MarketService = require(ServerScriptService.Services.MarketService)

local SHOP = Config.Shop

local MonetizationService = {}

local productById = {} -- [ProductId] = Name
local passById = {} -- [PassId] = Name
local owned = {} -- [player] = { [PassName] = true }
local nameCache = {} -- [userId] = Anzeigename
local vipCache = {} -- [userId] = { Vip, At } (für die weltweite Rangliste)
local proLimiter = RateLimiter.new(1, SHOP.ProInfoCooldown)
local testLimiter = RateLimiter.new(1, 2)

function MonetizationService.HasPass(player: Player, name: string): boolean
	local passes = owned[player]
	return passes ~= nil and passes[name] == true
end

function MonetizationService.PassState(player: Player)
	local result = {}
	for name in SHOP.Passes do
		result[name] = MonetizationService.HasPass(player, name)
	end
	return result
end

------------------------------------------------------------------------
-- Gamepässe
------------------------------------------------------------------------

local function checkPasses(player: Player)
	local passes = owned[player] or {}
	for name, pass in SHOP.Passes do
		if pass.Id ~= 0 and not passes[name] then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
			end)
			if ok and has then
				passes[name] = true
			end
		end
	end
	owned[player] = passes
end

-- VIP-Status beliebiger Spieler (weltweite Rangliste), mit Zwischenspeicher
function MonetizationService.IsVipUserId(userId: number): boolean
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return MonetizationService.HasPass(player, "Vip")
	end
	local passId = SHOP.Passes.Vip.Id
	if passId == 0 then
		return false
	end
	local cached = vipCache[userId]
	local t = os.clock()
	if cached and t - cached.At < SHOP.VipCacheSeconds then
		return cached.Vip
	end
	local ok, has = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
	end)
	if not ok then
		return if cached then cached.Vip else false
	end
	vipCache[userId] = { Vip = has == true, At = t }
	return has == true
end

------------------------------------------------------------------------
-- Developer Products
------------------------------------------------------------------------

-- Gutschrift (echter Kauf oder Studio-Test). -> true, wenn gebucht (oder schon gebucht)
local function grant(player: Player, name: string, receipt: string): boolean
	local product = SHOP.Products[name]
	if not product or not PlayerDataService.GetWallet(player) then
		return false
	end
	local ok, result = PlayerDataService.WalletUpdate(player, Ledger.WalletGrantProduct, {
		Job = WorldService.JobId,
		Receipt = receipt,
		Grant = product.Grant,
		Uses = Config.Rug.LicenseUses,
	})
	if not ok or not result or not result.Ok then
		return false
	end
	if not result.Already then
		print(string.format("[Shop] %s (%d) bought %s (%s)", player.Name, player.UserId, name, receipt))
		PlayerDataService.Notify(player, true, "✅ Thanks! " .. product.Title .. " added")
		PlayerDataService.PushState(player)
		if name == "Highlight" then
			MarketService.Highlight(player) -- startet sofort am aktiven Coin (sonst mit dem nächsten)
		end
	end
	return true
end

local function processReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local name = productById[info.ProductId]
	if not player or not name then
		if not name then
			warn("[Shop] unknown product " .. tostring(info.ProductId))
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- warten, bis die Daten geladen sind (Kauf direkt nach dem Join)
	for _ = 1, 20 do
		if PlayerDataService.GetWallet(player) or not player.Parent then
			break
		end
		task.wait(0.5)
	end
	local ok, granted = pcall(grant, player, name, tostring(info.PurchaseId))
	if ok and granted then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox versucht es später nochmal
end

------------------------------------------------------------------------
-- Studio-Test (nur in Studio, nur für noch nicht angelegte Ids)
------------------------------------------------------------------------

local testCounter = 0
local function onTestBuy(player: Player, name: any)
	if not RunService:IsStudio() or not testLimiter:Allow(player) or typeof(name) ~= "string" then
		return
	end
	local product, pass = SHOP.Products[name], SHOP.Passes[name]
	if product and product.Id == 0 then
		testCounter += 1
		grant(player, name, string.format("studio-%d-%d-%d", player.UserId, os.time(), testCounter))
	elseif pass and pass.Id == 0 then
		owned[player] = owned[player] or {}
		owned[player][name] = true -- nur bis zum Verlassen (Studio)
		PlayerDataService.Notify(player, true, "✅ (Studio test) " .. pass.Title .. " unlocked")
		PlayerDataService.PushState(player)
	end
end

------------------------------------------------------------------------
-- Pro: Top 10 mit Namen
------------------------------------------------------------------------

local function namesFor(userIds: { number })
	local missing = {}
	for _, userId in userIds do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			nameCache[userId] = player.DisplayName
		elseif not nameCache[userId] then
			table.insert(missing, userId)
		end
	end
	if #missing > 0 then
		local ok, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync(missing)
		end)
		if ok then
			for _, info in infos do
				nameCache[info.Id] = info.DisplayName
			end
		end
	end
end

local function onProInfo(player: Player, coinId: any)
	if not MonetizationService.HasPass(player, "Pro") or not proLimiter:Allow(player) then
		return nil
	end
	if typeof(coinId) ~= "string" or #coinId > 20 then
		return nil
	end
	local list = MarketService.TopHolders(coinId)
	if not list then
		return nil
	end
	local ids = {}
	for _, entry in list do
		local userId = tonumber(entry.Key)
		if userId then
			table.insert(ids, userId)
		end
	end
	namesFor(ids)
	local result = {}
	for _, entry in list do
		local userId = tonumber(entry.Key)
		table.insert(result, {
			N = if userId then nameCache[userId] or ("Player " .. userId) else "🤖 Bot trader",
			S = entry.Share,
			D = entry.Dev or nil, -- Ersteller
			U = if userId then entry.Key else nil,
		})
	end
	return result
end

------------------------------------------------------------------------

function MonetizationService.Init()
	for name, product in SHOP.Products do
		if product.Id ~= 0 then
			productById[product.Id] = name
		end
	end
	for name, pass in SHOP.Passes do
		if pass.Id ~= 0 then
			passById[pass.Id] = name
		end
	end
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local name = passById[passId]
		if purchased and name then
			owned[player] = owned[player] or {}
			owned[player][name] = true
			print(string.format("[Shop] %s (%d) bought pass %s", player.Name, player.UserId, name))
			PlayerDataService.Notify(player, true, "✅ Thanks! " .. SHOP.Passes[name].Title .. " unlocked")
			PlayerDataService.PushState(player)
		end
	end)
	Remotes.Event("ShopTestBuy").OnServerEvent:Connect(onTestBuy)
	Remotes.Function("ProInfo").OnServerInvoke = onProInfo
	PlayerDataService.PassState = MonetizationService.PassState

	local function onJoin(player: Player)
		checkPasses(player)
		PlayerDataService.PushState(player)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		proLimiter:Remove(player)
		testLimiter:Remove(player)
	end)
end

return MonetizationService
