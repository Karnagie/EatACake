--[[
	MusicService — the background-music playlist (client, R2: logic only).

	Tracks are PLACE-AUTHORED Sound instances under
	`SoundService.<AudioConfig.musicFolder>`; this module never creates or
	names a track. It shuffles them into a bag, plays one at a time with a
	fade in/out and a gap between, and routes every track through the
	`GameMusic` SoundGroup so the `music-enabled` setting can mute it in one
	place. Tuning: AudioConfig.music. Feature doc: docs/features/audio.md.

	Driven by AudioSubsClient's render step (R4 — no .Connect here, and the
	fade needs a per-frame lerp anyway).

	FIRST-NOTE CONTRACT: playback does NOT start until the player's saved
	`music-enabled` is known (SettingsSubsClient calls SetEnabled), so a
	"music off" player never hears a second of music at spawn. If the setting
	never arrives, the grace window expires, R8-warns and starts on the
	default (ON) rather than leaving the game silent forever. SoundPool applies
	the same gate to SFX.
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local AudioConfig = require(Shared:WaitForChild("config"):WaitForChild("AudioConfig"))

local SCOPE = "MusicService"
local START_GRACE = 1 -- seconds before a fresh track's IsPlaying is trusted
local LOAD_TIMEOUT = 15 -- seconds; a track that never streams is skipped, not hung on

local MusicService = {}

local group: SoundGroup? = nil
local tracks: { Sound } = {}
local baseVolume: { [Sound]: number } = {}
local bag: { Sound } = {} -- shuffled queue, refilled when drained
local current: Sound? = nil
local elapsed = 0 -- seconds the current track has been playing
local gapLeft = 0
local lastPlayed: Sound? = nil
local enabled = true
local settingsKnown = false
local graceElapsed = 0
local lastScanAt = -math.huge -- re-probe cadence while the folder is still empty

local function musicFolder(): Instance?
	return SoundService:FindFirstChild(AudioConfig.musicFolder)
end

local function collectTracks(): number
	lastScanAt = os.clock()
	table.clear(tracks)
	table.clear(bag)
	local folder = musicFolder()
	if folder == nil then
		return 0
	end
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("Sound") then
			table.insert(tracks, descendant)
			-- The authored Volume is the track's mix level; the fade owns `.Volume`
			-- from here on. Capture it ONCE — a re-scan after playback started would
			-- otherwise capture the faded value (often 0) and silence that track for
			-- the rest of the session.
			if baseVolume[descendant] == nil then
				baseVolume[descendant] = descendant.Volume
			end
			descendant.Looped = false
			descendant.SoundGroup = group
			descendant.Volume = 0
		end
	end
	table.sort(tracks, function(a, b)
		return a.Name < b.Name -- stable order in; the bag does the shuffling
	end)
	return #tracks
end

-- Refill the shuffled bag. The first track of a new bag is never the one that
-- just played, so a 2-track playlist can't repeat across the seam.
local function refillBag()
	table.clear(bag)
	-- `startNext` pops from the END, so fill in REVERSE: with shuffle off the
	-- playlist then runs in authored order, not backwards.
	for k = #tracks, 1, -1 do
		table.insert(bag, tracks[k])
	end
	if not AudioConfig.music.shuffle then
		return
	end
	for k = #bag, 2, -1 do
		local j = math.random(k)
		bag[k], bag[j] = bag[j], bag[k]
	end
	if #bag > 1 and bag[#bag] == lastPlayed then
		bag[#bag], bag[1] = bag[1], bag[#bag]
	end
end

local function stopCurrent()
	if current then
		current:Stop()
		current.Volume = 0
		current = nil
	end
	elapsed = 0
end

local function startNext()
	if #tracks == 0 then
		return
	end
	if #bag == 0 then
		refillBag()
	end
	local track = table.remove(bag)
	if track == nil or track.Parent == nil then
		-- A track was removed from the folder at runtime. Drop it from the index so
		-- the bag cannot rebuild around a dead entry every frame.
		Log.Once(SCOPE, "music-track-vanished", "a music track disappeared from the folder — re-indexing the playlist")
		collectTracks()
		return
	end
	current = track
	lastPlayed = track
	elapsed = 0
	track.TimePosition = 0
	track.Volume = 0
	track:Play()
	Log.Info(SCOPE, `now playing '{track.Name}'`)
end

function MusicService.Init()
	group = Instance.new("SoundGroup")
	group.Name = AudioConfig.groups.music
	group.Volume = 1
	group.Parent = SoundService

	local count = collectTracks()
	if count == 0 then
		-- Side-effect-free predicate: the healing re-scan lives in Step (below), so
		-- recovery does not depend on a warning being scheduled.
		Log.GraceOnce(SCOPE, "no-music-folder", 10, function()
			return #tracks == 0
		end, `SoundService.{AudioConfig.musicFolder} has no Sound instances — the game will have NO music (docs/features/audio.md: the folder is place content and must exist in BOTH places)`)
	else
		Log.Info(SCOPE, `{count} music track(s) indexed from SoundService.{AudioConfig.musicFolder}`)
	end
end

--API
-- Applies the `music-enabled` setting. The FIRST call also releases the
-- start gate — see the first-note contract in the header.
function MusicService.SetEnabled(on: boolean)
	settingsKnown = true
	local wanted = on == true
	if wanted == enabled and (wanted == false or current ~= nil) then
		return
	end
	enabled = wanted
	if group then
		group.Volume = if enabled then 1 else 0
	end
	if not enabled then
		stopCurrent()
		gapLeft = 0
	end
end

--API
function MusicService.IsEnabled(): boolean
	return enabled
end

--API
-- Per-frame playlist + fade step (driven by AudioSubsClient).
function MusicService.Step(dt: number)
	if not settingsKnown then
		graceElapsed += dt
		if graceElapsed < AudioConfig.settingsGraceSeconds then
			return
		end
		settingsKnown = true
		Log.Once(
			SCOPE,
			"settings-never-arrived",
			`no SettingsUpdate within {AudioConfig.settingsGraceSeconds}s — starting music on the default (ON); check SettingsSubs`
		)
	end
	if not enabled then
		return
	end
	if #tracks == 0 then
		-- Nothing indexed yet: re-probe on a cadence so a folder that replicates
		-- late (or is authored live in Studio) heals without a rejoin.
		if os.clock() - lastScanAt >= AudioConfig.music.rescanSeconds then
			collectTracks()
		end
		return
	end

	local track = current
	if track == nil then
		gapLeft -= dt
		if gapLeft <= 0 then
			startNext()
		end
		return
	end

	elapsed += dt
	local fade = math.max(AudioConfig.music.fadeSeconds, 0.01)
	local base = (baseVolume[track] or 0) * AudioConfig.music.volume
	local length = track.TimeLength
	local target = base * math.clamp(elapsed / fade, 0, 1)
	if length > 0 then
		local remaining = length - track.TimePosition
		target = math.min(target, base * math.clamp(remaining / fade, 0, 1))
	end
	track.Volume = target

	-- Advance. `IsPlaying` is false while a track is still STREAMING, so on a
	-- slow connection judging by it alone would skip the whole playlist in
	-- seconds — wait for `IsLoaded` first. A track that never streams at all is
	-- skipped once the load timeout expires (R8) rather than hanging the
	-- playlist on it forever.
	if elapsed <= START_GRACE then
		return
	end
	if not track.IsLoaded then
		if elapsed > LOAD_TIMEOUT then
			Log.Once(SCOPE, `music-load-{track.Name}`, `music track '{track.Name}' never loaded within {LOAD_TIMEOUT}s — skipped`)
			stopCurrent()
			gapLeft = AudioConfig.music.gapSeconds
		end
		return
	end
	if not track.IsPlaying then
		stopCurrent()
		gapLeft = AudioConfig.music.gapSeconds
	end
end

return MusicService
