--!strict
return table.freeze({
	BUILD = "v12 (two-handed, cursor in menus)", -- shown in the HUD; bump on every change so a stale Studio is obvious
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
	FLOAT_TAG = "SandboxFloat", -- props FloatService lifts in water; lift (mass units) in the FloatLift attribute
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
	CAR_MAX_SPEED = 60, -- studs/s at the wheel rim; 90 spun the wheels out and steering lost grip
	CAR_TORQUE_PER_MASS = 20, -- wheel motor torque = car mass * this * radius; at 40 the wheels spun past tire grip and steering lost bite
	CAR_STEER_ANGLE = 35, -- degrees, servo front wheels
	CAR_DIFFERENTIAL = 0.35, -- at full steer, outer wheels get 1 + this of the speed, inner 1 - this
	CAR_TURN_RADIUS = 18, -- studs; steer assist aims for yaw rate = speed / this at full steer
	CAR_MAX_YAW_RATE = 2.2, -- rad/s cap on that
	CAR_STEER_ASSIST = 90, -- assist torque per unit of mass per rad/s of yaw-rate error
	RAGDOLL_GETUP = 3, -- seconds before a toggled ragdoll stands up
	RAGDOLL_BUCKET_CAPACITY = 3,
	RAGDOLL_REFILL_PER_SECOND = 1,
	WHEEL_PROPS = { wheel_small = true, wheel_big = true }, -- prop ids the Wheel tool may mount
	DUPE_PART_CAP = 80, -- props in one dupe
	DUPE_SLOTS = 10,
	DUPE_LOAD_BUCKET_CAPACITY = 2,
	DUPE_LOAD_REFILL_PER_SECOND = 0.5,
	DUPE_STORE_BUCKET_CAPACITY = 3, -- save/delete a slot
	DUPE_STORE_REFILL_PER_SECOND = 0.2,
	DUPE_SAVE_DELAY = 15, -- seconds; slot changes are batched into one DataStore write
	MAP_ATTRIBUTE = "Map", -- on Player: MapCatalog id the player spawns on
	MAP_LADDER_TEXTURE = "rbxassetid://98078659072409", -- original brushed metal, replaces the converter's empty ladder TextureId
	MAP_BUCKET_CAPACITY = 2,
	MAP_REFILL_PER_SECOND = 0.5,
	AMMO_ATTRIBUTE = "Ammo", -- on each gun Tool: rounds in the magazine (server-set)
	RELOADING_ATTRIBUTE = "Reloading",
	PVP_ATTRIBUTE = "Pvp", -- on Player: takes and deals gun damage only when both sides have it on
	FIRE_BUCKET_CAPACITY = 20, -- shots; the per-gun rpm check is the real limit
	FIRE_REFILL_PER_SECOND = 16,
	RELOAD_BUCKET_CAPACITY = 3,
	RELOAD_REFILL_PER_SECOND = 1,
	PVP_BUCKET_CAPACITY = 2,
	PVP_REFILL_PER_SECOND = 0.2,
	ROCKET_CAP = 3, -- rockets in flight per player
	MIRROR_TAG = "Mirror", -- parts MapService tags; the client draws a reflection on them
	MIRROR_FACE_ATTRIBUTE = "MirrorFace", -- which face of a tagged part shows the reflection
	MIRROR_SEARCH = 12, -- studs from a MapCatalog mirror point to the wall face used
	MIRROR_WIDTH = 28, -- studs; the generated mirror panel on that wall
	MIRROR_HEIGHT = 14,
	MIRROR_FRAME = 0.6, -- studs the black frame sticks out around the glass
	MIRROR_OFFSET = 0.3, -- studs in front of the collision face, clear of the visible brush meshes
	MIRROR_PIXELS_PER_STUD = 16, -- SurfaceGui resolution; 28x14 at 16 is a 448x224 render, not a 155-stud wall at 50
	MIRROR_MAX_DISTANCE = 160, -- studs before a mirror stops rendering
	MIRROR_ROOM_RANGE = 45, -- studs of nearby map geometry copied into the viewport
	MIRROR_ROOM_PARTS = 140, -- cap on those copies
	FLASHLIGHT_NAME = "Flashlight", -- SpotLight on the Head
	FLASHLIGHT_BUCKET_CAPACITY = 4,
	FLASHLIGHT_REFILL_PER_SECOND = 2,
	WALK_SPEED = 20, -- Roblox default is 16
	JUMP_HEIGHT = 8, -- Roblox default is 7.2
	FEEDBACK_MAX = 500, -- characters
	FEEDBACK_COOLDOWN = 60, -- seconds between messages per player
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
