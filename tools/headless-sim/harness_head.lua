
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

local ReplicatedStorage = stub.newInstance("Folder", "ReplicatedStorage")
local Workspace = stub.newInstance("Folder", "Workspace")
workspace = Workspace

local playersList = {}
local PlayersService = { GetPlayers = function() return playersList end }
local RunServiceStub = { Heartbeat = { Wait = function() return 1 / 60 end } }

game = {
	GetService = function(_, name)
		if name == "ReplicatedStorage" then return ReplicatedStorage end
		if name == "Players" then return PlayersService end
		if name == "RunService" then return RunServiceStub end
		error("unstubbed service " .. name)
	end,
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
