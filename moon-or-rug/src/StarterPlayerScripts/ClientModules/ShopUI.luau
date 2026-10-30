-- ShopUI (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/ShopUI
-- Shop-Fenster (🛒 oben): alle Robux-Produkte (Gutscheine) und Gamepässe auf einen Blick.
-- Fester Inhalt, keine Zufalls-Käufe. Der Server bucht jeden Kauf genau einmal.
--
-- Platz: Fenster 85 % breit, 484 hoch (passt in die kleinste Höhe von 496), Liste scrollt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Screen = require(script.Parent.Screen)
local MarketClient = require(script.Parent.MarketClient)

local Colors = Screen.Colors
local SHOP = Config.Shop
local ROW = 80
local ICONS = {
	CreateCoin = "🚀",
	Boost = "📈",
	Highlight = "✨",
	License = "☠",
	Pro = "📊",
	HalfInsurance = "🛡",
	DoubleDaily = "🎁",
	Vip = "⭐",
}

local ShopUI = {}

function ShopUI.new(parent: GuiObject)
	local self = {}

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
	})
	Screen.Label({
		Text = "🛒 SHOP",
		Font = Screen.Fonts.Bold,
		TextSize = 30,
		Size = UDim2.new(1, -180, 0, 36),
		ZIndex = 42,
		Parent = panel,
	})
	Screen.Label({
		Text = "Fixed items only · Cash can never be turned back into Robux",
		TextSize = 20,
		TextColor3 = Colors.Muted,
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, -180, 0, 24),
		ZIndex = 42,
		Parent = panel,
	})
	local closeButton = Screen.Button({
		Text = "CLOSE",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(160, 72),
		ZIndex = 42,
		Parent = panel,
	})

	local list = Screen.Scroller({
		Position = UDim2.fromOffset(0, 84),
		Size = UDim2.new(1, 0, 1, -84),
		ZIndex = 42,
		Parent = panel,
	})

	local rows = {}
	for i, name in SHOP.Order do
		local item = SHOP.Products[name] or SHOP.Passes[name]
		local isPass = SHOP.Passes[name] ~= nil
		local frame = Screen.New("Frame", {
			Size = UDim2.new(1, -10, 0, ROW),
			BackgroundColor3 = Colors.PanelLight,
			LayoutOrder = i,
			ZIndex = 43,
			Parent = list,
		}, {
			Screen.Corner(10),
		})
		Screen.Label({
			Text = ICONS[name] or "•",
			TextSize = 32,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.fromOffset(48, ROW),
			ZIndex = 44,
			Parent = frame,
		})
		local title = Screen.Label({
			Font = Screen.Fonts.Bold,
			Text = item.Title .. (if isPass then "  · pass" else ""),
			Position = UDim2.fromOffset(64, 10),
			Size = UDim2.new(1, -64 - 170, 0, 28),
			ZIndex = 44,
			Parent = frame,
		})
		local info = Screen.Label({
			Text = item.Info,
			TextSize = 20,
			TextColor3 = Colors.Muted,
			Position = UDim2.fromOffset(64, 42),
			Size = UDim2.new(1, -64 - 170, 0, 26),
			ZIndex = 44,
			Parent = frame,
		})
		local buy = Screen.Button({
			Text = "R$ " .. item.Robux,
			BackgroundColor3 = Colors.Green,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.fromOffset(156, 72),
			ZIndex = 44,
			Parent = frame,
		})
		buy.Activated:Connect(function()
			if isPass and MarketClient.HasPass(name) then
				return
			end
			MarketClient.Buy(name)
		end)
		rows[name] = { Title = title, Info = info, Buy = buy, IsPass = isPass, Item = item }
	end

	function self.Refresh()
		local me = MarketClient.Me
		local vouchers = me.Vouchers or {}
		local have = {
			CreateCoin = vouchers.CT or 0,
			Boost = me.FreeBoosts or 0,
			Highlight = vouchers.HT or 0,
			License = me.RugLicense or 0,
		}
		for name, row in rows do
			if row.IsPass then
				local owns = MarketClient.HasPass(name)
				row.Buy.Text = if owns then "OWNED" else "R$ " .. row.Item.Robux
				row.Buy.BackgroundColor3 = if owns then Colors.Border else Colors.Green
			else
				local count = have[name] or 0
				row.Info.Text = row.Item.Info .. (if count > 0 then string.format(" · you have %d", count) else "")
			end
		end
	end

	function self.Show()
		self.Refresh()
		overlay.Visible = true
	end

	local function hide()
		overlay.Visible = false
	end
	closeButton.Activated:Connect(hide)
	overlay.Activated:Connect(hide)

	return self
end

return ShopUI
