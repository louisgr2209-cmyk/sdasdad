-- CreateCoinUI (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/CreateCoinUI
-- Formular "Coin erstellen": Name, Ticker, Beschreibung, Icon (feste Auswahl), Dev-Buy (0/10/25/50 %).
-- Der Server prüft alles noch einmal (Level, Cash, Regeln, Roblox-Filter, Sperrliste).
--
-- Platz: Fenster 85 % breit, 484 hoch (passt in die kleinste Höhe von 496)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Screen = require(script.Parent.Screen)
local MarketClient = require(script.Parent.MarketClient)

local Colors = Screen.Colors
local L = Config.Launch
local ICON = 46

local CreateCoinUI = {}

function CreateCoinUI.new(parent: GuiObject)
	local self = {}
	local selectedIcon = Config.CoinIcons[1]
	local devIndex = 1

	local overlay = Screen.New("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Background,
		BackgroundTransparency = 0.3,
		Visible = false,
		ZIndex = 40,
		Parent = parent,
	})
	local panel = Screen.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.85, 0, 0, 484),
		BackgroundColor3 = Colors.Panel,
		Active = true,
		ZIndex = 41,
		Parent = overlay,
	}, {
		Screen.Corner(14),
		Screen.Padding(16),
		Screen.New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local function textBox(placeholder: string, maxLength: number, size: UDim2, order: number, parentFrame)
		local box = Screen.New("TextBox", {
			PlaceholderText = placeholder,
			Text = "",
			ClearTextOnFocus = false,
			Font = Screen.Fonts.Medium,
			TextSize = 22,
			TextColor3 = Colors.Text,
			PlaceholderColor3 = Colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = Colors.PanelLight,
			Size = size,
			LayoutOrder = order,
			ZIndex = 42,
			Parent = parentFrame,
		}, {
			Screen.Corner(10),
			Screen.New("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
		})
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if #box.Text > maxLength then
				box.Text = string.sub(box.Text, 1, maxLength)
			end
		end)
		return box
	end

	local function row(order: number, height: number)
		return Screen.New("Frame", {
			Size = UDim2.new(1, 0, 0, height),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			ZIndex = 42,
			Parent = panel,
		}, {
			Screen.New("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
	end

	Screen.Label({
		Text = "🚀 CREATE A COIN",
		Font = Screen.Fonts.Bold,
		TextSize = 30,
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 1,
		ZIndex = 42,
		Parent = panel,
	})

	local nameRow = row(2, 56)
	local nameBox = textBox(
		string.format("Name (%d-%d)", L.NameMin, L.NameMax),
		L.NameMax,
		UDim2.new(0.62, -4, 1, 0),
		1,
		nameRow
	)
	local tickerBox = textBox("TICKER (3-5)", L.TickerMax, UDim2.new(0.38, -4, 1, 0), 2, nameRow)
	tickerBox:GetPropertyChangedSignal("Text"):Connect(function()
		local upper = string.upper((string.gsub(tickerBox.Text, "[^%a]", "")))
		if upper ~= tickerBox.Text then
			tickerBox.Text = upper
		end
	end)
	local descBox = textBox(
		string.format("Short description (max. %d)", L.DescMax),
		L.DescMax,
		UDim2.new(1, 0, 0, 56),
		3,
		panel
	)

	-- Icons: 2 Reihen à 10
	local iconGrid = Screen.New("Frame", {
		Size = UDim2.new(1, 0, 0, ICON * 2 + 6),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		ZIndex = 42,
		Parent = panel,
	}, {
		Screen.New("UIGridLayout", {
			CellSize = UDim2.fromOffset(ICON, ICON),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local iconButtons = {}
	for i, icon in Config.CoinIcons do
		local button = Screen.Button({
			Text = icon,
			TextSize = 28,
			LayoutOrder = i,
			ZIndex = 43,
			Parent = iconGrid,
		})
		button.Activated:Connect(function()
			selectedIcon = icon
			self.Refresh()
		end)
		iconButtons[icon] = button
	end

	-- Dev-Buy
	local devRow = row(5, 56)
	Screen.Label({
		Text = "Dev buy:",
		TextSize = 22,
		Size = UDim2.new(0, 100, 1, 0),
		LayoutOrder = 0,
		ZIndex = 43,
		Parent = devRow,
	})
	local devButtons = {}
	for i, share in L.DevBuyOptions do
		local button = Screen.Button({
			Text = math.floor(share * 100 + 0.5) .. "%",
			TextSize = 22,
			Size = UDim2.new(0, 96, 1, 0),
			LayoutOrder = i,
			ZIndex = 43,
			Parent = devRow,
		})
		button.Activated:Connect(function()
			devIndex = i
			self.Refresh()
		end)
		devButtons[i] = button
	end

	local costLabel = Screen.Label({
		TextSize = 20,
		TextColor3 = Colors.Muted,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = 6,
		ZIndex = 42,
		Parent = panel,
	})

	local buttonRow = row(7, 72)
	local createButton = Screen.Button({
		Text = "CREATE",
		BackgroundColor3 = Colors.Green,
		Size = UDim2.new(0, 240, 1, 0),
		LayoutOrder = 1,
		ZIndex = 43,
		Parent = buttonRow,
	})
	local cancelButton = Screen.Button({
		Text = "CANCEL",
		Size = UDim2.new(0, 160, 1, 0),
		LayoutOrder = 2,
		ZIndex = 43,
		Parent = buttonRow,
	})

	function self.Refresh()
		for icon, button in iconButtons do
			button.BackgroundColor3 = if icon == selectedIcon then Colors.Accent else Colors.PanelLight
		end
		for i, button in devButtons do
			button.BackgroundColor3 = if i == devIndex then Colors.Border else Colors.PanelLight
		end
		local cash = MarketClient.Me.Cash or 0
		local devCash = math.max(0, cash - L.CreateCost) * L.DevBuyOptions[devIndex]
		costLabel.Text = string.format(
			"Cost: %s + dev buy %s · you get 5%% of the coins · %s Cash",
			Format.Short(L.CreateCost),
			Format.Short(devCash),
			if cash >= L.CreateCost then "enough" else "not enough"
		)
		costLabel.TextColor3 = if cash >= L.CreateCost then Colors.Muted else Colors.Red
	end

	function self.Show()
		self.Refresh()
		overlay.Visible = true
	end

	local function hide()
		overlay.Visible = false
	end

	-- Fenster bleibt offen, bis der Server antwortet: Erfolg -> zu, Fehler -> im Fenster anzeigen (nichts neu tippen)
	local waiting = false
	createButton.Activated:Connect(function()
		if waiting then
			return
		end
		waiting = true
		costLabel.Text = "Checking…"
		costLabel.TextColor3 = Colors.Muted
		MarketClient.CreateCoin(nameBox.Text, tickerBox.Text, descBox.Text, selectedIcon, devIndex)
		task.delay(8, function()
			waiting = false -- falls keine Antwort kommt: wieder klickbar
		end)
	end)
	MarketClient.TradeResult.Event:Connect(function(ok: boolean, message: string)
		if not waiting or not overlay.Visible then
			return
		end
		waiting = false
		if ok then
			hide()
			nameBox.Text, tickerBox.Text, descBox.Text = "", "", ""
		else
			costLabel.Text = "❌ " .. message
			costLabel.TextColor3 = Colors.Red
		end
	end)
	cancelButton.Activated:Connect(hide)
	overlay.Activated:Connect(hide)

	return self
end

return CreateCoinUI
