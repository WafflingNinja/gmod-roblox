--!strict
-- Shared checks for remote handlers.
local COORD_LIMIT = 1e5

local Validate = {}

-- NaN and inf both fail these comparisons.
function Validate.isFiniteVector(v: Vector3): boolean
	return math.abs(v.X) < COORD_LIMIT and math.abs(v.Y) < COORD_LIMIT and math.abs(v.Z) < COORD_LIMIT
end

function Validate.isFiniteCFrame(cf: CFrame): boolean
	for _, n in { cf:GetComponents() } do
		if not (math.abs(n) < COORD_LIMIT) then
			return false
		end
	end
	return true
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
