--!strict
-- Wait for the first full copy of the game. Modules index ReplicatedStorage.Shared directly when required, and
-- PlayerScripts can start before it has all arrived ("WeaponCatalog is not a valid member of Shared").
if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- One lookup + one assert per module: a missing or non-ModuleScript module fails here, with its name,
-- instead of as a bare "attempt to index nil" deep inside a require chain.
local function module(parent: Instance, name: string): ModuleScript
	local found = parent:WaitForChild(name, 10)
	assert(found, `StarterPlayerScripts: module {name} missing (under {parent.Name})`)
	assert(found:IsA("ModuleScript"), `StarterPlayerScripts: {name} under {parent.Name} is not a ModuleScript`)
	return found
end

local ui = script.Parent:WaitForChild("UI", 10)
assert(ui, "StarterPlayerScripts.UI missing")
local tools = script.Parent:WaitForChild("Tools", 10)
assert(tools, "StarterPlayerScripts.Tools missing")
local menuModule = module(ui, "SpawnMenu")
local controllerModule = module(tools, "ToolController")
local selectModule = module(ui, "WeaponSelect")
local ragdollModule = module(script.Parent, "Ragdoll")
local firstPersonModule = module(script.Parent, "FirstPerson")
local mainMenuModule = module(ui, "MainMenu")
local keyboardLookModule = module(script.Parent, "KeyboardLook")
local gunPoseModule = module(script.Parent, "GunPose")
local flashlightModule = module(script.Parent, "Flashlight")
local mirrorModule = module(script.Parent, "Mirror")
local thirdPersonModule = module(script.Parent, "ThirdPerson")
local mapLightingModule = module(script.Parent, "MapLighting")
local movementModule = module(script.Parent, "Movement")
local npcVoiceModule = module(script.Parent, "NpcVoice")
local vipChatModule = module(ui, "VipChat")
require(menuModule).init()
require(selectModule).init()
require(ragdollModule).init()
require(firstPersonModule).init()
require(controllerModule).init()
require(keyboardLookModule).init()
require(gunPoseModule).init()
require(flashlightModule).init()
require(mirrorModule).init()
require(thirdPersonModule).init()
require(mapLightingModule).init()
require(movementModule).init()
require(npcVoiceModule).init()
require(vipChatModule).init()
require(mainMenuModule).init()
