--!strict
-- Wheels, seats and premade cars. One Heartbeat drives every occupied VehicleSeat; Roblox already
-- replicates the driver's ThrottleFloat/SteerFloat, so there is no drive remote.
-- A vehicle is every wheel whose chassis is in the seat's rigid assembly. Builds with steer (servo) wheels
-- turn them; builds without steer tank-style (left and right wheels at different speeds).
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local PropCatalog = require(ReplicatedStorage.Shared.PropCatalog)
local PropBuilder = require(script.Parent.PropBuilder)

local BRAKE = 0.2 -- share of drive torque that holds the wheels when there is no input

type Wheel = { hinge: HingeConstraint, wheel: BasePart, steer: HingeConstraint? }

local wheels: { [BasePart]: { Wheel } } = {} -- chassis -> its wheels
local driving: { [VehicleSeat]: boolean? } = setmetatable({}, { __mode = "k" }) :: any

-- Frame at `position` whose X axis is `axis` (attachments and cylinders both use X).
local function frameAlong(position: Vector3, axis: Vector3): CFrame
	local up = if math.abs(axis.Y) < 0.9 then Vector3.yAxis else Vector3.zAxis
	return CFrame.fromMatrix(position, axis, (up - axis * axis:Dot(up)).Unit)
end

local function attach(part: BasePart, world: CFrame): Attachment
	local attachment = Instance.new("Attachment")
	attachment.CFrame = part.CFrame:ToObjectSpace(world)
	attachment.Parent = part
	return attachment
end

local function weld(base: BasePart, part: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = base
	constraint.Part1 = part
	constraint.Parent = part
end

local function track(chassis: BasePart, entry: Wheel)
	local list = wheels[chassis]
	if not list then
		list = {}
		wheels[chassis] = list
		chassis.Destroying:Once(function()
			wheels[chassis] = nil
		end)
	end
	table.insert(list, entry)
	entry.hinge.Destroying:Once(function()
		local current = wheels[chassis]
		local index = current and table.find(current, entry)
		if current and index then
			table.remove(current, index)
		end
	end)
end

local function driveWheel(
	entry: Wheel,
	seat: VehicleSeat,
	throttle: number,
	steer: number,
	tank: boolean,
	torque: number
)
	local hinge = entry.hinge
	local base = hinge.Attachment0
	if not base then
		return
	end
	local radius = entry.wheel.Size.Y / 2
	local power = throttle
	local side = if (entry.wheel.Position - seat.Position):Dot(seat.CFrame.RightVector) >= 0 then 1 else -1
	if tank then
		power = math.clamp(throttle - steer * side, -1, 1)
	else
		-- Differential: in a turn the outer wheels spin faster than the inner ones. Same speed on every wheel
		-- (with this much torque) locks the axles together and the car plows straight instead of turning.
		power = throttle * (1 - steer * side * Config.CAR_DIFFERENTIAL)
	end
	-- Rolling forward spins about up x forward; flip for wheels whose hinge axis points the other way.
	local forwardSpin = seat.CFrame.UpVector:Cross(seat.CFrame.LookVector)
	local sign = if base.WorldAxis:Dot(forwardSpin) >= 0 then 1 else -1
	hinge.AngularVelocity = sign * power * Config.CAR_MAX_SPEED / radius
	hinge.MotorMaxTorque = torque * radius * (if power == 0 then BRAKE else 1)
	if entry.steer then
		entry.steer.TargetAngle = -steer * Config.CAR_STEER_ANGLE
	end
end

-- Wheel grip alone turns cars unreliably (one slipping wheel and the car plows on). A torque about the seat's up
-- axis pulls the yaw rate toward speed / turn radius, so steering always bites and reverse steers like a car.
-- With no steer input it damps spin. Off when nobody drives.
local function steerAssist(seat: VehicleSeat, steer: number, occupied: boolean, mass: number)
	local assist = seat:FindFirstChild("SteerAssist")
	if not assist then
		local attachment = Instance.new("Attachment")
		attachment.Name = "SteerAssistAttachment"
		attachment.Parent = seat
		local torque = Instance.new("Torque")
		torque.Name = "SteerAssist"
		torque.RelativeTo = Enum.ActuatorRelativeTo.World
		torque.Attachment0 = attachment
		torque.Parent = seat
		assist = torque
	end
	local torque = assist :: Torque
	local root = seat.AssemblyRootPart
	if not occupied or not root then
		torque.Torque = Vector3.zero
		return
	end
	local up = seat.CFrame.UpVector
	local forwardSpeed = root.AssemblyLinearVelocity:Dot(seat.CFrame.LookVector)
	local target = -steer
		* math.clamp(forwardSpeed / Config.CAR_TURN_RADIUS, -Config.CAR_MAX_YAW_RATE, Config.CAR_MAX_YAW_RATE)
	local current = root.AssemblyAngularVelocity:Dot(up)
	torque.Torque = up * (target - current) * mass * Config.CAR_STEER_ASSIST
end

-- ponytail: scans every chassis per occupied seat each frame; index chassis by assembly if this shows in profiles.
local function drive(seat: VehicleSeat, occupied: boolean)
	local throttle = if occupied then seat.ThrottleFloat else 0
	local steer = if occupied then seat.SteerFloat else 0
	local root = seat.AssemblyRootPart
	local lists: { { Wheel } } = {}
	-- Wheels are their own assemblies (hinged), so count them: a light chassis on heavy wheels (the buggy) got
	-- almost no torque from the chassis mass alone and would not move.
	local mass = seat.AssemblyMass
	for chassis, list in wheels do
		if chassis.AssemblyRootPart == root then
			table.insert(lists, list)
			for _, entry in list do
				mass += entry.wheel.AssemblyMass
			end
		end
	end
	steerAssist(seat, steer, occupied, mass)
	local torque = mass * Config.CAR_TORQUE_PER_MASS
	for _, list in lists do
		local tank = true
		for _, entry in list do
			tank = tank and entry.steer == nil
		end
		for _, entry in list do
			driveWheel(entry, seat, throttle, steer, tank, torque)
		end
	end
end

local VehicleService = {}

-- Hinge a wheel (catalog `def`) to `chassis` at `point`, axle along `normal`. Steer wheels sit on an
-- invisible knuckle that a servo turns about the chassis' up axis. Returns the drive hinge and every
-- instance made for it, so the caller can count and clean them up.
function VehicleService.attachWheel(
	chassis: BasePart,
	point: Vector3,
	normal: Vector3,
	def: PropCatalog.PropDef,
	steer: boolean
): (HingeConstraint, { Instance })
	local axis = normal.Unit
	local halfWidth = def.size[1] / 2 + 0.05
	local mount = frameAlong(point, axis)
	local made: { Instance } = {}

	local base: BasePart = chassis
	local steerHinge: HingeConstraint? = nil
	if steer then
		local knuckle = Instance.new("Part")
		knuckle.Name = "Knuckle"
		knuckle.Size = Vector3.one * 0.4
		knuckle.Transparency = 1
		knuckle.CanCollide = false
		knuckle.CanQuery = false
		knuckle.CanTouch = false
		knuckle.CFrame = mount
		local upright = frameAlong(point, chassis.CFrame.UpVector)
		local servo = Instance.new("HingeConstraint")
		servo.ActuatorType = Enum.ActuatorType.Servo
		servo.ServoMaxTorque = math.huge
		servo.AngularSpeed = 4
		servo.LimitsEnabled = true
		servo.LowerAngle = -Config.CAR_STEER_ANGLE
		servo.UpperAngle = Config.CAR_STEER_ANGLE
		servo.Attachment0 = attach(chassis, upright)
		servo.Attachment1 = attach(knuckle, upright)
		servo.Parent = knuckle
		knuckle.Parent = chassis
		table.insert(made, servo.Attachment0 :: Attachment)
		table.insert(made, knuckle)
		base = knuckle
		steerHinge = servo
	end

	local wheel = PropBuilder.build(def, frameAlong(point + axis * halfWidth, axis))
	wheel.Name = "Wheel"
	local wheelAttachment = Instance.new("Attachment")
	wheelAttachment.Position = Vector3.new(-halfWidth, 0, 0)
	wheelAttachment.Parent = wheel
	local hinge = Instance.new("HingeConstraint")
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.MotorMaxTorque = 0
	hinge.Attachment0 = attach(base, mount)
	hinge.Attachment1 = wheelAttachment
	hinge.Parent = wheel
	wheel.Parent = chassis
	table.insert(made, hinge.Attachment0 :: Attachment)
	table.insert(made, wheel)

	track(chassis, { hinge = hinge, wheel = wheel, steer = steerHinge })
	return hinge, made
end

-- Seat and wheels for a premade car. Call on the unparented chassis, before it is claimed.
function VehicleService.buildCar(def: PropCatalog.PropDef, chassis: BasePart)
	local vehicle = def.vehicle
	if not vehicle then
		return
	end
	local s = vehicle.seat
	local seat = PropBuilder.build(PropCatalog.byId.vehicle_seat, chassis.CFrame * CFrame.new(s[1], s[2], s[3]))
	seat.Massless = true
	weld(chassis, seat)
	seat.Parent = chassis

	local wheelDef = PropCatalog.byId[vehicle.wheel]
	for _, mount in vehicle.wheels do
		local p = mount.position
		local side = if p[1] >= 0 then 1 else -1
		VehicleService.attachWheel(
			chassis,
			chassis.CFrame * Vector3.new(p[1], p[2], p[3]),
			chassis.CFrame.RightVector * side,
			wheelDef,
			mount.steer == true
		)
	end
end

function VehicleService.init()
	RunService.Heartbeat:Connect(function()
		for _, instance in CollectionService:GetTagged(Config.SEAT_TAG) do
			if not instance:IsA("VehicleSeat") or not instance:IsDescendantOf(Workspace) then
				continue
			end
			local occupied = instance.Occupant ~= nil
			if occupied or driving[instance] then
				-- One last pass after the driver leaves sets every wheel to brake.
				driving[instance] = if occupied then true else nil
				drive(instance, occupied)
			end
		end
	end)
end

return VehicleService
