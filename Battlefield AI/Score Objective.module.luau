local ScoreObjective = {Initialized = {}}
local Data = {}

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RNG = Random.new()

local Beacons = workspace.Map.Beacons
local Nodes = workspace["AI Nodes"] :: Folder

local ScanRegion = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Scan Region"))
local Utility = require(script["Score Objective Utility"])

local DEBUG_SCORE_PRINT = false

local TOP_NODES_TO_CHOOSE_FROM = 6

local function GetData(Bot: Model)
	local BotData = Data[Bot]
	if BotData then return BotData end
	
	BotData = {
		Bases = {},
		AINodes = {},
		CachedBaseCFrames = {},
		LastNodeSwitch = 0,
		TimesQuicklySwitchedNodes = 0,
		ReachedObjective = Instance.new("BindableEvent"),
		ObjectiveChanged = Instance.new("BindableEvent"),
		ReachedObjectiveConnection = nil
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

function ScoreObjective.getReachedObjective(Bot: Model)
	return GetData(Bot).ReachedObjective
end

function ScoreObjective.getObjectiveChanged(Bot: Model)
	return GetData(Bot).ObjectiveChanged
end

local function GetBeaconScore(Bot: Model, BeaconNode: BasePart)
	local BotConfig = Bot.Configuration
	local BotNation = BotConfig.Nation.Value
	local Score = 0

	local NEED_TO_CAPTURE_INCREASE = 2

	local AlliesNearby, EnemiesNearby = Utility.getAlliesAndEnemiesNearPart(Bot, BeaconNode)
	local TotalActorsNearby = AlliesNearby + EnemiesNearby

	Score += Utility.getDistanceScore(Bot, BeaconNode.Position) * 2.5
	Score -= Utility.getCrowdPenalty(TotalActorsNearby, 10)

	local Beacon = Beacons[BeaconNode:GetAttribute("BeaconFullName")]
	local Owner = Beacon.Configuration.Nation.Value

	if Owner ~= BotNation then
		Score += NEED_TO_CAPTURE_INCREASE

		Score += math.min(EnemiesNearby, 8) * 0.6
		Score += math.min(AlliesNearby, 3) * 0.5

		local AllyOutnumber = math.max(0, (AlliesNearby - EnemiesNearby) - 4)
		Score -= AllyOutnumber * 2

		local AllyShortage = math.max(0, 6 - AlliesNearby)
		Score += AllyShortage * 0.75

		local EasyCapture = math.max(0, 4 - EnemiesNearby)
		Score += EasyCapture * 2
	else
		-- Don't camp already owned beacons
		Score -= NEED_TO_CAPTURE_INCREASE

		-- Nevermind, enemies are attacking it
		if EnemiesNearby > 0 then
			Score += math.min(EnemiesNearby, 12) * 1.75
		end

		Score -= math.min(AlliesNearby, 12) * 2 -- So we don't camp places with lots of allies already there
	end

	if DEBUG_SCORE_PRINT then print(Beacon.Name, "score:", Score) end
	return Score
end

local function GetFlankScore(Bot: Model, Flank: BasePart)
	local BotConfig = Bot.Configuration
	local BotNation = BotConfig.Nation.Value
	local Score = 6

	local BIASED_INCREASE = 4

	local AlliesNearby, EnemiesNearby = Utility.getAlliesAndEnemiesNearPart(Bot, Flank)
	local TotalActorsNearby = AlliesNearby + EnemiesNearby

	Score += Utility.getDistanceScore(Bot, Flank.Position)
	Score -= Utility.getCrowdPenalty(AlliesNearby, 5) * 2 

	Score += math.min(EnemiesNearby, 6) * 0.8

	local EnemyOutnumber = math.max(0, (EnemiesNearby - AlliesNearby) - 4)
	Score -= EnemyOutnumber * 1.75

	Score += math.min(AlliesNearby, 4) * 0.8

	-- Unused flank
	if TotalActorsNearby <= 4 then
		Score += 2
	end

	local BiasedNation = Flank:GetAttribute("BiasedNation")
	if BiasedNation == BotNation.Name then
		Score += BIASED_INCREASE
	else
		Score += BIASED_INCREASE * 1.35
	end

	if DEBUG_SCORE_PRINT then print("Flank score:", Score) end
	return Score
end

-- Key = Node.Name, Value = FunctionThatScoresTheNode
local NODE_SCORE_FUNCTIONS = {
	["Beacon Zone"] = GetBeaconScore,
	["Flank"] = GetFlankScore
}

function ScoreObjective.initialize(Bot: Model)
	if ScoreObjective.Initialized[Bot] then return end
	ScoreObjective.Initialized[Bot] = true

	local BotData = GetData(Bot)
	Utility.initialize(Bot)
	
	local BotConfig = Bot.Configuration
	local BotNation = BotConfig.Nation.Value
	local Brain = require(Bot["Bot Controller"].Brain)
	
	local HasCleanedUp, Cleanup
	
	--[[ "Claimed amount" refers to how many bots are going to a specific node.
	When the objective changes, this decrements the old node's claimed amount and increments the new node's claimed amount. Also marks LastNode ]]
	BotData.ObjectiveChanged.Event:Connect(function(NewObjectiveNode: BasePart?)
		if Brain.LastNode then Utility.toggleNodeClaim(Bot, Brain.LastNode) end
		Brain.LastNode = NewObjectiveNode

		if not NewObjectiveNode then return end
		Utility.toggleNodeClaim(Bot, NewObjectiveNode, true)
	end)

	Bot.Humanoid.Died:Once(function()
		BotData.ObjectiveChanged:Fire() -- So the above connection decrements the claimed amount for the node we had originally planned to go to before death
		Cleanup()
	end)

	-- Adds the given base to Bases if possible
	local function AddBase(Base: Model)
		local Index = table.find(BotData.Bases, Base)
		if Index then return end

		if not (Base:HasTag("Deployment Location") and Base.Name:match("Base")) then return end
		if Base.Configuration.Nation.Value ~= BotNation then return end

		table.insert(BotData.Bases, Base)
	end

	-- Adds every base to Bases
	for _, Base in CollectionService:GetTagged("Deployment Location") do
		AddBase(Base)
	end

	local BaseAddedConnection = CollectionService:GetInstanceAddedSignal("Deployment Location"):Connect(function(Base: Model)
		AddBase(Base)
	end)

	local BaseRemovedConnection = CollectionService:GetInstanceRemovedSignal("Deployment Location"):Connect(function(Base: Model)
		local Index = table.find(BotData.Bases, Base)
		if not Index then return end

		table.remove(BotData.Bases, Index)
	end)

	local function CacheNode(Node: BasePart)
		local Index = table.find(BotData.AINodes, Node)
		if Index then return end

		table.insert(BotData.AINodes, Node)
	end

	for _, Node in Nodes:GetChildren() do
		CacheNode(Node)
	end
	
	Cleanup = function()
		if HasCleanedUp then return end
		HasCleanedUp = true
		
		BaseAddedConnection:Disconnect()
		BaseRemovedConnection:Disconnect()
		BaseAddedConnection = nil
		BaseRemovedConnection = nil
		
		BotData.ObjectiveChanged:Destroy()
		BotData.ReachedObjective:Destroy()
		
		ScoreObjective.Initialized[Bot] = nil
	end
	
	Bot.Destroying:Once(function()
		if Brain.LastNode then
			Utility.toggleNodeClaim(Bot, Brain.LastNode)	
			Brain.LastNode = nil
		end
		
		Cleanup()
	end)
end

function ScoreObjective.setBestObjective(Bot: Model)
	local BotData = GetData(Bot)
	local BotConfig = Bot.Configuration
	local BotNation = BotConfig.Nation.Value
	
	local Brain = require(Bot["Bot Controller"].Brain)
	local HumanoidRootPart = Bot.HumanoidRootPart
	
	local BestNode
	local CandidateNodes = {}

	local Now = os.clock()

	-- Determines if we're in a base. UIf
	local BaseInsideOf: Model?
	for _, Base: Model in BotData.Bases do
		local Cached = BotData.CachedBaseCFrames[Base]
		if not (Cached and Cached.Pivot and Cached.Extents) then
			Cached = {
				Pivot = Base:GetPivot(),
				Extents = Base:GetExtentsSize()
			}
			
			BotData.CachedBaseCFrames[Base] = Cached
		end

		if not ScanRegion.isPositionInsideBox(HumanoidRootPart.Position, Cached.Pivot, Cached.Extents) then
			continue
		end

		BaseInsideOf = Base
		break
	end

	-- Goes outside of the base if we're in one
	if BaseInsideOf then
		local Outside = BaseInsideOf.Outside
		Brain.TargetInstance = Outside
		Brain.TargetPosition = Outside.Position
		return
	end

	if not Bot:GetAttribute("NodeLocked") then
		-- Increments the amount of times we quickly swapped nodes
		if Now - BotData.LastNodeSwitch <= 0.8 then
			BotData.TimesQuicklySwitchedNodes += 1
		else
			BotData.TimesQuicklySwitchedNodes = 0
		end

		if BotData.TimesQuicklySwitchedNodes >= BotConfig["Quickly Switching Switch Threshold"].Value then
			-- Stop oscillating and commit to whatever node we're on
			Bot:SetAttribute("NodeLocked", true)
			
			if BotData.ReachedObjectiveConnection then
				BotData.ReachedObjectiveConnection:Disconnect()
				BotData.ReachedObjectiveConnection = nil
			end

			BotData.ReachedObjectiveConnection = BotData.ReachedObjective.Event:Once(function()
				BotData.ReachedObjectiveConnection = nil
				if not Bot.Parent or BestNode ~= Brain.TargetInstance then
					return
				end
				
				-- Objective (node) reached, we can release the lock, however we might set the lock again below if it's a beacon we have to cap
				Bot:SetAttribute("NodeLocked", false)
				if BestNode.Name ~= "Beacon Zone" then return end

				-- Beacon logic: our desired node is a beacon, so wait until we get there and capture it before releasing the lock
				local Beacon = Beacons[BestNode:GetAttribute("BeaconFullName")]
				local BeaconNation = Beacon.Configuration.Nation
				if BeaconNation.Value == BotNation then return end -- No need to force the bot to get the beacon if we already got it

				Bot:SetAttribute("NodeLocked", true)
				
				-- Waits while bot exists, is alive, the best node is the current live target, and we don't own the desired beacon
				while Bot.Parent and Bot.Humanoid.Health > 0 and BestNode == Brain.TargetInstance and BeaconNation.Value ~= BotNation do
					task.wait(0.5)
				end

				-- Beacon captured
				if BeaconNation.Value ~= BotNation then return end
				Bot:SetAttribute("NodeLocked", false)
			end)
		end

		-- Actually scores nodes
		for _, Node: BasePart in BotData.AINodes do
			local NodeType = Node.Name
			local ScoreFunction = NODE_SCORE_FUNCTIONS[NodeType]

			if not ScoreFunction then
				warn('Weird node "' .. NodeType .. '"')
				continue
			end

			local Score = ScoreFunction(Bot, Node)
			Score -= Utility.getClaimedPenalty(Bot, Node)
			Score += Utility:GetRandomNoise()

			local Candidate = {
				Node = Node,
				Score = Score
			}
			
			table.insert(CandidateNodes, Candidate)
		end

		table.sort(CandidateNodes, function(A, B)
			return A.Score > B.Score
		end)

		local CandidateCount = math.min(TOP_NODES_TO_CHOOSE_FROM, #CandidateNodes)
		if CandidateCount <= 0 then return end

		BestNode = CandidateNodes[RNG:NextInteger(1, CandidateCount)].Node

		Brain.TargetInstance = BestNode
		Brain.TargetPosition = BestNode.Position

		if BestNode ~= Brain.LastNode then
			BotData.ObjectiveChanged:Fire(BestNode)
			BotData.LastNodeSwitch = Now
		end
	end

	-- Chases relevant enemies, otherwise continues towards the chosen objective
	local Target = Brain.Target
	if Target and Utility.isCurrentTargetRelevant(Bot, BestNode and BestNode.Position or vector.zero) then
		Bot:SetAttribute("NodeLocked", false)
		
		local TargetHumanoidRootPart = Target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not TargetHumanoidRootPart then
			return
		end

		Brain.TargetPosition = TargetHumanoidRootPart.Position
		Brain.TargetInstance = Target
		
		return
	end
end

return ScoreObjective
