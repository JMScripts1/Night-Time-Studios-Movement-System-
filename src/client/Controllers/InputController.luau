--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

export type Action = "Sprint" | "Crouch" | "Jump" | "Dash" | "VaultMid"

local SPRINT: Action = "Sprint"

-- above the default controls and sunk, so Space never jumps the humanoid
local PRIORITY = Enum.ContextActionPriority.High.Value

local BINDS: { [Action]: Enum.KeyCode } = {
	Crouch = Config.KEYS.CROUCH,
	Jump = Config.KEYS.JUMP,
	Dash = Config.KEYS.DASH,
	VaultMid = Config.KEYS.VAULT_MID,
}

-- first held key wins, so W and D together is a forward dash
local DASH_KEYS: { { key: Enum.KeyCode, dir: Types.DashDir } } = {
	{ key = Enum.KeyCode.W, dir = "F" },
	{ key = Enum.KeyCode.A, dir = "L" },
	{ key = Enum.KeyCode.S, dir = "B" },
	{ key = Enum.KeyCode.D, dir = "R" },
}

local InputController = {}

local held: { [Action]: boolean } = {}
local pressed: { [Action]: boolean } = {}
local lastTap = 0

function InputController.isDown(action: Action): boolean
	return held[action] == true
end

function InputController.take(action: Action): boolean
	local was = pressed[action] == true
	pressed[action] = nil
	return was
end

-- a press nothing took this step is dropped, not kept for later
function InputController.flush()
	table.clear(pressed)
end

function InputController.dashDir(): Types.DashDir
	for _, bind in DASH_KEYS do
		if UserInputService:IsKeyDown(bind.key) then
			return bind.dir
		end
	end
	return "B"
end

for action: Action, key in BINDS do
	ContextActionService:BindActionAtPriority(`Move{action}`, function(_, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin then
			held[action] = true
			pressed[action] = true
		else
			held[action] = nil
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, key)
end

-- the sprint key also walks, so it's watched without sinking it
UserInputService.InputBegan:Connect(function(input: InputObject, isProcessed: boolean)
	if isProcessed or input.KeyCode ~= Config.KEYS.SPRINT then
		return
	end
	local now = os.clock()
	if now - lastTap <= Config.DOUBLE_TAP then
		held[SPRINT] = true
	end
	lastTap = now
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Config.KEYS.SPRINT then
		held[SPRINT] = nil
	end
end)

-- a key let go while the window is unfocused never sends an End
UserInputService.WindowFocusReleased:Connect(function()
	table.clear(held)
end)

return InputController
