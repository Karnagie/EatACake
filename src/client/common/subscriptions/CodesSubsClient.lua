--[[
	CodesSubsClient — promo-code wiring (R4).
	Submit -> RedeemCode; CodeResultUpdate -> localized status line in the
	Codes panel (AppRoot.codesStatus = { text, kind }).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local CodesSubsClient = {}

function CodesSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local locale = data.LocaleData
	local rRedeem = Net.Remote("RedeemCode")

	AppRoot.SetCallbacks({
		onRedeem = function(code)
			if type(code) == "string" and #code > 0 then
				AppRoot.Clear("codesStatus") -- clear while waiting
				rRedeem:FireServer(code)
			end
		end,
	})

	Net.Update("CodeResultUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.status) ~= "string" then
			return
		end
		local status = payload.status
		local text, kind
		if status == "ok" then
			kind = "ok"
			local granted = payload.granted
			if type(granted) == "table" and granted.kind == "gems" then
				text = locale.T("status-code-ok-gems", { n = granted.amount or 0 })
			else
				text = locale.T("status-code-ok")
			end
		else
			kind = "error"
			text = if status == "expired"
				then locale.T("status-code-expired")
				elseif status == "already" then locale.T("status-code-already")
				elseif status == "cooldown" then locale.T("status-code-cooldown")
				else locale.T("status-code-invalid")
		end
		AppRoot.Set({ codesStatus = { text = text, kind = kind } })
	end)
end

return CodesSubsClient
