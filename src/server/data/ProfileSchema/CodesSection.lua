--[[
	Profile section: codes — promo-code redemption ledger.

	redeemed -- { [code: string] = true } (codes are stored normalized:
	upper-case, trimmed — see CodesService).
]]

return {
	key = "codes",
	version = 1,
	defaults = {
		redeemed = {},
	},
	intKeySets = {},
	migrations = {},
	sanitize = function(section)
		if type(section.redeemed) ~= "table" then
			section.redeemed = {}
		end
		return section
	end,
}
