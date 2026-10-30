--!strict
-- Remote lookup with a timeout, so a missing remote fails loudly instead of yielding forever.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local cache: { [string]: Instance } = {} -- remotes never move; don't re-wait on every lookup

local function find(name: string): Instance
	local cached = cache[name]
	if cached then
		return cached
	end
	local folder = ReplicatedStorage:WaitForChild("Remotes", 10)
	assert(folder, "Remote folder ReplicatedStorage.Remotes missing")
	local remote = folder:WaitForChild(name, 10)
	assert(remote, `Remote missing: {name}`)
	cache[name] = remote
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
