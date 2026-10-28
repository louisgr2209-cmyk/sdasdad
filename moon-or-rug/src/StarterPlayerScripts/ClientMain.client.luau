-- ClientMain (LocalScript) – StarterPlayer/StarterPlayerScripts/ClientMain
-- Startet den Client. Der Client zeigt nur an, alle Entscheidungen trifft der Server.

local modules = script.Parent:WaitForChild("ClientModules")
local Screen = require(modules:WaitForChild("Screen"))
local TerminalUI = require(modules:WaitForChild("TerminalUI"))

Screen.Setup()
TerminalUI.Start()
