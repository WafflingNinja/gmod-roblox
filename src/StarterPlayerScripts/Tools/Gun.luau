--!strict
-- Client side of the guns: LMB fires (held down for automatic ones), R reloads. We send only the gun id, the
-- camera position and the aim; the server checks fire rate and ammo, adds spread and does the hit. Locally we
-- draw the tracer, muzzle flash and recoil straight away so shooting feels instant.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Aim = require(script.Parent.Parent.Aim)
local Net = require(script.Parent.Parent.Net)
local Sfx = require(script.Parent.Parent.Sfx)
local ToolHud = require(script.Parent.Parent.UI.ToolHud)
local WeaponSelect = require(script.Parent.Parent.UI.WeaponSelect)
local Config = require(ReplicatedStorage.Shared.Config)
local WeaponCatalog = require(ReplicatedStorage.Shared.WeaponCatalog)

local RECOIL = math.rad(1.2) -- view kick per shot; rockets kick four times as hard
local IMPACT_SECONDS = 0.12
local TRACER_SECONDS = 0.05
local FLASH_SECONDS = 0.04
local TRACER_COLOR = Color3.fromRGB(255, 220, 150)
local PULSE_COLOR = Color3.fromRGB(120, 200, 255) -- AR2

local player = Players.LocalPlayer

-- Bright burst where a shot ends.
local function impact(at: Vector3)
	local spark = Instance.new("Part")
	spark.Shape = Enum.PartType.Ball
	spark.Size = Vector3.one * 0.5
	spark.Anchored = true
	spark.CanCollide = false
	spark.CanQuery = false
	spark.CanTouch = false
	spark.CastShadow = false
	spark.Material = Enum.Material.Neon
	spark.Color = TRACER_COLOR
	spark.Position = at
	spark.Parent = Workspace
	Debris:AddItem(spark, IMPACT_SECONDS)
end

local function tracer(from: Vector3, to: Vector3, color: Color3)
	local length = (to - from).Magnitude
	if length < 1 then
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.new(0.06, 0.06, length)
	part.CFrame = CFrame.lookAt((from + to) / 2, to)
	part.Parent = Workspace
	Debris:AddItem(part, TRACER_SECONDS)
end

local function muzzleOf(tool: Instance?): Attachment?
	local handle = tool and tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	return if muzzle and muzzle:IsA("Attachment") then muzzle else nil
end

local function colorOf(def: WeaponCatalog.WeaponDef): Color3
	return if def.id == "AR2" then PULSE_COLOR else TRACER_COLOR
end

local Gun = {}

-- Other players' shots: the server tells everyone where each bullet landed.
function Gun.init()
	Net.unreliable("WeaponFx").OnClientEvent:Connect(function(shooter: unknown, id: unknown, finish: unknown)
		if
			typeof(shooter) ~= "Instance"
			or shooter == player
			or typeof(id) ~= "string"
			or typeof(finish) ~= "Vector3"
		then
			return
		end
		local def = WeaponCatalog.byId[id]
		-- A Player, or an NPC Model carrying the gun (the Armed Citizen).
		local character = if shooter:IsA("Player") then shooter.Character else shooter
		local muzzle = muzzleOf(character and character:FindFirstChild(id))
		if def and muzzle then
			tracer(muzzle.WorldPosition, finish, colorOf(def))
			impact(finish)
		end
	end)
end

-- ToolController calls the returned function when the gun is equipped; it returns the cleanup.
function Gun.starter(def: WeaponCatalog.WeaponDef): () -> () -> ()
	return function()
		local tool = player.Character and player.Character:FindFirstChild(def.id)
		if not tool or not tool:IsA("Tool") then
			return function() end
		end
		local fireRemote = Net.event("WeaponFire")
		local reloadRemote = Net.event("WeaponReload")
		local muzzle = muzzleOf(tool)
		local flash: PointLight? = nil
		if muzzle then
			local light = Instance.new("PointLight")
			light.Color = colorOf(def)
			light.Range = 10
			light.Brightness = 6
			light.Enabled = false
			light.Parent = muzzle
			flash = light
		end
		local holding = false
		local lastShot = 0
		local connections: { RBXScriptConnection } = {}

		local function updateHud()
			local ammo = tool:GetAttribute(Config.AMMO_ATTRIBUTE)
			ToolHud.setAmmo(
				def.label,
				if typeof(ammo) == "number" then ammo else 0,
				def.magazine,
				tool:GetAttribute(Config.RELOADING_ATTRIBUTE) == true
			)
		end

		local function shoot()
			local camera = Workspace.CurrentCamera
			local now = os.clock()
			if not camera or now - lastShot < 60 / def.rpm or tool:GetAttribute(Config.RELOADING_ATTRIBUTE) then
				return
			end
			lastShot = now
			local ammo = tool:GetAttribute(Config.AMMO_ATTRIBUTE)
			if typeof(ammo) ~= "number" or ammo <= 0 then
				Sfx.play("dry_fire")
				reloadRemote:FireServer(def.id)
				holding = false
				return
			end
			local origin = camera.CFrame.Position
			local hit = Aim.cast(def.range)
			local finish = if hit and hit.result
				then hit.result.Position
				else origin + camera.CFrame.LookVector * def.range
			-- The server shoots from our head, so aim from there at what the crosshair is on. In first person that is
			-- the camera's own direction; in third person the camera sits off to the side and this keeps shots on it.
			local head = player.Character and player.Character:FindFirstChild("Head")
			local from = if head and head:IsA("BasePart") then head.Position else origin
			local direction = if (finish - from).Magnitude > 1 then (finish - from).Unit else camera.CFrame.LookVector
			if direction:Dot(camera.CFrame.LookVector) < 0.5 then
				direction = camera.CFrame.LookVector -- the crosshair hit something between the camera and the head
			end
			fireRemote:FireServer(def.id, origin, direction)

			if not def.rocket then
				tracer(if muzzle then muzzle.WorldPosition else origin, finish, colorOf(def))
				impact(finish)
			end
			if flash then
				local light = flash
				light.Enabled = true
				task.delay(FLASH_SECONDS, function()
					light.Enabled = false
				end)
			end
			camera.CFrame *= CFrame.Angles(RECOIL * (if def.rocket then 4 else 1), 0, 0)
		end

		table.insert(connections, tool:GetAttributeChangedSignal(Config.AMMO_ATTRIBUTE):Connect(updateHud))
		table.insert(connections, tool:GetAttributeChangedSignal(Config.RELOADING_ATTRIBUTE):Connect(updateHud))
		table.insert(
			connections,
			UserInputService.InputBegan:Connect(function(input, processed)
				if processed or WeaponSelect.isOpen() then
					return
				end
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					holding = true
					shoot()
				elseif input.KeyCode == Enum.KeyCode.R then
					reloadRemote:FireServer(def.id)
				end
			end)
		)
		table.insert(
			connections,
			UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					holding = false
				end
			end)
		)
		if def.automatic then
			table.insert(
				connections,
				RunService.RenderStepped:Connect(function()
					if holding then
						shoot()
					end
				end)
			)
		end

		ToolHud.setCrosshair(true)
		updateHud()

		return function()
			for _, connection in connections do
				connection:Disconnect()
			end
			if flash then
				flash:Destroy()
			end
			ToolHud.setAmmo(nil)
			ToolHud.setCrosshair(false)
		end
	end
end

return Gun
