-- CoinPage (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/CoinPage
-- Coin-Seite: links Chart + Ampel-Indikatoren + Infos, rechts Position, Kaufen/Verkaufen
-- (10/25/50 %/alles), Live-Trades. Stop-Loss und Versicherung kommen in Phase 5.
--
-- Platz (kleinster Fall 976 x 368 Design-Pixel):
--   links 60 %: Kopf 72 | Chart (mind. 176) | 4 Ampel-Kacheln 72 | 1 Infozeile 24
--   rechts 40 %: Position 26 | BUY 20+72 | SELL 20+72 | Live-Trades (Rest, mind. 3 Zeilen)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Screen = require(script.Parent.Screen)
local MarketClient = require(script.Parent.MarketClient)
local ChartRenderer = require(script.Parent.ChartRenderer)
local Indicators = require(ReplicatedStorage.Shared.Indicators)
local CreatorStyle = require(ReplicatedStorage.Shared.CreatorStyle)

local Colors = Screen.Colors
local TRADE_ROWS = 8
local CHIPS = 72 -- Höhe der Ampel-Kacheln
local INFO = 24 -- Höhe der Infozeile

local RATING_COLORS = {
	Good = Colors.Green,
	Ok = Colors.Accent,
	Bad = Colors.Red,
}
local RATING_DOTS = { Good = "🟢", Ok = "🟡", Bad = "🔴" }

local CoinPage = {}

-- parent: Seite, onBack(): zurück zur vorigen Seite
function CoinPage.new(parent: GuiObject, onBack: () -> ())
	local self = { CoinId = nil :: string? }
	local helpDef -- gerade geöffnete Erklärung (oder nil)
	local updateHelp -- Funktion, wird weiter unten gesetzt

	------------------------------------------------------------------
	-- Links: Kopf, Chart, Infos
	------------------------------------------------------------------
	local left = Screen.New("Frame", {
		Size = UDim2.new(0.6, -6, 1, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local back = Screen.Button({
		Text = "◀",
		Size = UDim2.fromOffset(72, 72),
		Parent = left,
	})
	back.Activated:Connect(onBack)

	local nameLabel = Screen.Label({
		Font = Screen.Fonts.Bold,
		TextSize = 28,
		Position = UDim2.fromOffset(84, 2),
		Size = UDim2.new(1, -84, 0, 36),
		Parent = left,
	})
	local priceLabel = Screen.Label({
		Font = Screen.Fonts.Bold,
		TextSize = 24,
		Position = UDim2.fromOffset(84, 40),
		Size = UDim2.new(1, -84, 0, 30),
		Parent = left,
	})
	-- Boost: nur beim eigenen Coin (ab Level 15, 25.000 Cash, 10 Min.)
	local boostButton = Screen.Button({
		TextSize = 20,
		BackgroundColor3 = Colors.Accent,
		TextColor3 = Colors.Background,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(120, 72),
		Visible = false,
		Parent = left,
	})
	-- Mit Cash, wenn möglich; sonst Robux-Kauf (49 R$, ohne Level), danach automatisch boosten
	local function canBoostWithCash(): boolean
		local me = MarketClient.Me
		local level = if me.Stats then me.Stats.Level else 1
		return level >= Config.Launch.BoostMinLevel and (me.Cash or 0) >= Config.Launch.BoostCost
	end
	boostButton.Activated:Connect(function()
		local coinId = self.CoinId
		if not coinId then
			return
		end
		if (MarketClient.Me.FreeBoosts or 0) > 0 or canBoostWithCash() or MarketClient.BoostLeft(coinId) > 0 then
			MarketClient.Boost(coinId)
			return
		end
		local before = MarketClient.Me.FreeBoosts or 0
		MarketClient.BuyThen("Boost", function()
			return (MarketClient.Me.FreeBoosts or 0) > before
		end, function()
			MarketClient.Boost(coinId)
		end)
	end)
	-- Rugpull: nur beim eigenen Coin mit Lizenz, ein Klick verkauft alles (Phase 7)
	local rugButton = Screen.Button({
		TextSize = 20,
		BackgroundColor3 = Colors.Red,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -128, 0, 0),
		Size = UDim2.fromOffset(120, 72),
		Visible = false,
		Parent = left,
	})
	rugButton.Activated:Connect(function()
		if self.CoinId then
			MarketClient.RugPull(self.CoinId)
		end
	end)

	local chartHolder = Screen.New("Frame", {
		Position = UDim2.fromOffset(0, 82),
		Size = UDim2.new(1, 0, 1, -82 - 8 - CHIPS - 4 - INFO),
		BackgroundTransparency = 1,
		Parent = left,
	})
	local chart = ChartRenderer.new(chartHolder)
	-- Pro: Kerzen-Chart an/aus (ohne Pro: 🔒, antippen = kaufen)
	local candles = false
	local candleButton = Screen.Button({
		TextSize = 20,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(112, 72),
		BackgroundTransparency = 0.2,
		Parent = chartHolder,
	})
	candleButton.Activated:Connect(function()
		if not MarketClient.HasPass("Pro") then
			MarketClient.Buy("Pro")
			return
		end
		candles = not candles
		chart:SetCandles(candles)
		self.Refresh()
	end)

	------------------------------------------------------------------
	-- Ampel-Indikatoren (antippen = Erklärung)
	------------------------------------------------------------------
	local chipRow = Screen.New("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -(4 + INFO)),
		Size = UDim2.new(1, 0, 0, CHIPS),
		BackgroundTransparency = 1,
		Parent = left,
	}, {
		Screen.New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local chips = {} -- [id] = { Value, Stroke }
	local count = #Indicators.List
	local showHelp -- wird unten gesetzt
	for i, def in Indicators.List do
		local chip = Screen.Button({
			Text = "",
			BackgroundColor3 = Colors.Panel,
			Size = UDim2.new(1 / count, -8 * (count - 1) / count, 1, 0),
			LayoutOrder = i,
			Parent = chipRow,
		})
		Screen.Label({
			Text = def.Label .. " ?",
			TextSize = 20,
			TextColor3 = Colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(4, 6),
			Size = UDim2.new(1, -8, 0, 24),
			Parent = chip,
		})
		chips[def.Id] = {
			Value = Screen.Label({
				Font = Screen.Fonts.Bold,
				TextSize = 26,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(4, 32),
				Size = UDim2.new(1, -8, 0, 32),
				Parent = chip,
			}),
			Stroke = Screen.New("UIStroke", {
				Thickness = 2,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Parent = chip,
			}),
		}
		chip.Activated:Connect(function()
			showHelp(def)
		end)
	end

	local infoLabel = Screen.Label({
		TextSize = 20,
		TextColor3 = Colors.Muted,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 4, 1, 0),
		Size = UDim2.new(1, -8, 0, INFO),
		Parent = left,
	})

	------------------------------------------------------------------
	-- Rechts: Position, Kaufen, Verkaufen, Live-Trades
	------------------------------------------------------------------
	local right = Screen.New("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.4, -6, 1, 0),
		BackgroundColor3 = Colors.Panel,
		ClipsDescendants = true,
		Parent = parent,
	}, {
		Screen.Corner(12),
		Screen.Padding(12),
		Screen.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local positionLabel = Screen.Label({
		Font = Screen.Fonts.Bold,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = 1,
		Parent = right,
	})

	local function tradeRow(order: number, side: string, color: Color3)
		local row = Screen.New("Frame", {
			Size = UDim2.new(1, 0, 0, 72),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = right,
		}, {
			Screen.New("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local count = #Config.Trade.Fractions
		for i, fraction in Config.Trade.Fractions do
			local amount = if fraction >= 1
				then (if side == "Buy" then "MAX" else "ALL")
				else math.floor(fraction * 100 + 0.5) .. "%"
			local button = Screen.Button({
				Text = string.upper(side) .. "\n" .. amount, -- zwei Zeilen: passt auch auf schmale Bildschirme
				TextSize = 22,
				BackgroundColor3 = color,
				Size = UDim2.new(1 / count, -8 * (count - 1) / count, 1, 0),
				LayoutOrder = i,
				Parent = row,
			})
			button.Activated:Connect(function()
				if self.CoinId then
					MarketClient.Trade(self.CoinId, side, fraction)
				end
			end)
		end
	end
	tradeRow(2, "Buy", Colors.Green)
	tradeRow(3, "Sell", Colors.Red)

	-- Schutz: Stop-Loss (ab Level 3) und Versicherung (ab Level 5)
	local protectRow = Screen.New("Frame", {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = right,
	}, {
		Screen.New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local stopButton = Screen.Button({
		TextSize = 20,
		Size = UDim2.new(0.5, -4, 1, 0),
		LayoutOrder = 1,
		Parent = protectRow,
	})
	local insureButton = Screen.Button({
		TextSize = 20,
		Size = UDim2.new(0.5, -4, 1, 0),
		LayoutOrder = 2,
		Parent = protectRow,
	})
	local stopLevels = Config.Protection.StopLossLevels
	stopButton.Activated:Connect(function()
		local coinId = self.CoinId
		if not coinId then
			return
		end
		-- Stufen durchschalten: OFF -> -10 % -> -20 % -> -30 % -> -50 % -> OFF
		local position = MarketClient.Me.Positions[coinId]
		local current = 0
		for i, level in stopLevels do
			if position and position.SL == level then
				current = i
			end
		end
		MarketClient.SetStopLoss(coinId, (current + 1) % (#stopLevels + 1))
	end)
	insureButton.Activated:Connect(function()
		local coinId = self.CoinId
		if coinId then
			local insured = MarketClient.Me.Insured or {}
			MarketClient.SetInsurance(coinId, not insured[coinId])
		end
	end)

	Screen.Label({
		Text = "LIVE TRADES",
		Font = Screen.Fonts.Bold,
		TextSize = 20,
		TextColor3 = Colors.Muted,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 6,
		Parent = right,
	})
	local tradeList = Screen.New("Frame", {
		-- füllt den Rest: 26 + 72 + 72 + 64 + 22 + 5 Abstände à 6 = 286 (kleinster Bildschirm: 2 Zeilen)
		Size = UDim2.new(1, 0, 1, -286),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		LayoutOrder = 7,
		Parent = right,
	}, {
		Screen.New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local tradeLabels = {}
	for i = 1, TRADE_ROWS do
		tradeLabels[i] = Screen.Label({
			TextSize = 20,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = i,
			Parent = tradeList,
		})
	end

	------------------------------------------------------------------
	-- Erklärung zu einer Ampel (Fenster über der Coin-Seite)
	------------------------------------------------------------------
	local overlay = Screen.New("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Background,
		BackgroundTransparency = 0.3,
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	})
	local helpPanel = Screen.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.65, 0, 1, -20),
		BackgroundColor3 = Colors.Panel,
		Active = true, -- Tippen ins Fenster schließt es nicht
		ZIndex = 21,
		Parent = overlay,
	}, {
		Screen.Corner(14),
		Screen.Padding(16),
		Screen.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local function helpLabel(order: number, height: number, props)
		props.Size = UDim2.new(1, 0, 0, height)
		props.LayoutOrder = order
		props.ZIndex = 22
		props.Parent = helpPanel
		return Screen.Label(props)
	end
	local helpTitle = helpLabel(1, 32, { Font = Screen.Fonts.Bold, TextSize = 28 })
	local helpText = helpLabel(2, 80, {
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local helpRules = {}
	for i = 1, 3 do
		helpRules[i] = helpLabel(2 + i, 26, {})
	end
	-- Pro: Top-10-Namen (2 Spalten à 5) bzw. Dev-Verkäufe; ohne Pro gesperrte Kachel "🔒 PRO"
	local proList = Screen.New("Frame", {
		Size = UDim2.new(1, 0, 0, 5 * 26),
		BackgroundTransparency = 1,
		Visible = false,
		LayoutOrder = 6,
		ZIndex = 22,
		Parent = helpPanel,
	}, {
		Screen.New("UIGridLayout", {
			CellSize = UDim2.new(0.5, -6, 0, 26),
			CellPadding = UDim2.fromOffset(6, 0),
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local proRows = {}
	for i = 1, 10 do
		proRows[i] = Screen.Label({ TextSize = 20, LayoutOrder = i, ZIndex = 23, Parent = proList })
	end
	local buttonRow = Screen.New("Frame", {
		Size = UDim2.new(1, 0, 0, 72),
		BackgroundTransparency = 1,
		LayoutOrder = 10,
		ZIndex = 22,
		Parent = helpPanel,
	}, {
		Screen.New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local okButton = Screen.Button({
		Text = "OK",
		Size = UDim2.fromOffset(200, 72),
		LayoutOrder = 1,
		ZIndex = 22,
		Parent = buttonRow,
	})
	local proButton = Screen.Button({
		BackgroundColor3 = Colors.Accent,
		TextColor3 = Colors.Background,
		TextSize = 20,
		Size = UDim2.new(1, -208, 1, 0),
		Visible = false,
		LayoutOrder = 2,
		ZIndex = 22,
		Parent = buttonRow,
	})
	proButton.Activated:Connect(function()
		MarketClient.Buy("Pro")
	end)
	local proTop = nil -- zuletzt geladene Top-10-Liste
	local proTopCoin = nil

	updateHelp = function()
		local coin = self.CoinId and MarketClient.Coins[self.CoinId]
		if not (helpDef and coin) then
			return
		end
		local value = Indicators.Value(coin, helpDef.Id)
		local rating = Indicators.Rate(helpDef.Id, value)
		helpTitle.Text = string.format("%s: %s %s", helpDef.Title, Indicators.Display(helpDef.Id, value), RATING_DOTS[rating])
		helpTitle.TextColor3 = RATING_COLORS[rating]
		helpText.Text = helpDef.Explain
		local rules = Indicators.Rules(helpDef.Id)
		for i, label in helpRules do
			label.Text = rules[i] or ""
		end

		-- Pro-Teile: Top 10 mit Namen, Dev-Verkäufe live
		local pro = MarketClient.HasPass("Pro")
		local proTopic = helpDef.Id == "Top10" or helpDef.Id == "Dev"
		proButton.Visible = proTopic and not pro
		proButton.Text = if helpDef.Id == "Top10" then "🔒 PRO: see top 10 names" else "🔒 PRO: dev sells live"
		local showList = proTopic and pro
		proList.Visible = showList
		helpText.Visible = not showList
		for _, label in helpRules do
			label.Visible = not showList
		end
		if not showList then
			return
		end
		for _, label in proRows do
			label.Text = ""
			label.TextColor3 = Colors.Text
		end
		if helpDef.Id == "Top10" then
			if proTopCoin ~= coin.Id or not proTop then
				proRows[1].Text = "Loading…"
				return
			end
			for i, entry in proTop do
				proRows[i].Text = string.format(
					"%d. %s%s %s",
					i,
					if entry.D then "👨‍💻 " else "",
					CreatorStyle.Name(entry.N, MarketClient.CreatorTier(entry.U)),
					Indicators.Display("Top10", entry.S)
				)
				proRows[i].TextColor3 = if entry.D then Colors.Accent else Colors.Text
			end
		else
			-- Dev-Trades aus den letzten Live-Trades
			local shown = 0
			local trades = coin.Trades or {}
			for i = #trades, 1, -1 do
				local trade = trades[i]
				if MarketClient.IsDevTrade(coin, trade) and shown < 10 then
					shown += 1
					proRows[shown].Text = string.format(
						"%s %s · %s ago",
						if trade.Side == "Buy" then "🟢 bought" else "🔴 sold",
						Format.Cash(trade.Cash),
						Format.Duration(workspace:GetServerTimeNow() - (trade.Time or 0))
					)
				end
			end
			if shown == 0 then
				proRows[1].Text = "No dev trades in the last " .. Config.Market.RecentTrades .. " trades"
			end
		end
	end
	showHelp = function(def)
		helpDef = def
		updateHelp()
		overlay.Visible = true
		local coinId = self.CoinId
		if def.Id == "Top10" and coinId and MarketClient.HasPass("Pro") then
			proTop, proTopCoin = nil, coinId
			task.spawn(function()
				local list = MarketClient.ProInfo(coinId)
				if helpDef == def and self.CoinId == coinId then
					proTop = list or {}
					updateHelp()
				end
			end)
		end
	end
	local function hideHelp()
		helpDef = nil
		overlay.Visible = false
	end
	okButton.Activated:Connect(hideHelp)
	overlay.Activated:Connect(hideHelp)

	------------------------------------------------------------------
	-- Anzeige
	------------------------------------------------------------------
	function self.Show(coinId: string)
		hideHelp()
		self.CoinId = coinId
		self.Refresh()
	end

	function self.Refresh()
		local coin = self.CoinId and MarketClient.Coins[self.CoinId]
		if not coin then
			nameLabel.Text = "Coin is gone"
			priceLabel.Text = ""
			return
		end

		nameLabel.Text = string.format("%s %s  $%s", coin.Icon, coin.Name, coin.Ticker)
		local mine = coin.CreatorId == MarketClient.MyKey
		local canRug = mine and (MarketClient.Me.RugLicense or 0) > 0 and not coin.Rugged and coin.Stage ~= "Dead"
		boostButton.Visible = mine
		rugButton.Visible = canRug
		local labelWidth = if canRug then -84 - 256 elseif mine then -84 - 128 else -84
		if canRug then
			local t = workspace:GetServerTimeNow()
			local ageLeft = Config.Rug.MinCoinAge - (t - coin.CreatedAt)
			local cooldownLeft = (MarketClient.Me.RugReadyAt or 0) - t
			if cooldownLeft > 0 then
				rugButton.Text = "☠ RUG\n" .. Format.Duration(cooldownLeft)
			elseif ageLeft > 0 then
				rugButton.Text = "☠ RUG\nin " .. Format.Duration(ageLeft)
			else
				rugButton.Text = "☠ RUG\n" .. MarketClient.Me.RugLicense .. " left"
			end
		end
		nameLabel.Size = UDim2.new(1, labelWidth, 0, 36)
		priceLabel.Size = UDim2.new(1, labelWidth, 0, 30)
		if mine then
			local boostLeft = MarketClient.BoostLeft(coin.Id)
			local myStats = MarketClient.Me.Stats
			if boostLeft > 0 then
				boostButton.Text = "🚀 " .. Format.Duration(boostLeft)
			elseif (MarketClient.Me.FreeBoosts or 0) > 0 then
				boostButton.Text = "🚀 BOOST\nFREE ×" .. MarketClient.Me.FreeBoosts -- Bronze-Creator / Robux
			elseif not canBoostWithCash() then
				boostButton.Text = "🚀 BOOST\nR$ " .. Config.Shop.Products.Boost.Robux -- ohne Level, mit Robux
			else
				boostButton.Text = "🚀 BOOST\n" .. Format.Short(Config.Launch.BoostCost)
			end
		end
		local change = MarketClient.ChartChange(coin)
		if coin.Rugged then
			priceLabel.Text = string.format("%s  ·  RUGGED", Format.Price(coin.Price))
			priceLabel.TextColor3 = Colors.Red
		else
			priceLabel.Text = string.format("%s  %s", Format.Price(coin.Price), Format.Percent(change))
			priceLabel.TextColor3 = if change >= 0 then Colors.Green else Colors.Red
		end

		chart:SetData(coin.Chart or {}, coin.Candle)
		local pro = MarketClient.HasPass("Pro")
		if not pro and candles then
			candles = false
			chart:SetCandles(false)
		end
		candleButton.Text = if not pro then "🕯 🔒 PRO" elseif candles then "📈 LINE" else "🕯 CANDLE"

		infoLabel.Text = string.format(
			"MC %s · Migration %d%% · %s · %s · by %s",
			Format.Short(coin.MarketCap),
			math.min(100, math.floor(coin.MarketCap / Config.Curve.MigrationMarketCap * 100)),
			Format.Duration(MarketClient.Age(coin)),
			coin.Stage,
			CreatorStyle.Name(coin.CreatorName or "?", MarketClient.CreatorTier(coin.CreatorId))
		)

		for _, def in Indicators.List do
			local value = Indicators.Value(coin, def.Id)
			local rating = Indicators.Rate(def.Id, value)
			local chip = chips[def.Id]
			chip.Value.Text = Indicators.Display(def.Id, value)
			chip.Value.TextColor3 = RATING_COLORS[rating]
			chip.Stroke.Color = RATING_COLORS[rating]
		end
		if helpDef then
			updateHelp()
		end

		local position = MarketClient.Me.Positions[coin.Id]
		if position then
			local value = MarketClient.PositionValue(coin, position)
			local pnl = if position.Cost > 0 then value / position.Cost - 1 else 0
			positionLabel.Text = string.format(
				"You: %s · %s (%s)%s",
				Format.Short(position.Amount),
				Format.Cash(value),
				Format.Percent(pnl),
				if mine then " · sell max 25%/min" else "" -- Ersteller verkauft stufenweise
			)
			positionLabel.TextColor3 = if pnl >= 0 then Colors.Green else Colors.Red
		else
			positionLabel.Text = "You hold none"
			positionLabel.TextColor3 = Colors.Muted
		end

		local stats = MarketClient.Me.Stats
		local myLevel = if stats then stats.Level else 1
		local protection = Config.Protection
		if myLevel < protection.StopLossMinLevel then
			stopButton.Text = "🛑 STOP 🔒 Lv " .. protection.StopLossMinLevel
			stopButton.BackgroundColor3 = Colors.PanelLight
		else
			local sl = position and position.SL
			stopButton.Text = if sl then string.format("🛑 STOP -%d%%", math.floor(sl * 100 + 0.5)) else "🛑 STOP OFF"
			stopButton.BackgroundColor3 = if sl then Colors.Border else Colors.PanelLight
		end
		if myLevel < protection.InsuranceMinLevel then
			insureButton.Text = "🛡 INSURE 🔒 Lv " .. protection.InsuranceMinLevel
			insureButton.BackgroundColor3 = Colors.PanelLight
		else
			local on = (MarketClient.Me.Insured or {})[coin.Id] == true
			insureButton.Text = if on then "🛡 INSURED +5%" else "🛡 INSURE OFF"
			insureButton.BackgroundColor3 = if on then Colors.Border else Colors.PanelLight
		end

		local trades = coin.Trades or {}
		for i = 1, TRADE_ROWS do
			local trade = trades[#trades - i + 1]
			local label = tradeLabels[i]
			if trade then
				-- Pro: Käufe/Verkäufe des Erstellers live markiert
				local isDev = pro and MarketClient.IsDevTrade(coin, trade)
				label.Text = string.format(
					"%s%s%s %s %s",
					if isDev then "👨‍💻 DEV " else "",
					if trade.IsNpc then "🤖 " else "",
					CreatorStyle.Name(trade.Trader or "?", MarketClient.CreatorTier(trade.TraderId), trade.Vip),
					if trade.Side == "Buy" then "bought" else "sold",
					Format.Cash(trade.Cash)
				)
				label.TextColor3 = if isDev then Colors.Accent elseif trade.Side == "Buy" then Colors.Green else Colors.Red
			else
				label.Text = ""
			end
		end
	end

	return self
end

return CoinPage
