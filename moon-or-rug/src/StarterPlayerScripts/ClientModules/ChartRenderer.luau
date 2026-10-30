-- ChartRenderer (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/ChartRenderer
-- Zeichnet einen Linien-Chart aus kleinen Balken (Frames). Roblox hat keine Chart-Bibliothek.
-- 60 Punkte + aktueller Punkt. Grün = gestiegen, Rot = gefallen.
-- Pro-Terminal (Phase 8): Kerzen-Modus (Docht = Hoch/Tief, Körper = Start/Ende je 5 Sek.).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Screen = require(script.Parent.Screen)

local Colors = Screen.Colors
local LINE_THICKNESS = 3 -- Design-Pixel

local ChartRenderer = {}
ChartRenderer.__index = ChartRenderer

-- parent: Frame, in den der Chart gezeichnet wird (füllt ihn ganz aus)
function ChartRenderer.new(parent: GuiObject)
	local self = setmetatable({}, ChartRenderer)
	self.Frame = Screen.New("Frame", {
		Name = "Chart",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		ClipsDescendants = true,
		Parent = parent,
	}, {
		Screen.Corner(12),
	})
	-- Zeichenfläche mit Rand, damit Linie und Beschriftung nicht am Rand kleben
	self.Area = Screen.New("Frame", {
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.new(1, -24, 1, -60),
		BackgroundTransparency = 1,
		Parent = self.Frame,
	})
	self.HighLabel = Screen.Label({
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -24, 0, 24),
		TextSize = 20,
		TextColor3 = Colors.Muted,
		Parent = self.Frame,
	})
	self.LowLabel = Screen.Label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -4),
		Size = UDim2.new(1, -24, 0, 24),
		TextSize = 20,
		TextColor3 = Colors.Muted,
		Parent = self.Frame,
	})
	self.Segments = {}
	self.Wicks = {}
	self.Points = {}
	self.Candles = {} -- { O, H, L, C }
	self.CandleMode = false
	self.Area:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:Draw()
	end)
	return self
end

-- chart = Liste { O, H, L, C }, current = aktueller Punkt (oder nil)
function ChartRenderer:SetData(chart, current)
	local points, candles = {}, {}
	for _, point in chart do
		table.insert(points, point.C)
		table.insert(candles, point)
	end
	if current then
		table.insert(points, current.C)
		table.insert(candles, current)
	end
	self.Points = points
	self.Candles = candles
	self:Draw()
end

function ChartRenderer:SetCandles(on: boolean)
	self.CandleMode = on
	self:Draw()
end

local function segment(self, index: number, list)
	list = list or self.Segments
	local frame = list[index]
	if not frame then
		frame = Screen.New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0,
			Parent = self.Area,
		})
		list[index] = frame
	end
	frame.Visible = true
	frame.Rotation = 0
	return frame
end

local function hideFrom(list, first: number)
	for i = first, #list do
		list[i].Visible = false
	end
end

-- Kerzen: Docht von Tief bis Hoch, Körper von Start bis Ende
local function drawCandles(self, size: Vector2)
	local candles = self.Candles
	local low, high = math.huge, -math.huge
	for _, c in candles do
		low = math.min(low, c.L or c.C)
		high = math.max(high, c.H or c.C)
	end
	if high - low < high * 0.001 then
		high += high * 0.01
		low -= low * 0.01
	end
	self.HighLabel.Text = "High " .. Format.Price(high)
	self.LowLabel.Text = "Low " .. Format.Price(low)
	local stepX = size.X / math.max(1, #candles)
	local function y(price: number): number
		return size.Y * (1 - (price - low) / (high - low))
	end
	for i, c in candles do
		local x = (i - 0.5) * stepX
		local color = if c.C >= c.O then Colors.Green else Colors.Red
		local wick = segment(self, i, self.Wicks)
		wick.BackgroundColor3 = color
		local top, bottom = y(c.H or c.C), y(c.L or c.C)
		wick.Position = UDim2.fromOffset(x, (top + bottom) / 2)
		wick.Size = UDim2.fromOffset(2, math.max(1, bottom - top))
		local body = segment(self, i)
		body.BackgroundColor3 = color
		local bodyTop, bodyBottom = y(math.max(c.O, c.C)), y(math.min(c.O, c.C))
		body.Position = UDim2.fromOffset(x, (bodyTop + bodyBottom) / 2)
		body.Size = UDim2.fromOffset(math.max(2, stepX * 0.6), math.max(2, bodyBottom - bodyTop))
	end
	hideFrom(self.Segments, #candles + 1)
	hideFrom(self.Wicks, #candles + 1)
end

function ChartRenderer:Draw()
	local points = self.Points
	local scale = Screen.GetScale()
	local size = self.Area.AbsoluteSize / scale -- Größe in Design-Pixeln
	if #points < 2 or size.X <= 0 or size.Y <= 0 then
		hideFrom(self.Segments, 1)
		hideFrom(self.Wicks, 1)
		self.HighLabel.Text = if points[1] then Format.Price(points[1]) else ""
		self.LowLabel.Text = "Waiting for trades…"
		return
	end

	if self.CandleMode then
		drawCandles(self, size)
		return
	end
	hideFrom(self.Wicks, 1)

	local low, high = math.huge, -math.huge
	for _, p in points do
		low = math.min(low, p)
		high = math.max(high, p)
	end
	if high - low < high * 0.001 then -- flacher Kurs: etwas Luft oben/unten
		high += high * 0.01
		low -= low * 0.01
	end
	self.HighLabel.Text = "High " .. Format.Price(high)
	self.LowLabel.Text = "Low " .. Format.Price(low)

	local color = if points[#points] >= points[1] then Colors.Green else Colors.Red
	local stepX = size.X / (#points - 1)
	local function pos(i: number): Vector2
		return Vector2.new((i - 1) * stepX, size.Y * (1 - (points[i] - low) / (high - low)))
	end

	for i = 1, #points - 1 do
		local a, b = pos(i), pos(i + 1)
		local delta = b - a
		local frame = segment(self, i)
		frame.BackgroundColor3 = color
		frame.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
		frame.Size = UDim2.fromOffset(delta.Magnitude + 1, LINE_THICKNESS)
		frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	end
	hideFrom(self.Segments, #points)
end

return ChartRenderer
