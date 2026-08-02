local ScoreObjectiveUtility = {Initialized = setmetatable({}, {__mode = "k"})}

local Teams = game:GetService("Teams")
local Nations = Teams:GetChildren()

local Data = {}

local RNG = Random.new()

local function GetData(Bot: Model)
	local BotData = Data[Bot]
	if BotData then return BotData end
	
	BotData = {
		TakenDamageFrom = setmetatable({}, {__mode = "k"}),
		LastDamageFrom = setmetatable({}, {__mode = "k"})
	}
	
	local HasCleanedUp
	local function Cleanup()
		if HasCleanedUp then return end
		HasCleanedUp = true

		Data[Bot] = nil
	end

	Bot.Humanoid.Died:Once(Cleanup)
	Bot.Destroying:Once(Cleanup)
	
	Data[Bot] = BotData
	return BotData
end

function ScoreObjectiveUtility.initialize(Bot: Model)
	if ScoreObjectiveUtility.Initialized[Bot] then return end
	ScoreObjectiveUtility.Initialized[Bot] = true
	
	local BotData = GetData(Bot)
	
	Bot.Hit.Event:Connect(function(Attacker: Model, Damage)
		BotData.TakenDamageFrom[Attacker] = (BotData.TakenDamageFrom[Attacker] or 0) + Damage
		BotData.LastDamageFrom[Attacker] = os.clock()
	end)
end

function ScoreObjectiveUtility.getAlliesAndEnemiesNearPart(Bot: Model, Part: BasePart)
	local BotConfig = Bot.Configuration
	local BotNation = BotConfig.Nation.Value
	local AlliesNearby, EnemiesNearby = Part:GetAttribute(BotNation.Name) or 0, 0

	for _, Nation in Nations do
		if Nation == BotNation then continue end
		EnemiesNearby += Part:GetAttribute(Nation.Name) or 0
	end

	return AlliesNearby, EnemiesNearby
end

function ScoreObjectiveUtility.getDistanceScore(Bot: Model, Position: Vector3, BaseScore)
	local HumanoidRootPart = Bot.HumanoidRootPart
	local VISION_SQ = Bot.Configuration.Vision.Value ^ 2
	BaseScore = BaseScore or 2.5

	local Delta = HumanoidRootPart.Position - Position
	local DistanceSq = Delta:Dot(Delta)

	return BaseScore - math.clamp(DistanceSq / VISION_SQ, 0, 1)
end

function ScoreObjectiveUtility.getCrowdPenalty(ActorCount, Threshold)
	return math.max(0, ActorCount - Threshold)
end

function ScoreObjectiveUtility.getClaimedPenalty(Bot: Model, Node: BasePart)
	local BotConfig = Bot.Configuration
	local BotNation = BotConfig.Nation.Value
	
	local Brain = require(Bot["Bot Controller"].Brain)
	local ClaimedAmount = Node:GetAttribute(BotNation.Name .. "Claimed") or 0

	if Brain.LastNode == Node then
		ClaimedAmount -= 1
	end

	return math.max(0, ClaimedAmount) * 2.5
end

-- Claims/unclaims (claiming = marking as the bot is heading there) the given node for the bot
function ScoreObjectiveUtility.toggleNodeClaim(Bot: Model, Node: BasePart, ClaimOrUnclaim)
	local BotConfig = Bot.Configuration
	local BotNation = BotConfig.Nation.Value
	
	local AttributeName = BotNation.Name .. "Claimed"
	local CurrentClaimed = Node:GetAttribute(AttributeName) or 0
	Node:SetAttribute(AttributeName, math.max(
		0,
		CurrentClaimed + (ClaimOrUnclaim and 1 or -1))
	)
end

function ScoreObjectiveUtility.isCurrentTargetRelevant(Bot: Model, CurrentMovementGoal: Vector3)
	local BotData = GetData(Bot)
	local Humanoid = Bot.Humanoid
	local HumanoidRootPart = Bot.HumanoidRootPart
	
	local BotConfig = Bot.Configuration
	
	local Brain = require(Bot["Bot Controller"].Brain)
	local Target = Brain.Target
	
	local RELEVANT_ENEMY_RADIUS_SQ = BotConfig["Relevant Enemy Radius"].Value ^ 2
	local THREAT_CONSIDER_DAMAGE_THRESHOLD = BotConfig["Threat Consider Damage Threshold"].Value / 100
	local THREAT_MEMORY_DECAY_DELAY = BotConfig["Threat Memory Decay Delay"].Value
	
	local TargetHumanoidRootPart = Target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not TargetHumanoidRootPart then return end
	
	-- If the enemy is relevant to our current position
	local CurrentDelta = TargetHumanoidRootPart.Position - HumanoidRootPart.Position
	if CurrentDelta:Dot(CurrentDelta) < RELEVANT_ENEMY_RADIUS_SQ then
		return true
	end
	
	-- If the enemy is relevant to the current movement goal
	local MovementGoalDelta = TargetHumanoidRootPart.Position - CurrentMovementGoal
	if MovementGoalDelta:Dot(MovementGoalDelta) < RELEVANT_ENEMY_RADIUS_SQ then
		return true
	end
	
	-- Relevancy is also considered based on received damage
	local TakenDamage = BotData.TakenDamageFrom[Target] or 0
	local LastHit = BotData.LastDamageFrom[Target] or 0
	
	-- Clears the damage if it's been a while since we were hit
	if os.clock() - LastHit > THREAT_MEMORY_DECAY_DELAY then
		BotData.TakenDamageFrom[Target] = nil
		BotData.LastDamageFrom[Target] = nil
		return
	end
	
	-- If the enemy has dealt enough damage to warrant a threat
	if TakenDamage / Humanoid.MaxHealth >= THREAT_CONSIDER_DAMAGE_THRESHOLD then
		return true
	end
end

function ScoreObjectiveUtility:GetRandomNoise()
	return RNG:NextInteger(-1, 1)
end

return ScoreObjectiveUtility
