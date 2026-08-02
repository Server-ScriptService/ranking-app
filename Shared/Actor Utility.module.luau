local ActorUtility = {}

local Players = game:GetService("Players")

function ActorUtility.indexNationFromObject(Object: Instance)
	local Current = Object

	for _ = 1, 12 do
		if not Current then return end
		
		local TeamValue = Current:FindFirstChild("Team")
		if TeamValue then
			return TeamValue.Value
		end

		local Config = Current:FindFirstChild("Configuration")
		local ConfigTeam = Config and Config:FindFirstChild("Nation")
		if ConfigTeam then
			return ConfigTeam.Value
		end

		local Player = Players:GetPlayerFromCharacter(Current)
		if Player then
			return Player.Team
		end

		Current = Current.Parent
	end
	
	return
end

return ActorUtility
