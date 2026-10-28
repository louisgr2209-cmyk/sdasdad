-- LeaderboardUI (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/LeaderboardUI
-- Ranglisten: WORLD (Top 50 aller Server) oder SERVER (Spieler auf diesem Server),
-- Zeitraum ALL TIME (Vermögen, PNL, bester Trade) / WEEK / TODAY (PNL, bester Trade).
--
-- Platz (kleinster Fall 976 x 368): Schalter 64 | 10 | Spalten (Titel 30, Liste, "You" 28)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Screen = require(script.Parent.Screen)
local MarketClient = require(script.Parent.MarketClient)

local Colors = Screen.Colors
local ROW = 30

local PERIODS = {
	{ Id = "All", Label = "ALL TIME", Boards = { "Wealth", "Pnl", "Best" } },
	{ Id = "Week", Label = "WEEK", Boards = { "WeekPnl", "WeekBest" } },
	{ Id = "Day", Label = "TODAY", Boards = { "DayPnl", "DayBest" } },
}
local TITLES = {
	Wealth = "Net worth",
	Pnl = "PnL (realized)",
	Best = "Best trade",
	WeekPnl = "PnL this week",
	WeekBest = "Best trade this week",
	DayPnl = "PnL today",
	DayBest = "Best trade today",
}

local LeaderboardUI = {}

function LeaderboardUI.new(parent: GuiObject)
	local self = {}
	local scope = "World"
	local period = PERIODS[1]

	-- Schalter oben
	local controls = Screen.New("Frame", {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		Screen.New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local scopeButtons, periodButtons = {}, {}
	local function styleButtons()
		for id, button in scopeButtons do
			button.BackgroundColor3 = if id == scope then Colors.Border else Colors.PanelLight
		end
		for id, button in periodButtons do
			button.BackgroundColor3 = if id == period.Id then Colors.Border else Colors.PanelLight
		end
	end
	for i, id in { "World", "Server" } do
		local button = Screen.Button({
			Text = string.upper(id),
			TextSize = 22,
			Size = UDim2.new(0, 130, 1, 0),
			LayoutOrder = i,
			Parent = controls,
		})
		button.Activated:Connect(function()
			scope = id
			self.Refresh()
		end)
		scopeButtons[id] = button
	end
	Screen.New("Frame", { Size = UDim2.new(0, 20, 1, 0), BackgroundTransparency = 1, LayoutOrder = 3, Parent = controls })
	for i, def in PERIODS do
		local button = Screen.Button({
			Text = def.Label,
			TextSize = 22,
			Size = UDim2.new(0, 150, 1, 0),
			LayoutOrder = 3 + i,
			Parent = controls,
		})
		button.Activated:Connect(function()
			period = def
			self.Refresh()
		end)
		periodButtons[def.Id] = button
	end

	-- Bis zu 3 Spalten
	local area = Screen.New("Frame", {
		Position = UDim2.fromOffset(0, 74),
		Size = UDim2.new(1, 0, 1, -74),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local hint = Screen.Label({
		TextColor3 = Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 40),
		Visible = false,
		Parent = area,
	})
	local columns = {}
	for i = 1, 3 do
		local column = Screen.New("Frame", {
			BackgroundColor3 = Colors.Panel,
			Parent = area,
		}, {
			Screen.Corner(12),
		})
		local title = Screen.Label({
			Font = Screen.Fonts.Bold,
			TextColor3 = Colors.Muted,
			Position = UDim2.fromOffset(12, 4),
			Size = UDim2.new(1, -24, 0, 30),
			Parent = column,
		})
		local list = Screen.Scroller({
			Position = UDim2.fromOffset(8, 36),
			Size = UDim2.new(1, -16, 1, -36 - 34),
			Parent = column,
		})
		list:FindFirstChildOfClass("UIListLayout").Padding = UDim.new(0, 0)
		local you = Screen.Label({
			Font = Screen.Fonts.Bold,
			TextColor3 = Colors.Accent,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 12, 1, -4),
			Size = UDim2.new(1, -24, 0, 28),
			Parent = column,
		})
		columns[i] = { Frame = column, Title = title, List = list, You = you, Rows = {} }
	end

	local function row(column, index: number)
		local entry = column.Rows[index]
		if entry then
			entry.Frame.Visible = true
			return entry
		end
		local frame = Screen.New("Frame", {
			Size = UDim2.new(1, -8, 0, ROW),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = column.List,
		})
		entry = {
			Frame = frame,
			Name = Screen.Label({ Size = UDim2.new(1, -110, 1, 0), TextSize = 20, Parent = frame }),
			Value = Screen.Label({
				TextSize = 20,
				Font = Screen.Fonts.Bold,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0, 105, 1, 0),
				Parent = frame,
			}),
		}
		column.Rows[index] = entry
		return entry
	end

	-- Eigene Werte (Client rechnet nur zur Anzeige)
	local function myValue(board: string): number
		local me = MarketClient.Me
		if board == "Wealth" then
			local total = me.Cash or 0
			for coinId, position in me.Positions or {} do
				local coin = MarketClient.Coins[coinId]
				if coin then
					total += MarketClient.PositionValue(coin, position)
				end
			end
			return total
		end
		local stats = me.Stats or {}
		return stats[board] or 0
	end

	function self.Refresh()
		styleButtons()
		local boards = MarketClient.Leaderboard[scope]
		local count = #period.Boards
		hint.Visible = boards == nil
		hint.Text = if scope == "World"
			then "World ranking loads every minute (not available in Studio test mode)."
			else "Loading…"
		for i, column in columns do
			local board = period.Boards[i]
			column.Frame.Visible = board ~= nil and boards ~= nil
			if not board then
				continue
			end
			column.Frame.Size = UDim2.new(1 / count, -8 * (count - 1) / count, 1, 0)
			column.Frame.Position = UDim2.new((i - 1) / count, 8 * (i - 1) / count, 0, 0)
			column.Title.Text = TITLES[board]
			column.You.Text = "You: " .. Format.Cash(myValue(board))
			local list = (boards and boards[board]) or {}
			for index, entry in list do
				local r = row(column, index)
				r.Name.Text = index .. ". " .. entry.N
				r.Value.Text = Format.Short(entry.V)
				r.Value.TextColor3 = if entry.V >= 0 then Colors.Green else Colors.Red
				r.Name.TextColor3 = if index <= 3 then Colors.Accent else Colors.Text
			end
			for index = #list + 1, #column.Rows do
				column.Rows[index].Frame.Visible = false
			end
		end
	end

	return self
end

return LeaderboardUI
