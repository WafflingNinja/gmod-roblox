--!strict
-- Friendly NPCs (docs/NPC.md): spawn through Ownership, wander / follow / stay (E prompt, owner only), greet
-- players and turn their head to whoever is near, flee explosions, go limp when grabbed or thrown. NPCs with a
-- gun (Armed Citizen) shoot back at whoever is near when hurt instead of running. The server picks every voice line; clients play the
-- sound and show the subtitle (StarterPlayerScripts/NpcVoice). Also the Konami-code unlock for RostikPro12308.
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local NpcCatalog = require(ReplicatedStorage.Shared.NpcCatalog)
local VoiceLines = require(ReplicatedStorage.Shared.VoiceLines)
local VoicePicker = require(ReplicatedStorage.Shared.VoicePicker)
local WeaponCatalog = require(ReplicatedStorage.Shared.WeaponCatalog)
local Hold = require(script.Parent.Hold)
local Ownership = require(script.Parent.Ownership)
local RateLimiter = require(script.Parent.RateLimiter)
local SpawnService = require(script.Parent.SpawnService)
local ToolService = require(script.Parent.ToolService)
local Validate = require(script.Parent.Validate)
local WeaponService = require(script.Parent.WeaponService)

local remotes = ReplicatedStorage.Remotes
local spawnRemote = remotes.SpawnNpc :: RemoteEvent
local sayRemote = remotes.NpcSay :: RemoteEvent
local unlockRemote = remotes.UnlockSecret :: RemoteEvent
local notifyRemote = remotes.Notify :: RemoteEvent
local propsFolder = Workspace.Props :: Folder

-- Roblox's own default R6 animations. The rig's Animate LocalScript can't run on a server-owned NPC.
local WALK_ANIMATION = "rbxassetid://180426354"
local IDLE_ANIMATION = "rbxassetid://180435571"
local CORPSE_SECONDS = 5
local RETRIES = 3
local LOOK_RANGE = 20 -- studs; the head turns to the nearest player this close
local LOOK_YAW = math.rad(70)
local LOOK_PITCH = math.rad(30)
local ANGRY_RANGE = 60 -- studs; an armed NPC shoots back at the nearest player this close
local ANGRY_SECONDS = 8
local FIRE_SLOWDOWN = 2.5 -- an armed NPC fires this many times slower than the gun's rpm
local JUMP_CHANCE = 0.08 -- per wander step

type Mode = "wander" | "follow" | "stay"
type Npc = {
	def: NpcCatalog.NpcDef,
	owner: Player,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	prompt: ProximityPrompt,
	mode: Mode,
	home: Vector3,
	health: number,
	nextMove: number,
	nextIdle: number,
	lastLine: string?,
	quietUntil: number, -- no new line before this
	greeted: { [Player]: number },
	held: boolean,
	limpUntil: number?,
	fleeFrom: Vector3?,
	fleeUntil: number,
	neck: Motor6D?,
	neckC0: CFrame, -- the neck's rest pose; head turns are applied on top
	gun: WeaponCatalog.WeaponDef?,
	angryAt: Player?,
	angryUntil: number,
	nextShot: number,
}

local npcs: { [Model]: Npc } = {}
local voiceEnds: { number } = {} -- end times of lines playing anywhere, for the server-wide cap
local avatarIds: { [string]: number } = {}

local spawnLimiter = RateLimiter.new(Config.NPC_BUCKET_CAPACITY, Config.NPC_REFILL_PER_SECOND)
local promptLimiter = RateLimiter.new(Config.NPC_PROMPT_BUCKET_CAPACITY, Config.NPC_PROMPT_REFILL_PER_SECOND)
local unlockLimiter = RateLimiter.new(1, 0.1)

-- Same reason as Dupes: an unpublished place throws here, and that must not stop the services after this one.
local unlockStore: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("Unlocks")
	end)
	if ok then
		unlockStore = result
	else
		warn(`Npc: DataStore unavailable, unlocks will not save this session: {result}`)
	end
end

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function rgb(c: NpcCatalog.Rgb): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function voicesPlaying(now: number): number
	for i = #voiceEnds, 1, -1 do
		if voiceEnds[i] <= now then
			table.remove(voiceEnds, i)
		end
	end
	return #voiceEnds
end

local function pickLine(npcId: string, category: string, last: string?): string?
	return VoicePicker.pick(VoiceLines.lines, npcId, category, last, NpcCatalog.lineWeights, math.random())
end

-- `force` skips the per-NPC gap and the server cap (death lines).
local function say(npc: Npc, category: string, force: boolean?)
	local now = os.clock()
	if not force and (now < npc.quietUntil or voicesPlaying(now) >= Config.NPC_VOICES_AT_ONCE) then
		return
	end
	local id = pickLine(npc.def.voice, category, npc.lastLine)
	if not id then
		return
	end
	local length = VoiceLines.lines[id].length
	npc.lastLine = id
	npc.quietUntil = now + math.max(length, Config.NPC_VOICE_GAP)
	table.insert(voiceEnds, now + length)
	sayRemote:FireAllClients(npc.model, id)
end

local function nearestPlayer(position: Vector3, range: number): (Player?, BasePart?)
	local best, bestRoot, bestDistance = nil, nil, range
	for _, player in Players:GetPlayers() do
		local root = Validate.aliveRoot(player)
		local distance = if root then (root.Position - position).Magnitude else math.huge
		if root and distance < bestDistance then
			best, bestRoot, bestDistance = player, root, distance
		end
	end
	return best, bestRoot
end

local function description(def: NpcCatalog.NpcDef): HumanoidDescription
	local avatar = def.avatar
	if avatar then
		local ok, result = pcall(function(): HumanoidDescription
			local userId = avatarIds[avatar] or Players:GetUserIdFromNameAsync(avatar)
			avatarIds[avatar] = userId
			return Players:GetHumanoidDescriptionFromUserId(userId)
		end)
		if ok then
			return result
		end
		warn(`Npc: could not load {avatar}'s avatar, using body colors: {result}`)
	end
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = rgb(def.head)
	desc.TorsoColor = rgb(def.torso)
	desc.LeftArmColor = rgb(def.arms)
	desc.RightArmColor = rgb(def.arms)
	desc.LeftLegColor = rgb(def.legs)
	desc.RightLegColor = rgb(def.legs)
	return desc
end

local function capPart(name: string, size: Vector3, cframe: CFrame, head: BasePart)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = Color3.fromRGB(20, 20, 20)
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = part
	weld.Parent = part
	part.Parent = head.Parent
end

-- Rig with the NPC's look, at `cframe`. Yields (avatar lookups). nil if Roblox couldn't build it.
local function build(def: NpcCatalog.NpcDef, cframe: CFrame): Model?
	local ok, result = pcall(function(): Model
		return Players:CreateHumanoidModelFromDescription(description(def), Enum.HumanoidRigType.R6)
	end)
	if not ok then
		warn(`Npc: could not build {def.id}: {result}`)
		return nil
	end
	local model = result
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local head = model:FindFirstChild("Head")
	if not humanoid or not head or not head:IsA("BasePart") or not model:FindFirstChild("HumanoidRootPart") then
		model:Destroy()
		return nil
	end
	model.Name = def.name
	humanoid.DisplayName = def.name
	humanoid.WalkSpeed = Config.NPC_WALK_SPEED
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	model:PivotTo(cframe)
	if def.cap then
		capPart("CapDome", Vector3.new(1.25, 0.45, 1.25), head.CFrame * CFrame.new(0, 0.55, 0), head)
		capPart("CapBrim", Vector3.new(1.2, 0.1, 0.7), head.CFrame * CFrame.new(0, 0.38, -0.8), head)
	end
	CollectionService:AddTag(model, Config.NPC_TAG)
	return model
end

local function animate(humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local function track(id: string): AnimationTrack
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		return animator:LoadAnimation(animation)
	end
	local walk = track(WALK_ANIMATION)
	track(IDLE_ANIMATION):Play()
	humanoid.Running:Connect(function(speed: number)
		if speed > 0.5 then
			if not walk.IsPlaying then
				walk:Play()
			end
			walk:AdjustSpeed(speed / Config.NPC_WALK_SPEED)
		elseif walk.IsPlaying then
			walk:Stop()
		end
	end)
end

local function setLimp(npc: Npc, limp: boolean)
	npc.humanoid.PlatformStand = limp
	if not limp then
		-- Stand back up facing the same way, a little above the floor.
		local look = npc.root.CFrame.LookVector
		local yaw = math.atan2(-look.X, -look.Z)
		npc.root.CFrame = CFrame.new(npc.root.Position + Vector3.yAxis * 2) * CFrame.Angles(0, yaw, 0)
		npc.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function serverOwn(root: BasePart)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
end

local function wander(npc: Npc, now: number)
	if now < npc.nextMove then
		return
	end
	npc.nextMove = now + 4 + math.random() * 6
	local angle = math.random() * 2 * math.pi
	local radius = math.random() * Config.NPC_WANDER_RADIUS
	npc.humanoid:MoveTo(npc.home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
	if math.random() < JUMP_CHANCE then
		npc.humanoid.Jump = true
	end
end

-- Turn to face `position` on the spot (yaw only).
local function face(npc: Npc, position: Vector3)
	local root = npc.root
	local flat = Vector3.new(position.X, root.Position.Y, position.Z)
	if (flat - root.Position).Magnitude > 0.5 then
		root.CFrame = CFrame.lookAt(root.Position, flat)
	end
end

-- R6 neck: turn the head toward `position`, or back to rest when nil. Clamped so it never spins round.
local function look(npc: Npc, position: Vector3?)
	local neck = npc.neck
	local torso = neck and neck.Part0
	if not neck or not torso then
		return
	end
	if not position then
		neck.C0 = npc.neckC0
		return
	end
	local head = neck.Part1 or torso
	local direction = torso.CFrame:VectorToObjectSpace(position - head.Position)
	if direction.Magnitude < 0.1 then
		return
	end
	direction = direction.Unit
	local yaw = math.clamp(math.atan2(-direction.X, -direction.Z), -LOOK_YAW, LOOK_YAW)
	local pitch = math.clamp(math.asin(direction.Y), -LOOK_PITCH, LOOK_PITCH)
	neck.C0 = CFrame.new(npc.neckC0.Position) * CFrame.Angles(pitch, yaw, 0) * npc.neckC0.Rotation
end

-- Armed NPC: stand, face the target and fire. False once there's no one to shoot at.
local function fight(npc: Npc, now: number): boolean
	local gun, target = npc.gun, npc.angryAt
	if not gun or not target or now > npc.angryUntil then
		npc.angryAt = nil
		return false
	end
	local targetRoot = Validate.aliveRoot(target)
	local head = npc.model:FindFirstChild("Head")
	if not targetRoot or not head or not head:IsA("BasePart") then
		npc.angryAt = nil
		return false
	end
	npc.humanoid:MoveTo(npc.root.Position)
	face(npc, targetRoot.Position)
	if now >= npc.nextShot then
		npc.nextShot = now + 60 / gun.rpm * FIRE_SLOWDOWN
		WeaponService.npcFire(npc.model, gun, head, targetRoot.Position + Vector3.yAxis * 1.5)
	end
	return true
end

-- Grab / throw / get-up. True while the NPC is out of the NPC's own control.
local function physics(npc: Npc, now: number): boolean
	local root = npc.root
	local held = Hold.isHeld(root)
	local speed = root.AssemblyLinearVelocity.Magnitude
	if held ~= npc.held then
		npc.held = held
		if held then
			npc.limpUntil = nil
			setLimp(npc, true)
			say(npc, "grabbed")
		else
			serverOwn(root) -- Hold.release hands ownership back to the engine
			npc.limpUntil = now + Config.NPC_GETUP
			if speed > Config.NPC_THROW_SPEED then
				say(npc, "thrown")
			end
		end
		return true
	end
	if held then
		return true
	end
	if not npc.limpUntil and speed > Config.NPC_THROW_SPEED then -- punted or blown away
		npc.limpUntil = now + Config.NPC_GETUP
		setLimp(npc, true)
		say(npc, "thrown")
		return true
	end
	local limpUntil = npc.limpUntil
	if limpUntil then
		if now < limpUntil or speed > 4 then
			return true
		end
		npc.limpUntil = nil
		setLimp(npc, false)
	end
	return false
end

local function think(npc: Npc, now: number)
	if npc.root.Anchored or npc.humanoid.Health <= 0 or physics(npc, now) then
		return
	end
	local root, humanoid = npc.root, npc.humanoid
	if fight(npc, now) then
		return
	end

	local fleeFrom = npc.fleeFrom
	if fleeFrom and now < npc.fleeUntil then
		local away = (root.Position - fleeFrom) * Vector3.new(1, 0, 1)
		humanoid:MoveTo(root.Position + (if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis) * 16)
		return
	end
	npc.fleeFrom = nil

	if npc.mode == "follow" then
		local ownerRoot = Validate.aliveRoot(npc.owner)
		if ownerRoot and (ownerRoot.Position - root.Position).Magnitude > Config.NPC_FOLLOW_DISTANCE then
			humanoid:MoveTo(ownerRoot.Position)
		end
	elseif npc.mode == "wander" then
		wander(npc, now)
	end

	local _, nearRoot = nearestPlayer(root.Position, LOOK_RANGE)
	look(npc, if nearRoot then nearRoot.Position + Vector3.yAxis * 1.5 else nil)

	local player, playerRoot = nearestPlayer(root.Position, Config.NPC_GREET_RANGE)
	if player and playerRoot and now - (npc.greeted[player] or -math.huge) > Config.NPC_GREET_COOLDOWN then
		npc.greeted[player] = now
		if npc.mode ~= "follow" then
			humanoid:MoveTo(root.Position)
			npc.nextMove = now + 3 -- stand and talk for a moment
			face(npc, playerRoot.Position)
		end
		say(npc, "greet")
	elseif now >= npc.nextIdle then
		npc.nextIdle = now + math.random(Config.NPC_IDLE_MIN, Config.NPC_IDLE_MAX)
		say(npc, "idle")
	end
end

local function flee(npc: Npc, from: Vector3)
	if npc.gun then
		return -- armed NPCs stand their ground
	end
	if not npc.fleeFrom then
		say(npc, "flee")
	end
	npc.fleeFrom = from
	npc.fleeUntil = os.clock() + Config.NPC_FLEE_SECONDS
end

local function ownedCount(player: Player): (number, number)
	local mine, total = 0, 0
	for _, npc in npcs do
		total += 1
		if npc.owner == player then
			mine += 1
		end
	end
	return mine, total
end

local function canSpawn(player: Player): boolean
	local mine, total = ownedCount(player)
	if mine >= Config.NPC_PLAYER_CAP then
		notify(player, `NPC limit reached ({Config.NPC_PLAYER_CAP}). Remove some first.`)
		return false
	elseif total >= Config.NPC_SERVER_CAP then
		notify(player, "This server is full of NPCs.")
		return false
	elseif not Ownership.canSpawn(player) then
		notify(player, `Prop limit reached ({Config.PROP_CAP}). Remove some first.`)
		return false
	end
	return true
end

local function promptText(npc: Npc)
	npc.prompt.ActionText = if npc.mode == "follow" then "Stay" else "Follow"
end

local function add(player: Player, def: NpcCatalog.NpcDef, model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local torso = model:FindFirstChild("Torso")
	local neck = torso and torso:FindFirstChild("Neck")
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = `{def.name} ({player.DisplayName}'s)`
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	local now = os.clock()
	local npc: Npc = {
		def = def,
		owner = player,
		model = model,
		humanoid = humanoid,
		root = root,
		prompt = prompt,
		mode = "wander",
		home = root.Position,
		health = humanoid.Health,
		nextMove = now + 2,
		nextIdle = now + math.random(Config.NPC_IDLE_MIN, Config.NPC_IDLE_MAX),
		lastLine = nil,
		quietUntil = 0,
		greeted = { [player] = now }, -- the spawn line is its hello to the owner
		held = false,
		limpUntil = nil,
		fleeFrom = nil,
		fleeUntil = 0,
		neck = if neck and neck:IsA("Motor6D") then neck else nil,
		neckC0 = if neck and neck:IsA("Motor6D") then neck.C0 else CFrame.identity,
		gun = if def.gun then WeaponCatalog.byId[def.gun] else nil,
		angryAt = nil,
		angryUntil = 0,
		nextShot = 0,
	}
	promptText(npc)

	prompt.Triggered:Connect(function(who: Player)
		if who ~= npc.owner or not promptLimiter:consume(who, 1) or humanoid.Health <= 0 then
			return
		end
		if npc.mode == "follow" then
			npc.mode = "stay"
			npc.home = root.Position
			humanoid:MoveTo(root.Position)
			say(npc, "stay", true)
		else
			npc.mode = "follow"
			say(npc, "follow", true)
		end
		promptText(npc)
	end)
	humanoid.HealthChanged:Connect(function(health: number)
		if health < npc.health and health > 0 then
			say(npc, "hurt")
			if npc.gun then
				npc.angryAt = nearestPlayer(root.Position, ANGRY_RANGE)
				npc.angryUntil = os.clock() + ANGRY_SECONDS
				npc.health = health
				return
			end
			local _, threat = nearestPlayer(root.Position, Config.NPC_FLEE_RANGE)
			if threat then
				npc.fleeFrom = threat.Position
				npc.fleeUntil = os.clock() + Config.NPC_FLEE_SECONDS
			end
		end
		npc.health = health
	end)
	humanoid.Died:Connect(function()
		say(npc, "death", true)
		npcs[model] = nil
		prompt:Destroy()
		task.delay(CORPSE_SECONDS, function()
			model:Destroy()
		end)
	end)
	-- X on the NPC removes its root (that's the owned part); take the whole body with it.
	root.Destroying:Connect(function()
		model:Destroy()
	end)
	model.Destroying:Connect(function()
		npcs[model] = nil
	end)

	Ownership.claim(player, root)
	model.Parent = propsFolder
	if def.gun then
		local tool = ToolService.buildWeapon(def.gun)
		if tool then
			tool.Parent = model -- a Tool parented to a character in the world is held in its right hand
		end
	end
	serverOwn(root)
	animate(humanoid)
	npcs[model] = npc
	say(npc, "spawn", true)
end

local function loadUnlock(player: Player)
	local db = unlockStore
	if not db then
		return
	end
	for attempt = 1, RETRIES do
		local ok, value = pcall(function()
			return db:GetAsync(`u{player.UserId}`)
		end)
		if ok then
			if value == true and player.Parent then
				player:SetAttribute(Config.SECRET_ATTRIBUTE, true)
			end
			return
		end
		task.wait(2 ^ attempt)
	end
	warn(`Npc: could not load unlocks for {player.UserId}`)
end

local function saveUnlock(userId: number)
	local db = unlockStore
	if not db then
		return
	end
	for attempt = 1, RETRIES do
		local ok = pcall(function()
			db:UpdateAsync(`u{userId}`, function()
				return true
			end)
		end)
		if ok then
			return
		end
		task.wait(2 ^ attempt)
	end
	warn(`Npc: could not save unlock for {userId}`)
end

local NpcService = {}

function NpcService.init()
	spawnRemote.OnServerEvent:Connect(function(player: Player, npcId: unknown, position: unknown)
		if not spawnLimiter:consume(player, 1) then
			return
		end
		if typeof(npcId) ~= "string" or typeof(position) ~= "Vector3" then
			return
		end
		local def = NpcCatalog.byId[npcId]
		if not def or not Validate.isFiniteVector(position) then
			return
		end
		if def.secret and player:GetAttribute(Config.SECRET_ATTRIBUTE) ~= true then
			return
		end
		local root = Validate.aliveRoot(player)
		if not root or (position - root.Position).Magnitude > Config.SPAWN_RANGE or not canSpawn(player) then
			return
		end
		if SpawnService.nearOtherPlayer(player, position) then
			notify(player, "Too close to another player.")
			return
		end
		local at = position + Vector3.yAxis * 3
		local facing = Vector3.new(root.Position.X, at.Y, root.Position.Z)
		local model = build(def, if (facing - at).Magnitude > 0.1 then CFrame.lookAt(at, facing) else CFrame.new(at))
		if not model then
			return
		end
		-- build yielded: the player may have left or hit a cap meanwhile.
		if not player.Parent or not canSpawn(player) then
			model:Destroy()
			return
		end
		add(player, def, model)
	end)

	unlockRemote.OnServerEvent:Connect(function(player: Player)
		if not unlockLimiter:consume(player, 1) or player:GetAttribute(Config.SECRET_ATTRIBUTE) == true then
			return
		end
		player:SetAttribute(Config.SECRET_ATTRIBUTE, true)
		local id = pickLine(NpcCatalog.byId.rostik.voice, "unlock", nil)
		if id then
			sayRemote:FireClient(player, nil, id)
		end
		saveUnlock(player.UserId)
	end)

	Workspace.ChildAdded:Connect(function(child: Instance)
		if not child:IsA("Explosion") then
			return
		end
		for _, npc in npcs do
			if (npc.root.Position - child.Position).Magnitude < Config.NPC_FLEE_RANGE then
				flee(npc, child.Position)
			end
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < 1 / Config.NPC_THINK_RATE then
			return
		end
		elapsed = 0
		local now = os.clock()
		for _, npc in npcs do
			think(npc, now)
		end
	end)

	Players.PlayerAdded:Connect(loadUnlock)
	for _, player in Players:GetPlayers() do
		task.spawn(loadUnlock, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		for _, npc in npcs do
			npc.greeted[player] = nil
		end
	end)
end

return NpcService
