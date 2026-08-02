
-- ── globals the game code expects ───────────────────────────────────────
Vector3 = stub.Vector3
CFrame = stub.CFrame
Color3 = stub.Color3
ColorSequence = stub.ColorSequence
NumberSequence = stub.NumberSequence
NumberSequenceKeypoint = stub.NumberSequenceKeypoint
NumberRange = stub.NumberRange
Enum = stub.Enum
Instance = stub.Instance
Vector2 = { new = function(x, y) return { X = x, Y = y } end }

-- Roblox's `typeof` reports "Instance" for anything in the DataModel, and real
-- game code guards on it (`typeof(player) == "Instance"`). The Luau CLI's
-- builtin answers "table" for our stand-ins, which would make every such guard
-- silently refuse — a whole subsystem could then "pass" by doing nothing. Any
-- stand-in that answers `IsA` is an Instance here.
local rawTypeof = typeof
function typeof(value)
	if type(value) == "table" and rawget(value, "IsA") ~= nil then
		return "Instance"
	end
	if type(value) == "table" and getmetatable(value) ~= nil and (value :: any).IsA ~= nil then
		return "Instance"
	end
	return rawTypeof(value)
end

local ReplicatedStorage = stub.newInstance("Folder", "ReplicatedStorage")
local Workspace = stub.newInstance("Folder", "Workspace")
workspace = Workspace

local playersList = {}
local PlayersService = {
	GetPlayers = function() return playersList end,
	GetPlayerByUserId = function(_, userId)
		for _, p in ipairs(playersList) do
			if p.UserId == userId then return p end
		end
		return nil
	end,
}
local RunServiceStub = { Heartbeat = { Wait = function() return 1 / 60 end } }

-- ── analytics recorder ──────────────────────────────────────────────────
-- Records what the game ASKED AnalyticsService to log, so a scenario can
-- assert on the rate-limit budget, the coalescing and the priority reserves
-- without a published place (the real service is server + published only).
-- `__ANALYTICS.fail` makes every call throw, which is how the "Studio /
-- unpublished place" path is exercised.
__ANALYTICS = { custom = {}, funnel = {}, onboarding = {}, economy = {}, calls = 0, fail = false }

-- The real API declares `customFields` as a Dictionary and Roblox's reflection
-- THROWS when handed a Lua array. A stub that records the table verbatim would
-- happily pass a positional `{ tier, reason }` that explodes live — which is
-- exactly the defect an adversarial review found after 53 green checks. So the
-- stub enforces the cast the engine would.
local VALID_FIELD_KEYS = { CustomField01 = true, CustomField02 = true, CustomField03 = true }
local function assertFields(fields, what)
	if fields == nil then
		return
	end
	if type(fields) ~= "table" then
		error(`{what}: customFields must be a table, got {type(fields)}`)
	end
	for key in pairs(fields) do
		if type(key) ~= "string" then
			error(`{what}: customFields is an ARRAY (numeric key {tostring(key)}) — Roblox expects a Dictionary and throws on this`)
		end
		if not VALID_FIELD_KEYS[key] then
			error(`{what}: '{key}' is not one of CustomField01..03`)
		end
	end
end

local function record(bucket, entry)
	__ANALYTICS.calls += 1
	assertFields(entry.fields, bucket)
	if __ANALYTICS.fail then
		error(__ANALYTICS.failMessage or "AnalyticsService is not available in this place")
	end
	table.insert(__ANALYTICS[bucket], entry)
end
local AnalyticsServiceStub = {
	LogCustomEvent = function(_, player, name, value, fields)
		record("custom", { player = player, name = name, value = value, fields = fields })
	end,
	LogFunnelStepEvent = function(_, player, funnel, sessionId, step, stepName, fields)
		record("funnel", {
			player = player, funnel = funnel, sessionId = sessionId,
			step = step, stepName = stepName, fields = fields,
		})
	end,
	LogOnboardingFunnelStepEvent = function(_, player, step, stepName, fields)
		record("onboarding", { player = player, step = step, stepName = stepName, fields = fields })
	end,
	LogEconomyEvent = function(_, player, flow, currency, amount, balance, transaction, sku, fields)
		record("economy", {
			player = player, flow = flow, currency = currency, amount = amount,
			balance = balance, transaction = transaction, sku = sku, fields = fields,
		})
	end,
}

local guidSerial = 0
local HttpServiceStub = {
	GenerateGUID = function()
		guidSerial += 1
		return string.format("stub-guid-%08d", guidSerial)
	end,
}

--API (harness) — a Player good enough for analytics code: identity + presence.
function __newPlayer(userId: number, name: string?)
	local player = {
		UserId = userId,
		Name = name or ("Player" .. tostring(userId)),
		Parent = PlayersService,
		_attributes = {},
	}
	function player:IsA(className: string)
		return className == "Player"
	end
	function player:GetAttribute(key: string)
		return self._attributes[key]
	end
	function player:SetAttribute(key: string, value: any)
		self._attributes[key] = value
	end
	function player:GetJoinData()
		return self._joinData or {}
	end
	table.insert(playersList, player)
	return player
end

--API (harness) — remove a player from the presence list (a leave).
function __removePlayer(player)
	for index, p in ipairs(playersList) do
		if p == player then
			table.remove(playersList, index)
			break
		end
	end
	player.Parent = nil
end

game = {
	GetService = function(_, name)
		if name == "ReplicatedStorage" then return ReplicatedStorage end
		if name == "Players" then return PlayersService end
		if name == "RunService" then return RunServiceStub end
		if name == "AnalyticsService" then return AnalyticsServiceStub end
		if name == "HttpService" then return HttpServiceStub end
		error("unstubbed service " .. name)
	end,
	PlaceId = 0,
	GameId = 0,
}

-- task.spawn runs SYNCHRONOUSLY here: the fade / collect loops play out in
-- place, which is exactly what we want to assert on.
task = {
	spawn = function(f, ...) f(...) end,
	delay = function(_, f, ...) f(...) end,
	wait = function() return 1 / 60 end,
}

local LOG = {}
local ONCE_SEEN: { [string]: boolean } = {}
local LogStub = {
	Info = function(scope, m) table.insert(LOG, `[{scope}] {m}`) end,
	Sum = function(scope, m) table.insert(LOG, `[{scope}] {m}`) end,
	Warn = function(scope, m) table.insert(LOG, `[{scope}] WARN — {m}`) end,
	-- Real Log.Once fires ONCE PER KEY. The stub used to ignore the key and print
	-- every call, which made a correct single warning look like 30 R8 violations
	-- in the scenario output. Mirror the real dedup.
	Once = function(scope, key, m)
		local k = `{scope}/{key}`
		if ONCE_SEEN[k] then
			return
		end
		ONCE_SEEN[k] = true
		table.insert(LOG, `[{scope}] ONCE — {m}`)
	end,
	GraceOnce = function() end,
}
local function flushLog()
	for _, line in ipairs(LOG) do print(line) end
	LOG = {}
end

-- ── module registry + the LOCAL require shim ────────────────────────────
__REGISTRY = { ["Shared.Log"] = LogStub }

local proxyMeta = {}
local function makeProxy(path)
	return setmetatable({ __path = path }, proxyMeta)
end
proxyMeta.__index = function(self, key)
	if key == "WaitForChild" or key == "FindFirstChild" then
		return function(_, child) return makeProxy(self.__path .. "." .. child) end
	end
	if key == "Parent" then
		return makeProxy((self.__path:gsub("%.[^%.]+$", "")))
	end
	-- Any other index is a CHILD lookup (`script.Parent.GridUtil`).
	return makeProxy(self.__path .. "." .. key)
end

local Shared = makeProxy("Shared")
ReplicatedStorage.WaitForChild = function(_, name)
	if name == "Shared" then return Shared end
	return ReplicatedStorage:FindFirstChild(name)
end
ReplicatedStorage.FindFirstChild = function(_, name)
	for _, c in ipairs(ReplicatedStorage._children) do
		if c.Name == name then return c end
	end
	return nil
end

-- `script.Parent.X` — how a Rojo-synced module reaches a SIBLING. Resolves to
-- the same proxy the WaitForChild path produces, so an inlined CakeOps works.
script = makeProxy("Shared.CakeOps")

-- Declared LOCAL and BEFORE the inlined module bodies, so lexical scoping makes
-- every inlined `require(...)` hit this and never the CLI builtin.
local function require(target)
	if type(target) == "table" and target.__path then
		local mod = __REGISTRY[target.__path]
		assert(mod ~= nil, "unstubbed module " .. target.__path)
		return mod
	end
	error("unexpected require target")
end
