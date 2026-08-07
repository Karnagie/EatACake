--[[
	ShopSubsClient — shop consumer (R4).

	ShopUpdate -> AppRoot.shop. Row activation routes by id prefix:
	"product:<key>" -> RequestPurchase or RequestGemPurchase depending on the
	product's CURRENCY, "pass:<key>" -> RequestGamepass, "group" -> OPEN the
	community reward panel.

	⚠ The Free section's `group` row no longer claims anything. That reward became
	a wait with a community join prompt attached (features/group-reward.md), so it
	needs a surface that can show the instruction and the countdown — the shop row
	is an entry point into that panel, not a second claim path. `AppRoot.group`
	and the `ClaimGroupReward` remote are owned by SocialSubsClient (lobby), which
	is also the only place the panel can live: `GroupService:PromptJoinAsync` is
	client-only and the reward's whole server half is in the lobby partition.

	The currency lookup is rebuilt from every ShopUpdate rather than carried on
	the cell: ShopPanel passes the row ID and nothing else to onActivated, so a
	`currency` field on the view-model cell could never reach this handler.

	It also owns the WORLD purchase surfaces (`ShopUiData["prompt-products"]`): a
	ProximityPrompt whose name is listed there fires RequestPurchase for the
	product it is paired with — that is how the checkpoint's LayerEater sells the
	paid layer clear. The server still decides everything (it re-validates the key,
	refuses the prompt when the grant cannot land, and owns ProcessReceipt); this
	only asks.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "ShopSubsClient"

local ShopSubsClient = {}

function ShopSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local SoundPool = modules.SoundPool
	-- Optional (features/analytics.md). Which CARD a player taps only exists
	-- on the client until the server is asked for a purchase, and the taps
	-- that never become a request are the interesting ones.
	local Analytics = modules.LocalAnalyticsService
	local rPurchase = Net.Remote("RequestPurchase")
	local rGemPurchase = Net.Remote("RequestGemPurchase")
	local rGamepass = Net.Remote("RequestGamepass")

	-- product key -> currency, refreshed by every ShopUpdate below. Empty until
	-- the first payload lands, which is also when the shop first has cells to
	-- click, so an unknown key here means a Robux product and never a gem one.
	local currencyByKey: { [string]: string? } = {}

	AppRoot.SetCallbacks({
		onShopTabChanged = function(tabId)
			if Analytics and type(tabId) == "string" then
				Analytics.Track("shop", "tab", tabId, { urgent = true })
			end
		end,
		onShopActivated = function(rowId)
			if type(rowId) ~= "string" then
				return
			end
			if Analytics then
				Analytics.Track("shop", "card", rowId, { urgent = true })
			end
			local productKey = string.match(rowId, "^product:(.+)$")
			if productKey then
				if currencyByKey[productKey] == "gems" then
					rGemPurchase:FireServer(productKey)
				else
					rPurchase:FireServer(productKey)
				end
				-- Cue the REQUEST, not the sale: on the Robux route the prompt is
				-- about to take over the screen (ProcessReceipt owns the outcome),
				-- and on the gem route the server can still refuse. Either way the
				-- result arrives as a ShopUpdate/CurrencyUpdate, not as this click.
				SoundPool.Play("purchaseStart")
				return
			end
			local passKey = string.match(rowId, "^pass:(.+)$")
			if passKey then
				rGamepass:FireServer(passKey)
				SoundPool.Play("purchaseStart")
				return
			end
			if rowId == "group" then
				-- Hand off to the panel that owns the claim (SocialSubsClient). It
				-- replaces the shop window rather than layering over it: `openPanel`
				-- holds exactly one panel, which is the contract that keeps the modal
				-- scrim and the panel whoosh honest.
				AppRoot.Open("GroupReward")
			end
		end,
	})

	Net.Update("ShopUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local products = if type(payload.products) == "table" then payload.products else {}
		-- Rebuilt, not merged: a product dropped from the catalogue must stop
		-- routing to the gem remote the moment it stops being sold.
		table.clear(currencyByKey)
		for _, product in ipairs(products) do
			if type(product) == "table" and type(product.key) == "string" then
				currencyByKey[product.key] = product.currency
			end
		end
		AppRoot.Set({
			shop = {
				products = products,
				passes = if type(payload.passes) == "table" then payload.passes else {},
			},
		})
	end)

	-- ── World purchase surfaces (R4: the event lives here) ───────────────
	-- Built once: a prompt name -> product key map, so the PromptTriggered
	-- handler is a table lookup rather than a scan. An empty/missing list is
	-- normal in a place that authors no such prompt, but a MALFORMED row is a
	-- product that can never be bought with nothing in the console (R8).
	local productByPrompt: { [string]: string } = {}
	-- R8: every branch here says something. A MISSING ShopUiData (require failed,
	-- or a partition move stranded it) used to fall through both arms in silence,
	-- leaving every prompt press a no-op with no console trace — a paid product
	-- that cannot be bought and nothing anywhere saying so. Data modules load
	-- before subscriptions start, so an immediate warn cannot false-positive on a
	-- late arrival.
	if data.ShopUiData == nil then
		Log.Warn(SCOPE, "ShopUiData is MISSING -- every world purchase prompt is dead (the LayerEater cannot be bought)")
	else
		local promptProducts = data.ShopUiData["prompt-products"]
		if type(promptProducts) ~= "table" then
			Log.Warn(SCOPE, "ShopUiData has no 'prompt-products' array -- world purchase prompts are wired to nothing")
		else
			for index, entry in ipairs(promptProducts) do
				if type(entry) == "table" and type(entry.prompt) == "string" and type(entry.product) == "string" then
					productByPrompt[entry.prompt] = entry.product
				else
					Log.Warn(SCOPE, `ShopUiData["prompt-products"][{index}] is malformed -- that world purchase surface is dead`)
				end
			end
		end
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local key = productByPrompt[prompt.Name]
		if key == nil then
			return
		end
		if Analytics then
			Analytics.Track("shop", "card", `prompt:{key}`, { urgent = true })
		end
		-- Always the ROBUX remote: a world-sold product is a dev product by
		-- construction (a gem product needs the balance the shop window shows),
		-- and the server refuses the gem key on this route anyway.
		rPurchase:FireServer(key)
		SoundPool.Play("purchaseStart")
	end)

	-- ⚠ `GroupRewardUpdate` is NOT consumed here any more — SocialSubsClient owns
	-- it (lobby), because the payload now drives a client-only community join
	-- prompt as well as `AppRoot.group`. Two consumers of one update is exactly
	-- the drift D3 bans.
end

return ShopSubsClient
