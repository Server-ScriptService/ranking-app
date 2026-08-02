local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Tool = script.Parent
local Event = ReplicatedStorage.Network.Events.Weapons[Tool.Name]

local Player = Players.LocalPlayer
local Mouse = Player:GetMouse()

local AmmunitionGui = Tool:WaitForChild("Ammunition")
local Background = AmmunitionGui:WaitForChild("Background")
local ShootButton = Background:WaitForChild("Shoot") :: ImageButton
Background:WaitForChild("Weapon Name").Text = Tool.Name

local Holding, LoopRunning

local Automatics = require(ReplicatedStorage.Modules.Automatics)
local Effects = require(Tool:WaitForChild("Effects"))

local Cooldown = Tool.Cooldown
local Range = Tool.Range

local function FireShot()
	local ShotInfo = Automatics.getShotInfo(Range.Value)
	Effects.playLocal(ShotInfo.HitPosition, ShotInfo.MaterialName, ShotInfo.HitPart)
	
	Event:FireServer(
		ShotInfo.Origin,
		ShotInfo.Direction,
		ShotInfo.HitPosition,
		ShotInfo.HitPart,
		ShotInfo.MaterialName
	)
end

local function FireLoop()
	if LoopRunning then return end

	LoopRunning = true
	local NextShot = 0

	while Holding do
		if not Automatics.canFire(Tool) then
			RunService.Heartbeat:Wait()
			continue
		end
		
		local Now = os.clock()
		
		if Now >= NextShot then
			FireShot()
			NextShot = Now + Cooldown.Value
		else
			RunService.Heartbeat:Wait()
		end
	end

	LoopRunning = false
end

local function DisplayAmmo()
	Automatics.displayAmmo(AmmunitionGui, Tool)	
end

local function BeginFiring()
	Holding = true
	FireLoop()
end

local function StopFiring()
	Holding = false
end

if UserInputService.TouchEnabled then
	ShootButton.Visible = true

	ShootButton.InputBegan:Connect(function(Input)
		if Input.UserInputType ~= Enum.UserInputType.Touch then return end
		
		ShootButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
		BeginFiring()	
	end)

	ShootButton.InputEnded:Connect(function(Input)
		if Input.UserInputType ~= Enum.UserInputType.Touch then return end
		
		ShootButton.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		StopFiring()	
	end)
else
	Mouse.Button1Down:Connect(BeginFiring)
	Mouse.Button1Up:Connect(StopFiring)
end

DisplayAmmo()
Tool.Ammo.Changed:Connect(DisplayAmmo)

Tool.Equipped:Connect(function()
	AmmunitionGui.Parent = Player.PlayerGui
end)

Tool.Unequipped:Connect(function()
	Holding = false
	AmmunitionGui.Parent = Tool
	ShootButton.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
end)
