-- TutorialUI (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/TutorialUI
-- Pflicht-Tutorial für neue Spieler (nicht überspringbar, kurz):
--   1) Coin antippen   2) BUY tippen   3) SELL ALL tippen   4) fertig
-- Alles außer der aktuellen Aufgabe ist abgedunkelt und gesperrt (4 Blocker-Flächen um ein "Loch").
-- Erledigt wird auf dem Server gespeichert (kommt nie wieder).

local RunService = game:GetService("RunService")

local Screen = require(script.Parent.Screen)
local MarketClient = require(script.Parent.MarketClient)

local Colors = Screen.Colors
local Z = 80 -- über allem (Fenster 30–41, Hinweis 60)

local TutorialUI = {}

-- root: Terminal-Root. targets = { Pulse = () -> GuiObject, Buy = () -> GuiObject, Sell = () -> GuiObject,
--   CoinOpen = () -> string? (geöffneter Coin oder nil) }
function TutorialUI.Start(root: GuiObject, targets)
	local step = 1
	local coinId: string? = nil
	local finished = false

	-- 4 Blocker (oben, unten, links, rechts vom Loch): fangen jedes Tippen ab
	local blockers = {}
	for i = 1, 4 do
		blockers[i] = Screen.New("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BorderSizePixel = 0,
			BackgroundColor3 = Colors.Background,
			BackgroundTransparency = 0.35,
			ZIndex = Z,
			Parent = root,
		})
	end
	-- Rahmen um das Loch
	local ring = Screen.New("Frame", {
		BackgroundTransparency = 1,
		ZIndex = Z + 1,
		Parent = root,
	}, {
		Screen.Corner(12),
		Screen.New("UIStroke", { Color = Colors.Accent, Thickness = 3 }),
	})
	-- Sprechblase oben in der Mitte
	local bubble = Screen.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.new(0.7, 0, 0, 72),
		BackgroundColor3 = Colors.Panel,
		ZIndex = Z + 2,
		Parent = root,
	}, {
		Screen.Corner(12),
		Screen.New("UIStroke", { Color = Colors.Accent, Thickness = 2 }),
	})
	local text = Screen.Label({
		Font = Screen.Fonts.Bold,
		TextSize = 24,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -24, 1, 0),
		ZIndex = Z + 3,
		Parent = bubble,
	})
	-- Schluss-Knopf (nur bei Schritt 4)
	local doneButton = Screen.Button({
		Text = "LET'S TRADE 🚀",
		BackgroundColor3 = Colors.Green,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(300, 72),
		Visible = false,
		ZIndex = Z + 2,
		Parent = root,
	})

	local TEXTS = {
		"👋 Welcome! Tap any coin to open it.",
		"Tap BUY to buy a little of this coin.",
		"Prices move fast! Tap SELL ALL to take your profit (or loss).",
		"That's it! Buy early, sell high, level up. Watch out for rug pulls! 🚨",
	}

	-- Loch auf ein GuiObject setzen (Design-Pixel relativ zu root), nil = alles abdunkeln
	local function hole(target: GuiObject?)
		local scale = Screen.GetScale()
		local rootPos, rootSize = root.AbsolutePosition, root.AbsoluteSize / scale
		local x0, y0, x1, y1 = 0, 0, 0, 0
		if target and target.Visible then
			local pos = (target.AbsolutePosition - rootPos) / scale - Vector2.new(6, 6)
			local size = target.AbsoluteSize / scale + Vector2.new(12, 12)
			x0, y0 = math.max(0, pos.X), math.max(0, pos.Y)
			x1, y1 = math.min(rootSize.X, pos.X + size.X), math.min(rootSize.Y, pos.Y + size.Y)
		end
		local W, H = rootSize.X, rootSize.Y
		local rects = {
			{ 0, 0, W, y0 }, -- oben
			{ 0, y1, W, H - y1 }, -- unten
			{ 0, y0, x0, y1 - y0 }, -- links
			{ x1, y0, W - x1, y1 - y0 }, -- rechts
		}
		for i, r in rects do
			blockers[i].Position = UDim2.fromOffset(r[1], r[2])
			blockers[i].Size = UDim2.fromOffset(math.max(0, r[3]), math.max(0, r[4]))
		end
		ring.Visible = x1 > x0
		ring.Position = UDim2.fromOffset(x0, y0)
		ring.Size = UDim2.fromOffset(x1 - x0, y1 - y0)
	end

	local connection
	local function finish()
		if finished then
			return
		end
		finished = true
		connection:Disconnect()
		MarketClient.SetFlag("Tutorial")
		for _, blocker in blockers do
			blocker:Destroy()
		end
		ring:Destroy()
		bubble:Destroy()
		doneButton:Destroy()
	end
	doneButton.Activated:Connect(finish)

	-- Jeden Frame: Fortschritt prüfen und Loch nachführen (Fenstergröße/Drehung ändert sich)
	connection = RunService.RenderStepped:Connect(function()
		local positions = MarketClient.Me.Positions or {}
		if step == 1 then
			local open = targets.CoinOpen()
			local coin = open and MarketClient.Coins[open]
			if coin and not coin.Rugged and coin.Stage ~= "Dead" then
				coinId = open
				step = 2
			end
		elseif step == 2 then
			if targets.CoinOpen() ~= coinId then
				step = 1 -- Coin verschwunden: nochmal einen wählen
			elseif positions[coinId] then
				step = 3
			end
		elseif step == 3 then
			if not positions[coinId] then
				step = 4
			end
		end
		text.Text = TEXTS[step]
		doneButton.Visible = step == 4
		if step == 1 then
			hole(targets.Pulse())
		elseif step == 2 then
			hole(targets.Buy())
		elseif step == 3 then
			hole(targets.Sell())
		else
			hole(doneButton)
		end
	end)
end

return TutorialUI
