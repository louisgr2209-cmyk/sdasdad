-- TerminalUI (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/TerminalUI
-- Vollbild-Terminal: Kopfleiste (Logo, Tabs, Cash + Level), Seiten (Pulse, Coin, Portfolio, Leaderboard),
-- Ticker unten, Level-Up-Banner, Daily-Reward-Knopf. Platz für später: Shop (Phase 8).
-- Breite (mind. 976): Logo 180 | 10 | Tabs 3 x 140 + 2 x 10 = 440 | Daily 64 | 10 | Cash/Level 230
-- Admins: statt des Logos "🚀" 56 + ADMIN-Knopf 118 (gleiche Breite 180)
--
-- Höhen (Design-Pixel, mind. 520): 12 Rand | Kopf 72 | 10 | Seite (Rest, mind. 368) | 10 | Ticker 36 | 12 Rand

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Screen = require(script.Parent.Screen)
local MarketClient = require(script.Parent.MarketClient)
local PulseList = require(script.Parent.PulseList)
local CoinPage = require(script.Parent.CoinPage)
local Portfolio = require(script.Parent.Portfolio)
local LeaderboardUI = require(script.Parent.LeaderboardUI)
local DailyRewardUI = require(script.Parent.DailyRewardUI)
local CreateCoinUI = require(script.Parent.CreateCoinUI)
local AdminUI = require(script.Parent.AdminUI)
local Levels = require(ReplicatedStorage.Shared.Levels)

local Colors = Screen.Colors
local HEADER = 72
local TICKER = 36
local GAP = 10

local TerminalUI = {}

function TerminalUI.Start()
	MarketClient.Start()

	local root = Screen.CreateRoot("Terminal")
	Screen.Padding(12).Parent = root

	------------------------------------------------------------------
	-- Kopfleiste
	------------------------------------------------------------------
	local header = Screen.New("Frame", {
		Size = UDim2.new(1, 0, 0, HEADER),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local logo = Screen.Label({
		Text = "🚀 MOON OR RUG",
		Font = Screen.Fonts.Bold,
		TextSize = 24,
		Size = UDim2.new(0, 180, 1, 0),
		Parent = header,
	})
	-- ADMIN-Knopf: nur für Admins sichtbar (Server prüft jede Admin-Anfrage trotzdem)
	local adminButton = Screen.Button({
		Text = "ADMIN",
		TextSize = 22,
		BackgroundColor3 = Colors.Red,
		Position = UDim2.fromOffset(62, 4),
		Size = UDim2.fromOffset(118, 64),
		Visible = false,
		Parent = header,
	})
	local tabBar = Screen.New("Frame", {
		Position = UDim2.fromOffset(190, 0),
		Size = UDim2.new(1, -190 - 240 - 74, 1, 0),
		BackgroundTransparency = 1,
		Parent = header,
	}, {
		Screen.New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	-- Daily-Reward-Knopf (leuchtet, wenn bereit)
	local dailyButton = Screen.Button({
		Text = "🎁",
		TextSize = 32,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -240, 0, 4),
		Size = UDim2.fromOffset(64, 64),
		Parent = header,
	})

	-- Rechts: Cash, darunter Level + XP-Balken
	local wallet = Screen.New("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 230, 1, 0),
		BackgroundTransparency = 1,
		Parent = header,
	})
	local cashLabel = Screen.Label({
		Font = Screen.Fonts.Bold,
		TextSize = 26,
		TextColor3 = Colors.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, 0, 0, 36),
		Parent = wallet,
	})
	local levelLabel = Screen.Label({
		TextSize = 20,
		TextColor3 = Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = wallet,
	})
	local xpBar = Screen.New("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 62),
		Size = UDim2.new(0, 150, 0, 6),
		BackgroundColor3 = Colors.PanelLight,
		Parent = wallet,
	}, {
		Screen.Corner(3),
	})
	local xpFill = Screen.New("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Green,
		Parent = xpBar,
	}, {
		Screen.Corner(3),
	})

	------------------------------------------------------------------
	-- Seiten
	------------------------------------------------------------------
	local pageArea = Screen.New("Frame", {
		Position = UDim2.fromOffset(0, HEADER + GAP),
		Size = UDim2.new(1, 0, 1, -(HEADER + GAP + GAP + TICKER)),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local function page(name: string)
		return Screen.New("Frame", {
			Name = name,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = pageArea,
		})
	end

	local pages = {}
	local current = "Pulse"
	local lastTab = "Pulse"
	local tabButtons = {}

	local function show(name: string)
		current = name
		if name ~= "Coin" then
			lastTab = name
		end
		for pageName, entry in pages do
			entry.Frame.Visible = pageName == name
		end
		for tabName, button in tabButtons do
			button.BackgroundColor3 = if tabName == lastTab then Colors.Border else Colors.PanelLight
		end
		pages[name].View.Refresh()
	end

	local function openCoin(coinId: string)
		pages.Coin.View.Show(coinId)
		show("Coin")
	end

	local pulseFrame = page("Pulse")
	local createUI -- Formular "Coin erstellen" (wird unten gebaut, liegt über allem)
	pages.Pulse = {
		Frame = pulseFrame,
		View = PulseList.new(pulseFrame, openCoin, function()
			local stats = MarketClient.Me.Stats
			if stats and stats.Level < Config.Launch.CreateMinLevel then
				MarketClient.TradeResult:Fire(false, "Creating coins unlocks at level " .. Config.Launch.CreateMinLevel)
				return
			end
			createUI.Show()
		end),
	}
	local coinFrame = page("Coin")
	pages.Coin = {
		Frame = coinFrame,
		View = CoinPage.new(coinFrame, function()
			show(lastTab)
		end),
	}
	local portfolioFrame = page("Portfolio")
	pages.Portfolio = { Frame = portfolioFrame, View = Portfolio.new(portfolioFrame, openCoin) }
	local leaderboardFrame = page("Leaderboard")
	pages.Leaderboard = { Frame = leaderboardFrame, View = LeaderboardUI.new(leaderboardFrame) }

	for i, tabName in { "Pulse", "Portfolio", "Leaderboard" } do
		local button = Screen.Button({
			Text = string.upper(tabName),
			TextSize = 20,
			Size = UDim2.new(0, 140, 1, -8),
			LayoutOrder = i,
			Parent = tabBar,
		})
		button.Activated:Connect(function()
			show(tabName)
		end)
		tabButtons[tabName] = button
	end

	------------------------------------------------------------------
	-- Ticker unten (Rugpulls, große Gewinne)
	------------------------------------------------------------------
	local ticker = Screen.New("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, TICKER),
		BackgroundColor3 = Colors.Panel,
		Parent = root,
	}, {
		Screen.Corner(8),
	})
	local tickerLabel = Screen.Label({
		Text = Config.Ticker.IdleText,
		TextSize = 20,
		TextColor3 = Colors.Muted,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -24, 1, 0),
		Parent = ticker,
	})
	local newsQueue = {}
	MarketClient.News.Event:Connect(function(news)
		table.insert(newsQueue, news)
		while #newsQueue > 10 do
			table.remove(newsQueue, 1)
		end
	end)
	task.spawn(function()
		while true do
			local news = table.remove(newsQueue, 1)
			if news then
				tickerLabel.Text = (if news.Kind == "Rug" then "🚨 " else "💰 ") .. news.Text
				tickerLabel.TextColor3 = if news.Kind == "Rug" then Colors.Red else Colors.Accent
				task.wait(Config.Ticker.ShowSeconds)
			else
				tickerLabel.Text = Config.Ticker.IdleText
				tickerLabel.TextColor3 = Colors.Muted
				task.wait(0.5)
			end
		end
	end)

	------------------------------------------------------------------
	-- Hinweis nach einem Trade (oben in der Mitte, verschwindet wieder)
	------------------------------------------------------------------
	local toast = Screen.Label({
		Font = Screen.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		BackgroundColor3 = Colors.PanelLight,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, HEADER + GAP + 4),
		Size = UDim2.new(0.6, 0, 0, 44),
		Visible = false,
		ZIndex = 60, -- über allen Fenstern (z. B. Code einlösen)
		Parent = root,
	})
	Screen.Corner(10).Parent = toast
	local toastId = 0
	MarketClient.TradeResult.Event:Connect(function(ok: boolean, message: string)
		toastId += 1
		local myId = toastId
		toast.Text = message
		toast.TextColor3 = if ok then Colors.Green else Colors.Red
		toast.Visible = true
		task.delay(2.5, function()
			if toastId == myId then
				toast.Visible = false
			end
		end)
	end)

	------------------------------------------------------------------
	-- Level-Up-Banner (oben in der Mitte, 4 Sek.)
	------------------------------------------------------------------
	local banner = Screen.Label({
		Font = Screen.Fonts.Bold,
		TextSize = 24, -- längster Text (ca. 55 Zeichen) passt bei 1000 Breite
		TextColor3 = Colors.Background,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		BackgroundColor3 = Colors.Accent,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, HEADER + GAP + 54),
		Size = UDim2.new(0.8, 0, 0, 56),
		Visible = false,
		ZIndex = 11,
		Parent = root,
	})
	Screen.Corner(12).Parent = banner
	local bannerId = 0
	local function showLevelUp(level: number)
		local rank = Levels.Rank(level)
		local unlock = Levels.UnlockAt(level)
		banner.Text = string.format("LEVEL UP!  Lv %d · %s", level, rank.Rank)
			.. (if unlock then " – " .. unlock.Unlock .. " unlocked" else "")
		banner.Visible = true
		bannerId += 1
		local myId = bannerId
		task.delay(4, function()
			if bannerId == myId then
				banner.Visible = false
			end
		end)
	end

	------------------------------------------------------------------
	-- Aktualisieren
	------------------------------------------------------------------
	local daily = DailyRewardUI.new(root)
	createUI = CreateCoinUI.new(root)
	dailyButton.Activated:Connect(daily.Show)
	local admin = AdminUI.new(root)
	adminButton.Activated:Connect(admin.Show)

	local lastLevel = nil
	MarketClient.Changed.Event:Connect(function()
		local dailyState = MarketClient.Me.Daily
		dailyButton.BackgroundColor3 = if dailyState and dailyState.CanClaim then Colors.Accent else Colors.PanelLight
		daily.Refresh()
		createUI.RefreshLicense() -- z. B. Lizenz gekauft
		local isAdmin = MarketClient.Me.Extra ~= nil and MarketClient.Me.Extra.IsAdmin == true
		adminButton.Visible = isAdmin
		logo.Text = if isAdmin then "🚀" else "🚀 MOON OR RUG"
		logo.Size = UDim2.new(0, if isAdmin then 56 else 180, 1, 0)
		cashLabel.Text = "💵 " .. Format.Cash(MarketClient.Me.Cash)
		local stats = MarketClient.Me.Stats
		if stats then
			local level, progress = Levels.Progress(stats.Xp)
			levelLabel.Text = string.format("Lv %d · %s", level, Levels.Rank(level).Rank)
			xpFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
			if lastLevel and level > lastLevel then
				showLevelUp(level)
			end
			lastLevel = level
		end
		pages[current].View.Refresh()
	end)
	levelLabel.Text = ""
	cashLabel.Text = "💵 …"
	show("Pulse")
end

return TerminalUI
