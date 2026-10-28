--!strict
-- Joint limits for player ragdolls, by Motor6D name (R15). Angles in degrees.
--   ball:  cone = swing from the rest direction, twist = +/- rotation along the limb
--   hinge: bends one way only, lower..upper around the joint's X axis. R15 faces -Z, so a positive angle swings the
--          lower limb forward (elbow) and a negative one backward (knee).
-- Joints not listed (R6 rigs, accessories) get FALLBACK.
export type Joint =
	{
		kind: "ball",
		cone: number,
		twist: number,
	}
	| {
		kind: "hinge",
		lower: number,
		upper: number,
	}

local function ball(cone: number, twist: number): Joint
	return { kind = "ball", cone = cone, twist = twist }
end

local function hinge(lower: number, upper: number): Joint
	return { kind = "hinge", lower = lower, upper = upper }
end

local RagdollJoints = {}

RagdollJoints.FALLBACK = ball(50, 45)

RagdollJoints.byMotor = {
	Neck = ball(45, 40),
	Waist = ball(25, 20),
	LeftShoulder = ball(100, 50),
	RightShoulder = ball(100, 50),
	LeftElbow = hinge(0, 135),
	RightElbow = hinge(0, 135),
	LeftWrist = ball(40, 15),
	RightWrist = ball(40, 15),
	LeftHip = ball(70, 25),
	RightHip = ball(70, 25),
	LeftKnee = hinge(-135, 0),
	RightKnee = hinge(-135, 0),
	LeftAnkle = ball(25, 10),
	RightAnkle = ball(25, 10),
} :: { [string]: Joint }

function RagdollJoints.of(motorName: string): Joint
	return RagdollJoints.byMotor[motorName] or RagdollJoints.FALLBACK
end

return RagdollJoints
