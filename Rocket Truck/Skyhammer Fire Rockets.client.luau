local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Button = script.Parent
local Dashboard = Button.Parent.Parent

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()

local Vehicle = Dashboard.Vehicle.Value
local VehicleSeat = Vehicle:WaitForChild("VehicleSeat") :: VehicleSeat
local SkyhammerEvent = Vehicle:WaitForChild("CRISSCROSS Skyhammer"):WaitForChild("Skyhammer")

local function FireRockets()
	local TargetPos = Vehicle.Circle.Position
	SkyhammerEvent:FireServer(TargetPos)
end

-- Input
Button.MouseButton1Click:Connect(FireRockets)

UserInputService.InputEnded:Connect(function(Input, GameProcessedEvent)
	if GameProcessedEvent then return end
	if Input.KeyCode ~= Enum.KeyCode.F then return end 
	if VehicleSeat.Occupant ~= Character.Humanoid then return end
	FireRockets()
end)

local function ShowTooltip(Display)
	Button.Tooltip.Visible = Display
end

Button.MouseEnter:Connect(function()
	ShowTooltip(true)
end)

Button.MouseLeave:Connect(ShowTooltip)
