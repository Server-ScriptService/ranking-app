local Teams = game:GetService("Teams")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local BeaconFolder = workspace.Map.Beacons
local Beacons = BeaconFolder:GetChildren()

local ScanRegion = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Scan Region"))
local PointGainEvent = ReplicatedStorage:WaitForChild("Network"):WaitForChild("Events"):WaitForChild("Point Gain")

local Actors = {}
local PointAwardCooldowns = {}

local SATURATION_THRESHOLD = 8 -- If a beacon has this many soldiers, it's considered saturated

local POINTS_REWARD_FOR_CAPTURE = 150
local BEACON_CAPTURE_REWARD_COOLDOWN = 10

local function IsCharacterInZone(Character: Model, Zone: BasePart)
	local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
	return HumanoidRootPart and ScanRegion.isPositionInsideBox(HumanoidRootPart.Position, Zone.CFrame, Zone.Size)
end

-- Returns true if the given character is NEAR the given zone (not strictly inside)
local function IsCharacterNearZone(Character: Model, Zone: BasePart)
	local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
	if not HumanoidRootPart then return end

	local ZoneSize = Zone.Size :: Vector3
	ZoneSize = vector.create(ZoneSize.X, ZoneSize.Y * 6, ZoneSize.Z * 6)

	return ScanRegion.isPositionInsideBox(HumanoidRootPart.Position, Zone.CFrame, ZoneSize)
end

-- Returns a table for each nation with the amount of soldiers on that nation in them. Is strictly in the beacon
local function GetNationSoldiersInsideBeacon(Beacon: Model)
	local NationCounts = {} -- Key = nation, value = amount of soldiers from that nation
	local Soldiers = {} -- Key = nation, value = array of the actual actors
	local Zone = Beacon.Zone :: BasePart

	for _, Nation in pairs(Teams:GetTeams()) do
		NationCounts[Nation] = 0
		Soldiers[Nation] = {}
	end

	for _, Actor: Model in Actors do
		local PlayerActor = Players:GetPlayerFromCharacter(Actor)
		local ActorConfiguration = Actor:FindFirstChild("Configuration") and Actor.Configuration
		
		local Nation = PlayerActor and PlayerActor.Team or ActorConfiguration and ActorConfiguration.Nation.Value
		if not Nation then continue end
		
		if Nation and NationCounts[Nation] ~= nil and IsCharacterInZone(Actor, Zone) then
			if Actor.Humanoid.Health <= 0 then continue end
			NationCounts[Nation] += 1
			table.insert(Soldiers[Nation], Actor)
		end
	end

	return NationCounts, Soldiers
end

-- Returns a table for each nation with the amount of soldiers on that nation in them. Is loose, only near the beacon, not precise
local function GetNationSoldiersNearBeacon(Beacon: Model)
	local NationCounts = {} -- Key = nation, value = amount of soldiers from that nation
	local Zone = Beacon.Zone :: BasePart
	
	for _, Nation in pairs(Teams:GetTeams()) do
		NationCounts[Nation] = 0
	end
	
	for _, Actor: Model in Actors do
		local PlayerActor = Players:GetPlayerFromCharacter(Actor)
		local ActorConfiguration = Actor:FindFirstChild("Configuration") and Actor.Configuration
		local Nation = PlayerActor and PlayerActor.Team or ActorConfiguration and ActorConfiguration.Nation.Value
		
		if Nation and NationCounts[Nation] ~= nil and IsCharacterNearZone(Actor, Zone) and Actor.Humanoid.Health > 0 then
			NationCounts[Nation] += 1
		end
	end
	
	return NationCounts
end

local function BeaconLoop(Beacon: Model)
	local Configuration = Beacon.Configuration :: Configuration

	local CaptureProgress: NumberValue, ProgressToCapture: NumberValue = Configuration["Capture Progress"], Configuration["Progress To Capture"]
	local ProgressIncrease: NumberValue = Configuration["Progress Increase"]

	local OwnerNation: ObjectValue, CapturingNation: ObjectValue = Configuration.Nation, Configuration["Capturing Nation"]

	local NationsInside, SoldiersInside = GetNationSoldiersInsideBeacon(Beacon)
	local NationsNear = GetNationSoldiersNearBeacon(Beacon)
	
	local NationsOnBeacon = 0
	local TotalSoldiersNearBeacon = 0
	
	local NationAttemptingCapture
	
	-- Populates the soldiers on the beacon
	for Nation, SoldierCount in NationsInside do
		if SoldierCount <= 0 then continue end

		NationsOnBeacon += 1
		NationAttemptingCapture = Nation
	end
	
	-- Populates the soldiers near the beacon
	for _, Soldiers in NationsNear do
		TotalSoldiersNearBeacon += Soldiers
	end
	
	if Beacon:GetAttribute("Saturated") == nil then
		Beacon:SetAttribute("Saturated", false)
	end
	
	if TotalSoldiersNearBeacon >= SATURATION_THRESHOLD then
		Beacon:SetAttribute("Saturated", true)
	else
		Beacon:SetAttribute("Saturated", false)
	end

	if NationsOnBeacon > 1 then
		Beacon:SetAttribute("Contested", true)
		return
	end

	Beacon:SetAttribute("Contested", false)

	if NationsOnBeacon == 0 then
		-- Decrements capture progress if a capturing nation was on the beacon before they exited
		if CapturingNation.Value then
			CaptureProgress.Value = math.max(CaptureProgress.Value - ProgressIncrease.Value, 0)
			if CaptureProgress.Value <= 0 then
				CapturingNation.Value = nil
			end
		end

		return
	end

	-- Owner nation on their own beacon
	if OwnerNation.Value == NationAttemptingCapture then
		CapturingNation.Value = nil
		CaptureProgress.Value = 0
		return
	end

	-- If capturing nation is not the same as the one attempting capture, set it
	if CapturingNation.Value ~= NationAttemptingCapture then
		CapturingNation.Value = NationAttemptingCapture
		CaptureProgress.Value = 0
	end

	CaptureProgress.Value += ProgressIncrease.Value

	-- Successful capture logic
	if CaptureProgress.Value < ProgressToCapture.Value then return end
	
	OwnerNation.Value = NationAttemptingCapture
	CaptureProgress.Value = 0
	CapturingNation.Value = nil

	-- Point reward
	for _, Soldier in SoldiersInside[OwnerNation.Value] do
		local AssistingPlayer = Players:GetPlayerFromCharacter(Soldier)
		if not AssistingPlayer then continue end

		local IsOnCooldown = PointAwardCooldowns[AssistingPlayer.UserId]
		if IsOnCooldown then continue end

		PointAwardCooldowns[AssistingPlayer.UserId] = true
		task.delay(BEACON_CAPTURE_REWARD_COOLDOWN, function()
			PointAwardCooldowns[AssistingPlayer.UserId] = nil
		end)

		local Data = AssistingPlayer.Data
		Data:SetAttribute("Points", Data:GetAttribute("Points") + POINTS_REWARD_FOR_CAPTURE)
		PointGainEvent:FireClient(AssistingPlayer, "SECURED BEACON", POINTS_REWARD_FOR_CAPTURE)
	end
end

local function SetBeaconColor(OwnerNation: ObjectValue, Beacon: Model)
	local Nation: Team = OwnerNation.Value
	local NationColor = Nation and Nation.TeamColor.Color or Color3.fromRGB(255, 255, 255)

	Beacon.Beam.Color = NationColor
	Beacon.Outline.Color = NationColor
	Beacon.Rim.Color = NationColor
end

-- Visually updates the beacon color based on the owner nation
local function AddColorConnectionsForBeacon(Beacon: Model)
	local OwnerNation = Beacon.Configuration.Nation
	SetBeaconColor(OwnerNation, Beacon)

	OwnerNation:GetPropertyChangedSignal("Value"):Connect(function()
		SetBeaconColor(OwnerNation, Beacon)
	end)

	Beacon:GetAttributeChangedSignal("Contested"):Connect(function()
		SetBeaconColor(OwnerNation, Beacon)
	end)
end

-- Manages the Actors table
for _, Actor in CollectionService:GetTagged("Actor") do
	table.insert(Actors, Actor)
end

CollectionService:GetInstanceAddedSignal("Actor"):Connect(function(Actor: Model)
	table.insert(Actors, Actor)
end)

CollectionService:GetInstanceRemovedSignal("Actor"):Connect(function(Actor: Model)
	local Index = table.find(Actors, Actor)
	if Index then table.remove(Actors, Index) end
end)

for _, Beacon in Beacons do
	AddColorConnectionsForBeacon(Beacon)
end

BeaconFolder.ChildAdded:Connect(function(Beacon: Model)
	table.insert(Beacons, Beacon)
	AddColorConnectionsForBeacon(Beacon)
end)

while task.wait(0.25) do
	for _, Beacon in Beacons do
		BeaconLoop(Beacon)
	end
end
