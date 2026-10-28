-- CoinPage (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/CoinPage
-- Coin-Seite: links Chart + Infos, rechts Position, Kaufen/Verkaufen (10/25/50 %/alles), Live-Trades.
-- Stop-Loss und Versicherung kommen in Phase 5.
--
-- Platz (kleinster Fall 976 x 368 Design-Pixel):
--   links 60 %: Kopf 72 | Chart | 2 Infozeilen à 24
--   rechts 40 %: Position 26 | BUY 20+72 | SELL 20+72 | Live-Trades (Rest, mind. 3 Zeilen)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Screen = require(script.Parent.Screen)
local MarketClient = require(script.Parent.MarketClient)
local ChartRenderer = require(script.Parent.ChartRenderer)

local Colors = Screen.Colors
local TRADE_ROWS = 8

local CoinPage = {}

-- parent: Seite, onBack(): zurück zur vorigen Seite
function CoinPage.new(parent: GuiObject, onBack: () -> ())
	local self = { CoinId = nil :: string? }

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

	local chartHolder = Screen.New("Frame", {
		Position = UDim2.fromOffset(0, 82),
		Size = UDim2.new(1, 0, 1, -82 - 56),
		BackgroundTransparency = 1,
		Parent = left,
	})
	local chart = ChartRenderer.new(chartHolder)

	local infoLabel = Screen.Label({
		TextSize = 20,
		TextColor3 = Colors.Muted,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 4, 1, -26),
		Size = UDim2.new(1, -8, 0, 24),
		Parent = left,
	})
	local warningLabel = Screen.Label({
		TextSize = 20,
		TextColor3 = Colors.Red,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 4, 1, 0),
		Size = UDim2.new(1, -8, 0, 24),
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
		Screen.Label({
			Text = if side == "Buy" then "BUY" else "SELL",
			Font = Screen.Fonts.Bold,
			TextSize = 20,
			TextColor3 = color,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = order,
			Parent = right,
		})
		local row = Screen.New("Frame", {
			Size = UDim2.new(1, 0, 0, 72),
			BackgroundTransparency = 1,
			LayoutOrder = order + 1,
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
			local button = Screen.Button({
				Text = if fraction >= 1
					then (if side == "Buy" then "MAX" else "ALL")
					else math.floor(fraction * 100 + 0.5) .. "%",
				TextSize = 24,
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
	tradeRow(4, "Sell", Colors.Red)

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
		-- füllt den Rest: 26 + 20 + 72 + 20 + 72 + 22 + 6 Abstände à 6 = 268
		Size = UDim2.new(1, 0, 1, -268),
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
	-- Anzeige
	------------------------------------------------------------------
	function self.Show(coinId: string)
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
		local change = MarketClient.ChartChange(coin)
		if coin.Rugged then
			priceLabel.Text = string.format("%s  ·  RUGGED", Format.Price(coin.Price))
			priceLabel.TextColor3 = Colors.Red
		else
			priceLabel.Text = string.format("%s  %s", Format.Price(coin.Price), Format.Percent(change))
			priceLabel.TextColor3 = if change >= 0 then Colors.Green else Colors.Red
		end

		chart:SetData(coin.Chart or {}, coin.Candle)

		infoLabel.Text = string.format(
			"MC %s · 👥 %d · Dev %.1f%% · %s · %s",
			Format.Short(coin.MarketCap),
			coin.Holders,
			coin.DevShare * 100,
			Format.Duration(MarketClient.Age(coin)),
			coin.Stage
		)
		if coin.CreatorHasLicense then
			warningLabel.Text = "by " .. coin.CreatorName .. " · ⚠ LIC: creator owns a rug pull license"
			warningLabel.TextColor3 = Colors.Red
		else
			warningLabel.Text = "by " .. coin.CreatorName
			warningLabel.TextColor3 = Colors.Muted
		end

		local position = MarketClient.Me.Positions[coin.Id]
		if position then
			local value = MarketClient.PositionValue(coin, position)
			local pnl = if position.Cost > 0 then value / position.Cost - 1 else 0
			positionLabel.Text = string.format(
				"You: %s · %s (%s)",
				Format.Short(position.Amount),
				Format.Cash(value),
				Format.Percent(pnl)
			)
			positionLabel.TextColor3 = if pnl >= 0 then Colors.Green else Colors.Red
		else
			positionLabel.Text = "You hold none"
			positionLabel.TextColor3 = Colors.Muted
		end

		local trades = coin.Trades or {}
		for i = 1, TRADE_ROWS do
			local trade = trades[#trades - i + 1]
			local label = tradeLabels[i]
			if trade then
				label.Text = string.format(
					"%s%s %s %s",
					if trade.IsNpc then "🤖 " else "",
					trade.Trader,
					if trade.Side == "Buy" then "bought" else "sold",
					Format.Cash(trade.Cash)
				)
				label.TextColor3 = if trade.Side == "Buy" then Colors.Green else Colors.Red
			else
				label.Text = ""
			end
		end
	end

	return self
end

return CoinPage
