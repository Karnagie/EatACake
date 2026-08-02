--[[
	AnalyticsConfig — THE analytics catalog (shared, loaded by both sides).

	Every funnel, every funnel step, every custom event name and every rate
	constant lives HERE and nowhere else. Code never passes a literal event
	name to AnalyticsService; it passes a catalog key, so a typo is a loud
	`Validate()` failure at boot instead of a metric that silently never
	appears on the dashboard 90 days later.

	⚠ WHY THIS FILE EXISTS AT ALL — Roblox analytics is a QUOTA'd product.
	Verified 2026-08-02 against create.roblox.com/docs/production/analytics
	(event-types, custom-events, funnel-events) and the staff answer in
	devforum thread 3084051:

	  | rate limit          | 120 + (20 x CCU) events per MINUTE, per server |
	  | custom event names  | 100 per experience (cardinality, resets daily) |
	  | funnels             | 10 names x 100 steps                           |
	  | custom fields       | 3 per event, 8000 combined unique VALUES       |
	  | economy             | 10 currencies, 20 transaction types, 100 SKUs  |
	  | retention           | 90 days from the last data received            |
	  | where               | SERVER only, PUBLISHED places only             |

	A solo game server is allowed 140 events/min — a bit over two per second.
	"Track every tap" therefore cannot mean "one event name per button": it
	means ONE event name (`ui_press`) carrying the control id in a custom
	field, spent out of a budget (Analytics/Sink.lua). Roblox's own docs say
	it outright: "use custom fields whenever possible instead of event names,
	since there is a much tighter cardinality limit on event names".

	Steps are declared ONCE (`flowSteps`) and drive BOTH the built-in
	onboarding funnel (lifetime, per player, de-duped by Roblox) and the
	`PlayerFlow` custom funnel (per SESSION, so it measures returning players
	too). One list = the two funnels can never drift apart.
]]

local AnalyticsConfig = {}

-- ── platform quotas ─────────────────────────────────────────────────────
AnalyticsConfig.limits = {
	-- The documented budget. `safety01` is the fraction of it we actually
	-- spend: overshooting earns "AnalyticsService: You have sent too many
	-- events" and the overflow is DROPPED SILENTLY by the platform, which is
	-- exactly the failure mode R8 forbids. We would rather drop knowingly.
	eventsPerMinuteBase = 120,
	eventsPerMinutePerPlayer = 20,
	safety01 = 0.75,
	maxCustomEventNames = 100,
	maxFunnels = 10,
	maxFunnelSteps = 100,
	maxCustomFields = 3,
	-- Field VALUES are free-form, but 8000 combined unique values across all
	-- three fields become "Other" — so values must be bounded vocabularies
	-- (a control id, a difficulty, a reason), never user text or ids.
	maxFieldValueChars = 40,
}

-- ── priority tiers ──────────────────────────────────────────────────────
-- The budget is spent top-down. When it runs low the sink protects the
-- signal that cannot be reconstructed (a funnel step happens once) and
-- sheds the signal that is merely dense (taps, bites) — and reports how
-- much it shed, because an undercount presented as a count is a lie.
AnalyticsConfig.tiers = {
	-- always sent while any budget remains
	critical = { rank = 1, reserve01 = 0 },
	-- sent while >15% of the minute's budget is left
	normal = { rank = 2, reserve01 = 0.15 },
	-- sent while >50% is left; this is where raw taps live
	bulk = { rank = 3, reserve01 = 0.5 },
}

-- ── the initial player flow ─────────────────────────────────────────────
-- The beats of a first session IN ORDER, from the join to the first cleared
-- cake. This is the answer to "where do players get confused and what do
-- they never finish": anything with a cliff in front of it is the problem.
--
--   key        stable id used in code and as the `flow_step` field value
--   name       the human label on the Creator Dashboard
--   place      where it can fire ("lobby" | "game" | "any") — routing only
--   optional   true = not every healthy player hits it (tutorial-only
--              beats), so a gap under it is not automatically a leak
--   stallSeconds  how long a player may sit on this step before it counts
--              as CONFUSION and emits `flow_stall`. nil = never stalls.
AnalyticsConfig.flowSteps = {
	{ key = "join", name = "Joined", place = "any" },
	{ key = "spawn", name = "Character Spawned", place = "any", stallSeconds = 30 },
	{ key = "hud-ready", name = "HUD Ready", place = "any", stallSeconds = 30 },
	{ key = "pad-approach", name = "Approached A Pad", place = "lobby", stallSeconds = 90 },
	{ key = "pad-enter", name = "Stood On A Pad", place = "lobby", stallSeconds = 60 },
	{ key = "selector-open", name = "Match Selector Opened", place = "lobby", stallSeconds = 30 },
	{ key = "difficulty-pick", name = "Difficulty Chosen", place = "lobby", stallSeconds = 45 },
	{ key = "party-pick", name = "Party Size Chosen", place = "lobby", stallSeconds = 45 },
	{ key = "start-press", name = "Start Pressed", place = "lobby", stallSeconds = 60 },
	{ key = "countdown", name = "Countdown Started", place = "lobby", stallSeconds = 60 },
	{ key = "launch", name = "Match Launched", place = "lobby", stallSeconds = 45 },
	{ key = "teleport", name = "Teleport Started", place = "lobby", stallSeconds = 60 },
	{ key = "arrive", name = "Arrived In Game", place = "game", stallSeconds = 45 },
	{ key = "match-start", name = "Match Started", place = "game", stallSeconds = 60 },
	{ key = "slides", name = "Story Slides Shown", place = "game", stallSeconds = 120 },
	{ key = "slides-skip", name = "Slides Skipped", place = "game", stallSeconds = 60 },
	{ key = "eat-hint", name = "Eat Hint Shown", place = "game", optional = true, stallSeconds = 90 },
	{ key = "first-bite", name = "First Bite", place = "game", stallSeconds = 120 },
	{ key = "eat-hint-clear", name = "Eat Hint Cleared", place = "game", optional = true },
	{ key = "first-find", name = "First Find Collected", place = "game", optional = true },
	{ key = "first-layer", name = "First Layer Cleared", place = "game", stallSeconds = 600 },
	{ key = "belly-full", name = "Belly Full", place = "game", stallSeconds = 600 },
	{ key = "checkpoint", name = "Reached The Checkpoint", place = "game", stallSeconds = 180 },
	{ key = "gym-start", name = "Fat Burn Started", place = "game", stallSeconds = 120 },
	{ key = "first-gym", name = "First Fat Burned", place = "game", stallSeconds = 120 },
	{ key = "upgrades-open", name = "Upgrade Tree Opened", place = "game", stallSeconds = 180 },
	{ key = "first-upgrade", name = "First Upgrade Bought", place = "game", stallSeconds = 120 },
	{ key = "tutorial-done", name = "Tutorial Completed", place = "game", optional = true },
	{ key = "boss", name = "Boss Reached", place = "game" },
	{ key = "match-win", name = "Match Won", place = "game" },
	{ key = "return-lobby", name = "Returned To Lobby", place = "lobby" },
}

-- ── funnels ─────────────────────────────────────────────────────────────
-- At most 10 NAMES exist per experience and the limit is enforced by silent
-- drops, so two slots stay deliberately EMPTY for whatever the next feature
-- needs. `session` says how the funnelSessionId is derived:
--   "flow"    the cross-place analytics session (survives the teleport)
--   "round"   the round id (one match)
--   "visit"   a fresh id per ATTEMPT — landing on the funnel's first step
--             opens a new one (pads, shop/upgrades/gym/find visits all recur)
AnalyticsConfig.funnels = {
	flow = {
		name = "PlayerFlow",
		session = "flow",
		-- steps come from flowSteps; filled in below
	},
	queue = {
		name = "Matchmaking",
		-- "visit", not a mode of its own: a player who steps on three pads is
		-- three matchmaking ATTEMPTS. It briefly had a `queue` mode that
		-- nothing implemented, which meant only the first pad visit per player
		-- was ever counted and the conversion rate was computed over
		-- first-visits alone.
		session = "visit",
		steps = {
			{ key = "enter", name = "Stood On A Pad" },
			{ key = "selector", name = "Selector Opened" },
			{ key = "difficulty", name = "Difficulty Chosen" },
			{ key = "party", name = "Party Size Chosen" },
			{ key = "start", name = "Start Pressed" },
			{ key = "countdown", name = "Countdown Running" },
			{ key = "launch", name = "Roster Launched" },
			{ key = "sent", name = "Teleport Sent" },
		},
	},
	tutorial = {
		name = "Tutorial",
		session = "flow",
		steps = {
			{ key = "slides", name = "Slides Shown" },
			{ key = "skip", name = "Slides Skipped" },
			{ key = "eat", name = "Eat Hint Shown" },
			{ key = "bite", name = "First Bite Landed" },
			{ key = "belly", name = "Belly Filled" },
			{ key = "path", name = "Guidance Beam Shown" },
			{ key = "arrived", name = "Reached The Checkpoint" },
			{ key = "upgrades", name = "Opened The Computer" },
			{ key = "done", name = "Tutorial Completed" },
		},
	},
	match = {
		name = "Match",
		session = "round",
		steps = {
			{ key = "arrive", name = "Arrived" },
			{ key = "start", name = "Match Started" },
			{ key = "bite", name = "First Bite" },
			{ key = "layer", name = "First Layer Cleared" },
			{ key = "gym", name = "First Fat Burned" },
			{ key = "upgrade", name = "First Upgrade" },
			{ key = "half", name = "Half The Cake" },
			{ key = "boss", name = "Boss Reached" },
			{ key = "win", name = "Boss Defeated" },
			{ key = "return", name = "Returned To Lobby" },
		},
	},
	shop = {
		name = "Shop",
		session = "visit",
		steps = {
			{ key = "open", name = "Shop Opened" },
			{ key = "tab", name = "Tab Viewed" },
			{ key = "card", name = "Item Tapped" },
			{ key = "prompt", name = "Purchase Prompted" },
			{ key = "bought", name = "Purchase Completed" },
		},
	},
	upgrades = {
		name = "Upgrades",
		session = "visit",
		steps = {
			{ key = "open", name = "Tree Opened" },
			{ key = "select", name = "Node Selected" },
			{ key = "attempt", name = "Buy Attempted" },
			{ key = "bought", name = "Tier Bought" },
		},
	},
	gym = {
		name = "GymBurn",
		session = "visit",
		steps = {
			{ key = "near", name = "Reached The Gym" },
			{ key = "start", name = "Burn Started" },
			{ key = "tap", name = "Tapped To Burn" },
			{ key = "banked", name = "Calories Banked" },
		},
	},
	find = {
		name = "Finds",
		session = "visit",
		steps = {
			{ key = "glint", name = "Find Revealed" },
			{ key = "uncovered", name = "Find Uncovered" },
			{ key = "collected", name = "Find Collected" },
		},
	},
}

-- `flow` shares the ONE ordered step list, so the custom funnel and the
-- built-in onboarding funnel can never disagree about what step 12 is.
AnalyticsConfig.funnels.flow.steps = AnalyticsConfig.flowSteps

-- ── custom event names ──────────────────────────────────────────────────
-- 100 names exist for the whole experience, FOREVER, and a name is spent the
-- first time it is sent. Anything that varies per press/item/reason is a
-- FIELD VALUE, not a name. Keys are kebab-case (CLAUDE.md); the values are
-- the snake_case names the dashboard shows.
AnalyticsConfig.events = {
	-- session + flow
	["session-start"] = "session_start",
	["place-minutes-lobby"] = "place_minutes_lobby",
	["place-minutes-game"] = "place_minutes_game",
	-- value = SECONDS SPENT on the previous step. This one event answers
	-- "which step is slow" for every step at once.
	["flow-step"] = "flow_step",
	-- the confusion signal: still on this step past its stallSeconds budget
	["flow-stall"] = "flow_stall",
	-- left without finishing; field = the last step they did reach
	["flow-abandon"] = "flow_abandon",

	-- raw interaction (the "every tap" layer)
	["ui-press"] = "ui_press",
	-- pressed something that could not respond: a DISABLED button, or a
	-- control whose handler declined (the EAT button under an input lock).
	-- High-signal for "they tried and the game said nothing".
	["ui-dead-press"] = "ui_dead_press",
	["ui-panel"] = "ui_panel",
	["ui-hold"] = "ui_hold",

	-- lobby + matchmaking
	["pad-approach"] = "pad_approach",
	["pad-enter"] = "pad_enter",
	["pad-exit"] = "pad_exit",
	["queue-configure"] = "queue_configure",
	["queue-error"] = "queue_error",
	["queue-launch"] = "queue_launch",
	["queue-abandon"] = "queue_abandon",

	-- handoff
	["teleport-start"] = "teleport_start",
	["teleport-fail"] = "teleport_fail",
	["teleport-recovered"] = "teleport_recovered",

	-- match
	["match-arrive"] = "match_arrive",
	["match-start"] = "match_start",
	["match-reject"] = "match_reject",
	["match-end"] = "match_end",
	["boss-start"] = "boss_start",
	["boss-end"] = "boss_end",

	-- tutorial
	["tutorial-step"] = "tutorial_step",
	["tutorial-skip"] = "tutorial_skip",
	["tutorial-done"] = "tutorial_done",

	-- gameplay loop counters (the funnel's denominators)
	["bite"] = "bite",
	["find-collected"] = "find_collected",
	["layer-cleared"] = "layer_cleared",
	["gym-banked"] = "gym_banked",
	["upgrade-bought"] = "upgrade_bought",

	-- monetization
	["shop-open"] = "shop_open",
	["shop-tab"] = "shop_tab",
	["shop-card"] = "shop_card",
	["purchase-prompt"] = "purchase_prompt",
	["purchase-result"] = "purchase_result",

	-- instrumentation health (R8: the telemetry reports its own losses)
	["analytics-dropped"] = "analytics_dropped",
	["client-error"] = "client_error",
}

-- ── economy vocabulary ──────────────────────────────────────────────────
-- 10 currencies / 20 transaction types / 100 SKUs before the dashboard
-- groups the rest as "Other". These are the only strings allowed through.
AnalyticsConfig.economy = {
	currencies = {
		calories = "Calories",
		gems = "Gems",
		robux = "Robux",
	},
	-- Roblox's own transactionType vocabulary; anything else pollutes the
	-- 20-value budget with a name that means the same thing.
	transactions = {
		iap = "IAP",
		shop = "Shop",
		gameplay = "Gameplay",
		contextual = "ContextualPurchase",
		timed = "TimedReward",
		onboarding = "Onboarding",
	},
}

-- ── client -> server beat protocol ──────────────────────────────────────
-- The client cannot call AnalyticsService (server + published places only),
-- so every tap has to make one hop. It is a firehose pointed at a rate
-- limit, so it is batched, bounded, and validated like any other remote (R6).
AnalyticsConfig.beat = {
	flushSeconds = 2, -- normal cadence
	-- A funnel-critical beat jumps the queue — but never faster than the
	-- server will admit messages. At 0.15s a player working through the
	-- matchmaking panel could push 4 messages/s past a 3/s gate, and the
	-- server drops the WHOLE message (up to 24 beats, funnel steps included).
	-- Kept strictly above 1/messagesPerSecond.
	urgentFlushSeconds = 0.4,
	maxQueued = 120, -- client-side backstop; overflow is counted, not kept
	maxPerMessage = 24,
	-- server-side per-player admission (R6). A modded client can fire this
	-- remote as fast as it likes; it buys nothing but it must not be able to
	-- burn the SERVER's analytics budget or its own CPU share.
	messagesPerSecond = 3,
	messageBurst = 8,
	beatsPerMinute = 240,
	-- How many DISTINCT field values one player may introduce per session
	-- before the rest are folded into "other". The experience-wide budget is
	-- 8000 unique values across all three fields, shared by every server and
	-- every player, and everything past it becomes "Other" — permanently, for
	-- the 90-day retention window. One modded client sending a fresh id per
	-- beat at the legal rate would exhaust it in about half an hour and take
	-- every honest breakdown in the game down with it. A real player touches a
	-- few dozen distinct controls in a session, so this is invisible to them.
	maxDistinctValuesPerPlayer = 80,
}

-- ── client-side watchers ────────────────────────────────────────────────
AnalyticsConfig.client = {
	-- How close counts as "approached the starting area" without stepping on
	-- it. The gap between this beat and `pad-enter` is the answer to "do they
	-- see the pads at all, or do they see them and not understand them".
	padApproachStuds = 30,
	-- One throttled loop drives the panel watcher, the pad watcher and the
	-- flush pump. Panels live for seconds, so polling beats a callback chain.
	pollSeconds = 0.25,
	-- Re-resolve the authored pads this often: LobbyMap is place content and
	-- can replicate long after the client starts (ADR-0007).
	padRescanSeconds = 5,
}

-- ── what the client is TRUSTED to assert ────────────────────────────────
-- R6 applies to telemetry too. A modded client cannot gain anything by lying
-- to analytics, but it can POISON the one dataset the game's design
-- decisions are made from, which is worth exactly as much care as a
-- currency remote. The rule: the client may only assert beats the SERVER
-- CANNOT SEE FOR ITSELF. Everything the server can observe — bites,
-- purchases, teleports, arrivals, gym banks, layer clears — is logged where
-- it actually happens and is silently refused from a client.
AnalyticsConfig.clientFlowSteps = {
	["hud-ready"] = true, -- the React root mounted; only the client knows
	["pad-approach"] = true, -- walked NEAR a pad without stepping on it
	-- The two selections live entirely inside MatchmakingPanel's local state
	-- and never reach the server unless START is pressed — which is exactly
	-- why they matter: a player who picks a difficulty and then leaves is
	-- invisible to the server and is the single most interesting drop-off in
	-- the lobby.
	["difficulty-pick"] = true,
	["party-pick"] = true,
	-- Pressed START. Not the same as the server accepting it: a press that
	-- is throttled or lands on a stale session never arrives, and that gap
	-- (start-press without countdown) is a bug report nobody had to file.
	["start-press"] = true,
	["slides"] = true, -- the comic board rendered
	["slides-skip"] = true, -- SKIP pressed
	["eat-hint"] = true, -- the instruction popup rendered
	["eat-hint-clear"] = true, -- popup dismissed
	["checkpoint"] = true, -- stood on the plate (BodySubsClient owns the test)
	["upgrades-open"] = true, -- the hex tree overlay opened
}

-- Per-STEP, not per-funnel. A funnel-wide allow-list looks tight and is not:
-- `shop` and `upgrades` both END in a conversion step (`bought`), so allowing
-- the funnel wholesale would have let a modded client assert "Purchase
-- Completed" — the one number in the game that must never be assertable.
AnalyticsConfig.clientFunnels = {
	-- The two SELECTIONS and the START press live entirely inside the
	-- matchmaking panel's local state and never reach the server unless the
	-- server accepts a configure. Everything else in this funnel (enter,
	-- selector, countdown, launch, sent) is server-observed and refused here.
	queue = { difficulty = true, party = true, start = true },
	-- the whole tutorial flow is client-driven by design
	tutorial = { slides = true, skip = true, eat = true, belly = true, path = true, arrived = true, upgrades = true },
	-- browsing is client-side; `prompt` and `bought` are logged by ShopSubs
	shop = { open = true, tab = true, card = true },
	-- opening/selecting; `attempt` and `bought` are logged by UpgradeSubs
	upgrades = { open = true, select = true },
	-- the glint is a client-side marker; the collection is server-observed
	find = { glint = true },
}

-- Beat kinds a client may send at all. Anything else is dropped with one
-- warn — an unknown kind is either a stale client or someone probing.
AnalyticsConfig.clientBeatKinds = {
	press = true, -- a kit button was pressed
	["dead-press"] = true, -- ...one that could not respond
	panel = true, -- a panel opened/closed
	hold = true, -- a hold button was released (value = seconds)
	flow = true, -- a clientFlowSteps beat
	funnel = true, -- a clientFunnels step
	tutorial = true, -- tutorial step + dwell
	shop = true, -- shop browse events
	platform = true, -- once per session: input device + screen class
	error = true, -- a client-side failure worth counting
}

-- ── derived lookups ─────────────────────────────────────────────────────
local flowIndex: { [string]: number } = {}
for index, step in ipairs(AnalyticsConfig.flowSteps) do
	flowIndex[step.key] = index
end

--API
-- 1-based position of a flow step, or nil when the key is unknown.
function AnalyticsConfig.FlowIndex(key: string): number?
	return flowIndex[key]
end

--API
function AnalyticsConfig.FlowStep(key: string)
	local index = flowIndex[key]
	return if index then AnalyticsConfig.flowSteps[index] else nil
end

--API
-- The dashboard name for a catalog key. Returns nil for an unknown key so
-- the caller can warn instead of inventing a name (which would silently
-- burn one of the 100 slots).
function AnalyticsConfig.Event(key: string): string?
	return AnalyticsConfig.events[key]
end

--API
-- The events-per-minute this server may actually spend right now.
function AnalyticsConfig.BudgetPerMinute(playerCount: number): number
	local limits = AnalyticsConfig.limits
	local raw = limits.eventsPerMinuteBase + limits.eventsPerMinutePerPlayer * math.max(0, playerCount)
	return math.max(1, math.floor(raw * limits.safety01))
end

--API
-- Asserts the catalog still fits inside the platform quotas and returns
-- (ok, report, problems). Called once at Start and printed (R8): a catalog
-- that has quietly outgrown the limits loses data on the SERVER SIDE of
-- Roblox with no error at the call site, which is unfindable at runtime.
function AnalyticsConfig.Validate(): (boolean, string, { string })
	local limits = AnalyticsConfig.limits
	local problems = {}

	local eventCount = 0
	local seenNames = {}
	for key, name in pairs(AnalyticsConfig.events) do
		eventCount += 1
		if type(name) ~= "string" or name == "" then
			table.insert(problems, `event '{key}' has no name`)
		elseif seenNames[name] then
			table.insert(problems, `event name '{name}' is used by two keys ('{key}' and '{seenNames[name]}')`)
		else
			seenNames[name] = key
		end
	end
	if eventCount > limits.maxCustomEventNames then
		table.insert(problems, `{eventCount} custom event names exceeds the {limits.maxCustomEventNames} allowed`)
	end

	local funnelCount, worstSteps = 0, 0
	local seenFunnelNames = {}
	for key, funnel in pairs(AnalyticsConfig.funnels) do
		funnelCount += 1
		if type(funnel.name) ~= "string" or funnel.name == "" then
			table.insert(problems, `funnel '{key}' has no name`)
		elseif seenFunnelNames[funnel.name] then
			table.insert(problems, `funnel name '{funnel.name}' is used twice`)
		else
			seenFunnelNames[funnel.name] = true
		end
		local steps = funnel.steps or {}
		if #steps == 0 then
			table.insert(problems, `funnel '{key}' has no steps`)
		end
		if #steps > limits.maxFunnelSteps then
			table.insert(problems, `funnel '{key}' has {#steps} steps (max {limits.maxFunnelSteps})`)
		end
		worstSteps = math.max(worstSteps, #steps)
		local seenStepKeys = {}
		for _, step in ipairs(steps) do
			if seenStepKeys[step.key] then
				table.insert(problems, `funnel '{key}' repeats step key '{step.key}'`)
			end
			seenStepKeys[step.key] = true
		end
	end
	if funnelCount > limits.maxFunnels then
		table.insert(problems, `{funnelCount} funnels exceeds the {limits.maxFunnels} allowed (excess funnels are DROPPED silently)`)
	end

	local report = `{eventCount}/{limits.maxCustomEventNames} event names, `
		.. `{funnelCount}/{limits.maxFunnels} funnels, `
		.. `longest funnel {worstSteps}/{limits.maxFunnelSteps} steps, `
		.. `{#AnalyticsConfig.flowSteps} flow beats`
	return #problems == 0, report, problems
end

return AnalyticsConfig
