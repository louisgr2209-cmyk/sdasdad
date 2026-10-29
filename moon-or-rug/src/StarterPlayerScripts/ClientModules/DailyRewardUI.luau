-- DailyRewardUI (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/DailyRewardUI
-- Fenster mit den 7 Tagen des Daily Rewards und CLAIM-Knopf, darunter der Creator-Code
-- (einlösen – einmal im ganzen Spiel – oder als Gold-Creator den eigenen Code wählen/sehen).
-- Der Server entscheidet alles (einmal pro Tag, Lücke = Tag 1, Code-Regeln).
--
-- Platz: Fenster 80 % breit (bei 1000 Breite ca. 100 pro Tag), 440 hoch (passt in 496)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Screen = require(script.Parent.Screen)
local MarketClient = require(script.Parent.MarketClient)
local CreatorStyle = require(ReplicatedStorage.Shared.CreatorStyle)

local Colors = Screen.Colors
local DAYS = Config.Protection.Daily
local CR = Config.Creator

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
		Size = UDim2.new(0.8, 0, 0, 440),
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

	-- Creator-Code
	Screen.Label({
		Text = "🎬 CREATOR CODE",
		Font = Screen.Fonts.Bold,
		TextSize = 22,
		Position = UDim2.fromOffset(0, 206),
		Size = UDim2.new(1, 0, 0, 26),
		ZIndex = 32,
		Parent = panel,
	})
	local codeHint = Screen.Label({
		TextSize = 20,
		TextColor3 = Colors.Muted,
		Position = UDim2.fromOffset(0, 232),
		Size = UDim2.new(1, 0, 0, 24),
		ZIndex = 32,
		Parent = panel,
	})
	local codeBox = Screen.New("TextBox", {
		Text = "",
		ClearTextOnFocus = false,
		Font = Screen.Fonts.Medium,
		TextSize = 22,
		TextColor3 = Colors.Text,
		PlaceholderColor3 = Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = Colors.PanelLight,
		Position = UDim2.fromOffset(0, 262),
		Size = UDim2.new(1, -228, 0, 72),
		ZIndex = 32,
		Parent = panel,
	}, {
		Screen.Corner(10),
		Screen.New("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
	})
	codeBox:GetPropertyChangedSignal("Text"):Connect(function()
		local clean = string.sub(string.upper((string.gsub(codeBox.Text, "[^%w]", ""))), 1, CR.CodeMax)
		if clean ~= codeBox.Text then
			codeBox.Text = clean
		end
	end)
	local codeButton = Screen.Button({
		Text = "REDEEM",
		BackgroundColor3 = Colors.Accent,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 262),
		Size = UDim2.fromOffset(216, 72),
		ZIndex = 32,
		Parent = panel,
	})
	local myCodeLabel = Screen.Label({
		Font = Screen.Fonts.Bold,
		TextSize = 26,
		TextColor3 = CreatorStyle.Gold,
		Position = UDim2.fromOffset(0, 262),
		Size = UDim2.new(1, 0, 0, 72),
		Visible = false,
		ZIndex = 32,
		Parent = panel,
	})
	local codeMode = "redeem" -- "redeem" / "choose" / "none"

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

		-- Creator-Code: Gold -> eigener Code, sonst einlösen (einmal im ganzen Spiel)
		local extra = MarketClient.Me.Extra or {}
		if (extra.Tier or 0) >= 4 then
			codeMode = if extra.Code then "none" else "choose"
			myCodeLabel.Text = if extra.Code then "Your code: " .. extra.Code else ""
			codeHint.Text = if extra.Code
				then string.format("Used %d times · you get %d Cash per use (max. %d per day)", extra.Uses or 0, CR.CreatorPerRedeem, CR.CreatorDailyCap)
				else string.format("Pick your own code (%d-%d letters/numbers). You can choose it only once!", CR.CodeMin, CR.CodeMax)
		elseif extra.Redeemed then
			codeMode = "none"
			myCodeLabel.Text = "✅ Code " .. extra.Redeemed .. " used"
			codeHint.Text = "Every player can use one creator code."
		else
			codeMode = "redeem"
			if extra.AccountOk == false then
				codeHint.Text = string.format("Your Roblox account must be at least %d days old.", CR.MinAccountAgeDays)
			elseif (extra.PlaytimeLeft or 0) > 0 then
				codeHint.Text = string.format("Play %d more minutes to use a code.", math.ceil(extra.PlaytimeLeft / 60))
			else
				codeHint.Text = string.format("Enter a creator code: +%s Cash (only once!)", Format.Short(CR.CodeReward))
			end
		end
		codeBox.Visible = codeMode ~= "none"
		codeButton.Visible = codeMode ~= "none"
		myCodeLabel.Visible = codeMode == "none"
		codeButton.Text = if codeMode == "choose" then "SET CODE" else "REDEEM"
		codeBox.PlaceholderText = if codeMode == "choose" then "YOUR CODE" else "CODE"
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
	codeButton.Activated:Connect(function()
		local code = codeBox.Text
		if #code < CR.CodeMin then
			codeHint.Text = string.format("Code: %d to %d letters/numbers", CR.CodeMin, CR.CodeMax)
			return
		end
		if codeMode == "choose" then
			MarketClient.SetCreatorCode(code)
		elseif codeMode == "redeem" then
			MarketClient.RedeemCode(code)
		end
		codeBox.Text = ""
	end)
	close.Activated:Connect(self.Hide)
	overlay.Activated:Connect(self.Hide)

	return self
end

return DailyRewardUI
