--[[
	SoundPool — every SFX the client plays (GDD §7.7).

	Pooled 2D voices created ONCE at Init (zero Instance.new in hot paths),
	round-robin, pitch jittered ±10%, combo raises bite pitch. One dedicated
	looping voice carries the granular slump channel whose volume follows
	avalanche energy (§7.4 — the game's signature sound).

	The SAMPLES are place-authored Sound instances under
	`ReplicatedStorage.<AudioConfig.sfxFolder>` (any nesting); this module
	resolves them BY NAME and copies SoundId/Volume/PlaybackSpeed onto a pooled
	voice. Keys, shaping and the name contract live in AudioConfig.sounds —
	nothing here hardcodes an asset. Feature doc: docs/features/audio.md.

	SETTINGS GATE: the group starts MUTED and opens on the first SetEnabled, so a
	player who saved `sfx-enabled = false` never hears the first seconds of a
	session (the same contract MusicService documents for the first note). If the
	setting never arrives the grace expires, R8-warns and unmutes on the default.

	R8: a missing folder, a missing sample name and a duplicate sample name each
	warn ONCE with a pointer; the cue is then skipped rather than crashing, and
	the folder is re-probed periodically so a late-replicating library heals
	itself (no blocking WaitForChild in feature flow).

	Templates that carry SoundEffect children (a PitchShiftSoundEffect etc.)
	cannot be represented by a bare pooled voice — those get ONE dedicated clone
	each, so the authored effect chain survives (at the cost of no overlap).
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local AudioConfig = require(Shared:WaitForChild("config"):WaitForChild("AudioConfig"))

local SCOPE = "SoundPool"
local REBUILD_COOLDOWN = 5 -- seconds between bank rebuilds after a miss

local SoundPool = {}

local group: SoundGroup? = nil
local pool: { Sound } = {}
local stamps: { [Sound]: number } = {} -- cut-generation guard per voice
local cursor = 1
local bank: { [string]: Sound } = {} -- authored template by instance name
local effectful: { [Sound]: boolean } = {} -- memoised "carries a SoundEffect?"
local dedicated: { [string]: Sound } = {} -- clones for effect-carrying templates
local lastBuildAt = -math.huge
local lastPlayAt: { [string]: number } = {} -- throttle bookkeeping per key
local slumpVoice: Sound? = nil
local slumpTargetVolume = 0
local slumpStarted = false -- the loop only starts once there IS avalanche energy
local enabled = true
local settingsKnown = false -- muted until the saved `sfx-enabled` arrives

-- ── the authored bank ───────────────────────────────────────────────────

local function sfxFolder(): Instance?
	return ReplicatedStorage:FindFirstChild(AudioConfig.sfxFolder)
end

-- Index every Sound under the authored folder by NAME. Rebuilt (at most every
-- REBUILD_COOLDOWN) when a lookup misses, so a library that replicates late —
-- or one the developer edits live in Studio — heals without a restart.
local function buildBank(): number
	lastBuildAt = os.clock()
	table.clear(bank)
	table.clear(effectful)
	local folder = sfxFolder()
	if folder == nil then
		return 0
	end
	local count, duplicates = 0, 0
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("Sound") then
			if bank[descendant.Name] ~= nil then
				duplicates += 1
				Log.Once(
					SCOPE,
					`dup-sfx-{descendant.Name}`,
					`two Sounds named '{descendant.Name}' under ReplicatedStorage.{AudioConfig.sfxFolder} — the first wins; rename one (docs/features/audio.md)`
				)
			else
				bank[descendant.Name] = descendant
				count += 1
			end
		end
	end
	if duplicates > 0 then
		Log.Warn(SCOPE, `bank rebuilt with {count} sample(s), {duplicates} duplicate name(s) ignored`)
	end
	return count
end

local function template(name: string): Sound?
	local found = bank[name]
	if found ~= nil and found.Parent ~= nil then
		return found
	end
	if os.clock() - lastBuildAt >= REBUILD_COOLDOWN then
		buildBank()
		found = bank[name]
	end
	return found
end

-- Effect-carrying templates need their own instance (a pooled voice has no
-- effect chain). Cloned once, re-triggered on each play.
local function dedicatedVoice(name: string, source: Sound): Sound
	local existing = dedicated[name]
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local clone = source:Clone()
	clone.Name = `Dedicated_{name}`
	clone.Looped = false
	clone.SoundGroup = group
	clone.Parent = SoundService
	-- Only cache it once it is actually routed through the group; a clone cached
	-- with SoundGroup = nil (play before Init) would be deaf to SetEnabled forever.
	if group ~= nil then
		dedicated[name] = clone
	end
	return clone
end

-- MEMOISED: Play runs at bite rate, and `GetDescendants` allocates a table on
-- every call. A template's effect chain is authored, not runtime, so the answer
-- is stable for as long as the instance lives (buildBank drops the cache with
-- the bank it belongs to).
local function hasEffects(sound: Sound): boolean
	local cached = effectful[sound]
	if cached ~= nil then
		return cached
	end
	local found = false
	for _, descendant in ipairs(sound:GetDescendants()) do
		if descendant:IsA("SoundEffect") then
			found = true
			break
		end
	end
	effectful[sound] = found
	return found
end

-- ── lifecycle ───────────────────────────────────────────────────────────

function SoundPool.Init()
	group = Instance.new("SoundGroup")
	group.Name = AudioConfig.groups.sfx
	group.Volume = 0 -- muted until the saved `sfx-enabled` arrives (settings gate)
	group.Parent = SoundService

	-- Never leave the game permanently silent because a settings push was lost.
	task.delay(AudioConfig.settingsGraceSeconds, function()
		if settingsKnown then
			return
		end
		Log.Once(
			SCOPE,
			"sfx-settings-never-arrived",
			`no SettingsUpdate within {AudioConfig.settingsGraceSeconds}s — unmuting SFX on the default (ON); check SettingsSubs`
		)
		SoundPool.SetEnabled(true)
	end)

	for k = 1, AudioConfig.poolSize do
		local voice = Instance.new("Sound")
		voice.Name = `Pooled_{k}`
		voice.SoundGroup = group
		voice.Parent = SoundService
		stamps[voice] = 0
		table.insert(pool, voice)
	end

	local count = buildBank()
	if count == 0 then
		-- A silent game is exactly the "dangerous silent state" R8 exists for.
		-- Deferred + non-blocking: only warn if the library really never shows.
		Log.GraceOnce(SCOPE, "no-sfx-folder", 10, function()
			return buildBank() == 0
		end, `ReplicatedStorage.{AudioConfig.sfxFolder} has no Sound instances — the game will be SILENT (docs/features/audio.md: the folder is place content and must exist in BOTH places)`)
	else
		Log.Info(SCOPE, `{count} authored sample(s) indexed from ReplicatedStorage.{AudioConfig.sfxFolder}`)
	end

	-- Slump channel: a dedicated looping voice, started silent. Its volume is
	-- driven every frame from avalanche energy (Step).
	local slumpDef = AudioConfig.sounds[AudioConfig.slump.key]
	local slumpTemplate = if slumpDef ~= nil then template(slumpDef.asset) else nil
	if slumpTemplate == nil then
		Log.Once(
			SCOPE,
			"no-slump-loop",
			`slump loop sample '{slumpDef and slumpDef.asset or AudioConfig.slump.key}' not found — cake avalanches will be silent`
		)
	else
		local voice = slumpTemplate:Clone()
		voice.Name = "SlumpLoop"
		voice.Looped = true
		voice.Volume = 0
		voice.PlaybackSpeed = slumpTemplate.PlaybackSpeed * (slumpDef.pitch or 1)
		voice.SoundGroup = group
		voice.Parent = SoundService
		-- NOT played here: this module runs in the lobby too, where nothing ever
		-- feeds it energy — an inaudible loop would still stream forever. Started
		-- lazily on the first avalanche (Step).
		slumpVoice = voice
	end

	-- R8: a cue that never fires must be explainable from the console. An
	-- `enabled = false` key is deliberate, but silence is indistinguishable from a
	-- broken sample unless we say so once at boot.
	local off = {}
	for key, def in pairs(AudioConfig.sounds) do
		if def.enabled == false then
			table.insert(off, key)
		end
	end
	if #off > 0 then
		table.sort(off)
		Log.Sum(SCOPE, `{#off} sound(s) DISABLED in AudioConfig (intentional, not missing): {table.concat(off, ", ")}`)
	end
end

--API
-- Mutes/unmutes every SFX voice (the `sfx-enabled` setting). One group volume
-- covers pooled voices, dedicated clones and the slump loop.
function SoundPool.SetEnabled(on: boolean)
	settingsKnown = true
	enabled = on == true
	if group then
		group.Volume = if enabled then 1 else 0
	end
end

--API
function SoundPool.IsEnabled(): boolean
	return enabled
end

-- ── playback ────────────────────────────────────────────────────────────

--API
-- Plays an AudioConfig.sounds key. opts: { pitchMult, volumeMult }.
function SoundPool.Play(key: string, opts: { pitchMult: number?, volumeMult: number? }?)
	if not enabled then
		return -- muted: skip the lookup/voice churn entirely, not just the output
	end
	local def = AudioConfig.sounds[key]
	if def == nil then
		Log.Once(SCOPE, `no-key-{key}`, `unknown sound key '{key}' — add it to AudioConfig.sounds`)
		return
	end
	if def.enabled == false then
		return -- switched off in AudioConfig on purpose; Init already reported it (R8)
	end
	local now = os.clock()
	if def.throttle then
		local previous = lastPlayAt[key]
		if previous ~= nil and now - previous < def.throttle then
			return
		end
	end
	local source = template(def.asset)
	if source == nil then
		Log.Once(
			SCOPE,
			`no-asset-{def.asset}`,
			`sound '{key}' wants a Sound named '{def.asset}' under ReplicatedStorage.{AudioConfig.sfxFolder} — not found, cue skipped (docs/features/audio.md)`
		)
		return
	end
	lastPlayAt[key] = now

	-- Effect-carrying samples keep their own instance; everything else rides a
	-- pooled voice (SoundId swap, no allocation).
	local voice: Sound
	if hasEffects(source) then
		voice = dedicatedVoice(def.asset, source)
	else
		if #pool == 0 then
			-- Play before Init: the voices do not exist yet. Without this the
			-- round-robin divides by zero and the cue errors instead of just
			-- being missing (R8: say why, then degrade).
			Log.Once(SCOPE, "play-before-init", `sound '{key}' played before SoundPool.Init — no voices exist yet, cue dropped`)
			return
		end
		voice = pool[cursor]
		cursor = cursor % #pool + 1
		voice.SoundId = source.SoundId
	end

	local jitter = 1 + (math.random() * 2 - 1) * AudioConfig.pitchJitter
	voice:Stop()
	voice.Volume = source.Volume * (def.volume or 1) * ((opts and opts.volumeMult) or 1)
	voice.PlaybackSpeed = source.PlaybackSpeed
		* (def.pitch or 1)
		* jitter
		* ((opts and opts.pitchMult) or 1)
	voice.TimePosition = 0
	voice:Play()

	-- `cut` turns a long library sample into a crisp cue. The stamp guards the
	-- deferred stop: if this voice has since been reused for another cue, the old
	-- timer must not cut the new sound short. Bump it on EVERY play — including
	-- cues with no `cut` — or a pending timer from a previous cue survives the
	-- reuse and truncates an uncut celebration sound.
	local stamp = (stamps[voice] or 0) + 1
	stamps[voice] = stamp
	if def.cut then
		task.delay(def.cut, function()
			if stamps[voice] == stamp then
				voice:Stop()
			end
		end)
	end
end

--API
-- Bite SFX with the combo pitch ramp (§7.5).
function SoundPool.PlayBite(key: string, combo: number)
	SoundPool.Play(key, { pitchMult = 1 + AudioConfig.comboPitchPerStep * math.max(0, combo - 1) })
end

--API
-- Feeds avalanche energy (studs³) into the granular loop volume.
-- Peak-hold: deltas arrive at ~12 Hz while this is called every frame with
-- mostly-zero energy — overwriting would starve the loop to silence.
function SoundPool.PushSlumpEnergy(studs3: number)
	if studs3 > 0 then
		slumpTargetVolume = math.max(
			slumpTargetVolume,
			math.clamp(studs3 / AudioConfig.slump.volumeDiv, 0, AudioConfig.slump.maxVolume)
		)
	end
end

--API
-- Per-frame decay/lerp of the slump loop (called by CakeSubsClient).
function SoundPool.Step(dt: number)
	if slumpVoice == nil then
		return
	end
	if not slumpStarted then
		if slumpTargetVolume <= 0 then
			return -- no cake has slumped yet; don't stream the loop (lobby)
		end
		slumpStarted = true
		slumpVoice:Play()
	end
	local v = slumpVoice.Volume
	slumpVoice.Volume = v + (slumpTargetVolume - v) * math.min(1, dt * 6)
	slumpTargetVolume = math.max(0, slumpTargetVolume - dt * AudioConfig.slump.decayPerSecond)
end

return SoundPool
