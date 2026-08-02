local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
Player.CharacterAdded:Connect(function(NewCharacter: Model) Character = NewCharacter end)

local Modules = ReplicatedStorage.Modules
local WorldEffects = require(Modules["World Effects"])

local SkyhammerRocketSimulation = ReplicatedStorage.Network.Events.Vehicles["Skyhammer Rocket Simulation"]

local BaseRocket = ReplicatedStorage.Models.Dynamic["Skyhammer Rocket"]

local function Round1(Number)
	return math.round(Number * 10) / 10
end

SkyhammerRocketSimulation.OnClientEvent:Connect(function
(SkyhammerOwner: Player?, RocketCount, PerRocketLaunchDelay, StartTime, SentCirclePos: Vector3?)
	if not SkyhammerOwner then return end

	local SkyhammerOwnerId = SkyhammerOwner.UserId
	local AlreadyEmitSmoke

	for i = 1, RocketCount do
		local SkyhammerOwnerWorkspaceFolder = workspace:FindFirstChild(SkyhammerOwnerId)
		if not SkyhammerOwnerWorkspaceFolder then break end

		local Skyhammer: Model? = SkyhammerOwnerWorkspaceFolder:FindFirstChild("CRISSCROSS Skyhammer")
		local Circle: BasePart? = Skyhammer and Skyhammer:FindFirstChild("Circle")

		if not Skyhammer then break end
		if not (Circle or SentCirclePos) then break end

		local Attachment = Skyhammer:WaitForChild("Rocket Pod"):WaitForChild("Box"):WaitForChild("Attachment " .. i)

		local SkyhammerScript = Skyhammer:FindFirstChild(Skyhammer.Name)
		local CirclePosition = SentCirclePos or Circle.Position

		-- Visuals
		local ExplosionSFX = SkyhammerScript:WaitForChild("Explosion SFX")
		local ExplosionVFX = SkyhammerScript:WaitForChild("Explosion VFX")

		local Rocket = BaseRocket:Clone()
		Rocket.Parent = SkyhammerOwnerId == Player.UserId and Skyhammer or workspace[Player.UserId] --[[ Fixes a bug where the landing visualization circle
			was constantly moving up and down because the raycast was constantly hitting the circle, so if we own the skyhammer, the rocket will be parented to it
			because the raycast filter descendants instances would exclude the skyhammer vehicle and the rocket would be a descendant of the skyhammer
		]]

		Rocket.Attachment.Fire:SetAttribute("StopEmit", nil)

		local FlightTime, ArcHeight = 3, 140

		local LaunchTime = StartTime + ((i - 1) * PerRocketLaunchDelay)
		local Elapsed = math.max(0, workspace:GetServerTimeNow() - LaunchTime)

		local StartPos = Attachment.WorldPosition
		local LastPos = StartPos

		local MIN_DIRECTION_MAGNITUDE_EPSILON = 0.01 ^ 2
		local CollisionConnection
		CollisionConnection = RunService.Heartbeat:Connect(function(DeltaTime)
			if not Rocket.Parent then
				CollisionConnection:Disconnect()
				return
			end

			Elapsed += DeltaTime

			local Alpha = math.clamp(Elapsed / FlightTime, 0, 1)
			local TargetPosition = CirclePosition

			local FlatPosition = StartPos:Lerp(TargetPosition, Alpha)
			local ArcOffset = vector.create(0, math.sin(Alpha * math.pi) * ArcHeight, 0)
			local NewPos = FlatPosition + ArcOffset

			local Direction = NewPos - LastPos
			if Direction:Dot(Direction) >= MIN_DIRECTION_MAGNITUDE_EPSILON then -- Prevents lookAt from breaking
				Rocket:PivotTo(CFrame.lookAt(NewPos, NewPos + Direction))
			else
				Rocket:PivotTo(CFrame.new(NewPos))
			end

			LastPos = NewPos

			-- Explosion logic
			if Alpha < 1 then
				return
			end

			CollisionConnection:Disconnect()
			CollisionConnection = nil

			local ImpactCFrame = CFrame.new(NewPos)
			Rocket:Destroy()

			local Container = WorldEffects.generateNonInteractablePart(ImpactCFrame, 24)
			Container.Parent = workspace

			-- If we're the skyhammer owner, we will send the coordinates of the impact to the server to create the explosion there
			if Player == SkyhammerOwner then
				SkyhammerRocketSimulation:FireServer(CFrame.new(
					Round1(ImpactCFrame.X),
					Round1(ImpactCFrame.Y),
					Round1(ImpactCFrame.Z))
				)
			end

			task.defer(function()
				-- VFX
				local VFXAttachment = ExplosionVFX:Clone()
				VFXAttachment.Parent = Container

				local Attachment2 = VFXAttachment.Attachment
				local SmokeBlobs = Attachment2["Smoke Blobs"] :: ParticleEmitter
				local SmokeBlobFill = Attachment2["Smoke Blob Fill"] :: ParticleEmitter

				local Explosion = VFXAttachment.Explosion :: ParticleEmitter
				local BaseSmoke = VFXAttachment["Base Smoke"] :: ParticleEmitter
				local Debris = VFXAttachment.Debris :: ParticleEmitter
				local Mist = VFXAttachment.Mist :: ParticleEmitter

				Explosion:Emit(10)
				Debris:Emit(50)

				if not AlreadyEmitSmoke then
					AlreadyEmitSmoke = true

					BaseSmoke:Emit(40)
					SmokeBlobs:Emit(50)
					Mist:Emit(50)

					SmokeBlobFill.Enabled = true

					task.delay(SmokeBlobs.Lifetime.Max, function()
						SmokeBlobFill.Enabled = false
					end)
				end

				-- SFX
				local SFX = ExplosionSFX:Clone()
				SFX.Parent = Container

				if not SFX.IsLoaded then SFX.Loaded:Wait() end
				SFX:Play()
			end)

			-- Screen effects
			local HitParts = workspace:GetPartBoundsInBox(ImpactCFrame, vector.create(111, 18, 111))
			local HitCharacters = {}	

			for _, HitPart in HitParts do
				local OwnCharacter = HitPart:FindFirstAncestorWhichIsA("Model") == Character
				if not (OwnCharacter and not HitCharacters[OwnCharacter]) then continue end

				HitCharacters[OwnCharacter] = true
				WorldEffects.shakeScreen("Explosion", 6, 1)
				WorldEffects.blurScreen()
			end
		end)

		-- Fallback incase there's no explosion even after 12 seconds
		task.delay(12, function()
			if not CollisionConnection then return end

			CollisionConnection:Disconnect()
			CollisionConnection = nil

			Rocket:Destroy()
			SkyhammerRocketSimulation:FireServer()
		end)

		task.wait(PerRocketLaunchDelay)
	end
end)
