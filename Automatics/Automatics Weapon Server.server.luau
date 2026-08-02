local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Events = ReplicatedStorage:WaitForChild("Network"):WaitForChild("Events")

local Modules = ServerStorage.Modules
local Combat = require(Modules.Combat)
local Quickban = require(Modules.Quickban)
local Automatics = require(Modules.Automatics)

local WeaponsFolder = script.Parent

Automatics:initialize()

local function InitializeWeapon(WeaponContainer: Model)
	local Event = Events:WaitForChild("Weapons"):WaitForChild(WeaponContainer.Name)

	local Logic = require(WeaponContainer[WeaponContainer.Name .. " Logic"])
	Logic:initialize()

	Event.OnServerEvent:Connect(function
	(player: Player, OriginOrReloadSignal: Vector3 | string, Direction: Vector3, HitPosition: Vector3, HitPart: BasePart?, MaterialName)
		if not Combat.canAttack(player) then return end
		
		if OriginOrReloadSignal == "Reload" then
			local Character = player.Character

			local Weapon = Character and Character:FindFirstChild(WeaponContainer.Name)
			if not Weapon then return end

			Logic.reload(player)
			return
		end

		-- A legit client should send a Vector3 if they're legit if not reloading, we already handled reloading above
		if typeof(OriginOrReloadSignal) ~= "Vector3" then
			Quickban.ban(player)
			return
		end

		if typeof(Direction) ~= "Vector3" then
			Quickban.ban(player)
			return
		end

		if typeof(HitPosition) ~= "Vector3" then
			Quickban.ban(player)
			return
		end

		if HitPart ~= nil and typeof(HitPart) ~= "Instance" then
			Quickban.ban(player)
			return
		end

		local Character = player.Character

		local Weapon = Character and Character:FindFirstChild(WeaponContainer.Name)
		if not Weapon then return end
		
		local ShotInfo = {
			Origin = OriginOrReloadSignal,
			Direction = Direction,
			HitPosition = HitPosition,
			HitPart = HitPart,
			MaterialName = MaterialName
		}

		Logic.fireBullet(player, ShotInfo)
	end)
end

for _, WeaponContainer in pairs(WeaponsFolder:GetChildren()) do
	if not (WeaponContainer:IsA("Model") and WeaponContainer:FindFirstChild(WeaponContainer.Name .. " Logic")) then -- No weapon logic module means the weapon has no functionality
		continue
	end

	InitializeWeapon(WeaponContainer)
end
