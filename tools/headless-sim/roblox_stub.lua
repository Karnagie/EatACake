--!nolint
-- Minimal Roblox API stub good enough to run TreasureService headlessly under
-- the standalone luau CLI. CFrames carry a REAL 3x3 rotation (the treasure code
-- tilts finds, so axis-aligned-only would not verify anything).

local M = {}

-- ── Vector3 ─────────────────────────────────────────────────────────────
local V = {}
V.__index = function(self, k)
	if k == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif k == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		return V.new(self.X / m, self.Y / m, self.Z / m)
	end
	return rawget(V, k)
end
function V.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V)
end
V.__add = function(a, b) return V.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return V.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__unm = function(a) return V.new(-a.X, -a.Y, -a.Z) end
V.__mul = function(a, b)
	if type(b) == "number" then return V.new(a.X * b, a.Y * b, a.Z * b) end
	if type(a) == "number" then return V.new(b.X * a, b.Y * a, b.Z * a) end
	return V.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V.__tostring = function(a) return string.format("(%.2f, %.2f, %.2f)", a.X, a.Y, a.Z) end
function V:Lerp(other, t) return self + (other - self) * t end
function V:Dot(o) return self.X * o.X + self.Y * o.Y + self.Z * o.Z end
V.zero = V.new(0, 0, 0)
M.Vector3 = V

-- ── CFrame (position + 3x3 rotation, row vectors r1/r2/r3) ──────────────
-- Layout matches Roblox: columns are RightVector / UpVector / -LookVector.
local C = {}
local function cfNew(p, r)
	return setmetatable({ Position = p, R = r }, C)
end
local IDENTITY_R = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

C.__index = function(self, k)
	if k == "RightVector" then return V.new(self.R[1], self.R[4], self.R[7]) end
	if k == "UpVector" then return V.new(self.R[2], self.R[5], self.R[8]) end
	if k == "LookVector" then return V.new(-self.R[3], -self.R[6], -self.R[9]) end
	if k == "X" then return self.Position.X end
	if k == "Y" then return self.Position.Y end
	if k == "Z" then return self.Position.Z end
	return rawget(C, k)
end

function C.new(x, y, z)
	if type(x) == "table" then
		return cfNew(x, table.clone(IDENTITY_R))
	end
	return cfNew(V.new(x, y, z), table.clone(IDENTITY_R))
end

local function matMul(a, b)
	local out = {}
	for row = 0, 2 do
		for col = 1, 3 do
			out[row * 3 + col] = a[row * 3 + 1] * b[col]
				+ a[row * 3 + 2] * b[3 + col]
				+ a[row * 3 + 3] * b[6 + col]
		end
	end
	return out
end
local function matVec(r, v)
	return V.new(
		r[1] * v.X + r[2] * v.Y + r[3] * v.Z,
		r[4] * v.X + r[5] * v.Y + r[6] * v.Z,
		r[7] * v.X + r[8] * v.Y + r[9] * v.Z
	)
end

function C.Angles(rx, ry, rz)
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	local X = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local Y = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local Z = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return cfNew(V.zero, matMul(matMul(X, Y), Z))
end

C.__mul = function(a, b)
	if getmetatable(b) == V then
		return a.Position + matVec(a.R, b)
	end
	return cfNew(a.Position + matVec(a.R, b.Position), matMul(a.R, b.R))
end
C.__add = function(a, v) return cfNew(a.Position + v, a.R) end
C.__sub = function(a, v) return cfNew(a.Position - v, a.R) end
function C:Inverse()
	-- rotation is orthonormal: inverse = transpose
	local r = self.R
	local t = { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
	return cfNew(-matVec(t, self.Position), t)
end
function C:VectorToWorldSpace(v) return matVec(self.R, v) end
C.__tostring = function(a) return tostring(a.Position) end
M.CFrame = C

-- ── Color3 / sequences / ranges ─────────────────────────────────────────
M.Color3 = {
	fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end,
	new = function(r, g, b) return { R = r, G = g, B = b } end,
}
M.ColorSequence = { new = function(c) return { c } end }
M.NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
M.NumberSequence = { new = function(a) return a end }
M.NumberRange = { new = function(a, b) return { Min = a, Max = b or a } end }

-- ── Enum (only what is touched) ─────────────────────────────────────────
local function enumSet(names)
	local t = {}
	for _, n in ipairs(names) do t[n] = { Name = n } end
	return t
end
M.Enum = {
	PartType = enumSet({ "Ball", "Block" }),
	Material = enumSet({
		"Neon", "SmoothPlastic", "Sand", "Glass", "Fabric", "Plastic", "Concrete",
		"Metal", "Wood", "Brick", "Slate", "Marble", "Granite", "Foil", "Ice",
	}),
	HighlightDepthMode = enumSet({ "AlwaysOnTop", "Occluded" }),
	NormalId = enumSet({ "Top", "Bottom", "Front", "Back", "Left", "Right" }),
	-- Analytics (features/analytics.md). The custom-field keys matter: the
	-- real API wants the enum item's NAME as the dictionary key, so a stub
	-- without `.Name` would let a broken field build pass here and fail live.
	AnalyticsEconomyFlowType = enumSet({ "Source", "Sink" }),
	AnalyticsEconomyTransactionType = enumSet({
		"IAP", "Shop", "Gameplay", "ContextualPurchase", "TimedReward", "Onboarding",
	}),
	AnalyticsCustomFieldKeys = enumSet({ "CustomField01", "CustomField02", "CustomField03" }),
	MessageType = enumSet({ "MessageOutput", "MessageInfo", "MessageWarning", "MessageError" }),
}

-- ── Instances ───────────────────────────────────────────────────────────
local CLASS_PARENTS = {
	Part = "BasePart", MeshPart = "BasePart", UnionOperation = "BasePart",
	WedgePart = "BasePart", TrussPart = "BasePart", BasePart = "PVInstance",
	Model = "PVInstance", PVInstance = "Instance",
	Texture = "Decal", Decal = "FaceInstance", FaceInstance = "Instance",
	PointLight = "Light", SpotLight = "Light", SurfaceLight = "Light", Light = "Instance",
	Script = "BaseScript", LocalScript = "BaseScript", BaseScript = "LuaSourceContainer",
	LuaSourceContainer = "Instance",
	ParticleEmitter = "Instance", Trail = "Instance", Beam = "Instance",
	Highlight = "Instance", Folder = "Instance", Attachment = "Instance",
	SpecialMesh = "Instance", SurfaceAppearance = "Instance", Weld = "Instance",
}

local Inst = {}

local function partsIn(model)
	local out = {}
	if model:IsA("BasePart") then table.insert(out, model) end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(out, d) end
	end
	return out
end

-- Parent lives in `_parent`, NEVER as a raw "Parent" key. ⚠ __newindex only
-- fires while the key is ABSENT — raw-setting "Parent" once would silently
-- bypass child-list maintenance on every later assignment (cost an hour).
Inst.__index = function(self, k)
	if k == "Parent" then return rawget(self, "_parent") end
	return rawget(Inst, k)
end
Inst.__newindex = function(self, k, v)
	if k == "Parent" then
		local old = rawget(self, "_parent")
		if old ~= nil then
			for i, c in ipairs(old._children) do
				if c == self then
					table.remove(old._children, i)
					break
				end
			end
		end
		rawset(self, "_parent", v)
		if v ~= nil then table.insert(v._children, self) end
		return
	end
	rawset(self, k, v)
end

local function newInstance(class, name)
	local self = setmetatable({}, Inst)
	rawset(self, "ClassName", class)
	rawset(self, "Name", name or class)
	rawset(self, "_children", {})
	rawset(self, "_attributes", {})
	rawset(self, "_parent", nil)
	if class == "Part" or class == "MeshPart" then
		self.Size = V.new(4, 1.2, 2)
		self.CFrame = C.new(0, 0, 0)
		self.Transparency = 0
		self.Anchored = false
		self.CanCollide = true
		self.CanQuery = true
		self.CanTouch = true
		self.CastShadow = true
	elseif class == "Model" then
		self.PrimaryPart = nil
		rawset(self, "_scale", 1)
	elseif class == "Decal" or class == "Texture" then
		self.Transparency = 0
	elseif class == "ParticleEmitter" or class == "Trail" or class == "Beam" or class:find("Light") then
		self.Enabled = true
		self.Rate = 5
	elseif class == "Highlight" then
		self.Enabled = true
		self.FillTransparency = 0
		self.OutlineTransparency = 0
		self.Adornee = nil
	end
	return self
end

-- BasePart.Position mirrors CFrame.Position.
local baseIndex = Inst.__index
Inst.__index = function(self, k)
	if k == "Position" and rawget(self, "CFrame") ~= nil then
		return rawget(self, "CFrame").Position
	end
	return baseIndex(self, k)
end
local baseNewIndex = Inst.__newindex
Inst.__newindex = function(self, k, v)
	if k == "Position" and rawget(self, "CFrame") ~= nil then
		local cf = rawget(self, "CFrame")
		rawset(self, "CFrame", setmetatable({ Position = v, R = cf.R }, C))
		return
	end
	baseNewIndex(self, k, v)
end

function Inst:IsA(class)
	local c = rawget(self, "ClassName")
	while c do
		if c == class then return true end
		c = CLASS_PARENTS[c]
	end
	return false
end
function Inst:GetChildren()
	local out = {}
	for _, c in ipairs(rawget(self, "_children")) do table.insert(out, c) end
	return out
end
function Inst:GetDescendants()
	local out = {}
	for _, c in ipairs(rawget(self, "_children")) do
		table.insert(out, c)
		for _, d in ipairs(c:GetDescendants()) do table.insert(out, d) end
	end
	return out
end
function Inst:FindFirstChild(name)
	for _, c in ipairs(rawget(self, "_children")) do
		if c.Name == name then return c end
	end
	return nil
end
function Inst:FindFirstChildWhichIsA(class, recursive)
	for _, c in ipairs(recursive and self:GetDescendants() or self:GetChildren()) do
		if c:IsA(class) then return c end
	end
	return nil
end
function Inst:WaitForChild(name) return self:FindFirstChild(name) end
function Inst:SetAttribute(k, v) rawget(self, "_attributes")[k] = v end
function Inst:GetAttribute(k) return rawget(self, "_attributes")[k] end
function Inst:Destroy()
	self.Parent = nil
	rawset(self, "_destroyed", true)
end
function Inst:Clone()
	local copy = newInstance(rawget(self, "ClassName"), rawget(self, "Name"))
	for k, v in pairs(self) do
		if k ~= "_children" and k ~= "_attributes" and k ~= "_parent" then
			rawset(copy, k, v)
		end
	end
	rawset(copy, "_children", {})
	rawset(copy, "_attributes", {})
	for k, v in pairs(rawget(self, "_attributes")) do rawget(copy, "_attributes")[k] = v end
	local primary = rawget(self, "PrimaryPart")
	local primaryIndex = nil
	local originals = partsIn(self)
	for i, p in ipairs(originals) do
		if p == primary then primaryIndex = i end
	end
	for _, c in ipairs(rawget(self, "_children")) do
		c:Clone().Parent = copy
	end
	if primaryIndex then
		rawset(copy, "PrimaryPart", partsIn(copy)[primaryIndex])
	end
	return copy
end

-- ── PVInstance geometry: TRUE world AABB (rotation aware) ───────────────
local function worldAabb(model)
	local parts = partsIn(model)
	if #parts == 0 then return V.zero, V.zero end
	local lo = V.new(math.huge, math.huge, math.huge)
	local hi = V.new(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(parts) do
		local cf, s = p.CFrame, p.Size
		local r = cf.R
		local hx = 0.5 * (math.abs(r[1]) * s.X + math.abs(r[2]) * s.Y + math.abs(r[3]) * s.Z)
		local hy = 0.5 * (math.abs(r[4]) * s.X + math.abs(r[5]) * s.Y + math.abs(r[6]) * s.Z)
		local hz = 0.5 * (math.abs(r[7]) * s.X + math.abs(r[8]) * s.Y + math.abs(r[9]) * s.Z)
		local c = cf.Position
		lo = V.new(math.min(lo.X, c.X - hx), math.min(lo.Y, c.Y - hy), math.min(lo.Z, c.Z - hz))
		hi = V.new(math.max(hi.X, c.X + hx), math.max(hi.Y, c.Y + hy), math.max(hi.Z, c.Z + hz))
	end
	return (lo + hi) * 0.5, hi - lo
end
M.worldAabb = worldAabb

-- Roblox's GetBoundingBox is in the PIVOT's frame; the game code must not rely
-- on it being world-axis-aligned, and this stub reproduces that faithfully.
function Inst:GetBoundingBox()
	local parts = partsIn(self)
	if #parts == 0 then return C.new(0, 0, 0), V.zero end
	local frame = self:GetPivot()
	local inv = frame:Inverse()
	local lo = V.new(math.huge, math.huge, math.huge)
	local hi = V.new(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(parts) do
		local local_ = inv * p.CFrame
		local s, r = p.Size, local_.R
		local hx = 0.5 * (math.abs(r[1]) * s.X + math.abs(r[2]) * s.Y + math.abs(r[3]) * s.Z)
		local hy = 0.5 * (math.abs(r[4]) * s.X + math.abs(r[5]) * s.Y + math.abs(r[6]) * s.Z)
		local hz = 0.5 * (math.abs(r[7]) * s.X + math.abs(r[8]) * s.Y + math.abs(r[9]) * s.Z)
		local c = local_.Position
		lo = V.new(math.min(lo.X, c.X - hx), math.min(lo.Y, c.Y - hy), math.min(lo.Z, c.Z - hz))
		hi = V.new(math.max(hi.X, c.X + hx), math.max(hi.Y, c.Y + hy), math.max(hi.Z, c.Z + hz))
	end
	return frame * C.new((lo + hi) * 0.5), hi - lo
end
function Inst:GetExtentsSize()
	local _, size = self:GetBoundingBox()
	return size
end
function Inst:GetPivot()
	if self:IsA("BasePart") then return rawget(self, "CFrame") end
	local primary = rawget(self, "PrimaryPart")
	if primary then return primary.CFrame end
	local centre = worldAabb(self)
	return C.new(centre)
end
function Inst:PivotTo(cf)
	if self:IsA("BasePart") then
		rawset(self, "CFrame", cf)
		return
	end
	local inv = self:GetPivot():Inverse()
	local relative = {}
	for i, p in ipairs(partsIn(self)) do
		relative[i] = inv * p.CFrame
	end
	for i, p in ipairs(partsIn(self)) do
		rawset(p, "CFrame", cf * relative[i])
	end
end
function Inst:GetScale() return rawget(self, "_scale") or 1 end
function Inst:ScaleTo(scale)
	local factor = scale / self:GetScale()
	local pivot = self:GetPivot()
	local inv = pivot:Inverse()
	for _, p in ipairs(partsIn(self)) do
		local local_ = inv * p.CFrame
		p.Size = p.Size * factor
		rawset(p, "CFrame", pivot * (C.new(local_.Position * factor) * setmetatable({ Position = V.zero, R = local_.R }, C)))
	end
	rawset(self, "_scale", scale)
end

M.newInstance = newInstance
M.Instance = { new = function(class) return newInstance(class) end }

return M
