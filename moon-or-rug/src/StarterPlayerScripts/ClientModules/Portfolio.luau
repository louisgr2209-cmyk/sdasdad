-- Portfolio (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/Portfolio
-- Zwei Ansichten:
--   POSITIONS: Cash, Wert der Coins, offene Positionen mit Gewinn/Verlust, Level
--   HISTORY:   eigene Trades mit Gewinn/Verlust für TODAY / WEEK / ALL (UTC, wie die Ranglisten)
-- Platz (kleinster Fall 976 x 368): Kopfzeile 72 (Werte + Knöpfe rechts) | 12 | Liste (Rest, mind. 284)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Screen = require(script.Parent.Screen)
local MarketClient = require(script.Parent.MarketClient)
local Levels = require(ReplicatedStorage.Shared.Levels)

local Colors = Screen.Colors
local ROW_HEIGHT = 88
local LOG_ROW = 44
local HEAD = 72
local PERIODS = { "TODAY", "WEEK", "ALL" }
local SIDE_TEXT = { Buy = "BUY", Sell = "SELL", Rug = "☠ RUG", Dev = "DEV BUY", SL = "STOP-LOSS" }

local Portfolio = {}

-- Tag/Woche wie Ledger.PeriodKeys (UTC, Woche ab Montag)
local function periodKeys(t: number): (number, number)
	local day = math.floor(t / 86400)
	return day, math.floor((day + 3) / 7)
end

-- parent: Seite, onOpenCoin(coinId): Coin-Seite öffnen
function Portfolio.new(parent: GuiObject, onOpenCoin: (string) -> ())
	local self = {}
	local rows = {} -- [coinId] = row
	local mode = "Positions"
	local periodIndex = 1
	local log = nil -- zuletzt geladener Verlauf
	local loading = false

	-- Kopfzeile: Werte links, Knöpfe rechts
	local function statsPanel(rightSpace: number)
		return Screen.New("Frame", {
			Size = UDim2.new(1, -rightSpace, 0, HEAD),
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
	end
	local function stat(panel, count: number, order: number, title: string)
		local box = Screen.New("Frame", {
			Size = UDim2.fromScale(1 / count, 1),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = panel,
		})
		local titleLabel = Screen.Label({
			Text = title,
			TextSize = 20,
			TextColor3 = Colors.Muted,
			Size = UDim2.new(1, -8, 0, 22),
			Parent = box,
		})
		local value = Screen.Label({
			Font = Screen.Fonts.Bold,
			TextSize = 24,
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, -8, 0, 26),
			Parent = box,
		})
		return value, titleLabel
	end
	local function headButton(text: string, width: number, right: number)
		return Screen.Button({
			Text = text,
			TextSize = 20,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -right, 0, 0),
			Size = UDim2.fromOffset(width, HEAD),
			Parent = parent,
		})
	end

	------------------------------------------------------------------
	-- POSITIONS
	------------------------------------------------------------------
	local summary = statsPanel(170)
	local cashValue = stat(summary, 5, 1, "Cash")
	local positionsValue = stat(summary, 5, 2, "In coins")
	local totalValue = stat(summary, 5, 3, "Total")
	local pnlValue = stat(summary, 5, 4, "Open P/L")
	local levelValue, levelTitle = stat(summary, 5, 5, "Level")
	local historyButton = headButton("📜 HISTORY", 160, 0)

	local list = Screen.Scroller({
		Position = UDim2.fromOffset(0, HEAD + 12),
		Size = UDim2.new(1, 0, 1, -(HEAD + 12)),
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

	------------------------------------------------------------------
	-- HISTORY
	------------------------------------------------------------------
	local historySummary = statsPanel(260)
	local tradesValue = stat(historySummary, 4, 1, "Trades")
	local realizedValue = stat(historySummary, 4, 2, "Realized P/L")
	local winValue = stat(historySummary, 4, 3, "Win rate")
	local bestValue = stat(historySummary, 4, 4, "Best trade")
	local periodButton = headButton("TODAY", 120, 130)
	local backButton = headButton("◀ BACK", 120, 0)

	local logList = Screen.Scroller({
		Position = UDim2.fromOffset(0, HEAD + 12),
		Size = UDim2.new(1, 0, 1, -(HEAD + 12)),
		Parent = parent,
	})
	local logEmpty = Screen.Label({
		TextColor3 = Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 120),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = parent,
	})
	local logRows = {}

	local function logRow(index: number)
		local row = logRows[index]
		if row then
			row.Frame.Visible = true
			return row
		end
		local frame = Screen.New("Frame", {
			Size = UDim2.new(1, -10, 0, LOG_ROW),
			BackgroundColor3 = Colors.Panel,
			LayoutOrder = index,
			Parent = logList,
		}, {
			Screen.Corner(8),
		})
		row = {
			Frame = frame,
			Left = Screen.Label({
				TextSize = 20,
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(0.6, -12, 1, 0),
				Parent = frame,
			}),
			Right = Screen.Label({
				Font = Screen.Fonts.Bold,
				TextSize = 20,
				TextXAlignment = Enum.TextXAlignment.Right,
				Position = UDim2.fromScale(0.6, 0),
				Size = UDim2.new(0.4, -12, 1, 0),
				Parent = frame,
			}),
		}
		logRows[index] = row
		return row
	end

	-- Einträge des gewählten Zeitraums, neueste zuerst
	local function entriesInPeriod()
		local result = {}
		if not log then
			return result
		end
		local day, week = periodKeys(workspace:GetServerTimeNow())
		local period = PERIODS[periodIndex]
		for i = #log, 1, -1 do
			local entry = log[i]
			local eDay, eWeek = periodKeys(entry.At or 0)
			if period == "ALL" or (period == "TODAY" and eDay == day) or (period == "WEEK" and eWeek == week) then
				table.insert(result, entry)
			end
		end
		return result
	end

	local function refreshHistory()
		periodButton.Text = PERIODS[periodIndex] .. " ▸"
		local entries = entriesInPeriod()
		local realized, wins, sells, best = 0, 0, 0, nil
		for _, entry in entries do
			if entry.P then
				realized += entry.P
				sells += 1
				if entry.P > 0 then
					wins += 1
				end
				best = if best then math.max(best, entry.P) else entry.P
			end
		end
		tradesValue.Text = tostring(#entries)
		realizedValue.Text = (if realized >= 0 then "+" else "") .. Format.Cash(realized)
		realizedValue.TextColor3 = if realized >= 0 then Colors.Green else Colors.Red
		winValue.Text = if sells > 0 then string.format("%d%%", math.floor(wins / sells * 100 + 0.5)) else "–"
		bestValue.Text = if best then (if best >= 0 then "+" else "") .. Format.Cash(best) else "–"
		bestValue.TextColor3 = if best and best < 0 then Colors.Red else Colors.Green

		logEmpty.Visible = #entries == 0
		logEmpty.Text = if loading and not log then "Loading…" else "No trades in this period."
		local today = periodKeys(workspace:GetServerTimeNow())
		for i, entry in entries do
			local row = logRow(i)
			local at = entry.At or 0
			local when = os.date(if periodKeys(at) == today then "%H:%M" else "%d.%m. %H:%M", at)
			row.Left.Text = string.format(
				"%s  %s %s%s",
				when,
				SIDE_TEXT[entry.S] or tostring(entry.S),
				entry.I or "",
				if entry.T and entry.T ~= "" then " $" .. entry.T else ""
			)
			if entry.P then
				local cost = (entry.M or 0) - entry.P
				local percent = if cost > 0 then entry.P / cost else 0
				row.Right.Text = string.format(
					"%s → %s%s (%s)",
					Format.Cash(entry.M or 0),
					if entry.P >= 0 then "+" else "",
					Format.Cash(entry.P),
					Format.Percent(percent)
				)
				row.Right.TextColor3 = if entry.P >= 0 then Colors.Green else Colors.Red
			else
				row.Right.Text = Format.Cash(entry.M or 0)
				row.Right.TextColor3 = Colors.Muted
			end
		end
		for i = #entries + 1, #logRows do
			logRows[i].Frame.Visible = false
		end
	end

	local function loadLog()
		if loading then
			return
		end
		loading = true
		task.spawn(function()
			local result = MarketClient.TradeLog()
			loading = false
			if result then
				log = result
			end
			if mode == "History" then
				refreshHistory()
			end
		end)
	end

	local function setMode(newMode: string)
		mode = newMode
		local history = mode == "History"
		for _, item in { summary, historyButton, list, emptyLabel } do
			item.Visible = not history
		end
		for _, item in { historySummary, periodButton, backButton, logList, logEmpty } do
			item.Visible = history
		end
		if history then
			loadLog()
		end
		self.Refresh()
	end
	historyButton.Activated:Connect(function()
		setMode("History")
	end)
	backButton.Activated:Connect(function()
		setMode("Positions")
	end)
	periodButton.Activated:Connect(function()
		periodIndex = periodIndex % #PERIODS + 1
		refreshHistory()
	end)
	-- Nach einem eigenen Trade: Verlauf neu laden (Server begrenzt auf 1 Abfrage pro 2 Sek.)
	MarketClient.TradeResult.Event:Connect(function(ok: boolean)
		if ok and mode == "History" then
			task.delay(2, loadLog)
		end
	end)

	------------------------------------------------------------------
	-- Positionen
	------------------------------------------------------------------
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

	local function refreshPositions()
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
			levelTitle.Text = string.format("Next: %d XP", missing)
		end

		local shown = {}
		for index, entry in entries do
			local coin, position = entry.Coin, entry.Position
			local row = getRow(coin.Id)
			shown[coin.Id] = true
			row.Frame.LayoutOrder = index
			row.Icon.Text = coin.Icon
			local crown = if coin.CreatorId == MarketClient.MyKey then "👨‍💻 " else "" -- eigener Coin (👑 = Legend)
			local star = if MarketClient.IsFavorite(coin.Id) then "⭐" else ""
			row.Name.Text = crown
				.. star
				.. "$"
				.. coin.Ticker
				.. (if coin.Rugged then "  RUGGED" elseif coin.Stage == "Dead" then "  DEAD" else "")
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

	function self.Refresh()
		if mode == "History" then
			refreshHistory()
		else
			refreshPositions()
		end
	end

	setMode("Positions")
	return self
end

return Portfolio
