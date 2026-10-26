--!strict
-- Guns. The client sends only "I fired this gun from here, this way"; the server checks the gun is equipped, the
-- fire rate, the magazine, and that the origin is at the shooter's head, then adds spread and does the raycast or
-- launches the rocket itself. Ammo lives in the Tool's Ammo attribute (server-set, replicated to the HUD).
-- Props only take impulses from their owner's guns; players only take damage when both sides have PvP on.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local WeaponCatalog = require(ReplicatedStorage.Shared.WeaponCatalog)
local GravityGunService = require(script.Parent.GravityGunService)
local Ownership = require(script.Parent.Ownership)
local RateLimiter = require(script.Parent.RateLimiter)
local Sfx = require(script.Parent.Sfx)
local Validate = require(script.Parent.Validate)

local RPM_TOLERANCE = 0.85 -- accept shots slightly early (network jitter)
local MAX_IMPULSE_SPEED = 160 -- studs/s one hit can add to a prop (rockets hit hardest)

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

local function hurt(shooter: Player, instance: Instance, amount: number)
	local character = instance:FindFirstAncestorOfClass("Model")
	local victim = character and Players:GetPlayerFromCharacter(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if victim and humanoid and victim ~= shooter and pvp(shooter) and pvp(victim) then
		humanoid:TakeDamage(amount)
	end
end

local function explode(rocket: Rocket, position: Vector3)
	local r = rocket.def.rocket :: WeaponCatalog.Rocket
	local blast = Instance.new("Explosion")
	blast.Position = position
	blast.BlastRadius = r.radius
	blast.BlastPressure = 0 -- the engine's own push and joint breaking stay off; we apply ours below
	blast.DestroyJointRadiusPercent = 0
	blast.Parent = Workspace
	Sfx.playAt("explosion", position)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rocket.part }
	local hitHumanoids: { [Humanoid]: boolean } = {}
	for _, part in Workspace:GetPartBoundsInRadius(position, r.radius, params) do
		local offset = part.Position - position
		local falloff = 1 - math.clamp(offset.Magnitude / r.radius, 0, 1)
		local away = if offset.Magnitude > 0.1 then offset.Unit else Vector3.yAxis
		push(rocket.owner, part, away + Vector3.yAxis * 0.5, r.impulse * falloff)
		local humanoid = part.Parent and part.Parent:FindFirstChildOfClass("Humanoid")
		if humanoid and not hitHumanoids[humanoid] then
			hitHumanoids[humanoid] = true
			hurt(rocket.owner, part, r.damage * falloff)
		end
	end
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

-- One Heartbeat moves every rocket and sweeps a ray along its step.
local function stepRockets(dt: number)
	local now = os.clock()
	for i = #rockets, 1, -1 do
		local rocket = rockets[i]
		local from = rocket.part.Position
		local step = rocket.velocity * dt
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { rocket.part, rocket.owner.Character :: any }
		local hit = Workspace:Raycast(from, step, params)
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
	if not def or not Validate.isFiniteVector(origin) or not Validate.isFiniteVector(direction) then
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
	if (origin - head.Position).Magnitude > Config.FIRE_ORIGIN_DRIFT then
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
	if def.rocket then
		launch(player, def, origin + aim * 2, aim)
		return
	end
	local shot = spread(aim, def.spread)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: any }
	local hit = Workspace:Raycast(origin, shot * def.range, params)
	local finish = if hit then hit.Position else origin + shot * def.range
	if hit then
		push(player, hit.Instance, shot, def.impulse)
		hurt(player, hit.Instance, def.damage)
	end
	fxRemote:FireAllClients(player, def.id, finish)
end

local WeaponService = {}

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
