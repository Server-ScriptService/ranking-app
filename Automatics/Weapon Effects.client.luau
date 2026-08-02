local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponEffectsEvent = ReplicatedStorage.Network.Events["Weapon Effects"]

WeaponEffectsEvent.OnClientEvent:Connect(function(Weapon, HitPosition: Vector3?, MaterialName, HitPart: BasePart?)
	local EffectsModule = Weapon and Weapon:FindFirstChild("Effects")
	if not EffectsModule then return end

	require(EffectsModule).playWorld(Weapon, HitPosition, MaterialName, HitPart)
end)
