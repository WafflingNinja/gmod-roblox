--!strict
-- Toolgun modes. The server allowlists by id; the client builds its panel from the same list.
export type ToolMode = { id: string, name: string, hint: string }

local list: { ToolMode } = {
	{ id = "Weld", name = "Weld", hint = "Click one prop, then another, to weld them together." },
	{ id = "Rope", name = "Rope", hint = "Click one prop, then another, to tie them with a rope." },
	{
		id = "Thruster",
		name = "Thruster",
		hint = "Click a face to mount a thruster. It pushes the prop the opposite way. Hold F to fire.",
	},
	{
		id = "Wheel",
		name = "Wheel",
		hint = "Click a face to add a motor wheel (left small, right big). Add a Driver Seat to drive it.",
	},
	{ id = "Scale", name = "Scale", hint = "Left click grows a prop, right click shrinks it." },
	{ id = "Paint", name = "Paint", hint = "Pick a colour, then click a prop." },
	{ id = "Unweld", name = "Unweld", hint = "Click a prop to cut its welds, ropes and thrusters." },
	{ id = "Remove", name = "Remove", hint = "Click a prop to delete it." },
}

local byId: { [string]: ToolMode } = {}
for _, mode in list do
	byId[mode.id] = mode
end

return {
	list = list,
	byId = byId,
}
