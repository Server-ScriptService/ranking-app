local Automatics = {CachedPlayerRootParts = {}}

local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local RayParameters = RaycastParams.new()
RayParameters.CollisionGroup = "Shot Tracer"
RayParameters.FilterType = Enum.RaycastFilterType.Exclude

local ShotLimits = {
	MAX_ORIGIN_DISTANCE_FROM_HEAD_SQ = 18 ^ 2,
	RANGE_BUFFER = 10,
	MAX_FORWARD_ANGLE = 60,
	MAX_HIT_ERROR = 8
}

type Actor = Player | Model
type ClientShotInfo = {
	Origin: Vector3,
	Direction: Vector3,
	HitPosition: Vector3?,
	HitPart: BasePart?,
}

local function GetCharacterModelFromPart(Part: BasePart?)
	if not Part then return end
	local Current = Part
	
	while Current and Current ~= workspace do
		if Current:IsA("Model") and Current:FindFirstChildWhichIsA("Humanoid") then
			return Current
		end
		
		Current = Current.Parent
	end
	
	return
end

function Automatics:initialize()
	local function CachePlayerRootParts(player: Player)
		player.CharacterAdded:Connect(function(Character: Model)
			Automatics.CachedPlayerRootParts[player] = Character:WaitForChild("HumanoidRootPart")
		end)

		player.CharacterRemoving:Connect(function()
			Automatics.CachedPlayerRootParts[player] = nil
		end)

		-- Already existing character cache
		if player.Character then
			Automatics.CachedPlayerRootParts[player] = player.Character:WaitForChild("HumanoidRootPart")
		end
	end

	for _, player in pairs(Players:GetPlayers()) do
		CachePlayerRootParts(player)
	end

	Players.PlayerAdded:Connect(CachePlayerRootParts)

	Players.PlayerRemoving:Connect(function(player: Player)
		Automatics.CachedPlayerRootParts[player] = nil
	end)
end

function Automatics.createSound(Parent, Id, RollOffMin)
	local SFX = Instance.new("Sound")
	SFX.Volume = 2
	SFX.RollOffMinDistance = RollOffMin or 7
	SFX.SoundId = "rbxassetid://" .. Id
	SFX.Parent = Parent

	if not SFX.IsLoaded then 
		SFX.Loaded:Connect(function()
			SFX:Play()
			Debris:AddItem(SFX, SFX.TimeLength)
		end)
	else
		SFX:Play()
		Debris:AddItem(SFX, SFX.TimeLength)
	end

	return SFX
end

-- Hitscan, returns 1. Raycast's result 2. Blocked (true if path obstructed)
function Automatics.raycast(Actor: Actor, Origin: Vector3, Direction: Vector3)
	local Exclusions = Actor:IsA("Player") and {Actor.Character} or {Actor}
	
	local Character = Actor:IsA("Player") and Actor.Character or Actor
	local Head = Character:FindFirstChild("Head")
	if not Head then return end
	
	local HeadPosition = Head.Position
	local HeadToOrigin = HeadPosition and Origin - HeadPosition

	for _, Hitbox in CollectionService:GetTagged("NPC Hitbox") do
		table.insert(Exclusions, Hitbox)
	end

	RayParameters.FilterDescendantsInstances = Exclusions
	
	-- Prevents through-wall shooting
	if workspace:Raycast(HeadPosition, HeadToOrigin, RayParameters) then
		return nil, true
	end

	return workspace:Raycast(Origin, Direction, RayParameters)
end

function Automatics.handleDamageLogicForNPCs(Actor: Model, Origin: Vector3, Direction: Vector3, Range)
	local ActorShotResult = Automatics.raycast(Actor, Origin, Direction * Range)
	local Data = {}
	
	if ActorShotResult then
		Data.HitPosition = ActorShotResult.Position or Origin + Direction * Range
		Data.HitPart = ActorShotResult.Instance
		Data.MaterialName = ActorShotResult.Material.Name
	end
	
	return Data	
end

function Automatics.reload(Actor: Actor, Weapon: Model, ReloadingActors, ReloadTime, ReloadSFXId: string)
	local Key = Actor:IsA("Player") and Actor.UserId or Actor
	if ReloadingActors[Key] then return end

	local Ammo, MaxAmmo = Weapon:WaitForChild("Ammo"), Weapon:WaitForChild("Max Ammo")
	ReloadingActors[Key] = true

	-- This attachment is used to place the ReloadSFX on
	local Attachment = (Weapon:FindFirstChild("Barrel") or Weapon:FindFirstChild("Body")):FindFirstChildWhichIsA("Attachment")
	local Reloading = Weapon:FindFirstChild("Reloading")
	
	local function SetReloadingValue(Flag)
		Flag = if Flag == nil then false else Flag
		if Reloading then Reloading.Value = Flag end
	end
	
	SetReloadingValue(true)

	task.wait(ReloadTime)
	Automatics.createSound(Attachment, ReloadSFXId)
	
	Ammo.Value = MaxAmmo.Value
	SetReloadingValue()
	
	ReloadingActors[Key] = nil
end

function Automatics.validateClientShot(player: Player, ShotInfo: ClientShotInfo, Range)
	local Origin, Direction, HitPosition, HitPart = ShotInfo.Origin, ShotInfo.Direction, ShotInfo.HitPosition, ShotInfo.HitPart

	local Character = player.Character
	if not Character then return end

	local Head = Character:FindFirstChild("Head")
	local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
	if not (Head and HumanoidRootPart) then return end

	if Direction.Magnitude < 0.9 or Direction.Magnitude > 1.1 then
		return
	end
	
	-- Reported shot must be decently close to the player's head
	local OriginDistance = Origin - Head.Position
	if OriginDistance:Dot(OriginDistance) > ShotLimits.MAX_ORIGIN_DISTANCE_FROM_HEAD_SQ then
		return
	end

	local DirectionUnit = Direction.Unit
	local ToHit = HitPosition - Origin
	local Distance = ToHit.Magnitude
	
	-- Checks if the hit position is within a reasonable distance from the origin (weapon)
	if Distance == 0 or Distance > (Range + ShotLimits.RANGE_BUFFER) then
		return
	end
	
	-- Direction must point toward the reported hit
	if DirectionUnit:Dot(ToHit.Unit) < math.cos(math.rad(6)) then
		return
	end
	
	-- Checks if the direction unit is facing forward
	if HumanoidRootPart.CFrame.LookVector:Dot(DirectionUnit) < math.cos(math.rad(ShotLimits.MAX_FORWARD_ANGLE)) then
		return
	end
	
	local HitModel = GetCharacterModelFromPart(HitPart)
	local FilterList = {Character}
	
	if HitModel then
		table.insert(FilterList, HitModel)
	end
	
	RayParameters.FilterDescendantsInstances = FilterList
	
	-- Wall obstruction check from the camera
	local HeadToOrigin = Origin - Head.Position
	local CameraObstructedByWall = workspace:Raycast(Head.Position, HeadToOrigin, RayParameters)
	if CameraObstructedByWall then return end
	
	-- Shot obstruction check
	local ObstructedByWall = workspace:Raycast(Origin, DirectionUnit * Distance, RayParameters)
	if ObstructedByWall then return end
	
	-- Validates hit part
	if not HitPart then return true end
	
	if not HitPart:IsA("BasePart") then return end
	if HitPart:IsDescendantOf(Character) then return end

	local HitPartDistance = HitPart.Position - HitPosition
	local MaxDistance = ShotLimits.MAX_HIT_ERROR + HitPart.Size.Magnitude
	
	-- If the reported distance is too far from the part, it's invalid
	if HitPartDistance:Dot(HitPartDistance) > MaxDistance ^ 2 then
		return
	end
	
	return true
end

function Automatics.handleCooldown(Actor: Player | Model, CooldownTime, NextShot)
	local Now = os.clock()
	local Key = Actor:IsA("Player") and Actor.UserId or Actor

	local OnCooldown = (NextShot[Key] or 0) > Now
	if OnCooldown then return true end

	NextShot[Key] = Now + CooldownTime
	return
end

-- Rounds a vector's axis values to the nearest 0.1 stud
function Automatics.getPackedVector(Vector: Vector3?)
	local function Round1(Number)
		return math.round(Number * 10) / 10
	end
	
	return Vector and vector.create(
		Round1(Vector.x),
		Round1(Vector.y),
		Round1(Vector.z)
	)
end

return Automatics
