--[[
	RebirthPanel — rebirth confirm dialog (portrait Panel family).
	3 stat rows (current progress), warning line (what rebirth resets),
	cost line, big green rebirth button — faded + disabled when the
	player cannot afford it (SettingRow CanvasGroup pattern).

	props:
		name?, title, visible, size, zIndex?, onClose
		stats -- ARRAY of { label, value } (3 rows, RebirthLayout.StatPositions)
		warnText -- what rebirth resets
		costText -- rebirth price line
		buttonText -- big rebirth button label
		canAfford -- boolean; false renders the button disabled (faded)
		onRebirth -- rebirth button callback
		layout? -- Theme-section override, default Theme.RebirthLayout
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local PanelWithHeader = require(script.Parent.PanelWithHeader)
local StatRow = require(script.Parent.StatRow)
local OutlinedText = require(script.Parent.OutlinedText)
local Button = require(script.Parent.Button)

local function RebirthPanel(props)
	local layout = props.layout or Theme.RebirthLayout
	local stats = props.stats or {}
	local canAfford = props.canAfford ~= false

	local children = {}

	for index, stat in ipairs(stats) do
		local statPosition = layout.StatPositions[index]
		if statPosition == nil then
			break
		end
		children[`Stat{index}`] = React.createElement(StatRow, {
			name = `Stat{index}`,
			label = stat.label,
			value = stat.value,
			position = UDim2.fromScale(statPosition.X, statPosition.Y),
			size = UDim2.fromScale(layout.StatSize.X, layout.StatSize.Y),
			zIndex = 5,
		})
	end

	children.Warning = React.createElement(OutlinedText, {
		text = props.warnText or "",
		position = UDim2.fromScale(layout.WarnPosition.X, layout.WarnPosition.Y),
		size = UDim2.fromScale(layout.WarnSize.X, layout.WarnSize.Y),
		textColor = Color3.new(1, 1, 1),
		textGradient = layout.WarnGradient,
		textXAlignment = Enum.TextXAlignment.Center,
		zIndex = 5,
	})

	children.Cost = React.createElement(OutlinedText, {
		text = props.costText or "",
		position = UDim2.fromScale(layout.CostPosition.X, layout.CostPosition.Y),
		size = UDim2.fromScale(layout.CostSize.X, layout.CostSize.Y),
		textColor = Color3.new(1, 1, 1),
		textGradient = layout.CostGradient,
		textXAlignment = Enum.TextXAlignment.Center,
		zIndex = 5,
	})

	local buttonChildren = {
		Button = React.createElement(Button, {
			name = "RebirthButton",
			text = props.buttonText,
			-- 318x84-aspect variant so the button fills the zone (a
			-- 4.06-aspect style self-constrains below the designed height).
			style = Theme.RebirthButton,
			textXAlignment = Enum.TextXAlignment.Center,
			enabled = canAfford,
			size = UDim2.fromScale(1, 1),
			zIndex = 2,
			onActivated = props.onRebirth,
		}),
	}

	-- Kit disabled recipe: CanvasGroup fade only (same as UpgradeRow /
	-- QuestRow / DayCard) — no bespoke overlay values in the component.
	children.RebirthAction = React.createElement("CanvasGroup", {
		Name = "RebirthAction",
		Position = UDim2.fromScale(layout.ButtonPosition.X, layout.ButtonPosition.Y),
		Size = UDim2.fromScale(layout.ButtonSize.X, layout.ButtonSize.Y),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = canAfford and 0 or Theme.DayCard.DisabledTransparency,
		ZIndex = 5,
	}, buttonChildren)

	return React.createElement(PanelWithHeader, {
		name = props.name or "RebirthPanel",
		size = props.size,
		visible = props.visible,
		title = props.title,
		onClose = props.onClose,
		zIndex = props.zIndex,
	}, children)
end

return RebirthPanel
