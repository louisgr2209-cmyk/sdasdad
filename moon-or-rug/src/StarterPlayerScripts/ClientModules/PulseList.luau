-- PulseList (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/PulseList
-- Startseite: drei Spalten New · Almost done · Migrated.
-- Pro Coin: Icon, Ticker, Alter, Marktkapital, Holder, Dev-Anteil, Rug-Lizenz-Warnung, Schnellkauf.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Screen = require(script.Parent.Screen)
local MarketClient = require(script.Parent.MarketClient)
local Indicators = require(ReplicatedStorage.Shared.Indicators)

local Colors = Screen.Colors
local MAX_PER_COLUMN = 20
local CARD_HEIGHT = 96

local COLUMNS = {
	{ Stage = "New", Title = "NEW" },
	{ Stage = "AlmostDone", Title = "ALMOST DONE" },
	{ Stage = "Migrated", Title = "MIGRATED" },
}

local PulseList = {}

-- parent: Seite, onOpenCoin(coinId): Coin-Seite öffnen
function PulseList.new(parent: GuiObject, onOpenCoin: (string) -> ())
	local self = { Cards = {}, Columns = {} }

	Screen.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})

	for i, def in COLUMNS do
		local column = Screen.New("Frame", {
			Size = UDim2.new(1 / #COLUMNS, -8, 1, 0),
			BackgroundColor3 = Colors.Panel,
			LayoutOrder = i,
			Parent = parent,
		}, {
			Screen.Corner(12),
		})
		local title = Screen.Label({
			Text = def.Title,
			Font = Screen.Fonts.Bold,
			TextSize = 22,
			TextColor3 = Colors.Muted,
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -24, 0, 30),
			Parent = column,
		})
		local list = Screen.Scroller({
			Position = UDim2.fromOffset(8, 42),
			Size = UDim2.new(1, -16, 1, -50),
			Parent = column,
		})
		self.Columns[def.Stage] = { Title = title, List = list, Name = def.Title }
	end

	-- Eine Karte pro Coin, wird wiederverwendet
	local function getCard(coinId: string)
		local card = self.Cards[coinId]
		if card then
			return card
		end
		local frame = Screen.New("TextButton", {
			Text = "",
			AutoButtonColor = true,
			Size = UDim2.new(1, -8, 0, CARD_HEIGHT),
			BackgroundColor3 = Colors.PanelLight,
		}, {
			Screen.Corner(10),
		})
		-- Breite: Text links (78 %), BUY rechts (22 %, auf dem iPad ca. 64). Bei 1000 Design-Pixeln
		-- Bildschirmbreite (iPad) bleiben ca. 166 Pixel für Text = ca. 16 Zeichen pro Zeile.
		card = {
			Frame = frame,
			Stroke = Screen.New("UIStroke", {
				Color = Colors.Red,
				Thickness = 2,
				Enabled = false,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Parent = frame,
			}),
			Icon = Screen.Label({
				TextSize = 30,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(8, 8),
				Size = UDim2.fromOffset(36, 36),
				Parent = frame,
			}),
			Top = Screen.Label({
				Font = Screen.Fonts.Bold,
				TextSize = 22,
				Position = UDim2.fromOffset(52, 8),
				Size = UDim2.new(0.78, -60, 0, 26),
				Parent = frame,
			}),
			Middle = Screen.Label({
				TextSize = 20,
				TextColor3 = Colors.Muted,
				Position = UDim2.fromOffset(52, 36),
				Size = UDim2.new(0.78, -60, 0, 24),
				Parent = frame,
			}),
			Bottom = Screen.Label({
				TextSize = 20,
				TextColor3 = Colors.Muted,
				Position = UDim2.fromOffset(52, 62),
				Size = UDim2.new(0.78, -60, 0, 24),
				Parent = frame,
			}),
			Buy = Screen.Button({
				Text = "BUY",
				TextSize = 22,
				BackgroundColor3 = Colors.Green,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.new(0.22, 0, 0, 80),
				Parent = frame,
			}),
		}
		frame.Activated:Connect(function()
			onOpenCoin(coinId)
		end)
		card.Buy.Activated:Connect(function()
			MarketClient.Trade(coinId, "Buy", Config.Trade.QuickBuyFraction)
		end)
		self.Cards[coinId] = card
		return card
	end

	function self.Refresh()
		-- Coins nach Spalte sortieren
		local byStage = { New = {}, AlmostDone = {}, Migrated = {} }
		for _, coin in MarketClient.Coins do
			local list = byStage[coin.Stage]
			if list then -- "Dead" erscheint nicht
				table.insert(list, coin)
			end
		end
		table.sort(byStage.New, function(a, b)
			return a.CreatedAt > b.CreatedAt
		end)
		table.sort(byStage.AlmostDone, function(a, b)
			return a.MarketCap > b.MarketCap
		end)
		table.sort(byStage.Migrated, function(a, b)
			return a.MarketCap > b.MarketCap
		end)

		local shown = {}
		for stage, coins in byStage do
			local column = self.Columns[stage]
			column.Title.Text = string.format("%s  (%d)", column.Name, #coins)
			for index = 1, math.min(#coins, MAX_PER_COLUMN) do
				local coin = coins[index]
				local card = getCard(coin.Id)
				shown[coin.Id] = true
				card.Frame.LayoutOrder = index
				card.Frame.Parent = column.List
				card.Icon.Text = coin.Icon
				card.Top.Text = string.format("$%s · %s", coin.Ticker, Format.Duration(MarketClient.Age(coin)))
				card.Middle.Text = string.format("MC %s · 👥%d", Format.Short(coin.MarketCap), coin.Holders)
				if coin.Rugged then
					card.Bottom.Text = "RUGGED"
					card.Bottom.TextColor3 = Colors.Red
				elseif coin.CreatorHasLicense then
					-- ⚠ LIC = Ersteller hat eine Rug-Lizenz (Erklärung auf der Coin-Seite)
					card.Bottom.Text = string.format("Dev %.0f%% · ⚠ LIC", coin.DevShare * 100)
					card.Bottom.TextColor3 = Colors.Red
				else
					-- Dev-Anteil mit derselben Ampel wie auf der Coin-Seite (gelb/rot = Dev hat dazugekauft)
					local rating = Indicators.Rate("Dev", coin.DevShare)
					card.Bottom.Text = string.format("Dev %.0f%%", coin.DevShare * 100)
					card.Bottom.TextColor3 = if rating == "Good" then Colors.Muted
						elseif rating == "Ok" then Colors.Accent
						else Colors.Red
				end
				card.Stroke.Enabled = coin.Rugged == true
			end
		end

		-- Karten von Coins, die nicht mehr angezeigt werden, entfernen
		for coinId, card in self.Cards do
			if not shown[coinId] then
				card.Frame:Destroy()
				self.Cards[coinId] = nil
			end
		end
	end

	return self
end

return PulseList
