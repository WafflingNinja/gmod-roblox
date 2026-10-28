--!nocheck
-- Run: lune run tests/ragdoll.spec.luau
local RagdollJoints = require("../src/ReplicatedStorage/Shared/RagdollJoints")

local R15_MOTORS = {
	"Neck",
	"Waist",
	"LeftShoulder",
	"RightShoulder",
	"LeftElbow",
	"RightElbow",
	"LeftWrist",
	"RightWrist",
	"LeftHip",
	"RightHip",
	"LeftKnee",
	"RightKnee",
	"LeftAnkle",
	"RightAnkle",
}

for _, name in R15_MOTORS do
	assert(RagdollJoints.byMotor[name], "no limits for " .. name)
end

for name, joint in RagdollJoints.byMotor do
	if joint.kind == "hinge" then
		assert(joint.lower < joint.upper, name .. ": hinge range is backwards")
		assert(joint.lower >= -180 and joint.upper <= 180, name .. ": hinge past half a turn")
	else
		assert(joint.cone > 0 and joint.cone < 180, name .. ": cone out of range")
		assert(joint.twist >= 0 and joint.twist <= 180, name .. ": twist out of range")
	end
end

-- Elbows bend forward only (0..+), knees backward only (-..0): the human way.
for _, side in { "Left", "Right" } do
	local elbow = RagdollJoints.byMotor[side .. "Elbow"]
	local knee = RagdollJoints.byMotor[side .. "Knee"]
	assert(elbow.kind == "hinge" and elbow.lower == 0 and elbow.upper > 0, side .. " elbow")
	assert(knee.kind == "hinge" and knee.upper == 0 and knee.lower < 0, side .. " knee")
end

-- Left and right match, and the neck can't turn further than the shoulders.
for _, pair in { { "Shoulder", "ball" }, { "Hip", "ball" }, { "Wrist", "ball" }, { "Ankle", "ball" } } do
	local left, right = RagdollJoints.byMotor["Left" .. pair[1]], RagdollJoints.byMotor["Right" .. pair[1]]
	assert(left.cone == right.cone and left.twist == right.twist, pair[1] .. " sides differ")
end
assert(RagdollJoints.byMotor.Neck.cone < RagdollJoints.byMotor.LeftShoulder.cone, "neck looser than shoulder")

assert(RagdollJoints.of("Torso Weird") == RagdollJoints.FALLBACK, "unknown joint falls back")
assert(RagdollJoints.of("LeftKnee").kind == "hinge")

print("ragdoll ok (" .. #R15_MOTORS .. " joints)")
