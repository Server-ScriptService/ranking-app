local ServerStorage = game:GetService("ServerStorage")
local AIModules = ServerStorage.Modules.AI

local Brain =  require(script.Brain)

local Bot = script.Parent
local Humanoid = Bot.Humanoid

local DespawnTime = Bot.Configuration.Despawn.Value

local Actions = {}

-- Populates the actions table with all the modules in the AIModules folder and initializes them
for _, ActionModule in AIModules:GetChildren() do
	if not ActionModule:IsA("ModuleScript") then continue end
	
	Actions[ActionModule.Name] = require(ActionModule)
	local Initialize = Actions[ActionModule.Name]["initialize"]

	if Initialize then
		Initialize(Bot)
	end
	
	-- Below initializes any helpers that this action module may have
	local ActionModuleChildren = ActionModule:GetChildren()
	if #ActionModuleChildren <= 0 then continue end

	for _, HelperModule in ActionModuleChildren do
		if not HelperModule:IsA("ModuleScript") then continue end
		
		local InitializeHelper = require(HelperModule).initialize
		if InitializeHelper then InitializeHelper(Bot) end
	end
end

Humanoid.Died:Once(function()
	task.wait(DespawnTime)
	Bot:Destroy()
end)

while task.wait(0.3) do
	local ActionName = Brain.getBestAction()
	local Action = Actions[ActionName]
	if not Action then continue end

	Action.execute(Bot)
end
