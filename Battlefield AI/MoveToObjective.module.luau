local MoveToObjective = {}
local Data = {}

local MovementGoal = require(script["Movement Goal"])
local ScoreObjective = require(script["Score Objective"])
local ScoreTargetActor = require(script["Score Target Actor"])

local DESTINATION_ARRIVED_THRESHOLD_SQ = 4 ^ 2

local function GetData(Bot: Model)
	local BotData = Data[Bot]
	if BotData then return BotData end

	BotData = {
		IsHoldingPosition = false
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

function MoveToObjective.execute(Bot: Model)
	local BotData = GetData(Bot)
	local Humanoid, HumanoidRootPart = Bot.Humanoid, Bot.HumanoidRootPart

	local Brain = require(Bot["Bot Controller"].Brain)
	ScoreObjective.setBestObjective(Bot)

	if not Brain.TargetPosition then
		Brain.State = "Idle"
		return
	end

	local TargetGoal = MovementGoal.getMovementGoal(Bot, Brain.TargetPosition)
	local OffsetGoal = MovementGoal.getVariedTargetPosition(Bot, TargetGoal)

	local TargetInstance = Brain.TargetInstance

	if (TargetInstance and TargetInstance:HasTag("Actor")) then
		ScoreTargetActor.setBrainStateForTarget(Bot, OffsetGoal)
		local State = Brain.State

		if State ~= "Holding" then
			BotData.IsHoldingPosition = false
		end
			
		if State == "Charging" then
			Humanoid:MoveTo(OffsetGoal)
		elseif State == "Retreating" then
			MovementGoal.moveAwayFromTarget(Bot, OffsetGoal, ScoreTargetActor.STAY_WITHIN / 2)
		elseif State == "Holding" then
			if BotData.IsHoldingPosition then return end
			BotData.IsHoldingPosition = true
			Humanoid:MoveTo(HumanoidRootPart.Position)
		end
	else
		-- Not an actor
		Brain.State = "Moving"

		BotData.IsHoldingPosition = false
		Humanoid:MoveTo(OffsetGoal)

		local Delta = OffsetGoal - HumanoidRootPart.Position

		if Delta:Dot(Delta) > DESTINATION_ARRIVED_THRESHOLD_SQ then return end
		ScoreObjective.getReachedObjective(Bot):Fire()
	end
end

return MoveToObjective
