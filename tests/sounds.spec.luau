--!nocheck
-- Run: lune run tests/sounds.spec.luau
local fs = require("@lune/fs")
local Sounds = require("../src/ReplicatedStorage/Shared/Sounds")

local generator = fs.readFile("audio/sfx.py")
local count = 0
for name, def in Sounds do
	count += 1
	assert(type(def.id) == "string", "id must be a string: " .. name)
	assert(
		def.id == "" or def.id:match("^rbxasset://sounds/") or def.id:match("^rbxassetid://%d+$"),
		"id must be empty, rbxasset://sounds/ or rbxassetid://<n>: " .. name
	)
	assert(def.volume > 0 and def.volume <= 1, "volume 0-1: " .. name)
	if def.id == "" then
		assert(generator:find("def " .. name .. "%("), "not uploaded and no generator in audio/sfx.py: " .. name)
	end
end

-- Every sound name the code plays must exist, or it would silently never play.
local function walk(dir)
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			walk(path)
		elseif path:match("%.luau$") then
			local source = fs.readFile(path)
			for name in source:gmatch('Sfx%.%a+%(%s*"([%w_]+)"') do
				assert(Sounds[name], `{path} plays unknown sound "{name}"`)
			end
			for name in source:gmatch('"([%w_]+_hold)"') do
				assert(Sounds[name], `{path} uses unknown hold loop "{name}"`)
			end
		end
	end
end
walk("src")

print(`sounds ok ({count} sounds)`)
