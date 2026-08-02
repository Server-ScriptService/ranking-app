local MovementGoal = {}
local Data = {}

local RNG = Random.new()

local STUCK_CHECK_INTERVAL = 0.55
local MIN_MOVED_DISTANCE_SQ = 4
local JUMP_STUCK_TIME = 0.05
local SIDESTEP_STUCK_TIME = 1.8
local SIDESTEP_DISTANCE = 18
local SIDESTEP_DURATION = 1

local PERSONAL_SPACE_RADIUS = 15
local PERSONAL_SPACE_REFRESH_TIME = 5

local function GetData(Bot: Model)
	local BotData = Data[Bot]
	if BotData then return BotData end
	
	BotData = {
		NextPersonalOffsetRefresh = 0,
		LastStuckCheckTime = 0,
		TimeStuck = 0,
		SidestepUntil = 0,
		LastPosition = nil,
		SidestepPosition = nil,
	}
	
	Data[Bot] = BotData
	
	local HasCleanedUp
	local function Cleanup()
		if HasCleanedUp then return end
		HasCleanedUp = true

		Data[Bot] = nil
	end

	Bot.Humanoid.Died:Once(Cleanup)
	Bot.Destroying:Once(Cleanup)
	
	return BotData
end

-- Tracks whether the bot is stuck, triggers jump/sidestep recovery, and returns TargetPosition unless a temporary sidestep is active
function MovementGoal.getMovementGoal(Bot: Model, TargetPosition: Vector3)
	local Brain = require(Bot["Bot Controller"].Brain)
	local BotData = GetData(Bot)
	
	if Brain.State == "Holding" then
		BotData.TimeStuck = 0
		BotData.LastStuckCheckTime = 0
		BotData.LastPosition = nil
		BotData.SidestepPosition = nil
		
		return TargetPosition
	end
	
	local HumanoidRootPart = Bot.HumanoidRootPart :: BasePart
	local Humanoid = Bot.Humanoid
	
	local Now = os.clock()

	if BotData.SidestepPosition and Now < BotData.SidestepUntil then
		return BotData.SidestepPosition
	end

	BotData.SidestepPosition = nil

	if not BotData.LastPosition then
		BotData.LastPosition = HumanoidRootPart.Position
		BotData.LastStuckCheckTime = Now
		
		return TargetPosition
	end

	if Now - BotData.LastStuckCheckTime < STUCK_CHECK_INTERVAL then
		return TargetPosition
	end

	local CurrentPosition = HumanoidRootPart.Position
	local Delta = vector.create(CurrentPosition.X - BotData.LastPosition.X, 0, CurrentPosition.Z - BotData.LastPosition.Z)

	local MovedDistanceSq = Delta:Dot(Delta)
	local TimeDelta = Now - BotData.LastStuckCheckTime

	if MovedDistanceSq <= MIN_MOVED_DISTANCE_SQ then
		BotData.TimeStuck += TimeDelta
	else
		BotData.TimeStuck = 0
	end

	BotData.LastPosition = CurrentPosition
	BotData.LastStuckCheckTime = Now

	Humanoid.Jump = BotData.TimeStuck >= JUMP_STUCK_TIME

	if BotData.TimeStuck >= SIDESTEP_STUCK_TIME then
		local ToTarget = vector.create(TargetPosition.X - CurrentPosition.X, 0, TargetPosition.Z - CurrentPosition.Z)
		local Side = vector.create(-ToTarget.z, 0, ToTarget.x)
		
		Side = Side:Dot(Side) > 0 and Side.Unit or vector.create(1, 0, 0)
		if RNG:NextInteger(1, 2) == 1 then Side *= -1 end
		
		BotData.SidestepPosition = CurrentPosition + Side * SIDESTEP_DISTANCE
		BotData.SidestepUntil = Now + SIDESTEP_DURATION
		BotData.TimeStuck = 0

		Humanoid.Jump = true
		
		return BotData.SidestepPosition
	end

	return TargetPosition
end

-- Returns .getMovementGoal but with a random personal offset
function MovementGoal.getVariedTargetPosition(Bot: Model, TargetPosition: Vector3)
	local BotData = GetData(Bot)
	local Now = os.clock()

	if not BotData.PersonalOffset or Now >= BotData.NextPersonalOffsetRefresh then
		local Angle = RNG:NextNumber(0, math.pi * 2)
		local Radius = RNG:NextNumber(3, PERSONAL_SPACE_RADIUS)

		BotData.PersonalOffset = vector.create(
			math.cos(Angle) * Radius,
			0,
			math.sin(Angle) * Radius
		)

		BotData.NextPersonalOffsetRefresh = Now + PERSONAL_SPACE_REFRESH_TIME + RNG:NextNumber(0, 2)
	end

	return TargetPosition + BotData.PersonalOffset
end

-- Moves away from the given TargetPosition and how much AwayDistance
function MovementGoal.moveAwayFromTarget(Bot: Model, TargetPosition: Vector3, AwayDistance)
	local HumanoidRootPart = Bot.HumanoidRootPart
	local Humanoid = Bot.Humanoid
	local AwayDirection = HumanoidRootPart.Position - TargetPosition

	if AwayDirection.Magnitude < 0.05 then
		AwayDirection = -HumanoidRootPart.CFrame.LookVector
	end

	Humanoid:MoveTo(HumanoidRootPart.Position + AwayDirection.Unit * AwayDistance)
end

return MovementGoal
