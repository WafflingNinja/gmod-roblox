--!strict
-- Dupes. Toolgun "Dupe" mode copies a prop and everything linked to it (welds, ropes, thrusters, wheels) into
-- a server-side clipboard; the toolgun panel saves the clipboard to a slot, loads a slot at the crosshair and
-- deletes a slot. Slots live in memory for the session and are written to the "Dupes" DataStore (batched,
-- on leave, on shutdown). If the read at join failed, nothing is ever written, so an outage can't wipe saves.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DupeCodec = require(ReplicatedStorage.Shared.DupeCodec)
local PassCatalog = require(ReplicatedStorage.Shared.PassCatalog)
local PropCatalog = require(ReplicatedStorage.Shared.PropCatalog)
local Constraints = require(script.Parent.Constraints)
local Ownership = require(script.Parent.Ownership)
local Passes = require(script.Parent.Passes)
local PropBuilder = require(script.Parent.PropBuilder)
local RateLimiter = require(script.Parent.RateLimiter)
local Sfx = require(script.Parent.Sfx)
local SpawnService = require(script.Parent.SpawnService)
local ToolgunService = require(script.Parent.ToolgunService)
local Validate = require(script.Parent.Validate)

local RETRIES = 3
local SIZE_LIMIT = 3_500_000 -- bytes per key; the DataStore limit is 4 MB
local SHUTDOWN_WAIT = 25 -- seconds BindToClose waits for writes

type Session = {
	loaded: boolean, -- false until the DataStore read succeeds; never write before that
	slots: { [number]: DupeCodec.Dupe },
	clipboard: DupeCodec.Dupe?,
	dirty: boolean,
	scheduled: boolean,
	writing: boolean,
}

local RULES: DupeCodec.Rules = {
	ids = PropCatalog.byId,
	wheels = Config.WHEEL_PROPS,
	maxParts = Config.DUPE_PART_CAP,
	maxLinks = Config.CONSTRAINT_CAP,
	slots = Config.VIP_DUPE_SLOTS, -- load every saved slot; the per-player limit gates access
	scaleMin = Config.SCALE_MIN,
	scaleMax = Config.SCALE_MAX,
	ropeMax = Config.ROPE_MAX_LENGTH,
}

local remotes = ReplicatedStorage.Remotes
local saveRemote = remotes.DupeSave :: RemoteEvent
local loadRemote = remotes.DupeLoad :: RemoteEvent
local deleteRemote = remotes.DupeDelete :: RemoteEvent
local stateRemote = remotes.DupeState :: RemoteEvent
local notifyRemote = remotes.Notify :: RemoteEvent

-- An unpublished place (or a DataStore outage) throws here, and a throw at load time would abort Main.server
-- before every service after this one starts, MapService included: picking a map then did nothing. Dupes still
-- work in memory for the session; only saving is disabled.
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("Dupes")
	end)
	if ok then
		store = result
	else
		warn(`Dupes: DataStore unavailable, dupes will not save this session: {result}`)
	end
end
local sessions: { [Player]: Session } = {}
local writes = 0 -- DataStore writes in flight; BindToClose waits for them
local loadLimiter = RateLimiter.new(Config.DUPE_LOAD_BUCKET_CAPACITY, Config.DUPE_LOAD_REFILL_PER_SECOND)
local storeLimiter = RateLimiter.new(Config.DUPE_STORE_BUCKET_CAPACITY, Config.DUPE_STORE_REFILL_PER_SECOND)

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function vec(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

local function toVector(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function slotLimit(player: Player): number
	return if Passes.has(player, "more_dupe_slots") then Config.VIP_DUPE_SLOTS else Config.DUPE_SLOTS
end

local function slotOf(raw: unknown, limit: number): number?
	if typeof(raw) == "number" and raw % 1 == 0 and raw >= 1 and raw <= limit then
		return raw
	end
	return nil
end

-- Clipboard name and one label per available slot ("" = empty).
local function sendState(player: Player, session: Session)
	local limit = slotLimit(player)
	local labels: { string } = table.create(limit, "")
	for slot, dupe in session.slots do
		if slot <= limit then
			labels[slot] = `{dupe.name} ({#dupe.parts})`
		end
	end
	local clip = session.clipboard
	stateRemote:FireClient(player, if clip then `{clip.name} ({#clip.parts})` else "", labels)
end

-- Write the session's slots until nothing is dirty. One writer per session, so writes stay in order.
local function flush(userId: number, session: Session)
	if not session.loaded or session.writing then
		return
	end
	local db = store
	if not db then
		return
	end
	session.writing = true
	writes += 1
	while session.dirty do
		session.dirty = false
		local doc = DupeCodec.toStore(session.slots)
		if #HttpService:JSONEncode(doc) > SIZE_LIMIT then
			warn(`Dupes: {userId} over the size limit, not saved`)
			break
		end
		local ok, err = false, nil
		for attempt = 1, RETRIES do
			ok, err = pcall(function()
				db:UpdateAsync(`u{userId}`, function()
					return doc
				end)
			end)
			if ok then
				break
			end
			task.wait(2 ^ attempt)
		end
		if not ok then
			session.dirty = true -- retried on the next change, on leave or at shutdown
			warn(`Dupes: save failed for {userId}: {err}`)
			break
		end
	end
	writes -= 1
	session.writing = false
end

local function changed(player: Player, session: Session)
	session.dirty = true
	sendState(player, session)
	if not session.loaded or session.scheduled then
		return
	end
	session.scheduled = true
	task.delay(Config.DUPE_SAVE_DELAY, function()
		session.scheduled = false
		if sessions[player] == session then
			flush(player.UserId, session)
		end
	end)
end

local function load(player: Player, session: Session)
	local db = store
	if not db then
		notify(player, "Dupes will not be saved this session.")
		return
	end
	for attempt = 1, RETRIES do
		local ok, value = pcall(function()
			return db:GetAsync(`u{player.UserId}`)
		end)
		if sessions[player] ~= session then
			return
		end
		if ok then
			local slots = DupeCodec.fromStore(value, RULES)
			if not slots then
				warn(`Dupes: unreadable data for {player.UserId}, not touching it`)
				break
			end
			-- Slots saved while the read was in flight win.
			for slot, dupe in slots do
				if session.slots[slot] == nil then
					session.slots[slot] = dupe
				end
			end
			session.loaded = true
			sendState(player, session)
			if session.dirty then
				changed(player, session)
			end
			return
		end
		warn(`Dupes: load failed for {player.UserId}: {value}`)
		if attempt < RETRIES then
			task.wait(2 ^ attempt)
		end
	end
	notify(player, "Saved dupes could not load. Dupes will not be saved this session.")
end

-- The props at both ends of a constraint (welds use parts, the rest attachments).
local function ends(constraint: Instance): { Instance? }
	if constraint:IsA("WeldConstraint") then
		return { constraint.Part0, constraint.Part1 }
	elseif constraint:IsA("Constraint") then
		local a0, a1 = constraint.Attachment0, constraint.Attachment1
		return { a0 and a0.Parent, a1 and a1.Parent }
	end
	return {}
end

local function encodeLink(constraint: Instance, indexOf: { [Instance]: number }): DupeCodec.Link?
	local function at(instance: Instance?): number?
		return if instance then indexOf[instance] else nil
	end
	if constraint:IsA("WeldConstraint") then
		local a, b = at(constraint.Part0), at(constraint.Part1)
		return if a and b then { kind = "weld", a = a, b = b } else nil
	end
	if not constraint:IsA("Constraint") then
		return nil
	end
	local a0, a1 = constraint.Attachment0, constraint.Attachment1
	local a = at(a0 and a0.Parent)
	if not a0 or not a then
		return nil
	end
	if constraint:IsA("RopeConstraint") then
		local b = at(a1 and a1.Parent)
		if not a1 or not b then
			return nil
		end
		return { kind = "rope", a = a, b = b, pa = vec(a0.Position), pb = vec(a1.Position), length = constraint.Length }
	elseif constraint:IsA("VectorForce") then
		-- The thruster attachment looks into the clicked face.
		return { kind = "thruster", a = a, p = vec(a0.Position), n = vec(-a0.CFrame.LookVector) }
	elseif constraint:IsA("HingeConstraint") then
		local id = constraint:GetAttribute("WheelId")
		if typeof(id) ~= "string" then
			return nil
		end
		return { kind = "wheel", a = a, p = vec(a0.Position), n = vec(a0.Axis), wheel = id }
	end
	return nil
end

-- Flood-fill from `start` through the player's constraints, up to the part cap. Returns the dupe (nil if it
-- does not pass the codec) and whether the cap cut it short.
local function capture(player: Player, start: BasePart): (DupeCodec.Dupe?, boolean)
	local order: { BasePart } = { start }
	local indexOf: { [Instance]: number } = { [start] = 1 }
	local seen: { [Instance]: boolean } = {}
	local constraints: { Instance } = {}
	local capped = false
	local i = 1
	while i <= #order do
		for _, constraint in Constraints.linksOf(order[i]) do
			if seen[constraint] then
				continue
			end
			seen[constraint] = true
			table.insert(constraints, constraint)
			for _, other in ends(constraint) do
				if not other or indexOf[other] or not other:IsA("BasePart") or not Ownership.isOwner(player, other) then
					continue
				end
				if #order >= Config.DUPE_PART_CAP then
					capped = true
					continue
				end
				table.insert(order, other)
				indexOf[other] = #order
			end
		end
		i += 1
	end

	local parts: { DupeCodec.Part } = {}
	for index, part in order do
		local offset = part.Position - start.Position
		local rx, ry, rz = part.CFrame:ToEulerAnglesXYZ()
		local scale = part:GetAttribute("Scale")
		parts[index] = {
			id = part.Name, -- PropBuilder names props by catalog id
			cf = { offset.X, offset.Y, offset.Z, rx, ry, rz },
			color = { part.Color.R * 255, part.Color.G * 255, part.Color.B * 255 },
			scale = if typeof(scale) == "number" and scale ~= 1 then scale else nil,
			anchored = if part.Anchored then true else nil,
		}
	end
	local links: { DupeCodec.Link } = {}
	for _, constraint in constraints do
		local link = encodeLink(constraint, indexOf)
		if link then
			table.insert(links, link)
		end
	end
	local def = PropCatalog.byId[start.Name]
	local name = if def then def.name else "Dupe"
	local raw = {
		v = DupeCodec.VERSION,
		name = if #order > 1 then `{name} +{#order - 1}` else name,
		parts = parts,
		links = links,
	}
	-- Same check as a load from the DataStore, so a copy that would not load is refused now.
	return DupeCodec.sanitize(raw, RULES), capped
end

-- Rebuild `dupe` with its first part above `position`. Caps and range are checked by the caller.
local function paste(player: Player, dupe: DupeCodec.Dupe, position: Vector3)
	-- ponytail: bounding sphere per part keeps it out of the floor; big flat builds drop a little.
	local lowest = math.huge
	for _, p in dupe.parts do
		local size = PropCatalog.byId[p.id].size
		local radius = math.sqrt(size[1] ^ 2 + size[2] ^ 2 + size[3] ^ 2) / 2 * (p.scale or 1)
		lowest = math.min(lowest, p.cf[2] - radius)
	end
	local base = position + Vector3.new(0, 0.05 - lowest, 0)

	local made: { BasePart } = {}
	for index, p in dupe.parts do
		local cf = p.cf
		local cframe = CFrame.new(base + Vector3.new(cf[1], cf[2], cf[3]))
			* CFrame.fromEulerAnglesXYZ(cf[4], cf[5], cf[6])
		local part = SpawnService.spawn(player, PropCatalog.byId[p.id], cframe)
		part.Color = Color3.fromRGB(p.color[1], p.color[2], p.color[3])
		if p.scale then
			PropBuilder.setScale(part, p.scale)
		end
		part.Anchored = p.anchored == true
		made[index] = part
	end

	for _, link in dupe.links do
		local a = made[link.a]
		local b = if link.b then made[link.b] else nil
		local point = if link.p then a.CFrame:PointToWorldSpace(toVector(link.p)) else nil
		local normal = if link.n then a.CFrame:VectorToWorldSpace(toVector(link.n)) else nil
		if link.kind == "weld" and b then
			ToolgunService.weld(player, a, b)
		elseif link.kind == "rope" and b and link.pa and link.pb and link.length then
			local pointA = a.CFrame:PointToWorldSpace(toVector(link.pa))
			local pointB = b.CFrame:PointToWorldSpace(toVector(link.pb))
			ToolgunService.rope(player, a, pointA, b, pointB, link.length)
		elseif link.kind == "thruster" and point and normal then
			ToolgunService.thruster(player, a, point, normal)
		elseif link.kind == "wheel" and point and normal and link.wheel then
			ToolgunService.wheel(player, a, point, normal, link.wheel)
		end
	end
end

-- Whole dupe or nothing: refuse if any cap would be passed.
local function fits(player: Player, dupe: DupeCodec.Dupe): string?
	local thrusters = 0
	for _, link in dupe.links do
		if link.kind == "thruster" then
			thrusters += 1
		end
	end
	for _, part in dupe.parts do
		local def = PropCatalog.byId[part.id]
		if def.pass and not Passes.has(player, def.pass) then
			return "That build contains a pass vehicle."
		end
	end
	if Ownership.count(player) + #dupe.parts > Ownership.cap(player) then
		return `Not enough prop slots ({#dupe.parts} needed).`
	elseif Ownership.serverCount() + #dupe.parts > Config.SERVER_PROP_CAP then
		return "Server prop limit reached. Try again in a moment."
	elseif Constraints.count(player) + #dupe.links > Config.CONSTRAINT_CAP then
		return `Not enough constraint slots ({#dupe.links} needed).`
	elseif ToolgunService.thrusterCount(player) + thrusters > Config.THRUSTER_CAP then
		return `Thruster limit reached ({Config.THRUSTER_CAP}).`
	end
	return nil
end

local function onPlayerAdded(player: Player)
	local session: Session =
		{ loaded = false, slots = {}, clipboard = nil, dirty = false, scheduled = false, writing = false }
	sessions[player] = session
	-- Buying More Dupe Slots mid-session unlocks the extra rows immediately.
	player:GetAttributeChangedSignal(PassCatalog.attribute("more_dupe_slots")):Connect(function()
		if sessions[player] == session then
			sendState(player, session)
		end
	end)
	task.spawn(load, player, session)
end

local DupeService = {}

function DupeService.init()
	ToolgunService.handlers.Dupe = function(use)
		local session = sessions[use.player]
		if not session then
			return
		end
		local dupe, capped = capture(use.player, use.part)
		if not dupe then
			notify(use.player, "That can't be copied.")
			return
		end
		session.clipboard = dupe
		sendState(use.player, session)
		if capped then
			notify(use.player, `Copied the first {Config.DUPE_PART_CAP} parts only.`)
		end
	end

	saveRemote.OnServerEvent:Connect(function(player: Player, rawSlot: unknown)
		if not storeLimiter:consume(player, 1) then
			return
		end
		local slot = slotOf(rawSlot, slotLimit(player))
		local session = sessions[player]
		local clip = session and session.clipboard
		if not slot or not session or not clip then
			return
		end
		session.slots[slot] = clip
		changed(player, session)
	end)

	deleteRemote.OnServerEvent:Connect(function(player: Player, rawSlot: unknown)
		if not storeLimiter:consume(player, 1) then
			return
		end
		local slot = slotOf(rawSlot, slotLimit(player))
		local session = sessions[player]
		if not slot or not session or not session.slots[slot] then
			return
		end
		session.slots[slot] = nil
		changed(player, session)
	end)

	loadRemote.OnServerEvent:Connect(function(player: Player, rawSlot: unknown, position: unknown)
		if not loadLimiter:consume(player, 1) then
			return
		end
		local slot = slotOf(rawSlot, slotLimit(player))
		if not slot or typeof(position) ~= "Vector3" or not Validate.isFiniteVector(position) then
			return
		end
		local session = sessions[player]
		local dupe = session and session.slots[slot]
		local root = Validate.aliveRoot(player)
		if not dupe or not root or (position - root.Position).Magnitude > Config.SPAWN_RANGE then
			return
		end
		local refusal = fits(player, dupe)
			or (if SpawnService.nearOtherPlayer(player, position) then "Too close to another player." else nil)
		if refusal then
			notify(player, refusal)
			return
		end
		paste(player, dupe, position)
		Sfx.playAt("spawn", position)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		sessions[player] = nil
		if session then
			flush(player.UserId, session)
		end
	end)
	game:BindToClose(function()
		for player, session in sessions do
			task.spawn(flush, player.UserId, session)
		end
		local deadline = os.clock() + SHUTDOWN_WAIT
		while writes > 0 and os.clock() < deadline do
			task.wait(0.5)
		end
	end)
end

return DupeService
