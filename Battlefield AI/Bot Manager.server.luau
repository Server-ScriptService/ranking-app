local Players = game:GetService("Players")
local Teams = game:GetService("Teams")

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScanRegion = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Scan Region"))

local BaseCPU = script.CPU
local CPUs = Instance.new("Folder")
CPUs.Name = "CPUs"
CPUs.Parent = workspace

local Beacons = workspace.Map.Beacons

local RNG = Random.new()

local NextCPUId = 0

local MAX_BOTS = 50
local CPU_DEATH_SPAWN_DELAY = 3 -- The next CPU's spawning will be delayed by this if a CPU dies
local ACTOR_SCAN_BOX_SIZE = vector.create(96, 12, 96)

local NextCPUSpawnAt = {}

local function GetAliveCPUs()
	local Count = 0

	for _, CPU in CPUs:GetChildren() do
		local Humanoid = CPU:FindFirstChildOfClass("Humanoid")
		if not (Humanoid and Humanoid.Health > 0) then continue end
		
		Count += 1
	end

	return Count
end

local function GetDesiredCPUCount()
	local PlayerCount = #Players:GetPlayers()
	return math.clamp(MAX_BOTS - PlayerCount, 0, MAX_BOTS)
end

local function GetDesiredCPUsToCurrentDiff()
	local Desired, Current = GetDesiredCPUCount(), GetAliveCPUs()
	local Difference = Desired - Current

	return Difference
end

-- Returns the nation with the least amount of players
local function GetLessNation()
	local NationsActors = Teams:GetTeams()
	local NationsCount = {}

	for _, Nation in NationsActors do
		NationsCount[Nation] = 0
	end

	-- Counts the actors in each nation
	for _, Actor in CollectionService:GetTagged("Actor") do
		local PlayerActor = Players:GetPlayerFromCharacter(Actor)
		local Nation = PlayerActor and PlayerActor.Team or Actor.Configuration.Nation.Value
		if not Nation then continue end

		NationsCount[Nation] += 1
	end

	local WorstCount = math.huge
	local WorstNation

	for _, NationName in NationsActors do
		if NationsCount[NationName] >= WorstCount then continue end
		WorstNation = NationName
		WorstCount = NationsCount[NationName]
	end

	return WorstNation
end

local function GetAllyOutnumberNearLocation(Location: Model, CPUNation)
	local Allies, Enemies = 0, 0
	local Pivot = Location:GetPivot()
	
	local PivotY = workspace:Raycast(Pivot.Position, vector.create(0, -1500, 0))
	PivotY = PivotY and PivotY.Position.Y or 6.5
	Pivot = CFrame.new(Pivot.X, PivotY, Pivot.Z)

	for _, Actor: Model in CollectionService:GetTagged("Actor") do
		local HumanoidRootPart = Actor:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not HumanoidRootPart then continue end
		
		if not ScanRegion.isPositionInsideBox(HumanoidRootPart.Position, Pivot, ACTOR_SCAN_BOX_SIZE) then
			continue
		end

		local PlayerActor = Players:GetPlayerFromCharacter(Actor)
		local Nation = PlayerActor and PlayerActor.Team or Actor.Configuration.Nation.Value
		if not Nation then continue end

		if Nation == CPUNation then
			Allies += 1
		else
			Enemies += 1
		end
	end

	return Allies - Enemies
end

local function InsertCPU()
	if GetAliveCPUs() >= MAX_BOTS then return end
	
	local BestBeacon, BestBeaconScore
	local PlaceToSpawnCPUAt

	local CPUNation = GetLessNation()
	local NextSpawn = NextCPUSpawnAt[CPUNation] or 0
	if os.clock() < NextSpawn then return end

	-- Gets the furthest beacon we can spawn at that's not saturated already
	for _, Beacon in Beacons:GetChildren() do
		if Beacon.Configuration.Nation.Value ~= CPUNation then continue end

		local BeaconScore = Beacon:GetAttribute("UIOrder") or 0

		if GetAllyOutnumberNearLocation(Beacon, CPUNation) >= 3 then
			BeaconScore -= 4
		end

		if BeaconScore <= (BestBeaconScore or 0) then continue end
		BestBeaconScore = BeaconScore
		BestBeacon = Beacon
	end

	PlaceToSpawnCPUAt = BestBeacon

	if not PlaceToSpawnCPUAt then
		-- No beacon, resort to a random base
		local Bases = workspace[CPUNation.Name].Bases :: Folder
		local BaseChildren = Bases:GetChildren()
		if #BaseChildren == 0 then return end -- Still no location to spawn at
		
		PlaceToSpawnCPUAt = BaseChildren[RNG:NextInteger(1, #BaseChildren)]
	end

	NextCPUId += 1
	
	local CreatedCPU = BaseCPU:Clone()
	CreatedCPU.Name = "CPU #" .. NextCPUId
	CreatedCPU.Configuration.Nation.Value = CPUNation

	local Spawns = {}
	local ChosenSpawn

	-- CPU spawn location
	for _, ActorSpawn: BasePart in CollectionService:GetTagged("Actor Spawn") do
		if not (ActorSpawn:IsDescendantOf(PlaceToSpawnCPUAt) and ActorSpawn.Name == "Spawn") then continue end
		table.insert(Spawns, ActorSpawn)
	end

	-- CPU scripts
	CreatedCPU["Bot Controller"].Enabled = true
	CreatedCPU["Bot Animations"].Enabled = true
	
	ChosenSpawn = Spawns[RNG:NextInteger(1, #Spawns)]

	local CPUColor = CPUNation.TeamColor
	CreatedCPU["Body Colors"].RightArmColor = CPUColor
	CreatedCPU["Body Colors"].LeftArmColor = CPUColor
	CreatedCPU["Body Colors"].RightLegColor = CPUColor
	CreatedCPU["Body Colors"].LeftLegColor = CPUColor
	CreatedCPU["Body Colors"].HeadColor = CPUColor
	CreatedCPU["Body Colors"].TorsoColor = BrickColor.new(CPUColor.Color:Lerp(Color3.fromRGB(255, 255, 255), 0.25))

	-- Sets NextCPUSpawnAt[CPUNation] to now + CPU_SPAWN_DELAY if the CPU dies to prevent endless meat grinding stalemates
	CreatedCPU.Humanoid.Died:Once(function()
		if os.clock() < (NextCPUSpawnAt[CPUNation] or 0) then return end
		NextCPUSpawnAt[CPUNation] = os.clock() + CPU_DEATH_SPAWN_DELAY
	end)

	CreatedCPU:PivotTo(ChosenSpawn.CFrame)
	CreatedCPU.PrimaryPart = CreatedCPU.HumanoidRootPart
	CreatedCPU.Parent = CPUs
	
	return true -- Successfully spawned
end

local function PopMostUselessCPU()
	local MostUselessCPU
	local MostUselessCPUScore = -math.huge

	for _, CPU in CPUs:GetChildren() do
		local UselessnessScore = 0

		local Humanoid = CPU:FindFirstChild("Humanoid") :: Humanoid? 
		local HumanoidRootPart = CPU:FindFirstChild("HumanoidRootPart") :: BasePart?

		-- Immediately useless if it has no humanoid or humanoidrootpart or is dead
		if not (Humanoid and HumanoidRootPart and Humanoid.Health > 0) then
			MostUselessCPU = CPU
			break
		end

		local LastActorHitBy = CPU:FindFirstChild("Last Actor Hit By")
		if not (LastActorHitBy and LastActorHitBy.Value) then
			-- Hasn't been attacked in a while
			UselessnessScore += 1
		end

		local Brain = require(CPU["Bot Controller"].Brain)
		if Brain.State == "Idle" then
			UselessnessScore += 1.5
		else
			UselessnessScore -= 1.5
		end

		if Humanoid.Health / Humanoid.MaxHealth < 0.4 then
			UselessnessScore += 2
		end

		if Brain.Target then
			UselessnessScore -= 20
		end

		if UselessnessScore < MostUselessCPUScore then continue end
		MostUselessCPU = CPU
		MostUselessCPUScore = UselessnessScore
	end
	
	if not MostUselessCPU then return end
	MostUselessCPU:Destroy()
end

local function Loop()
	local Difference = GetDesiredCPUsToCurrentDiff()

	if Difference > 0 then
		InsertCPU()
	elseif Difference < 0 then
		PopMostUselessCPU()
	end
end

Loop()

while task.wait(0.25) do
	Loop()
end
