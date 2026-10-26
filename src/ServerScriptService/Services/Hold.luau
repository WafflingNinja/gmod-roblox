--!strict
-- Shared hold for the physgun and gravity gun. The client says where to hold; the server owns the physics.
-- A held prop is pulled toward an anchored target part by Align constraints, so speed is capped
-- no matter what the client sends, and the prop is server-owned while held.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local RateLimiter = require(script.Parent.RateLimiter)
local Sfx = require(script.Parent.Sfx)
local Validate = require(script.Parent.Validate)

local aimRemote = ReplicatedStorage.Remotes.PhysgunAim :: UnreliableRemoteEvent
local targetsFolder = Workspace.PhysgunTargets :: Folder

type HoldState = {
	prop: BasePart,
	target: Part,
	maxDistance: number, -- target clamp, studs from the character
	parts: { Instance }, -- constraints, attachments, beam: destroyed on release
	connections: { RBXScriptConnection },
}

local holds: { [Player]: HoldState } = {}
local aimLimiter = RateLimiter.new(Config.AIM_BUCKET_CAPACITY, Config.AIM_REFILL_PER_SECOND)

local Hold = {}

function Hold.get(player: Player): BasePart?
	local hold = holds[player]
	return hold and hold.prop
end

function Hold.isHeld(prop: BasePart): boolean
	for _, hold in holds do
		if hold.prop == prop then
			return true
		end
	end
	return false
end

function Hold.release(player: Player)
	local hold = holds[player]
	if not hold then
		return
	end
	holds[player] = nil
	for _, connection in hold.connections do
		connection:Disconnect()
	end
	for _, instance in hold.parts do
		instance:Destroy()
	end
	hold.target:Destroy()
	if hold.prop.Parent then
		Sfx.play("physgun_release", hold.prop)
	end
	if hold.prop.Parent and not hold.prop.Anchored then
		pcall(function()
			hold.prop:SetNetworkOwnershipAuto()
		end)
	end
end

-- `hum` is the Sounds name of the loop played while held.
function Hold.start(player: Player, prop: BasePart, tool: Tool, beamColor: Color3, maxDistance: number, hum: string)
	prop.Anchored = false
	pcall(function()
		prop:SetNetworkOwner(nil)
	end)

	local target = Instance.new("Part")
	target.Name = tostring(player.UserId)
	target.Anchored = true
	target.CanCollide = false
	target.CanQuery = false
	target.CanTouch = false
	target.Transparency = 1
	target.Size = Vector3.one * 0.2
	target.CFrame = prop.CFrame

	local targetAttachment = Instance.new("Attachment")
	targetAttachment.Parent = target
	local holdAttachment = Instance.new("Attachment")
	holdAttachment.Name = "PhysgunHold"
	holdAttachment.Parent = prop

	local position = Instance.new("AlignPosition")
	position.Mode = Enum.PositionAlignmentMode.TwoAttachment
	position.Attachment0 = holdAttachment
	position.Attachment1 = targetAttachment
	position.RigidityEnabled = false
	position.ApplyAtCenterOfMass = true
	position.MaxForce = math.huge
	position.MaxVelocity = Config.GRAB_MAX_SPEED
	position.Responsiveness = 40
	position.Parent = prop

	local orientation = Instance.new("AlignOrientation")
	orientation.Mode = Enum.OrientationAlignmentMode.TwoAttachment
	orientation.Attachment0 = holdAttachment
	orientation.Attachment1 = targetAttachment
	orientation.RigidityEnabled = false
	orientation.MaxTorque = math.huge
	orientation.MaxAngularVelocity = 20
	orientation.Responsiveness = 25
	orientation.Parent = prop

	local parts: { Instance } = { holdAttachment, position, orientation }
	local humSound = Sfx.loop(hum, holdAttachment)
	if humSound then
		table.insert(parts, humSound)
	end
	local handle = tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		local beam = Instance.new("Beam")
		beam.Attachment0 = muzzle
		beam.Attachment1 = holdAttachment
		beam.Color = ColorSequence.new(beamColor)
		beam.Width0 = 0.18
		beam.Width1 = 0.18
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Parent = holdAttachment
		table.insert(parts, beam)
	end

	local connections: { RBXScriptConnection } = {
		tool.Unequipped:Connect(function()
			Hold.release(player)
		end),
		prop.Destroying:Connect(function()
			Hold.release(player)
		end),
	}
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(
			connections,
			humanoid.Died:Connect(function()
				Hold.release(player)
			end)
		)
	end

	target.Parent = targetsFolder
	holds[player] = {
		prop = prop,
		target = target,
		maxDistance = maxDistance,
		parts = parts,
		connections = connections,
	}
end

function Hold.init()
	aimRemote.OnServerEvent:Connect(function(player: Player, aim: unknown)
		local hold = holds[player]
		if not hold or not aimLimiter:consume(player, 1) then
			return
		end
		if typeof(aim) ~= "CFrame" or not Validate.isFiniteCFrame(aim) then
			return
		end
		local root = Validate.aliveRoot(player)
		if not root then
			return
		end
		local offset = aim.Position - root.Position
		local position = aim.Position
		if offset.Magnitude > hold.maxDistance then
			position = root.Position + offset.Unit * hold.maxDistance
		end
		hold.target.CFrame = CFrame.new(position) * aim.Rotation:Orthonormalize()
	end)

	Players.PlayerRemoving:Connect(Hold.release)
end

return Hold
