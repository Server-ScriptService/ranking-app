local Effects = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Modules = ReplicatedStorage.Modules

local Automatics = require(Modules.Automatics)
local WeaponEffects = require(Modules["Weapon Effects"])

local Player = Players.LocalPlayer

local Camera = workspace.CurrentCamera

local Weapon = script.Parent
local Ammo = Weapon:WaitForChild("Ammo")
local Recoil = Weapon:WaitForChild("Recoil")

local PendingShots = 0

local GUNSHOT_SFX = 85393757257555
local GUNSHOT_VOLUME = 0.3

Ammo.Changed:Connect(function()
	PendingShots = 0
end)

local RecoilRadians = {
	CFrame.Angles(math.rad(Recoil.Value), 0, 0),
	CFrame.Angles(math.rad(Recoil.Value), 0, 0),
	CFrame.Angles(math.rad(Recoil.Value), 0, 0)
}

local function PlayWeaponEffects(VFXAttachment, HitPosition: Vector3?, MaterialName, HitPart: BasePart?)
	if VFXAttachment then
		Automatics.createSound(VFXAttachment, tostring(GUNSHOT_SFX), nil, GUNSHOT_VOLUME)

		VFXAttachment.Flash:Emit(5)
		VFXAttachment.Smoke:Emit(10)
	end

	if HitPosition and HitPart then
		task.defer(function()
			WeaponEffects.playMaterialEffects(HitPosition, MaterialName, HitPart)
		end)
	end
end

-- Local weapon effects, including stuff like recoil
function Effects.playLocal(HitPosition: Vector3?, MaterialName, HitPart: BasePart?)
	local VisualWeapon = Camera:FindFirstChild(Weapon.Name)
	if not WeaponEffects.canShowWeaponEffects(VisualWeapon, Weapon) then return end

	local Body = VisualWeapon and VisualWeapon:FindFirstChild("Body")
	if not Body then return end
	
	local VFX = Body.VFX

	if Ammo.Value - PendingShots <= 0 then return end
	PendingShots += 1

	Player.PlayerScripts.Gameplay["Automatics FPS"]["Weapon Fired"]:Fire(VisualWeapon)

	WeaponEffects.applyRecoil(RecoilRadians)
	PlayWeaponEffects(VFX, HitPosition, MaterialName, HitPart)
end

-- Weapon effects for other players
function Effects.playWorld(VisualWeapon, HitPosition: Vector3?, MaterialName, HitPart: BasePart?)
	if not WeaponEffects.canShowWeaponEffects(VisualWeapon, Weapon) then return end

	local Body = VisualWeapon:FindFirstChild("Body")
	if not Body then return end

	PlayWeaponEffects(Body:FindFirstChild("VFX"), HitPosition, MaterialName, HitPart)
end

return Effects
