--!strict
-- Remote lookup with a timeout, so a missing remote fails loudly instead of yielding forever.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local function find(name: string): Instance
	local folder = ReplicatedStorage:WaitForChild("Remotes", 10)
	local remote = folder and folder:WaitForChild(name, 10)
	assert(remote, `Remote missing: {name}`)
	return remote
end

function Net.event(name: string): RemoteEvent
	local remote = find(name)
	assert(remote:IsA("RemoteEvent"), `{name} is not a RemoteEvent`)
	return remote
end

function Net.unreliable(name: string): UnreliableRemoteEvent
	local remote = find(name)
	assert(remote:IsA("UnreliableRemoteEvent"), `{name} is not an UnreliableRemoteEvent`)
	return remote
end

return Net
