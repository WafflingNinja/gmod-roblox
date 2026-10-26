--!strict
return table.freeze({
	PROP_CAP = 150,
	SPAWN_RANGE = 150, -- studs, character to requested spawn point
	SPAWN_BUCKET_CAPACITY = 5,
	SPAWN_REFILL_PER_SECOND = 4,
	REMOVE_BUCKET_CAPACITY = 10,
	REMOVE_REFILL_PER_SECOND = 5,
	CLEAR_BUCKET_CAPACITY = 2,
	CLEAR_REFILL_PER_SECOND = 0.2,
	PROP_TAG = "SandboxProp",
	SEAT_TAG = "SandboxSeat", -- VehicleSeats VehicleService drives
	OWNER_ATTRIBUTE = "OwnerUserId",
	COUNT_ATTRIBUTE = "PropCount", -- on Player, replicated to the client HUD

	PHYSGUN = "Physgun", -- Tool names; the server finds the equipped tool by name
	TOOLGUN = "Toolgun",
	SLOT_ATTRIBUTE = "Slot", -- on each Tool: weapon-selector column 1-6
	SLOT_ORDER_ATTRIBUTE = "SlotOrder", -- position inside the column
	LABEL_ATTRIBUTE = "Label", -- display name in the selector
	GRAB_RANGE = 80, -- studs, character to prop at grab time
	HOLD_MIN = 4, -- studs, held prop distance from camera
	HOLD_MAX = 60, -- studs, held prop distance from character (server clamps)
	GRAB_MAX_SPEED = 150, -- studs/s a held prop can travel
	GRAB_BUCKET_CAPACITY = 5,
	GRAB_REFILL_PER_SECOND = 3,
	AIM_BUCKET_CAPACITY = 40,
	AIM_REFILL_PER_SECOND = 30,

	GRAVGUN = "GravityGun",
	GRAVGUN_PULL_RANGE = 60, -- studs, character to prop
	GRAVGUN_HOLD_RANGE = 12, -- closer than this RMB holds instead of pulling
	GRAVGUN_HOLD_DISTANCE = 8, -- studs from the camera while held
	GRAVGUN_PUNT_RANGE = 30,
	GRAVGUN_PULL_SPEED = 60, -- studs/s toward the player
	GRAVGUN_PUNT_SPEED = 120, -- studs/s added along the aim

	TOOL_RANGE = 120, -- studs, character to toolgun click point
	TOOL_BUCKET_CAPACITY = 8,
	TOOL_REFILL_PER_SECOND = 6,
	CONSTRAINT_CAP = 300, -- welds + ropes + thrusters per player
	THRUSTER_CAP = 20,
	ROPE_MAX_LENGTH = 100,
	THRUST_ACCEL = 350, -- studs/s^2; gravity is 196.2
	THRUSTER_BUCKET_CAPACITY = 20,
	THRUSTER_REFILL_PER_SECOND = 10,
	PROP_MAX_SPEED = 400, -- studs/s; faster props get server-owned and clamped (PhysicsGuard)
	SPAWN_PLAYER_CLEARANCE = 6, -- studs; no spawning on top of another player
	CAR_MAX_SPEED = 90, -- studs/s at the wheel rim
	CAR_TORQUE_PER_MASS = 40, -- wheel motor torque = chassis mass * this * radius
	CAR_STEER_ANGLE = 30, -- degrees, servo front wheels
	RAGDOLL_GETUP = 3, -- seconds before a toggled ragdoll stands up
	RAGDOLL_BUCKET_CAPACITY = 3,
	RAGDOLL_REFILL_PER_SECOND = 1,
	SCALE_MIN = 0.25,
	SCALE_MAX = 4,
	SCALE_STEP = 1.25,
	PALETTE = {
		{ 231, 76, 60 },
		{ 230, 126, 34 },
		{ 241, 196, 15 },
		{ 46, 204, 113 },
		{ 26, 188, 156 },
		{ 52, 152, 219 },
		{ 155, 89, 182 },
		{ 236, 240, 241 },
		{ 149, 165, 166 },
		{ 52, 73, 94 },
		{ 20, 20, 20 },
		{ 255, 105, 180 },
	},
})
