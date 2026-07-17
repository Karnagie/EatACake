--[[
	Log — console transparency layer (shared, used by both sides).

	PRINCIPLE (CLAUDE.md "Console Transparency"): a silent failure is a bug.
	Every layer reports what it loaded, what it skipped and WHY. Expected
	lifecycle events use print (hidden when verbose = false); anything that
	needs human attention — missing folder, failed require, no DataStore
	access, unresolved GUI — always warns.

	API:
	  Log.Info(scope, message) -- lifecycle event; shown only when verbose
	  Log.Sum(scope, message)  -- summary line; always shown
	  Log.Warn(scope, message) -- problem; always shown (uses warn())
	  Log.Once(scope, key, message) -- Warn that fires once per unique key

	Output format (greppable): [Server/Bootstrap] ... / [Client/UiData] ...
]]

local RunService = game:GetService("RunService")

local Log = {}

-- true  = log every module load / Init / Start / GUI resolve (recommended
--         during development)
-- false = only summaries and warnings (release)
Log.verbose = true

local side = if RunService:IsServer() then "Server" else "Client"
local onceFired: { [string]: boolean } = {}

--API
function Log.Info(scope: string, message: string)
	if Log.verbose then
		print(`[{side}/{scope}] {message}`)
	end
end

--API
function Log.Sum(scope: string, message: string)
	print(`[{side}/{scope}] {message}`)
end

--API
function Log.Warn(scope: string, message: string)
	warn(`[{side}/{scope}] {message}`)
end

--API
-- Warn exactly once per key — for conditions checked repeatedly
-- (e.g. a GUI that is still missing on every update).
function Log.Once(scope: string, key: string, message: string)
	if onceFired[key] then
		return
	end
	onceFired[key] = true
	Log.Warn(scope, message)
end

local graceScheduled: { [string]: boolean } = {}

--API
-- Deferred Once for dependencies that legitimately arrive LATE (StarterGui
-- clone after character spawn, slow replication on bad connections).
-- Schedules a NON-BLOCKING re-check after `seconds`; warns once only if
-- `stillBroken()` is still true — no false positives at boot, no yields in
-- the caller's flow. Repeated calls with the same key are coalesced.
function Log.GraceOnce(scope: string, key: string, seconds: number, stillBroken: () -> boolean, message: string)
	if graceScheduled[key] or onceFired[key] then
		return
	end
	graceScheduled[key] = true
	task.delay(seconds, function()
		if onceFired[key] then
			return
		end
		local ok, broken = pcall(stillBroken)
		if ok and broken == true then
			Log.Once(scope, key, message)
		end
	end)
end

return Log
