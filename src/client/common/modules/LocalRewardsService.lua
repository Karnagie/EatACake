--[[
	LocalRewardsService — view-model mapping for the daily reward window (R2,
	logic only, no React, no .Connect). Turns server payload snapshots into
	DayCard props for UIKit.RewardsPanel; AppRoot renders them.
	Each card carries an `iconName` (Theme.Icons key) for its reward kind — and
	for a BOOST, for its specific boostId: the track hands out several different
	boosts now, so one generic "x2 Boost" label would advertise the wrong perk.

	Daily state machine (per card):
	  claimable — day == current and claimable
	  claimed   — day < current, or the seam: `claimable == false` means
	              exactly "claimed today", so prev(current) is claimed even
	              across the Day N -> Day 1 loop boundary
	  tomorrow  — the day that unlocks on the next UTC day
	  locked    — everything else
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local LocalRewardsService = {}

local SCOPE = "LocalRewardsService"

local locale

function LocalRewardsService.Init(data)
	locale = data.LocaleData
end

-- Reward kind -> Theme.Icons name. Art carries the reward far faster than
-- "+250 Gems" does, which is the whole point of the landscape card.
local REWARD_ICON = {
	gems = "UiGem",
	calories = "UiCoins",
	boost = "UiBoost",
}

-- boostId -> the label key + art for ITS card. There used to be one boost in
-- the game and every "boost" descriptor rendered as one generic "x2 Boost" with
-- one icon; with four of them the login track would advertise the wrong perk.
-- Ids are TreasureConfig.boosts keys (ShopData grants them by the same id), and
-- an unknown one falls back to the generic label rather than rendering a blank.
--
-- `key` is the DAY-CARD label, which is not always the boost's canonical name:
-- the reward line lives in a 96px zone beside the art, so ~9 characters is the
-- budget. "boost-15m" therefore points at the generic `label-boost` ("x2
-- Boost", 8) rather than its own `boost-15m` ("x2 Calories", 11) — the same
-- perk, three characters cheaper.
local BOOST_CARD = {
	["boost-15m"] = { key = "label-boost", icon = "UiBoost" },
	["bite-15m"] = { key = "boost-bite", icon = "UiStrength" },
	["speed-15m"] = { key = "boost-speed", icon = "PassSpeed" },
	["capacity-15m"] = { key = "boost-capacity", icon = "PassStorageX2" },
}

local function boostCard(desc)
	local card = BOOST_CARD[desc.boostId]
	if card == nil then
		-- R8: the card still renders (generic label + generic art), but a boost
		-- the reward tables can hand out and this table has never heard of is a
		-- config drift someone has to fix.
		Log.Once(
			SCOPE,
			`boost-unmapped-{tostring(desc.boostId)}`,
			`reward boost '{tostring(desc.boostId)}' has no entry in BOOST_CARD — the card shows the generic `
				.. "x2 boost label and icon. Add it here when adding a boost to TreasureConfig.boosts."
		)
	end
	return card
end

local function rewardIcon(desc): string?
	if type(desc) ~= "table" then
		return nil
	end
	if desc.kind == "egg" then
		return if desc.eggType == "epic7" then "Egg7" else "Egg1"
	end
	if desc.kind == "boost" then
		local card = boostCard(desc)
		return if card then card.icon else REWARD_ICON.boost
	end
	return REWARD_ICON[desc.kind]
end

local function rewardText(desc): string
	if type(desc) ~= "table" then
		return ""
	end
	if desc.kind == "gems" then
		return locale.T("label-gems-n", { n = desc.amount or 0 })
	end
	if desc.kind == "calories" then
		return locale.T("label-calories-n", { n = desc.amount or 0 })
	end
	if desc.kind == "egg" then
		return locale.T(if desc.eggType == "epic7" then "label-egg-epic" else "label-egg")
	end
	if desc.kind == "boost" then
		local card = boostCard(desc)
		return locale.T(if card then card.key else "label-boost")
	end
	return locale.Tr(desc.name) or tostring(desc.kind)
end

--API
-- daily = { day, claimable, nodes = { [day] = desc } } -> (cards, footerText)
function LocalRewardsService.BuildDailyCards(daily)
	local cards = {}
	if type(daily) ~= "table" then
		return cards, ""
	end
	local current = daily.day or 1
	local daysCount = 0
	for day in pairs(daily.nodes or {}) do
		daysCount = math.max(daysCount, day)
	end
	local function nextDay(day: number): number
		return (daysCount > 0 and day >= daysCount) and 1 or (day + 1)
	end
	local tomorrowDay = if daily.claimable then nextDay(current) else current
	local claimedTodayDay = if not daily.claimable then (current > 1 and current - 1 or daysCount) else nil

	for day = 1, daysCount do
		local desc = daily.nodes[day]
		local state
		if day == current and daily.claimable then
			state = "claimable"
		elseif day == claimedTodayDay then
			state = "claimed"
		elseif day == tomorrowDay then
			state = "tomorrow"
		elseif day < current then
			state = "claimed"
		else
			state = "locked"
		end
		table.insert(cards, {
			id = day,
			title = locale.T("label-day-n", { n = day }),
			rewardText = rewardText(desc),
			iconName = rewardIcon(desc),
			subText = if state == "claimable"
				then locale.T("btn-claim")
				elseif state == "claimed" then locale.T("btn-claimed")
				elseif state == "tomorrow" then locale.T("btn-tomorrow")
				else locale.T("btn-locked"),
			state = state,
		})
	end

	local footer = if daily.claimable then locale.T("footer-daily-claim") else locale.T("footer-daily-tomorrow")
	return cards, footer
end

return LocalRewardsService
