--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Types = require(script.Parent.Types)

-- an empty id is a slot with no sound yet, it plays nothing
local Sounds: { [Types.SoundName]: string } = {
	Jump = "",
	DoubleJump = "",
	SlideJump = "",
	LedgeLeap = "",
	Dash = "",
	Land = "",
	Slide = "",
	WallRun = "",
	WallLeap = "",
	WallCling = "",
	WallBoost = "",
	Mantle = "",
}

return table.freeze(Sounds)
