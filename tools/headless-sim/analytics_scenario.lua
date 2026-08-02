--!nolint
-- analytics_scenario — proves the analytics pipeline behaves under the limits
-- it was built for, WITHOUT a published place (docs/features/analytics.md).
--
-- Everything interesting about this system is a behaviour under pressure: a
-- rate limit, a priority reserve, a coalescing window, a trust boundary, a
-- teleport that splits a funnel in half. None of that is visible by reading
-- the code and none of it can be tested in Studio, where AnalyticsService
-- refuses every call. So it is tested here, against the REAL modules.
--
--   python tools/headless-sim/build_sim.py && luau tools/headless-sim/sim.luau
--   (with SCENARIO_FILE=analytics_scenario.lua)

local AnalyticsConfig = __REGISTRY["Shared.config.AnalyticsConfig"]
local Sink = __REGISTRY["Server.subscriptions.Analytics.Sink"]
local Session = __REGISTRY["Server.subscriptions.Analytics.Session"]
local Ingest = __REGISTRY["Server.subscriptions.Analytics.Ingest"]

local failures = 0
local checks = 0
local function check(label: string, condition: boolean, detail: string?)
	checks += 1
	if condition then
		print(string.format("  ok   %s", label))
	else
		failures += 1
		print(string.format("  FAIL %s%s", label, if detail then ` — {detail}` else ""))
	end
end
local function section(title: string)
	print("")
	print("── " .. title .. " " .. string.rep("─", math.max(0, 60 - #title)))
end

local function counts()
	return #__ANALYTICS.custom, #__ANALYTICS.funnel, #__ANALYTICS.onboarding, #__ANALYTICS.economy
end
local function resetRecorder()
	__ANALYTICS.custom = {}
	__ANALYTICS.funnel = {}
	__ANALYTICS.onboarding = {}
	__ANALYTICS.economy = {}
end

-- A profile store stand-in: SessionLoadCount is what decides the cohort.
local profiles = { sessions = {} }
Session.Init({ PlayerProfileData = profiles })

-- ════════════════════════════════════════════════════════════════════════
section("catalog fits the platform quotas")
do
	local ok, report, problems = AnalyticsConfig.Validate()
	check("Validate() passes", ok, table.concat(problems, "; "))
	print("       " .. report)
	local limits = AnalyticsConfig.limits
	local eventCount = 0
	for _ in pairs(AnalyticsConfig.events) do
		eventCount += 1
	end
	check(`event names within {limits.maxCustomEventNames}`, eventCount <= limits.maxCustomEventNames)
	local funnelCount = 0
	for _ in pairs(AnalyticsConfig.funnels) do
		funnelCount += 1
	end
	check(`funnels within {limits.maxFunnels}`, funnelCount <= limits.maxFunnels)
	check(
		"the documented budget is not exceeded (120 + 20/CCU, minus headroom)",
		AnalyticsConfig.BudgetPerMinute(4) <= 120 + 20 * 4
	)
end

-- ════════════════════════════════════════════════════════════════════════
section("the flow funnel spans both places on one session id")
local alice = __newPlayer(101, "Alice")
profiles.sessions[101] = { SessionLoadCount = 1 } -- brand-new account
do
	resetRecorder()
	Sink.Prime()
	local session = Session.Begin(alice)
	check("cohort resolves to 'new' from SessionLoadCount", Session.Cohort(alice) == "new")

	Session.Flow(alice, "join")
	Session.Flow(alice, "spawn")
	Session.Flow(alice, "pad-enter")
	local _, funnels, onboarding = counts()
	check("three flow beats produced three funnel steps", funnels == 3, `got {funnels}`)
	check("a NEW player also feeds the built-in onboarding funnel", onboarding == 3, `got {onboarding}`)

	local sameSession = true
	for _, entry in ipairs(__ANALYTICS.funnel) do
		sameSession = sameSession and entry.sessionId == session.id
	end
	check("every step carries the same funnel session id", sameSession)

	local before = select(2, counts())
	Session.Flow(alice, "join")
	check("a repeated step is refused locally (it would cost rate limit)", select(2, counts()) == before)

	-- The steps must arrive in catalog order, which is what makes the
	-- dashboard's step-to-step conversion meaningful.
	local ordered = __ANALYTICS.funnel[1].step < __ANALYTICS.funnel[2].step
		and __ANALYTICS.funnel[2].step < __ANALYTICS.funnel[3].step
	check("steps are logged in catalog order", ordered)
end

-- ════════════════════════════════════════════════════════════════════════
section("a teleport does not split the funnel")
do
	-- Simulate the handoff: build the payload the lobby attaches, then start a
	-- fresh session on the "game server" and let it adopt.
	local payload = Session.HandoffPayload({ alice })
	check("handoff payload carries one entry per player", #payload == 1)
	check("it is an ARRAY, not a userId-keyed map (teleport data stringifies numeric keys)", payload[1] ~= nil)
	local carriedId = payload[1].s
	local carriedIndex = payload[1].i

	Session.End(alice)
	alice._joinData = { TeleportData = { analytics = payload } }
	resetRecorder()
	local resumed = Session.Begin(alice)
	check("the destination adopts the SAME session id", resumed.id == carriedId, `{resumed.id} vs {carriedId}`)
	check("it also adopts the cohort", Session.Cohort(alice) == "new")

	-- Steps already passed upstream must not be re-logged: the player joins a
	-- second server, so `join`/`spawn` fire again in the game place.
	Session.Flow(alice, "join")
	Session.Flow(alice, "spawn")
	check("steps already passed in the lobby are suppressed", select(2, counts()) == 0)
	check("the resume point is the carried index", resumed.flowBase == carriedIndex)

	Session.Flow(alice, "arrive")
	check("a LATER step still fires", select(2, counts()) == 1)
end

-- ════════════════════════════════════════════════════════════════════════
section("every tap is affordable: coalescing")
do
	resetRecorder()
	Sink.Prime()
	local before = Sink.Stats().tokens
	for _ = 1, 40 do
		Sink.Custom(alice, "ui-press", 1, { "StartButton", "Matchmaking", "lobby" }, {
			tier = "bulk",
			coalesce = true,
		})
	end
	check("40 identical taps spend NO budget while buffered", Sink.Stats().tokens == before)
	check("they are held as ONE pending entry", Sink.Stats().pending == 1, `pending {Sink.Stats().pending}`)
	local customBefore = select(1, counts())
	Sink.Flush(os.clock(), true)
	local sent = select(1, counts()) - customBefore
	check("the flush emits ONE event, not 40", sent == 1, `sent {sent}`)
	local entry = __ANALYTICS.custom[#__ANALYTICS.custom]
	check("its value carries the full count", entry.value == 40, `value {entry.value}`)
	check("the control id rides a custom field, not the event name", entry.name == "ui_press")
	local fieldCount = 0
	for _ in pairs(entry.fields) do
		fieldCount += 1
	end
	check("at most 3 custom fields are sent", fieldCount <= AnalyticsConfig.limits.maxCustomFields)

	-- Distinct controls must NOT merge, or every button would report as one.
	Sink.Custom(alice, "ui-press", 1, { "CloseButton", "Shop", "lobby" }, { tier = "bulk", coalesce = true })
	Sink.Custom(alice, "ui-press", 1, { "StartButton", "Shop", "lobby" }, { tier = "bulk", coalesce = true })
	check("different controls stay separate", Sink.Stats().pending == 2, `pending {Sink.Stats().pending}`)
	Sink.Flush(os.clock(), true)
end

-- ════════════════════════════════════════════════════════════════════════
section("under pressure, the funnel outranks the firehose")
do
	resetRecorder()
	Sink.Prime()
	local capacity = Sink.Stats().capacity
	-- Burn down to just under the bulk reserve (50% of the minute's budget).
	local target = math.floor(capacity * AnalyticsConfig.tiers.bulk.reserve01)
	local burned = 0
	while Sink.Stats().tokens > target and burned < capacity + 10 do
		Sink.Custom(alice, "bite", 1, nil, { tier = "normal" })
		burned += 1
	end
	check("budget can be spent down to the bulk reserve", Sink.Stats().tokens <= target)

	local customBefore = select(1, counts())
	local bulkOk = Sink.Custom(alice, "ui-press", 1, { "Spam", "Hud", "game" }, { tier = "bulk" })
	check("BULK traffic is refused below its reserve", bulkOk == false)
	check("...and really did not send", select(1, counts()) == customBefore)

	local criticalOk = Sink.Custom(alice, "flow-step", 1, { "first-bite", "new", "game" }, { tier = "critical" })
	check("CRITICAL traffic still lands", criticalOk == true)
	check("dropped events are COUNTED, not forgotten", Sink.Stats().dropped > 0)
end

-- ════════════════════════════════════════════════════════════════════════
section("the client may only assert what the server cannot see")
do
	resetRecorder()
	Sink.Prime()
	local bob = __newPlayer(202, "Bob")
	profiles.sessions[202] = { SessionLoadCount = 7 } -- a veteran
	Session.Begin(bob)
	check("a returning player is the 'returning' cohort", Session.Cohort(bob) == "returning")

	Ingest.OnBeat(bob, { { k = "flow", a = "slides-skip" } })
	check("a client-observable flow step is accepted", select(2, counts()) == 1)

	local before = select(2, counts())
	-- These are server-observable and must never be trusted from a client.
	Ingest.OnBeat(bob, { { k = "flow", a = "first-bite" } })
	Ingest.OnBeat(bob, { { k = "flow", a = "match-win" } })
	Ingest.OnBeat(bob, { { k = "flow", a = "first-upgrade" } })
	check("server-observable flow steps are REFUSED from a client", select(2, counts()) == before)

	local customBefore = select(1, counts())
	Ingest.OnBeat(bob, { { k = "not-a-real-kind", a = "x" } })
	Ingest.OnBeat(bob, "not even a table")
	Ingest.OnBeat(bob, { { k = "press" } }) -- no control id
	check("malformed / unknown beats are dropped without throwing", select(1, counts()) == customBefore)

	-- A veteran must not feed the lifetime onboarding funnel.
	local onboardBefore = select(3, counts())
	Session.Flow(bob, "join")
	check("a returning player does NOT spend budget on the onboarding funnel", select(3, counts()) == onboardBefore)

	-- Field values are clamped: an unbounded value would eat the
	-- experience-wide 8000-unique-value budget.
	Ingest.OnBeat(bob, { { k = "press", a = string.rep("A", 400), b = "Hud" } })
	Sink.Flush(os.clock(), true)
	local last = __ANALYTICS.custom[#__ANALYTICS.custom]
	local longest = 0
	for _, value in pairs(last.fields) do
		longest = math.max(longest, #value)
	end
	check(
		`field values are clamped to {AnalyticsConfig.limits.maxFieldValueChars} chars`,
		longest <= AnalyticsConfig.limits.maxFieldValueChars,
		`longest {longest}`
	)
end

-- ════════════════════════════════════════════════════════════════════════
section("a flooding client cannot burn the server's budget")
do
	resetRecorder()
	Sink.Prime()
	local mallory = __newPlayer(303, "Mallory")
	profiles.sessions[303] = { SessionLoadCount = 2 }
	Session.Begin(mallory)

	local batch = {}
	for index = 1, 200 do
		table.insert(batch, { k = "press", a = "Spam" .. tostring(index), b = "Hud" })
	end
	-- Stats are cumulative for the server's life, so measure the DELTA.
	local acceptedBefore = Ingest.Stats().accepted
	Ingest.OnBeat(mallory, batch)
	local accepted = Ingest.Stats().accepted - acceptedBefore
	check(
		`one message admits at most {AnalyticsConfig.beat.maxPerMessage} beats`,
		accepted <= AnalyticsConfig.beat.maxPerMessage,
		`accepted {accepted}`
	)

	-- Empty the per-player message bucket, then prove the next call is refused.
	for _ = 1, AnalyticsConfig.beat.messageBurst + 4 do
		Ingest.OnBeat(mallory, { { k = "press", a = "Spam", b = "Hud" } })
	end
	check("message-rate refusals are counted", Ingest.Stats().refused > 0)
end

-- ════════════════════════════════════════════════════════════════════════
section("confusion is measurable: stalls and abandonment")
do
	resetRecorder()
	Sink.Prime()
	local carol = __newPlayer(404, "Carol")
	profiles.sessions[404] = { SessionLoadCount = 1 }
	local session = Session.Begin(carol)
	Session.Flow(carol, "join")
	Session.Flow(carol, "spawn") -- stallSeconds = 30

	resetRecorder()
	Session.CheckStalls(os.clock())
	check("a player who just arrived does not count as stalled", select(1, counts()) == 0)

	-- Pretend they have been standing on this step for ten minutes.
	session.flowAt = os.clock() - 600
	Session.CheckStalls(os.clock())
	local stalled = false
	for _, entry in ipairs(__ANALYTICS.custom) do
		stalled = stalled or entry.name == "flow_stall"
	end
	check("blowing the step's patience budget fires flow_stall", stalled)

	resetRecorder()
	Session.CheckStalls(os.clock())
	check("...exactly once, not on every tick", select(1, counts()) == 0)

	resetRecorder()
	Session.ReportExit(carol, false)
	local abandoned = false
	for _, entry in ipairs(__ANALYTICS.custom) do
		abandoned = abandoned or entry.name == "flow_abandon"
	end
	check("leaving mid-flow is recorded as an abandonment", abandoned)

	resetRecorder()
	Session.Flow(carol, "hud-ready")
	Session.ReportExit(carol, true) -- handed off
	local wrongly = false
	for _, entry in ipairs(__ANALYTICS.custom) do
		wrongly = wrongly or entry.name == "flow_abandon"
	end
	check("a TELEPORT is not an abandonment (the flow continues elsewhere)", not wrongly)
end

-- ════════════════════════════════════════════════════════════════════════
section("recurring funnels count every attempt")
do
	resetRecorder()
	Sink.Prime()
	local dave = __newPlayer(505, "Dave")
	profiles.sessions[505] = { SessionLoadCount = 3 }
	Session.Begin(dave)

	Session.Funnel(dave, "shop", "open")
	Session.Funnel(dave, "shop", "tab")
	local firstVisit = __ANALYTICS.funnel[1].sessionId
	Session.Funnel(dave, "shop", "open") -- second visit
	Session.Funnel(dave, "shop", "tab")
	local secondVisit = __ANALYTICS.funnel[#__ANALYTICS.funnel].sessionId
	check("a second shop visit is logged at all", select(2, counts()) == 4, `got {select(2, counts())}`)
	check("...under a NEW funnel session id", firstVisit ~= secondVisit)
end

-- ════════════════════════════════════════════════════════════════════════
section("economy events use Roblox's own vocabulary")
do
	resetRecorder()
	Sink.Prime()
	Sink.Economy(
		alice,
		"source",
		AnalyticsConfig.economy.currencies.calories,
		250,
		1000,
		AnalyticsConfig.economy.transactions.gameplay,
		"gym-drain",
		{ "new", "touch", "game" }
	)
	check("a source is logged", select(4, counts()) == 1)
	local entry = __ANALYTICS.economy[1]
	check("flow type is the Source enum", entry.flow ~= nil and entry.flow.Name == "Source")
	check("currency comes from the catalog", entry.currency == "Calories")
	check("transaction type comes from the catalog", entry.transaction == "Gameplay")

	local before = select(4, counts())
	Sink.Economy(alice, "sink", "Gems", 0, 10, "Shop", "x", nil)
	Sink.Economy(alice, "sink", "Gems", -5, 10, "Shop", "x", nil)
	Sink.Economy(alice, "sink", "Gems", 0 / 0, 10, "Shop", "x", nil)
	check("zero / negative / NaN movements are refused", select(4, counts()) == before)
end

-- ════════════════════════════════════════════════════════════════════════
section("regressions found by adversarial review 2026-08-02")
do
	resetRecorder()
	Sink.Prime()
	local erin = __newPlayer(606, "Erin")
	profiles.sessions[606] = { SessionLoadCount = 4 }
	Session.Begin(erin)

	-- (1) The drop REPORT used to hand LogCustomEvent a positional array,
	-- which throws — and three of those disable the sink for the server, with
	-- a warn blaming Studio. The stub now enforces the Dictionary cast, so a
	-- regression here fails loudly instead of passing.
	Sink.Custom(erin, "ui-press", 1, { "Spam", "Hud", "game" }, { tier = "bulk" }) -- seed a drop
	local capacity = Sink.Stats().capacity
	while Sink.Stats().tokens > capacity * 0.5 do
		Sink.Custom(erin, "bite", 1, nil, { tier = "normal" })
	end
	Sink.Custom(erin, "ui-press", 1, { "Spam", "Hud", "game" }, { tier = "bulk" }) -- refused -> counted
	check("a drop was recorded", Sink.Stats().dropped > 0)
	resetRecorder()
	local lost = Sink.ReportDrops(erin)
	check("the drop report emits", lost > 0)
	check("...and did NOT disable the sink", Sink.IsDisabled() == false)
	local report = __ANALYTICS.custom[#__ANALYTICS.custom]
	check("the report reached the recorder", report ~= nil and report.name == "analytics_dropped")

	-- (2) It also used to clear the counts BEFORE checking it could send —
	-- and drops only happen when the budget is empty, so the report was
	-- discarded exactly when it mattered.
	Sink.Custom(erin, "ui-press", 1, { "Spam2", "Hud", "game" }, { tier = "bulk" })
	while Sink.Stats().tokens > capacity * 0.5 do
		Sink.Custom(erin, "bite", 1, nil, { tier = "normal" })
	end
	Sink.Custom(erin, "ui-press", 1, { "Spam2", "Hud", "game" }, { tier = "bulk" })
	local pendingDrops = Sink.Stats().dropped
	Sink.ReportDrops(nil) -- no witness available
	check("with no player to log against, the counts are KEPT", Sink.Stats().dropped == pendingDrops)

	-- (3) A client may not assert a conversion step.
	resetRecorder()
	local before = select(2, counts())
	Ingest.OnBeat(erin, { { k = "funnel", a = "shop", b = "bought" } })
	Ingest.OnBeat(erin, { { k = "shop", a = "bought", b = "starterpack" } })
	Ingest.OnBeat(erin, { { k = "funnel", a = "upgrades", b = "bought" } })
	check("a client CANNOT assert a purchase/conversion step", select(2, counts()) == before)
	Ingest.OnBeat(erin, { { k = "funnel", a = "shop", b = "tab" } })
	check("...but browsing steps still work", select(2, counts()) == before + 1)

	-- (4) Field-value CARDINALITY, not just length: unbounded distinct values
	-- would eat the experience-wide 8000-value budget.
	resetRecorder()
	local frank = __newPlayer(707, "Frank")
	profiles.sessions[707] = { SessionLoadCount = 9 }
	Session.Begin(frank)
	-- BATCHED: the per-player message budget is 3/s (burst 8), so one beat per
	-- message would run out of messages long before it ran out of values.
	local sent = 0
	-- Just over the cap: enough to prove the fold, few enough that the whole
	-- coalescing buffer fits in one primed bucket (a forced flush with no
	-- budget DROPS entries, which would hide the "other" row).
	local wanted = AnalyticsConfig.beat.maxDistinctValuesPerPlayer + 10
	while sent < wanted do
		local batch = {}
		for _ = 1, AnalyticsConfig.beat.maxPerMessage do
			sent += 1
			table.insert(batch, { k = "press", a = "Ctl" .. tostring(sent), b = "Hud" })
		end
		Ingest.OnBeat(frank, batch)
	end
	Sink.Prime()
	Sink.Flush(os.clock(), true)
	local distinct = {}
	local sawOther = false
	for _, entry in ipairs(__ANALYTICS.custom) do
		-- Filtered by PLAYER: the cap is per-player, and this forced flush also
		-- drains coalesced entries other test players left in the buffer.
		if entry.name == "ui_press" and entry.player == frank then
			for _, value in pairs(entry.fields) do
				distinct[value] = true
				sawOther = sawOther or value == "other"
			end
		end
	end
	local total = 0
	for _ in pairs(distinct) do
		total += 1
	end
	check("distinct field values per player are capped", total <= AnalyticsConfig.beat.maxDistinctValuesPerPlayer + 4, `saw {total}`)
	check("...and the excess is folded into 'other'", sawOther)

	-- (5) A hold is a MEASUREMENT and must never be merged.
	resetRecorder()
	Sink.Prime()
	-- A fresh player: Frank's per-player message budget is spent by the
	-- cardinality loop above.
	local grace = __newPlayer(808, "Grace")
	profiles.sessions[808] = { SessionLoadCount = 5 }
	Session.Begin(grace)
	Ingest.OnBeat(grace, {
		{ k = "hold", a = "EatButton", b = "world", v = 6 },
		{ k = "hold", a = "EatButton", b = "world", v = 6 },
	})
	Sink.Flush(os.clock(), true)
	local holds, worst = 0, 0
	for _, entry in ipairs(__ANALYTICS.custom) do
		if entry.name == "ui_hold" then
			holds += 1
			worst = math.max(worst, entry.value)
		end
	end
	check("two 6s holds stay two events", holds == 2, `got {holds}`)
	check("...neither reports an impossible 12s press", worst == 6, `worst {worst}`)

	-- (6) Every pad visit is its own matchmaking attempt.
	resetRecorder()
	Session.Funnel(frank, "queue", "enter")
	Session.Funnel(frank, "queue", "selector")
	local firstQueue = __ANALYTICS.funnel[1].sessionId
	Session.Funnel(frank, "queue", "enter")
	Session.Funnel(frank, "queue", "selector")
	check("a second pad visit is logged", select(2, counts()) == 4, `got {select(2, counts())}`)
	check("...under a new attempt id", __ANALYTICS.funnel[#__ANALYTICS.funnel].sessionId ~= firstQueue)
end

-- ════════════════════════════════════════════════════════════════════════
section("an unpublished place turns telemetry off, quietly and once")
do
	-- MUST BE LAST: `disabled` is sticky for the life of the server, which is
	-- the whole point (Studio would otherwise spam the console forever).
	resetRecorder()
	Sink.Prime()
	__ANALYTICS.fail = true
	__ANALYTICS.failMessage = "AnalyticsService is not available for this place"
	check("the sink starts enabled", Sink.IsDisabled() == false)
	for _ = 1, 5 do
		Sink.Custom(alice, "bite", 1, nil, { tier = "critical" })
	end
	check("three consecutive failures disable it", Sink.IsDisabled() == true)
	local callsBefore = __ANALYTICS.calls
	for _ = 1, 20 do
		Sink.Custom(alice, "bite", 1, nil, { tier = "critical" })
		Session.Flow(alice, "match-win")
	end
	check("nothing is attempted after that", __ANALYTICS.calls == callsBefore)
	check("and nothing threw", true)
end

-- ════════════════════════════════════════════════════════════════════════
print("")
print(string.rep("═", 64))
if failures == 0 then
	print(string.format("ANALYTICS PIPELINE: %d/%d checks passed", checks, checks))
else
	print(string.format("ANALYTICS PIPELINE: %d of %d checks FAILED", failures, checks))
end
print(string.rep("═", 64))
flushLog()
