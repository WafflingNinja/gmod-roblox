--!strict
-- Guns. The client sends only "I fired this gun, this way"; the server checks the gun is equipped, the fire rate
-- and the magazine, then raycasts from its own copy of the shooter's head and adds spread (or launches the rocket).
-- The claimed origin is ignored, so third-person aim and a spoofed camera position cannot move the shot.
-- Ammo lives in the Tool's Ammo attribute (server-set, replicated to the HUD).
-- Props only take impulses from their owner's guns; players only take damage when both sides have PvP on.
-- NPCs take damage from anyone.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local WeaponCatalog = require(ReplicatedStorage.Shared.WeaponCatalog)
local GravityGunService = require(script.Parent.GravityGunService)
local Ownership = require(script.Parent.Ownership)
local RagdollService = require(script.Parent.RagdollService)
local RateLimiter = require(script.Parent.RateLimiter)
local Sfx = require(script.Parent.Sfx)
local Validate = require(script.Parent.Validate)

local RPM_TOLERANCE = 0.85 -- accept shots slightly early (network jitter)
local MAX_IMPULSE_SPEED = 160 -- studs/s one hit can add to a prop (rockets hit hardest)
local NPC_SPREAD = 3 -- NPC shots spread this many times the gun's own spread
local GAS_CAN = "gas_can" -- PropCatalog id; blows up when its owner shoots it or blasts it
local GAS_BLAST = { radius = 14, damage = 60, impulse = 140 }
local CHAIN_DELAY = 0.15 -- seconds between gas cans setting each other off

type Rocket = {
	owner: Player,
	def: WeaponCatalog.WeaponDef,
	part: BasePart,
	velocity: Vector3,
	expires: number,
}

local remotes = ReplicatedStorage.Remotes
local fireRemote = remotes.WeaponFire :: RemoteEvent
local reloadRemote = remotes.WeaponReload :: RemoteEvent
local pvpRemote = remotes.SetPvp :: RemoteEvent
local fxRemote = remotes.WeaponFx :: UnreliableRemoteEvent

local fireLimiter = RateLimiter.new(Config.FIRE_BUCKET_CAPACITY, Config.FIRE_REFILL_PER_SECOND)
local reloadLimiter = RateLimiter.new(Config.RELOAD_BUCKET_CAPACITY, Config.RELOAD_REFILL_PER_SECOND)
local pvpLimiter = RateLimiter.new(Config.PVP_BUCKET_CAPACITY, Config.PVP_REFILL_PER_SECOND)

local lastShot: { [Player]: number } = {}
local rockets: { Rocket } = {}

local function pvp(player: Player): boolean
	return player:GetAttribute(Config.PVP_ATTRIBUTE) == true
end

local function headOf(player: Player): BasePart?
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	return if head and head:IsA("BasePart") then head else nil
end

-- Random direction within `degrees` of `direction`.
local function spread(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction
	end
	local angle = math.rad(degrees) * math.sqrt(math.random())
	local roll = math.random() * 2 * math.pi
	return (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)).LookVector
end

local function propOf(instance: Instance): BasePart?
	local props = Workspace:FindFirstChild("Props")
	local node: Instance? = instance
	while node and node.Parent ~= props do
		node = node.Parent
	end
	return if node and node:IsA("BasePart") then node else nil
end

-- Push `instance`'s prop if `shooter` owns it, adding at most MAX_IMPULSE_SPEED.
local function push(shooter: Player, instance: Instance, direction: Vector3, speed: number)
	local prop = propOf(instance)
	if not prop or prop.Anchored or not Ownership.isOwner(shooter, prop) then
		return
	end
	GravityGunService.kick(prop, direction.Unit * math.min(speed, MAX_IMPULSE_SPEED))
end

-- `shooter` nil = an NPC fired; it hurts players who have PvP on. `direction` is where the hit pushes.
local function hurt(shooter: Player?, instance: Instance, amount: number, direction: Vector3)
	local character = instance:FindFirstAncestorOfClass("Model")
	local victim = character and Players:GetPlayerFromCharacter(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and character and CollectionService:HasTag(character, Config.NPC_TAG) then
		if shooter then
			character:SetAttribute(Config.NPC_ATTACKER_ATTRIBUTE, shooter.UserId) -- an armed NPC shoots back at them
		end
		humanoid:TakeDamage(amount) -- NPCs are fair game, PvP or not
		return
	end
	if victim and humanoid and victim ~= shooter and (shooter == nil or pvp(shooter)) and pvp(victim) then
		humanoid:TakeDamage(amount)
		if instance:IsA("BasePart") then
			RagdollService.shove(instance, direction.Unit * Config.RAGDOLL_SHOT_SPEED)
		end
	end
end

type Blast = { radius: number, damage: number, impulse: number }

local detonate: (owner: Player, can: BasePart) -> ()

-- Explosion at `position`: pushes the owner's props, hurts by the usual rules, sets off the owner's gas cans.
local function blast(owner: Player, position: Vector3, b: Blast, ignore: Instance?)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = b.radius
	explosion.BlastPressure = 0 -- the engine's own push and joint breaking stay off; we apply ours below
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = Workspace
	Sfx.playAt("explosion", position)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if ignore then { ignore } else {}
	local hitHumanoids: { [Humanoid]: boolean } = {}
	for _, part in Workspace:GetPartBoundsInRadius(position, b.radius, params) do
		local offset = part.Position - position
		local falloff = 1 - math.clamp(offset.Magnitude / b.radius, 0, 1)
		local away = if offset.Magnitude > 0.1 then offset.Unit else Vector3.yAxis
		push(owner, part, away + Vector3.yAxis * 0.5, b.impulse * falloff)
		local humanoid = part.Parent and part.Parent:FindFirstChildOfClass("Humanoid")
		if humanoid and not hitHumanoids[humanoid] then
			hitHumanoids[humanoid] = true
			hurt(owner, part, b.damage * falloff, away + Vector3.yAxis * 0.5)
		end
		local prop = propOf(part)
		if prop and prop == part and prop.Name == GAS_CAN and Ownership.isOwner(owner, prop) then
			task.delay(CHAIN_DELAY, detonate, owner, prop)
		end
	end
end

function detonate(owner: Player, can: BasePart)
	if not can.Parent or can:GetAttribute("Detonated") then
		return
	end
	can:SetAttribute("Detonated", true)
	local position = can.Position
	can:Destroy()
	blast(owner, position, GAS_BLAST, nil)
end

-- A bullet hit: an own gas can goes up.
local function shotGasCan(shooter: Player, instance: Instance)
	local prop = propOf(instance)
	if prop and prop.Name == GAS_CAN and Ownership.isOwner(shooter, prop) then
		detonate(shooter, prop)
	end
end

local function explode(rocket: Rocket, position: Vector3)
	local r = rocket.def.rocket :: WeaponCatalog.Rocket
	blast(rocket.owner, position, r, rocket.part)
	rocket.part:Destroy()
end

local function launch(player: Player, def: WeaponCatalog.WeaponDef, origin: Vector3, direction: Vector3)
	local count = 0
	for _, rocket in rockets do
		if rocket.owner == player then
			count += 1
		end
	end
	if count >= Config.ROCKET_CAP then
		return
	end
	local r = def.rocket :: WeaponCatalog.Rocket
	local part: BasePart = Instance.new("Part")
	part.Name = "Rocket"
	part.Size = Vector3.new(0.4, 0.4, 1.6)
	part.Color = Color3.fromRGB(70, 74, 60)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.lookAt(origin, origin + direction)
	local trail = Instance.new("Fire")
	trail.Size = 2
	trail.Heat = 0
	trail.Parent = part
	part.Parent = Workspace
	table.insert(rockets, {
		owner = player,
		def = def,
		part = part,
		velocity = direction * r.speed,
		expires = os.clock() + r.lifetime,
	})
end

local rocketParams = RaycastParams.new()
rocketParams.FilterType = Enum.RaycastFilterType.Exclude

-- One Heartbeat moves every rocket and sweeps a ray along its step.
local function stepRockets(dt: number)
	local now = os.clock()
	for i = #rockets, 1, -1 do
		local rocket = rockets[i]
		local from = rocket.part.Position
		local step = rocket.velocity * dt
		local ignore: { Instance } = { rocket.part }
		local character = rocket.owner.Character
		if character then
			table.insert(ignore, character)
		end
		rocketParams.FilterDescendantsInstances = ignore
		local hit = Workspace:Raycast(from, step, rocketParams)
		if hit or now > rocket.expires or not rocket.owner.Parent then
			table.remove(rockets, i)
			explode(rocket, if hit then hit.Position else from)
		else
			rocket.part.CFrame = CFrame.lookAt(from + step, from + step * 2)
		end
	end
end

local function reload(player: Player, tool: Tool, def: WeaponCatalog.WeaponDef)
	if tool:GetAttribute(Config.RELOADING_ATTRIBUTE) or tool:GetAttribute(Config.AMMO_ATTRIBUTE) == def.magazine then
		return
	end
	tool:SetAttribute(Config.RELOADING_ATTRIBUTE, true)
	local handle = tool:FindFirstChild("Handle")
	if handle then
		Sfx.play("reload", handle)
	end
	task.delay(def.reload, function()
		-- Unequipping cancels: the tool left the character, the magazine stays as it was.
		if tool.Parent == player.Character then
			tool:SetAttribute(Config.AMMO_ATTRIBUTE, def.magazine)
		end
		tool:SetAttribute(Config.RELOADING_ATTRIBUTE, nil)
	end)
end

local function fire(player: Player, id: unknown, origin: unknown, direction: unknown)
	if not fireLimiter:consume(player, 1) then
		return
	end
	if typeof(id) ~= "string" or typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	local def = WeaponCatalog.byId[id]
	if not def or not Validate.isFiniteVector(direction) then
		return
	end
	if direction.Magnitude < 0.9 or direction.Magnitude > 1.1 then
		return
	end
	local tool = Validate.equippedTool(player, def.id)
	local head = headOf(player)
	if not tool or not head or not Validate.aliveRoot(player) then
		return
	end
	local now = os.clock()
	if now - (lastShot[player] or 0) < 60 / def.rpm * RPM_TOLERANCE then
		return
	end
	local ammo = tool:GetAttribute(Config.AMMO_ATTRIBUTE)
	if tool:GetAttribute(Config.RELOADING_ATTRIBUTE) or typeof(ammo) ~= "number" then
		return
	end
	local handle = tool:FindFirstChild("Handle")
	if ammo <= 0 then
		reload(player, tool, def)
		return
	end
	lastShot[player] = now
	tool:SetAttribute(Config.AMMO_ATTRIBUTE, ammo - 1)
	if handle then
		Sfx.play(def.sound, handle)
	end

	local aim = direction.Unit
	local aimOrigin = head.Position
	if def.rocket then
		-- Start the rocket at the barrel when the server can see it, so it does not pop out of the player's face.
		local at = aimOrigin + aim * 2
		local muzzle = handle and handle:FindFirstChild("Muzzle")
		if muzzle and muzzle:IsA("Attachment") then
			local point = muzzle.WorldPosition
			-- Only when the barrel is ahead of the head: a hold pose can swing the muzzle behind you, and the rocket
			-- then started there and looked like it fired backwards.
			if (point - aimOrigin).Magnitude <= 15 and (point - aimOrigin):Dot(aim) > 0 then
				at = point
			end
		end
		launch(player, def, at, aim)
		return
	end
	local shot = spread(aim, def.spread)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: any }
	local hit = Workspace:Raycast(aimOrigin, shot * def.range, params)
	local finish = if hit then hit.Position else aimOrigin + shot * def.range
	if hit then
		push(player, hit.Instance, shot, def.impulse)
		hurt(player, hit.Instance, def.damage, shot)
		shotGasCan(player, hit.Instance)
	end
	fxRemote:FireAllClients(player, def.id, finish)
end

local WeaponService = {}

-- An NPC shooting its gun (`def`, a Tool named def.id in the NPC) from `head` at `target`, the player who hurt it.
-- Same spread, range and damage as a player's shot, a bit less accurate; never pushes props. The target takes the
-- damage PvP or not (they started it); anyone else in the way only with PvP on.
function WeaponService.npcFire(npc: Model, def: WeaponCatalog.WeaponDef, head: BasePart, target: Player)
	local targetRoot = Validate.aliveRoot(target)
	if not targetRoot then
		return
	end
	local tool = npc:FindFirstChild(def.id)
	local handle = tool and tool:FindFirstChild("Handle")
	if handle then
		Sfx.play(def.sound, handle)
	end
	local aimAt = targetRoot.Position + Vector3.yAxis * 1.5
	local shot = spread((aimAt - head.Position).Unit, def.spread * NPC_SPREAD)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { npc }
	local hit = Workspace:Raycast(head.Position, shot * def.range, params)
	local finish = if hit then hit.Position else head.Position + shot * def.range
	if hit then
		local character = target.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and character and hit.Instance:IsDescendantOf(character) then
			humanoid:TakeDamage(def.damage)
			RagdollService.shove(hit.Instance, shot * Config.RAGDOLL_SHOT_SPEED)
		else
			hurt(nil, hit.Instance, def.damage, shot)
		end
	end
	fxRemote:FireAllClients(npc, def.id, finish)
end

function WeaponService.init()
	fireRemote.OnServerEvent:Connect(fire)

	reloadRemote.OnServerEvent:Connect(function(player: Player, id: unknown)
		if not reloadLimiter:consume(player, 1) or typeof(id) ~= "string" then
			return
		end
		local def = WeaponCatalog.byId[id]
		local tool = def and Validate.equippedTool(player, def.id)
		if def and tool then
			reload(player, tool, def)
		end
	end)

	pvpRemote.OnServerEvent:Connect(function(player: Player, on: unknown)
		if pvpLimiter:consume(player, 1) and typeof(on) == "boolean" then
			player:SetAttribute(Config.PVP_ATTRIBUTE, on)
		end
	end)

	RunService.Heartbeat:Connect(stepRockets)
	Players.PlayerRemoving:Connect(function(player)
		lastShot[player] = nil
	end)
end

return WeaponService
