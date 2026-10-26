--!strict
local BAD = {
	["149162327"] = true,
	["7948622114"] = true,
	["203785492"] = true,
}

local function fix()
	for _, v in ipairs(game:GetDescendants()) do
		if v:IsA("Decal") or v:IsA("Texture") then
			local t = v.Texture
			if typeof(t) == "string" then
				for id in pairs(BAD) do
					if string.find(t, id) then
						v.Texture = "rbxassetid://0"
						break
					end
				end
			end
		elseif v:IsA("MeshPart") then
			local t = v.TextureID
			if typeof(t) == "string" and t ~= "" then
				for id in pairs(BAD) do
					if string.find(t, id) then
						v.TextureID = ""
						break
					end
				end
			end
		elseif v:IsA("SpecialMesh") then
			local t = v.TextureId
			if typeof(t) == "string" and t ~= "" then
				for id in pairs(BAD) do
					if string.find(t, id) then
						v.TextureId = ""
						break
					end
				end
			end
		elseif v:IsA("SurfaceAppearance") then
			local c = v:FindFirstChildOfClass("Texture")
			if c and typeof(c.Texture) == "string" then
				for id in pairs(BAD) do
					if string.find(c.Texture, id) then
						v:Destroy()
						break
					end
				end
			end
		end
	end
end

task.wait()
fix()
game.DescendantAdded:Connect(function(d)
	task.wait()
	if d:IsA("Decal") or d:IsA("Texture") then
		local t = d.Texture
		if typeof(t) == "string" then
			for id in pairs(BAD) do
				if string.find(t, id) then
					d.Texture = "rbxassetid://0"
					break
				end
			end
		end
	elseif d:IsA("MeshPart") then
		local t = d.TextureID
		if typeof(t) == "string" and t ~= "" then
			for id in pairs(BAD) do
				if string.find(t, id) then
					d.TextureID = ""
					break
				end
			end
		end
	elseif d:IsA("SpecialMesh") then
		local t = d.TextureId
		if typeof(t) == "string" and t ~= "" then
			for id in pairs(BAD) do
				if string.find(t, id) then
					d.TextureId = ""
					break
				end
			end
		end
	end
end)
