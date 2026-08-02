local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")

local Mouse = Player:GetMouse()
local PlayerGui = Player:WaitForChild("PlayerGui")

local WeaponFiredEvent = script["Weapon Fired"]
local StartedAimingEvent = script["Started Aiming"]
local StoppedAimingEvent = script["Stopped Aiming"]

local Viewmodels = ReplicatedStorage.Models.Weapons.Viewmodels

local Camera = workspace.CurrentCamera
local IsFiringWeapon, IsM2Aiming

local SWAY = 0.2
local AIM_SWAY = 0.08
local AIM_SENSITIVITY_MULTIPLIER = 0.2

local CurrentSway = SWAY

local SwayCFrame = CFrame.identity
local LastCameraCF = CFrame.identity
local AimingCFrame = CFrame.identity
local BobCFrame = CFrame.identity
local HolsterCFrame = CFrame.identity

-- Mobile
local AimButtonConnection
local KeyboardEnabled = UserInputService.KeyboardEnabled

-- Smoothing, lower = slower
local AIM_SMOOTHING = 0.175
local BOB_SMOOTHING = 0.175
local HOLSTER_SMOOTHING = 0.125

local HOLSTER_OFFSET = CFrame.identity * CFrame.Angles(math.rad(-15), math.rad(15), math.rad(15))

local DEBUG_TURN_OFF_FPS = false

local EquippedTool
local ReloadTrack, ReloadConnection, Reloading
local Viewmodel

local function ClearReloadState()
	Reloading = false
	EquippedTool = nil

	if ReloadConnection then
		ReloadConnection:Disconnect()
		ReloadConnection = nil
	end

	if ReloadTrack then
		ReloadTrack:Stop(0)
		ReloadTrack = nil
	end
end

-- Plays/stops the reloading animation based on if the weapon's currently reloading
local function SetReloadingAnimation(ReloadValue: BoolValue, Boolean)
	if not ReloadTrack then return end
	
	Reloading = if Boolean == nil then ReloadValue.Value else Boolean
	if Reloading then
		IsFiringWeapon = false

		if IsM2Aiming then
			IsM2Aiming = false
			StoppedAimingEvent:Fire()
		end

		ReloadTrack:Stop(0)
		ReloadTrack:Play(0)
	elseif ReloadTrack.IsPlaying then
		ReloadTrack:Stop()
	end
end

-- Loads the weapon Viewmodel of the given WeaponName onto the camera
local function LoadViewmodel(WeaponName, ShouldDeleteViewmodel)
	local Weapon = Viewmodels:FindFirstChild(WeaponName)
	local CharacterTool = Character:FindFirstChild(WeaponName)

	local ExistingViewmodel = Camera:FindFirstChild(WeaponName)
	if ShouldDeleteViewmodel and ExistingViewmodel then
		ClearReloadState()
		ExistingViewmodel:Destroy()
		Viewmodel = nil

		if AimButtonConnection then
			AimButtonConnection:Disconnect()
			AimButtonConnection = nil
		end

		return
	end

	if not Weapon then
		warn("Unknown viewmodel", WeaponName)
		return
	end

	-- Hides the physical Tool because we do not want 2 guns viewable
	for _, Part in pairs(CharacterTool:GetDescendants()) do
		if Part:IsA("BasePart") then 
			Part.Transparency = 1
		elseif Part:IsA("ParticleEmitter") then
			Part:SetAttribute("StopEmit", true)
		end
	end

	Viewmodel = Weapon:Clone()
	Viewmodel.Parent = Camera

	EquippedTool = CharacterTool

	local AnimationController = Viewmodel.AnimationController
	local Animator = AnimationController.Animator :: Animator
	ReloadTrack = Animator:LoadAnimation(AnimationController.Reload)

	local ReloadValue = CharacterTool.Reloading :: BoolValue

	ReloadConnection = ReloadValue.Changed:Connect(function(NewValue)
		if CharacterTool ~= EquippedTool then return end
		SetReloadingAnimation(ReloadValue, NewValue)
	end)

	SetReloadingAnimation(ReloadValue)

	-- Mobile aiming
	if KeyboardEnabled then return end

	local AimButton = PlayerGui:WaitForChild("Ammunition").Background.Aim
	AimButton.Visible = true

	AimButtonConnection = AimButton.MouseButton1Click:Connect(function()
		if Reloading then return end

		IsM2Aiming = not IsM2Aiming
		AimButton.BackgroundColor3 = IsM2Aiming and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(0, 0, 0)

		if IsM2Aiming then
			StartedAimingEvent:Fire()
		else
			StoppedAimingEvent:Fire()
		end
	end)
end

-- If Flag is true, this will change the cursor to the aiming one
local function UpdateAimingCursor(Flag)
	UserInputService.MouseIcon = Flag and "http://www.roblox.com/asset?id=126137448942212" or ""
end

local function DeltaLerpAlpha(Alpha, DeltaTime)
	return 1 - (1 - Alpha) ^ (DeltaTime * 60)
end

WeaponFiredEvent.Event:Connect(function()
	if Reloading then return end
	IsFiringWeapon = true
end)

Mouse.Button1Up:Connect(function()
	IsFiringWeapon = false
end)

RunService.RenderStepped:Connect(function(DeltaTime)
	local AimAlpha = DeltaLerpAlpha(AIM_SMOOTHING, DeltaTime)
	local SwayAlpha = DeltaLerpAlpha(0.1, DeltaTime)
	local CameraBobAlpha = DeltaLerpAlpha(0.1, DeltaTime)
	local WeaponBobAlpha = DeltaLerpAlpha(BOB_SMOOTHING, DeltaTime)
	local HolsterAlpha = DeltaLerpAlpha(HOLSTER_SMOOTHING, DeltaTime)
	
	local Time = time()
	
	-- Aiming
	if Viewmodel and (not Reloading) and Viewmodel:FindFirstChild("Aim") and (IsFiringWeapon or IsM2Aiming) then
		UserInputService.MouseDeltaSensitivity = AIM_SENSITIVITY_MULTIPLIER

		local Offset = Viewmodel.Aim.CFrame:ToObjectSpace(Viewmodel.PrimaryPart.CFrame)
		AimingCFrame = AimingCFrame:Lerp(Offset, AimAlpha)
		CurrentSway = AIM_SWAY
	else
		UserInputService.MouseDeltaSensitivity = 1

		AimingCFrame = AimingCFrame:Lerp(CFrame.new(), AimAlpha)
		CurrentSway = SWAY
	end
	
	-- Swaying
	local Rotation = LastCameraCF:ToObjectSpace(Camera.CFrame)
	local X, Y = Rotation:ToOrientation()
	SwayCFrame = SwayCFrame:Lerp(CFrame.Angles(math.sin(X) * CurrentSway, math.sin(Y) * CurrentSway, 0), SwayAlpha)
	LastCameraCF = Camera.CFrame

	local BobOffset = CFrame.new()

	if Humanoid.MoveDirection ~= vector.zero and Viewmodel then
		local CameraBob = vector.create(0, math.sin(Time * Humanoid.WalkSpeed) * 0.2, 0)
		Humanoid.CameraOffset = Humanoid.CameraOffset:Lerp(CameraBob, CameraBobAlpha)	
		
		BobOffset = CFrame.new(
			math.cos(Time * 4) * 0.05,
			-Humanoid.CameraOffset.Y / 3,
			-Humanoid.CameraOffset.Z / 3
		) * CFrame.Angles(
			0,
			math.sin(Time * -4) * -0.05,
			math.cos(Time * -4) * 0.05
		)
		
		if IsFiringWeapon or IsM2Aiming then
			BobOffset = CFrame.new(BobOffset.X / 3, BobOffset.Y / 3, BobOffset.Z / 3)
		end	
	else
		Humanoid.CameraOffset = Humanoid.CameraOffset:Lerp(vector.zero, CameraBobAlpha)
		BobOffset = BobOffset:Lerp(CFrame.new(0, -Humanoid.CameraOffset.Y / 3, 0), CameraBobAlpha)
	end
	
	-- Holstering
	local ShouldHolster = not Reloading and not IsFiringWeapon and not IsM2Aiming
	local TargetHolsterCFrame = ShouldHolster and HOLSTER_OFFSET or CFrame.identity
	HolsterCFrame = HolsterCFrame:Lerp(TargetHolsterCFrame, HolsterAlpha)
	
	if not Viewmodel then
		UpdateAimingCursor()
		return
	end

	UpdateAimingCursor(true)
	BobCFrame = BobCFrame:Lerp(BobOffset, WeaponBobAlpha)
	Viewmodel:PivotTo(Camera.CFrame * HolsterCFrame * AimingCFrame * SwayCFrame * BobCFrame)
end)

-- PC ADS
if KeyboardEnabled then
	UserInputService.InputBegan:Connect(function(Input, GameProcessedEvent)
		if GameProcessedEvent or Input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
		if Reloading then return end

		IsM2Aiming = true
		StartedAimingEvent:Fire()
	end)

	UserInputService.InputEnded:Connect(function(Input, GameProcessedEvent)
		if GameProcessedEvent or Input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end

		IsM2Aiming = false
		StoppedAimingEvent:Fire()
	end)
end

local function ConnectShowViewmodelOnEquip()
	Character.ChildAdded:Connect(function(Tool)
		if not (Tool:IsA("Tool") and Tool:FindFirstChild("Ammo")) then return end
		if DEBUG_TURN_OFF_FPS then return end

		Player.CameraMode = Enum.CameraMode.LockFirstPerson
		LoadViewmodel(Tool.Name)
	end)

	Character.ChildRemoved:Connect(function(Tool)
		if not (Tool:IsA("Tool") and Tool:FindFirstChild("Ammo")) then return end
		if DEBUG_TURN_OFF_FPS then return end

		Player.CameraMode = Enum.CameraMode.Classic
		LoadViewmodel(Tool.Name, true)
	end)
end

local function ConnectOnDeath()
	-- Removes viewmodels on death and sets the camera to Classic
	Humanoid.Died:Once(function()
		ClearReloadState()
		IsM2Aiming = false

		local Weapon = Character:FindFirstChildWhichIsA("Tool")
		local IsWeapon = Weapon and Weapon:FindFirstChild("Ammo")

		if Viewmodel then
			Viewmodel:Destroy()
			Viewmodel = nil
		end

		if not IsWeapon then return end
		Player.CameraMode = Enum.CameraMode.Classic
	end)
end

ConnectShowViewmodelOnEquip()
ConnectOnDeath()

Player.CharacterAdded:Connect(function(NewCharacter: Model)
	Character = NewCharacter
	Humanoid = NewCharacter:WaitForChild("Humanoid")
	Camera = workspace.CurrentCamera
	PlayerGui = Player:WaitForChild("PlayerGui")

	if Viewmodel then
		Viewmodel:Destroy()
		Viewmodel = nil
	end
	
	ConnectShowViewmodelOnEquip()	
	ConnectOnDeath()
end)
