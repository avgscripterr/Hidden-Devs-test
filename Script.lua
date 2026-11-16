-- Connected Discord-Github

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local ScreenGui = PlayerGui:WaitForChild("ParkourInterface")
local BarBackground = ScreenGui:WaitForChild("StaminaBackground")
local BarFill = BarBackground:WaitForChild("StaminaFill")
local BarText = BarBackground:WaitForChild("StaminaText")

-- movement values are centralized for easyness
type SettingsType = {
	MaxStamina: number,
	StaminaDrain: number,
	StaminaRegen: number,
	WalkSpeed: number,
	SprintSpeed: number,
	JumpPower: number,
	DoubleJumpPower: number,
	WallJumpPower: number,
	WallJumpForward: number,
	WallDistance: number,
	WallCooldown: number,
}

local Settings: SettingsType = {
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
}

-- track the current character and movement state
local Character: Model? = nil
local Humanoid: Humanoid? = nil
local RootPart: BasePart? = nil

local Stamina = Settings.MaxStamina
local JumpCount = 0
local MaxJumps = 2
local IsSprinting = false
local LastWallJump = 0

local CharacterConnection: RBXScriptConnection? = nil

-- excludes the character from the wall detection
local RaycastSettings = RaycastParams.new()
RaycastSettings.FilterType = Enum.RaycastFilterType.Exclude

-- updates the ui bar
local function UpdateStaminaBar(): ()
	local Percentage = math.clamp(
		Stamina / Settings.MaxStamina,
		0,
		1
	)

	BarFill.Size = UDim2.fromScale(Percentage, 1)
	BarFill.BackgroundColor3 = Color3.new(
		1 - Percentage,
		Percentage,
		0.3
	)

	BarText.Text = "STAMINA " .. math.floor(Stamina)
end

-- prevents stamina from exceeding its configured limits
local function ChangeStamina(Amount: number): ()
	Stamina = math.clamp(
		Stamina + Amount,
		0,
		Settings.MaxStamina
	)

	UpdateStaminaBar()
end

-- refreshes variables whenever the player character is loaded
local function SetupCharacter(NewCharacter: Model): ()
	Character = NewCharacter
	Humanoid = NewCharacter:WaitForChild("Humanoid") :: Humanoid
	RootPart = NewCharacter:WaitForChild("HumanoidRootPart") :: BasePart

	RaycastSettings.FilterDescendantsInstances = {NewCharacter}

	Humanoid.UseJumpPower = true
	Humanoid.JumpPower = Settings.JumpPower
	Humanoid.WalkSpeed = Settings.WalkSpeed

	Stamina = Settings.MaxStamina
	JumpCount = 0
	IsSprinting = false

	UpdateStaminaBar()

	if CharacterConnection then
		CharacterConnection:Disconnect()
	end

	CharacterConnection = Humanoid.StateChanged:Connect(
		function(_, NewState: Enum.HumanoidStateType)
			if NewState == Enum.HumanoidStateType.Landed then
				JumpCount = 0
			end
		end
	)
end

-- checks all four sides for a nearby vertical surface
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

	for _, Direction in ipairs(Directions) do
		local Result = Workspace:Raycast(
			RootPart.Position,
			Direction * Settings.WallDistance,
			RaycastSettings
		)

		if Result and math.abs(Result.Normal.Y) < 0.25 then
			return Result.Normal
		end
	end

	return nil
end

-- launches the character away from the detected wall
local function PerformWallJump(): boolean
	if not Humanoid or not RootPart then
		return false
	end

	if os.clock() - LastWallJump < Settings.WallCooldown then
		return false
	end

	if Stamina < 15 then
		return false
	end

	local WallNormal = GetWallNormal()

	if not WallNormal then
		return false
	end

	LastWallJump = os.clock()
	ChangeStamina(-15)
	JumpCount = 1

	Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

	RootPart.AssemblyLinearVelocity = Vector3.new(
		WallNormal.X * Settings.WallJumpForward,
		Settings.WallJumpPower,
		WallNormal.Z * Settings.WallJumpForward
	)

	return true
end

-- replaces vertical velocity while keeping momentum
local function PerformDoubleJump(): boolean
	if not Humanoid or not RootPart then
		return false
	end

	if JumpCount >= MaxJumps or Stamina < 12 then
		return false
	end

	JumpCount += 1
	ChangeStamina(-12)

	Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

	local Velocity = RootPart.AssemblyLinearVelocity

	RootPart.AssemblyLinearVelocity = Vector3.new(
		Velocity.X,
		Settings.DoubleJumpPower,
		Velocity.Z
	)

	return true
end

-- chooses wall jumping before the regular second jump
local function HandleJump(): ()
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

-- switches between walking and sprinting speeds
local function SetSprinting(Enabled: boolean): ()
	if not Humanoid then
		return
	end

	IsSprinting = Enabled and Stamina > 0

	Humanoid.WalkSpeed = if IsSprinting
		then Settings.SprintSpeed
		else Settings.WalkSpeed
end

-- jump requests support keyboard and mobile jump controls
local function OnJumpRequest(): ()
	HandleJump()
end

-- keyboard input controls sprinting
local function OnInputBegan(
	Input: InputObject,
	Processed: boolean
): ()
	if Processed then
		return
	end

	if Input.KeyCode == Enum.KeyCode.LeftControl then
		SetSprinting(true)
	end
end

-- releases sprinting when the key is released
local function OnInputEnded(Input: InputObject): ()
	if Input.KeyCode == Enum.KeyCode.LeftControl then
		SetSprinting(false)
	end
end

-- continuously manages stamina and prevents sprinting without energy
local function UpdateMovement(DeltaTime: number): ()
	if not Humanoid or not RootPart then
		return
	end

	if Humanoid.Health <= 0 then
		return
	end

	if IsSprinting and Humanoid.MoveDirection.Magnitude > 0 then
		ChangeStamina(-Settings.StaminaDrain * DeltaTime)

		if Stamina <= 0 then
			SetSprinting(false)
		end
	else
		ChangeStamina(Settings.StaminaRegen * DeltaTime)
	end
end

-- global connections remain active across character respawns
UserInputService.JumpRequest:Connect(OnJumpRequest)
UserInputService.InputBegan:Connect(OnInputBegan)
UserInputService.InputEnded:Connect(OnInputEnded)
RunService.Heartbeat:Connect(UpdateMovement)

-- character lifecycle keeps movement references synced
Player.CharacterAdded:Connect(SetupCharacter)

Player.CharacterRemoving:Connect(function()
	if CharacterConnection then
		CharacterConnection:Disconnect()
		CharacterConnection = nil
	end

	Character = nil
	Humanoid = nil
	RootPart = nil
	IsSprinting = false
	JumpCount = 0
end)

-- initializes movement when the character already exists
if Player.Character then
	SetupCharacter(Player.Character)
end

UpdateStaminaBar()
