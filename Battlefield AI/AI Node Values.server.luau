local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Teams = game:GetService("Teams")

local AINodes = workspace["AI Nodes"]

local Modules = ReplicatedStorage:WaitForChild("Modules")

local ScanRegion = require(Modules:WaitForChild("Scan Region"))
local ActorUtility = require(Modules:WaitForChild("Actor Utility"))

local Nations = Teams:GetChildren()

-- Updates the amount of soldiers near the node. Bots use this
local function InitializeNode(Node: BasePart)
	while task.wait(1.5) do
		for _, Nation in Nations do
			Node:SetAttribute(Nation.Name, 0)
		end
		
		local Actors = ScanRegion.countActorsNearCFrame(Node.CFrame)
		
		for _, Actor in Actors do
			local Nation = ActorUtility.indexNationFromObject(Actor)
			if not Nation then continue end
			
			Node:SetAttribute(Nation.Name, (Node:GetAttribute(Nation.Name) or 0) + 1)
		end
	end
end

for _, Node in AINodes:GetChildren() do
	task.spawn(InitializeNode, Node)
end

AINodes.ChildAdded:Connect(function(Node: BasePart)
	InitializeNode(Node)
end)
