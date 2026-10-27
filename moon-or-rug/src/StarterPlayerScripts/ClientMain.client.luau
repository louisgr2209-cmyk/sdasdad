-- ClientMain (LocalScript) – StarterPlayer/StarterPlayerScripts/ClientMain
-- Startet den Client. Der Client zeigt nur an, alle Entscheidungen trifft der Server.

local modules = script.Parent:WaitForChild("ClientModules")
local Screen = require(modules:WaitForChild("Screen"))
local DebugTerminal = require(modules:WaitForChild("DebugTerminal"))

Screen.Setup()
DebugTerminal.Start() -- Test-UI (Phase 1–2), wird in Phase 3 ersetzt
