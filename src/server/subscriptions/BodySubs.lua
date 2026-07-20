--[[
	BodySubs — body/gym domain orchestration (R4, GDD §8):
	  * gym fat-DRAIN sessions: GymPrompt start (+ instant-burn) / GymTap remote /
	    the stepHz drain loop that banks calories as the belly empties and STOPS
	    when the player steps away from the machine
	  * auto-gym (full burn) for pass holders + the "burn" reward kind
	  * body replication: "StomachFill" player attribute (clients morph
	    locally) + authoritative WalkSpeed (fullness penalty, caramel slow)

	Cross-subs contract: CakeSubs/UpgradeSubs call RefreshBody(player) after
	anything that changes fill or stats.

	Gym model (see features/body-gym.md + GymService): pressing the prompt opens a
	session that drains the belly from its start fill to 0 — passively (burnSpeed)
	and per TAP (burnPerTap) — banking stored → calories (× gymEff) as it goes.
	The instantBurn upgrade removes a slice on press (final tier = all of it).
	Leaving the machine ends the session and keeps the partially-burned belly.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))

local EconomySubs = require(script.Parent.EconomySubs)
local RewardGrantSubs = require(script.Parent.RewardGrantSubs)

local SCOPE = "BodySubs"

local BodySubs = {}

local services_
local bodyCfg
local stomachCfg
local runtime
local uGym, uStomach

-- Wiring state (not game data): last caramel slow factor per player so
-- RefreshBody between 1 Hz surface checks stays consistent.
local caramelMult: { [Player]: number } = {}

--API
-- Recomputes WalkSpeed + the replicated StomachFill attribute.
function BodySubs.RefreshBody(player: Player)
	if services_ == nil then
		Log.Warn(SCOPE, `RefreshBody({player.Name}) before Start ran — skipped`)
		return
	end
	local userId = player.UserId
	local capacity = services_.StatsService.Capacity(userId)
	local fill01 = services_.StomachService.Fullness(userId, capacity)

	local rounded = math.floor(fill01 * 100 + 0.5) / 100
	if runtime.lastMorphFill[userId] ~= rounded then
		runtime.lastMorphFill[userId] = rounded
		player:SetAttribute("StomachFill", rounded)
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local base = services_.StatsService.WalkSpeed(userId)
		local penalty = 1 - stomachCfg.fullSpeedPenalty * fill01
		humanoid.WalkSpeed = base * penalty * (caramelMult[player] or 1)
	end
end

--API
-- Initial stomach push (lifecycle).
function BodySubs.SendStomach(player: Player)
	if uStomach == nil then
		Log.Warn(SCOPE, `SendStomach({player.Name}) before Start ran — push dropped`)
		return
	end
	local userId = player.UserId
	local stomachState = services_.StomachService.GetState(userId)
	if not stomachState then
		Log.Warn(SCOPE, `SendStomach({player.Name}): profile not loaded — push dropped`)
		return
	end
	stomachState.capacity = services_.StatsService.Capacity(userId)
	stomachState.gained = 0
	uStomach:FireClient(player, stomachState)
	BodySubs.RefreshBody(player)
end

function BodySubs.Start(data, services)
	services_ = services
	bodyCfg = data.CakeConfigData.body
	stomachCfg = bodyCfg.stomach
	runtime = data.PlayerRuntimeData
	local cakeOriginY = data.CakeConfigData.cake.grid.origin.y
	uGym = Net.Update("GymUpdate")
	uStomach = Net.Update("StomachUpdate")

	local gymCfg = bodyCfg.gym
	local stepTick = 1 / math.max(1, gymCfg.stepHz)

	-- Applies a GymService step/instant result: subtracts the drain's OWN delta
	-- from the current belly (so a mid-session bite survives — see GymService),
	-- banks the calorie delta, and resyncs the HUD belly bar + WalkSpeed/morph.
	local function creditResult(player: Player, result)
		local userId = player.UserId
		local state = services.StomachService.GetState(userId)
		if state then
			services.StomachService.SetBelly(userId, state.fill - result.dFill, state.stored - result.dStored)
		end
		if result.bankDelta and result.bankDelta > 0 then
			services.EconomyService.AddCalories(userId, result.bankDelta)
			services.ProgressService.AddStat(userId, "lifetimeCalories", result.bankDelta)
			EconomySubs.SendCurrency(player)
		end
		-- fill/stored changed → HUD belly bar + RefreshBody (speed/morph attr).
		BodySubs.SendStomach(player)
	end

	-- Full instant burn (auto-gym + the "burn" reward): empties the belly at
	-- once and banks stored × gymEff. The manual gym drains gradually instead.
	local function burnAll(player: Player, event: string)
		local userId = player.UserId
		-- Supersede any manual drain session so its baseline can't re-inflate the
		-- belly we're emptying here (the drain rewrites fill from startFill/tick).
		services.GymService.EndSession(userId)
		local banked = services.StomachService.Burn(userId, services.StatsService.GymEfficiency(userId), 1)
		if banked == nil then
			-- Both callers pre-check GetState, so this is defensive — but R8:
			-- never return silently from a missing-profile failure path.
			Log.Once(SCOPE, `burnall-noprofile-{userId}`, `{player.Name}: {event} burn before profile load — skipped`)
			return
		end
		if banked > 0 then
			services.EconomyService.AddCalories(userId, banked)
			services.ProgressService.AddStat(userId, "lifetimeCalories", banked)
			EconomySubs.SendCurrency(player)
		end
		uGym:FireClient(player, { event = event, banked = banked })
		-- Full stomach resync (fill/stored now 0) — includes RefreshBody.
		BodySubs.SendStomach(player)
	end

	-- Gym sessions start from the machine's ProximityPrompt (server-side
	-- event — no client remote to spoof a start from across the map).
	local ProximityPromptService = game:GetService("ProximityPromptService")
	local promptName = data.MapConfigData.checkpoint.promptName
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt.Name ~= promptName then
			return
		end
		local userId = player.UserId
		if not services.PersistenceService.IsLoaded(userId) then
			Log.Once(SCOPE, `gym-preload-{userId}`, `{player.Name}: GymPrompt before profile load — gym start ignored`)
			return
		end
		if services.GymService.HasSession(userId) then
			return -- already burning (re-press) — ignore, don't re-seed instant-burn
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or not services.MapService.NearGym(root.Position) then
			return -- not at a machine (§13 range validation — legit, no log)
		end
		local state = services.StomachService.GetState(userId)
		if not state or state.fill < gymCfg.minStartFill then
			return -- nothing to burn (empty belly) — legit no-op, no session opened
		end
		local gymEff = services.StatsService.GymEfficiency(userId)
		local start =
			services.GymService.StartSession(userId, state.fill, state.stored, services.StatsService.InstantBurn(userId), gymEff)
		creditResult(player, start) -- applies the instant-burn slice (if any)
		if start.complete then
			-- instant-burn maxed (final tier) — whole belly gone on press, no session.
			services.GymService.EndSession(userId)
			uGym:FireClient(player, { event = "instant", banked = start.bankedTotal })
		else
			uGym:FireClient(player, { event = "started" })
			uGym:FireClient(player, { event = "progress", remain01 = 1 - start.burned01 })
		end
	end)

	Net.Remote("GymTap").OnServerEvent:Connect(function(player)
		services.GymService.RegisterTap(player.UserId)
	end)

	-- Reward kind "burn": instant fat burn (dev product) — a full burn anywhere,
	-- no machine needed.
	RewardGrantSubs.Register("burn", function(player: Player, reward, source: string?)
		local stomachState = services.StomachService.GetState(player.UserId)
		if not stomachState then
			return nil
		end
		burnAll(player, "instant")
		return { kind = "burn" }
	end)

	-- Fat-drain loop (stepHz) + auto-gym + 1 Hz surface/caramel check + body
	-- morph lerp (MUST be server-side: runtime part-size changes are reverted by
	-- replication when written client-side).
	local morphCfg = bodyCfg.morph
	local morphTick = 1 / math.max(1, morphCfg.rateHz)
	local drainAcc, surfaceAcc, morphAcc = 0, 0, 0
	-- Natural (unscaled) size of each torso part, captured once on first sight —
	-- so we always scale from the TRUE original, never compound the scaled value.
	-- Pruned (below) when the part is destroyed, so it can't leak.
	local naturalTorso: { [BasePart]: Vector3 } = {}

	-- Only the TORSO parts grow (arms/legs/head keep their natural size). We can't
	-- use Humanoid BodyScale (it scales the WHOLE body); instead we grow the
	-- torso part's `OriginalSize` — the Humanoid auto-scaler enforces
	-- `Size = OriginalSize × BodyScale`, so scaling only the torso's OriginalSize
	-- (BodyScale left alone) grows only the torso and HOLDS. R15: UpperTorso +
	-- LowerTorso; R6: Torso.
	local function torsoParts(character: Model): { BasePart }
		local upper = character:FindFirstChild("UpperTorso") :: BasePart?
		if upper then
			local parts = { upper }
			local lower = character:FindFirstChild("LowerTorso") :: BasePart?
			if lower then
				table.insert(parts, lower)
			end
			return parts
		end
		local torso = character:FindFirstChild("Torso") :: BasePart?
		return if torso then { torso } else {}
	end

	local function stepMorph(player: Player, mdt: number)
		local character = player.Character
		if not character then
			return
		end
		local parts = torsoParts(character)
		if #parts == 0 then
			Log.GraceOnce(SCOPE, `notorso-{player.UserId}`, 2, function()
				local c = player.Character
				return c == nil or #torsoParts(c) == 0
			end, `{player.Name}: no torso part — body morph skipped`)
			return
		end
		local capacity = services_.StatsService.Capacity(player.UserId)
		local fill01 = services_.StomachService.Fullness(player.UserId, capacity)
		local alpha = math.min(1, morphCfg.lerpSpeed * mdt)
		local sx = 1 + (morphCfg.widthScale[2] - 1) * fill01
		local sy = 1 + (morphCfg.heightScale[2] - 1) * fill01
		local sz = 1 + (morphCfg.depthScale[2] - 1) * fill01
		for _, part in ipairs(parts) do
			local orig = part:FindFirstChild("OriginalSize") :: Vector3Value?
			if orig == nil then
				continue -- rig without OriginalSize (R6?) — can't torso-scale it
			end
			local nat = naturalTorso[part]
			if nat == nil then
				nat = orig.Value -- first sight = the natural (unscaled) torso size
				naturalTorso[part] = nat
			end
			local target = Vector3.new(nat.X * sx, nat.Y * sy, nat.Z * sz)
			local cur = part.Size
			-- Snap within minStep (reach full / fully return to natural), else lerp.
			local next_ = if (target - cur).Magnitude <= morphCfg.minStep then target else cur:Lerp(target, alpha)
			if next_ ~= cur then
				orig.Value = next_ -- keep OriginalSize in sync so the auto-scaler won't revert
				part.Size = next_
			end
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		drainAcc += dt
		if drainAcc >= stepTick then
			local mdt = drainAcc
			drainAcc = 0
			for _, player in ipairs(Players:GetPlayers()) do
				local userId = player.UserId
				if not services.PersistenceService.IsLoaded(userId) then
					continue -- profile unloaded (leaving/session-taken): skip gym work
				end
				if services.GymService.HasSession(userId) then
					-- STOP if the player stepped away from the machine (user rule:
					-- "walk away and it all stops"). Keeps the drained belly as-is.
					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if not root or not services.MapService.NearGym(root.Position) then
						services.GymService.EndSession(userId)
						uGym:FireClient(player, { event = "stopped" })
					else
						local result = services.GymService.Advance(
							userId,
							mdt,
							services.StatsService.BurnSpeed(userId),
							services.StatsService.BurnPerTap(userId)
						)
						if result then
							creditResult(player, result)
							if result.complete then
								services.GymService.EndSession(userId)
								uGym:FireClient(player, { event = "result", banked = result.bankedTotal })
							else
								uGym:FireClient(player, { event = "progress", remain01 = 1 - result.burned01 })
							end
						end
					end
				elseif services.StatsService.HasAutoGym(userId) then
					local stomachState = services.StomachService.GetState(userId)
					local last = runtime.lastAutoBurn[userId] or 0
					if
						stomachState
						and stomachState.stored >= gymCfg.minStoredToBurn
						and os.clock() - last >= gymCfg.autoBurnInterval
					then
						runtime.lastAutoBurn[userId] = os.clock()
						burnAll(player, "auto")
					end
				end
			end
		end

		surfaceAcc += dt
		if surfaceAcc >= 1 then
			surfaceAcc = 0
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local mult = 1
				if root then
					local surface = services.CakeFieldService.SurfaceHeightAt(root.Position.X, root.Position.Z)
					-- surface is relative to the cake origin; compare world Y.
					if surface ~= nil and math.abs(root.Position.Y - (cakeOriginY + surface)) < 8 then
						local layer = services.CakeFieldService.SurfaceLayerAt(root.Position.X, root.Position.Z)
						if layer and layer.walkSpeedMult then
							mult = layer.walkSpeedMult
						end
					end
				end
				if caramelMult[player] ~= mult then
					caramelMult[player] = mult
					BodySubs.RefreshBody(player)
				end
			end
		end

		morphAcc += dt
		if morphAcc >= morphTick then
			local mdt = morphAcc
			morphAcc = 0
			for part in pairs(naturalTorso) do
				if part.Parent == nil then -- torso part destroyed (respawn) — drop it
					naturalTorso[part] = nil
				end
			end
			for _, player in ipairs(Players:GetPlayers()) do
				if services.PersistenceService.IsLoaded(player.UserId) then
					stepMorph(player, mdt)
				end
			end
		end
	end)

	-- Respawn keeps the belly: reapply speed + attribute to new characters.
	local function watchCharacter(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(BodySubs.RefreshBody, player)
		end)
	end
	Players.PlayerAdded:Connect(watchCharacter)
	for _, player in ipairs(Players:GetPlayers()) do
		watchCharacter(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		caramelMult[player] = nil
	end)
end

return BodySubs
