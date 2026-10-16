--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local RunService = game:GetService("RunService")

local function remote(name: string): RemoteEvent
	if RunService:IsServer() then
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = script
		return event
	end
	return script:WaitForChild(name) :: RemoteEvent
end

return table.freeze({
	Move = remote("Move"),
	MoveDeny = remote("MoveDeny"),
	Dash = remote("Dash"),
	DashFx = remote("DashFx"),
})
