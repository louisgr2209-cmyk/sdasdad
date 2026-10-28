-- DailyRewardUI (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/DailyRewardUI
-- Fenster mit den 7 Tagen des Daily Rewards und CLAIM-Knopf.
-- Der Server entscheidet, ob abgeholt werden darf (einmal pro Tag, Lücke = Tag 1).
--
-- Platz: Fenster 80 % breit (bei 1000 Breite ca. 100 pro Tag), 330 hoch (passt in 496)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Screen = require(script.Parent.Screen)
local MarketClient = require(script.Parent.MarketClient)

local Colors = Screen.Colors
local DAYS = Config.Protection.Daily

local DailyRewardUI = {}

function DailyRewardUI.new(parent: GuiObject)
	local self = {}

	local overlay = Screen.New("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Background,
		BackgroundTransparency = 0.3,
		Visible = false,
		ZIndex = 30,
		Parent = parent,
	})
	local panel = Screen.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.8, 0, 0, 330),
		BackgroundColor3 = Colors.Panel,
		Active = true,
		ZIndex = 31,
		Parent = overlay,
	}, {
		Screen.Corner(14),
		Screen.Padding(16),
	})
	Screen.Label({
		Text = "🎁 DAILY REWARD",
		Font = Screen.Fonts.Bold,
		TextSize = 30,
		Size = UDim2.new(1, 0, 0, 36),
		ZIndex = 32,
		Parent = panel,
	})
	local subtitle = Screen.Label({
		TextColor3 = Colors.Muted,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 26),
		ZIndex = 32,
		Parent = panel,
	})

	local row = Screen.New("Frame", {
		Position = UDim2.fromOffset(0, 76),
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundTransparency = 1,
		ZIndex = 32,
		Parent = panel,
	}, {
		Screen.New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local boxes = {}
	for day, amount in DAYS do
		local box = Screen.New("Frame", {
			Size = UDim2.new(1 / #DAYS, -8 * (#DAYS - 1) / #DAYS, 1, 0),
			BackgroundColor3 = Colors.PanelLight,
			LayoutOrder = day,
			ZIndex = 32,
			Parent = row,
		}, {
			Screen.Corner(10),
		})
		Screen.Label({
			Text = "Day " .. day,
			TextSize = 20,
			TextColor3 = Colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 10),
			Size = UDim2.new(1, 0, 0, 24),
			ZIndex = 33,
			Parent = box,
		})
		Screen.Label({
			Text = Format.Cash(amount):gsub("%.00$", ""),
			Font = Screen.Fonts.Bold,
			TextSize = 26,
			TextColor3 = Colors.Accent,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 42),
			Size = UDim2.new(1, 0, 0, 32),
			ZIndex = 33,
			Parent = box,
		})
		local mark = Screen.Label({
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 80),
			Size = UDim2.new(1, 0, 0, 30),
			ZIndex = 33,
			Parent = box,
		})
		local stroke = Screen.New("UIStroke", {
			Color = Colors.Accent,
			Thickness = 3,
			Enabled = false,
			Parent = box,
		})
		boxes[day] = { Mark = mark, Stroke = stroke }
	end

	local claim = Screen.Button({
		Text = "CLAIM",
		BackgroundColor3 = Colors.Green,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.fromOffset(260, 72),
		ZIndex = 32,
		Parent = panel,
	})
	local close = Screen.Button({
		Text = "CLOSE",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(160, 72),
		ZIndex = 32,
		Parent = panel,
	})

	function self.Refresh()
		local daily = MarketClient.Me.Daily
		if not daily then
			subtitle.Text = "Loading…"
			claim.Visible = false
			return
		end
		claim.Visible = daily.CanClaim
		subtitle.Text = if daily.CanClaim
			then string.format("Day %d is ready! Miss a day and you start again at day 1.", daily.Next)
			else "Claimed today. Come back tomorrow for day " .. daily.Next .. "."
		for day, box in boxes do
			local done = day <= daily.Streak
			box.Mark.Text = if done then "✅" else ""
			box.Stroke.Enabled = daily.CanClaim and day == daily.Next
		end
	end

	function self.Show()
		self.Refresh()
		overlay.Visible = true
	end

	function self.Hide()
		overlay.Visible = false
	end

	claim.Activated:Connect(function()
		MarketClient.ClaimDaily()
		self.Hide()
	end)
	close.Activated:Connect(self.Hide)
	overlay.Activated:Connect(self.Hide)

	return self
end

return DailyRewardUI
