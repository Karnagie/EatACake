--[[
	PanelWithHeader -- compose PanelShell, Header and caller-owned body children.

	All props are presentation/callback inputs; this component owns no feature
	state and only forwards compatible panel/header/close style variants.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local PanelShell = require(script.Parent.PanelShell)
local Header = require(script.Parent.Header)

local function PanelWithHeader(props)
	local children = {}

	if props.children then
		for key, child in pairs(props.children) do
			children[key] = child
		end
	end

	children.Header = React.createElement(Header, {
		name = props.headerName or "Header",
		title = props.title,
		showTitle = props.showTitle,
		showClose = props.showClose,
		closeEnabled = props.closeEnabled,
		onClose = props.onClose,
		zIndex = props.headerZIndex or 10,
		size = props.headerSize,
		style = props.headerStyle,
		closeStyle = props.closeStyle,
	})

	return React.createElement(PanelShell, {
		name = props.name or "PanelWithHeader",
		anchorPoint = props.anchorPoint,
		position = props.position,
		size = props.size,
		visible = props.visible,
		style = props.panelStyle,
		zIndex = props.zIndex,
	}, children)
end

return PanelWithHeader
