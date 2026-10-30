-- Screen (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/Screen
-- Basis für ALLE Bildschirme:
--  * dunkler Hintergrund füllt den ganzen Bildschirm (auch hinter Notch/Dynamic Island)
--  * Inhalt liegt nur im sicheren Bereich (keine Notch, Dynamic Island, Kamera-Loch,
--    abgerundete Ecken, Roblox-Leiste oben)
--  * Layout wird für 1000 x 520 gebaut und auf jede Größe skaliert (iPhone bis PC)

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SoundFx = require(script.Parent.SoundFx)

local Screen = {}

local currentScale = 1

Screen.Colors = {
	Background = Color3.fromRGB(10, 12, 17),
	Panel = Color3.fromRGB(19, 22, 30),
	PanelLight = Color3.fromRGB(28, 32, 43),
	Border = Color3.fromRGB(40, 45, 58),
	Text = Color3.fromRGB(232, 236, 244),
	Muted = Color3.fromRGB(140, 148, 166),
	Green = Color3.fromRGB(34, 197, 94),
	Red = Color3.fromRGB(239, 68, 68),
	Accent = Color3.fromRGB(250, 204, 21),
}

Screen.Fonts = {
	Regular = Enum.Font.BuilderSans,
	Medium = Enum.Font.BuilderSansMedium,
	Bold = Enum.Font.BuilderSansBold,
}

-- Instanz mit Eigenschaften und Kindern bauen
function Screen.New(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local target: any = instance
	local parent
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			target[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	instance.Parent = parent
	return instance
end

function Screen.Corner(radius: number?): UICorner
	return Screen.New("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

function Screen.Padding(px: number): UIPadding
	return Screen.New("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

-- Textfeld mit Standardwerten (TextSize in Design-Pixeln, min. 20 für Handy)
function Screen.Label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Screen.Fonts.Medium,
		TextColor3 = Screen.Colors.Text,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for key, value in props do
		defaults[key] = value
	end
	return Screen.New("TextLabel", defaults)
end

-- Großer Button (Handy: min. 72 Design-Pixel hoch ≈ 44 pt auf dem kleinsten iPhone)
function Screen.Button(props: { [string]: any }): TextButton
	local defaults = {
		AutoButtonColor = true,
		BorderSizePixel = 0,
		Font = Screen.Fonts.Bold,
		TextColor3 = Screen.Colors.Text,
		TextSize = 26,
		BackgroundColor3 = Screen.Colors.PanelLight,
	}
	for key, value in props do
		defaults[key] = value
	end
	local button = Screen.New("TextButton", defaults)
	Screen.Corner(10).Parent = button
	button.Activated:Connect(function()
		SoundFx.Play("Click") -- dezenter Klick (abschaltbar)
	end)
	return button
end

-- Senkrechte Scroll-Liste (Höhe wächst automatisch mit dem Inhalt)
function Screen.Scroller(props: { [string]: any }): ScrollingFrame
	local defaults = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Screen.Colors.Border,
	}
	for key, value in props do
		defaults[key] = value
	end
	local scroller = Screen.New("ScrollingFrame", defaults)
	Screen.New("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroller,
	})
	return scroller
end

-- Aktueller Skalierungsfaktor (Bildschirm-Pixel pro Design-Pixel)
function Screen.GetScale(): number
	return currentScale
end

-- Roblox-Standard-UI ausblenden, die im Terminal stört
function Screen.Setup()
	for _, coreType in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.EmotesMenu } do
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, coreType, false)
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
end

-- Erstellt einen Vollbild-Bildschirm. Gibt "root" zurück: dort alles hineinbauen.
-- root ist in Design-Pixeln mind. ca. 1000 x 520 groß (je nach Seitenverhältnis mehr).
function Screen.CreateRoot(name: string): Frame
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local ui = Config.UI

	-- 1) Hintergrund: ganzer Bildschirm, auch hinter Notch und Roblox-Leiste
	Screen.New("ScreenGui", {
		Name = name .. "Background",
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		ResetOnSpawn = false,
		DisplayOrder = 0,
		Parent = playerGui,
	}, {
		Screen.New("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Screen.Colors.Background,
			BorderSizePixel = 0,
		}),
	})

	-- 2) Inhalt: nur im sicheren Bereich (Notch, Dynamic Island, Roblox-Leiste frei)
	local gui = Screen.New("ScreenGui", {
		Name = name,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ClipToDeviceSafeArea = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1,
		Parent = playerGui,
	})
	local holder = Screen.New("Frame", {
		Name = "SafeArea",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local root = Screen.New("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Parent = holder,
	})
	local scale = Screen.New("UIScale", { Parent = root })

	-- 3) Skalieren: kleinere Seite bestimmt den Faktor, root füllt den sicheren Bereich genau
	local function update()
		local size = holder.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local factor = math.min(size.X / ui.DesignWidth, size.Y / ui.DesignHeight)
		factor = math.clamp(factor, ui.MinScale, ui.MaxScale)
		scale.Scale = factor
		currentScale = factor
		root.Size = UDim2.fromOffset(size.X / factor, size.Y / factor)
	end
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()

	return root
end

return Screen
