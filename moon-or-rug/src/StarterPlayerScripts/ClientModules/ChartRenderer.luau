-- ChartRenderer (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/ChartRenderer
-- Zeichnet einen Linien-Chart aus kleinen Balken (Frames). Roblox hat keine Chart-Bibliothek.
-- 60 Punkte + aktueller Punkt. Grün = gestiegen, Rot = gefallen.

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
	self.Points = {}
	self.Area:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:Draw()
	end)
	return self
end

-- chart = Liste { O, H, L, C }, current = aktueller Punkt (oder nil)
function ChartRenderer:SetData(chart, current)
	local points = {}
	for _, point in chart do
		table.insert(points, point.C)
	end
	if current then
		table.insert(points, current.C)
	end
	self.Points = points
	self:Draw()
end

local function segment(self, index: number)
	local frame = self.Segments[index]
	if not frame then
		frame = Screen.New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0,
			Parent = self.Area,
		})
		self.Segments[index] = frame
	end
	frame.Visible = true
	return frame
end

function ChartRenderer:Draw()
	local points = self.Points
	local scale = Screen.GetScale()
	local size = self.Area.AbsoluteSize / scale -- Größe in Design-Pixeln
	if #points < 2 or size.X <= 0 or size.Y <= 0 then
		for _, frame in self.Segments do
			frame.Visible = false
		end
		self.HighLabel.Text = if points[1] then Format.Price(points[1]) else ""
		self.LowLabel.Text = "Waiting for trades…"
		return
	end

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
	for i = #points, #self.Segments do
		self.Segments[i].Visible = false
	end
end

return ChartRenderer
