-- Connected Discord-Github

-- services to avoid requesting them them again and again in the script
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- cache player and ui because they are reused by the movement system
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local ScreenGui = PlayerGui:WaitForChild("Parkour")
local BarBackground = ScreenGui:WaitForChild("StaminaBackground")
local BarFill = BarBackground:WaitForChild("StaminaFill")
local BarText = BarBackground:WaitForChild("StaminaText")

-- gameplay config so it is easy tochange settings
local SETTINGS = {
    MaxStamina = 100,
    StaminaDrain = 22,
    StaminaRegen = 17,

    WalkSpeed = 16,
    SprintSpeed = 25,

    JumpPower = 52,
    DoubleJumpPower = 48,

    WallJumpPower = 55,
    WallJumpForward = 38,
    WallDistance = 4,
    WallCooldown = 0.25,

    WallJumpCost = 15,
    DoubleJumpCost = 12,

    MaxJumps = 2,
    WallNormalThreshold = 0.25,

    SprintKey = Enum.KeyCode.LeftControl,
    StaminaTextPrefix = "STAMINA ",
}

-- store current character references so movement functions can safely check character availability
local Character: Model? = nil
local Humanoid: Humanoid? = nil
local RootPart: BasePart? = nil

-- track temporary movement state so it can be reset whenever a new character spawns
local Stamina = SETTINGS.MaxStamina
local JumpCount = 0
local IsSprinting = false
local LastWallJump = 0

-- group temporary character connections together so they can all be cleaned up during respawns
local CharacterConnections = {}

-- exclude the player's character from raycasts so wall detection only checks other objects
local RaycastSettings = RaycastParams.new()
RaycastSettings.FilterType = Enum.RaycastFilterType.Exclude

-- update the stamina ui using the current stamina percentage to control fill size and color
local function UpdateStaminaBar()
    local Percentage = math.clamp(
        Stamina / SETTINGS.MaxStamina,
        0,
        1
    )

    BarFill.Size = UDim2.fromScale(Percentage, 1)

    BarFill.BackgroundColor3 = Color3.new(
        1 - Percentage,
        Percentage,
        0.3
    )

    BarText.Text = SETTINGS.StaminaTextPrefix .. math.floor(Stamina)
end

-- apply stamina changes within valid limits and refresh the ui after every update
local function ChangeStamina(Amount)
    Stamina = math.clamp(
        Stamina + Amount,
        0,
        SETTINGS.MaxStamina
    )

    UpdateStaminaBar()
end

-- disconnect old character connections so previous characters cannot modify current movement state
local function CleanupCharacterConnections()
    for _, Connection in CharacterConnections do
        Connection:Disconnect()
    end

    table.clear(CharacterConnections)
end

-- check four horizontal directions for nearby walls and ignore surfaces that are too horizontal
local function GetWallNormal(): Vector3?
    if not RootPart then
        return nil
    end

    local Directions = {
        RootPart.CFrame.RightVector,
        -RootPart.CFrame.RightVector,
        RootPart.CFrame.LookVector,
        -RootPart.CFrame.LookVector,
    }

    for _, Direction in Directions do
        local Result = Workspace:Raycast(
            RootPart.Position,
            Direction * SETTINGS.WallDistance,
            RaycastSettings
        )

        if Result and math.abs(Result.Normal.Y) < SETTINGS.WallNormalThreshold then
            return Result.Normal
        end
    end

    return nil
end

-- launch the player away from a nearby wall when enough stamina is available and the cooldown has expired
local function PerformWallJump(): boolean
    if not Humanoid or not RootPart then
        return false
    end

    if os.clock() - LastWallJump < SETTINGS.WallCooldown then
        return false
    end

    if Stamina < SETTINGS.WallJumpCost then
        return false
    end

    local WallNormal = GetWallNormal()

    if not WallNormal then
        return false
    end

    -- record the jump time and consume stamina before applying velocity to prevent repeated requests bypassing restrictions
    LastWallJump = os.clock()
    ChangeStamina(-SETTINGS.WallJumpCost)

    JumpCount = 1

    Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

    -- use the wall normal for horizontal movement and configured jump power for vertical movement
    RootPart.AssemblyLinearVelocity = Vector3.new(
        WallNormal.X * SETTINGS.WallJumpForward,
        SETTINGS.WallJumpPower,
        WallNormal.Z * SETTINGS.WallJumpForward
    )

    return true
end

-- allow one additional airborne jump while preserving existing horizontal momentum
local function PerformDoubleJump(): boolean
    if not Humanoid or not RootPart then
        return false
    end

    if JumpCount >= SETTINGS.MaxJumps then
        return false
    end

    if Stamina < SETTINGS.DoubleJumpCost then
        return false
    end

    -- consume the jump and stamina before changing state to prevent repeated requests granting extra jumps
    JumpCount += 1
    ChangeStamina(-SETTINGS.DoubleJumpCost)

    Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

    -- replace only vertical velocity so existing horizontal movement remains unchanged
    local Velocity = RootPart.AssemblyLinearVelocity

    RootPart.AssemblyLinearVelocity = Vector3.new(
        Velocity.X,
        SETTINGS.DoubleJumpPower,
        Velocity.Z
    )

    return true
end

-- handle jump requests by allowing normal ground jumps and prioritizing wall jumps while airborne
local function HandleJump()
    if not Humanoid or not RootPart then
        return
    end

    if Humanoid.Health <= 0 then
        return
    end

    if Humanoid.FloorMaterial ~= Enum.Material.Air then
        JumpCount = 1
        return
    end

    if PerformWallJump() then
        return
    end

    PerformDoubleJump()
end

-- switch between walking and sprinting while preventing sprinting without available stamina
local function SetSprinting(Enabled)
    if not Humanoid then
        return
    end

    IsSprinting = Enabled and Stamina > 0

    Humanoid.WalkSpeed = if IsSprinting
        then SETTINGS.SprintSpeed
        else SETTINGS.WalkSpeed
end

-- start sprinting when the configured key is pressed and ignore input already processed by other uis
local function OnInputBegan(Input, Processed)
    if Processed then
        return
    end

    if Input.KeyCode == SETTINGS.SprintKey then
        SetSprinting(true)
    end
end

-- stop sprinting when the configured key is released and restore normal walking speed
local function OnInputEnded(Input)
    if Input.KeyCode == SETTINGS.SprintKey then
        SetSprinting(false)
    end
end

-- update stamina using delta time so draining and regeneration remain consistent across different frame rates
local function UpdateMovement(DeltaTime)
    if not Humanoid or not RootPart then
        return
    end

    if Humanoid.Health <= 0 then
        return
    end

    if IsSprinting and Humanoid.MoveDirection.Magnitude > 0 then
        ChangeStamina(-SETTINGS.StaminaDrain * DeltaTime)

        -- disable sprinting immediately when stamina reaches zero
        if Stamina <= 0 then
            SetSprinting(false)
        end
    else
        ChangeStamina(SETTINGS.StaminaRegen * DeltaTime)
    end
end

-- initialize character references and reset movement state whenever a new character spawns
local function SetupCharacter(NewCharacter: Model)
    CleanupCharacterConnections()

    Character = NewCharacter
    Humanoid = NewCharacter:WaitForChild("Humanoid") :: Humanoid
    RootPart = NewCharacter:WaitForChild("HumanoidRootPart") :: BasePart

    -- exclude the new character from wall detection so raycasts cannot hit the player
    RaycastSettings.FilterDescendantsInstances = {NewCharacter}

    -- apply default movement properties so every character starts with the same settings
    Humanoid.UseJumpPower = true
    Humanoid.JumpPower = SETTINGS.JumpPower
    Humanoid.WalkSpeed = SETTINGS.WalkSpeed

    -- reset temporary movement state so respawning restores full stamina and jump availability
    Stamina = SETTINGS.MaxStamina
    JumpCount = 0
    IsSprinting = false
    LastWallJump = 0

    UpdateStaminaBar()

    -- track landing so the player can use their additional jump again after touching the ground
    table.insert(
        CharacterConnections,
        Humanoid.StateChanged:Connect(function(_, NewState)
            if NewState == Enum.HumanoidStateType.Landed then
                JumpCount = 0
            end
        end)
    )
end

-- keep permanent input and heartbeat connections active across respawns using updated character references
UserInputService.JumpRequest:Connect(HandleJump)
UserInputService.InputBegan:Connect(OnInputBegan)
UserInputService.InputEnded:Connect(OnInputEnded)
RunService.Heartbeat:Connect(UpdateMovement)

-- initialize newly spawned characters and clean up references when characters are removed
Player.CharacterAdded:Connect(SetupCharacter)

Player.CharacterRemoving:Connect(function()
    CleanupCharacterConnections()
    Character = nil
    Humanoid = nil
    RootPart = nil
    IsSprinting = false
    JumpCount = 0
end)

-- initialize movement immediately if the character already exists when the script starts
if Player.Character then
    SetupCharacter(Player.Character)
else
    UpdateStaminaBar()
end
