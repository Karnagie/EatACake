--[[ SettingsDemo
	Reference composition: vertical Settings panel with toggle rows.
	Mock state only — real games wire values/callbacks to services via subscriptions.
]]

local React = require(game:GetService("ReplicatedStorage").Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local SettingsPanel = require(script.Parent.Parent.Components.SettingsPanel)

local INITIAL_VALUES = {
	Shadows = true,
	Music = true,
	Weather = false,
	Players = true,
	Invites = true,
}

local function calculatePanelScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	local viewportAspect = viewport.X / math.max(viewport.Y, 1)
	local panelAspect = Theme.Layout.PanelAspect
	local maxFraction = Theme.Layout.PanelMaxViewportFraction

	if viewportAspect >= panelAspect then
		return Vector2.new(maxFraction * panelAspect / viewportAspect, maxFraction)
	end

	return Vector2.new(maxFraction, maxFraction * viewportAspect / panelAspect)
end

local function App()
	local visible, setVisible = React.useState(true)
	local values, setValues = React.useState(INITIAL_VALUES)
	local panelScale, setPanelScale = React.useState(calculatePanelScale())

	React.useEffect(function()
		local viewportConnection
		local cameraConnection

		local function bindCamera()
			if viewportConnection then
				viewportConnection:Disconnect()
				viewportConnection = nil
			end

			local camera = workspace.CurrentCamera
			setPanelScale(calculatePanelScale())
			if camera then
				viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
					setPanelScale(calculatePanelScale())
				end)
			end
		end

		bindCamera()
		cameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)

		return function()
			if viewportConnection then
				viewportConnection:Disconnect()
			end
			if cameraConnection then
				cameraConnection:Disconnect()
			end
		end
	end, {})

	local function onToggle(id, value)
		setValues(function(previous)
			local nextValues = table.clone(previous)
			nextValues[id] = value
			return nextValues
		end)
	end

	return React.createElement("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {
		Settings = React.createElement(SettingsPanel, {
			visible = visible,
			size = UDim2.fromScale(panelScale.X, panelScale.Y),
			values = values,
			onToggle = onToggle,
			onClose = function()
				setVisible(false)
			end,
		}),
	})
end

return App
