--[[
	ServerBootstrap — server entry point.

	Initialization sequence (mirrored by LocalBootstrap on the client):
	1. Dynamically require every ModuleScript in data/, services/, subscriptions/
	2. Call Init() on each data module (if defined)
	3. Call Init(data) on each service
	4. Call Start(data, services) on each subscription module

	Modules are initialized in alphabetical order (deterministic). Services
	must NOT rely on cross-service init order beyond that.

	Console transparency (CLAUDE.md): every folder, module, Init and Start is
	reported; anything missing or failed WARNS — a silently skipped module is
	a bug. A subscription without Start() is always a mistake and warns.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "Bootstrap"
local root = script.Parent

local function loadFolder(folderName: string): { [string]: any }
	local modules = {}
	local folder = root:FindFirstChild(folderName)
	if not folder then
		Log.Warn(SCOPE, `folder '{folderName}' is MISSING — nothing loaded from it`)
		return modules
	end
	local names = {}
	for _, obj in ipairs(folder:GetChildren()) do
		if obj:IsA("ModuleScript") then
			local ok, mod = pcall(require, obj)
			if not ok then
				Log.Warn(SCOPE, `{folderName}/{obj.Name}: require FAILED — {mod}`)
			else
				modules[obj.Name] = mod
				table.insert(names, obj.Name)
			end
		end
	end
	table.sort(names)
	if #names == 0 then
		Log.Warn(SCOPE, `{folderName}: folder exists but contains NO modules`)
	else
		Log.Info(SCOPE, `{folderName}: {#names} module(s) — {table.concat(names, ", ")}`)
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
local services = loadFolder("services")
local subscriptions = loadFolder("subscriptions")

local dataInit, servicesInit, subsStarted = 0, 0, 0

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

forEachSorted(services, function(name, mod)
	if type(mod) ~= "table" or type(mod.Init) ~= "function" then
		Log.Info(SCOPE, `services/{name}: no Init(data) — takes no dependencies`)
		return
	end
	local ok, err = pcall(mod.Init, data)
	if ok then
		servicesInit += 1
		Log.Info(SCOPE, `services/{name}.Init ok`)
	else
		Log.Warn(SCOPE, `services/{name}.Init FAILED — {err}`)
	end
end)

forEachSorted(subscriptions, function(name, mod)
	if type(mod) ~= "table" or type(mod.Start) ~= "function" then
		Log.Warn(SCOPE, `subscriptions/{name} has NO Start(data, services) — it will NEVER run`)
		return
	end
	local ok, err = pcall(mod.Start, data, services)
	if ok then
		subsStarted += 1
		Log.Info(SCOPE, `subscriptions/{name}.Start ok`)
	else
		Log.Warn(SCOPE, `subscriptions/{name}.Start FAILED — {err}`)
	end
end)

Log.Sum(
	SCOPE,
	`complete — data: {count(data)} loaded ({dataInit} with Init) | services: {servicesInit}/{count(services)} initialized | subscriptions: {subsStarted}/{count(subscriptions)} started`
)
