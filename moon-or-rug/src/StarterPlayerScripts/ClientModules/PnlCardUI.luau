-- PnlCardUI (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/PnlCardUI
-- PNL-Karte zum Teilen (wie bei Trading-Terminals): Coin, Gewinn in %, Einsatz -> Wert, Name, Teil-Code.
-- Eigener Schalter LNR / $ (unabhängig von der Voreinstellung). 📸 SHARE: Roblox-Screenshot teilen,
-- der Einladungslink enthält "ref=<UserId>" -> wer darüber kommt, bekommt (wie der Teilende) einen Bonus.
--
-- Platz: Karte 560 x 490 in der Mitte (passt in 976 x 496), Knöpfe unten in der Karte.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CaptureService = game:GetService("CaptureService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Referral = require(ReplicatedStorage.Shared.Referral)
local Screen = require(script.Parent.Screen)
local MarketClient = require(script.Parent.MarketClient)

local Colors = Screen.Colors
local Z = 50

local PnlCardUI = {}

function PnlCardUI.new(parent: GuiObject)
	local self = {}
	local data = nil -- { Icon, Ticker, Cost, Value, Sold }
	local unit = Format.Unit

	local overlay = Screen.New("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Background,
		BackgroundTransparency = 0.2,
		Visible = false,
		ZIndex = Z,
		Parent = parent,
	})
	local card = Screen.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 490),
		BackgroundColor3 = Colors.Panel,
		Active = true,
		ZIndex = Z + 1,
		Parent = overlay,
	}, {
		Screen.Corner(18),
		Screen.Padding(18),
	})
	local stroke = Screen.New("UIStroke", { Thickness = 3, Parent = card })

	local function label(props)
		props.ZIndex = Z + 2
		props.Parent = card
		return Screen.Label(props)
	end
	label({
		Text = "🚀 MOON OR RUG",
		Font = Screen.Fonts.Bold,
		TextSize = 22,
		TextColor3 = Colors.Muted,
		Size = UDim2.new(1, 0, 0, 26),
	})
	local coinLabel = label({
		Font = Screen.Fonts.Bold,
		TextSize = 34,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 40),
	})
	local percentLabel = label({
		Font = Screen.Fonts.Bold,
		TextSize = 72,
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 0, 80),
	})
	local profitLabel = label({
		Font = Screen.Fonts.Bold,
		TextSize = 30,
		Position = UDim2.fromOffset(0, 162),
		Size = UDim2.new(1, 0, 0, 36),
	})
	local detailLabel = label({
		TextSize = 22,
		TextColor3 = Colors.Muted,
		Position = UDim2.fromOffset(0, 202),
		Size = UDim2.new(1, 0, 0, 28),
	})
	local nameLabel = label({
		TextSize = 22,
		Position = UDim2.fromOffset(0, 240),
		Size = UDim2.new(1, 0, 0, 28),
	})
	local codeLabel = label({
		Font = Screen.Fonts.Bold,
		TextSize = 22,
		TextColor3 = Colors.Accent,
		Position = UDim2.fromOffset(0, 272),
		Size = UDim2.new(1, 0, 0, 28),
	})

	-- Knöpfe (werden beim Screenshot kurz ausgeblendet)
	local controls = Screen.New("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 72 + 8 + 72),
		BackgroundTransparency = 1,
		ZIndex = Z + 2,
		Parent = card,
	})
	local function button(text: string, x: number, y: number, width: number, color: Color3?)
		return Screen.Button({
			Text = text,
			TextSize = 22,
			BackgroundColor3 = color or Colors.PanelLight,
			Position = UDim2.new(x, 0, 0, y),
			Size = UDim2.new(width, -6, 0, 72),
			ZIndex = Z + 3,
			Parent = controls,
		})
	end
	local lnrButton = button(Config.Currency.Symbol, 0, 0, 0.5)
	local usdButton = button("$ Dollar", 0.5, 0, 0.5)
	local shareButton = button("📸 SHARE", 0, 80, 0.6, Colors.Green)
	local closeButton = button("CLOSE", 0.6, 80, 0.4)

	local function render()
		if not data then
			return
		end
		local profit = data.Value - data.Cost
		local percent = if data.Cost > 0 then profit / data.Cost else 0
		local color = if profit >= 0 then Colors.Green else Colors.Red
		stroke.Color = color
		coinLabel.Text = string.format("%s $%s", data.Icon or "", data.Ticker or "?")
		percentLabel.Text = Format.Percent(percent)
		percentLabel.TextColor3 = color
		profitLabel.Text = (if profit >= 0 then "+" else "") .. Format.Money(profit, unit)
		profitLabel.TextColor3 = color
		detailLabel.Text = string.format(
			"Invested %s → %s %s",
			Format.Money(data.Cost, unit),
			if data.Sold then "sold for" else "now",
			Format.Money(data.Value, unit)
		)
		nameLabel.Text = "Trader: " .. Players.LocalPlayer.DisplayName
		codeLabel.Text = string.format(
			"Join with code %s → +%s bonus",
			Referral.Code(Players.LocalPlayer.UserId),
			Format.Money(Config.Referral.Reward, unit)
		)
		lnrButton.BackgroundColor3 = if unit == "LNR" then Colors.Accent else Colors.PanelLight
		usdButton.BackgroundColor3 = if unit == "USD" then Colors.Accent else Colors.PanelLight
	end

	-- data = { Icon, Ticker, Cost (Einsatz, intern), Value (jetzt/verkauft, intern), Sold = true/false }
	function self.Show(cardData)
		data = cardData
		unit = Format.Unit -- startet mit der Voreinstellung, eigener Schalter auf der Karte
		render()
		overlay.Visible = true
	end

	local function hide()
		overlay.Visible = false
	end

	lnrButton.Activated:Connect(function()
		unit = "LNR"
		render()
	end)
	usdButton.Activated:Connect(function()
		unit = "USD"
		render()
	end)
	closeButton.Activated:Connect(hide)
	overlay.Activated:Connect(hide)

	-- Screenshot ohne Knöpfe, dann Robloxs Teilen-Fenster mit Einladungslink (ref=<UserId>)
	local busy = false
	shareButton.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		controls.Visible = false
		task.wait(0.1) -- ein Bild ohne Knöpfe zeichnen lassen
		local ok = pcall(function()
			CaptureService:CaptureScreenshot(function(contentId)
				controls.Visible = true
				busy = false
				local okShare = pcall(function()
					CaptureService:PromptShareCapture(contentId, "ref=" .. Players.LocalPlayer.UserId, function() end, function() end)
				end)
				if not okShare then
					MarketClient.TradeResult:Fire(false, "Sharing isn't available here – take a screenshot instead!")
				end
			end)
		end)
		if not ok then
			controls.Visible = true
			busy = false
			MarketClient.TradeResult:Fire(false, "Sharing isn't available here – take a screenshot instead!")
		end
		task.delay(5, function() -- falls der Screenshot nie fertig wird
			if busy then
				controls.Visible = true
				busy = false
			end
		end)
	end)

	return self
end

return PnlCardUI
