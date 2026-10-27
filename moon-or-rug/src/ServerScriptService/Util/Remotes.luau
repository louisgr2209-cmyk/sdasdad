-- Remotes (ModuleScript) – ServerScriptService/Util/Remotes
-- Legt alle RemoteEvents/RemoteFunctions automatisch in ReplicatedStorage/Remotes an.
-- Du musst in Studio also KEINE Remotes von Hand erstellen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:FindFirstChild("Remotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
end

local Remotes = {}

local function get(className: string, name: string): Instance
	local remote = folder:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
	end
	return remote
end

function Remotes.Event(name: string): RemoteEvent
	return get("RemoteEvent", name) :: RemoteEvent
end

function Remotes.Function(name: string): RemoteFunction
	return get("RemoteFunction", name) :: RemoteFunction
end

return Remotes
