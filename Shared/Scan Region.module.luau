local ScanRegion = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local ActorUtility = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Actor Utility"))

local ACTOR_SCAN_BOX_SIZE = vector.create(96, 12, 96)

-- Counts the actors NEAR the given TargetCFrame
function ScanRegion.countActorsNearCFrame(TargetCFrame: CFrame)
	local Position = TargetCFrame.Position
	local RaycastResult = workspace:Raycast(Position, vector.create(0, -200, 0))
	local YPosition = RaycastResult and RaycastResult.Position.Y or Position.Y

	local BoxCFrame = CFrame.new(Position.X, YPosition, Position.Z)
	local Actors = {}

	for _, Actor: Model in CollectionService:GetTagged("Actor") do
		local HumanoidRootPart = Actor:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not HumanoidRootPart then continue end
		
		if not ScanRegion.isPositionInsideBox(HumanoidRootPart.Position, BoxCFrame, ACTOR_SCAN_BOX_SIZE) then
			continue
		end

		local Humanoid = Actor:FindFirstChild("Humanoid") :: Humanoid?
		if not (Humanoid and Humanoid.Health > 0) then continue end
		if not ActorUtility.indexNationFromObject(Actor) then continue end

		table.insert(Actors, Actor)
	end

	return Actors
end

function ScanRegion.isPositionInsideBox(Position: Vector3, BoxCFrame: CFrame, BoxSize: Vector3)
	local LocalPosition = BoxCFrame:PointToObjectSpace(Position)
	local HalfSize = BoxSize / 2

	return math.abs(LocalPosition.X) <= HalfSize.X 
		and math.abs(LocalPosition.Y) <= HalfSize.Y
		and math.abs(LocalPosition.Z) <= HalfSize.Z
end

-- Returns true if the position is grounded. ExcludeList excludes the given instances from the raycast
function ScanRegion.isPositionGrounded(Position: Vector3, ExcludeList)
	local Parameters = RaycastParams.new()
	Parameters.FilterType = Enum.RaycastFilterType.Exclude
	Parameters.FilterDescendantsInstances = ExcludeList or {}
	
	local Raycast = workspace:Raycast(Position, vector.create(0, -0.5, 0), Parameters)
	return Raycast ~= nil
end

return ScanRegion
