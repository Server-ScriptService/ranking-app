local AttackEnemy = {Initialized = {}}
local Data = {}

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActorUtility = require(ReplicatedStorage.Modules["Actor Utility"])

local MoveToObjective = require(script.Parent.MoveToObjective)

local SHOTS_FIRED_RESET_WINDOW = 10

local REACTION_TIME_MIN = 0.2
local REACTION_TIME_MAX = 1

local RNG = Random.new()

local function GetData(Bot: Model)
	local BotData = Data[Bot]
	if BotData then return BotData end
	
	BotData = {
		FiringLoopActive = false,
		ClaimedTarget = nil,
	}
	
	Data[Bot] = BotData
	
	local HasCleanedUp
	local function Cleanup()
		if HasCleanedUp then return end
		HasCleanedUp = true
		
		local ClaimedTarget = BotData.ClaimedTarget
		if ClaimedTarget then
			ClaimedTarget:SetAttribute("TargetingActors", math.max(
				ClaimedTarget:GetAttribute("TargetingActors") - 1, 0))
		end
		
		Data[Bot] = nil
	end

	Bot.Humanoid.Died:Once(Cleanup)
	Bot.Destroying:Once(Cleanup)
	
	return BotData
end

local function GetClosestEnemyActor(Bot: Model)
	local BotConfig = Bot.Configuration
	local HumanoidRootPart = Bot.HumanoidRootPart
	
	local ClosestDistance = BotConfig.Vision.Value ^ 2
	local ClosestActor

	for _, Actor in CollectionService:GetTagged("Actor") do
		if not Actor:IsDescendantOf(workspace) then continue end
		if Actor == Bot then continue end

		local ActorPlayer = Players:GetPlayerFromCharacter(Actor)
		
		if ActorUtility.indexNationFromObject(Actor) == Bot.Configuration.Nation.Value then continue end
		if ActorPlayer and not (ActorPlayer.Character and ActorPlayer:GetAttribute("Spawned")) then continue end

		local Humanoid = Actor.Humanoid
		if Humanoid.Health <= 0 then continue end

		local ActorHumanoidRootPart = Actor:FindFirstChild("HumanoidRootPart")
		if not ActorHumanoidRootPart then continue end
		
		if not Actor.CanBeAttacked.Value then
			continue
		end
		
		local TargetingActors = (Actor:GetAttribute("TargetingActors") or 0)
		local OwnsThisTargetingActorsClaim =GetData(Bot).ClaimedTarget == Actor
		
		if TargetingActors >= BotConfig["Avoid If Targeting Actors Exceeds"].Value and not OwnsThisTargetingActorsClaim then
			continue
		end
		
		local Delta = ActorHumanoidRootPart.Position - HumanoidRootPart.Position
		local DistanceSq = Delta:Dot(Delta)
		if DistanceSq >= ClosestDistance then continue end
		
		ClosestDistance = DistanceSq
		ClosestActor = Actor
	end

	return ClosestActor
end

function AttackEnemy.initialize(Bot: Model)
	if AttackEnemy.Initialized[Bot] then return end
	AttackEnemy.Initialized[Bot] = true
	
	local HumanoidRootPart = Bot.HumanoidRootPart
	local Brain = require(Bot["Bot Controller"].Brain)
	
	task.spawn(function()
		while task.wait(SHOTS_FIRED_RESET_WINDOW) and Bot.Parent do
			Bot:SetAttribute("ShotsFired", 0)
			Bot:SetAttribute("ShotsLanded", 0)
		end
	end)
	
	-- This loop discovers enemies while the bot is moving/idling/no actual target, and inside .execute it is fetched one more time for an accurate target update
	task.spawn(function()
		while task.wait(1) and Bot.Parent and Bot.Humanoid.Health > 0 do
			Brain.Target = GetClosestEnemyActor(Bot)
		end
	end)
	
	local LOOK_UPDATE_RATE = 1 / 20 -- Hz
	
	local LastLookUpdate = 0
	
	local FaceAttachment = Instance.new("Attachment")
	FaceAttachment.Name = "FaceAttachment"
	FaceAttachment.Parent = HumanoidRootPart

	local FaceAlign = Instance.new("AlignOrientation")
	FaceAlign.Name = "FaceAlign"
	FaceAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment
	FaceAlign.Attachment0 = FaceAttachment
	FaceAlign.RigidityEnabled = false
	FaceAlign.Responsiveness = 35
	FaceAlign.MaxTorque = math.huge
	FaceAlign.Enabled = false
	FaceAlign.Parent = HumanoidRootPart
	
	-- Looks towards the active target
	local LOOK_EPSILON_SQ = 0.1 ^ 2
	local Connection = RunService.Heartbeat:Connect(function(DeltaTime)
		LastLookUpdate += DeltaTime
		if LastLookUpdate < LOOK_UPDATE_RATE then return end
		LastLookUpdate = 0
		
		local Enemy = Brain.Target
		if not Enemy then FaceAlign.Enabled = false return end

		local EnemyHumanoidRootPart = Enemy:FindFirstChild("HumanoidRootPart")
		if not EnemyHumanoidRootPart then FaceAlign.Enabled = false return end

		local BotPosition = HumanoidRootPart.Position
		local EnemyPosition = EnemyHumanoidRootPart.Position
		local LookPosition = vector.create(EnemyPosition.X, BotPosition.Y, EnemyPosition.Z)
		
		-- This is so lookAt does not receive similar positions and bug out
		local Difference = LookPosition - BotPosition
		if Difference:Dot(Difference) <= LOOK_EPSILON_SQ then
			FaceAlign.Enabled = false
			return
		end
		
		FaceAlign.CFrame = CFrame.lookAt(BotPosition, LookPosition)
		FaceAlign.Enabled = true
	end)
	
	local HasCleanedUp
	local function Cleanup()
		if HasCleanedUp then return end
		HasCleanedUp = true
		
		Connection:Disconnect()
		Connection = nil
		AttackEnemy.Initialized[Bot] = nil
	end
	
	Bot.Humanoid.Died:Once(Cleanup)
	Bot.Destroying:Once(Cleanup)
end

local function GetSpreadDirection(Direction: Vector3, SpreadDegrees)
	local SpreadRadians = math.rad(SpreadDegrees)

	local Pitch = RNG:NextNumber(-SpreadRadians, SpreadRadians)
	local Yaw = RNG:NextNumber(-SpreadRadians, SpreadRadians)

	return (CFrame.lookAt(vector.zero, Direction) * CFrame.Angles(Pitch, Yaw, 0)).LookVector
end

local function FindAutomatic(Bot: Model)
	for _, Child in Bot:GetChildren() do
		if not (Child:IsA("Tool") and Child:FindFirstChild("Ammo")) then continue end
		return Child
	end	
end

function AttackEnemy.execute(Bot: Model)
	local BotData = GetData(Bot)
	local BotConfig = Bot.Configuration
	local Humanoid = Bot.Humanoid
	
	local Brain = require(Bot["Bot Controller"].Brain)
	
	local Weapon = FindAutomatic(Bot)
	local WeaponName = Weapon.Name
	local WeaponLogic = require(ServerScriptService.Weapons[WeaponName][WeaponName .. " Logic"])
	local WeaponCooldown = ServerStorage.Weapons[Weapon.Name].Cooldown.Value
	
	local Enemy = GetClosestEnemyActor(Bot)
	Brain.Target = Enemy
	
	-- Returns the amount of actors targeting the given character
	local function GetTargetingActors(Character: Model)
		return (Character:GetAttribute("TargetingActors") or 0)
	end
	
	-- Edits the amount of actors targeting the given character
	local function EditTargetingActors(Character: Model, Amount)
		Character:SetAttribute("TargetingActors", math.max(GetTargetingActors(Character) + Amount, 0))
	end
	
	-- If Flag is true, it marks the brain's state as attacking. Else idle
	local function CountBrainAttacking(Flag)
		Flag = if Flag == nil then false else Flag
		Bot:SetAttribute("Attacking", Flag)
		Brain.State = Flag and "Attacking" or "Idle"
	end
	
	-- No enemy to attack
	if not Enemy then
		CountBrainAttacking()
		
		if BotData.ClaimedTarget then
			EditTargetingActors(BotData.ClaimedTarget, -1)
			BotData.ClaimedTarget = nil	
		end
		
		-- Releases the target instance if it was an actor we were targeting
		local TargetInstance = Brain.TargetInstance
		if TargetInstance and TargetInstance:HasTag("Actor") then
			Brain.TargetInstance = nil
			Brain.TargetPosition = nil
		end
		
		MoveToObjective.execute(Bot)
		return
	end
	
	if Humanoid.Health <= 0 then
		if BotData.ClaimedTarget then
			EditTargetingActors(BotData.ClaimedTarget, -1)
			BotData.ClaimedTarget = nil
		end
		
		CountBrainAttacking()
		return
	end

	local EnemyHumanoidRootPart = Enemy.HumanoidRootPart
	
	if BotData.ClaimedTarget and Enemy ~= BotData.ClaimedTarget then
		-- Target switched, unclaim the previous target
		EditTargetingActors(BotData.ClaimedTarget, -1)
		BotData.ClaimedTarget = nil
	end
	
	MoveToObjective.execute(Bot)
	
	if BotData.FiringLoopActive then return end
	BotData.FiringLoopActive = true
	
	CountBrainAttacking(true)
	
	-- Weapon firing loop
	task.spawn(function()
		task.wait(RNG:NextNumber(REACTION_TIME_MIN, REACTION_TIME_MAX))
		
		while Brain.Target == Enemy and Humanoid.Health > 0 do
			local WeaponBody = Weapon:FindFirstChild("Body")
			if not WeaponBody then break end
			
			if not EnemyHumanoidRootPart.Parent then
				break
			end
			
			local Origin = WeaponBody.Attachment.WorldPosition
			
			local Direction = EnemyHumanoidRootPart.Position - Origin
			local SpreadDegrees = math.clamp(2 + Direction.Magnitude / BotConfig["Aim Accuracy"].Value, 2, 8)

			local DidShotLand = WeaponLogic.fireBullet(Bot, {
				Origin = Weapon.Body.Attachment.WorldPosition,
				Direction = GetSpreadDirection(Direction.Unit, SpreadDegrees)
			})
			
			Bot:SetAttribute("ShotsFired", (Bot:GetAttribute("ShotsFired") or 0) + 1)
			
			if DidShotLand then
				Bot:SetAttribute("ShotsLanded", (Bot:GetAttribute("ShotsLanded") or 0) + 1)
				
				if not BotData.ClaimedTarget then
					BotData.ClaimedTarget = Enemy
					EditTargetingActors(Enemy, 1)
				end
			end
			
			task.wait(WeaponCooldown)
		end
		
		BotData.FiringLoopActive = false
	end)
end

return AttackEnemy
