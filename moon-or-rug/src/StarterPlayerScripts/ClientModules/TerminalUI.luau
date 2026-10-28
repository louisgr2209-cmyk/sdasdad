-- TerminalUI (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/TerminalUI
-- Vollbild-Terminal: Kopfleiste (Logo, Tabs, Cash), Seiten (Pulse, Coin, Portfolio), Ticker unten.
-- Platz für später in der Kopfleiste: Level (Phase 4), Daily Reward (Phase 5), Shop (Phase 8).
--
-- Höhen (Design-Pixel, mind. 560): 12 Rand | Kopf 72 | 10 | Seite (Rest, mind. 408) | 10 | Ticker 36 | 12 Rand

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Screen = require(script.Parent.Screen)
local MarketClient = require(script.Parent.MarketClient)
local PulseList = require(script.Parent.PulseList)
local CoinPage = require(script.Parent.CoinPage)
local Portfolio = require(script.Parent.Portfolio)

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
	Screen.Label({
		Text = "🚀 MOON OR RUG",
		Font = Screen.Fonts.Bold,
		TextSize = 28,
		Size = UDim2.new(0, 230, 1, 0),
		Parent = header,
	})
	local tabBar = Screen.New("Frame", {
		Position = UDim2.fromOffset(240, 0),
		Size = UDim2.new(1, -240 - 260, 1, 0),
		BackgroundTransparency = 1,
		Parent = header,
	}, {
		Screen.New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local cashLabel = Screen.Label({
		Font = Screen.Fonts.Bold,
		TextSize = 28,
		TextColor3 = Colors.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 250, 1, 0),
		Parent = header,
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
	pages.Pulse = { Frame = pulseFrame, View = PulseList.new(pulseFrame, openCoin) }
	local coinFrame = page("Coin")
	pages.Coin = {
		Frame = coinFrame,
		View = CoinPage.new(coinFrame, function()
			show(lastTab)
		end),
	}
	local portfolioFrame = page("Portfolio")
	pages.Portfolio = { Frame = portfolioFrame, View = Portfolio.new(portfolioFrame, openCoin) }

	for i, tabName in { "Pulse", "Portfolio" } do
		local button = Screen.Button({
			Text = string.upper(tabName),
			TextSize = 24,
			Size = UDim2.new(0, 170, 1, -8),
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
		ZIndex = 10,
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
	-- Aktualisieren
	------------------------------------------------------------------
	MarketClient.Changed.Event:Connect(function()
		cashLabel.Text = "💵 " .. Format.Cash(MarketClient.Me.Cash)
		pages[current].View.Refresh()
	end)
	cashLabel.Text = "💵 …"
	show("Pulse")
end

return TerminalUI
