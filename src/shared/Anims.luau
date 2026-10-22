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
	Roll = true,
	LedgeLeap2 = true,
	AirDash = true,
	WallGrab = true,
}
for state in MoveDefs do
	SLOTS[state] = true
end

-- an empty id is a slot with no animation yet, it plays nothing
local Anims: { [Types.AnimName]: string } = {
	Idle = "rbxassetid://111253788104830",
	Walk = "rbxassetid://134520063601014",
	Run = "rbxassetid://84237278404758",
	Jump = "rbxassetid://91804113405885",
	Slide = "rbxassetid://131338188389559",
	SlideJump = "rbxassetid://87854361282454",
	CrouchIdle = "rbxassetid://118920925691918",
	CrouchWalk = "rbxassetid://126287311643867",
	WallRunLeft = "rbxassetid://74080959050186",
	WallRunRight = "rbxassetid://94263927972902",
	Fall = "rbxassetid://127049077162885",
	DoubleJump = "rbxassetid://81048300627588",
	WallCling = "rbxassetid://122183968429231",
	WallBoost = "rbxassetid://135795023642057",
	WallLeapLeft = "rbxassetid://133207858909587",
	WallLeapRight = "rbxassetid://71164723335647",
	Mantle = "rbxassetid://137171835971660",
	DashB = "rbxassetid://132820400906047",
	DashF = "rbxassetid://132385598213592",
	DashL = "rbxassetid://90778754431207",
	DashR = "rbxassetid://99540956567959",
	AirDash = "rbxassetid://98118360762129",
	Roll = "rbxassetid://120431676333500",
	LedgeLeap = "rbxassetid://90219606237010",
	LedgeLeap2 = "rbxassetid://120588070311007",
	WallGrab = "rbxassetid://117778559144458",
}

-- the old solver doesn't check keys in the table above, so a typo would just never play
for name: string in Anims do
	assert(SLOTS[name], `no state or slot called {name}`)
end

return table.freeze(Anims)
