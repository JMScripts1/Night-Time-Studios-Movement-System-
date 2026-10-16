--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Probes = require(ReplicatedStorage.Shared.Probes)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Parent.Context)
local InputController = require(script.Parent.Parent.Parent.InputController)
local Air = require(script.Parent.Air)

type Ctx = Context.Ctx

local SLIDE_DOWN = Vector3.new(0, -Config.CLING_SLIDE_SPEED, 0)

local WallCling = {}

local function findLedge(c: Ctx): boolean
	if not Context.isReady(c, "VaultMid") then
		return false
	end
	local hit = Probes.vaultMid(c.root)
	if not hit then
		return false
	end
	c.vault = hit
	return true
end

function WallCling.enter(c: Ctx)
	local wall = c.wall :: Types.WallHit
	Context.face(c, -wall.normal)

	if c.state == "WallCling" then
		c.momentum = 0
		c.heading = Vector3.zero
		Context.drive(c, SLIDE_DOWN)
		return
	end

	Context.glide(c, Vector3.zero)
	Air.launch(c, Config.BOOST_UP)
end

function WallCling.update(c: Ctx): Types.MoveState?
	local landed: Types.MoveState? = Air.land(c)
	if landed then
		return landed
	elseif InputController.take("VaultMid") and findLedge(c) then
		return "VaultMid"
	end
	local elapsed = os.clock() - c.since

	if c.state == "WallCling" then
		if InputController.take("Jump") then
			return "WallBoost"
		elseif elapsed >= Config.CLING_MAX_TIME or not Probes.wall(c.root, math.huge) then
			return "Fall"
		end
		return nil
	end

	if InputController.take("Jump") then
		local wall: Types.MoveState? = Air.wall(c)
		if wall then
			return wall
		end
	end

	-- only once over the top, pushing in any earlier pins us to the wall and friction kills the climb
	local inward = -(c.wall :: Types.WallHit).normal
	if Probes.isOverLip(c.root, inward) then
		Context.glide(c, inward * Config.BOOST_IN)
	end
	return if elapsed >= Config.BOOST_TIME then "Fall" else nil
end

WallCling.exit = Context.release

return WallCling
