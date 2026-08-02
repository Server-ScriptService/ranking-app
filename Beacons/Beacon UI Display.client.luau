local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FadeInTweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FadeOutTweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local BeaconFrame = script.Parent
local Template = BeaconFrame.Template
Template.Visible = false

local SetupBeaconDisplay, SaturationNotified = {}, {}

local Notifications = require(ReplicatedStorage.Modules.Notifications)

local SATURATED_NOTIFY_COOLDOWN = 8

-- Clones a new Frame for the given Beacon and updates it accordingly
local function InitializeBeaconDisplay(Beacon: Model)
	if SetupBeaconDisplay[Beacon] then return end
	
	SetupBeaconDisplay[Beacon] = true
	Beacon.Destroying:Once(function()
		SetupBeaconDisplay[Beacon] = nil
	end)

	local Configuration = Beacon:WaitForChild("Configuration") :: Configuration
	local CapturingNation, Nation = Configuration:WaitForChild("Capturing Nation") :: ObjectValue, Configuration:WaitForChild("Nation") :: ObjectValue
	
	-- UI
	local BeaconDisplayFrame = Template:Clone()
	local Gradient, Label = BeaconDisplayFrame.UIGradient, BeaconDisplayFrame.Label
	
	local SaturatedIndicator = BeaconDisplayFrame.Saturated	
	local SaturatedTooltip = SaturatedIndicator.Tooltip
	
	local BeaconLetter = Beacon.Name:sub(-1) -- Parses the beacons letter by getting the last letter of the beacon's name
	
	local SaturatedIndicatorTween
	local SaturatedIndicatorTweenEnd
	
	local IsAnimatingGradient = false
	
	BeaconDisplayFrame.Visible = true
	
	-- Updates the beacon display frame's UI color. The middle color will be the color of the capturing nation, or the nation color if there is no capturing nation.
	local function ShowNationColor()
		local CapturingNationVal
		local NationVal

		local CapturingNationColor
		local NationColor
		
		local function UpdateNationVariables()
			CapturingNationVal = CapturingNation.Value
			NationVal = Nation.Value

			CapturingNationColor = CapturingNationVal and CapturingNationVal.TeamColor.Color
			NationColor = NationVal and NationVal.TeamColor.Color or Color3.fromRGB(255, 255, 255)
		end
		
		UpdateNationVariables()
		
		Gradient.Rotation = 0
		Gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, NationColor),
			ColorSequenceKeypoint.new(0.5, CapturingNationColor or NationColor),
			ColorSequenceKeypoint.new(1, NationColor)
		})

		if not CapturingNationVal then
			IsAnimatingGradient = false
			return
		end
		
		if IsAnimatingGradient then return end
		IsAnimatingGradient = true

		-- UI animation when capturing
		task.spawn(function()
			local GradientDir = "Right"
			local BASE_KEYPOINT_INCREMENT_STEP = 0.02
			
			while CapturingNation.Value do
				UpdateNationVariables()
				local MiddleKeypoint = Gradient.Color.Keypoints[2].Time

				-- Direction bouncing (when it hits the right, go left, when it hits the left, go right)
				if MiddleKeypoint >= 1 and GradientDir == "Right" then GradientDir = "Left" end
				if MiddleKeypoint <= 0 and GradientDir == "Left" then GradientDir = "Right" end
				
				-- Positive = right, negative = left
				local IncrementStep = GradientDir == "Right" and BASE_KEYPOINT_INCREMENT_STEP or -BASE_KEYPOINT_INCREMENT_STEP

				Gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, NationColor),
					ColorSequenceKeypoint.new(math.clamp(MiddleKeypoint + IncrementStep, 0, 1), CapturingNationColor or NationColor),
					ColorSequenceKeypoint.new(1, NationColor)
				})

				task.wait(0.01)
			end
			
			IsAnimatingGradient = false
		end)
	end
	
	local function ShowSaturatedIndicator()
		local IsSaturated = Beacon:GetAttribute("Saturated")
		
		if SaturatedIndicatorTween then
			SaturatedIndicatorTween:Cancel()
			SaturatedIndicatorTween = nil
			
			SaturatedIndicatorTweenEnd:Disconnect()
			SaturatedIndicatorTweenEnd = nil
		end
		
		SaturatedIndicator.ImageTransparency = 1
		SaturatedIndicator.Visible = true
		
		SaturatedIndicatorTween = TweenService:Create(SaturatedIndicator, IsSaturated and FadeInTweenInfo or FadeOutTweenInfo, {
			ImageTransparency = IsSaturated and 0 or 1
		})
		SaturatedIndicatorTween:Play()
		
		SaturatedIndicatorTweenEnd = SaturatedIndicatorTween.Completed:Once(function()
			SaturatedIndicatorTween = nil
			SaturatedIndicatorTweenEnd = nil
		end)
		
		-- Saturation notifier
		if IsSaturated then
			local Now = os.clock()
			
			if Now - (SaturationNotified[Beacon] or 0) >= SATURATED_NOTIFY_COOLDOWN then
				SaturationNotified[Beacon] = Now
				Notifications.NotifyMe({
					BeaconLetter .. " is <font color='rgb(255, 255, 0)'>saturated</font>",
					Beacon.Name .. " is <font color='rgb(255, 0, 0)'>saturated</font>. Many soldiers are near this point."
				}, 6.5)	
			end
		else
			SaturatedTooltip.Visible = false
			SaturatedIndicator.Visible = false
		end
	end

	ShowNationColor()
	ShowSaturatedIndicator()
	
	Label.Text = BeaconLetter
	
	BeaconDisplayFrame.Name = Beacon.Name
	BeaconDisplayFrame.LayoutOrder = Beacon:GetAttribute("UIOrder") or 0
	BeaconDisplayFrame.Parent = BeaconFrame

	CapturingNation:GetPropertyChangedSignal("Value"):Connect(ShowNationColor)
	Nation:GetPropertyChangedSignal("Value"):Connect(ShowNationColor)
	Beacon:GetAttributeChangedSignal("Saturated"):Connect(ShowSaturatedIndicator)
	
	-- Tooltip display
	SaturatedIndicator.MouseEnter:Connect(function()
		if not (SaturatedIndicator.Visible and Beacon:GetAttribute("Saturated")) then return end
		SaturatedTooltip.Visible = true
	end)
	
	SaturatedIndicator.MouseLeave:Connect(function()
		SaturatedTooltip.Visible = false
	end)
end

local function StartDisplayIfBeacon(Beacon: Model)
	if not (Beacon.Name:find("Beacon") and Beacon:GetAttribute("Contested") ~= nil) then return end
	InitializeBeaconDisplay(Beacon)
end

for _, MaybeBeacon in CollectionService:GetTagged("Deployment Location") do
	StartDisplayIfBeacon(MaybeBeacon)
end

CollectionService:GetInstanceAddedSignal("Deployment Location"):Connect(function(MaybeBeacon: Model)
	StartDisplayIfBeacon(MaybeBeacon)
end)
