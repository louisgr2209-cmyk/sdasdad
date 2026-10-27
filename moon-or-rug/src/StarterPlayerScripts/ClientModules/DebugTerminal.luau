-- DebugTerminal (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/DebugTerminal
-- NUR zum Testen (Phase 1–2). Wird in Phase 3 durch TerminalUI ersetzt.
-- Zeigt nur an, was der Server schickt. Buttons schicken nur Wünsche an den Server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Curve = require(ReplicatedStorage.Shared.BondingCurve)
local Format = require(ReplicatedStorage.Shared.Format)
local Screen = require(script.Parent.Screen)

local Colors = Screen.Colors
local FEE_TOTAL = Config.Fees.Creator + Config.Fees.Burn
local MAX_TRADES_SHOWN = 3
local ROW = 28 -- Höhe einer Textzeile
-- Breite: Info-Text hat mind. 764 Design-Pixel (1000 - Ränder - Buttons), Zeilen sind kürzer.
-- Höhen addiert: 32 Rand + 44 + 156 + 72 + 72 + 28 + 3*28 + 5*10 Abstand = 538 <= 560 (passt immer)

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

	-- Coins sortiert: neueste zuerst
	local function sortedIds()
		local ids = {}
		for id in coins do
			table.insert(ids, id)
		end
		table.sort(ids, function(a, b)
			return coins[a].CreatedAt > coins[b].CreatedAt
		end)
		return ids
	end

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
	local titleLabel = Screen.Label({
		Text = "MOON OR RUG  ·  test",
		Font = Screen.Fonts.Bold,
		TextSize = 28,
		Size = UDim2.new(0.6, 0, 1, 0),
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
		Size = UDim2.new(0.4, 0, 1, 0),
		Parent = header,
	})

	-- Coin-Infos (links Text, rechts ◀ ▶)
	local panel = Screen.New("Frame", {
		Size = UDim2.new(1, 0, 0, 156),
		BackgroundColor3 = Colors.Panel,
		LayoutOrder = 2,
		Parent = root,
	}, {
		Screen.Corner(12),
		Screen.Padding(16),
	})
	local info = Screen.New("Frame", {
		Size = UDim2.new(1, -172, 1, 0),
		BackgroundTransparency = 1,
		Parent = panel,
	}, {
		Screen.New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local function infoLine(order: number, height: number, props)
		props.Size = UDim2.new(1, 0, 0, height)
		props.LayoutOrder = order
		props.Parent = info
		return Screen.Label(props)
	end
	local nameLabel = infoLine(1, 34, { Text = "Loading…", Font = Screen.Fonts.Bold, TextSize = 30 })
	local statsLabel = infoLine(2, 26, { Text = "", TextColor3 = Colors.Muted })
	local creatorLabel = infoLine(3, 26, { Text = "", TextColor3 = Colors.Muted })
	local positionLabel = infoLine(4, 26, { Text = "" })

	local function stepCoin(direction: number)
		local ids = sortedIds()
		if #ids == 0 then
			return
		end
		local index = table.find(ids, selectedId) or 1
		selectedId = ids[(index - 1 + direction) % #ids + 1]
		trades = {}
	end
	for i, def in { { "◀", -1 }, { "▶", 1 } } do
		local button = Screen.Button({
			Text = def[1],
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, if i == 1 then -84 else 0, 0.5, 0),
			Size = UDim2.fromOffset(72, 72),
			Parent = panel,
		})
		button.Activated:Connect(function()
			stepCoin(def[2])
			DebugTerminal.Refresh()
		end)
	end

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

	-- Status (Antwort vom Server oder Meldung wie Rugpull)
	local statusLabel = Screen.Label({
		Text = "Tap BUY to start.",
		Size = UDim2.new(1, 0, 0, ROW),
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
	function DebugTerminal.Refresh()
		cashLabel.Text = "Cash: " .. Format.Cash(me.Cash)

		local ids = sortedIds()
		if not (selectedId and coins[selectedId]) then
			selectedId = ids[1]
			trades = {}
		end
		local coin = selectedId and coins[selectedId]
		if not coin then
			nameLabel.Text = "No coins yet…"
			return
		end
		titleLabel.Text = string.format("MOON OR RUG  ·  coin %d/%d", table.find(ids, selectedId) or 1, #ids)

		local status = coin.Stage
		if coin.Rugged then
			status ..= " · RUGGED"
		end
		nameLabel.Text = string.format("%s  %s  ($%s)", coin.Icon, coin.Name, coin.Ticker)
		nameLabel.TextColor3 = if coin.Rugged or coin.Stage == "Dead" then Colors.Red else Colors.Text
		statsLabel.Text = string.format(
			"Price %s · MCap %s · Holders %d · %s",
			Format.Price(coin.Price),
			Format.Short(coin.MarketCap),
			coin.Holders,
			status
		)
		creatorLabel.Text = string.format(
			"Age %s · Dev %s (%.1f%%)%s",
			Format.Duration(workspace:GetServerTimeNow() - coin.CreatedAt),
			coin.CreatorName,
			coin.DevShare * 100,
			if coin.CreatorHasLicense then " · ⚠ RUG LICENSE" else ""
		)

		local position = me.Positions[coin.Id]
		if position then
			-- Wert = was man jetzt beim Verkaufen bekäme (nach Gebühr)
			local value = Curve.CashForTokens(Config.Curve, coin.Supply, position.Amount) * (1 - FEE_TOTAL)
			local pnl = if position.Cost > 0 then value / position.Cost - 1 else 0
			positionLabel.Text = string.format(
				"You hold %s %s · worth %s · P/L %s",
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
					"%s  %s%s  %s %s  for %s",
					string.upper(trade.Side),
					if trade.IsNpc then "🤖 " else "",
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
		for _, coinInfo in update.Coins do
			local coin = coins[coinInfo.Id] or {}
			for key, value in coinInfo do
				coin[key] = value
			end
			coins[coinInfo.Id] = coin
		end
		for _, id in update.Removed or {} do
			coins[id] = nil
		end
		for _, news in update.News or {} do
			statusLabel.Text = "🚨 " .. news.Text
			statusLabel.TextColor3 = Colors.Accent
		end
		addTrades(update.Trades)
		DebugTerminal.Refresh()
	end)

	playerState.OnClientEvent:Connect(function(state)
		me = state
		DebugTerminal.Refresh()
	end)

	tradeResult.OnClientEvent:Connect(function(result)
		statusLabel.Text = result.Message
		statusLabel.TextColor3 = if result.Ok then Colors.Green else Colors.Red
	end)

	-- Erste Daten holen (mit Wiederholung, falls der Server noch startet)
	for _ = 1, 5 do
		local ok, snapshot = pcall(getSnapshot.InvokeServer, getSnapshot)
		if ok and snapshot then
			for _, coinInfo in snapshot.Coins do
				coins[coinInfo.Id] = coinInfo
			end
			selectedId = sortedIds()[1]
			if selectedId then
				addTrades(coins[selectedId].Trades or {})
			end
			if snapshot.Me then
				me = snapshot.Me
			end
			break
		end
		task.wait(1)
	end
	DebugTerminal.Refresh()
end

return DebugTerminal
