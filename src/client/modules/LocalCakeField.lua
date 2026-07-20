--[[
	LocalCakeField — the client's mirror of the server heightfield (GDD §4.7).

	Data shape: same u16 buffer layout as the server (GridUtil), plus:
	  meta        { cakeIndex, footprint, composition, rareKind, biome, ... }
	  changed     set+list of cells awaiting the renderer (drained per frame)
	  avalanche   accumulated |Δh| (studs³) from NON-predicted server deltas —
	              drives the granular slump SFX (§7.4)

	The local player's own bite is PREDICTED with the shared CakeOps math the
	instant the input fires; the server delta then overwrites the same cells
	with near-identical values (reconcile = plain overwrite, no correction
	pass needed). Deltas matching the prediction within 0.05 studs add no
	avalanche energy, so your own bites don't trigger slump sounds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GridUtil = require(Shared:WaitForChild("GridUtil"))
local CakeOps = require(Shared:WaitForChild("CakeOps"))
local Log = require(Shared:WaitForChild("Log"))
local CakeConfig = require(Shared:WaitForChild("config"):WaitForChild("CakeConfig"))

local LocalCakeField = {}

local layersCfg = CakeConfig.layers
local gridCfg = CakeConfig.grid

local field: buffer
local meta = nil -- nil until the first snapshot arrives
-- Layer gate (features/cake-sim.md): index of the current TOP edible band.
-- Seeded from the snapshot meta, refreshed by CakeCycleUpdate (SetActiveBand)
-- so PredictBite clamps to the SAME floor the server does — no phantom
-- craters cut into a still-locked layer beneath.
local activeBandIndex = 0

local changedSet: { [number]: boolean } = {}
local changedList: { number } = {}
local avalancheStuds3 = 0

function LocalCakeField.Init()
	field = buffer.create(gridCfg.size * gridCfg.size * 2)
end

local function markChanged(i: number)
	if not changedSet[i] then
		changedSet[i] = true
		table.insert(changedList, i)
	end
end

--API
function LocalCakeField.HasCake(): boolean
	return meta ~= nil
end

--API
function LocalCakeField.Meta()
	return meta
end

--API
function LocalCakeField.ApplySnapshot(buf: buffer, newMeta)
	if buffer.len(buf) ~= buffer.len(field) then
		Log.Warn("LocalCakeField", `snapshot size {buffer.len(buf)} ≠ field {buffer.len(field)} — dropped`)
		return
	end
	buffer.copy(field, 0, buf, 0)
	meta = newMeta
	activeBandIndex = newMeta.activeBandIndex or #newMeta.composition
	table.clear(changedSet)
	table.clear(changedList)
	avalancheStuds3 = 0
end

--API
-- Layer gate: refresh the active (top) band from a CakeCycleUpdate so the
-- prediction floor tracks the server between snapshots.
function LocalCakeField.SetActiveBand(index: number)
	if type(index) == "number" and index >= 1 then
		activeBandIndex = index
	end
end

--API
function LocalCakeField.ActiveBandIndex(): number
	return activeBandIndex
end

--API
-- Studs height of the active band's floor — bites can't go below it while
-- the layer gate is on. nil before the first snapshot.
function LocalCakeField.ActiveFloorStuds(): number?
	if meta == nil then
		return nil
	end
	local idx = math.clamp(activeBandIndex, 1, #meta.composition)
	return math.max(meta.composition[1].top, meta.composition[idx].bottom)
end

--API
-- Delta packet: [u16 cellIndex][u16 height]*n. Stale cake indices dropped.
function LocalCakeField.ApplyDelta(cakeIndex: number, buf: buffer)
	if meta == nil or cakeIndex ~= meta.cakeIndex then
		return
	end
	local cellArea = gridCfg.cell * gridCfg.cell
	local count = buffer.len(buf) // 4
	for k = 0, count - 1 do
		local i = buffer.readu16(buf, k * 4)
		local units = buffer.readu16(buf, k * 4 + 2)
		local old = GridUtil.ReadHeight(field, i)
		if old ~= units then
			GridUtil.WriteHeight(field, i, units)
			markChanged(i)
			local deltaStuds = math.abs(units - old) / GridUtil.UNITS_PER_STUD
			if deltaStuds > 0.05 then
				avalancheStuds3 += deltaStuds * cellArea
			end
		end
	end
end

--API
-- Local bite prediction (same math as the server). Returns removed volume
-- (studs³) + the surface layer at the bite point, or nil before a snapshot.
function LocalCakeField.PredictBite(px: number, pz: number, radiusStuds: number, depthStuds: number)
	if meta == nil then
		return nil
	end
	local preH = GridUtil.SurfaceHeightAt(field, gridCfg, meta.footprint, px, pz) or 0
	local layer = CakeOps.LayerAtStuds(meta.composition, layersCfg, preH)
	-- Match the server's clamp: the active-band floor while the layer gate is
	-- on, else the absolute core floor. Otherwise prediction would carve below
	-- a locked layer and the next delta would snap it back (visible pop).
	local floorUnits = GridUtil.StudsToUnits(meta.composition[1].top)
	if CakeConfig.layerGate.enabled then
		local activeFloor = LocalCakeField.ActiveFloorStuds()
		if activeFloor then
			floorUnits = GridUtil.StudsToUnits(activeFloor)
		end
	end
	local removed, changed = CakeOps.ApplyBite(
		field, gridCfg, meta.footprint, meta.composition, layersCfg,
		px, pz, radiusStuds, depthStuds, floorUnits
	)
	for _, i in ipairs(changed) do
		markChanged(i)
	end
	return removed, layer
end

--API
-- Renderer drain: cells changed since last call. Returns the internal list
-- (caller must NOT keep a reference past the frame).
function LocalCakeField.DrainChanged(): { number }
	if #changedList == 0 then
		return changedList
	end
	local out = changedList
	changedList = {}
	table.clear(changedSet)
	return out
end

--API
-- Slump SFX energy (studs³) accumulated since last call.
function LocalCakeField.DrainAvalanche(): number
	local v = avalancheStuds3
	avalancheStuds3 = 0
	return v
end

--API
function LocalCakeField.ReadHeightStuds(i: number): number
	return GridUtil.UnitsToStuds(GridUtil.ReadHeight(field, i))
end

--API
function LocalCakeField.SurfaceHeightAt(wx: number, wz: number): number?
	if meta == nil then
		return nil
	end
	return GridUtil.SurfaceHeightAt(field, gridCfg, meta.footprint, wx, wz)
end

--API
function LocalCakeField.LayerAtStuds(hStuds: number)
	if meta == nil then
		return nil
	end
	return CakeOps.LayerAtStuds(meta.composition, layersCfg, hStuds)
end

--API
-- World-space surface point under/near a world position, or nil when the
-- XZ is outside the cake footprint (skirt cells count as outside).
function LocalCakeField.SurfacePoint(wx: number, wz: number): Vector3?
	if meta == nil then
		return nil
	end
	local x, z = GridUtil.WorldToCell(gridCfg, wx, wz)
	if not GridUtil.InBounds(gridCfg.size, x, z) or not GridUtil.InCake(gridCfg.size, meta.footprint, x, z) then
		return nil
	end
	local h = LocalCakeField.SurfaceHeightAt(wx, wz) or 0
	return Vector3.new(wx, gridCfg.origin.y + h, wz)
end

return LocalCakeField
