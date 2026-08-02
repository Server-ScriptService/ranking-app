local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local WeaponEffectsEvent = ReplicatedStorage.Network.Events["Weapon Effects"]

WeaponEffectsEvent.OnClientEvent:Connect(function(Weapon, Shooter, HitPosition: Vector3?, MaterialName, HitPart: BasePart?)
	local IsShooterPlayer = Players:GetPlayerFromCharacter(Shooter)
	local Character = IsShooterPlayer and IsShooterPlayer.Character or Shooter
	if not Character then return end
	
	local EffectsModule = Weapon and Weapon:FindFirstChild("Effects")
	if not EffectsModule then return end	
	
	require(EffectsModule).playWorld(Weapon, HitPosition, MaterialName, HitPart)
end)
