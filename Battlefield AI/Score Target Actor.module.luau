local ScoreTargetActor = {
	STAY_WITHIN = 56,
	STAY_WITHIN_SQ = 56 ^ 2
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")

local ScanRegion = require(Modules:WaitForChild("Scan Region"))
local ActorUtility = require(Modules:WaitForChild("Actor Utility"))

local MIN_SHOTS_FIRED_TO_SAMPLE = 5

function ScoreTargetActor.setBrainStateForTarget(Bot: Model, OffsetGoal: Vector3)
	local Brain = require(Bot["Bot Controller"].Brain)
	local Humanoid, HumanoidRootPart = Bot.Humanoid :: Humanoid, Bot.HumanoidRootPart
	
	local BotConfig = Bot.Configuration
	local BotNation = BotConfig.Nation.Value
	
	local Weapon = Bot:FindFirstChildWhichIsA("Tool")
	local BaseWeaponModel = ServerStorage.Weapons[Weapon.Name]
	
	local ChargeScore = 0
	local CHARGE_THRESHOLD = 5

	local TargetInstance = Brain.TargetInstance

	local OffsetGoalDelta = OffsetGoal - HumanoidRootPart.Position
	local DistanceToOffsetGoalSq = OffsetGoalDelta:Dot(OffsetGoalDelta)

	local EnemyHumanoidRootPart = TargetInstance:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not EnemyHumanoidRootPart then return end

	local EnemyDelta = EnemyHumanoidRootPart.Position - HumanoidRootPart.Position
	local DistanceToEnemySq = EnemyDelta:Dot(EnemyDelta)
	
	-- If the bot gets stuck in a vehicle with a cabin, this exits it from the vehicle
	local SeatPart = Humanoid.SeatPart
	local Cabin = SeatPart and SeatPart.Parent:FindFirstChild("Cabin")
	if Cabin then
		local ExitAttachment = Cabin["Exit Attachment"] :: Attachment
		Bot:PivotTo(ExitAttachment.WorldCFrame)
	end
	
	if DistanceToOffsetGoalSq < ScoreTargetActor.STAY_WITHIN_SQ then
		ChargeScore += 3
	end

	local BotHP = Humanoid.Health / Humanoid.MaxHealth

	if BotHP >= 0.65 then
		ChargeScore += 2
	elseif BotHP <= 0.4 then
		ChargeScore -= 2
	end
	
	local ShotsFired = Bot:GetAttribute("ShotsFired") or 0
	local ShotsLanded = Bot:GetAttribute("ShotsLanded") or 0
	
	local ShotAccuracy = ShotsFired > 0 and (ShotsLanded / ShotsFired) or 0
	if DistanceToEnemySq >= BaseWeaponModel.Range.Value ^ 2 and ShotsFired >= MIN_SHOTS_FIRED_TO_SAMPLE and ShotAccuracy < 0.6 then
		ChargeScore += 4
	end

	local NearbyActors = ScanRegion.countActorsNearCFrame(EnemyHumanoidRootPart.CFrame)
	local EnemiesNearTarget, AlliesNearTarget = 0, 0

	for _, Actor in NearbyActors do
		local ActorNation = ActorUtility.indexNationFromObject(Actor)
		
		if ActorNation == BotNation then
			AlliesNearTarget += 1
		else
			EnemiesNearTarget += 1
		end
	end

	if AlliesNearTarget >= EnemiesNearTarget then
		ChargeScore += 2
	else
		ChargeScore -= 1.5
	end
	
	local RaycastParameters = RaycastParams.new()
	RaycastParameters.FilterDescendantsInstances = {Bot}

	local HAS_LOS_DECREASE = 3.5
	local HasLOS = workspace:Raycast(HumanoidRootPart.Position, EnemyHumanoidRootPart.Position - HumanoidRootPart.Position, RaycastParameters)
	HasLOS = HasLOS and HasLOS.Instance:IsDescendantOf(TargetInstance)

	if HasLOS then
		-- We don't actually need to go forward if we can just shoot from here
		ChargeScore -= HAS_LOS_DECREASE * 1.8
	else
		ChargeScore += HAS_LOS_DECREASE
	end

	if ChargeScore >= CHARGE_THRESHOLD then
		-- Able to charge (but first we see if we're already charging)
		if DistanceToEnemySq > ScoreTargetActor.STAY_WITHIN_SQ or not HasLOS then
			-- Charge
			Brain.State = "Charging"
		else 
			-- Enemy too close, retreat
			Brain.State = "Retreating"
		end
	else
		-- We can't charge
		Brain.State = "Holding"
	end
end

return ScoreTargetActor
