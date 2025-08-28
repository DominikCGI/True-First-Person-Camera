-- TFP Camera VERSION: v.0.9.8d
print("[TFP Camera] TFP Head Camera Initialized\n")
local UEHelpers = require("UEHelpers")
local KismetSystemLibrary = StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')

-- List of keys -> https://github.com/UE4SS-RE/RE-UE4SS/blob/main/assets/Mods/shared/Types.lua

-- === Configurables: =======================================================================================

--[[ TFP Camera Config ]]--
-- 	 Controls how the True First Person camera activates and behaves. This includes 
-- 	 toggling, animation override, freelook, helmet overlay, FOV and overall camera settings.

local toggle_key = Key.OEM_PLUS				-- Key used to stoggle TFP mode on/off. (e.g., Key.B, Key.F12, Key.OEM_PLUS, etc.)
local EnableStateSave = true				-- If true, remembers the TFP camera state between game sessions
local NoAnimationLean = false  				-- If true, disables animation-based leaning (work-in-progress feature)
local HeadBobAmount = 1.0 					-- 0.0 = maximum smoothing, 1.0 = original bob, values in between = proportional blend

--[[ Base Offset Config ]]--
-- 	 Controls where the TFP camera is placed relative to the character’s head. 

local XOffset = 0							-- Forward/backward offset (positive = forward, negative = backward)
local YOffset = 0							-- Side offset left|right  (positive = left, negative = right) 
local ZOffset = 1							-- Vertical offset up|down (positive = up, negative = down)

--[[ Detail Offset Config ]]--
-- 	 Adds extra camera offsets. These values are *added* on top of the base offsets above.

local SittingOffset = -2					-- Additional Forward/backward offset while sitting  (positive = forward, negative = backward)
local CrouchOffset = -1  					-- Additional Forward/backward offset while crouched (positive = forward, negative = backward)
local RidingOffset = 5	 					-- Additional Forward/backward offset while riding   (positive = forward, negative = backward)

--[[ Helmet Overlay Config ]]--
-- 	 Toggles whether a helmet “visor” is rendered on screen when wearing a helmet.

local HelmetOverlay = true					-- Enables helmet overlay graphics (true = on, false = off)
local hide_FOV_key = Key.H					-- Key to manually toggle overlay visuals (HelmetOverlay must be true)

--[[ Freelook Config ]]--
-- 	 Configures freelook mode, (Camera can rotate independently of character movement).

local FreelookKey = "V"						-- Key to activate freelook. Hold or Toggle (e.g., "V", "Alt", etc.)
local EnableFreelookStateSave = true		-- Remembers freelook state between game sessions
local FreelookToggleMode = true				-- If true: freelook toggles on/off. If false: key must be held down
local FreelookParallax = true				-- Enables parallax shift while freelooking for realism 
local FreeLookThreshold = 90				-- Max head turn angle before the body begins turning with the camera (degrees) [default: 90]
local RotationSpeed = 2.0					-- Body rotation speed (degrees/frame) [default: 1.0]

--[[ FOV Config ]]--
-- 	 Allows the TFP camera to override the game’s default FOV (Field of View).

local allowCustomFOV = true					-- If true, use custom FOV below while TFP is active
local customFOV = 75     					-- Desired FOV while in TFP mode | Tip: Also adjust Camera ZOffset. Example customFOV = 110 | ZOffset = -10	

--[[ Smooth Movement Config ]]--
--	 When TFP mode is active and smooth movement is enabled, scrolling the mouse wheel will adjust the player's movement speed.

local enableSmoothMovement = false          -- Master toggle: Set enableSmoothMovement to false to disable this feature entirely
local smoothMovementOutsideTFP = false  	-- If true, Set to true to enable outside TFP
local speedUpKey = "MouseScrollUp"          -- Key to increase movement speed (mouse wheel up)
local speedDownKey = "MouseScrollDown"      -- Key to decrease movement speed (mouse wheel down)
local athleticsSmoothScaling = true 		-- If true, Athletics-based speed bonuses scale with scroll:
											-- At min scroll (e.g. 0.60): No Athletics bonus is applied
											-- At max scroll (1.0): Full Athletics bonus is applied
											-- In between: Bonus increases smoothly
											-- Set to false to always apply full Athletics bonus (like vanilla)
											  
local modifierMax = 1.00                    -- Maximum movement speed multiplier
local modifierMin = 0.60                    -- Minimum movement speed multiplier allowed
local minSprintScale = 0.85 				-- Minimum sprint speed multiplier allowed (0.85 - prevents sprint crawling)
local stepAmount = 0.05                     -- Amount to increase/decrease the multiplier per scroll step
local inputCooldown = 0.05                  -- Cooldown (in seconds) between scroll inputs to prevent double inputs
local maxOnSprint = false                   -- When sprinting, set ALL speed multiplier to maximum (1.0). Will reset walk, run and sprint
											-- Tip: Leave maxOnSprint = false. Instead set minSprintScale = 1.0 <- Will only reset sprint

-- ==========================================================================================================
-- === Debug: ===============================================================================================									  
--	 Most players do NOT need to change these. For modders or users with: Custom characters, Non-vanilla races, Unusual skeletons.
--   If your character’s head shadow appears offset or disconnected, you can adjust the vertical offset with "ShadowHeadZOffset" below.

local printDebugLog = false					-- If true, print detailed debug log
local hideHead = true						-- If true, hides the character's head model
local hideHair = true						-- If true, hides the character's hair
local hideHelmet = true						-- If true, hides the equipped helmet mesh
local hideQuiver = true						-- If true, hides quiver mesh (on back)
local drawHiddenShadow = true				-- If true, hidden parts (head, hair, helmet, hoods) cast shadows for realism
local showHeadShadowMesh = false			-- If true, makes the shadow-casting meshes visible (for debugging only)
local resetFadeEachFrame = false			-- If true, fade will be reset on each player tick
local ShadowHeadZOffset = 0.5 				-- Adjusts vertical shadow-casting position of the invisible head (positive = up)
local StableCameraLagSpeed = 8.0			-- These are the stable lag speeds used when HeadBobAmount = 0.0
local StableCameraRotationLagSpeed = 10.0	-- These are the stable lag speeds used when HeadBobAmount = 0.0

local enableNoAnimationLeanFeature = false
enableNoAnimationLeanFeature = NoAnimationLean

-- ==========================================================================================================
-- === Do not change: =======================================================================================

-- Function Declarations
local function StartCameraFollow() end
local function UpdateTFPCamera() end
local function StopCameraFollow() end

-- Cached math functions
local math_sin = math.sin
local math_cos = math.cos
local math_rad = math.rad
local math_abs = math.abs

-- Internal state
local tfpStatePath = "ue4ss/Mods/TFPCamera/tfp_state.txt"
local freelookStatePath = "ue4ss/Mods/TFPCamera/freelook_state.txt"
local originalFOV = nil
local isLoading = false
local firstLoad = false
local activated = false
local freelookActive = false
local isStartingCamera = false
local isUpdatingCamera = false
local wasFreelookBeforeDock = false
local exitingFreelook = false
local FreelookMode = true
local noScrolling = true

-- Player state tracking
local wasRiding = false
local isRiding = false
local wasCrouching = false
local isCrouched = false
local wasDocked = false
local isDocked = false
local inTransition = false
local wasInTransition = false
local didResetAfterDock = false
local transitionCounter = 0

-- Static values
local lastDeltaYaw = 0
local StaticYOffset = 14
local StaticXOffset = -1
local StaticZOffset = 12
local FreelookShift = 8	
local ShadowHeadXOffset = 0	

-- Object References
local controller, character, headRig, bodyRig, camera, altarCameraActor, fade = nil, nil, nil, nil, nil, nil, nil
local headbone = FName("head")
local neckName = FName("neck_02")
local eyeBoneR = FName("FACIAL_R_Pupil")
local eyeBoneL = FName("FACIAL_L_Pupil")
local socketName = FName("FACIAL_C_FacialRoot")
local hasFacialRootSocket = nil 
local amulet = nil
local quiverActor = nil
local WPC = nil

-- Headwear Internal State
local cachedHelmetComponent = nil
local helmetStaticMesh = nil
local sharedHoodMesh = nil
local headwear = nil
local secondHead = nil
local standardHood = nil
local secondHeadOffsetSet = false

-- Hair Internal State
local usePP = false
local hairShadowMesh = nil
local hairMeshInitialized = false

-- Helmet FOV Internal State
local userHelmetFOV = false 
local wasHelmetEquipped = false 
local fovActive = false   

-- Stored original spring lag settings
local originalLagEnable = nil
local originalRotLagEnable = nil
local originalLagSpeed = nil
local originalRotLagSpeed = nil

-- Reusing tables to reduce GC overhead
local TFP_PREALLOC = {
    base    = { X = 0, Y = 0, Z = 0 },
    baseN   = { X = 0, Y = 0, Z = 0 },
    forward = { X = 0, Y = 0 },
    right   = { X = 0, Y = 0 },
    freel   = { X = 0, Y = 0, Z = 0 },
    offset  = { X = 0, Y = 0, Z = 0 },
    target  = { X = 0, Y = 0, Z = 0 },
    offH    = { X = 0, Y = 0, Z = 0 },
    targetX = { X = 0, Y = 0, Z = 0 },
    rot     = { Pitch = 0, Yaw = 0, Roll = 0 },
    camRot  = { Pitch = 0, Yaw = 0, Roll = 0 },
    ctrlRot = { Pitch = 0, Yaw = 0, Roll = 0 }
}

-- Smooth Movement Internal State
local baseSpeed_SM = nil
local onHorse_SM = false
local moveSpeedMod_SM = 1.00
local lastValidInput_SM = 0.0
local smoothHooksRegistered = false

if not enableSmoothMovement then
    smoothMovementOutsideTFP = false
end

-- If smooth movement outside TFP is enabled, block the mouse wheel at initialization.
-- ---------------------------------------------------------------------------
if enableSmoothMovement and smoothMovementOutsideTFP then
    RegisterHook("/Script/Altar.VEnhancedAltarPlayerController:MouseWheelUpInput",
        function(pc)
            local ok, val = pcall(function() return pc:get() end)
            if ok and val then val.bIsPOVChangeLocked = true end
        end,
        function(pc)
            local ok, val = pcall(function() return pc:get() end)
            if ok and val then val.bIsPOVChangeLocked = false end
        end
    )
end

-- Properties to scale when adjusting speed
-- ---------------------------------------------------------------------------
local movementProps_SM = {
    "MoveWalkMax",
    "MoveWalkMin",
    "MoveRunMult",
    "MoveSprintBaseMult",  	
    "MoveSwimRunBase",
    "MoveSwimWalkBase",
    "MoveMaxFlySpeed",
    "MoveMinFlySpeed"
}

-- Conditionally include Athletics scaling
-- ---------------------------------------------------------------------------
if athleticsSmoothScaling then
    table.insert(movementProps_SM, "MoveRunAthleticsMult")
    table.insert(movementProps_SM, "MoveSprintAthleticsMult")
end

-- === Stability Helpers ===
-- Runs a function in protected mode and logs any errors
-- ---------------------------------------------------------------------------
local function safeCall(name, func)
    local ok, err = pcall(func)
    if not ok then
        print("[TFP Camera] ERROR in "..name..": "..tostring(err))
    end
    return ok
end

-- Stores hook IDs so they can be unregistered later
local registeredHooks = {}

-- Wrapper around RegisterHook that stores returned IDs and logs failures
-- ---------------------------------------------------------------------------
local function registerSafeHook(funcPath, pre, post)
    local ok, preId, postId = pcall(RegisterHook, funcPath, pre, post)
    if ok and preId then
        table.insert(registeredHooks, {preId, postId})
    elseif not ok then
        print("[TFP Camera] Failed to register hook "..funcPath..": "..tostring(preId))
    end
end

-- Unregisters all hooks (At the start of StopCameraFollow)
-- ---------------------------------------------------------------------------
local function unregisterAllHooks()
    for _, ids in ipairs(registeredHooks) do
        pcall(UnregisterHook, ids[1], ids[2])
    end
    registeredHooks = {}
end

-- Animation: Neutral Locomotion Overwrite Helpers
-- ---------------------------------------------------------------------------
local moveInput = { 
	forward = false, 
	left = false, 
	right = false, 
	back = false 
	}

if NoAnimationLean then
	local temporarilyEnabledFreelook = false
	function CheckTemporaryFreelook()
		local strafeOnly = (moveInput.left or moveInput.right) and not (moveInput.forward or moveInput.back)
		local diagonal = (moveInput.forward or moveInput.back) and (moveInput.left or moveInput.right)
		local shouldForceFreelook = strafeOnly or diagonal

		if shouldForceFreelook then
			if not freelookActive then
				temporarilyEnabledFreelook = true
				freelookActive = true
			end
		else
			if temporarilyEnabledFreelook then
				exitingFreelook = true -- trigger smooth exit
				temporarilyEnabledFreelook = false
				freelookActive = false -- still disable actual freelook
			end
		end
	end
end

-- === No Leaning (Player-Only) ============================================================================
-- Helper: clear lean blend space on player character's anim instance
-- ---------------------------------------------------------------------------
local function isPlayerCharacter(animInstance)
    if not animInstance or not animInstance:IsValid() then return false end
    local name = animInstance:GetFullName()
    return name:match("OblivionPlayerCharacter") ~= nil
end

local function zeroHumanLean(self)
    if not NoAnimationLean then return end
    if not isPlayerCharacter(self) then return end

    local data = self.LayerData
    if data then
        if data.LeanBlendSpace then
            if printDebugLog then
				print("[NoLeaning] Clearing LeanBlendSpace on " .. tostring(self:GetFullName()))
			end
            data.LeanBlendSpace = nil
        else
			if printDebugLog then
				print("[NoLeaning] LeanBlendSpace is already nil on " .. tostring(self:GetFullName()))
			end
        end
    else
		if printDebugLog then
			print("[NoLeaning] No LayerData found for " .. tostring(self:GetFullName()))
		end
    end
end

-- Safe hook registration helper
-- ---------------------------------------------------------------------------
local function safeHook(funcPath, pre, post)
	local ok, err = pcall(function() RegisterHook(funcPath, pre, post) end)
    if not ok then
        print("[NoLeaning] Warning: could not hook " .. funcPath .. ": " .. tostring(err))
    end
end

-- Hook into creation of player anim instance only
-- ---------------------------------------------------------------------------
if enableNoAnimationLeanFeature then
	NotifyOnNewObject("/Script/Altar.VEnhancedLocomotionSystemCharacterAnimInstance", function(obj)
		if isPlayerCharacter(obj) then
			zeroHumanLean(obj)
		end
	end)

	-- Hooks to wipe lean BS only when player anim blueprint executes
	-- ---------------------------------------------------------------------------

	local enhancedBP = "/Game/Dev/Animation/Templates/ImplementedLayers/Characters/EnhancedLocomotion/TABP_EnhancedLocomotionSystem.TABP_EnhancedLocomotionSystem_C"
	safeHook(enhancedBP .. ":AnimGraph",                function() end, function(self, ...) zeroHumanLean(self) end)
	safeHook(enhancedBP .. ":EnhancedLocomotionLayer",  function() end, function(self, ...) zeroHumanLean(self) end)
	safeHook(enhancedBP .. ":ExecuteUbergraph_TABP_EnhancedLocomotionSystem",
		function() end, function(self, ...) zeroHumanLean(self) end
	)

	-- Intercept state transitions on the anim instance (player-only)
	-- ---------------------------------------------------------------------------
	local transitionHooks = {
		"OnEnterStartState",
		"OnLeftStartState",
		"OnStandSneakTransitionUpdate",
		"OnStandSneakTransitionFinished"
	}

	for _, fn in ipairs(transitionHooks) do
		safeHook("/Script/Altar.VEnhancedLocomotionSystemCharacterAnimInstance:" .. fn,
			function(self, context, node) end,
			function(self, context, node) zeroHumanLean(self) end
		)
	end
end

-- === Persistence Logic ====================================================================================
-- ---------------------------------------------------------------------------

-- TFP state save
local function SaveTFPState()
    if not EnableStateSave then return end
    local file = io.open(tfpStatePath, "w")
    if file then
        file:write(activated and "1" or "0")
        file:close()
    end
end

-- TFP state load
local function LoadTFPState()
    if not EnableStateSave then return false end
    local file = io.open(tfpStatePath, "r")
    if file then
        local contents = file:read("*a")
        file:close()
        return contents == "1"
    end
    return false
end

-- Freelook state save
local function SaveFreelookState()
    if not EnableFreelookStateSave then return end
    local file = io.open(freelookStatePath, "w")
    if file then
        file:write(freelookActive and "1" or "0")
        file:close()
    end
end

-- Freelook state load
local function LoadFreelookState()
    if not EnableFreelookStateSave then return false end
    local file = io.open(freelookStatePath, "r")
    if file then
        local contents = file:read("*a")
        file:close()
        return contents == "1"
    end
    return false
end

-- === Helmet FOV Mapping ==============================================================================================

-- Post Process Materials
-- ---------------------------------------------------------------------------
local ppPattern = "BP_OblivionPlayerCharacter_C_%d+%.NODE_AddPostProcessComponent"
local postProcessComps = {}

-- Find references once (e.g. after the world has loaded)
LoopAsync(100, function()
    postProcessComps = {}
    local comps = FindAllOf("PostProcessComponent")
    for _, comp in ipairs(comps) do
        if comp and comp:IsValid() and comp:GetFullName():match(ppPattern) then
            table.insert(postProcessComps, comp)
        end
    end
    if #postProcessComps > 0 then
        return true
    end
    return false
end)

-- Helper to set blend weight on all components
function SetFovWeight(weight)
    if not postProcessComps or #postProcessComps == 0 then return end
    for _, comp in ipairs(postProcessComps) do
        if comp and comp:IsValid() then
            local arr = comp.Settings.WeightedBlendables.Array
            if arr and #arr > 0 then
                arr[1].Weight = weight
            end
        end
    end
end

-- Post Process Materials Mapping Table
-- ---------------------------------------------------------------------------
local HelmetFOVMaterials = {
    BP_BDP_Amber_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_AmberHelmetFOV.M_AmberHelmetFOV",
	BP_BDP_Elven_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_AmberHelmetFOV.M_AmberHelmetFOV",
    BP_BDP_Blades_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_BladesHelmetFOV.M_BladesHelmetFOV",
    BP_BDP_BloodWorm_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_BloodWormHelmetFOV.M_BloodWormHelmetFOV",
    BP_BDP_Chainmail_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_ChainmailHelmetFOV.M_ChainmailHelmetFOV",
    BP_BDP_ClavicusVile_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_ClavicusVileHelmetFOV.M_ClavicusVileHelmetFOV",
    BP_BDP_Daedric_BoundHelmet = "/Game/Mods/TFPCamera/HelmetFOV/M_DaedricHelmetFOV.M_DaedricHelmetFOV",
    BP_BDP_Daedric_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_DaedricHelmetFOV.M_DaedricHelmetFOV",
    BP_BDP_Dwarven_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_DwarvenHelmetFOV.M_DwarvenHelmetFOV",
    BP_BDP_Ebony_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_EbonyHelmetFOV.M_EbonyHelmetFOV",
    BP_BDP_Amelion_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_EbonyHelmetFOV.M_EbonyHelmetFOV",
    BP_BDP_Fur_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_FurHelmetFOV.M_FurHelmetFOV",
    BP_BDP_Glass_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_GlassHelmetFOV.M_GlassHelmetFOV",
    BP_BDP_Iron_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_IronHelmetFOV.M_IronHelmetFOV",
    BP_BDP_Legion_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_LegionHelmetFOV.M_LegionHelmetFOV",
    BP_BDP_LegionDragon_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_LegionHelmetFOV.M_LegionHelmetFOV",
    BP_BDP_ImperialPalace_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_LegionHelmetFOV.M_LegionHelmetFOV",
    BP_BDP_LegionOld_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_LegionHelmetFOV.M_LegionHelmetFOV",
    BP_BDP_LegionHorseBackGuard_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_LegionHelmetFOV.M_LegionHelmetFOV",
    BP_BDP_Mithril_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_MithrilHelmetFOV.M_MithrilHelmetFOV",
    BP_BDP_Orcish_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_OrcishHelmetFOV.M_OrcishHelmetFOV",
    BP_BDP_OreynBearclaw_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_OreynBearclawHelmetFOV.M_OreynBearclawHelmetFOV",
    BP_BDP_Steel_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_SteelHelmetFOV.M_SteelHelmetFOV",
    BP_BDP_Blackwood_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_SteelHelmetFOV.M_SteelHelmetFOV",
    BP_BDP_Thief_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_LeatherHelmetFOV.M_LeatherHelmetFOV",
    BP_BDP_Pit_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_ThiefHelmetFOV.M_ThiefHelmetFOV",
    BP_BDP_Townguard_Cho_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_TownguardHelmetFOV.M_TownguardHelmetFOV",
    BP_BDP_MythicDawn_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_MythicDawnHelmetFOV.M_MythicDawnHelmetFOV",
    BP_BDP_NDPelinal_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_CrusaderHelmetFOV.M_CrusaderHelmetFOV",
    -- SI
    BP_BDP_GoldenSaint_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_GoldenSaintHelmetFOV.M_GoldenSaintHelmetFOV",
    BP_BDP_GoldenSaint_Helmet_Captain = "/Game/Mods/TFPCamera/HelmetFOV/M_GoldenSaintHelmetFOV.M_GoldenSaintHelmetFOV",
    BP_BDP_DarkSeducer_Helmet_Captain = "/Game/Mods/TFPCamera/HelmetFOV/M_DarkSeducerHelmetFOV.M_DarkSeducerHelmetFOV",
    BP_BDP_DarkSeducer_Helmet_Elite = "/Game/Mods/TFPCamera/HelmetFOV/M_DarkSeducerHelmetFOV.M_DarkSeducerHelmetFOV",
    BP_BDP_DarkSeducer_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_DarkSeducerHelmetFOV.M_DarkSeducerHelmetFOV",
    BP_BDP_Madness_Helmet_Cirion= "/Game/Mods/TFPCamera/HelmetFOV/M_MadnessHelmetFOV.M_MadnessHelmetFOV",
    BP_BDP_Madness_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_MadnessHelmetFOV.M_MadnessHelmetFOV",
    BP_BDP_SE_Order_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_OrderHelmetFOV.M_OrderHelmetFOV",
    -- Hoods and other headwear
    BP_BDP_Mage_Hood = "/Game/Mods/TFPCamera/HelmetFOV/M_GenericHoodFOV.M_GenericHoodFOV",
    BP_BDP_MageArch_Hood = "/Game/Mods/TFPCamera/HelmetFOV/M_GenericHoodFOV.M_GenericHoodFOV",
    BP_BDP_MC_BlackRobe_Hood = "/Game/Mods/TFPCamera/HelmetFOV/M_GenericHoodFOV.M_GenericHoodFOV",
    BP_BDP_KingWorm_Hood = "/Game/Mods/TFPCamera/HelmetFOV/M_GenericHoodFOV.M_GenericHoodFOV",
    BP_BDP_LC_GreyRobe_Hood = "/Game/Mods/TFPCamera/HelmetFOV/M_GenericHoodFOV.M_GenericHoodFOV",
    BP_BDP_LC_Robe01_Hood = "/Game/Mods/TFPCamera/HelmetFOV/M_GenericHoodFOV.M_GenericHoodFOV",
    BP_BDP_LC_Robe02_Hood = "/Game/Mods/TFPCamera/HelmetFOV/M_GenericHoodFOV.M_GenericHoodFOV",
    BP_BDP_LC_Robe03_Hood = "/Game/Mods/TFPCamera/HelmetFOV/M_GenericHoodFOV.M_GenericHoodFOV",
    BP_BDP_MythicDawn_Hood = "/Game/Mods/TFPCamera/HelmetFOV/M_GenericHoodFOV.M_GenericHoodFOV",
    BP_BDP_Necromancer_Hood = "/Game/Mods/TFPCamera/HelmetFOV/M_GenericHoodFOV.M_GenericHoodFOV",
    BP_Generic_BDP_SKH_Hood = "/Game/Mods/TFPCamera/HelmetFOV/M_GenericHoodFOV.M_GenericHoodFOV",
    BP_BDP_SE_Zealot_Hood = "/Game/Mods/TFPCamera/HelmetFOV/M_ZealotHoodFOV.M_ZealotHoodFOV",
    BP_BDP_UC_Robe01_Hood = "/Game/Mods/TFPCamera/HelmetFOV/M_GenericHoodFOV.M_GenericHoodFOV",
    BP_BDP_UC_Robe02_Hood = "/Game/Mods/TFPCamera/HelmetFOV/M_GenericHoodFOV.M_GenericHoodFOV",
    BP_BDP_DarkBrotherhood_Hood = "/Game/Mods/TFPCamera/HelmetFOV/M_DarkBrotherhoodHoodFOV.M_DarkBrotherhoodHoodFOV",
    BP_BDP_CowlOfTheGrayFox = "/Game/Mods/TFPCamera/HelmetFOV/M_GreyfoxHelmetFOV.M_GreyfoxHelmetFOV",
    BP_BDP_DarkBrotherhood_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_GenericHoodFOV.M_GenericHoodFOV",
    -- Mods
    BP_BDP_Arena_Helmet = "/Game/Mods/TFPCamera/HelmetFOV/M_GladiatorHelmetFOV.M_GladiatorHelmetFOV",
    BP_BDP_Arena_HelmetLight = "/Game/Mods/TFPCamera/HelmetFOV/M_GladiatorHelmetFOV.M_GladiatorHelmetFOV",
}
-- === Helpers ==============================================================================================
-- ---------------------------------------------------------------------------
-- Registers a tick hook safely by waiting for the class to load
local function SafeRegisterTickHook(path, handler)
    LoopAsync(100, function()
        local class = StaticFindObject(path:match("(.+):"))
        if class and class:IsValid() then
            RegisterHook(path, handler)
            return true
        end
        return false
    end)
end

-- Waits for a valid object of a given class to appear, with timeout
-- ---------------------------------------------------------------------------
local function WaitForObject(className, timeoutMs)
    local obj = nil
    local waited = 0
    while (not obj or not obj:IsValid()) and waited < timeoutMs do
        obj = FindFirstOf(className)
        if obj and obj:IsValid() then return obj end
        Sleep(10)  
        waited = waited + 10
    end
    return obj
end

-- Checks if the player character is valid (used to confirm game world is ready)
-- ---------------------------------------------------------------------------
local function IsGameWorldReady()
    local char = FindFirstOf("VOblivionPlayerCharacter")
    return char and char:IsValid()
end

-- Scroll Lock Helpers (Smooth Movement)
-- ---------------------------------------------------------------------------
local function LockPOV(pc)
    local ok, val = pcall(function() return pc:get() end)
    if ok and val then
        val.bIsPOVChangeLocked = true
    end
end

local function UnlockPOV(pc)
    local ok, val = pcall(function() return pc:get() end)
    if ok and val then
        val.bIsPOVChangeLocked = false
    end
end

-- Normalizes yaw to [-180, 180] range
-- ---------------------------------------------------------------------------
local function NormalizeYaw(yaw)
    yaw = yaw % 360
    if yaw > 180 then yaw = yaw - 360 end
    return yaw
end

-- Clamps rotation delta to max speed limit
-- ---------------------------------------------------------------------------
local function ClampRotation(delta, speed)
    return math.max(-speed, math.min(speed, delta))
end

-- Resets camera transform safely with pcall
-- ---------------------------------------------------------------------------
local function ResetCamera()
	if camera and camera:IsValid() then
		pcall(function()
			camera:ResetRelativeTransform()
		end)
	end
end

-- Updates static camera Y offset based on character state
-- ---------------------------------------------------------------------------
local function UpdateYOffset(state)
	if state == "crouch" then
		StaticYOffset = StaticYOffset + CrouchOffset
	elseif state == "ride" then
		StaticYOffset = StaticYOffset + RidingOffset
	elseif state == "sit" then
		StaticYOffset = StaticYOffset + SittingOffset
	else
		StaticYOffset = 14
	end
end

-- Checks if head bone is hidden in TFP -> Hide head bone if not hidden
-- ---------------------------------------------------------------------------
local function HideHeadBone()
    if not hideHead then return end
    if not headRig or not headRig:IsValid() then return end
    local ok, hidden = pcall(function() return headRig:IsBoneHiddenByName(headbone) end)
    if ok and not hidden then
        headRig:HideBoneByName(headbone, 0)
    end
end

-- Checks if character has a helmet equipped
-- ---------------------------------------------------------------------------
local function IsHelmetEquipped()
	if not character or not character:IsValid() then return false end
	local CBPC = character.CharacterBodyPairingComponent
	if not CBPC or not CBPC:IsValid() then return false end
	local helmetForm = CBPC:GetBodyPartForm(0)
	return helmetForm and helmetForm:IsValid()
end

-- Hides the quiver actor if equipped and valid
-- ---------------------------------------------------------------------------
local function HideQuiverIfPossible()
	WPC = character and character.WeaponsPairingComponent or nil
	if WPC and WPC:IsValid() and WPC.QuiverActor and WPC.QuiverActor:IsValid() then
		quiverActor = WPC.QuiverActor
		quiverActor:SetActorHiddenInGame(true)
	end
end

-- Finds an object by class and partial name match (regex-friendly)
-- ---------------------------------------------------------------------------
function FindByName(class, name)
    if name == nil then
        class, name = class:match("^(%w+) (.+)$")
    end	
    if class == nil or name == nil then 
		return CreateInvalidObject() 
	end
    local objs = FindAllOf(class) or {}	
    for i = 1, #objs, 1 do
        if objs[i]:GetFullName():match(name) then
            return objs[i]
        end
    end
    return CreateInvalidObject()
end

-- Whitelist for hoods
-- ---------------------------------------------------------------------------
local KnownHoodBlueprints = {
    ["/Game/Forms/items/clothing/DL9TongHood01.DL9TongHood01"] = true,
	["/Game/Forms/items/clothing/DL9TongHood02.DL9TongHood02"] = true,
    ["/Game/Forms/items/clothing/AnotherHood.AnotherHood"] = true }

-- Checks if character has a hood equipped
-- ---------------------------------------------------------------------------
local function IsHoodEquipped()
    if not character or not character:IsValid() then return false end

    local CBPC = character.CharacterBodyPairingComponent
    if not CBPC or not CBPC:IsValid() then return false end

    local helmetForm = CBPC:GetBodyPartForm(0)
    if not helmetForm or not helmetForm:IsValid() then return false end

    local fullName = helmetForm:GetFullName()

    -- Check whitelist match
    if KnownHoodBlueprints[fullName] then
        return true
    end

    -- Fallback: string match "hood" (for unknown hoods)
    local lowerName = string.lower(fullName)
    if string.find(lowerName, "hood") then
        return true
    end

    return false
end

-- Updates the cached StaticMeshComponent of the helmet
-- ---------------------------------------------------------------------------
local function UpdateHelmetStaticMesh()
	if not hideHelmet then return end
	if not cachedHelmetComponent or not cachedHelmetComponent:IsValid() then return end

	local childActor = cachedHelmetComponent:GetChildComponent(0)
	if not childActor or not childActor:IsValid() then
		print("[TFP Camera] No valid child actor on helmet")
		HideHelmetFOV()

		-- No headwear → disable shadow hood
        if drawHiddenShadow and standardHood and standardHood:IsValid() then
            standardHood:SetCastHiddenShadow(false)
			if usePP then
				hairShadowMesh:SetCastHiddenShadow(true)
			end			
		end
		return
	end

	local fullName = childActor:GetFullName()
	local _, pathPart = string.match(fullName, "^(%S+)%s+(.+)$")  
	if not pathPart then
		print("[TFP Camera] Failed to extract path from: " .. fullName)
		return
	end

	-- Clear old mesh refs
	helmetStaticMesh = nil
	sharedHoodMesh = nil

	-- Helmet (static mesh) path logic
	local basePath = string.gsub(pathPart, "%.[^%.]+$", "")
	local staticMeshPath = basePath .. ".StaticMesh"
	local usedFallback = false

	-- Try helmet static mesh
	helmetStaticMesh = FindByName("StaticMeshComponent", staticMeshPath)
	if helmetStaticMesh and helmetStaticMesh:IsValid() then
		helmetStaticMesh:SetVisibility(false, false)
		if drawHiddenShadow then
			helmetStaticMesh:SetCastHiddenShadow(true)
			if usePP then
				hairShadowMesh:SetCastHiddenShadow(false)
			end
		end
	else
		helmetStaticMesh = nil

		-- Try resolving hood skeletal mesh instead
		local hoodMesh = FindByName("SkeletalMeshComponent", basePath .. ".Root Skeletal Mesh")
		if hoodMesh and hoodMesh:IsValid() then
			sharedHoodMesh = hoodMesh
			sharedHoodMesh:SetVisibility(false, false)
			if drawHiddenShadow then
				sharedHoodMesh:SetCastHiddenShadow(true)
				if usePP then
					hairShadowMesh:SetCastHiddenShadow(false)
				end				
			end
		else
			print("[TFP Camera] No valid hood skeletal mesh found")
		end
	end

	-- Set Hood Shadow mesh
	if drawHiddenShadow then
		local hoodEquipped = IsHoodEquipped()
		standardHood:SetCastHiddenShadow(hoodEquipped)
	end
end

-- Update Helmet FOV Pattern
-- ---------------------------------------------------------------------------
function ForceHelmetFOVPatternUpdate()
    if not character or not character:IsValid() then return end
    if not cachedHelmetComponent or not cachedHelmetComponent:IsValid() then return end

    -- Determine the blueprint name of the equipped helmet/hood
    local childActor = cachedHelmetComponent:GetChildComponent(0)
    if not childActor or not childActor:IsValid() then return end
    local fullName = childActor:GetFullName()
    local _, pathPart = string.match(fullName, "^(%S+)%s+(.+)$")
    if not pathPart then return end
    local bpNameFull = string.match(pathPart, "BP_BDP_[%w_]+_C")
    if not bpNameFull then return end
    local bpName = string.gsub(bpNameFull, "_C$", "")

    -- Look up the post-process material for that blueprint
    local newMatPath = HelmetFOVMaterials[bpName]
    if not newMatPath then
        return
    end

    -- Load the material asset
     local mat = StaticFindObject(newMatPath)
    if not mat or not mat:IsValid() then return end

    for _, comp in ipairs(postProcessComps) do
        if comp and comp:IsValid() then
            local settings = comp.Settings
            if settings and settings.WeightedBlendables then
                local arr = settings.WeightedBlendables.Array
                if arr and #arr > 0 then
                    arr[1].Object = mat
                end
            end
        end
    end
end

-- Find the cached SkeletalMeshComponent for dynamic hair
-- ---------------------------------------------------------------------------
local function FindHairMesh()
	if not headRig or not headRig:IsValid() then
		print("[TFP] HeadRig invalid.")
		return
	end

	local children = headRig.AttachChildren
	if not children or #children < 2 then
		print("[TFP] Not enough -AttachChildren- under HeadRig.")
		return
	end
	
	local foundHair = nil
	
	-- Find last valid SkeletalMesh child (assumed to be head hair)
	for i = #children, 2, -1 do 
		local child = children[i]
		if child and child:IsValid() and child.SkeletalMesh and child.SkeletalMesh:IsValid() then
			foundHair = child
			hairMeshInitialized = true
			break
		end
	end


	if not foundHair then
		print("[TFP] Could not find dynamic hair mesh from AttachChildren.")
		return
	end
	cachedHairMesh = foundHair

	if usePP and drawHiddenShadow and hideHair and hairShadowMesh and hairShadowMesh:IsValid() then
		local visualMesh = foundHair.SkeletalMesh
		local skeletalAsset = foundHair.SkeletalMeshAsset
		local skinnedAsset = foundHair.SkinnedAsset

		if visualMesh and visualMesh:IsValid()
			and skeletalAsset and skeletalAsset:IsValid()
			and skinnedAsset and skinnedAsset:IsValid() then

			hairShadowMesh.SkeletalMesh = visualMesh
			hairShadowMesh.SkeletalMeshAsset = skeletalAsset
			hairShadowMesh.SkinnedAsset = skinnedAsset
			hairShadowMesh:SetVisibility(false, false)
			hairShadowMesh:SetCastHiddenShadow(true)
			
			if printDebugLog then
				print("[TFP] Shadow hair mesh copied from dynamic hair (AttachChildren index 2).")
			end
		else
			print("[TFP] One or more mesh fields were invalid.")
		end
	end
end

-- Show Helmet FOV:
-- ---------------------------------------------------------------------------
function ShowHelmetFOV()
    if not activated or not HelmetOverlay then return end
    if not IsHelmetEquipped() and not IsHoodEquipped() then
        SetFovWeight(0.0)
        return
    end
    ForceHelmetFOVPatternUpdate()
    SetFovWeight(1.0)
end

-- Hide Helmet FOV:
-- ---------------------------------------------------------------------------
function HideHelmetFOV()
    if not HelmetOverlay then return end
    SetFovWeight(0.0)
end

-- Clear LookAt target before activation
-- ---------------------------------------------------------------------------
local function ClearPlayerLookAt()
    local lookAtInstances = FindAllOf("TABP_LookAt_C")
    for _, inst in ipairs(lookAtInstances) do
        if inst:GetFullName():match("OblivionPlayerCharacter") then
            inst.K2Node_PropertyAccess_2 = { X = 0, Y = 0, Z = 0 }
        end
    end
end

-- Check (live) riding state
-- ---------------------------------------------------------------------------
local function IsCurrentlyRiding()
    local pc = controller
    if not pc or not pc:IsValid() then pc = FindFirstOf("BP_AltarPlayerController_C") end
    if pc and pc:IsValid() then
        local ok, res = pcall(function() return pc.IsHorseRiding() end)
        if ok then return res == true end
    end
    return false
end

-- Check (live) docking state
-- ---------------------------------------------------------------------------
local function IsCurrentlyDocked()
    local char = character
    if (not char) or (not char:IsValid()) then
		local pc = controller
		if not pc or not pc:IsValid() then
			pc = FindFirstOf("BP_AltarPlayerController_C")
		end
		
        if pc and pc:IsValid() then char = pc.Character end
    end
    return (char and char:IsValid() and char:IsDocked()) or false
end

-- Runs a console command safely using the player controller
-- ---------------------------------------------------------------------------
local function RunConsoleCommand(command)
	local playerController = UEHelpers.GetPlayerController()
	if playerController and playerController:IsValid() then
		KismetSystemLibrary:ExecuteConsoleCommand(playerController.player, command, playerController, false)
	else
		print("[TFP Camera] Could not run console command: player controller invalid.")
	end
end

-- === Smooth Movement Logic =============================================================================
-- Adjusts the movement speed modifier when scroll wheel input events occur. 
-- ---------------------------------------------------------------------------
local function AdjustMovementMod_SM(Context, Key)
    if not enableSmoothMovement then return end
    if not activated and not smoothMovementOutsideTFP then return end
    -- Safely retrieve the key name
    local ok, keyObj = pcall(function() return Key:get() end)
    if not ok or not keyObj then return end
    local keyName = keyObj.KeyName:ToString()
    if keyName == speedUpKey then
        -- prevent double input within the cooldown window
        if os.clock() - lastValidInput_SM < inputCooldown then return end
        moveSpeedMod_SM = math.min(moveSpeedMod_SM + stepAmount, modifierMax)
        lastValidInput_SM = os.clock()
    elseif keyName == speedDownKey then
        if os.clock() - lastValidInput_SM < inputCooldown then return end
        moveSpeedMod_SM = math.max(moveSpeedMod_SM - stepAmount, modifierMin)
        lastValidInput_SM = os.clock()
    end
end

-- Applies the current movement speed modifier to the character.
-- ---------------------------------------------------------------------------
local baseMovement_SM = { initialized = false } -- cache of original values

local function ApplyMovementMod_SM()
    if not enableSmoothMovement or (not activated and not smoothMovementOutsideTFP) then return end

	local scale = moveSpeedMod_SM
    if scale == 1.0 then
        -- No multiplier change; skip rewriting all movement properties
        return
    end
	
    local pc  = controller or FindFirstOf("BP_AltarPlayerController_C")
    if not pc or not pc:IsValid() then return end
    local char = character or pc.Character
    if not char or not char:IsValid() then return end

    if not baseMovement_SM.initialized then
        local move = char.CharacterMovement
        if move and move:IsValid() then
            for _, prop in ipairs(movementProps_SM) do
                local val = move[prop]
                if val ~= nil then
                    baseMovement_SM[prop] = val
                end
            end
            baseMovement_SM.initialized = true
        end
        if not baseSpeed_SM then
            baseSpeed_SM = char.CharacterMovement.MoveRunMult
        end
    end

    local okHorse, isHorse = pcall(function() return pc.IsHorseRiding() end)
    onHorse_SM = okHorse and isHorse or false

    if not onHorse_SM and baseMovement_SM.initialized then
        local move = char.CharacterMovement
        if move and move:IsValid() then
            for prop, baseVal in pairs(baseMovement_SM) do
                if prop ~= "initialized" then
                    local scale = moveSpeedMod_SM

                    -- Clamp sprinting bonus minimum
                    if prop == "MoveSprintBaseMult" and scale < minSprintScale then
                        scale = minSprintScale
                    end

                    -- Fade-in Athletics bonus from scroll min → max
                    if athleticsSmoothScaling and (prop == "MoveRunAthleticsMult" or prop == "MoveSprintAthleticsMult") then
						local t = (moveSpeedMod_SM - modifierMin) / (modifierMax - modifierMin)
						t = math.max(0, math.min(t, 1)) -- clamp to 0–1
						scale = t
					end
                    move[prop] = baseVal * scale
                end
            end
        end
    end
end

-- Hook to set movement speed to maximum when sprint key is released.
-- ---------------------------------------------------------------------------
if maxOnSprint then
    RegisterHook("/Script/Altar.VEnhancedAltarPlayerController:ToggleSprint", function()
        if not enableSmoothMovement then return end
        if not activated then return end
        moveSpeedMod_SM = modifierMax
    end)
end

-- === TFP Mode =============================================================================================
-- Main TFP Head Camera Logic 
-- ---------------------------------------------------------------------------
local function UpdateTFPCamera()

    if isUpdatingCamera then return end
    isUpdatingCamera = true

	local success, err = pcall(function()
		if not activated then return end
		
		-- Cache globals in locals for speed
        local _headRig    = headRig
        local _bodyRig    = bodyRig
        local _character  = character
        local _controller = controller
        local _camera     = camera
		
		if not hasFacialRootSocket then return end
		
		-- Validate objects
        if not (_headRig and _headRig:IsValid() and _bodyRig and _bodyRig:IsValid()
             and _character and _character:IsValid() and _controller and _controller:IsValid()
             and _camera and _camera:IsValid() and hasFacialRootSocket) then
            return
        end

        -- Hide hair mesh if needed
        if hideHair and _headRig.bShouldHideHair == false then
            _headRig:ShouldHideHair(hideHair, false)
        end
		
		-- Handle Helmet FOV Update
		if HelmetOverlay and activated and character and character:IsValid() then
			local helmetNow = IsHelmetEquipped()
			-- Helmet status changed
			if helmetNow ~= wasHelmetEquipped then
				wasHelmetEquipped = helmetNow
				if helmetNow then
					-- New helmet or hood equipped. Update meshes and FOV effect.
					UpdateHelmetStaticMesh()
					ForceHelmetFOVPatternUpdate()
					ShowHelmetFOV()
				else	
					HideHelmetFOV()
				end
			end
		end

		-- Handle docking process
		isDockedInProgress = character:IsInDockingProcess()
		inTransition = false

		if isDockedInProgress and not character:IsDocked() then
			ResetCamera()	
			inTransition = true
			character.bUseControllerRotationYaw = false
			didResetAfterDock = false
		end
		isDocked = character:IsDocked()

		if isDocked then
			inTransition = false
			isDockedInProgress = false
		end
		
		if wasInTransition and not inTransition and not didResetAfterDock then		
			transitionCounter = transitionCounter +1
			didResetAfterDock = true
			
			if transitionCounter == 1 then
				ResetCamera()
			end
						
			if transitionCounter == 2 then
				if not wasFreelookBeforeDock then
					freelookActive = false
					exitingFreelook = true
				end
				ResetCamera()				
				transitionCounter = 0
			end
		end

		if isDocked ~= wasDocked then
			if isDocked then
				UpdateYOffset(isDocked and "sit" or nil)
				wasFreelookBeforeDock = freelookActive
				freelookActive = true
				exitingFreelook = false
				character.bUseControllerRotationYaw = false				
			else
				UpdateYOffset(isDocked and "sit" or nil)
				character.bUseControllerRotationYaw = true			
			end
			wasDocked = isDocked
		end		
		wasInTransition = inTransition

		-- Handle Crouch state change
		isCrouched = character.bIsCrouched or false
		if isCrouched ~= wasCrouching then
			UpdateYOffset(isCrouched and "crouch" or nil)
			wasCrouching = isCrouched
		end

		-- Handle Riding state change
		isRiding = controller.IsHorseRiding()
		if isRiding ~= wasRiding then
			UpdateYOffset(isRiding and "ride" or nil)
			wasRiding = isRiding
		end
		
		-- Freelook Key (toggle or hold)
		if FreelookMode and controller and controller:IsValid() and not isRiding then
			local inputPressed = controller:WasInputKeyJustPressed({ KeyName = FName(FreelookKey) })
			local inputReleased = controller:WasInputKeyJustReleased({ KeyName = FName(FreelookKey) })

			if FreelookToggleMode then
				if inputPressed then
					freelookActive = not freelookActive
					exitingFreelook = not freelookActive
					SaveFreelookState()
				end
			else
				if inputPressed then
					freelookActive = true
					exitingFreelook = false
					SaveFreelookState()
				elseif inputReleased then
					freelookActive = false
					exitingFreelook = true
					SaveFreelookState()
				end
			end
		end	
		
		-- Calculate camera position
		local trR = _headRig:GetBoneTransform(neckName, 0)
        local trN = _bodyRig:GetBoneTransform(headbone, 0)
        local rot = _headRig:GetSocketRotation(socketName)

		-- Reuse table
        local p = TFP_PREALLOC
        local base    = p.base
        local baseN   = p.baseN
        local forward = p.forward
        local right   = p.right
        local freel   = p.freel
        local offset  = p.offset
        local target  = p.target
        local offH    = p.offH
        local targetX = p.targetX

        -- Assign base positions
        base.X,  base.Y,  base.Z  = trR.Translation.X, trR.Translation.Y, trR.Translation.Z
        baseN.X, baseN.Y, baseN.Z = trN.Translation.X, trN.Translation.Y, trN.Translation.Z

        -- Compute direction vectors from yaw
        local yawRad = math_rad(rot.Yaw)
        local s      = math_sin(yawRad)
        local c      = math_cos(yawRad)
        forward.X, forward.Y = c, s
        right.X,   right.Y   = -s, c

		-- Freelook parallax
		freel.X, freel.Y, freel.Z = 0, 0, 0
		if freelookActive and FreelookParallax then
			local yawOffsetRad = math_rad(lastDeltaYaw)
			local backShift = math_sin(yawOffsetRad) * FreelookShift
			local sideShift = -FreelookShift * (math_abs(lastDeltaYaw) / FreeLookThreshold)
			freel.X = right.X * sideShift + forward.X * -backShift
			freel.Y = right.Y * sideShift + forward.Y * -backShift
			-- freel.Z = math.sin(yawOffsetRad) * 1.5
		end

		-- Compute static offsets
        offset.X = forward.X * (YOffset + StaticXOffset) + right.X * (XOffset + StaticYOffset)
        offset.Y = forward.Y * (YOffset + StaticXOffset) + right.Y * (XOffset + StaticYOffset)
        offset.Z = ZOffset + StaticZOffset

        -- Final camera location
        target.X = base.X + offset.X + freel.X
        target.Y = base.Y + offset.Y + freel.Y
        target.Z = base.Z + offset.Z + freel.Z
		
		-- Calculate shadow helmet position 
		local HelmetXOffset = -4.5
        local HelmetYOffset = 0.0
        local HelmetZOffset = 0.0
        offH.X = forward.X * HelmetYOffset + right.X * HelmetXOffset
        offH.Y = forward.Y * HelmetYOffset + right.Y * HelmetXOffset
        offH.Z = HelmetZOffset
		
		-- Final Shadow Helmet location
		targetX.X = baseN.X + offH.X + freel.X
        targetX.Y = baseN.Y + offH.Y + freel.Y
        targetX.Z = baseN.Z + offH.Z + freel.Z
		
		-- Defensive target rotation
		local actorYaw = 0
		if character and character:IsValid() then
			local rot = character:K2_GetActorRotation()
			if rot then actorYaw = NormalizeYaw(rot.Yaw or 0) end
		end
		
		-- Rotation sync
		local camYaw = 0
		local camManager = controller and controller:IsValid() and controller.PlayerCameraManager or nil
		if camManager and camManager:IsValid() then
			local viewRot = camManager:GetCameraRotation()
			if viewRot then camYaw = NormalizeYaw(viewRot.Yaw or 0) end
		end
		
		-- Sync camera rotation during docking process
		if inTransition and camera and camera:IsValid() then
		local dockRot = character:K2_GetActorRotation()
		local currentRot = camera:K2_GetComponentRotation()
			camera:K2_SetWorldRotation({
				Pitch = currentRot.Pitch,
				Yaw = dockRot.Yaw,
				Roll = currentRot.Roll
			}, false, {}, true)
		end

		-- Freelook mode
		if FreelookMode and freelookActive then
			local deltaYaw = NormalizeYaw(camYaw - actorYaw)
	
			if math_abs(deltaYaw) > FreeLookThreshold then
				local sign = deltaYaw > 0 and 1 or -1
				if math_abs(lastDeltaYaw) < FreeLookThreshold then
					lastDeltaYaw = sign * FreeLookThreshold
				end
			else
				lastDeltaYaw = deltaYaw
			end
			
			local desiredYaw = camYaw - lastDeltaYaw
			local step = ClampRotation(NormalizeYaw(desiredYaw - actorYaw), RotationSpeed)
			local newYaw = NormalizeYaw(actorYaw + step)
			character.bUseControllerRotationYaw = false
			
			if not inTransition then
				if isDocked then
					-- Allow freelook rotation but clamp it within a narrow band (e.g. ±15 degrees)
					local delta = NormalizeYaw(newYaw - actorYaw)
					local clampedDelta = math.max(-15, math.min(15, delta))
					local dockedYaw = NormalizeYaw(actorYaw + clampedDelta)
				else
					local r = TFP_PREALLOC.rot
					r.Pitch, r.Yaw, r.Roll = 0, newYaw, 0
					character:K2_SetActorRotation(r, false)
				end
			end 

		elseif exitingFreelook then
			local desiredYaw = camYaw
			local step = ClampRotation(NormalizeYaw(desiredYaw - actorYaw), RotationSpeed * 2)
			local newYaw = NormalizeYaw(actorYaw + step)		
			character.bUseControllerRotationYaw = false
			local r = TFP_PREALLOC.rot
			r.Pitch, r.Yaw, r.Roll = 0, newYaw, 0
			character:K2_SetActorRotation(r, false)		
			
			if math_abs(desiredYaw - actorYaw) < 0.5 then
				exitingFreelook = false
				lastDeltaYaw = 0
				character.bUseControllerRotationYaw = true
			end
		else
			lastDeltaYaw = 0
			character.bUseControllerRotationYaw = not inTransition
		end
		
		-- Clamp deltaYaw if docked
		if isDocked then
			if controller and controller:IsValid() then
				local controlRot = controller:GetDesiredRotation()
				local deltaYaw = NormalizeYaw(controlRot.Yaw - actorYaw)
				local clampedYaw = math.max(-90, math.min(90, deltaYaw))
				local fixedYaw = NormalizeYaw(actorYaw + clampedYaw)

				-- Apply clamped yaw
				controller:SetControlRotation({
					Pitch = controlRot.Pitch,
					Yaw = fixedYaw,
					Roll = controlRot.Roll
				})
			end
		end	

		-- Clamp camera pitch if docked
		if isDocked and not inTransition and not isRiding and camera and camera:IsValid() then
			local camRot = camera:K2_GetComponentRotation()
			if camRot then
				local clampedPitch = math.max(-85, math.min(85, camRot.Pitch))		
				camera:K2_SetWorldRotation({
					Pitch = clampedPitch,
					Yaw = camRot.Yaw,
					Roll = camRot.Roll
				}, false, {}, true)
			end
		end
		
		-- Set final camera target
		pcall(function()
            _camera:K2_SetWorldLocation(target, false, {}, true)
        end)

        -- Update helmet shadow mesh if enabled
        if drawHiddenShadow and helmetStaticMesh and helmetStaticMesh:IsValid()
           and secondHead and secondHead:IsValid() then
            helmetStaticMesh:K2_SetWorldLocation(targetX, false, {}, true)
        end
		
		-- Ensure the head bone stays hidden even after closing map or level reload.
		if hideHead then
			HideHeadBone()
		end		
		
		if resetFadeEachFrame then 
			fade:Deactivate(true)
			fade:Activate(false)
			fade:SetAutoActivate(false)
			fade:SetComponentTickEnabled(false)
			fade:SetTickableWhenPaused(false)
		end
	
    end)
	
	-- Animation: Neutral Locomotion Overwrite
	if NoAnimationLean then
		do
			local wpc = character and character.WeaponsPairingComponent
			local isNeutral = wpc and wpc:IsValid() and (not wpc:IsWeaponDrawn()) and (not wpc:IsTorchHeld())

			if isNeutral and character and character:IsValid() then
				local forward = moveInput.forward
				local back = moveInput.back
				local left = moveInput.left
				local right = moveInput.right

				local direction = nil

				if forward then
					if left then direction = -45
					elseif right then direction = 45 end
				elseif back then
					if left then direction = 45
					elseif right then direction = -45 end
				elseif left and not right then
					direction = -90
				elseif right and not left then
					direction = 90
				end
						
				-- Use in freelook mode function:
				if freelookActive then
					if direction then
						local controlRot = controller:GetControlRotation()
						local baseYaw = NormalizeYaw(controlRot.Yaw)

						local targetYaw = NormalizeYaw(baseYaw + direction)

						local currentRot = character:K2_GetActorRotation()
						local currentYaw = NormalizeYaw(currentRot.Yaw)
						local delta = NormalizeYaw(targetYaw - currentYaw)

						local maxStep = 12.0 -- Smooth turn speed per frame
						local clampedDelta = ClampRotation(delta, maxStep)
						local newYaw = NormalizeYaw(currentYaw + clampedDelta)

						character:K2_SetActorRotation({
							Pitch = currentRot.Pitch,
							Yaw = newYaw,
							Roll = currentRot.Roll
						}, false)
					end
				end
			end
		end
	end
	
	isUpdatingCamera = false
	
    if not success then
        print("[TFP Camera] ERROR in UpdateTFPCamera:\n", err)
        StopCameraFollow()
    end
end

-- === Camera Activation ====================================================================================
-- ---------------------------------------------------------------------------
local function StartCameraFollow()
	
	-- Prevent toggle from vanilla 1st. person
	if character and character.FirstPersonCameraSpringArmComponent 
		and character.FirstPersonCameraSpringArmComponent:IsVisible() then 
		return 
	end
	
	-- Set StartingCamera to prevent it from starting a second time (just in case)
	if isStartingCamera then return end
    isStartingCamera = true
		
	local success, err = pcall(function()
		
		-- Activate and save persistent state
		activated = true
		ClearPlayerLookAt()
		SaveTFPState()
		
		-- Get the Player Controller
		controller = FindFirstOf("BP_AltarPlayerController_C")
		
		-- Search and wait for player (5 Seconds)
		character = WaitForObject("VOblivionPlayerCharacter", 5000)
		if not character then
			print("[TFP Camera] ERROR: Character not found after 5 seconds.\n")
			return
		end
		
		-- Abort TFP activation if no player character is found		
		if not character or not character:IsValid() then return end
			
		-- Get skeletons for head and body components
		headRig = character.HumanoidHeadComponent
		bodyRig = character.MainSkeletalMeshComponent	
		
		-- Cache head socket once
		hasFacialRootSocket = (headRig and headRig:IsValid() and headRig:DoesSocketExist(socketName)) or false
		if not hasFacialRootSocket then
			print("[TFP Camera] Warning: socket "..tostring(socketName).." not found on head rig.")
		end

		-- Get second head & amulet
		local parent = headRig:GetAttachParent()

		-- Loop through attached children
		for i = 0, 50 do
			local child = parent:GetChildComponent(i)

			if not child then
				goto continue
			end

			if not child:IsValid() then
				goto continue
			end

			local fullName = ""
			local ok = pcall(function()
				fullName = child:GetFullName()
			end)

			if ok then
				if fullName:find("Amulet") then
					amulet = child
				end
				if drawHiddenShadow then
					if fullName:find("NODE_AddVHumanoidHeadComponent%-1") then
						secondHead = child
					end
					if fullName:find("NODE_AddVHumanoidHeadComponent%-8") then
						standardHood = child
					end
									
					if fullName:find("NODE_AddVHumanoidHeadComponent%-9") then
						hairShadowMesh = child									
					end							
				end
			else
				print(string.format("[TFP] [%d] <failed to get full name>", i))
			end
			::continue::
		end
		
		if drawHiddenShadow then
			if secondHead and secondHead:IsValid() then				
				-- print("[TFP] Found second HumanoidHeadComponent: " .. secondHead:GetFullName())
			else
				print("[TFP] Could not find second HumanoidHeadComponent")
			end
			
			if standardHood and standardHood:IsValid() then
				standardHood:SetCastHiddenShadow(false)
			else
				print("[TFP] Could not find standard Hood Component")
			end
			
			if hairShadowMesh and hairShadowMesh:IsValid() then
				usePP = true
				hairShadowMesh:SetCastHiddenShadow(true)
			else
				usePP = false
			end		
		end

		if amulet and amulet:IsValid() then
		else
			print("[TFP] Could not find Amulet")
		end		
		
		local parent2 = headRig
		for i = 0, 25 do
			local child = parent2:GetChildComponent(i)

			if not child then
				goto continue
			end

			if not child:IsValid() then
				goto continue
			end

			local fullName = ""
			local ok = pcall(function()
				fullName = child:GetFullName()
			end)

			if ok then
				if fullName:find("Headwear") then
					headwear = child
					break
				end
			else
				print(string.format("[TFP] [%d] <failed to get full name>", i))
			end
			::continue::
		end
		
		-- Calculate shadow head position
		if drawHiddenShadow then
			secondHead:SetCastHiddenShadow(true)
			local currentPos = secondHead:K2_GetComponentLocation()
			if not secondHeadOffsetSet then
				pcall(function()
					local currentPos = secondHead:K2_GetComponentLocation()
					secondHead:K2_SetWorldLocation({
						X = currentPos.X + ShadowHeadXOffset,
						Y = currentPos.Y,
						Z = currentPos.Z + ShadowHeadZOffset
				}, false, {}, true)
				end)
				secondHeadOffsetSet = true
			end
			
			if showHeadShadowMesh then
				secondHead:SetOnlyOwnerSee(false)
			end
		end
		
		-- Find and set shadow hair mesh
		FindHairMesh()
		
		-- Get Camera and Camera Fade Component
		altarCameraActor = FindFirstOf("VAltarCameraActor")
		if not altarCameraActor or not altarCameraActor:IsValid() then return end	
		camera = altarCameraActor.CameraComponent
		fade = altarCameraActor.CharacterFadeInOutComponent
		
		-- Abort if no camera or valid fade component was found
		if not camera or not camera:IsValid() or not fade or not fade:IsValid() then return end
				
		-- Disable Camera Collision check
		character.ThirdPersonCameraSpringArmComponent.bDoCollisionTest = false

		-- Capture original spring lag settings for head-bob smoothing
		if HeadBobAmount ~= 1.0 then
			do
				local springArm = character.ThirdPersonCameraSpringArmComponent
				if springArm and springArm:IsValid() then
					-- Save the originals only the first time we toggle TFP
					if originalLagEnable == nil then
						originalLagEnable = springArm.bEnableCameraLag
						originalRotLagEnable = springArm.bEnableCameraRotationLag
						originalLagSpeed = springArm.CameraLagSpeed
						originalRotLagSpeed = springArm.CameraRotationLagSpeed
					end

					local amount = HeadBobAmount or 1.0  
					local lagSpeed = StableCameraLagSpeed * (1.0 - amount) + originalLagSpeed * amount
					local rotLagSpeed = StableCameraRotationLagSpeed * (1.0 - amount) + originalRotLagSpeed * amount

					-- Enable lag if any smoothing is requested; otherwise restore original enable flags
					if amount < 1.0 then
						springArm.bEnableCameraLag = true
						springArm.bEnableCameraRotationLag = true
					else
						springArm.bEnableCameraLag = originalLagEnable
						springArm.bEnableCameraRotationLag = originalRotLagEnable
					end
					springArm.CameraLagSpeed = lagSpeed
					springArm.CameraRotationLagSpeed = rotLagSpeed
				end
			end
		end

		-- Store original FOV
		originalFOV = camera.FieldOfView
		
		-- Set custom FOV
		if allowCustomFOV then
			RunConsoleCommand("Altar.ThirdPersonFOV " .. tostring(customFOV))
		end
		
		-- Set vanity camera timeout: 2 hours
		RunConsoleCommand("vts.Camera.VanityTimetoActivate 7200")
				
		-- Hide helmet
		if hideHelmet then
			if headwear and headwear:IsValid() then
				cachedHelmetComponent = headwear
				UpdateHelmetStaticMesh()
			end
		end
		
		-- Hide hair meshes:
		if headRig and headRig:IsValid() then
			headRig:ShouldHideHair(hideHair, false)
		end
		
		-- Hide quiver meshes:
		if hideQuiver then
			HideQuiverIfPossible()
		end
		
		-- Disable Mouse Wheel Scolling
		if noScrolling then
			RegisterHook("/Script/Altar.VEnhancedAltarPlayerController:MouseWheelUpInput",
				function(pc)
					local ok, val = pcall(function() return pc:get() end)
					if ok and val then val.bIsPOVChangeLocked = true end
				end,
				function(pc)
					local ok, val = pcall(function() return pc:get() end)
					if ok and val then val.bIsPOVChangeLocked = false end
				end
			)
		end
	
		-- Hide Camera Fade
		if fade and fade:IsValid() then
			pcall(function()
				fade:SetDitherOnCharacterVisibleComponents(character, false, 0.0)
				fade:Deactivate(true)
				fade:SetComponentTickEnabled(false)
				fade:Activate(false)
				fade:SetAutoActivate(false)
				fade:SetComponentTickEnabled(false)
				fade:SetTickableWhenPaused(false)
			end)
		end
		
		-- Hide Head
		if hideHead and headRig and headRig:IsValid() then
			headRig:HideBoneByName(headbone, 0)
		end
		
		-- Update Helmet Overlay
		if HelmetOverlay then
			userHelmetFOV = true
			UpdateHelmetStaticMesh()
			ForceHelmetFOVPatternUpdate()
			ShowHelmetFOV()
		end	

		print("[TFP Camera] TFP Camera ENABLED\n")
	end)
	
	-- On Toggle Off
	isStartingCamera = false
	
	-- When unsolvable error occurs
	if not success then
		print("[TFP Camera] ERROR in StartCameraFollow:\n", err)
		StopCameraFollow()
	end
end

-- === Reset Camera =========================================================================================
-- ---------------------------------------------------------------------------
local function StopCameraFollow()
	activated = false
	SaveTFPState()
	print("[TFP Camera] TFP Camera DISABLED\n")

	-- Remove all hooks registered via registerSafeHook
	unregisterAllHooks()
	
	-- Head visibility 
	if hideHead and headRig and headRig:IsValid() then
		pcall(function()
			headRig:UnHideBoneByName(headbone)
		end)
	end

	--Reset Camera Fade Component
	if fade and fade:IsValid() then
		pcall(function()
			fade:SetComponentTickEnabled(true)
			fade:SetAutoActivate(true)
			fade:Activate(true)
			fade:SetTickableWhenPaused(true)
		end)
	end

	-- Reset Character Rotation
	if character and character:IsValid() then
		character.bUseControllerRotationYaw = false
	end

	-- Reset spring-arm lag settings on exit
	if HeadBobAmount ~= 1.0 then
		do
			local springArm = character and character.ThirdPersonCameraSpringArmComponent
			if springArm and springArm:IsValid() and originalLagEnable ~= nil then
				springArm.bEnableCameraLag = originalLagEnable
				springArm.bEnableCameraRotationLag = originalRotLagEnable
				springArm.CameraLagSpeed = originalLagSpeed
				springArm.CameraRotationLagSpeed = originalRotLagSpeed
			end
		end
	end

	-- Reset Custom FOV
	if allowCustomFOV and controller and controller:IsValid() then
		RunConsoleCommand("Altar.ThirdPersonFOV " .. tostring(originalFOV))
	end

	-- Reset Vanity Camera - 2 Minutes (Game default)
	RunConsoleCommand("vts.Camera.VanityTimetoActivate 120")

	-- Reset Camera Position
	if camera and camera:IsValid() then
		pcall(function() camera:ResetRelativeTransform() end)
	end
	
	-- Enable Camera Collision check
	character.ThirdPersonCameraSpringArmComponent.bDoCollisionTest = true
	
	-- Hair visibility 
	if hideHair and headRig and headRig:IsValid() then
		local shouldHideHair = IsHelmetEquipped()
		headRig:ShouldHideHair(shouldHideHair, false)
	end

	-- Quiver visibility 
	if hideQuiver and quiverActor and quiverActor:IsValid() then
		quiverActor:SetActorHiddenInGame(false)
	end

	-- Shadow visibility 
	if drawHiddenShadow then
		secondHead:SetCastHiddenShadow(false)
		standardHood:SetCastHiddenShadow(false)				
		if usePP then
			hairShadowMesh:SetCastHiddenShadow(false)
		end		
	end
	
	-- Reset for re-evaluation every time TFP is activated.
	hairMeshInitialized = false
	
	-- Re-enable Scrolling
	if noScrolling and not smoothMovementOutsideTFP then
		local function LockPOV(pc) pc:get().bIsPOVChangeLocked = false end
		RegisterHook("/Script/Altar.VEnhancedAltarPlayerController:MouseWheelUpInput", LockPOV, UnlockPOV)
	end		
	
	-- HelmetOverlay visibility
	if HelmetOverlay then
		HideHelmetFOV()
	end
	
	-- Helmet/Hood visibility
	if hideHelmet and cachedHelmetComponent and cachedHelmetComponent:IsValid() and IsHelmetEquipped() then
		if helmetStaticMesh and helmetStaticMesh:IsValid() then
			helmetStaticMesh:SetVisibility(true, false)
			if drawHiddenShadow then
				helmetStaticMesh:SetCastHiddenShadow(false)
				if not showHeadShadowMesh then
					helmetStaticMesh:ResetRelativeTransform()
					helmetStaticMesh:K2_SetRelativeRotation({ Pitch = -90.0, Yaw = 0.0, Roll = 0.0 }, false, {}, true)
				end
			end
		elseif sharedHoodMesh and sharedHoodMesh:IsValid() then
			sharedHoodMesh:SetVisibility(true, false)
			if drawHiddenShadow then
				sharedHoodMesh:SetCastHiddenShadow(false)
			end
		else
			-- print("[TFP Camera] No helmet or hood mesh found to unhide")
		end
	end
	
	-- Restore original movement values
	if enableSmoothMovement and not smoothMovementOutsideTFP and character and character:IsValid() then
		-- restore cached multipliers
		if baseMovement_SM.initialized then
			local move = character.CharacterMovement
			for prop, baseVal in pairs(baseMovement_SM) do
				if prop ~= "initialized" then
					move[prop] = baseVal
				end
			end
		end
		-- restore MoveRunMult
		if baseSpeed_SM then
			character.CharacterMovement.MoveRunMult = baseSpeed_SM
		end
		-- reset for next activation
		moveSpeedMod_SM = 1.00
		baseSpeed_SM    = nil
		lastValidInput_SM = 0.0
		baseMovement_SM = { initialized = false }
	end
end

-- === Input Binding & Game Hooks ==========================================================================

-- Toggle TFP Camera Hook
-- ---------------------------------------------------------------------------
RegisterKeyBind(toggle_key, function()
    if activated then 
		StopCameraFollow() 
	else 
		StartCameraFollow() 
	end
end)

-- Toggle Helmet Overlay Hook
-- ---------------------------------------------------------------------------
RegisterKeyBind(hide_FOV_key, function()
	if not HelmetOverlay then return end -- new fix
    fovActive = not fovActive
    local weight = fovActive and 1.0 or 0.0
    SetFovWeight(weight)
end)

-- Find Player Character Hook
-- ---------------------------------------------------------------------------

LoopAsync(50, function()
    local char = FindFirstOf("VOblivionPlayerCharacter")
    if char and char:IsValid() then
        registerSafeHook(
            "/Game/Dev/PlayerBlueprints/BP_OblivionPlayerCharacter.BP_OblivionPlayerCharacter_C:ReceiveTick",
            function(context)
                ExecuteInGameThread(function()
                    safeCall("UpdateTFPCamera", UpdateTFPCamera)
                end)
            end
        )
        return true
    end
    return false
end)

-- Reset Camera Hook
-- ---------------------------------------------------------------------------
RegisterHook("/Script/Altar.VAltarPlayerCameraManager:SetCurrentCameraSetting", function()
	if activated and headRig and headRig:IsValid() then
		LoopAsync(80, function()
			ExecuteInGameThread(function()
				if hideHead then headRig:HideBoneByName(headbone, 0) end				
				if hideHelmet and cachedHelmetComponent and cachedHelmetComponent:IsValid() then
					UpdateHelmetStaticMesh()
				end			
			end)	
			return true 
		end)	
		ForceHelmetFOVPatternUpdate()
		ShowHelmetFOV()
	end
end)

-- Close Menu Hook
-- ---------------------------------------------------------------------------
RegisterHook("/Script/Altar.VPlayerMenuViewModel:RegisterCloseMenuHandler", function()
	ExecuteInGameThread(function()
		if activated then
			if hideHead then 
				headRig:HideBoneByName(headbone, 0) 
			end		
				
			if hideQuiver then
				HideQuiverIfPossible()
			end
			
			if hideHelmet then
				if helmetStaticMesh and helmetStaticMesh:IsValid() then
					helmetStaticMesh:SetVisibility(true, false)
					helmetStaticMesh:SetCastHiddenShadow(false)
				end
				helmetStaticMesh = nil

				if sharedHoodMesh and sharedHoodMesh:IsValid() then
					sharedHoodMesh:SetVisibility(true, false)
					sharedHoodMesh:SetCastHiddenShadow(false)
				end
				sharedHoodMesh = nil

				if cachedHelmetComponent and cachedHelmetComponent:IsValid() then
					UpdateHelmetStaticMesh()
				end
			end
		else
			return
		end	
		
		if activated and not hairMeshInitialized then
			if not IsHelmetEquipped() and not IsHoodEquipped() then
				print("[TFP] Retrying hair mesh setup after helmet was unequipped.")
				FindHairMesh()
			end
		end
	end)
	-- Show Helmet Overlay
	ForceHelmetFOVPatternUpdate()
	ShowHelmetFOV()	
end)

-- Fade to Black Hook 
-- ---------------------------------------------------------------------------
RegisterHook("/Script/Altar.VLevelChangeData:OnFadeToBlackBeginEventReceived", function()
	isLoading = true
	if userHelmetFOV then
		HelmetOverlay = false
	end
end)

-- Gamestart Hook 
-- ---------------------------------------------------------------------------
RegisterHook("/Script/Altar.VLevelChangeData:OnFadeToGameBeginEventReceived", function()
    if not LoadTFPState() then return end
	local maxRetries = 500
	local retries = 0
	
	LoopAsync(100, function()
		retries = retries + 1
		if retries > maxRetries then return true end
		if not IsGameWorldReady() then return false end	
		
		local char = FindFirstOf("VOblivionPlayerCharacter")
		local camActor = FindFirstOf("VAltarCameraActor")
		local head = char and char.HumanoidHeadComponent
		local fadeComp = camActor and camActor.CharacterFadeInOutComponent

		if char and camActor and head and fadeComp
			and char:IsValid() and camActor:IsValid()
			and head:IsValid() and fadeComp:IsValid() then
			
			firstLoad = true
			StartCameraFollow()
			
            if LoadFreelookState() then
                freelookActive = true
                exitingFreelook = false
            end	
			return true
		end
		return false
	end)
	isLoading = false
	
	if userHelmetFOV then
		HelmetOverlay = true
	end
	
	if activated and hideHead and headRig and headRig:IsValid() then
		headRig:HideBoneByName(headbone, 0)
	end
end)

-- Hide Helmet Overlay on Pause Menu
-- ---------------------------------------------------------------------------
RegisterHook("/Script/Altar.VPlayerMenuViewModel:RegisterOpenPauseMenuHandler", function()
	HideHelmetFOV()
end)

-- Show Helmet Overlay after Pause Menu
-- ---------------------------------------------------------------------------
RegisterHook("/Script/Altar.VPlayerMenuViewModel:RegisterClosePauseMenuHandler", function()
	ForceHelmetFOVPatternUpdate()
	if activated and hideHead and headRig and headRig:IsValid() then
		headRig:HideBoneByName(headbone, 0)
	end
	ShowHelmetFOV()
end)

-- Hook into TABP_LookAt and set target in front of camera
-- ---------------------------------------------------------------------------
RegisterHook("Function /Game/Dev/Animation/Templates/ImplementedLayers/Characters/TABP_LookAt.TABP_LookAt_C:EvaluateGraphExposedInputs_ExecuteUbergraph_TABP_LookAt_AnimGraphNode_AdvancedLookAt_A0FAD3894A8BA22925668A80995EC038",
function(lookAt)
    local lookAt = lookAt:get() ---@cast lookAt UTABP_LookAt_C
    if not activated then return end
    if not lookAt:GetFullName():match("OblivionPlayerCharacter") then return end
    
    local PlayerController = UEHelpers.GetPlayerController()
    if not PlayerController or not PlayerController:IsValid() then return end

    local CameraManager = PlayerController.PlayerCameraManager
    if not CameraManager or not CameraManager:IsValid() then return end

    local cameraLocation = CameraManager:GetCameraLocation()
    local cameraRotation = CameraManager:GetCameraRotation()
    if not cameraLocation or not cameraRotation then return end

    local yawRad = math_rad(cameraRotation.Yaw)
    local pitchRad = math_rad(cameraRotation.Pitch)
    local offsetDistance = 200.0

    local forward = {
        X = math_cos(pitchRad) * math_cos(yawRad),
        Y = math_cos(pitchRad) * math_sin(yawRad),
        Z = math_sin(pitchRad)
    }

    local targetLocation = {
        X = cameraLocation.X + forward.X * offsetDistance,
        Y = cameraLocation.Y + forward.Y * offsetDistance,
        Z = cameraLocation.Z + forward.Z * offsetDistance
    }	
    lookAt.K2Node_PropertyAccess_2 = targetLocation
end)

-- === Smooth Movement Hooks =========================================================================

-- Register hooks for smooth movement adjustments. 
-- ---------------------------------------------------------------------------
if enableSmoothMovement and not smoothHooksRegistered then
    -- Character tick hook: apply movement modifier each tick
    LoopAsync(3000, function()
        return pcall(RegisterHook,
            "/Game/Dev/PlayerBlueprints/BP_OblivionPlayerCharacter.BP_OblivionPlayerCharacter_C:ReceiveTick",
            ApplyMovementMod_SM)
    end)

    -- Input hook: adjust movement modifier on scroll events
    LoopAsync(3000, function()
        return pcall(RegisterHook,
            "/Game/Dev/Controllers/BP_AltarPlayerController.BP_AltarPlayerController_C:InpActEvt_AnyKey_K2Node_InputKeyEvent_1",
            AdjustMovementMod_SM)
    end)
    -- Set the flag so hooks are not registered again
    smoothHooksRegistered = true
end

--=== No Animation-Lean ==============================================================================

-- Movement Input Pressed Hooks
-- ---------------------------------------------------------------------------
if enableNoAnimationLeanFeature then
    local function onPress(dir)
        -- Skip while riding or docked (live state)
        if IsCurrentlyRiding() or IsCurrentlyDocked() then return end
        moveInput[dir] = true
        CheckTemporaryFreelook()
    end

    local function onRelease(dir)
        -- Skip while riding or docked (live state)
        if IsCurrentlyRiding() or IsCurrentlyDocked() then return end
        moveInput[dir] = false
        CheckTemporaryFreelook()
    end

    RegisterHook("/Script/Altar.VEnhancedAltarPlayerController:MovementLeftInput_Pressed", function()
        onPress("left")
    end)
    RegisterHook("/Script/Altar.VEnhancedAltarPlayerController:MovementRightInput_Pressed", function()
        onPress("right")
    end)
    RegisterHook("/Script/Altar.VEnhancedAltarPlayerController:MovementForwardInput_Pressed", function()
        onPress("forward")
    end)
    RegisterHook("/Script/Altar.VEnhancedAltarPlayerController:MovementBackwardInput_Pressed", function()
        onPress("back")
    end)

    RegisterHook("/Script/Altar.VEnhancedAltarPlayerController:MovementLeftInput_Released", function()
        onRelease("left")
    end)
    RegisterHook("/Script/Altar.VEnhancedAltarPlayerController:MovementRightInput_Released", function()
        onRelease("right")
    end)
    RegisterHook("/Script/Altar.VEnhancedAltarPlayerController:MovementForwardInput_Released", function()
        onRelease("forward")
    end)
    RegisterHook("/Script/Altar.VEnhancedAltarPlayerController:MovementBackwardInput_Released", function()
        onRelease("back")
    end)
end