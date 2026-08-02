--[[ dump_regions.luau
Dump visible GuiObject rects from a running Studio session as a regions JSON
skeleton for tools/tonal-hierarchy/tonal.py.

USAGE (via Studio MCP execute_luau, Edit or Play datamodel):
 1. Start the receiver on the host:  python tools/tonal-hierarchy/tonal.py listen --out regions.json
 2. Edit CONFIG below (ROOT path), run this script.
 3. The dump arrives as regions.json. EDIT IT BY HAND before analyzing:
    assign "level" (1 = primary CTA, 2 = second read, 3 = supporting,
    4 = chrome/background) and "role" (cta / tab-active / tab-inactive /
    title / content / container / background / decor), delete noise rows.
    A dumped region has level = nil, which tonal.py treats as level 3 + warn.

Rects are viewport pixels; the JSON carries "viewport" so tonal.py rescales
if the screenshot resolution differs from the viewport.
]]

local CONFIG = {
	-- Instance to scan. Examples:
	--   game.CoreGui.ShopPreview                  (edit-mode preview harness)
	--   game.Players.LocalPlayer.PlayerGui.UiRoot (Play, Client context)
	ROOT = game:GetService("CoreGui"):FindFirstChild("ShopPreview"),
	MAX_DEPTH = 7,
	MIN_SIZE = 14,     -- skip elements thinner than this on either axis
	MAX_REGIONS = 150,
	POST = true,       -- POST to URL (needs `tonal.py listen` running);
	                   -- false = return the JSON string (may truncate)
	URL = "http://127.0.0.1:8788/",
}

local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")

local root = CONFIG.ROOT
assert(root, "dump_regions: CONFIG.ROOT is nil — point it at a ScreenGui")

-- Inset correction, OFFSET-based — the flag alone is not enough:
-- AbsolutePosition can be reported in inset-relative space even on an
-- IgnoreGuiInset=true gui (observed live: a full-bleed PlayerGui root with
-- DeviceSafeInsets reports every child 58px above its true screenshot
-- position, while an identical CoreGui gui reports physical pixels).
-- child − screenGui.AbsolutePosition is invariant to whichever origin
-- Roblox picked; add back the root's PHYSICAL origin: 0 for a full-bleed
-- gui, the topbar inset for a classic inset one.
local screenGui = root:IsA("ScreenGui") and root
	or root:FindFirstAncestorWhichIsA("ScreenGui")
local offsetX, offsetY = 0, 0
if screenGui then
	local guiPos = screenGui.AbsolutePosition
	local inset = GuiService:GetGuiInset()
	local physX = screenGui.IgnoreGuiInset and 0 or inset.X
	local physY = screenGui.IgnoreGuiInset and 0 or inset.Y
	offsetX = physX - guiPos.X
	offsetY = physY - guiPos.Y
end

local camera = workspace.CurrentCamera
local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)

local function isDrawn(obj)
	if obj.BackgroundTransparency < 0.95 then
		return true
	end
	if (obj:IsA("ImageLabel") or obj:IsA("ImageButton"))
		and obj.ImageTransparency < 0.95 and obj.Image ~= "" then
		return true
	end
	if (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox"))
		and obj.TextTransparency < 0.95 and obj.Text ~= "" then
		return true
	end
	return false
end

local regions = {}
local truncated = false

local function walk(inst, path, depth)
	if depth > CONFIG.MAX_DEPTH or truncated then
		return
	end
	for _, child in inst:GetChildren() do
		if child:IsA("GuiObject") then
			local p = path == "" and child.Name or (path .. "." .. child.Name)
			local sz = child.AbsoluteSize
			-- Visibility prunes the subtree (invisible children never draw);
			-- the size gate only skips the INSERT — a zero-size anchor frame
			-- routinely holds visible overflowing children.
			if child.Visible then
				if sz.X >= CONFIG.MIN_SIZE and sz.Y >= CONFIG.MIN_SIZE
					and isDrawn(child) then
					if #regions >= CONFIG.MAX_REGIONS then
						truncated = true
						return
					end
					local pos = child.AbsolutePosition
					table.insert(regions, {
						name = p,
						class = child.ClassName,
						rect = {
							math.floor(pos.X + offsetX + 0.5),
							math.floor(pos.Y + offsetY + 0.5),
							math.floor(sz.X + 0.5),
							math.floor(sz.Y + 0.5),
						},
					})
				end
				walk(child, p, depth + 1)
			end
		end
	end
end

walk(root, "", 1)

local payload = HttpService:JSONEncode({
	source = root:GetFullName(),
	viewport = { viewport.X, viewport.Y },
	insetOffset = { offsetX, offsetY }, -- applied to every rect; 0,0 = none
	truncated = truncated,
	regions = regions,
})

if CONFIG.POST then
	local ok, err = pcall(function()
		HttpService:PostAsync(CONFIG.URL, payload,
			Enum.HttpContentType.ApplicationJson)
	end)
	return ok and (`dumped {#regions} regions -> {CONFIG.URL}`
			.. (truncated and " (TRUNCATED at MAX_REGIONS)" or ""))
		or (`POST failed ({err}) — is 'tonal.py listen' running? `
			.. `Falling back to inline return:\n` .. payload)
else
	return payload
end
