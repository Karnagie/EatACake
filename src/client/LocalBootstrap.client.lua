--[[
	LocalBootstrap — client entry point.

	Same sequence as ServerBootstrap:
	1. Dynamically require every ModuleScript in data/, modules/, subscriptions/
	2. Call Init() on each data module (if defined)
	3. Call Init(data) on each module (client-side service)
	4. Call Start(data, modules) on each subscription module
	5. Fire ClientReady — the server holds the initial state push until this
	   arrives (RemoteEvents fired before listeners connect are silently lost).

	Console transparency (CLAUDE.md): every folder, module, Init and Start is
	reported; anything missing or failed WARNS — a silently skipped module is
	a bug. A subscription without Start() is always a mistake and warns.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "Bootstrap"
local root = script.Parent

local KIND_HINTS = { "data", "services", "modules", "subscriptions" }

-- A "partition" is a container holding at least one KIND folder. Template
-- default = ONE flat partition: root (the Client folder) directly holds
-- data/modules/subscriptions. The two-place split instead maps root's children
-- to Common + Lobby|Game folders, EACH a partition with the same kind folders;
-- the loader MERGES them, so which features a place runs is decided purely by
-- which partition folders its project.json maps — this bootstrap stays
-- byte-identical in both places.
local function collectPartitions(): { Instance }
	for _, kind in ipairs(KIND_HINTS) do
		if root:FindFirstChild(kind) then
			return { root } -- flat layout (single place / template default)
		end
	end
	local parts = {}
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Folder") then
			for _, kind in ipairs(KIND_HINTS) do
				if child:FindFirstChild(kind) then
					table.insert(parts, child)
					break
				end
			end
		end
	end
	table.sort(parts, function(a, b)
		return a.Name < b.Name
	end)
	return parts
end

local partitions = collectPartitions()
if #partitions == 0 then
	Log.Warn(SCOPE, "no partitions found (no data/modules/subscriptions folder under Client) — NOTHING will load")
else
	local names = {}
	for _, p in ipairs(partitions) do
		table.insert(names, if p == root then "<flat>" else p.Name)
	end
	Log.Info(SCOPE, `partitions ({#partitions}): {table.concat(names, ", ")}`)
end

-- Merge one kind folder (e.g. "subscriptions") across every partition into one
-- name-keyed table. A duplicate module name across partitions WARNS (R8) and is
-- ignored (first-loaded wins) — rename to fix.
local function loadFolder(kind: string): { [string]: any }
	local modules = {}
	for _, partition in ipairs(partitions) do
		local folder = partition:FindFirstChild(kind)
		if folder then
			local prefix = if partition == root then "" else `{partition.Name}/`
			for _, obj in ipairs(folder:GetChildren()) do
				if obj:IsA("ModuleScript") then
					if modules[obj.Name] ~= nil then
						Log.Warn(SCOPE, `{kind}/{obj.Name}: DUPLICATE across partitions — '{partition.Name}' ignored (first-loaded wins); rename to fix`)
					else
						local ok, mod = pcall(require, obj)
						if not ok then
							Log.Warn(SCOPE, `{prefix}{kind}/{obj.Name}: require FAILED — {mod}`)
						else
							modules[obj.Name] = mod
						end
					end
				end
			end
		end
	end
	local names = {}
	for name in pairs(modules) do
		table.insert(names, name)
	end
	table.sort(names)
	if #names == 0 then
		Log.Warn(SCOPE, `{kind}: NO modules loaded (checked {#partitions} partition(s))`)
	else
		Log.Info(SCOPE, `{kind}: {#names} module(s) — {table.concat(names, ", ")}`)
	end
	return modules
end

local function forEachSorted(modules: { [string]: any }, fn: (string, any) -> ())
	local names = {}
	for name in pairs(modules) do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in ipairs(names) do
		fn(name, modules[name])
	end
end

local function count(modules: { [string]: any }): number
	local n = 0
	for _ in pairs(modules) do
		n += 1
	end
	return n
end

local data = loadFolder("data")
local clientModules = loadFolder("modules")
local subscriptions = loadFolder("subscriptions")

local dataInit, modulesInit, subsStarted = 0, 0, 0

forEachSorted(data, function(name, mod)
	if type(mod) == "table" and type(mod.Init) == "function" then
		local ok, err = pcall(mod.Init)
		if ok then
			dataInit += 1
			Log.Info(SCOPE, `data/{name}.Init ok`)
		else
			Log.Warn(SCOPE, `data/{name}.Init FAILED — {err}`)
		end
	end
end)

forEachSorted(clientModules, function(name, mod)
	if type(mod) ~= "table" or type(mod.Init) ~= "function" then
		Log.Info(SCOPE, `modules/{name}: no Init(data) — takes no dependencies`)
		return
	end
	local ok, err = pcall(mod.Init, data)
	if ok then
		modulesInit += 1
		Log.Info(SCOPE, `modules/{name}.Init ok`)
	else
		Log.Warn(SCOPE, `modules/{name}.Init FAILED — {err}`)
	end
end)

forEachSorted(subscriptions, function(name, mod)
	if type(mod) ~= "table" or type(mod.Start) ~= "function" then
		Log.Warn(SCOPE, `subscriptions/{name} has NO Start(data, modules) — it will NEVER run`)
		return
	end
	local ok, err = pcall(mod.Start, data, clientModules, subscriptions)
	if ok then
		subsStarted += 1
		Log.Info(SCOPE, `subscriptions/{name}.Start ok`)
	else
		Log.Warn(SCOPE, `subscriptions/{name}.Start FAILED — {err}`)
	end
end)

-- Tell the server every listener above is connected. The server holds the
-- initial state push until this arrives (see PlayerLifecycleSubs).
do
	local ok, err = pcall(function()
		local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
		Net.Remote("ClientReady"):FireServer()
	end)
	if ok then
		Log.Info(SCOPE, "ClientReady sent — server may push initial state now")
	else
		Log.Warn(SCOPE, `ClientReady FAILED — initial state will never arrive: {err}`)
	end
end

Log.Sum(
	SCOPE,
	`complete — data: {count(data)} loaded ({dataInit} with Init) | modules: {modulesInit}/{count(clientModules)} initialized | subscriptions: {subsStarted}/{count(subscriptions)} started`
)
