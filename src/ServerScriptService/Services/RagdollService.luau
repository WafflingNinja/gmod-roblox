--!strict
-- Player ragdolls: G toggles (stand up after a few seconds or on G again), dying always ragdolls.
-- Motor6Ds are disabled and replaced by limit-bound constraints at the same joints (RagdollJoints): ball sockets
-- with a twist axis along the limb, hinges for elbows and knees. The Root joint stays so the camera keeps following.
-- Parts get a heavier density, high friction and no bounce so bodies drop, slide and settle; neighbouring parts
-- ignore each other (their joint overlaps) while arms and legs still collide with the rest of the body.
-- The character is client-owned: every part is pinned to its player so a nearby second player can't take over a limb,
-- and the client switches its Humanoid into the Physics state when told (RagdollState) and back to GettingUp after.
-- Standing up lifts the body upright with the limbs still loose (RAGDOLL_RISE), then hands the joints back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local RagdollJoints = require(ReplicatedStorage.Shared.RagdollJoints)
local RateLimiter = require(script.Parent.RateLimiter)
local Sfx = require(script.Parent.Sfx)
local Validate = require(script.Parent.Validate)

local remotes = ReplicatedStorage.Remotes
local toggleRemote = remotes.RagdollToggle :: RemoteEvent
local stateRemote = remotes.RagdollState :: RemoteEvent

local ROOT_JOINTS = { Root = true, RootJoint = true }
local TORSO = { UpperTorso = true, LowerTorso = true, Torso = true }
local LIMB_AXIS = CFrame.Angles(0, 0, math.rad(90)) -- ball sockets twist around X; this turns X along the limb
local SHOVE_WINDOW = 0.5 -- seconds a bullet hit is remembered for a ragdoll that starts right after it
local SURFACE_WEIGHT = 50 -- friction/bounce of the body wins over the surface it lands on

type Original = { collide: boolean, physics: PhysicalProperties? }

type Ragdoll = {
	made: { Instance },
	lift: { Instance }, -- the stand-up forces, kept apart so dying mid-rise can drop them
	motors: { Motor6D },
	parts: { [BasePart]: Original }, -- restored on stand-up
	dead: boolean, -- dead ragdolls never stand up
	rising: boolean,
}

local ragdolls: { [Model]: Ragdoll } = {}
local lastShove: { [Model]: { part: BasePart, velocity: Vector3, at: number } } = {}
local limiter = RateLimiter.new(Config.RAGDOLL_BUCKET_CAPACITY, Config.RAGDOLL_REFILL_PER_SECOND)

local function destroyAll(instances: { Instance })
	for _, instance in instances do
		instance:Destroy()
	end
	table.clear(instances)
end

local function push(part: BasePart, velocity: Vector3)
	part:ApplyImpulse(velocity * part.AssemblyMass)
end

local function finish(player: Player, character: Model, ragdoll: Ragdoll)
	ragdolls[character] = nil
	destroyAll(ragdoll.lift)
	destroyAll(ragdoll.made)
	for _, motor in ragdoll.motors do
		motor.Enabled = true
	end
	for part, original in ragdoll.parts do
		local anyPart: any = part -- nil is valid for CustomPhysicalProperties (the material default); the type says it isn't
		anyPart.CanCollide = original.collide
		anyPart.CustomPhysicalProperties = original.physics
	end
	stateRemote:FireClient(player, false)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		Sfx.play("ragdoll_getup", root)
	end
end

-- Where the body stands: on the floor under the root, facing the way the chest or head points.
local function uprightPose(character: Model, root: BasePart, humanoid: Humanoid): CFrame?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(root.Position + Vector3.yAxis * 2, Vector3.new(0, -16, 0), params)
	if not hit then
		return nil
	end
	local chest = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or root
	local look = (chest :: BasePart).CFrame.LookVector
	local facing = Vector3.new(look.X, 0, look.Z)
	if math.abs(look.Y) > 0.7 then
		-- Lying on the back stands up facing the feet, lying on the front facing where the head points.
		local up = (chest :: BasePart).CFrame.UpVector
		facing = Vector3.new(up.X, 0, up.Z) * (if look.Y > 0 then -1 else 1)
	end
	if facing.Magnitude < 0.05 then
		facing = -Vector3.zAxis
	end
	local position =
		Vector3.new(root.Position.X, hit.Position.Y + humanoid.HipHeight + root.Size.Y / 2, root.Position.Z)
	return CFrame.lookAt(position, position + facing.Unit)
end

local function totalMass(character: Model): number
	local mass = 0
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			mass += part.Mass
		end
	end
	return mass
end

-- Pull the root up and upright. Only the root is driven; the loose limbs hang from it and the joints take over after.
local function lift(character: Model, root: BasePart, pose: CFrame, ragdoll: Ragdoll)
	local attachment = Instance.new("Attachment")
	attachment.Name = "RagdollRise"
	attachment.Parent = root
	local orientation = Instance.new("AlignOrientation")
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.Attachment0 = attachment
	orientation.CFrame = pose.Rotation
	orientation.RigidityEnabled = false
	orientation.MaxTorque = 1e6
	orientation.MaxAngularVelocity = 8
	orientation.Responsiveness = 30
	orientation.Parent = root
	local position = Instance.new("AlignPosition")
	position.Mode = Enum.PositionAlignmentMode.OneAttachment
	position.Attachment0 = attachment
	position.Position = pose.Position
	position.RigidityEnabled = false
	position.MaxForce = totalMass(character) * Workspace.Gravity * 3
	position.MaxVelocity = 10
	position.Responsiveness = 20
	position.Parent = root
	ragdoll.lift = { attachment, orientation, position }
end

local function standUp(player: Player, character: Model)
	local ragdoll = ragdolls[character]
	if not ragdoll or ragdoll.dead or ragdoll.rising then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local pose = if humanoid and root and root:IsA("BasePart") then uprightPose(character, root, humanoid) else nil
	if not pose then
		finish(player, character, ragdoll) -- no floor to stand on: hand the joints back where it lies
		return
	end
	ragdoll.rising = true
	lift(character, root :: BasePart, pose, ragdoll)
	task.delay(Config.RAGDOLL_RISE, function()
		if ragdolls[character] == ragdoll and not ragdoll.dead then
			finish(player, character, ragdoll)
		end
	end)
end

-- Heavier, grippy, dead-bounce body parts; remembers what to put back.
local function weigh(character: Model, ragdoll: Ragdoll)
	for _, part in character:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		ragdoll.parts[part] = { collide = part.CanCollide, physics = part.CustomPhysicalProperties }
		-- Limbs collide while floppy; the root box doesn't, or the body slides around on it.
		part.CanCollide = part.Name ~= "HumanoidRootPart"
		local density = if TORSO[part.Name] then Config.RAGDOLL_TORSO_DENSITY else Config.RAGDOLL_DENSITY
		part.CustomPhysicalProperties =
			PhysicalProperties.new(density, Config.RAGDOLL_FRICTION, 0, SURFACE_WEIGHT, SURFACE_WEIGHT)
	end
end

local function joint(motor: Motor6D, part0: BasePart, part1: BasePart, ragdoll: Ragdoll)
	local spec = RagdollJoints.of(motor.Name)
	local a0 = Instance.new("Attachment")
	local a1 = Instance.new("Attachment")
	local constraint: Constraint
	if spec.kind == "hinge" then
		a0.CFrame = motor.C0
		a1.CFrame = motor.C1
		local hinge = Instance.new("HingeConstraint")
		hinge.LimitsEnabled = true
		hinge.LowerAngle = spec.lower
		hinge.UpperAngle = spec.upper
		hinge.Restitution = 0
		constraint = hinge
	else
		a0.CFrame = motor.C0 * LIMB_AXIS
		a1.CFrame = motor.C1 * LIMB_AXIS
		local socket = Instance.new("BallSocketConstraint")
		socket.LimitsEnabled = true
		socket.UpperAngle = spec.cone
		socket.TwistLimitsEnabled = true
		socket.TwistLowerAngle = -spec.twist
		socket.TwistUpperAngle = spec.twist
		socket.Restitution = 0
		socket.MaxFrictionTorque = part1.Mass * Config.RAGDOLL_JOINT_FRICTION
		constraint = socket
	end
	a0.Parent = part0
	a1.Parent = part1
	local constraintAny = constraint :: any
	constraintAny.Attachment0 = a0
	constraintAny.Attachment1 = a1
	constraint.Parent = part1
	-- Neighbours overlap at the joint; without this they fight and jitter.
	local apart = Instance.new("NoCollisionConstraint")
	apart.Part0 = part0
	apart.Part1 = part1
	apart.Parent = part1
	table.insert(ragdoll.made, constraint)
	table.insert(ragdoll.made, apart)
	table.insert(ragdoll.made, a0)
	table.insert(ragdoll.made, a1)
	motor.Enabled = false
	table.insert(ragdoll.motors, motor)
end

-- Every limb simulates on its player's client. Left to "auto", a second player standing near would take over
-- some of the loose assemblies and the body would stutter on both screens.
local function pinToPlayer(player: Player, character: Model)
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") and part:CanSetNetworkOwnership() then
			part:SetNetworkOwner(player)
		end
	end
end

local function fall(player: Player, character: Model, dying: boolean)
	if ragdolls[character] then
		return
	end
	local ragdoll: Ragdoll = { made = {}, lift = {}, motors = {}, parts = {}, dead = dying, rising = false }
	weigh(character, ragdoll)
	for _, motor in character:GetDescendants() do
		if not motor:IsA("Motor6D") or ROOT_JOINTS[motor.Name] then
			continue
		end
		local part0, part1 = motor.Part0, motor.Part1
		if part0 and part1 then
			joint(motor, part0, part1, ragdoll)
		end
	end
	ragdolls[character] = ragdoll

	-- Push before the limbs are handed to the client; an impulse on an assembly the client owns gets overwritten.
	local shove = lastShove[character]
	lastShove[character] = nil
	if shove and os.clock() - shove.at < SHOVE_WINDOW then
		push(shove.part, shove.velocity)
	end
	pinToPlayer(player, character)
	if dying then
		return
	end
	stateRemote:FireClient(player, true)
	task.delay(Config.RAGDOLL_GETUP, function()
		if ragdolls[character] == ragdoll then
			standUp(player, character)
		end
	end)
end

local function watch(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.Died:Once(function()
		-- A toggled ragdoll is already floppy; it just stops getting up.
		local current = ragdolls[character]
		if current then
			current.dead = true
			destroyAll(current.lift)
		else
			fall(player, character, true)
		end
	end)
	character.Destroying:Once(function()
		ragdolls[character] = nil
		lastShove[character] = nil
	end)
end

local RagdollService = {}

-- A bullet hit `part` and should push it by `velocity` (studs/s) if that body is floppy now or goes floppy right
-- after (the shot that kills).
function RagdollService.shove(part: BasePart, velocity: Vector3)
	local character = part:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end
	if ragdolls[character] then
		push(part, velocity)
	elseif Players:GetPlayerFromCharacter(character) then
		lastShove[character] = { part = part, velocity = velocity, at = os.clock() }
	end
end

function RagdollService.init()
	toggleRemote.OnServerEvent:Connect(function(player: Player)
		if not limiter:consume(player, 1) then
			return
		end
		local character = player.Character
		if not character or not Validate.aliveRoot(player) then
			return
		end
		if ragdolls[character] then
			standUp(player, character)
		else
			fall(player, character, false)
		end
	end)

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			watch(player, character)
		end)
		if player.Character then
			task.spawn(watch, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			ragdolls[player.Character] = nil
			lastShove[player.Character] = nil
		end
	end)
end

return RagdollService
