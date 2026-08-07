--[[
	ShopUiData — authored WORLD surfaces that sell a shop product (R1), read by
	ShopSubsClient.

	Most of the catalogue is bought from the shop window, whose cells carry their
	own product key in the payload. A HIDDEN product (`ShopData.hidden`) has no
	cell at all and is bought by touching something in the world instead, so the
	key has to be written down somewhere on the client — here.

	COMMON, like UpgradesUiData: the subscription is common, and a place that
	authors no such prompt simply never fires one.

	⚠ Each `prompt` name is the client half of a pair — the server writes the same
	string into `MapConfigData.checkpoint` (it is what builds/positions the prompt).
	Rename in both places or the prompt stops selling anything. Same split as
	`UpgradeStation` / UpgradesUiData.

	Shape:
	  ["prompt-products"] : ARRAY of { prompt = <ProximityPrompt name>,
	                                   product = <ShopData.products key> }
]]

local ShopUiData = {
	["prompt-products"] = {
		-- The checkpoint contraption that eats the layer you are standing on for
		-- 9 R$ (features/checkpoint.md). Game place only — the lobby authors no
		-- LayerEater, and its `eatlayer` grant kind has no handler there.
		{ prompt = "LayerEaterPrompt", product = "layer-eater" },
	},
}

return ShopUiData
