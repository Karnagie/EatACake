--[[
	CodesService
	Promo-code redemption logic over the profile's `codes` section (R2).
	Config (the code catalogue) comes from CodesData.

	R3: does NOT grant. TryRedeem validates, marks the ledger and RETURNS
	(status, reward descriptor); CodesSubs grants via RewardGrantSubs.
]]

local CodesService = {}

local profileData, codesData

function CodesService.Init(data)
	profileData = data.PlayerProfileData
	codesData = data.CodesData
end

local function section(userId: number)
	local profile = profileData.profiles[userId]
	return profile and profile.codes
end

--API
-- Normalizes raw player input to catalogue form: trimmed, upper-cased.
function CodesService.Normalize(raw: string): string
	return string.upper((string.gsub(raw, "%s+", "")))
end

--API
-- Peek without consuming: (status, code definition?). Statuses:
-- "invalid" | "expired" | "already" | "ok".
function CodesService.Check(userId: number, raw: string): (string, { [string]: any }?)
	local codes = section(userId)
	if not codes or type(raw) ~= "string" or #raw == 0 or #raw > codesData.maxLength then
		return "invalid", nil
	end
	local code = CodesService.Normalize(raw)
	local def = codesData.codes[code]
	if not def then
		return "invalid", nil
	end
	if def.expiresAt ~= nil and os.time() > def.expiresAt then
		return "expired", nil
	end
	if codes.redeemed[code] then
		return "already", nil
	end
	return "ok", def
end

--API
-- Redeem: marks the ledger and returns ("ok", reward descriptor), or the
-- failing status. Caller grants (R3) — call Check first if the grant
-- pipeline must be validated before consuming.
function CodesService.TryRedeem(userId: number, raw: string): (string, { [string]: any }?)
	local status, def = CodesService.Check(userId, raw)
	if status ~= "ok" or def == nil then
		return status, nil
	end
	local codes = section(userId)
	if not codes then
		return "invalid", nil
	end
	codes.redeemed[CodesService.Normalize(raw)] = true
	return "ok", table.clone(def.reward)
end

return CodesService
