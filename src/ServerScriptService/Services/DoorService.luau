--!strict
-- Source map doors. The map importer tags each door model `MapDoor` and gives it Hinge, Kind, Angle,
-- Offset and Speed attributes; this service turns them into hinged or sliding doors that open on a
-- ProximityPrompt or on touch, then close again on their own.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DOOR_TAG = "MapDoor"
local OPEN_SECONDS = 4
local MOVE_SECONDS = 0.55
local TOUCH_COOLDOWN = 1
local PROMPT_RANGE = 22 -- studs the E prompt shows from
local DROP_MIN = 2 -- studs above the floor before a door is treated as floating
local DROP_MAX = 20 -- never drop a door further than this; it is not sitting on that floor

type Door = {
	model: Model,
	closed: CFrame,
	open: CFrame,
	openedAt: number?,
	touching: number,
	moving: boolean,
	gen: number,
	conns: { RBXScriptConnection },
	prompt: ProximityPrompt?,
}

local doors: { Door } = {}

local function targetFor(model: Model, open: boolean): CFrame
	local rawHinge = model:GetAttribute("Hinge")
	local hinge = if typeof(rawHinge) == "Vector3" then rawHinge else Vector3.zero
	local kind = model:GetAttribute("Kind")
	if kind == "slide" then
		local rawOffset = model:GetAttribute("Offset")
		local offset = if typeof(rawOffset) == "Vector3" then rawOffset else Vector3.yAxis * 8
		return CFrame.new(hinge + (if open then offset else Vector3.zero))
	end
	local rawAngle = model:GetAttribute("Angle")
	local angle = if typeof(rawAngle) == "number" and rawAngle ~= 0 then rawAngle else 90
	return CFrame.new(hinge) * CFrame.Angles(0, math.rad(angle) * (if open then 1 else 0), 0)
end

-- A new move supersedes one still running (gen), so the door always ends where the last request wanted.
local function move(door: Door, open: boolean)
	local to = if open then door.open else door.closed
	local from = door.model:GetPivot()
	door.gen += 1
	local gen = door.gen
	if from == to then
		door.moving = false
		return
	end
	door.moving = true
	task.spawn(function()
		local duration = MOVE_SECONDS * math.clamp((from.Position - to.Position).Magnitude / 20 + 0.35, 0.35, 1.5)
		local start = os.clock()
		while door.gen == gen and door.model.Parent do
			local alpha = math.clamp((os.clock() - start) / duration, 0, 1)
			local eased = alpha * alpha * (3 - 2 * alpha)
			door.model:PivotTo(from:Lerp(to, eased))
			if alpha >= 1 then
				break
			end
			task.wait()
		end
		if door.gen == gen then
			door.moving = false
		end
	end)
end

local function open(door: Door)
	door.openedAt = os.clock()
	if door.prompt then
		door.prompt.ActionText = "Close"
	end
	move(door, true)
end

local function close(door: Door)
	door.openedAt = nil
	if door.prompt then
		door.prompt.ActionText = "Open"
	end
	move(door, false)
end

-- Older imports put prop doors at the Source origin, which sits at mid-height: the panel ended up floating
-- about 5 studs above the floor. Measure the floor under the door and lower the whole model (and its Hinge)
-- by the gap, so the swing target still lines up. Current imports already do this in MapImport.
local function dropToFloor(model: Model): CFrame
	local closed = model:GetPivot()
	local cframe, size = model:GetBoundingBox()
	if size.Magnitude < 0.1 then
		return closed
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { model }
	local props = Workspace:FindFirstChild("Props")
	if props then
		table.insert(ignore, props)
	end
	local siblings = model.Parent
	if siblings and siblings:IsA("Folder") then
		table.insert(ignore, siblings)
	end
	params.FilterDescendantsInstances = ignore
	local bottom = cframe.Position.Y - size.Y / 2
	local hit = Workspace:Raycast(
		Vector3.new(cframe.Position.X, bottom + 0.5, cframe.Position.Z),
		Vector3.new(0, -(size.Y / 2 + DROP_MAX), 0),
		params
	)
	if not hit or hit.Normal.Y < 0.5 then
		return closed
	end
	local gap = bottom - hit.Position.Y
	if gap <= DROP_MIN or gap > DROP_MAX then
		return closed
	end
	local drop = Vector3.new(0, -gap, 0)
	model:PivotTo(closed - drop)
	local hinge = model:GetAttribute("Hinge")
	if typeof(hinge) == "Vector3" then
		model:SetAttribute("Hinge", hinge - drop)
	end
	return model:GetPivot()
end

local function setup(model: Instance)
	if not model:IsA("Model") or model:GetAttribute("DoorReady") == true then
		return
	end
	model:SetAttribute("DoorReady", true)
	local closed = dropToFloor(model)
	local openCF = targetFor(model, true)
	local door: Door = {
		model = model,
		closed = closed,
		open = openCF,
		openedAt = nil,
		touching = 0,
		moving = false,
		gen = 0,
		conns = {},
		prompt = nil,
	}
	table.insert(doors, door)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DoorPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Door"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	table.insert(
		door.conns,
		prompt.Triggered:Connect(function(_player: Player)
			if door.openedAt then
				close(door)
			else
				open(door)
			end
		end)
	)
	door.prompt = prompt
	local anchor = model:FindFirstChildWhichIsA("BasePart")
	if anchor then
		prompt.Parent = anchor
	end

	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			table.insert(
				door.conns,
				part.Touched:Connect(function(hit)
					local character = hit:FindFirstAncestorOfClass("Model")
					local player = character and Players:GetPlayerFromCharacter(character)
					if not player then
						return
					end
					door.touching = os.clock()
					if not door.openedAt then
						open(door)
					end
				end)
			)
		end
	end
end

-- Touched only fires on contact changes, so a player standing still in the doorway needs a position check.
local function occupied(door: Door): boolean
	local cframe, size = door.model:GetBoundingBox()
	local half = size / 2 + Vector3.one * 3
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local local_ = cframe:PointToObjectSpace(root.Position)
			if math.abs(local_.X) <= half.X and math.abs(local_.Y) <= half.Y and math.abs(local_.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

local DoorService = {}

function DoorService.init()
	for _, model in CollectionService:GetTagged(DOOR_TAG) do
		setup(model)
	end
	CollectionService:GetInstanceAddedSignal(DOOR_TAG):Connect(setup)
	CollectionService:GetInstanceRemovedSignal(DOOR_TAG):Connect(function(gone: Instance)
		for i = #doors, 1, -1 do
			local door = doors[i]
			local model: Instance = door.model
			if model == gone then
				for _, conn in door.conns do
					conn:Disconnect()
				end
				table.remove(doors, i)
			end
		end
	end)

	local sinceCheck = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sinceCheck += dt
		if sinceCheck < 0.5 then
			return
		end
		sinceCheck = 0
		local now = os.clock()
		for _, door in doors do
			local openedAt = door.openedAt
			if openedAt and not door.moving then
				local touching = door.touching > now - TOUCH_COOLDOWN
				local recent = now - openedAt < OPEN_SECONDS
				if not touching and not recent and occupied(door) then
					door.touching = now
				elseif not touching and not recent then
					close(door)
				end
			end
		end
	end)
end

return DoorService
