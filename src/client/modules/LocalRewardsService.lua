--[[
	LocalRewardsService — view-model mapping for the reward windows (R2,
	logic only, no React, no .Connect). Turns server payload snapshots into
	DayCard props for UIKit.RewardsPanel; AppRoot renders them.

	Daily state machine (per card):
	  claimable — day == current and claimable
	  claimed   — day < current, or the seam: `claimable == false` means
	              exactly "claimed today", so prev(current) is claimed even
	              across the Day N -> Day 1 loop boundary
	  tomorrow  — the day that unlocks on the next UTC day
	  locked    — everything else

	Time cards: claimed / claimable (elapsed >= threshold) / locked with a
	live countdown (AppRoot ticks a re-render each second while open).
]]

local LocalRewardsService = {}

local locale

function LocalRewardsService.Init(data)
	locale = data.LocaleData
end

--API
-- "m:ss" under an hour, "h:mm:ss" above.
function LocalRewardsService.FormatClock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
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
		return locale.T("label-boost")
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

--API
-- Elapsed-today seconds from a payload snapshot + the receive-time clock.
function LocalRewardsService.ElapsedToday(time): number
	if type(time) ~= "table" then
		return 0
	end
	return (time.secondsToday or 0) + math.max(0, os.clock() - (time.receivedClock or os.clock()))
end

--API
-- time = { secondsToday, receivedClock, claimed = {[index]=true},
--          nodes = {[index]=desc(+seconds)} } -> (cards, footerText)
function LocalRewardsService.BuildTimeCards(time)
	local cards = {}
	if type(time) ~= "table" then
		return cards, ""
	end
	local elapsed = LocalRewardsService.ElapsedToday(time)
	local count = 0
	for index in pairs(time.nodes or {}) do
		count = math.max(count, index)
	end
	for index = 1, count do
		local desc = time.nodes[index]
		local threshold = desc and desc.seconds or 0
		local state, sub
		if time.claimed[index] then
			state = "claimed"
			sub = locale.T("btn-claimed")
		elseif elapsed >= threshold then
			state = "claimable"
			sub = locale.T("btn-claim")
		else
			state = "locked"
			sub = LocalRewardsService.FormatClock(threshold - elapsed)
		end
		table.insert(cards, {
			id = index,
			title = LocalRewardsService.FormatClock(threshold),
			rewardText = rewardText(desc),
			subText = sub,
			state = state,
		})
	end
	local footer = locale.T("footer-time-today", { t = LocalRewardsService.FormatClock(elapsed) })
	return cards, footer
end

--API
-- Any milestone reached and unclaimed right now? (HUD badge.)
function LocalRewardsService.AnyTimeClaimable(time): boolean
	if type(time) ~= "table" then
		return false
	end
	local elapsed = LocalRewardsService.ElapsedToday(time)
	for index, desc in pairs(time.nodes or {}) do
		if not time.claimed[index] and elapsed >= (desc.seconds or math.huge) then
			return true
		end
	end
	return false
end

return LocalRewardsService
