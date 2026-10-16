--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local MoveDefs = require(script.Parent.MoveDefs)
local Types = require(script.Parent.Types)

local SLOTS: { [string]: true } = {
	WallRunLeft = true,
	WallRunRight = true,
	WallLeapLeft = true,
	WallLeapRight = true,
	DashF = true,
	DashB = true,
	DashL = true,
	DashR = true,
}
for state in MoveDefs do
	SLOTS[state] = true
end

local Anims: { [Types.AnimName]: string } = {
	Idle = "rbxassetid://135449190200569",
	Walk = "rbxassetid://92621759199829",
	Run = "rbxassetid://97365671049008",
	Jump = "rbxassetid://91804113405885",
	Slide = "rbxassetid://131338188389559",
	SlideJump = "rbxassetid://94777797533254",
	CrouchIdle = "rbxassetid://118920925691918",
	CrouchWalk = "rbxassetid://126287311643867",
	WallRunLeft = "rbxassetid://74080959050186",
	WallRunRight = "rbxassetid://94263927972902",
	Fall = "rbxassetid://127049077162885",
	DoubleJump = "rbxassetid://84083501909606",
	WallCling = "rbxassetid://130191404882056",
	WallBoost = "rbxassetid://113668530383382",
	WallLeapLeft = "rbxassetid://133207858909587",
	WallLeapRight = "rbxassetid://71164723335647",
	VaultLow = "rbxassetid://86455447340825",
	DashB = "rbxassetid://131828121072220",
	DashF = "rbxassetid://132385598213592",
	DashL = "rbxassetid://90778754431207",
	DashR = "rbxassetid://99540956567959",
}

-- the old solver doesn't check keys in the table above, so a typo would just never play
for name: string in Anims do
	assert(SLOTS[name], `no state or slot called {name}`)
end

return table.freeze(Anims)
