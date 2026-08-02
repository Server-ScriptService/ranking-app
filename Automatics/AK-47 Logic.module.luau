local Logic = {}

local Model = script.Parent

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Modules = ServerStorage.Modules
local Combat = require(Modules.Combat)
local DamageModule = require(Modules.Damage)
local Automatics = require(Modules.Automatics)

local WeaponModel = ServerStorage.Weapons[Model.Name]
local Cooldown = WeaponModel.Cooldown.Value
local ReloadTime = WeaponModel.Reload.Value
local Damage = WeaponModel.Damage.Value
local Range = WeaponModel.Range.Value

local NextShot, ReloadingActors, ActorCleanupConnection = {}, {}, {}

local EFFECT_DISTANCE_SQ = 350 ^ 2 -- Players must be within this range to receive weapon effects

local WeaponEffects = ReplicatedStorage:WaitForChild("Network"):WaitForChild("Events"):WaitForChild("Weapon Effects")

local RELOAD_ID = tostring(Model["Reload Id"].Value)

type Actor = Player | Model
type ShotInfo = {
	Origin: Vector3,
	Direction: Vector3,
	HitPosition: Vector3?,
	HitPart: BasePart?,
	MaterialName: string?
}

function Logic:initialize()
	if Logic.Initialized then return end
	Logic.Initialized = true

	Players.PlayerRemoving:Connect(function(player: Player)
		NextShot[player.UserId] = nil
		ReloadingActors[player.UserId] = nil
	end)
end

function Logic.reload(Actor: Actor)
	local IsActorPlayer = Actor:IsA("Player")
	local Key = IsActorPlayer and Actor.UserId or Actor
	if ReloadingActors[Key] then return end
	
	local Character = IsActorPlayer and Actor.Character or Actor
	local Weapon = Character and Character:FindFirstChild(Model.Name)
	if not Weapon then return end
	
	Automatics.reload(Actor, Weapon, ReloadingActors, ReloadTime, RELOAD_ID)
end

function Logic.fireBullet(Actor: Actor, InfoTable: ShotInfo)
	local IsActorPlayer = Actor:IsA("Player")
	
	local Key = IsActorPlayer and Actor.UserId or Actor
	if ReloadingActors[Key] then return end

	local Origin, Direction, HitPosition, HitPart = InfoTable.Origin, InfoTable.Direction, InfoTable.HitPosition, InfoTable.HitPart
	local MaterialName = InfoTable.MaterialName

	local Character = IsActorPlayer and Actor.Character or Actor

	local AK47 = Character and Character:FindFirstChild(Model.Name)
	if not AK47 then return end

	local Ammo = AK47:FindFirstChild("Ammo")
	if not Ammo then return end

	if Ammo.Value <= 0 then
		-- Reload
		Automatics.reload(Actor, AK47, ReloadingActors, ReloadTime, RELOAD_ID)
		return
	end
	
	local OnCooldown = Automatics.handleCooldown(Actor, Cooldown, NextShot)
	if OnCooldown then return end
	
	if IsActorPlayer and not Automatics.validateClientShot(Actor, InfoTable, Range) then
		return
	end

	if Actor:IsA("Model") and not ActorCleanupConnection[Actor] then
		ActorCleanupConnection[Actor] = true

		Actor.Destroying:Once(function()
			NextShot[Actor] = nil
			ReloadingActors[Actor] = nil
			ActorCleanupConnection[Actor] = nil
		end)
	end

	Ammo.Value -= 1	

	local function DamageLogic(PartToAttack: BasePart?)
		if not PartToAttack then return end

		local AttackInfo = Combat.canAttackEnemy(PartToAttack, Character)
		if not AttackInfo.Target then return end
		
		DamageModule.dealDamage(AttackInfo.TargetHealthContainer, Damage, PartToAttack, {
			Attacker = Actor,
			MouseDir = HitPosition
		})
		
		return true -- Shot landed
	end

	local ShotLanded

	if IsActorPlayer then
		DamageLogic(HitPart)
	elseif Actor:IsA("Model") then
		-- Raycast manually for the non-player. We don't raycast for the player branch because they raycast themselves & we validate
		local NPCShotResult = Automatics.handleDamageLogicForNPCs(Actor, Origin, Direction, Range)	
		HitPosition = NPCShotResult.HitPosition
		HitPart = NPCShotResult.HitPart
		MaterialName = NPCShotResult.MaterialName
		ShotLanded = DamageLogic(HitPart)
	end

	for OtherPlayer, HumanoidRootPart in Automatics.CachedPlayerRootParts do
		if OtherPlayer == Actor then continue end

		local Delta = HumanoidRootPart.Position - Origin
		if Delta:Dot(Delta) > EFFECT_DISTANCE_SQ then continue end

		WeaponEffects:FireClient(
			OtherPlayer,
			AK47,
			Actor,
			Automatics.getPackedVector(HitPosition),
			MaterialName,
			HitPart
		)
	end

	return ShotLanded
end

return Logic
