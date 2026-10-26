--!strict
-- Small helpers and the colour/type tokens shared by every panel.
local Ui = {}

Ui.THEME = {
	panel = Color3.fromRGB(24, 26, 28),
	row = Color3.fromRGB(38, 41, 44),
	text = Color3.fromRGB(232, 232, 228),
	muted = Color3.fromRGB(150, 154, 156),
	accent = Color3.fromRGB(255, 170, 50),
	font = Enum.Font.GothamMedium,
}

function Ui.make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

function Ui.label(text: string, parent: Instance, props: { [string]: any }?): TextLabel
	local base = {
		Text = text,
		Font = Ui.THEME.font,
		TextSize = 16,
		TextColor3 = Ui.THEME.text,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	if props then
		for key, value in props do
			base[key] = value
		end
	end
	return Ui.make("TextLabel", base, parent)
end

return Ui
