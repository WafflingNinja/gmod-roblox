--!strict
-- Weighted random voice line for an NPC and category, never the same line twice in a row. Pure, lune-tested.
type Line = { npc: string, category: string, text: string, start: number, length: number } -- VoiceLines.Line

local VoicePicker = {}

-- Line ids for npc + category, sorted so a given roll always picks the same line.
function VoicePicker.candidates(lines: { [string]: Line }, npc: string, category: string): { string }
	local ids: { string } = {}
	for id, line in lines do
		if line.npc == npc and line.category == category then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

-- `roll` is in [0, 1). Returns nil when the NPC has no line for the category.
function VoicePicker.pick(
	lines: { [string]: Line },
	npc: string,
	category: string,
	last: string?,
	weights: { [string]: number },
	roll: number
): string?
	local ids = VoicePicker.candidates(lines, npc, category)
	if #ids > 1 and last then
		local index = table.find(ids, last)
		if index then
			table.remove(ids, index)
		end
	end
	local total = 0
	for _, id in ids do
		total += weights[id] or 1
	end
	local target = roll * total
	for _, id in ids do
		target -= weights[id] or 1
		if target < 0 then
			return id
		end
	end
	return ids[#ids]
end

return VoicePicker
