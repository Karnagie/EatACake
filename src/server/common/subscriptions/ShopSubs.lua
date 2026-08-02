--[[
	ShopSubs — the shop domain (R4), BOTH currencies: Robux dev products and
	gamepasses, and the gem-priced boosts row. The SINGLE owner of
	MarketplaceService.ProcessReceipt on the server.

	COMMON since 2026-07-30 — it runs in BOTH places, and that is a money-path
	requirement, not tidiness. While it was lobby-only, the game place had NO
	ProcessReceipt at all: every receipt that surfaced there (Roblox's
	in-experience Store, a re-delivery, a purchase completed as the player
	teleported) was dropped with no console trace. Roblox retries forever, so
	nothing was stolen, but the player saw nothing happen and the funnel showed
	nothing either.

	Two consequences worth knowing:
	• A receipt whose grant kind is registered only by the GAME partition
	  (`burn`) is deferred with NotProcessedYet in the lobby and granted when
	  Roblox re-delivers it in a game server. Self-healing, but not instant.
	• The shop UI is still opened from the lobby only; this sub answering in the
	  game place is about DELIVERY, not about showing the window there.

	Wires:
	• RequestPurchase (key): validate key -> PromptProductPurchase. A oneTime
	  product already owned resyncs instead of prompting; devProductId = 0
	  refuses with a warning (nothing breaks).
	• RequestGemPurchase (key): the IN-GAME currency path — our server is the
	  cashier, so it does everything ProcessReceipt does except talk to Roblox:
	  refuse a Robux product loudly (tampering), refuse mid-teleport-release
	  (Save is a no-op there), validate the WHOLE grants list BEFORE spending,
	  then an ATOMIC EconomyService.TrySpendGems, grants with no yields between,
	  Save, and a resync of both the catalogue and the balance.
	• ProcessReceipt: map ProductId -> key, refuse while a teleport release is in
	  flight, skip an already-handled PurchaseId, grant via RewardGrantSubs,
	  mark oneTime, record the receipt, Save, PurchaseGranted. Unknown product /
	  offline player / failed grant -> NotProcessedYet (Roblox retries — money is
	  never eaten).
	• RequestGamepass (key): validate -> PromptGamePassPurchase.
	• PromptGamePassPurchaseFinished: mark runtime ownership + resync.
	• On join (SendShop): push the full catalogue snapshot. Gamepass ownership
	  is fetched by PassOwnershipSubs (COMMON, runs in both places), which
	  re-pushes this catalogue once ownership resolves.

	ShopUpdate payload (an explicit whitelist in `shopPayload` — a new ShopData
	field never reaches the client until a line is added there):
	  { products = ARRAY {key,label,desc,icon,accent,premium,bundle,currency,
	                      priceRobux,priceGems,section,order,best,oneTime,owned,
	                      configured},
	    passes   = ARRAY {key,label,desc,icon,accent,premium,priceRobux,order,
	                      owned,configured} }
	ROBUX prices are reference-only (the dashboard is authoritative) — shown on
	buttons, never used in math. `priceGems` is the opposite: it is the price
	this server actually charges, and the client shows it only to decide whether
	the card renders affordable.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))
local PlaceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("PlaceConfig"))
local AnalyticsConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("AnalyticsConfig"))
-- Resolved from the subscriptions registry in Start, never by script.Parent —
-- partition moves must not break the wiring (see the lobby/game split).
local RewardGrantSubs
local PassOwnershipSubs
local AnalyticsSubs -- optional; features/analytics.md

local SCOPE = "ShopSubs"

local ShopSubs = {}

-- Telemetry on the MONEY path, and therefore doubly forbidden from being able
-- to affect it: every call is pcall'd and a failure is a console line, never a
-- refused purchase (R8).
local function beatShop(player: Player, funnelStep: string?, eventKey: string?, sku: string?, result: string?, value: number?)
	if AnalyticsSubs == nil then
		return
	end
	local ok, err = pcall(function()
		if funnelStep then
			AnalyticsSubs.Funnel(player, "shop", funnelStep)
		end
		if eventKey then
			AnalyticsSubs.Event(player, eventKey, value or 1, { sku, result, PlaceConfig.current() }, {
				tier = "critical",
			})
		end
	end)
	if not ok then
		Log.Once(SCOPE, "shop-analytics", `shop analytics beat FAILED (telemetry only, purchase unaffected): {err}`)
	end
end

local function beatEconomy(
	player: Player,
	flow: string,
	currency: string,
	amount: number,
	balance: number,
	transaction: string,
	sku: string?
)
	if AnalyticsSubs == nil then
		return
	end
	local ok, err = pcall(AnalyticsSubs.Economy, player, flow, currency, amount, balance, transaction, sku)
	if not ok then
		Log.Once(SCOPE, "shop-economy-analytics", `economy analytics beat FAILED (telemetry only): {err}`)
	end
end

local ShopService, PersistenceService, EconomyService
local EconomySubs
local ShopData, profileData
local uShop
-- TreasureConfig.boosts, captured in Start so `descriptorValid` can prove a
-- boost descriptor names a def that actually exists (see the boost branch).
local boostDefs

local function shopPayload(userId: number)
	local products = {}
	for key, def in pairs(ShopData.products) do
		table.insert(products, {
			key = key,
			label = def.label,
			desc = def.desc,
			icon = def.icon,
			accent = def.accent,
			-- Hero cells only. Sent as an ARRAY of plain {icon, text} tables —
			-- RemoteEvent serialisation stringifies numeric keys, so this must
			-- stay a sequence (docs/registries/remotes.md).
			bundle = def.bundle,
			-- The two GEM fields. Both are needed on the client: `currency`
			-- routes the click to the right remote and picks the price glyph,
			-- `priceGems` is what the affordable/unaffordable card state is
			-- computed against. Omitting either from this whitelist is silent —
			-- the card just renders as an unpriced Robux product.
			currency = def.currency,
			priceGems = def.priceGems,
			priceRobux = def.priceRobux,
			-- Fall back to "boosts", never "gems": the gem section is the one
			-- with a BEST VALUE ribbon and gold accents, so a mis-sectioned
			-- product would land in the wrong grid wearing the wrong hierarchy.
			-- Matches LocalShopService's else-branch.
			section = def.section or "boosts",
			order = def.order or 0,
			best = def.best == true,
			premium = def.premium == true,
			oneTime = def.oneTime == true,
			owned = def.oneTime == true and ShopService.IsOneTimeOwned(userId, key) or false,
			-- The UI must be able to SHOW that a product cannot be sold. Without
			-- this it renders a live BUY button whose purchase the server
			-- refuses, and the player sees nothing happen (R8: silent failure).
			-- "Can be sold" means a nonzero DASHBOARD id for a Robux product and
			-- a nonzero PRICE for a gem one — a gem product has no dashboard id
			-- at all, so testing devProductId would mark the whole boosts row
			-- permanently "SOON".
			configured = if ShopData.IsGemProduct(def)
				then (type(def.priceGems) == "number" and def.priceGems > 0)
				else (type(def.devProductId) == "number" and def.devProductId > 0),
		})
	end
	table.sort(products, function(a, b)
		if a.section ~= b.section then
			return a.section < b.section
		end
		return a.order < b.order
	end)
	local passes = {}
	for key, def in pairs(ShopData.gamepasses) do
		table.insert(passes, {
			key = key,
			label = def.label,
			desc = def.desc,
			icon = def.icon,
			accent = def.accent,
			premium = def.premium == true,
			priceRobux = def.priceRobux,
			order = def.order or 0,
			owned = ShopService.OwnsPass(userId, key),
			configured = type(def.gamePassId) == "number" and def.gamePassId > 0,
		})
	end
	table.sort(passes, function(a, b)
		return a.order < b.order
	end)
	return { products = products, passes = passes }
end

--API
-- Push the catalogue + ownership snapshot (called by PlayerLifecycleSubs on
-- join and internally after purchases).
function ShopSubs.SendShop(player: Player)
	if uShop == nil then
		Log.Warn(SCOPE, `SendShop({player.Name}) before Start ran — push dropped`)
		return
	end
	uShop:FireClient(player, shopPayload(player.UserId))
end


-- Descriptor sanity per kind. The old guard tested `kind == "gold"`, a kind
-- this game does not have — so `{ kind = "gems", amount = 0 }` sailed through
-- validation, both handlers returned nil, and grantProduct still returned true:
-- PurchaseGranted for nothing. Kinds are listed explicitly so ADDING one to
-- ShopData without deciding what "valid" means for it fails loudly here rather
-- than silently accepting anything.
local function descriptorValid(reward): (boolean, string?)
	local kind = reward.kind
	if kind == "gems" or kind == "calories" then
		if math.floor(tonumber(reward.amount) or 0) <= 0 then
			return false, `{kind} amount must be > 0`
		end
	elseif kind == "boost" then
		if type(reward.boostId) ~= "string" or reward.boostId == "" then
			return false, "boost needs a boostId"
		end
		-- The id must name a REAL def, not merely be a non-empty string. The four
		-- product keys (boost-15m, boost-bite, boost-speed, boost-capacity)
		-- deliberately differ from the four def ids (boost-15m, bite-15m,
		-- speed-15m, capacity-15m) and exactly one of them collides, so a
		-- copy-paste slip is one token away — and StatsService.GrantBoost answers
		-- an unknown id with `false`, which on the GEM path means the gems are
		-- already spent. Daily rewards shipped `boostId = "golden-slice"` (a FIND
		-- id) once, so this is a mistake that has actually reached main.
		if boostDefs ~= nil and boostDefs[reward.boostId] == nil then
			return false, `boostId '{reward.boostId}' is not a TreasureConfig.boosts def`
		end
	elseif kind == "egg" then
		if reward.eggType ~= nil and type(reward.eggType) ~= "string" then
			return false, "egg eggType must be a string when present"
		end
	elseif kind == "burn" then
		-- no payload
	else
		return false, `unknown kind '{tostring(kind)}' — add a rule to descriptorValid`
	end
	return true
end

-- Returns the validated, non-empty grants list, or nil + a reason if ANY entry
-- can't be granted. Validating the WHOLE list BEFORE granting anything is what
-- makes the grant loop all-or-nothing: a partial failure mid-loop would
-- otherwise re-mint the successful grants on every Roblox receipt retry.
local function grantableList(def): ({ { [string]: any } }?, string?)
	local grants = def.grants or { def.grant }
	if #grants == 0 then
		return nil, "no grant/grants"
	end
	for _, reward in ipairs(grants) do
		if type(reward) ~= "table" then
			return nil, "a grant entry is not a table"
		end
		if not RewardGrantSubs.HasHandler(reward.kind) then
			-- Not necessarily a config bug: `burn` is registered by the GAME
			-- partition only, so a receipt for it that surfaces in the lobby is
			-- deliberately deferred (NotProcessedYet) and delivered when Roblox
			-- re-delivers it in a game server.
			return nil, `no handler for kind '{tostring(reward.kind)}' in this place`
		end
		local ok, why = descriptorValid(reward)
		if not ok then
			return nil, why
		end
	end
	return grants
end

local function grantProduct(player: Player, userId: number, key: string, purchaseId: string): boolean
	local def = ShopData.products[key]
	if not def or not profileData.Get(userId) then
		return false
	end
	local grants, why = grantableList(def)
	if not grants then
		Log.Warn(SCOPE, `product '{key}' is not grantable here — refusing: {tostring(why)}`)
		return false
	end
	-- No yields from here on: the pre-validated loop applies atomically, and the
	-- receipt is recorded in the SAME stretch so a re-delivery can never slip
	-- between the grant and the ledger write.
	for _, reward in ipairs(grants) do
		local granted = RewardGrantSubs.Grant(player, reward, `shop:{key}`)
		if granted == nil then
			-- Should be impossible after grantableList; log loudly either way.
			Log.Warn(SCOPE, `product '{key}': pre-validated grant still declined ({tostring(reward.kind)})`)
		end
	end
	if def.oneTime then
		ShopService.MarkOneTimePurchased(userId, key)
	end
	ShopService.MarkReceiptHandled(userId, purchaseId)
	return true
end

local function processReceipt(receiptInfo)
	local key = ShopData.KeyForProductId(receiptInfo.ProductId)
	if not key then
		-- Not one of our configured products — let Roblox retry (a later
		-- code version may handle it). R8: never silent on a money path.
		Log.Once(SCOPE, `receipt-unknown-{receiptInfo.ProductId}`, `receipt for UNKNOWN ProductId {receiptInfo.ProductId} — not in ShopData; retrying forever until configured`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local userId = receiptInfo.PlayerId
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		-- Payer isn't in THIS server (cross-server timing / rejoin churn).
		-- R8: never silent on a money path — Roblox retries on rejoin.
		Log.Once(SCOPE, `receipt-offline-{userId}`, `receipt '{key}' for {userId}: payer not in this server — NotProcessedYet (retries on rejoin)`)
		return Enum.ProductPurchaseDecision.NotProcessedYet -- retried on rejoin
	end
	-- A pending receipt can arrive BEFORE the profile loads (join with a
	-- queued receipt). Wait a bounded window instead of burning the retry.
	local deadline = os.clock() + 15
	while not PersistenceService.IsLoaded(userId) do
		if os.clock() > deadline or player.Parent ~= Players then
			Log.Info(SCOPE, `receipt '{key}' for {userId}: profile not loaded in time — NotProcessedYet (will retry)`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		task.wait(0.5)
	end
	-- A handoff to the other place is in flight: PersistenceService.Save is a
	-- NO-OP while a release nonce is set, so granting now would take the Robux,
	-- consume the receipt and lose the reward with the released session. Defer —
	-- Roblox re-delivers, and the destination server (ShopSubs is COMMON) grants
	-- it there.
	if profileData.releaseNonces[userId] ~= nil then
		Log.Warn(SCOPE, `receipt '{key}' for {userId} arrived mid-teleport-release — NotProcessedYet (granted after the handoff)`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)
	-- Roblox re-delivers a receipt until it sees PurchaseGranted. A server that
	-- granted and then died hands the SAME PurchaseId to the next one, which for
	-- a consumable mints the reward twice for one payment.
	if ShopService.IsReceiptHandled(userId, purchaseId) then
		-- Already granted — but "granted" may still only be true IN MEMORY (this
		-- is the retry of a receipt whose save did not confirm), so confirm the
		-- write before telling Roblox to stop retrying. On a fresh server the
		-- profile is whatever last committed, so an unsaved grant is simply
		-- absent from the ledger and falls through to a clean re-grant below.
		if not PersistenceService.SaveAndWait(userId) then
			Log.Warn(SCOPE, `receipt {purchaseId} ('{key}') already granted to {userId} but still unsaved — NotProcessedYet`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		Log.Info(SCOPE, `receipt {purchaseId} ('{key}') already granted to {userId} — consuming without re-granting`)
		ShopSubs.SendShop(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local def = ShopData.products[key]
	if def.oneTime and ShopService.IsOneTimeOwned(userId, key) then
		-- Stray duplicate receipt for a one-time item: consume WITHOUT
		-- double-granting.
		ShopSubs.SendShop(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local ok, granted = pcall(grantProduct, player, userId, key, purchaseId)
	if not ok or not granted then
		-- CRITICAL: the player PAID and the grant failed. Never swallow.
		Log.Warn(SCOPE, `PAID GRANT FAILED for '{key}' (user {userId}) — returning NotProcessedYet for retry: {ok and "grant declined" or granted}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- WAIT for the write. `Save` is fire-and-forget (ProfileStore spawns it), so
	-- returning PurchaseGranted straight after it tells Roblox to stop retrying
	-- while the grant still exists only in memory — a hard crash in that window
	-- takes the Robux and delivers nothing, permanently. Not confirming is the
	-- one case where re-delivery is the CORRECT outcome: the retry either hits
	-- the ledger on this server (and re-tries the save) or, after a crash, finds
	-- a profile with neither the grant nor the ledger entry and grants cleanly.
	if not PersistenceService.SaveAndWait(userId) then
		Log.Warn(
			SCOPE,
			`product '{key}' granted to {player.Name} but the save did NOT confirm — NotProcessedYet so Roblox re-delivers`
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	ShopSubs.SendShop(player)
	-- Logged only HERE, after the save confirmed. Anywhere earlier and a
	-- re-delivered receipt would count the same sale twice, which on the one
	-- chart the game is monetised against is worse than not counting it.
	beatShop(player, "bought", "purchase-result", key, "robux", 1)
	beatEconomy(
		player,
		"sink",
		AnalyticsConfig.economy.currencies.robux,
		receiptInfo.CurrencySpent,
		0,
		AnalyticsConfig.economy.transactions.iap,
		key
	)
	Log.Info(SCOPE, `product '{key}' granted to {player.Name} ({receiptInfo.CurrencySpent} R$)`)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

--API
-- Join-state hook: PlayerLifecycleSubs calls this after profile load + ClientReady.
function ShopSubs.PushInitialState(player: Player)
	ShopSubs.SendShop(player)
	-- Gamepass ownership is fetched by PassOwnershipSubs (COMMON — runs in both
	-- the lobby and the game place); it re-pushes this catalogue once ownership
	-- resolves. (Was ShopSubs.RefreshPassOwnership, which couldn't run in game.)
end

function ShopSubs.Start(data, services, subscriptions)
	RewardGrantSubs = subscriptions.RewardGrantSubs
	PassOwnershipSubs = subscriptions.PassOwnershipSubs
	EconomySubs = subscriptions.EconomySubs
	AnalyticsSubs = subscriptions.AnalyticsSubs
	if AnalyticsSubs == nil then
		Log.Warn(SCOPE, "AnalyticsSubs missing — purchase prompts, results and economy events will not be logged")
	end
	ShopService = services.ShopService
	PersistenceService = services.PersistenceService
	EconomyService = services.EconomyService
	ShopData = data.ShopData
	profileData = data.PlayerProfileData
	boostDefs = data.CakeConfigData and data.CakeConfigData.treasures and data.CakeConfigData.treasures.boosts
	if boostDefs == nil then
		Log.Warn(
			SCOPE,
			"TreasureConfig.boosts missing — boost descriptors can no longer be checked against a real def, "
				.. "so a typo'd boostId will only surface as a spent-but-not-granted purchase"
		)
	end
	uShop = Net.Update("ShopUpdate")

	-- FIRST, before anything that can throw. This Start runs under the
	-- bootstrap's pcall, so a later failure would leave receipts unhandled with
	-- nothing in the console saying the money path is dead (R8) — the most
	-- dangerous silent state this game has.
	MarketplaceService.ProcessReceipt = processReceipt
	Log.Sum(SCOPE, `ProcessReceipt armed in the {PlaceConfig.current()} place`)

	Net.Remote("RequestPurchase").OnServerEvent:Connect(function(player, key)
		if type(key) ~= "string" then
			Log.Once(SCOPE, "purchase-badtype", `RequestPurchase with a non-string key from {player.Name} — ignored`)
			return
		end
		local def = ShopData.products[key]
		if not def then
			-- Either a tampering client or a UI row whose id drifted from ShopData.
			-- Silent, this is a button that does nothing with no console trace.
			Log.Once(SCOPE, `purchase-unknown-{key}`, `RequestPurchase for unknown product '{key}' — refused`)
			return
		end
		-- The mirror of the guard on RequestGemPurchase below. A gem product has
		-- no dev product to prompt, so without this branch it would fall into the
		-- "no devProductId" warn and blame a missing dashboard id for what is
		-- really a tampering client or a UI route that drifted.
		if ShopData.IsGemProduct(def) then
			Log.Warn(SCOPE, `RequestPurchase for '{key}', which is a GEM product — refused (it is bought with RequestGemPurchase)`)
			return
		end
		-- ⚠ The oneTime check below is only meaningful once the profile EXISTS.
		-- `IsOneTimeOwned` resolves the section out of `profiles[userId]` and
		-- returns false when there is no profile, so it cannot tell "not owned"
		-- from "don't know yet" — and the consequence here is prompting an owner
		-- to buy a one-time product (the 99 R$ Starter Pack) a SECOND time. The
		-- gem path has carried these two guards since ADR-0015; the Robux path is
		-- the one that spends real money, so it needs them at least as much.
		local userId = player.UserId
		if not PersistenceService.IsLoaded(userId) then
			Log.Info(SCOPE, `RequestPurchase '{key}' from {player.Name}: profile not loaded — refused, resyncing`)
			ShopSubs.SendShop(player)
			return
		end
		-- Mid-teleport-release the profile is about to be handed to another server
		-- and `Save` is a NO-OP, so ProcessReceipt would defer the grant anyway
		-- (NotProcessedYet). Prompting here just charges the player for something
		-- that cannot land until they arrive; refuse and let them buy after.
		if profileData.releaseNonces[userId] ~= nil then
			Log.Warn(SCOPE, `RequestPurchase '{key}' from {player.Name} arrived mid-teleport-release — refused (buy again after the handoff)`)
			ShopSubs.SendShop(player)
			return
		end
		if def.oneTime and ShopService.IsOneTimeOwned(userId, key) then
			ShopSubs.SendShop(player) -- resync: hide the owned card
			return
		end
		if type(def.devProductId) ~= "number" or def.devProductId <= 0 then
			Log.Warn(SCOPE, `product '{key}' has no devProductId in ShopData — purchase refused`)
			return
		end
		-- The Roblox prompt is about to appear. Everything that does NOT reach
		-- `purchase_result` after this is a player who saw the price and said
		-- no — the most valuable number in the shop, and one Roblox's own
		-- reporting does not give you.
		beatShop(player, "prompt", "purchase-prompt", key, "robux", 1)
		MarketplaceService:PromptProductPurchase(player, def.devProductId)
	end)

	-- Wiring state (not game data): gem-purchase burst bucket per userId. Every
	-- refusal below answers with a full catalogue re-push and some warn LOUDLY, so
	-- without a gate a client firing this on Heartbeat costs the whole server CPU
	-- and buries the console. Sized in ShopData so a HUMAN buying two boosts back
	-- to back is never throttled — a dropped legitimate purchase is invisible on
	-- the client, which already played its press feedback.
	local gemBuckets: { [number]: { windowStart: number, count: number } } = {}

	-- The GEM purchase path (ADR-0015). This is a currency path with no Roblox in
	-- it: our server is the cashier, so every guarantee ProcessReceipt gets for
	-- free (validate before charging, never grant mid-handoff, never take money
	-- for a no-op) has to be written out here.

	Net.Remote("RequestGemPurchase").OnServerEvent:Connect(function(player, key)
		if type(key) ~= "string" then
			Log.Once(SCOPE, "gembuy-badtype", `RequestGemPurchase with a non-string key from {player.Name} — ignored`)
			return
		end
		local userId = player.UserId
		local now = os.clock()
		local bucket = gemBuckets[userId]
		if bucket == nil or (now - bucket.windowStart) >= ShopData.gemPurchaseWindowSeconds then
			bucket = { windowStart = now, count = 0 }
			gemBuckets[userId] = bucket
		end
		bucket.count += 1
		if bucket.count > ShopData.gemPurchaseBurst then
			-- Dropped BEFORE any push or warn — that is the whole point of the gate.
			-- Log.Once per player rather than silence: no human reaches this, so a
			-- player who does is either scripting or hitting a client bug, and a
			-- dropped purchase must never be invisible (R8). Once per userId per
			-- server, so the flood it is protecting against cannot flood the log.
			Log.Once(
				SCOPE,
				`gembuy-throttled-{userId}`,
				`{player.Name} exceeded {ShopData.gemPurchaseBurst} gem purchases in {ShopData.gemPurchaseWindowSeconds}s — `
					.. `throttling this player's RequestGemPurchase (further drops are silent)`
			)
			return
		end
		local def = ShopData.products[key]
		if not def then
			Log.Once(SCOPE, `gembuy-unknown-{key}`, `RequestGemPurchase for unknown product '{key}' — refused`)
			return
		end
		-- A ROBUX product arriving here is not a UI slip: the client routes by the
		-- `currency` field it was sent, so reaching this remote with a Robux key
		-- means someone is trying to buy a 2000 R$ gem pack for nothing. Refuse
		-- LOUDLY (Warn, not Once — the count matters on a money path).
		if not ShopData.IsGemProduct(def) then
			Log.Warn(SCOPE, `RequestGemPurchase for '{key}', which is a ROBUX product — refused (tampering, or a drifted client route)`)
			return
		end
		local price = math.floor(tonumber(def.priceGems) or 0)
		if price <= 0 then
			Log.Warn(SCOPE, `gem product '{key}' has no priceGems in ShopData — purchase refused`)
			return
		end
		if def.oneTime and ShopService.IsOneTimeOwned(userId, key) then
			ShopSubs.SendShop(player) -- resync: hide the owned card
			return
		end
		if not PersistenceService.IsLoaded(userId) then
			Log.Info(SCOPE, `RequestGemPurchase '{key}' from {player.Name}: profile not loaded — refused, resyncing`)
			ShopSubs.SendShop(player)
			return
		end
		-- Mid-teleport-release, exactly the case ProcessReceipt defers on:
		-- PersistenceService.Save is a NO-OP while a release nonce is set, so
		-- spending here would take the gems, grant the boost, and lose BOTH with
		-- the released session. There is no Roblox retry to fall back on for an
		-- in-game currency, so this refuses outright rather than deferring.
		if profileData.releaseNonces[userId] ~= nil then
			Log.Warn(SCOPE, `RequestGemPurchase '{key}' from {player.Name} arrived mid-teleport-release — refused (buy again after the handoff)`)
			ShopSubs.SendShop(player)
			return
		end
		-- Validate the WHOLE grants list BEFORE spending anything: the money must
		-- never be taken for a no-op, and unlike a receipt there is no retry that
		-- would put it back.
		local grants, why = grantableList(def)
		if not grants then
			Log.Warn(SCOPE, `gem product '{key}' is not grantable here — refused WITHOUT spending: {tostring(why)}`)
			ShopSubs.SendShop(player)
			return
		end
		-- ATOMIC check + deduct inside EconomyService. A read-then-subtract here
		-- would leave a window for a second click to pass the same balance check.
		beatShop(player, "prompt", "purchase-prompt", key, "gems", 1)
		local spent, balance = EconomyService.TrySpendGems(userId, price)
		if not spent then
			-- The "not enough gems" path. The card is already greyed client-side,
			-- so arriving here means a stale client or a race — either way it is a
			-- refusal the console has to show (R8), not a silent no-op.
			Log.Info(SCOPE, `{player.Name} cannot afford '{key}': {price} gems, balance {tostring(balance)} — refused`)
			beatShop(player, nil, "purchase-result", key, "unaffordable", 1)
			ShopSubs.SendShop(player)
			return
		end
		-- NO YIELDS between the spend and the grants: the list is pre-validated,
		-- so this loop applies atomically and the profile can never be observed
		-- with the gems gone and the reward missing.
		--
		-- A declined grant here should be impossible, but "should be impossible"
		-- is not a guarantee a currency path may rest on: Roblox re-delivers a
		-- failed RECEIPT, and nothing re-delivers spent gems. So if any grant
		-- declines, the spend is COMPENSATED — the player ends the exchange with
		-- their gems rather than with neither the gems nor the reward.
		local declined = 0
		for _, reward in ipairs(grants) do
			if RewardGrantSubs.Grant(player, reward, `shop-gems:{key}`) == nil then
				declined += 1
				Log.Warn(SCOPE, `gem product '{key}': pre-validated grant still declined ({tostring(reward.kind)})`)
			end
		end
		if declined > 0 then
			EconomyService.AddGems(userId, price)
			PersistenceService.Save(userId)
			ShopSubs.SendShop(player)
			if EconomySubs then
				EconomySubs.SendCurrency(player)
			end
			beatShop(player, nil, "purchase-result", key, "refunded", 1)
			Log.Warn(SCOPE, `gem product '{key}': {declined} grant(s) declined AFTER the spend — refunded {price} gems to {player.Name}`)
			return
		end
		if def.oneTime then
			ShopService.MarkOneTimePurchased(userId, key)
		end
		PersistenceService.Save(userId)
		ShopSubs.SendShop(player)
		-- RewardGrantSubs pushes CurrencyUpdate when it GRANTS gems; a SPEND has
		-- no such push, so without this the HUD keeps showing the pre-purchase
		-- balance until the next find. EconomySubs is COMMON, but resolve it
		-- through the registry and guard it — a partition move must degrade to a
		-- stale pill with a console line, not to a nil call (R3/R8).
		if EconomySubs then
			EconomySubs.SendCurrency(player)
		else
			Log.Once(
				SCOPE,
				"no-economysubs",
				"EconomySubs missing — a gem purchase cannot re-push the balance, so the HUD stays stale until the next earn"
			)
		end
		beatShop(player, "bought", "purchase-result", key, "gems", 1)
		beatEconomy(
			player,
			"sink",
			AnalyticsConfig.economy.currencies.gems,
			price,
			EconomyService.GetGems(userId) or 0,
			AnalyticsConfig.economy.transactions.shop,
			key
		)
		Log.Info(SCOPE, `gem product '{key}' bought by {player.Name} for {price} gems (balance {tostring(balance)})`)
	end)

	Net.Remote("RequestGamepass").OnServerEvent:Connect(function(player, key)
		if type(key) ~= "string" then
			Log.Once(SCOPE, "gamepass-badtype", `RequestGamepass with a non-string key from {player.Name} — ignored`)
			return
		end
		local def = ShopData.gamepasses[key]
		if not def then
			Log.Once(SCOPE, `gamepass-unknown-{key}`, `RequestGamepass for unknown gamepass '{key}' — refused`)
			return
		end
		if ShopService.OwnsPass(player.UserId, key) then
			ShopSubs.SendShop(player)
			return
		end
		if type(def.gamePassId) ~= "number" or def.gamePassId <= 0 then
			Log.Warn(SCOPE, `gamepass '{key}' has no gamePassId in ShopData — purchase refused`)
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, def.gamePassId)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if not wasPurchased then
			return
		end
		for key, def in pairs(ShopData.gamepasses) do
			if def.gamePassId == gamePassId then
				ShopService.SetPassOwned(player.UserId, key, true)
				-- The cell flipping to OWNED is not the perk taking effect: the
				-- client gates auto-eat/auto-gym on player ATTRIBUTES, which only
				-- PassOwnershipSubs writes. Without this a 399 R$ pass bought
				-- mid-session did nothing until the next place transition.
				if PassOwnershipSubs then
					PassOwnershipSubs.ApplyPerkAttributes(player)
				else
					Log.Once(SCOPE, "no-passownership", "PassOwnershipSubs missing — a mid-session pass purchase will not apply its perk attributes until rejoin")
				end
				ShopSubs.SendShop(player)
				Log.Info(SCOPE, `gamepass '{key}' purchased by {player.Name}`)
				return
			end
		end
		Log.Once(
			SCOPE,
			`pass-unknown-{gamePassId}`,
			`PromptGamePassPurchaseFinished for gamePassId {gamePassId}, which is in no ShopData entry — ownership NOT recorded`
		)
	end)

	Players.PlayerRemoving:Connect(function(player)
		ShopService.ClearRuntime(player.UserId)
		gemBuckets[player.UserId] = nil
	end)

	-- Config validation (after all Starts — grant kinds must be registered).
	task.defer(function()
		local unconfigured, unpriced, undeliverable, badBoost = {}, {}, {}, {}
		for key, def in pairs(ShopData.products) do
			local grants = def.grants or { def.grant }
			-- A boostId that names no def is a SPENT-BUT-NOT-GRANTED purchase on
			-- the gem path (the refund below puts the gems back, but the player
			-- still clicked BUY and got nothing). Catch it at boot, where it costs
			-- one line, instead of at the first purchase.
			for _, reward in ipairs(grants) do
				if reward and reward.kind == "boost" and boostDefs ~= nil and boostDefs[tostring(reward.boostId)] == nil then
					table.insert(badBoost, `{key}({tostring(reward.boostId)})`)
				end
			end
			-- The gem refund is all-or-nothing at the PRICE, not per grant: a
			-- multi-grant gem product whose second grant declines refunds the full
			-- price while the first grant stands, which is free loot on repeat.
			-- Every gem product ships with exactly one grant today; this keeps it
			-- that way loudly rather than by luck.
			if ShopData.IsGemProduct(def) and #grants > 1 then
				Log.Warn(
					SCOPE,
					`gem product '{key}' has {#grants} grants — the gem refund path is all-or-nothing at the price, so a `
						.. `partial failure would refund in full AND keep the grants that succeeded. Split it, or make the `
						.. `refund per-grant before shipping this.`
				)
			end
			if #grants == 0 then
				-- Was a raw `warn(`, which bypasses Log and so never carries the
				-- scope tag the console report is read by (R8).
				Log.Warn(SCOPE, `product '{key}' has NO grant/grants — a purchase would take Robux for nothing (refused at receipt)`)
			end
			for _, reward in ipairs(grants) do
				if reward and not RewardGrantSubs.HasHandler(reward.kind) then
					table.insert(undeliverable, `{key}({tostring(reward.kind)})`)
				end
			end
			-- A GEM product must NEVER appear in the "NOT ON SALE" list: it needs
			-- no Creator Dashboard id, so listing it there would make the console
			-- permanently claim a working, sellable catalogue is broken — the
			-- exact false positive R8 forbids. Its equivalent misconfiguration is
			-- a missing price, reported separately below.
			if ShopData.IsGemProduct(def) then
				if type(def.priceGems) ~= "number" or def.priceGems <= 0 then
					table.insert(unpriced, key)
				end
			elseif type(def.devProductId) ~= "number" or def.devProductId <= 0 then
				table.insert(unconfigured, key)
			end
		end
		local unconfiguredPasses = {}
		for key, def in pairs(ShopData.gamepasses) do
			if type(def.gamePassId) ~= "number" or def.gamePassId <= 0 then
				table.insert(unconfiguredPasses, key)
			end
		end
		table.sort(unconfigured)
		table.sort(unpriced)
		table.sort(unconfiguredPasses)
		table.sort(undeliverable)
		table.sort(badBoost)
		if #badBoost > 0 then
			Log.Warn(
				SCOPE,
				`product(s) granting a boostId that is NOT in TreasureConfig.boosts: {table.concat(badBoost, ", ")}. `
					.. `The purchase is refused before charging; fix the id in ShopData (docs/registries/data-keys.md lists them).`
			)
		end
		-- ONE line each instead of fifteen: the per-product spam buried the two
		-- lines that actually matter (an undeliverable grant kind, and the fact
		-- that the whole catalogue is off sale).
		if #unconfigured > 0 or #unconfiguredPasses > 0 then
			Log.Warn(
				SCOPE,
				`NOT ON SALE — {#unconfigured} product id(s) and {#unconfiguredPasses} gamepass id(s) are still 0: `
					.. `{table.concat(unconfigured, ", ")}{#unconfigured > 0 and #unconfiguredPasses > 0 and " | " or ""}`
					.. `{table.concat(unconfiguredPasses, ", ")}. `
					.. `Create them on the Creator Dashboard and paste the ids into ShopData (docs/recipes/publish-readiness.md).`
			)
		end
		if #unpriced > 0 then
			Log.Warn(
				SCOPE,
				`GEM product(s) with no priceGems: {table.concat(unpriced, ", ")}. They render as "SOON" and refuse to sell. `
					.. `Set priceGems in ShopData (they need no Creator Dashboard id).`
			)
		end
		if #undeliverable > 0 then
			Log.Warn(
				SCOPE,
				`grant kind(s) with NO handler in the {PlaceConfig.current()} place: {table.concat(undeliverable, ", ")}. `
					.. `A receipt for these is deferred here and delivered when Roblox re-delivers it in a place that has the handler.`
			)
		end
	end)
end

return ShopSubs
