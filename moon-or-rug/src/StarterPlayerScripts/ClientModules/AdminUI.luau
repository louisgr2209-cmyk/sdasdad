-- AdminUI (ModuleScript) – StarterPlayer/StarterPlayerScripts/ClientModules/AdminUI
-- Admin-Fenster für das Creator-Programm: Roblox-Name, Video-Link (nur Admins sehen ihn), Stufe wählen,
-- GRANT / REVOKE, letzte 10 Aktionen. Nur sichtbar für Admins – der Server prüft trotzdem jede Anfrage.
--
-- Platz: Fenster 85 % breit, 484 hoch (passt in die kleinste Höhe von 496)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Screen = require(script.Parent.Screen)
local MarketClient = require(script.Parent.MarketClient)

local Colors = Screen.Colors
local TIERS = Config.Creator.Tiers

local AdminUI = {}

function AdminUI.new(parent: GuiObject)
	local self = {}
	local tier = 1

	local overlay = Screen.New("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Background,
		BackgroundTransparency = 0.3,
		Visible = false,
		ZIndex = 40,
		Parent = parent,
	})
	local panel = Screen.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.85, 0, 0, 484),
		BackgroundColor3 = Colors.Panel,
		Active = true,
		ZIndex = 41,
		Parent = overlay,
	}, {
		Screen.Corner(14),
		Screen.Padding(16),
		Screen.New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local function row(order: number, height: number)
		return Screen.New("Frame", {
			Size = UDim2.new(1, 0, 0, height),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			ZIndex = 42,
			Parent = panel,
		}, {
			Screen.New("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
	end

	local function textBox(placeholder: string, maxLength: number, size: UDim2, order: number, parentFrame)
		local box = Screen.New("TextBox", {
			PlaceholderText = placeholder,
			Text = "",
			ClearTextOnFocus = false,
			Font = Screen.Fonts.Medium,
			TextSize = 22,
			TextColor3 = Colors.Text,
			PlaceholderColor3 = Colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			BackgroundColor3 = Colors.PanelLight,
			Size = size,
			LayoutOrder = order,
			ZIndex = 42,
			Parent = parentFrame,
		}, {
			Screen.Corner(10),
			Screen.New("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
		})
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if #box.Text > maxLength then
				box.Text = string.sub(box.Text, 1, maxLength)
			end
		end)
		return box
	end

	Screen.Label({
		Text = "🛠 ADMIN · CREATORS",
		Font = Screen.Fonts.Bold,
		TextSize = 28,
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 1,
		ZIndex = 42,
		Parent = panel,
	})

	local inputRow = row(2, 56)
	local nameBox = textBox("Roblox name", 20, UDim2.new(0.4, -4, 1, 0), 1, inputRow)
	local videoBox = textBox("Video link (only admins see it)", 200, UDim2.new(0.6, -4, 1, 0), 2, inputRow)

	local tierRow = row(3, 72)
	local tierButtons = {}
	for i, info in TIERS do
		local button = Screen.Button({
			Text = info.Name,
			TextSize = 22,
			Size = UDim2.new(0.25, -6, 1, 0),
			LayoutOrder = i,
			ZIndex = 43,
			Parent = tierRow,
		})
		button.Activated:Connect(function()
			tier = i
			self.Refresh()
		end)
		tierButtons[i] = button
	end

	local actionRow = row(4, 72)
	local grantButton = Screen.Button({
		Text = "GRANT",
		BackgroundColor3 = Colors.Green,
		Size = UDim2.new(0, 200, 1, 0),
		LayoutOrder = 1,
		ZIndex = 43,
		Parent = actionRow,
	})
	local revokeButton = Screen.Button({
		Text = "REVOKE",
		BackgroundColor3 = Colors.Red,
		Size = UDim2.new(0, 200, 1, 0),
		LayoutOrder = 2,
		ZIndex = 43,
		Parent = actionRow,
	})
	local closeButton = Screen.Button({
		Text = "CLOSE",
		Size = UDim2.new(0, 160, 1, 0),
		LayoutOrder = 3,
		ZIndex = 43,
		Parent = actionRow,
	})

	local status = Screen.Label({
		Text = "",
		TextSize = 20,
		TextColor3 = Colors.Muted,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 5,
		ZIndex = 42,
		Parent = panel,
	})

	-- Letzte 10 Aktionen
	local logList = Screen.Scroller({
		Size = UDim2.new(1, 0, 0, 140),
		LayoutOrder = 6,
		ZIndex = 42,
		Parent = panel,
	})
	local logRows = {}

	local function showLog(log)
		for _, label in logRows do
			label:Destroy()
		end
		logRows = {}
		if type(log) ~= "table" or #log == 0 then
			table.insert(
				logRows,
				Screen.Label({
					Text = "No actions yet.",
					TextSize = 20,
					TextColor3 = Colors.Muted,
					Size = UDim2.new(1, -10, 0, 24),
					ZIndex = 43,
					Parent = logList,
				})
			)
			return
		end
		for i, entry in log do
			local when = os.date("%d.%m. %H:%M", math.floor(entry.At or 0))
			local text = string.format(
				"%s · %s %s %s%s · by %s",
				when,
				string.upper(entry.Act or "?"),
				entry.T or "?",
				if entry.Act == "grant" then "→ " .. (entry.Tier or "?") else "",
				if entry.V and entry.V ~= "" then " · " .. entry.V else "",
				entry.A or "?"
			)
			table.insert(
				logRows,
				Screen.Label({
					Text = text,
					TextSize = 20,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Size = UDim2.new(1, -10, 0, 24),
					LayoutOrder = i,
					ZIndex = 43,
					Parent = logList,
				})
			)
		end
	end

	function self.Refresh()
		for i, button in tierButtons do
			button.BackgroundColor3 = if i == tier then Colors.Accent else Colors.PanelLight
		end
	end

	local function hide()
		overlay.Visible = false
	end

	function self.Show()
		self.Refresh()
		overlay.Visible = true
		status.Text = "Loading log…"
		task.spawn(function()
			local log = MarketClient.AdminLog()
			status.Text = if log then "" else "Not allowed"
			showLog(log)
		end)
	end

	-- Doppelklick-Schutz: bis zur Antwort (max. 10 Sek.) gesperrt
	local waiting = false
	local function send(action: string)
		if waiting then
			return
		end
		local name = string.gsub(nameBox.Text, "%s", "")
		if #name < 3 then
			status.Text = "❌ Enter a Roblox name"
			status.TextColor3 = Colors.Red
			return
		end
		waiting = true
		status.Text = "Saving…"
		status.TextColor3 = Colors.Muted
		MarketClient.AdminAction(action, name, if action == "grant" then tier else nil, videoBox.Text)
		task.delay(10, function()
			waiting = false
		end)
	end

	MarketClient.AdminResult.Event:Connect(function(result)
		waiting = false
		status.Text = (if result.Ok then "✅ " else "❌ ") .. tostring(result.Message)
		status.TextColor3 = if result.Ok then Colors.Green else Colors.Red
		showLog(result.Log)
		if result.Ok then
			nameBox.Text, videoBox.Text = "", ""
		end
	end)

	grantButton.Activated:Connect(function()
		send("grant")
	end)
	revokeButton.Activated:Connect(function()
		send("revoke")
	end)
	closeButton.Activated:Connect(hide)
	overlay.Activated:Connect(hide)

	return self
end

return AdminUI
