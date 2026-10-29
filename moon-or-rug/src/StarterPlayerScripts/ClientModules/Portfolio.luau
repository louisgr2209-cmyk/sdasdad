-- Portfolio (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/Portfolio
-- Cash, offene Positionen mit Gewinn/Verlust, Level. Eigener Coin folgt in Phase 6.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Screen = require(script.Parent.Screen)
local MarketClient = require(script.Parent.MarketClient)
local Levels = require(ReplicatedStorage.Shared.Levels)

local Colors = Screen.Colors
local ROW_HEIGHT = 88

local Portfolio = {}

-- parent: Seite, onOpenCoin(coinId): Coin-Seite öffnen
function Portfolio.new(parent: GuiObject, onOpenCoin: (string) -> ())
	local self = {}
	local rows = {} -- [coinId] = row

	-- Kopf: Summen
	local summary = Screen.New("Frame", {
		Size = UDim2.new(1, 0, 0, 72),
		BackgroundColor3 = Colors.Panel,
		Parent = parent,
	}, {
		Screen.Corner(12),
		Screen.Padding(12),
		Screen.New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local function stat(order: number, title: string)
		local box = Screen.New("Frame", {
			Size = UDim2.fromScale(0.2, 1),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = summary,
		})
		Screen.Label({
			Text = title,
			TextSize = 20,
			TextColor3 = Colors.Muted,
			Size = UDim2.new(1, -8, 0, 22),
			Parent = box,
		})
		return Screen.Label({
			Font = Screen.Fonts.Bold,
			TextSize = 24,
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, -8, 0, 26),
			Parent = box,
		})
	end
	local cashValue = stat(1, "Cash")
	local positionsValue = stat(2, "In coins")
	local totalValue = stat(3, "Total")
	local pnlValue = stat(4, "Open P/L")
	local levelValue = stat(5, "Level")

	local list = Screen.Scroller({
		Position = UDim2.fromOffset(0, 84),
		Size = UDim2.new(1, 0, 1, -84),
		Parent = parent,
	})
	local emptyLabel = Screen.Label({
		Text = "No positions yet. Buy a coin in PULSE.",
		TextColor3 = Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 120),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = parent,
	})

	local function getRow(coinId: string)
		local row = rows[coinId]
		if row then
			return row
		end
		local frame = Screen.New("TextButton", {
			Text = "",
			Size = UDim2.new(1, -10, 0, ROW_HEIGHT),
			BackgroundColor3 = Colors.Panel,
			Parent = list,
		}, {
			Screen.Corner(10),
		})
		row = {
			Frame = frame,
			Icon = Screen.Label({
				TextSize = 32,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.fromOffset(44, ROW_HEIGHT),
				Parent = frame,
			}),
			Name = Screen.Label({
				Font = Screen.Fonts.Bold,
				Position = UDim2.fromOffset(64, 14),
				Size = UDim2.new(0.5, -64, 0, 28),
				Parent = frame,
			}),
			Amount = Screen.Label({
				TextSize = 20,
				TextColor3 = Colors.Muted,
				Position = UDim2.fromOffset(64, 46),
				Size = UDim2.new(0.5, -64, 0, 26),
				Parent = frame,
			}),
			Value = Screen.Label({
				Font = Screen.Fonts.Bold,
				TextXAlignment = Enum.TextXAlignment.Right,
				Position = UDim2.new(0.5, 0, 0, 14),
				Size = UDim2.new(0.5, -150, 0, 28),
				Parent = frame,
			}),
			Pnl = Screen.Label({
				TextSize = 20,
				TextXAlignment = Enum.TextXAlignment.Right,
				Position = UDim2.new(0.5, 0, 0, 46),
				Size = UDim2.new(0.5, -150, 0, 26),
				Parent = frame,
			}),
			Sell = Screen.Button({
				Text = "SELL ALL",
				TextSize = 22,
				BackgroundColor3 = Colors.Red,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(124, 72),
				Parent = frame,
			}),
		}
		frame.Activated:Connect(function()
			onOpenCoin(coinId)
		end)
		row.Sell.Activated:Connect(function()
			MarketClient.Trade(coinId, "Sell", 1)
		end)
		rows[coinId] = row
		return row
	end

	function self.Refresh()
		local me = MarketClient.Me
		local inCoins, totalCost = 0, 0
		local entries = {}
		for coinId, position in me.Positions or {} do
			local coin = MarketClient.Coins[coinId]
			if coin then
				local value = MarketClient.PositionValue(coin, position)
				inCoins += value
				totalCost += position.Cost
				table.insert(entries, { Coin = coin, Position = position, Value = value })
			end
		end
		table.sort(entries, function(a, b)
			return a.Value > b.Value
		end)

		cashValue.Text = Format.Cash(me.Cash)
		positionsValue.Text = Format.Cash(inCoins)
		totalValue.Text = Format.Cash(me.Cash + inCoins)
		local openPnl = inCoins - totalCost
		pnlValue.Text = (if openPnl >= 0 then "+" else "") .. Format.Cash(openPnl)
		pnlValue.TextColor3 = if openPnl >= 0 then Colors.Green else Colors.Red
		emptyLabel.Visible = #entries == 0
		if me.Stats then
			local level, progress, missing = Levels.Progress(me.Stats.Xp)
			levelValue.Text = string.format("Lv %d · %d%%", level, math.floor(progress * 100))
			levelValue.TextColor3 = Colors.Text
			-- kleine Hilfe im Titel: wie viel XP noch fehlt (kurz, passt auch auf das iPad)
			levelValue.Parent:FindFirstChildOfClass("TextLabel").Text = string.format("Next: %d XP", missing)
		end

		local shown = {}
		for index, entry in entries do
			local coin, position = entry.Coin, entry.Position
			local row = getRow(coin.Id)
			shown[coin.Id] = true
			row.Frame.LayoutOrder = index
			row.Icon.Text = coin.Icon
			local crown = if coin.CreatorId == MarketClient.MyKey then "👑 " else ""
			row.Name.Text = crown .. "$" .. coin.Ticker .. (if coin.Rugged then "  RUGGED" elseif coin.Stage == "Dead" then "  DEAD" else "")
			row.Name.TextColor3 = if coin.Rugged or coin.Stage == "Dead" then Colors.Red else Colors.Text
			local marks = ""
			if position.SL then
				marks ..= string.format(" · 🛑-%d%%", math.floor(position.SL * 100 + 0.5))
			end
			if me.Insured and me.Insured[coin.Id] then
				marks ..= " · 🛡"
			end
			if coin.CreatorId == MarketClient.MyKey and me.Stats and me.Stats.FeesEarned > 0 then
				marks ..= " · fees " .. Format.Short(me.Stats.FeesEarned)
			end
			row.Amount.Text = string.format("%s · cost %s%s", Format.Short(position.Amount), Format.Cash(position.Cost), marks)
			local pnl = if position.Cost > 0 then entry.Value / position.Cost - 1 else 0
			row.Value.Text = Format.Cash(entry.Value)
			row.Pnl.Text = Format.Percent(pnl)
			row.Pnl.TextColor3 = if pnl >= 0 then Colors.Green else Colors.Red
		end
		for coinId, row in rows do
			if not shown[coinId] then
				row.Frame:Destroy()
				rows[coinId] = nil
			end
		end
	end

	return self
end

return Portfolio
