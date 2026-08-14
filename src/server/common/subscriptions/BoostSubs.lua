--[[
	BoostSubs — keeps every DERIVED value in sync with the player's live timed
	boost set, on GRANT and on EXPIRY (COMMON: runs in BOTH places).

	A boost is nothing but a row in `progress.activeBoosts` with an `expiresAt`;
	no event fires when that timestamp passes. Stats READ per use need no help —
	the next read of CaloriesMult/GemsMult simply stops finding the boost. The
	three stats added with the gem-shop boosts are different: they are PUSHED or
	APPLIED once and then STICK until something rewrites them.
	  biteRadius — the CLIENT predicts craters from its own copy, so it is
	               mirrored into the `BiteRadiusMult` player attribute
	               (attributes replicate by themselves: no remote, no payload)
	  walkSpeed  — written onto the Humanoid by BodySubs.RefreshBody
	  capacity   — rides the StomachUpdate payload (HUD belly bar + full gate)
	Without this module a bite boost would keep widening the client's predicted
	craters after it expired, and a speed boost would never wear off at all.

	HOW: every Apply arms a one-shot timer on the SOONEST expiresAt, so a boost
	ending is exact rather than up to a tick late (the client would otherwise keep
	predicting boosted craters after the server had already dropped the boost). A
	`TreasureConfig.boostTickSeconds` sweep comparing
	StatsService.BoostSignature(userId) with the last one seen is the BACKSTOP for
	anything the timer misses. Grants don't wait for either — RewardGrantSubs calls
	Apply directly, so a 500-gem purchase does something the same frame.

	R2: no tuning here (the tick lives beside the boost defs in TreasureConfig).
	R3: no service→service call — BodySubs is reached through the subscriptions
	registry and is legitimately nil in the LOBBY partition.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

-- Resolved from the subscriptions registry in Start: BodySubs lives in the GAME
-- partition and is ABSENT in the lobby (same guarded pattern UpgradeSubs uses).
local BodySubs

local SCOPE = "BoostSubs"

local BoostSubs = {}

local services_
-- Wiring state (not game data): last boost signature seen per userId, so the
-- sweep can tell "nothing changed" from "granted / refreshed / expired".
local lastSignature: { [number]: string } = {}
-- Generation stamp per userId. Every Apply bumps it and arms ONE timer for the
-- soonest expiry; a timer whose stamp is stale (a later grant re-armed, or the
-- player left) does nothing. Without it a burst of grants leaves a fan of timers
-- all firing Apply on the same player.
local expiryGeneration: { [number]: number } = {}

-- Number of boosts encoded in a signature ("a@1|b@2" -> 2), used only to say
-- WHICH way the set moved in the log line.
local function countBoosts(signature: string): number
	if signature == "" then
		return 0
	end
	local n = 1
	for _ in string.gmatch(signature, "|") do
		n += 1
	end
	return n
end

--API
-- Re-applies every value a live boost feeds. Idempotent and safe to call at any
-- time; callers do not need to know whether anything actually changed.
-- ⚠ SECOND CALLER since 2026-08-13: `PassOwnershipSubs` runs this after a
-- gamepass purchase and after the join ownership fetch. Boosts are not the only
-- thing that moves capacity and walk speed — `capacity2`/`vip` double the belly
-- too — and this is the one routine that re-derives the PUSHED/APPLIED family
-- (bite mirror, RefreshBody, SendStomach). Keep it caller-agnostic: it must not
-- start assuming the trigger was a boost.
function BoostSubs.Apply(player: Player)
	if services_ == nil then
		-- Before Start, or Start aborted on a missing dependency (below).
		Log.Warn(SCOPE, `Apply({player.Name}) with no services — boosted bite radius / speed / capacity NOT applied`)
		return
	end
	local userId = player.UserId

	-- CLIENT MIRROR (see LocalStatsService): the client predicts craters from the
	-- replicated upgrade LEVELS alone, which know nothing about boosts.
	player:SetAttribute("BiteRadiusMult", services_.StatsService.BoostMult(userId, "biteRadius"))

	-- BodySubs is nil in the LOBBY: no body, no belly and no cake to re-apply to
	-- there. The attribute above is still written, because a boost BOUGHT in the
	-- lobby survives the teleport (RunResetSubs keeps timed boosts) and the game
	-- place re-applies it on arrival.
	if BodySubs ~= nil then
		-- RefreshBody first and SendStomach second, not the other way round:
		-- SendStomach ends in RefreshBody but DROPS the whole push (and so the
		-- refresh) when the profile isn't loaded, and WalkSpeed must be corrected
		-- even then — a speed boost that outlives its timer is a movement exploit.
		BodySubs.RefreshBody(player) -- Humanoid WalkSpeed + the StomachFill attribute
		BodySubs.SendStomach(player) -- re-push capacity to the HUD belly bar
	end

	-- Everything derived is now in sync with THIS boost set, so record it: the
	-- sweep below then stays quiet instead of re-doing (and re-logging) work a
	-- grant already did a fraction of a second earlier.
	lastSignature[userId] = services_.StatsService.BoostSignature(userId)

	-- ON-TIME EXPIRY, not next-tick expiry. The server drops a boost the instant
	-- os.time() passes expiresAt (every stat read prunes), but the client's
	-- BiteRadiusMult only changes when we rewrite it — so a purely periodic sweep
	-- leaves the client predicting craters ~1.96x the authoritative area for up to
	-- a full tick, and over-prediction is the visible one (cake pops back). The
	-- sweep stays as the backstop; this timer is what makes the common case exact.
	local generation = (expiryGeneration[userId] or 0) + 1
	expiryGeneration[userId] = generation
	local expiresAt = services_.StatsService.NextBoostExpiry(userId)
	if expiresAt ~= nil then
		-- os.time() is whole seconds, so land just PAST the boundary rather than on
		-- it: firing at exactly expiresAt can re-read the boost as still live.
		task.delay(math.max(0, expiresAt - os.time()) + 0.05, function()
			if expiryGeneration[userId] ~= generation or player.Parent == nil then
				return -- superseded by a later grant, or the player left
			end
			BoostSubs.Apply(player)
		end)
	end
end

--API
-- Join-state hook: PlayerLifecycleSubs calls this after profile load +
-- ClientReady. Required, not just an optimisation: a boost bought in the lobby
-- survives the handoff, but the game place's Player instance is a FRESH one
-- carrying no attributes at all.
function BoostSubs.PushInitialState(player: Player)
	BoostSubs.Apply(player) -- also seeds the sweep cache, so the first tick is quiet
end

function BoostSubs.Start(data, services, subscriptions)
	BodySubs = subscriptions.BodySubs

	-- Dependency gate BEFORE `services_` is armed, so a degraded boot leaves
	-- Apply warning once per call instead of erroring inside it.
	if services.StatsService == nil or services.PersistenceService == nil then
		Log.Warn(SCOPE, "StatsService/PersistenceService missing — boosts DISABLED (a speed or bite boost would never wear off)")
		return
	end
	local treasureCfg = data.CakeConfigData and data.CakeConfigData.treasures
	if treasureCfg == nil then
		Log.Warn(SCOPE, "CakeConfigData.treasures missing — boosts DISABLED (a speed or bite boost would never wear off)")
		return
	end
	services_ = services

	local tickSeconds = math.max(0.1, tonumber(treasureCfg.boostTickSeconds) or 1)
	if BodySubs == nil then
		Log.Info(SCOPE, "BodySubs absent (lobby partition) — boosts here only write the BiteRadiusMult attribute; speed/capacity are applied in the game place")
	end
	Log.Info(SCOPE, `armed: expiry sweep every {tickSeconds}s (TreasureConfig.boostTickSeconds)`)

	local sweepAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		sweepAcc += dt
		if sweepAcc < tickSeconds then
			return
		end
		sweepAcc = 0
		for _, player in ipairs(Players:GetPlayers()) do
			local userId = player.UserId
			if not services.PersistenceService.IsLoaded(userId) then
				continue -- joining / leaving: no profile, so no boosts to read
			end
			-- Reading the signature also PRUNES the expired entries (StatsService)
			-- — this call is what actually retires them.
			local signature = services.StatsService.BoostSignature(userId)
			local previous = lastSignature[userId] or ""
			if signature ~= previous then
				-- Apply records the new signature (single writer) — so a tick that
				-- somehow failed to apply retries next second instead of going quiet.
				local was, now = countBoosts(previous), countBoosts(signature)
				local verb = "refreshed"
				if now > was then
					verb = "granted"
				elseif now < was then
					verb = "expired"
				end
				Log.Info(SCOPE, `{player.Name}: boost {verb} ({was} -> {now} live) — re-applying bite radius / speed / capacity`)
				BoostSubs.Apply(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSignature[player.UserId] = nil
		-- Cleared, not bumped: leaving a counter per userId leaks for the server's
		-- lifetime. A pending timer then reads nil, fails the generation compare,
		-- and stops — and in the one case where a rejoin could restart the counter
		-- at the same value, the timer's captured Player instance is already
		-- destroyed, so the `player.Parent == nil` check catches it.
		expiryGeneration[player.UserId] = nil
	end)
end

return BoostSubs
