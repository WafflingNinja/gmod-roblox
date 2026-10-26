--!strict
-- Crosshair (screen centre) raycasts, shared by the spawn menu and the tools.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

export type Hit = { origin: Vector3, direction: Vector3, result: RaycastResult? }

local ignored: Instance? = nil

local Aim = {}

-- In third person the camera sits behind the car we drive; ThirdPerson sets that car here so aiming skips it.
function Aim.setIgnored(instance: Instance?)
	ignored = instance
end

-- Ray from the camera through the screen centre, ignoring our own character (and the Aim.setIgnored instance).
function Aim.cast(range: number): Hit?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter: { Instance } = if player.Character then { player.Character } else {}
	if ignored and ignored.Parent then
		table.insert(filter, ignored)
	end
	params.FilterDescendantsInstances = filter
	return {
		origin = ray.Origin,
		direction = ray.Direction,
		result = Workspace:Raycast(ray.Origin, ray.Direction * range, params),
	}
end

-- The prop (direct child of Workspace.Props) that `instance` belongs to, if any.
function Aim.prop(instance: Instance): BasePart?
	local props = Workspace:FindFirstChild("Props")
	local node: Instance? = instance
	while node and node.Parent ~= props do
		node = node.Parent
	end
	if node and node:IsA("BasePart") then
		return node
	end
	return nil
end

return Aim
