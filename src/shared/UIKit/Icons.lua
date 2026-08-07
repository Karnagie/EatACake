--[[
	Theme.Icons — the single icon registry (R1/kit iron rule 2).

	name -> rbxassetid. Components NEVER inline an asset id; they take an icon
	NAME (or read Theme.Icons.X) so art can be re-pointed in one place.

	Source art: C:\Users\vladimir\Desktop\Sprites\
	  Roblox icons/        -> Ui*      (flat colour glyphs, pre-outlined)
	  vector-badges/       -> Pass*, Rarity*, Ribbon*
	  vector-item-tiers/   -> GemPack*, CoinPack*, Egg*
	  vector-food-pack/    -> Sq*      ("-outline-256" cut: thick dark outline,
	                                    matches the kit's Outer/Rim/Face recipe)

	Re-uploading: serve the Sprites folder over http and use the Studio MCP
	upload_image tool (local file paths are rejected — http/https only), then
	regenerate this table. Batches of ~14 (45 times out).
]]

-- Resolve through `Theme.Icon(name)` — it warns once on a miss and returns a
-- visible fallback. This table holds ONLY names, no functions: a helper here
-- would share the namespace with the icons themselves.
local Icons = {}

-- UI glyphs (Roblox icons pack) — menu buttons, chips, status glyphs
Icons.UiAim =        "rbxassetid://120259440013057"
Icons.UiArrowLeft =  "rbxassetid://73524128042364"
Icons.UiArrowRight = "rbxassetid://84537622065671"
Icons.UiBolt =       "rbxassetid://77697722557816"
Icons.UiBomb =       "rbxassetid://129794777234647"
Icons.UiBoom =       "rbxassetid://130845077374461"
Icons.UiBoost =      "rbxassetid://133399522288424"
Icons.UiBox =        "rbxassetid://126911441369736"
Icons.UiBulb =       "rbxassetid://125610557336087"
Icons.UiCalendar =   "rbxassetid://97238354874930"
Icons.UiCharts =     "rbxassetid://123398315209353"
Icons.UiCheck =      "rbxassetid://92800839380303"
Icons.UiClose =      "rbxassetid://99868918371991"
Icons.UiCodes =      "rbxassetid://82798762043244"
Icons.UiCoins =      "rbxassetid://140340080288483"
Icons.UiFire =       "rbxassetid://110022316947372"
Icons.UiFriend =     "rbxassetid://91418962999771"
Icons.UiGem =        "rbxassetid://79394485672993"
Icons.UiGift =       "rbxassetid://76352890473075"
Icons.UiGiftOpen =   "rbxassetid://75479330452904"
Icons.UiHammer =     "rbxassetid://109680361857409"
Icons.UiHeart =      "rbxassetid://124607685593319"
Icons.UiInventory =  "rbxassetid://81335973094261"
Icons.UiJetpack =    "rbxassetid://121935175995643"
Icons.UiLock =       "rbxassetid://123826571941514"
Icons.UiMap =        "rbxassetid://74203109485878"
Icons.UiMoreGift =   "rbxassetid://71428364780679"
Icons.UiPaw =        "rbxassetid://94212668985853"
Icons.UiPunch =      "rbxassetid://72479475799518"
Icons.UiQuest =      "rbxassetid://115447050603864"
Icons.UiRebirth =    "rbxassetid://80418189242112"
Icons.UiRewardStar = "rbxassetid://95434256111031"
Icons.UiRobux =      "rbxassetid://118207993108763"
Icons.UiSearch =     "rbxassetid://92899149015792"
Icons.UiSettings =   "rbxassetid://81051372859087"
Icons.UiShoe =       "rbxassetid://112448418121354"
Icons.UiShop =       "rbxassetid://73616261814412"
Icons.UiShocked =    "rbxassetid://104112343212762"
Icons.UiSpring =     "rbxassetid://111427218897351"
Icons.UiStar =       "rbxassetid://112012097747556"
Icons.UiStrength =   "rbxassetid://88182799955864"
Icons.UiTeleport =   "rbxassetid://136076418219520"
Icons.UiTrade =      "rbxassetid://138983042396155"
Icons.UiTrophy =     "rbxassetid://87125957293210"
Icons.UiVerified =   "rbxassetid://87074461169089"
Icons.UiWheel =      "rbxassetid://130337412400685"

-- Gamepass / perk badges (premade badge art — shop pass cards)
Icons.PassAutoClick =   "rbxassetid://79943325731694"
Icons.PassAutoEgg =     "rbxassetid://118646744619177"
Icons.PassAutoRebirth = "rbxassetid://70709395303525"
Icons.PassBoombox =     "rbxassetid://109888231848271"
Icons.PassCashX2 =      "rbxassetid://139599585541859"
Icons.PassClicksX2 =    "rbxassetid://74368996581836"
Icons.PassCoinX2 =      "rbxassetid://109732551129155"
Icons.PassCoinX3 =      "rbxassetid://140387703049010"
Icons.PassEggX2 =       "rbxassetid://110615591414286"
Icons.PassGemX2 =       "rbxassetid://109300748183888"
Icons.PassGemX3 =       "rbxassetid://77857993641736"
Icons.PassHoverboard =  "rbxassetid://121900562038353"
Icons.PassLuckX2 =      "rbxassetid://121311038287622"
Icons.PassMvp =         "rbxassetid://76131770606580"
Icons.PassPetsX2 =      "rbxassetid://92335765236464"
Icons.PassPetsX3 =      "rbxassetid://113924202749507"
Icons.PassPro =         "rbxassetid://103294455522541"
Icons.PassSpeed =       "rbxassetid://126224002039622"
Icons.PassStorageX2 =   "rbxassetid://97488866061940"
Icons.PassStorageX3 =   "rbxassetid://121463976002508"
Icons.PassVip =         "rbxassetid://76914943355402"
Icons.PassXpX2 =        "rbxassetid://128882480025647"

-- Rarity marks — Star = corner badge, Disc = solid tier dot
Icons.RarityDiscCommon =    "rbxassetid://101462266341215"
Icons.RarityDiscEpic =      "rbxassetid://105244701261122"
Icons.RarityDiscLegendary = "rbxassetid://121407042963389"
Icons.RarityDiscRare =      "rbxassetid://97595320046314"
Icons.RarityDiscSecret =    "rbxassetid://79831086438076"
Icons.RarityDiscUncommon =  "rbxassetid://79778443338133"
Icons.RarityStarCommon =    "rbxassetid://104724883338726"
Icons.RarityStarEpic =      "rbxassetid://135991914670470"
Icons.RarityStarLegendary = "rbxassetid://79495585232361"
Icons.RarityStarRare =      "rbxassetid://107923388305666"
Icons.RarityStarSecret =    "rbxassetid://118337629153847"
Icons.RarityStarUncommon =  "rbxassetid://111615981532821"

-- Ribbons — corner tags (BEST VALUE / LIMITED / NEW)
Icons.RibbonGold =    "rbxassetid://70664859252602"
Icons.RibbonGreen =   "rbxassetid://102756329016800"
Icons.RibbonPurple =  "rbxassetid://140277667378457"
Icons.RibbonRainbow = "rbxassetid://76301099307614"
Icons.RibbonRed =     "rbxassetid://80817829946769"

-- Currency + crate art (shop pack cards)
Icons.CoinPackL =  "rbxassetid://117330120694126"
Icons.CoinPackM =  "rbxassetid://114600373203448"
Icons.CoinPackS =  "rbxassetid://134807953075369"
Icons.CoinPackXL = "rbxassetid://134686966331982"
Icons.Egg1 =       "rbxassetid://99733994822996"
Icons.Egg2 =       "rbxassetid://90660273370946"
Icons.Egg3 =       "rbxassetid://129968559440213"
Icons.Egg4 =       "rbxassetid://136107746083404"
Icons.Egg5 =       "rbxassetid://77245158304805"
Icons.Egg6 =       "rbxassetid://118510919587336"
Icons.Egg7 =       "rbxassetid://136791232923947"
Icons.Egg8 =       "rbxassetid://86205286728337"
Icons.GemPackL =   "rbxassetid://118443459142580"
Icons.GemPackM =   "rbxassetid://127605101986847"
Icons.GemPackS =   "rbxassetid://102050487192341"
Icons.GemPackXL =  "rbxassetid://76011177339436"

-- Squishies — the collectible roster (real character renders, 256x256 with the
-- kit's own thick dark outline; they replaced a food-vector placeholder set).
-- Tier + stats live in src/shared/config/PetConfig.lua; each entry names its
-- icon here explicitly, so a typo warns instead of silently rendering the
-- fallback glyph.
-- NOT included on purpose: two renders in the source folder are recognisable
-- third-party characters (Naruto, All Might). Shipping those risks a Roblox
-- moderation takedown of the asset and the place.

Icons.SqVoidCup =      "rbxassetid://95490648227961"
Icons.SqBonsaiTwist =  "rbxassetid://139644507919940"
Icons.SqIceCup =       "rbxassetid://128242944831996"
Icons.SqIceCupWink =   "rbxassetid://111104192471940"
Icons.SqIceCupCalm =   "rbxassetid://79213510470118"
Icons.SqEmberDrop =    "rbxassetid://117849377309029"
Icons.SqHaloCup =      "rbxassetid://104746229271787"
Icons.SqPlumSparkle =  "rbxassetid://121553087767240"
Icons.SqAquaDrop =     "rbxassetid://130375776700682"
Icons.SqLilacDrop =    "rbxassetid://87297927914240"
Icons.SqSunsetDrop =   "rbxassetid://84198569701289"
Icons.SqMintDrop =     "rbxassetid://89625880094139"
Icons.SqCoolShades =   "rbxassetid://71357736023262"
Icons.SqVisorVoid =    "rbxassetid://85277577002478"
Icons.SqCrownGold =    "rbxassetid://134254062262615"
Icons.SqStrawHat =     "rbxassetid://104139439222297"
Icons.SqStormCloud =   "rbxassetid://128877980460540"
Icons.SqDevilWing =    "rbxassetid://79131535345037"
Icons.SqLeafSprout =   "rbxassetid://124823727490618"
Icons.SqStoneLoaf =    "rbxassetid://89141504703464"
Icons.SqBonsaiPot =    "rbxassetid://74355665235820"
Icons.SqPeachGlow =    "rbxassetid://85365607943780"
Icons.SqCreamWink =    "rbxassetid://112619564111393"
Icons.SqBlushPink =    "rbxassetid://82724383291135"
Icons.SqMintGlow =     "rbxassetid://111583585482406"
Icons.SqRainbowDrop =  "rbxassetid://79715254413155"
Icons.SqSkyBeam =      "rbxassetid://119299025881956"
Icons.SqGrapeDrop =    "rbxassetid://90084449765888"
Icons.SqPastelArc =    "rbxassetid://125700576574972"
Icons.SqOceanDrop =    "rbxassetid://131386513056395"
Icons.SqGalaxyRing =   "rbxassetid://96767799447643"
Icons.SqStripeShell =  "rbxassetid://82912948575121"
Icons.SqHazardCore =   "rbxassetid://86143283590892"
Icons.SqNebulaDrop =   "rbxassetid://86268502052709"
Icons.SqButterCup =    "rbxassetid://129113791762880"
Icons.SqEmberRage =    "rbxassetid://121678365991641"
Icons.SqSnowDrop =     "rbxassetid://91214279711621"
Icons.SqGreenBlade =   "rbxassetid://110490590440888"
Icons.SqSombrero =     "rbxassetid://107599833575313"
Icons.SqOfficer =      "rbxassetid://85193096441438"
Icons.SqVikingHelm =   "rbxassetid://75677477156221"
Icons.SqSuit =         "rbxassetid://122829519744049"
Icons.SqLavenderDrop = "rbxassetid://97706722038585"
Icons.SqLimeGlow =     "rbxassetid://117234079459339"
Icons.SqAmberDrop =    "rbxassetid://72825529815709"
Icons.SqBlossom =      "rbxassetid://139917084474689"
Icons.SqAlien =        "rbxassetid://91333538848987"
Icons.SqFirefighter =  "rbxassetid://93921065707055"

-- Badge-pack line icons (vector-badges/Icons, "Outline" cut) — heavier, more
-- readable at HUD size than the flat Ui* glyphs. Prefer these on menu buttons.
Icons.BadgeBackpack =  "rbxassetid://121785035797237"
Icons.BadgeCheck =     "rbxassetid://95022281095375"
Icons.BadgeChest =     "rbxassetid://135728258000243"
Icons.BadgeClock =     "rbxassetid://97911070075873"
Icons.BadgeCoin =      "rbxassetid://106885642757222"
Icons.BadgeGem =       "rbxassetid://94243313336795"
Icons.BadgeKey =       "rbxassetid://121361033098441"
Icons.BadgeLightning = "rbxassetid://77916016486115"
Icons.BadgeStats =     "rbxassetid://111711765776852"
Icons.BadgeStorage =   "rbxassetid://78078863082780"
Icons.BadgeTrophy =    "rbxassetid://85335418886874"
Icons.TextInfinity =   "rbxassetid://104419767277337"

-- Upgrade-tree glyphs that come from OUTSIDE the Roblox-icons pack. One per hex
-- node (features/upgrades.md): the tree's audience may not read, so the glyph
-- IS the node — see UpgradeTreeConfig.icons for the stat -> name mapping.
-- `UiCake` is the vector-food-pack "-outline-256" cut (same cut as the Sq*
-- squishies, so it sits in the kit's Outer/Rim/Face family); `UiDumbbell` is a
-- standalone perk glyph — nothing in the packs above reads as "gym".
Icons.UiCake =         "rbxassetid://96232110647703"
Icons.UiDumbbell =     "rbxassetid://113435550918213"
Icons.UiHand =         "rbxassetid://137811233003146" -- open cartoon glove: one TAP

-- Onboarding comic (features/tutorial.md). FOUR PANELS OF ONE STORY, read
-- TL -> TR -> BL -> BR: the character finds the poster, reads the challenge,
-- gets excited, runs at the cake. Order is load-bearing — renumbering these
-- breaks the narrative, unlike every other entry in this file.
-- All four are 4:3 (716x535); Theme.TutorialPanel's art window is cut to match.
Icons.TutorialSlide1 = "rbxassetid://139890329511008"
Icons.TutorialSlide2 = "rbxassetid://88501692577908"
Icons.TutorialSlide3 = "rbxassetid://135307023473908"
Icons.TutorialSlide4 = "rbxassetid://99839198517910"

return Icons
