--!strict
-- Dupe data: plain tables in and out, JSON-safe for DataStores. Pure (no Roblox datatypes) so lune can test it.
-- Everything read back goes through sanitize: an unknown id, bad number or broken link drops the whole dupe;
-- colour, scale and name are clamped instead.
-- cf = {x, y, z, rx, ry, rz}: position relative to the first part, Euler XYZ radians (world rotation).
-- Link points (p, pa, pb) and the normal n are in the part's own frame.

export type Part = { id: string, cf: { number }, color: { number }, scale: number?, anchored: boolean? }
export type LinkKind = "weld" | "rope" | "thruster" | "wheel"
export type Link = {
	kind: LinkKind,
	a: number,
	b: number?, -- weld, rope
	pa: { number }?, -- rope: attachment on a
	pb: { number }?, -- rope: attachment on b
	length: number?, -- rope
	p: { number }?, -- thruster, wheel: mount point on a
	n: { number }?, -- thruster, wheel: clicked face normal on a
	wheel: string?, -- wheel prop id
}
export type Dupe = { v: number, name: string, parts: { Part }, links: { Link } }
export type Store = { v: number, slots: { [string]: Dupe } }
export type Rules = {
	ids: { [string]: any }, -- PropCatalog.byId
	wheels: { [string]: boolean },
	maxParts: number,
	maxLinks: number,
	slots: number,
	scaleMin: number,
	scaleMax: number,
	ropeMax: number,
}

local VERSION = 1
local EXTENT = 1000 -- studs, part offset from the first part
local LOCAL_EXTENT = 200 -- studs, link point inside a part
local NAME_MAX = 40

-- NaN and inf fail the comparison.
local function finite(n: unknown, limit: number): number?
	if type(n) == "number" and math.abs(n) <= limit then
		return n
	end
	return nil
end

-- A fresh list of exactly `count` finite numbers.
local function numbers(raw: unknown, count: number, limit: number): { number }?
	if type(raw) ~= "table" then
		return nil
	end
	local t = raw :: { unknown }
	if #t ~= count then
		return nil
	end
	local out = table.create(count)
	for i = 1, count do
		local n = finite(t[i], limit)
		if not n then
			return nil
		end
		out[i] = n
	end
	return out
end

local function unit(raw: unknown): { number }?
	local v = numbers(raw, 3, 2)
	if not v then
		return nil
	end
	local m = math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2)
	if m < 0.9 or m > 1.1 then
		return nil
	end
	return { v[1] / m, v[2] / m, v[3] / m }
end

local function index(raw: unknown, count: number): number?
	if type(raw) == "number" and raw % 1 == 0 and raw >= 1 and raw <= count then
		return raw
	end
	return nil
end

local function cleanName(raw: unknown): string
	if type(raw) ~= "string" then
		return "Dupe"
	end
	local name = string.sub((string.gsub(raw, "[^%w %+%-]", "")), 1, NAME_MAX)
	return if name == "" then "Dupe" else name
end

local function sanitizePart(raw: unknown, rules: Rules): Part?
	if type(raw) ~= "table" then
		return nil
	end
	local t = raw :: any
	local id, scale = t.id, t.scale
	if type(id) ~= "string" or not rules.ids[id] then
		return nil
	end
	local cf = numbers(t.cf, 6, EXTENT)
	local rgb = numbers(t.color, 3, 1e3)
	if not cf or not rgb or (scale ~= nil and not finite(scale, 1e3)) then
		return nil
	end
	local color = table.create(3)
	for i, c in rgb do
		color[i] = math.clamp(math.floor(c + 0.5), 0, 255)
	end
	return {
		id = id,
		cf = cf,
		color = color,
		scale = if scale ~= nil then math.clamp(scale, rules.scaleMin, rules.scaleMax) else nil,
		anchored = if t.anchored == true then true else nil,
	}
end

local function sanitizeLink(raw: unknown, count: number, rules: Rules): Link?
	if type(raw) ~= "table" then
		return nil
	end
	local t = raw :: any
	local a = index(t.a, count)
	if not a then
		return nil
	end
	local kind = t.kind
	if kind == "weld" or kind == "rope" then
		local b = index(t.b, count)
		if not b or b == a then
			return nil
		end
		if kind == "weld" then
			return { kind = "weld", a = a, b = b }
		end
		local pa = numbers(t.pa, 3, LOCAL_EXTENT)
		local pb = numbers(t.pb, 3, LOCAL_EXTENT)
		local length = finite(t.length, rules.ropeMax)
		if not pa or not pb or not length then
			return nil
		end
		return { kind = "rope", a = a, b = b, pa = pa, pb = pb, length = math.max(length, 0.5) }
	elseif kind == "thruster" or kind == "wheel" then
		local p = numbers(t.p, 3, LOCAL_EXTENT)
		local n = unit(t.n)
		if not p or not n then
			return nil
		end
		if kind == "thruster" then
			return { kind = "thruster", a = a, p = p, n = n }
		end
		local wheel = t.wheel
		if type(wheel) ~= "string" or not rules.wheels[wheel] then
			return nil
		end
		return { kind = "wheel", a = a, p = p, n = n, wheel = wheel }
	end
	return nil
end

local DupeCodec = {}

DupeCodec.VERSION = VERSION

-- A clean copy of `raw`, or nil if it is not a usable dupe.
function DupeCodec.sanitize(raw: unknown, rules: Rules): Dupe?
	if type(raw) ~= "table" then
		return nil
	end
	local t = raw :: any
	if t.v ~= VERSION or type(t.parts) ~= "table" or type(t.links) ~= "table" then
		return nil
	end
	local rawParts, rawLinks = t.parts :: { unknown }, t.links :: { unknown }
	if #rawParts < 1 or #rawParts > rules.maxParts or #rawLinks > rules.maxLinks then
		return nil
	end
	local parts: { Part } = table.create(#rawParts)
	for i = 1, #rawParts do
		local part = sanitizePart(rawParts[i], rules)
		if not part then
			return nil
		end
		parts[i] = part
	end
	local links: { Link } = table.create(#rawLinks)
	for i = 1, #rawLinks do
		local link = sanitizeLink(rawLinks[i], #parts, rules)
		if not link then
			return nil
		end
		links[i] = link
	end
	return { v = VERSION, name = cleanName(t.name), parts = parts, links = links }
end

-- DataStore value. Slot keys are strings: a sparse number-keyed table does not survive JSON.
function DupeCodec.toStore(slots: { [number]: Dupe }): Store
	local out: { [string]: Dupe } = {}
	for slot, dupe in slots do
		out[tostring(slot)] = dupe
	end
	return { v = VERSION, slots = out }
end

-- Slots from a DataStore value. nil = refuse: the value is from an unknown version or broken, so the
-- caller must not overwrite it. A new player (no value) gets empty slots.
function DupeCodec.fromStore(raw: unknown, rules: Rules): { [number]: Dupe }?
	if raw == nil then
		return {}
	end
	if type(raw) ~= "table" or (raw :: any).v ~= VERSION or type((raw :: any).slots) ~= "table" then
		return nil
	end
	local stored = (raw :: any).slots
	local slots: { [number]: Dupe } = {}
	for slot = 1, rules.slots do
		local dupe = DupeCodec.sanitize(stored[tostring(slot)], rules)
		if dupe then
			slots[slot] = dupe
		end
	end
	return slots
end

return DupeCodec
