--!strict
-- Player ragdolls: G toggles (stand up after a few seconds or on G again), dying always ragdolls.
-- Motor6Ds are disabled and replaced by limited BallSocketConstraints at the same joints; the Root joint stays
-- so the camera keeps following. The character is client-owned, so the client switches its Humanoid into the
-- Physics state when told (RagdollState) and back to GettingUp after.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RateLimiter = require(script.Parent.RateLimiter)
local Sfx = require(script.Parent.Sfx)
local Validate = require(script.Parent.Validate)

local remotes = ReplicatedStorage.Remotes
local toggleRemote = remotes.RagdollToggle :: RemoteEvent
local stateRemote = remotes.RagdollState :: RemoteEvent

local ROOT_JOINTS = { Root = true, RootJoint = true }

type Ragdoll = {
	made: { Instance },
	motors: { Motor6D },
	collisions: { [BasePart]: boolean }, -- original CanCollide, restored on stand-up
	dead: boolean, -- dead ragdolls never stand up
}

local ragdolls: { [Model]: Ragdoll } = {}
local limiter = RateLimiter.new(Config.RAGDOLL_BUCKET_CAPACITY, Config.RAGDOLL_REFILL_PER_SECOND)

local function standUp(player: Player, character: Model)
	local ragdoll = ragdolls[character]
	if not ragdoll or ragdoll.dead then
		return
	end
	ragdolls[character] = nil
	for _, instance in ragdoll.made do
		instance:Destroy()
	end
	for _, motor in ragdoll.motors do
		motor.Enabled = true
	end
	for part, canCollide in ragdoll.collisions do
		part.CanCollide = canCollide
	end
	stateRemote:FireClient(player, false)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		Sfx.play("ragdoll_getup", root)
	end
end

local function fall(player: Player, character: Model, dying: boolean)
	if ragdolls[character] then
		return
	end
	local ragdoll: Ragdoll = { made = {}, motors = {}, collisions = {}, dead = dying }
	for _, motor in character:GetDescendants() do
		if not motor:IsA("Motor6D") or ROOT_JOINTS[motor.Name] then
			continue
		end
		local part0, part1 = motor.Part0, motor.Part1
		if not part0 or not part1 then
			continue
		end
		local a0 = Instance.new("Attachment")
		a0.CFrame = motor.C0
		a0.Parent = part0
		local a1 = Instance.new("Attachment")
		a1.CFrame = motor.C1
		a1.Parent = part1
		local socket = Instance.new("BallSocketConstraint")
		socket.Attachment0 = a0
		socket.Attachment1 = a1
		socket.LimitsEnabled = true
		socket.UpperAngle = 50
		socket.TwistLimitsEnabled = true
		socket.TwistLowerAngle = -45
		socket.TwistUpperAngle = 45
		socket.Parent = part1
		table.insert(ragdoll.made, socket)
		table.insert(ragdoll.made, a0)
		table.insert(ragdoll.made, a1)
		motor.Enabled = false
		table.insert(ragdoll.motors, motor)
	end
	-- Limbs collide while floppy; the root box doesn't, or the body slides around on it.
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") then
			ragdoll.collisions[part] = part.CanCollide
			part.CanCollide = part.Name ~= "HumanoidRootPart"
		end
	end
	ragdolls[character] = ragdoll
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
		else
			fall(player, character, true)
		end
	end)
	character.Destroying:Once(function()
		ragdolls[character] = nil
	end)
end

local RagdollService = {}

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
		end
	end)
end

return RagdollService
