--[[
	FoodBurst — the celebration confetti (features/food-burst.md).

	A screen-space burst of food sprites: a whole GROUP (orchard / tropical /
	bakery / candy / creamery) launches from below the bottom edge, arcs to
	roughly mid-screen and falls back off. Fired on every layer clear and,
	bigger, when the Cake Monster dies.

	Shape follows FloatingNumbers: one template built at Init, a fixed pool
	cloned from it (R5), ZERO Instance.new in the fire path. Motion is
	integrated per frame here rather than tweened — each sprite needs its own
	gravity, drift, spin and squash, and five tweens per sprite would be ~240
	live tweens per burst.

	Not React: this is juice, not UI (features/juice.md). It draws in its OWN
	ScreenGui at DisplayOrder 99 — one BELOW UiRoot's 100 — so the food flies in
	front of the world but BEHIND the HUD and the cheer banner. The banner is
	the thing the player must READ; the food is the thing they must FEEL.

	⚠ Every distance is a SCREEN FRACTION, never pixels: `x`/`y` are UDim2 scale
	(y = 0 is the TOP edge) and velocities are screen-heights/second, so the arc
	is identical on a phone and on a monitor. Sprites size on
	`SizeConstraint.RelativeYY`, so a wide screen does not stretch them.

	Tuning + group membership: `JuiceConfig.foodBurst` / `.foodBurstGroups`.
	Stepped by CakeSubsClient (R4 — this module connects nothing itself).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local JuiceConfig = require(Shared:WaitForChild("config"):WaitForChild("JuiceConfig"))
local Theme = require(Shared:WaitForChild("UIKit"):WaitForChild("Theme"))
local Log = require(Shared:WaitForChild("Log"))

local SCOPE = "FoodBurst"

local FoodBurst = {}

type Sprite = {
	label: ImageLabel,
	live: boolean,
	shown: boolean,
	delay: number, -- seconds still to wait before this one launches
	age: number,
	x: number, -- screen fraction across
	y: number, -- screen fraction down (0 = TOP edge)
	vx: number, -- screen heights / s
	vy: number, -- screen heights / s, NEGATIVE is upward
	size: number, -- height as a screen fraction
	spin: number, -- degrees / s
	angle: number,
}

local gui: ScreenGui?
local pool: { Sprite } = {}
local cursor = 1
local liveCount = 0

local function between(range: { number }): number
	return range[1] + (range[2] - range[1]) * math.random()
end

function FoodBurst.Init(data)
	local cfg = JuiceConfig.foodBurst
	-- Place gate, same marker AppRoot uses for `showGame`: only the GAME place
	-- ever clears a layer or fights the Cake Monster, and a lobby that reported
	-- "ready — 80 pooled sprites" would read as a working feature that can never
	-- fire (CakeSubsClient returns before Fire/Step are reachable there).
	if data == nil or data.GameUiData == nil then
		Log.Info(SCOPE, "game client partition absent — celebration bursts not built (lobby)")
		return
	end
	-- A re-Init (Studio reload, or the verification hook in
	-- features/food-burst.md) must reset the ACCOUNTING too. `liveCount` is only
	-- ever decremented under `sprite.live`, so a stale count from the old pool
	-- can never be worked off: it would kill Step's fast path and make
	-- ActiveCount() — the verification hook itself — report phantom sprites
	-- forever.
	gui = nil
	table.clear(pool)
	liveCount = 0
	cursor = 1
	local player = Players.LocalPlayer
	local playerGui = player and player:WaitForChild("PlayerGui", 10)
	if playerGui == nil then
		-- R8: never return silently. Without the ScreenGui every Fire() is a
		-- no-op and the game just quietly stops celebrating.
		Log.Warn(SCOPE, "no PlayerGui after 10s — celebration bursts are DISABLED for this session")
		return
	end

	local previous = playerGui:FindFirstChild("FoodBurst")
	if previous then
		previous:Destroy() -- a re-Init (Studio reload) must not stack two layers
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "FoodBurst"
	screen.ResetOnSpawn = false
	-- Full-bleed on purpose: the sprites LAUNCH from off-screen and must not be
	-- clipped to the safe area on the way in.
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- One below UiRoot (100). The HUD and the cheer banner MUST stay on top.
	screen.DisplayOrder = 99

	-- R5: build ONE view object, clone the rest.
	local proto = Instance.new("ImageLabel")
	proto.Name = "Food"
	proto.BackgroundTransparency = 1
	proto.BorderSizePixel = 0
	proto.AnchorPoint = Vector2.new(0.5, 0.5)
	-- ⚠ `Stretch` (the default), NOT `Fit`. `Fit` preserves the SOURCE image's
	-- aspect and draws it at the shorter side of the frame, so a squashed frame
	-- would only letterbox: the squash & stretch below would never render and
	-- every sprite would draw at ~0.77 of its configured size. The aspect worry
	-- that makes `Fit` tempting is already handled by SizeConstraint.RelativeYY.
	proto.ScaleType = Enum.ScaleType.Stretch
	-- Both axes measured against the parent's HEIGHT, so a 21:9 monitor does
	-- not stretch an apple into a melon.
	proto.SizeConstraint = Enum.SizeConstraint.RelativeYY
	proto.Visible = false
	proto.Image = Theme.Icon("FoodApple")

	for k = 1, cfg.poolSize do
		local label = proto:Clone()
		label.Name = `Food_{k}`
		label.Parent = screen
		pool[k] = {
			label = label,
			live = false,
			shown = false,
			delay = 0,
			age = 0,
			x = 0.5,
			y = 1.2,
			vx = 0,
			vy = 0,
			size = 0.08,
			spin = 0,
			angle = 0,
		}
	end
	proto:Destroy()

	screen.Parent = playerGui
	gui = screen
	Log.Info(SCOPE, `ready — {cfg.poolSize} pooled sprites across {#JuiceConfig.foodBurstGroups} food groups`)
end

--API
-- Fires one burst for a celebration `kind` ("layer" / "monster"), whose size
-- comes from `JuiceConfig.foodBurst.counts`. Every sprite is drawn from ONE
-- food group, so the celebration reads as a theme instead of food soup.
-- `groupId` forces a specific group (dev hook); otherwise the group is rolled.
-- Returns the group id used, or nil if the burst could not run.
function FoodBurst.Fire(kind: string, groupId: string?): string?
	if gui == nil then
		Log.Once(SCOPE, "fire-no-gui", "Fire() before a successful Init — no celebration burst")
		return nil
	end
	local groups = JuiceConfig.foodBurstGroups
	if #groups == 0 then
		Log.Once(SCOPE, "fire-no-groups", "JuiceConfig.foodBurstGroups is EMPTY — nothing to launch")
		return nil
	end
	local range = JuiceConfig.foodBurst.counts[kind]
	if range == nil then
		Log.Once(SCOPE, `fire-kind-{kind}`, `no burst size for kind '{kind}' — add one to JuiceConfig.foodBurst.counts`)
		return nil
	end
	local count = math.round(between(range))

	local group = groups[math.random(#groups)]
	if groupId ~= nil then
		local matched = false
		for _, candidate in ipairs(groups) do
			if candidate.id == groupId then
				group = candidate
				matched = true
				break
			end
		end
		if not matched then
			-- R8: silently rolling a random group here would let a dev probe a
			-- misspelled id, see a burst, and conclude the hook works.
			Log.Once(SCOPE, `fire-unknown-{groupId}`, `no food group '{groupId}' — rolled a random one instead`)
		end
	end
	local icons = group.icons
	if #icons == 0 then
		Log.Once(SCOPE, `fire-empty-{group.id}`, `food group '{group.id}' has no icons — burst skipped`)
		return nil
	end

	local cfg = JuiceConfig.foodBurst
	-- Never ask for more than the pool holds: past that the tail of the burst
	-- would recycle sprites that are still on their way up.
	local wanted = math.min(count, #pool)
	if wanted < count then
		Log.Once(
			SCOPE,
			"fire-truncated",
			`burst of {count} cut to {wanted} — raise JuiceConfig.foodBurst.poolSize above the largest count`
		)
	end
	for i = 1, wanted do
		local sprite = pool[cursor]
		cursor = cursor % #pool + 1
		if not sprite.live then
			liveCount += 1
		end

		-- Apex FIRST, speed derived: h = v²/(2g) => v = sqrt(2gh). Tuning the
		-- arc directly is what keeps "lands about halfway up" true on every
		-- screen; a tuned launch SPEED does not survive an aspect change.
		local apex = between(cfg.launchApex)
		local speed = math.sqrt(2 * cfg.gravity * apex)
		local x = between(cfg.spawnSpread)
		-- Drift biased AWAY from the screen centre, so the burst blooms open
		-- instead of the whole wave sliding one way.
		local outward = if x < 0.5 then -1 else 1
		local drift = (math.random() * 2 - 1) * cfg.driftSpeed
		sprite.vx = drift * (1 - cfg.driftOutward) + math.abs(drift) * outward * cfg.driftOutward

		sprite.live = true
		sprite.shown = false
		sprite.delay = (i - 1) * cfg.stagger + math.random() * cfg.staggerJitter
		sprite.age = 0
		sprite.x = x
		sprite.y = 1 + cfg.spawnBelow
		sprite.vy = -speed
		sprite.size = between(cfg.sizeRange)
		sprite.spin = between(cfg.spinSpeed) * (if math.random() < 0.5 then -1 else 1)
		sprite.angle = math.random() * 360

		sprite.label.Image = Theme.Icon(icons[math.random(#icons)])
		sprite.label.Visible = false -- shown once its stagger delay elapses
	end
	return group.id
end

--API
-- Per-frame integration. Driven from CakeSubsClient's RenderStepped (R4).
function FoodBurst.Step(dt: number)
	if liveCount == 0 then
		return
	end
	local cfg = JuiceConfig.foodBurst
	-- A hitched frame (asset load, teleport) must not fling the whole burst off
	-- screen in one step.
	local step = math.min(dt, cfg.maxStep)
	-- ⚠ `Position` scale is width-relative on X and height-relative on Y, but
	-- every velocity here is in screen HEIGHTS. Integrating vx straight into x
	-- would make the horizontal bloom aspect-dependent — 1.8x too fast on 16:9
	-- and ~2.3x on 21:9 — which is exactly the thing this module's units exist
	-- to prevent. Convert once per frame.
	local viewport = gui ~= nil and gui.AbsoluteSize or Vector2.zero
	local xPerHeight = if viewport.X > 1 then viewport.Y / viewport.X else 1

	for _, sprite in ipairs(pool) do
		if sprite.live then
			if sprite.delay > 0 then
				sprite.delay -= step
			else
				sprite.age += step
				sprite.vy += cfg.gravity * step
				sprite.x += sprite.vx * xPerHeight * step
				sprite.y += sprite.vy * step
				sprite.angle += sprite.spin * step

				-- Gone once the whole sprite has cleared the bottom edge. The
				-- lifetime is a backstop: a config edit that zeroed gravity
				-- would otherwise strand the pool full of live sprites and
				-- every later burst would be empty.
				-- ⚠ `vy > 0` (falling) is LOAD-BEARING, not a nicety. Sprites
				-- SPAWN at `1 + spawnBelow` = 1.09, which is already past the
				-- exit line for every size under ~0.117 — so without this an
				-- ascending sprite was killed on its first integrated frame if
				-- that frame did not lift it clear. It deleted ~21% of every
				-- burst at 60 Hz and ~60% at 144 Hz: silently, and WORSE on
				-- better hardware, so it never reproduced on a locked-60 dev
				-- machine.
				local offscreen = sprite.vy > 0
					and (sprite.y - cfg.fadeBelow > 1 + sprite.size * cfg.exitMargin)
				if offscreen or sprite.age > cfg.maxLifetime then
					sprite.live = false
					sprite.shown = false
					sprite.label.Visible = false
					liveCount -= 1
				else
					-- Scale-in with overshoot: the sprite POPS into existence
					-- at the bottom edge rather than sliding in at full size.
					local pop = 1
					if sprite.age < cfg.popTime then
						local t = sprite.age / cfg.popTime
						pop = t * (cfg.popOvershoot + (1 - cfg.popOvershoot) * t)
					end
					-- Squash & stretch: tall and thin at speed, wide and flat
					-- at the apex. This is what sells the weight.
					local speed01 = math.clamp(math.abs(sprite.vy) / cfg.stretchRefSpeed, 0, 1)
					local stretch = 1 + cfg.stretch * (speed01 - 0.5) * 2
					local h = sprite.size * pop * stretch
					local w = sprite.size * pop / stretch

					local label = sprite.label
					label.Size = UDim2.fromScale(w, h)
					label.Position = UDim2.fromScale(sprite.x, sprite.y)
					label.Rotation = sprite.angle
					if not sprite.shown then
						sprite.shown = true
						label.Visible = true
					end
				end
			end
		end
	end
end

--API
-- Drops every live sprite instantly. NOT wired to round end or teleport on
-- purpose: a burst is fully gone in under 3 s and `maxLifetime` caps it at 4,
-- so there is no state worth tearing down — this exists for the Studio
-- verification flow (features/food-burst.md), next to ActiveCount().
function FoodBurst.Clear()
	for _, sprite in ipairs(pool) do
		sprite.live = false
		sprite.shown = false
		sprite.label.Visible = false
	end
	liveCount = 0
end

--API
-- Live sprite count — the Studio verification hook (features/food-burst.md).
function FoodBurst.ActiveCount(): number
	return liveCount
end

return FoodBurst
