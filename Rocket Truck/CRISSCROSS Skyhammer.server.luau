local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ServerStorage.Modules

local Damage = require(Modules.Damage)
local Combat = require(Modules.Combat)
local Quickban = require(Modules.Quickban)

local Events = ReplicatedStorage:WaitForChild("Network"):WaitForChild("Events")
local SkyhammerRocketSimulation = Events:WaitForChild("Vehicles"):WaitForChild("Skyhammer Rocket Simulation")

local SkyhammerEvent = script.Skyhammer

local Skyhammer = script.Parent
local VehicleSeat = Skyhammer.VehicleSeat
local Box = Skyhammer["Rocket Pod"].Box
local LaunchVFXAttachment = Box:WaitForChild("Launch VFX")

local Wind = LaunchVFXAttachment:WaitForChild("Wind")

local LaunchSmoke = LaunchVFXAttachment:WaitForChild("Skyhammer Launch Smoke")

local Configuration = Skyhammer.Configuration
local SkyhammerOwner = Configuration.Owner.Value
local SkyhammerUsable = Configuration:WaitForChild("IsUsable")

-- Statistics
local Statistics = Skyhammer.Statistics
local RocketDamage = Statistics["Rocket Damage"]
local RocketCount = Statistics["Rocket Count"]

local FireRocketsCooldown = Statistics["Fire Rockets Cooldown"]
local PerRocketLaunchDelay = Statistics["Per-Rocket Launch Delay"]

local RocketPower = Statistics["Rocket Power"]
local MinRocketPower = Statistics["Min Rocket Power"]
local MaxRocketPower = Statistics["Max Rocket Power"]
local OnFireRocketsCooldown = Statistics["On Fire Rockets Cooldown"]

local MAX_ROCKET_ANTICHEAT_DISTANCE = 529 ^ 2 -- Client can't report rockets further than this

local EXPLOSION_HITBOX_SIZE = vector.create(32, 24, 32)

local RocketsRemaining = {} -- Prevents the skyhammer owner from calling however many explosions they want

local function FireRockets(CirclePosition: Vector3)
	OnFireRocketsCooldown.Value = true
	SkyhammerUsable.Value = false

	Wind:Play()
	LaunchSmoke:SetAttribute("StopEmit", nil)

	for _, player in pairs(Players:GetPlayers()) do
		local SendingCirclePosition
		if player ~= SkyhammerOwner then SendingCirclePosition = CirclePosition end

		SkyhammerRocketSimulation:FireClient(
			player,
			SkyhammerOwner,
			RocketCount.Value,
			PerRocketLaunchDelay.Value,
			workspace:GetServerTimeNow() + 0.1,
			SendingCirclePosition
		)
	end

	task.delay(4.5, function()
		Wind:Stop()
		LaunchSmoke:SetAttribute("StopEmit", true)
		SkyhammerUsable.Value = true	
	end)

	task.delay(FireRocketsCooldown.Value, function()
		OnFireRocketsCooldown.Value = false
	end)
end

local function OnExplosion(ExplosionSite: CFrame?)
	if not ExplosionSite then return end

	local Delta = ExplosionSite.Position - Skyhammer["Rocket Pod"].Box.Position
	if Delta:Dot(Delta) >= MAX_ROCKET_ANTICHEAT_DISTANCE then
		warn("Returned because explosion site was unusually far away from the skyhammer box")
		return
	end

	-- Damage logic
	local HitParts = workspace:GetPartBoundsInBox(ExplosionSite, EXPLOSION_HITBOX_SIZE, OverlapParams.new())
	local HitCharacters = {}

	for _, HitPart in HitParts do
		local AttackInfo = Combat.canAttackEnemy(HitPart, Skyhammer)
		local Target = AttackInfo.Target

		if not Target then continue end
		if HitCharacters[Target] then continue end

		HitCharacters[Target] = true
		Damage.dealDamage(AttackInfo.TargetHealthContainer, RocketDamage.Value, HitPart, {
			Attacker = SkyhammerOwner
		})
	end
end

SkyhammerEvent.OnServerEvent:Connect(function(player: Player, RocketPowerOrCirclePosition)
	-- Is not a rocket power adjustment nor a circle position
	if typeof(RocketPowerOrCirclePosition) ~= "number" and typeof(RocketPowerOrCirclePosition) ~= "Vector3" then
		Quickban.ban(player)
		return
	end
	
	if not (player == SkyhammerOwner and VehicleSeat.Occupant == player.Character.Humanoid) then
		return
	end

	-- Rocket power adjustment
	if typeof(RocketPowerOrCirclePosition) == "number" then
		RocketPower.Value = math.clamp(
			RocketPowerOrCirclePosition, -- RocketPower
			MinRocketPower.Value,
			MaxRocketPower.Value
		)
		return
	end

	if OnFireRocketsCooldown.Value then
		return
	end
	
	-- Actual rocket firing logic	
	FireRockets(RocketPowerOrCirclePosition) -- CirclePosition
	RocketsRemaining[player.UserId] = RocketCount.Value
end)

SkyhammerRocketSimulation.OnServerEvent:Connect(function(player: Player, ImpactCFrame: CFrame?)
	if ImpactCFrame ~= nil and typeof(ImpactCFrame) ~= "CFrame" then
		Quickban.ban(player)
		return
	end
	
	if not (player == SkyhammerOwner and VehicleSeat.Occupant == player.Character.Humanoid) then
		return
	end

	local Remaining = RocketsRemaining[player.UserId]
	if not (Remaining and Remaining > 0) then return end
	
	RocketsRemaining[player.UserId] -= 1
	OnExplosion(ImpactCFrame)

	if RocketsRemaining[player.UserId] > 0 then return end
	RocketsRemaining[player.UserId] = nil
end)

Players.PlayerRemoving:Connect(function(player: Player)
	if player ~= SkyhammerOwner then return end
	RocketsRemaining[player.UserId] = nil
end)
