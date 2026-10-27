-- DebugTerminal (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/DebugTerminal
-- NUR für Phase 1 zum Testen der Markt-Engine. Wird in Phase 3 durch TerminalUI ersetzt.
-- Zeigt nur an, was der Server schickt. Buttons schicken nur Wünsche an den Server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Curve = require(ReplicatedStorage.Shared.BondingCurve)
local Format = require(ReplicatedStorage.Shared.Format)
local Screen = require(script.Parent.Screen)

local Colors = Screen.Colors
local FEE_TOTAL = Config.Fees.Creator + Config.Fees.Burn
local MAX_TRADES_SHOWN = 4
local ROW = 28 -- Höhe einer Trade-Zeile
-- Höhen addiert: 32 Rand + 44 + 126 + 72 + 72 + 28 + 4*28 + 5*10 Abstand = 536 <= 560 (passt immer)

local DebugTerminal = {}

function DebugTerminal.Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local tradeRequest = remotes:WaitForChild("TradeRequest") :: RemoteEvent
	local tradeResult = remotes:WaitForChild("TradeResult") :: RemoteEvent
	local marketUpdate = remotes:WaitForChild("MarketUpdate") :: RemoteEvent
	local playerState = remotes:WaitForChild("PlayerState") :: RemoteEvent
	local getSnapshot = remotes:WaitForChild("GetMarketSnapshot") :: RemoteFunction

	local coins = {} -- [coinId] = info vom Server
	local selectedId: string? = nil
	local me = { Cash = 0, Positions = {} }
	local trades = {} -- letzte Trades des gewählten Coins

	--------------------------------------------------------------------
	-- UI bauen (Design-Pixel, Root ist mind. ~1000 x 560)
	--------------------------------------------------------------------
	local root = Screen.CreateRoot("DebugTerminal")
	Screen.Padding(16).Parent = root
	Screen.New("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = root,
	})

	-- Kopfzeile
	local header = Screen.New("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = root,
	})
	Screen.Label({
		Text = "MOON OR RUG  ·  engine test",
		Font = Screen.Fonts.Bold,
		TextSize = 28,
		Size = UDim2.new(0.5, 0, 1, 0),
		Parent = header,
	})
	local cashLabel = Screen.Label({
		Text = "Cash: …",
		Font = Screen.Fonts.Bold,
		TextSize = 28,
		TextColor3 = Colors.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		Parent = header,
	})

	-- Coin-Infos
	local panel = Screen.New("Frame", {
		Size = UDim2.new(1, 0, 0, 126),
		BackgroundColor3 = Colors.Panel,
		LayoutOrder = 2,
		Parent = root,
	}, {
		Screen.Corner(12),
		Screen.Padding(16),
		Screen.New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local nameLabel = Screen.Label({
		Text = "Loading…",
		Font = Screen.Fonts.Bold,
		TextSize = 30,
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 1,
		Parent = panel,
	})
	local statsLabel = Screen.Label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = Colors.Muted,
		LayoutOrder = 2,
		Parent = panel,
	})
	local positionLabel = Screen.Label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = 3,
		Parent = panel,
	})

	-- Kaufen-/Verkaufen-Reihen
	local function buttonRow(order: number, side: string, color: Color3)
		local row = Screen.New("Frame", {
			Size = UDim2.new(1, 0, 0, 72),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = root,
		}, {
			Screen.New("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 12),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		for i, fraction in Config.Trade.Fractions do
			local amountText = if fraction >= 1
				then (if side == "Buy" then "MAX" else "ALL")
				else math.floor(fraction * 100 + 0.5) .. "%"
			local button = Screen.Button({
				Text = string.upper(side) .. " " .. amountText,
				BackgroundColor3 = color,
				Size = UDim2.new(1 / #Config.Trade.Fractions, -9, 1, 0),
				LayoutOrder = i,
				Parent = row,
			})
			button.Activated:Connect(function()
				if selectedId then
					tradeRequest:FireServer(selectedId, side, fraction)
				end
			end)
		end
	end
	buttonRow(3, "Buy", Colors.Green)
	buttonRow(4, "Sell", Colors.Red)

	-- Status (Antwort vom Server)
	local statusLabel = Screen.Label({
		Text = "Tap BUY to start.",
		Size = UDim2.new(1, 0, 0, 28),
		TextColor3 = Colors.Muted,
		LayoutOrder = 5,
		Parent = root,
	})

	-- Live-Trades
	local tradeList = Screen.New("Frame", {
		Size = UDim2.new(1, 0, 0, MAX_TRADES_SHOWN * ROW),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		LayoutOrder = 6,
		Parent = root,
	}, {
		Screen.New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	--------------------------------------------------------------------
	-- Anzeige aktualisieren
	--------------------------------------------------------------------
	local function refresh()
		cashLabel.Text = "Cash: " .. Format.Cash(me.Cash)

		local coin = selectedId and coins[selectedId]
		if not coin then
			return
		end
		nameLabel.Text = string.format("%s  %s  ($%s)", coin.Icon, coin.Name, coin.Ticker)
		statsLabel.Text = string.format(
			"Price %s   ·   MCap %s   ·   Holders %d   ·   %s",
			Format.Price(coin.Price),
			Format.Cash(coin.MarketCap),
			coin.Holders,
			coin.Stage
		)

		local position = me.Positions[coin.Id]
		if position then
			-- Wert = was man jetzt beim Verkaufen bekäme (nach Gebühr)
			local value = Curve.CashForTokens(Config.Curve, coin.Supply, position.Amount) * (1 - FEE_TOTAL)
			local pnl = if position.Cost > 0 then value / position.Cost - 1 else 0
			positionLabel.Text = string.format(
				"You hold %s %s  ·  worth %s  ·  P/L %s",
				Format.Short(position.Amount),
				coin.Ticker,
				Format.Cash(value),
				Format.Percent(pnl)
			)
			positionLabel.TextColor3 = if pnl >= 0 then Colors.Green else Colors.Red
		else
			positionLabel.Text = "You hold nothing yet."
			positionLabel.TextColor3 = Colors.Muted
		end

		for _, child in tradeList:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		for i = #trades, math.max(1, #trades - MAX_TRADES_SHOWN + 1), -1 do
			local trade = trades[i]
			Screen.Label({
				Text = string.format(
					"%s  %s  %s %s  for %s",
					string.upper(trade.Side),
					trade.Trader,
					Format.Short(trade.Tokens),
					trade.Ticker,
					Format.Cash(trade.Cash)
				),
				TextColor3 = if trade.Side == "Buy" then Colors.Green else Colors.Red,
				Size = UDim2.new(1, 0, 0, ROW),
				LayoutOrder = #trades - i,
				Parent = tradeList,
			})
		end
	end

	local function addTrades(list)
		for _, trade in list do
			if trade.CoinId == selectedId then
				table.insert(trades, trade)
			end
		end
		while #trades > MAX_TRADES_SHOWN do
			table.remove(trades, 1)
		end
	end

	--------------------------------------------------------------------
	-- Server-Daten
	--------------------------------------------------------------------
	marketUpdate.OnClientEvent:Connect(function(update)
		for _, info in update.Coins do
			local coin = coins[info.Id] or {}
			for key, value in info do
				coin[key] = value
			end
			coins[info.Id] = coin
			if not selectedId then
				selectedId = info.Id
			end
		end
		addTrades(update.Trades)
		refresh()
	end)

	playerState.OnClientEvent:Connect(function(state)
		me = state
		refresh()
	end)

	tradeResult.OnClientEvent:Connect(function(result)
		statusLabel.Text = result.Message
		statusLabel.TextColor3 = if result.Ok then Colors.Green else Colors.Red
	end)

	-- Erste Daten holen (mit Wiederholung, falls der Server noch startet)
	for _ = 1, 5 do
		local ok, snapshot = pcall(getSnapshot.InvokeServer, getSnapshot)
		if ok and snapshot then
			for _, info in snapshot.Coins do
				coins[info.Id] = info
				selectedId = selectedId or info.Id
				if info.Id == selectedId then
					addTrades(info.Trades)
				end
			end
			if snapshot.Me then
				me = snapshot.Me
			end
			break
		end
		task.wait(1)
	end
	refresh()
end

return DebugTerminal
