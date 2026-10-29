--!strict
-- Shared checks for remote handlers.
local COORD_LIMIT = 1e5

local Validate = {}

-- Finite scalar inside plus/minus `limit`. NaN and inf both fail the comparison. Use this for any
-- client-sent number that feeds a CFrame, speed or time.
function Validate.isFiniteNumber(n: number, limit: number?): boolean
	local bound = limit or COORD_LIMIT
	return math.abs(n) <= bound
end

-- NaN and inf both fail these comparisons.
function Validate.isFiniteVector(v: Vector3): boolean
	return math.abs(v.X) < COORD_LIMIT and math.abs(v.Y) < COORD_LIMIT and math.abs(v.Z) < COORD_LIMIT
end

-- Unrolled: this runs per aim packet, and the table form allocated every call.
function Validate.isFiniteCFrame(cf: CFrame): boolean
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return math.abs(x) < COORD_LIMIT
		and math.abs(y) < COORD_LIMIT
		and math.abs(z) < COORD_LIMIT
		and math.abs(r00) < COORD_LIMIT
		and math.abs(r01) < COORD_LIMIT
		and math.abs(r02) < COORD_LIMIT
		and math.abs(r10) < COORD_LIMIT
		and math.abs(r11) < COORD_LIMIT
		and math.abs(r12) < COORD_LIMIT
		and math.abs(r20) < COORD_LIMIT
		and math.abs(r21) < COORD_LIMIT
		and math.abs(r22) < COORD_LIMIT
end

function Validate.aliveRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

-- The tool must be in the character, not just the backpack.
function Validate.equippedTool(player: Player, name: string): Tool?
	local character = player.Character
	local tool = character and character:FindFirstChild(name)
	if tool and tool:IsA("Tool") then
		return tool
	end
	return nil
end

return Validate
