--!strict
-- Toolgun: one remote, allowlisted modes. Every use is validated against server state:
-- tool equipped, alive, in range, click point on the prop, prop owned by the caller.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PropCatalog = require(ReplicatedStorage.Shared.PropCatalog)
local ToolModes = require(ReplicatedStorage.Shared.ToolModes)
local Constraints = require(script.Parent.Constraints)
local Ownership = require(script.Parent.Ownership)
local PropBuilder = require(script.Parent.PropBuilder)
local RateLimiter = require(script.Parent.RateLimiter)
local Sfx = require(script.Parent.Sfx)
local Validate = require(script.Parent.Validate)
local VehicleService = require(script.Parent.VehicleService)

local CLICK_MODES = { Weld = true, Rope = true, Thruster = true, Wheel = true, Unweld = true }

local remotes = ReplicatedStorage.Remotes
local useRemote = remotes.ToolgunUse :: RemoteEvent
local thrustersRemote = remotes.ThrustersHeld :: RemoteEvent
local selectRemote = remotes.ToolSelect :: RemoteEvent
local notifyRemote = remotes.Notify :: RemoteEvent

type Use = { player: Player, tool: Tool, part: BasePart, point: Vector3, normal: Vector3, extra: unknown }
type Pending = { mode: string, part: BasePart, point: Vector3, unequipped: RBXScriptConnection }
type Thruster = { part: BasePart, emitter: ParticleEmitter }

local pending: { [Player]: Pending } = {}
local thrusters: { [Player]: { [VectorForce]: Thruster } } = {}
local useLimiter = RateLimiter.new(Config.TOOL_BUCKET_CAPACITY, Config.TOOL_REFILL_PER_SECOND)
local thrusterLimiter = RateLimiter.new(Config.THRUSTER_BUCKET_CAPACITY, Config.THRUSTER_REFILL_PER_SECOND)

-- The link builders below are also used by DupeService to rebuild a saved dupe.
local ToolgunService = {}

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function clearPending(player: Player)
	local entry = pending[player]
	if entry then
		entry.unequipped:Disconnect()
		pending[player] = nil
		selectRemote:FireClient(player, nil)
	end
end

local function beginPending(mode: string, use: Use)
	clearPending(use.player)
	local entry: Pending
	entry = {
		mode = mode,
		part = use.part,
		point = use.point,
		unequipped = use.tool.Unequipped:Once(function()
			if pending[use.player] == entry then
				clearPending(use.player)
			end
		end),
	}
	pending[use.player] = entry
	selectRemote:FireClient(use.player, use.part)
end

-- First click remembers a prop, second click on a different prop calls `finish`.
local function twoClick(mode: string, use: Use, finish: (Pending, Use) -> ())
	local first = pending[use.player]
	if not first or first.mode ~= mode or not first.part.Parent or not Ownership.isOwner(use.player, first.part) then
		beginPending(mode, use)
		return
	end
	if first.part == use.part then
		return
	end
	clearPending(use.player)
	if not Constraints.canAdd(use.player) then
		notify(use.player, `Constraint limit reached ({Config.CONSTRAINT_CAP}).`)
		return
	end
	finish(first, use)
end

local function attachmentAt(part: BasePart, worldPoint: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.CFrame = CFrame.new(part.CFrame:PointToObjectSpace(worldPoint))
	attachment.Parent = part
	return attachment
end

local function setThrusters(player: Player, held: boolean)
	local set = thrusters[player]
	if not set then
		return
	end
	for force, thruster in set do
		local mass = thruster.part.AssemblyMass
		force.Force = if held then Vector3.new(0, 0, -mass * Config.THRUST_ACCEL) else Vector3.zero
		thruster.emitter.Enabled = held
	end
end

function ToolgunService.thrusterCount(player: Player): number
	local n = 0
	local set = thrusters[player]
	if set then
		for _ in set do
			n += 1
		end
	end
	return n
end

-- Thruster on `part`'s face at `point` (world), pushing away from `normal`.
function ToolgunService.thruster(player: Player, part: BasePart, point: Vector3, normal: Vector3)
	if not Constraints.canAdd(player) then
		notify(player, `Constraint limit reached ({Config.CONSTRAINT_CAP}).`)
		return
	end
	if ToolgunService.thrusterCount(player) >= Config.THRUSTER_CAP then
		notify(player, `Thruster limit reached ({Config.THRUSTER_CAP}).`)
		return
	end
	if normal.Magnitude < 0.9 or normal.Magnitude > 1.1 then
		return
	end

	-- Force acts along the attachment's -Z, which points into the face that was clicked.
	local thrustFrame = CFrame.lookAt(point, point - normal.Unit)
	local attachment = Instance.new("Attachment")
	attachment.CFrame = part.CFrame:ToObjectSpace(thrustFrame)
	attachment.Parent = part

	local force = Instance.new("VectorForce")
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	force.ApplyAtCenterOfMass = false
	force.Force = Vector3.zero
	force.Parent = part

	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Rate = 80
	emitter.Lifetime = NumberRange.new(0.2, 0.4)
	emitter.Speed = NumberRange.new(18, 24)
	emitter.EmissionDirection = Enum.NormalId.Back
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 190, 80), Color3.fromRGB(255, 70, 20))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Parent = attachment

	local set = thrusters[player]
	if not set then
		set = {}
		thrusters[player] = set
	end
	set[force] = { part = part, emitter = emitter }
	force.Destroying:Once(function()
		if thrusters[player] then
			thrusters[player][force] = nil
		end
	end)
	local extras: { Instance } = { attachment }
	Constraints.register(player, force, { part }, extras)
end

function ToolgunService.weld(player: Player, a: BasePart, b: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = a
	weld.Part1 = b
	weld.Parent = a
	Constraints.register(player, weld, { a, b })
end

-- Rope between world points on `a` and `b`. The caller checks the length cap.
function ToolgunService.rope(player: Player, a: BasePart, pointA: Vector3, b: BasePart, pointB: Vector3, length: number)
	local a0 = attachmentAt(a, pointA)
	local a1 = attachmentAt(b, pointB)
	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = a0
	rope.Attachment1 = a1
	rope.Length = math.max(length, 0.5)
	rope.Visible = true
	rope.Thickness = 0.2
	rope.Color = BrickColor.new("Dark stone grey")
	rope.Parent = a
	local extras: { Instance } = { a0, a1 }
	Constraints.register(player, rope, { a, b }, extras)
end

-- Motor wheel `id` on `part` at `point` (world), axle along `normal`. The wheel is a child of the prop,
-- so it dies with it; Unweld also removes it.
function ToolgunService.wheel(player: Player, part: BasePart, point: Vector3, normal: Vector3, id: string)
	if normal.Magnitude < 0.9 or normal.Magnitude > 1.1 then
		return
	end
	if not Constraints.canAdd(player) then
		notify(player, `Constraint limit reached ({Config.CONSTRAINT_CAP}).`)
		return
	end
	local hinge, made = VehicleService.attachWheel(part, point, normal, PropCatalog.byId[id], false)
	hinge:SetAttribute("WheelId", id)
	Constraints.register(player, hinge, { part }, made)
end

-- Keyed by ToolModes id. DupeService adds "Dupe".
local handlers: { [string]: (Use) -> () } = {}
ToolgunService.handlers = handlers

handlers.Weld = function(use)
	twoClick("Weld", use, function(first, second)
		ToolgunService.weld(second.player, first.part, second.part)
	end)
end

handlers.Rope = function(use)
	twoClick("Rope", use, function(first, second)
		local length = (first.point - second.point).Magnitude
		if length > Config.ROPE_MAX_LENGTH then
			notify(second.player, "Rope too long.")
			return
		end
		ToolgunService.rope(second.player, first.part, first.point, second.part, second.point, length)
	end)
end

handlers.Thruster = function(use)
	ToolgunService.thruster(use.player, use.part, use.point, use.normal)
end

handlers.Wheel = function(use)
	local id = use.extra
	if typeof(id) ~= "string" or not Config.WHEEL_PROPS[id] then
		return
	end
	ToolgunService.wheel(use.player, use.part, use.point, use.normal, id)
end

handlers.Scale = function(use)
	local direction = use.extra
	if direction ~= 1 and direction ~= -1 then
		return
	end
	local sign: number = if direction == 1 then 1 else -1
	local base = use.part:GetAttribute("BaseSize")
	if typeof(base) ~= "Vector3" then
		return
	end
	local current = use.part:GetAttribute("Scale")
	local scale = if typeof(current) == "number" then current else 1
	local nextScale = math.clamp(scale * Config.SCALE_STEP ^ sign, Config.SCALE_MIN, Config.SCALE_MAX)
	if nextScale == scale then
		return
	end
	PropBuilder.setScale(use.part, nextScale)
end

handlers.Paint = function(use)
	local index = use.extra
	if typeof(index) ~= "number" or index % 1 ~= 0 then
		return
	end
	local color = Config.PALETTE[index]
	if color then
		use.part.Color = Color3.fromRGB(color[1], color[2], color[3])
	end
end

handlers.Unweld = function(use)
	Constraints.clearFor(use.part)
end

handlers.Remove = function(use)
	Sfx.playAt("remove", use.part.Position)
	use.part:Destroy()
end

function ToolgunService.init()
	useRemote.OnServerEvent:Connect(
		function(player: Player, mode: unknown, target: unknown, point: unknown, normal: unknown, extra: unknown)
			if not useLimiter:consume(player, 1) then
				return
			end
			if typeof(mode) ~= "string" or not ToolModes.byId[mode] then
				return
			end
			local handler = handlers[mode]
			local tool = Validate.equippedTool(player, Config.TOOLGUN)
			local root = Validate.aliveRoot(player)
			if not handler or not tool or not root then
				return
			end
			if typeof(target) ~= "Instance" or not target:IsA("BasePart") then
				return
			end
			if not Ownership.isOwner(player, target) then
				notify(player, "That prop is not yours.")
				return
			end
			if typeof(point) ~= "Vector3" or not Validate.isFiniteVector(point) then
				return
			end
			if (point - root.Position).Magnitude > Config.TOOL_RANGE then
				return
			end
			-- The click point must actually be on the prop.
			if (point - target.Position).Magnitude > target.Size.Magnitude / 2 + 2 then
				return
			end
			local faceNormal = Vector3.yAxis
			if typeof(normal) == "Vector3" and Validate.isFiniteVector(normal) then
				faceNormal = normal
			end
			handler({ player = player, tool = tool, part = target, point = point, normal = faceNormal, extra = extra })
			local handle = tool:FindFirstChild("Handle")
			if handle then
				Sfx.play("toolgun_fire", handle)
			end
			if CLICK_MODES[mode] and target.Parent then
				Sfx.play("weld", target)
			end
		end
	)

	thrustersRemote.OnServerEvent:Connect(function(player: Player, held: unknown)
		if typeof(held) == "boolean" and thrusterLimiter:consume(player, 1) then
			setThrusters(player, held)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			setThrusters(player, false)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		clearPending(player)
		thrusters[player] = nil
	end)
end

return ToolgunService
