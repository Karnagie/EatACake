--[[
	CodesData
	Promo-code catalogue (R1) — the SINGLE tuning point for codes.

	codes[CODE] = {
		reward,    -- descriptor (ADR-0002 grammar)
		expiresAt, -- optional unix time; nil = never expires
	}

	Keys MUST be normalized already: UPPER-CASE, no spaces (CodesService
	normalizes player input the same way before lookup). One redemption per
	player per code (profile.codes.redeemed ledger). Retiring a code =
	deleting its row (redeemed ledger entries are preserved harmlessly).
]]

local CodesData = {}

CodesData.codes = {
	["WELCOME"] = {
		reward = { kind = "gems", amount = 25 },
		expiresAt = nil,
	},
	["EATCAKE"] = {
		reward = { kind = "egg", eggType = "lucky" },
		expiresAt = nil,
	},
	["SWEETTOOTH"] = {
		reward = { kind = "boost", boostId = "boost-15m" },
		expiresAt = nil,
	},
}

-- Max accepted input length (anything longer is rejected before lookup).
-- Keep in sync with the client input clamp (UIKit TextInput maxLength,
-- default 32).
CodesData.maxLength = 32

-- Min seconds between one player's redeem attempts (anti-spam; the client
-- gets a "cooldown" status, not silence).
CodesData.attemptCooldownSeconds = 2

return CodesData
