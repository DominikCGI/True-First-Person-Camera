-- PlayerCamera TFP version (reworked, toggle-based, safe tick, neutral locomotion support) 
print("[TFP Camera: Player Camera] Player Camera Initialized\n")

-- === Configurables: =======================================================================================

local toggle_key = Key.P  					-- press P to toggle this mod on/off
local combatAsNeutral = true				-- If true, combat will behave like neutral locomotion (orient to movement).
local rotateDuringAttack = true				-- if true, face the crosshair while attacking (Need: combatAsNeutral = true)
local rotationSpeed = 6.0 					-- degrees per tick used for rotationSpeed (default = 6.0) 	

-- ==========================================================================================================
-- === Do not change: =======================================================================================

local activated = false
local controller, player, springArm, targetYaw = nil, nil, nil, nil
local AnimTime = 0
local ANIM_TIME_BLOCK = 0.2
local ANIM_TIME_SPELL = 1.4
local ANIM_TIME_BOW   = 0.6

-- === Persistence Logic ====================================================================================
-- ---------------------------------------------------------------------------
local pcStatePath = "ue4ss/Mods/PlayerCamera/pc_state.txt"

local function SavePCState()
    local f = io.open(pcStatePath, "w")
    if f then
        f:write(activated and "1" or "0")
        f:close()
    end
end

local function LoadPCState()
    local f = io.open(pcStatePath, "r")
    if f then
        local contents = f:read("*all")
        f:close()
        return contents == "1"
    end
    return false
end

-- === TFP Logic ============================================================================================
-- ---------------------------------------------------------------------------
local tfpStatePath = "ue4ss/Mods/TFPCamera/tfp_state.txt"

-- Reads the TFP state file; returns true if TFP is active
local function LoadTFPState()
    local f = io.open(tfpStatePath, "r")
    if f then
        local contents = f:read("*all")
        f:close()
        return contents == "1"
    end
    return false
end

local wasPCActiveBeforeTFP = false

-- === Player Camera Logic =================================================================================
-- ---------------------------------------------------------------------------

-- Save original camera flags so they can be restored when disabling
-- ---------------------------------------------------------------------------
local origSettings = { saved = false }

-- Update references to controller, player and spring arm
-- ---------------------------------------------------------------------------
local function UpdatePlayer()
    controller = controller or FindFirstOf("BP_AltarPlayerController_C")
    if not (controller and controller:IsValid()) then
        player    = nil
        springArm = nil
        return
    end
    player = controller.Character
    if player and player:IsValid() then
        springArm = player.ThirdPersonCameraSpringArmComponent
    else
        springArm = nil
    end
end

-- Save the current settings once before we start modifying them
-- ---------------------------------------------------------------------------
local function SaveOriginalSettings()
    if origSettings.saved then return end
    UpdatePlayer()
    if player and player:IsValid() and springArm and springArm:IsValid() then
        local move = player.CharacterMovement
        if move and move:IsValid() then
            origSettings.bUsePawnControlRotation   = springArm.bUsePawnControlRotation
            origSettings.bUseControllerRotationYaw = player.bUseControllerRotationYaw
            origSettings.bOrientRotationToMovement = move.bOrientRotationToMovement
            origSettings.bUseControllerDesiredRotation = move.bUseControllerDesiredRotation
            origSettings.saved = true
        end
    end
end

-- Restore saved settings (called when disabling)
-- ---------------------------------------------------------------------------
local function RestoreOriginalSettings()
    if not origSettings.saved then return end
    UpdatePlayer()
    if player and player:IsValid() and springArm and springArm:IsValid() then
        local move = player.CharacterMovement
        if move and move:IsValid() then
            springArm.bUsePawnControlRotation   = origSettings.bUsePawnControlRotation
            player.bUseControllerRotationYaw    = origSettings.bUseControllerRotationYaw
            move.bOrientRotationToMovement      = origSettings.bOrientRotationToMovement
            move.bUseControllerDesiredRotation  = origSettings.bUseControllerDesiredRotation
        end
    end
end

-- Apply camera flags only when mod is activated
-- ---------------------------------------------------------------------------
local function SetCameraBehavior(bLockCamera, bLockRotation, bOrientToMovement)
    if not activated then return end
    if player and player:IsValid() and springArm and springArm:IsValid() then
        local move = player.CharacterMovement
        if move and move:IsValid() then
            springArm.bUsePawnControlRotation   = bLockCamera
            player.bUseControllerRotationYaw    = bLockRotation
            move.bOrientRotationToMovement      = bOrientToMovement
            move.bUseControllerDesiredRotation  = not bOrientToMovement
        end
    end
end

-- Detect first-person mode
-- ---------------------------------------------------------------------------
local function IsFirstPerson()
    return player and player.FirstPersonCameraSpringArmComponent and player.FirstPersonCameraSpringArmComponent:IsVisible()
end

-- Detect combat by checking weapon or torch status
-- ---------------------------------------------------------------------------
local function IsPlayerInCombat()
    if not (player and player:IsValid()) then return false end
    local wpc = player.WeaponsPairingComponent
    if wpc and wpc:IsValid() then
        if wpc:IsWeaponDrawn() then return true end
        if wpc:IsTorchHeld() then return true end
    end
    return false
end

-- Action lock: called on block, spell and bow
-- ---------------------------------------------------------------------------
local function HandleActionLock(duration)
    if not activated then return end
    if not IsFirstPerson() then
        SetCameraBehavior(true, false, false)
        if duration then
            AnimTime = os.clock() + duration
        end
    end
end

local function HandleActionRelease()
    if not activated then return end
    if not IsFirstPerson() then
        if IsPlayerInCombat() then
            if combatAsNeutral then
                SetCameraBehavior(true, false, true)
            else
                SetCameraBehavior(true, false, false)
            end
        else
            SetCameraBehavior(true, false, true)
        end
    end
end

-- Enable and disable functions
-- ---------------------------------------------------------------------------
local function EnablePlayerCamera()
    SaveOriginalSettings()
    activated = true
    AnimTime = 0
    UpdatePlayer()
    if player and player:IsValid() then
        SetCameraBehavior(true, false, true)
    end
    print("[PlayerCamera] Enabled")
end

local function DisablePlayerCamera()
    if not activated then return end
    activated = false
    AnimTime = 0
    RestoreOriginalSettings()
    print("[PlayerCamera] Disabled")
end

-- Toggle Player Camera Hook
-- ---------------------------------------------------------------------------
RegisterKeyBind(toggle_key, function()
    if LoadTFPState() then
        -- Optionally print a message to the log
        print("[PlayerCamera] TFP is active; PlayerCamera cannot be toggled.")
        return
    end
    if activated then
        DisablePlayerCamera()
    else
        EnablePlayerCamera()
    end
    SavePCState()
end)

-- Gamestart Hook 
-- ---------------------------------------------------------------------------
RegisterHook("/Script/Altar.VLevelChangeData:OnFadeToGameBeginEventReceived", function()
    -- Wait until the player character exists, then restore the camera state.
    LoopAsync(100, function()
        local class = StaticFindObject("/Game/Dev/PlayerBlueprints/BP_OblivionPlayerCharacter.BP_OblivionPlayerCharacter_C")
        if class then
            local pcWasSavedActive = LoadPCState()
            local tfpActive        = LoadTFPState()

            if tfpActive then
                -- Do not enable PC now; remember if it was saved as active
                if pcWasSavedActive then
                    wasPCActiveBeforeTFP = true
                end
            else
                -- If TFP isn’t active, restore PC if it was saved as active
                if pcWasSavedActive then
                    EnablePlayerCamera()
                end
            end
            return true
        end
        return false
    end)
end)

-- Defer tick hook registration until the class is loaded (Safe pattern)
-- ---------------------------------------------------------------------------
LoopAsync(100, function()
    local class = StaticFindObject("/Game/Dev/PlayerBlueprints/BP_OblivionPlayerCharacter.BP_OblivionPlayerCharacter_C")
    if class and class:IsValid() then
        RegisterHook("/Game/Dev/PlayerBlueprints/BP_OblivionPlayerCharacter.BP_OblivionPlayerCharacter_C:ReceiveTick", function(Context, _)
            if not activated then return end
			UpdatePlayer()
			if not (player and player:IsValid() and springArm and springArm:IsValid()) then return end

			if IsFirstPerson() then
				SetCameraBehavior(false, true, false)
				return
			end

			-- === Smooth attack rotation logic ===
			if rotateDuringAttack and targetYaw and player and player:IsValid() then
				local rot = player:K2_GetActorRotation()
				local currentYaw = rot.Yaw
				local delta = (targetYaw - currentYaw + 540) % 360 - 180

				if math.abs(delta) < 1.0 then
					-- Rotation complete
					rotateDuringAttack = false
					targetYaw = nil
				else
					-- Smooth rotation step
					local step = math.max(-rotationSpeed, math.min(rotationSpeed, delta))
					local newYaw = currentYaw + step
					player:K2_SetActorRotation({ Pitch = rot.Pitch, Yaw = newYaw, Roll = rot.Roll }, false)
				end
			end

			-- otherwise, apply normal combat logic
			if player:IsAttacking() or IsPlayerInCombat() then
				if combatAsNeutral then
					SetCameraBehavior(true, false, true)
				else
					SetCameraBehavior(true, false, false)
				end
				return
			end
			
			if os.clock() < AnimTime then
				return
			end

			-- Neutral locomotion behaviour
			SetCameraBehavior(true, false, true)
        end)
        return true
    end
    return false
end)

-- Action hooks (block, spell, bow)
-- ---------------------------------------------------------------------------
RegisterHook("/Script/Altar.VEnhancedAltarPlayerController:BlockInput_Pressed", function(ctx)
    if not activated then return end
    if not ctx or not ctx.Context or not ctx.Context:IsValid() then return end
    UpdatePlayer()
    HandleActionLock(ANIM_TIME_BLOCK)
end)

-- BlockInput Released hook
-- ---------------------------------------------------------------------------
RegisterHook("/Script/Altar.VEnhancedAltarPlayerController:BlockInput_Released", function(ctx)
    if not activated then return end
    if not ctx or not ctx.Context or not ctx.Context:IsValid() then return end
    UpdatePlayer()
    HandleActionRelease()
end)

local spellCastHooks = {
    "OnCastTargeRightEnter",
    "OnCastTargetLeftEnter",
    "OnCastTouchLeftEnter",
    "OnCastTouchRightEnter",
}
for _, fn in ipairs(spellCastHooks) do
    RegisterHook("/Script/Altar.VSpellCastSingleAnimInstance:" .. fn, function(ctx)
        if not activated then return end
        if not ctx or not ctx.Context or not ctx.Context:IsValid() then return end
        UpdatePlayer()
        HandleActionLock(ANIM_TIME_SPELL)
    end)
end

-- Attack pressed: lock to crosshair if the feature is enabled
-- ---------------------------------------------------------------------------
RegisterHook("/Script/Altar.VEnhancedAltarPlayerController:OnAttackRequestPressed", function(ctx)
    if not activated then return end
    if not ctx or not ctx.Context or not ctx.Context:IsValid() then return end
    UpdatePlayer()

    -- Store target yaw from controller
    if controller and controller:IsValid() and player and player:IsValid() then
        local ctrlRot = controller:GetControlRotation()
        if ctrlRot then
            targetYaw = ctrlRot.Yaw
            rotateDuringAttack = true
        end
    end

    HandleActionLock(ANIM_TIME_BOW)
end)

-- Attack released: restore the appropriate orientation
-- ---------------------------------------------------------------------------
RegisterHook("/Script/Altar.VEnhancedAltarPlayerController:OnAttackRequestReleased", function(ctx)
    if not activated then return end
    if not ctx or not ctx.Context or not ctx.Context:IsValid() then return end
    UpdatePlayer()
end)

-- Compass logic: use custom north when mod is active; otherwise use default yaw
-- ---------------------------------------------------------------------------
local marker = nil
local compassCtrl = nil

local function GetNorthMarkerYaw()
    if not (marker and marker:IsValid()) then
        marker = FindFirstOf("BP_NorthMarker_C")
        if not (marker and marker:IsValid()) then return 0.0 end
    end
    local rot = marker:K2_GetActorRotation()
    return rot and rot.Yaw or 0.0
end

local function GetCameraYaw()
    local ctrl = compassCtrl
    if not (ctrl and ctrl:IsValid()) then
        ctrl = FindFirstOf("BP_AltarPlayerController_C")
        if not (ctrl and ctrl:IsValid()) then return 0.0 end
        compassCtrl = ctrl
    end
    local rot = ctrl:GetControlRotation()
    return rot and ((rot.Yaw + 90.0) % 360.0) or 0.0
end

local function GetCompassNorth()
    local camYaw    = GetCameraYaw()
    local markerYaw = GetNorthMarkerYaw()
    return (camYaw - markerYaw) % 360.0
end

NotifyOnNewObject("/Script/Altar.AltarCommonGameViewportClient", function(viewPort)
    RegisterHook("/Script/Altar.VHUDMainViewModel:GetCompassDirectionValue", function(self)
        if not activated then
            return GetCameraYaw()
        end
        local world = viewPort.World:GetFullName()
        if not world:find("World/") then
            return GetCompassNorth()
        end
        return GetCameraYaw()
    end)
end)

-- Check TFP State every 1000ms and adjust PlayerCamera accordingly
-- ---------------------------------------------------------------------------
LoopAsync(1000, function()
    local tfpActive = LoadTFPState()

    if tfpActive then
        -- TFP became active and PlayerCamera is on -> disable it and remember that it was on
        if activated then
            wasPCActiveBeforeTFP = true
            DisablePlayerCamera()
        end
    else
        -- TFP not active; Enable PlayerCamera only if it was active before TFP was turned on
        if wasPCActiveBeforeTFP and not activated then
            EnablePlayerCamera()
        end
        wasPCActiveBeforeTFP = false
    end
    return false
end)