--[[
Aggressive Guard AI with Command System & Pathfinding State Machine

-- V18 (Robust Pathfinding State) --
- This script now features a dedicated "PATHFINDING" state.
- The instant the AI detects it is stuck, it computes a full path to the target and follows it.
- It will intelligently abandon the path if the target moves too far, ensuring it doesn't follow a stale route.
- This creates a much more reliable and persistent navigation system when obstacles are present.

]]

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local TextChatService = game:GetService("TextChatService")

-- Settings
local ATTACK_RANGE = 8
local STOPPING_DISTANCE = 3
local ATTACK_COOLDOWN = 1
local JUMP_HEIGHT_THRESHOLD = 7
local STEP_HEIGHT_THRESHOLD = 4
local VOICELINE_COOLDOWN = 10

-- Local Player variables
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local backpack = player:WaitForChild("Backpack")

-- AI & Combat variables
local isAttacking = false
local selectedTool = nil
local guardedHitbox = nil
local baseOwner = nil
local whitelist = {}

-- State Machine and Voiceline variables
local currentAIState = "IDLE"
local lastVoicelineTime = 0
local forcedTarget = nil

-- NEW: Stuck detection and Pathfinding variables
local lastPosition = Vector3.new()
local stuckTimer = 0
local STUCK_TIME_THRESHOLD = 1.5 -- Reduced time to trigger pathfinding faster
local activePath = nil
local nextWaypointIndex = 1

-- Voiceline Configuration Table
local voicelines = {
	engagement = {
		"Intruder detected! Neutralizing threat.",
		"Hostile contact! Moving to engage.",
		"You're not supposed to be here!",
		"Get out of this base!",
		"Protecting the perimeter!"
	},
	returning = {
		"Zone clear. Returning to my post.",
		"Threat eliminated. Resuming guard duty.",
		"All clear. Heading back to the center."
	},
	traveling_end = {
		"Arrived at the new guard post. Securing the area.",
		"Guard duty initiated at new location.",
		"This base is now under my protection."
	},
	hunting = {
		"Affirmative. Hunting new target: ",
		"Roger that. Engaging target: ",
		"On the hunt. Target acquired: "
	},
	stopping = {
		"Disengaging. Returning to normal operations.",
		"Understood. Ceasing attack.",
		"Stopping attack command. Resuming guard duty."
	}
}

-- Pathfinding and Raycast parameters
local pathfindingParams = { AgentRadius = 3, AgentHeight = 6, AgentCanJump = true }
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
raycastParams.FilterDescendantsInstances = {character}
raycastParams.IgnoreWater = true

-- ===================================================================================
-- GUI CREATION & LOGIC
-- ===================================================================================

local mainScreenGui = Instance.new("ScreenGui", player:WaitForChild("PlayerGui"))
mainScreenGui.Name = "AiControlGui"
mainScreenGui.ResetOnSpawn = false

local toolFrame = Instance.new("Frame", mainScreenGui)
toolFrame.Name = "ToolFrame"
toolFrame.Size = UDim2.new(0, 150, 0, 180)
toolFrame.Position = UDim2.new(0, 10, 1, -190)
toolFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
toolFrame.BackgroundTransparency = 0.3
toolFrame.BorderSizePixel = 1
toolFrame.BorderColor3 = Color3.fromRGB(200, 200, 200)

local toolTitle = Instance.new("TextLabel", toolFrame)
toolTitle.Name = "Title"
toolTitle.Size = UDim2.new(1, 0, 0, 20)
toolTitle.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
toolTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
toolTitle.Text = "Select Tool"
toolTitle.Font = Enum.Font.SourceSansBold
toolTitle.TextSize = 14

local toolScrollingFrame = Instance.new("ScrollingFrame", toolFrame)
toolScrollingFrame.Name = "ToolList"
toolScrollingFrame.Size = UDim2.new(1, 0, 1, -20)
toolScrollingFrame.Position = UDim2.new(0, 0, 0, 20)
toolScrollingFrame.BackgroundTransparency = 1
Instance.new("UIListLayout", toolScrollingFrame).Padding = UDim.new(0, 2)

local playerFrame = Instance.new("Frame", mainScreenGui)
playerFrame.Name = "PlayerFrame"
playerFrame.Size = UDim2.new(0, 150, 0, 180)
playerFrame.Position = UDim2.new(0, 170, 1, -190)
playerFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
playerFrame.BackgroundTransparency = 0.3
playerFrame.BorderSizePixel = 1
playerFrame.BorderColor3 = Color3.fromRGB(200, 200, 200)

local playerTitle = Instance.new("TextLabel", playerFrame)
playerTitle.Name = "Title"
playerTitle.Size = UDim2.new(1, 0, 0, 20)
playerTitle.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
playerTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
playerTitle.Text = "Select Base"
playerTitle.Font = Enum.Font.SourceSansBold
playerTitle.TextSize = 14

local playerScrollingFrame = Instance.new("ScrollingFrame", playerFrame)
playerScrollingFrame.Name = "PlayerList"
playerScrollingFrame.Size = UDim2.new(1, 0, 1, -20)
playerScrollingFrame.Position = UDim2.new(0, 0, 0, 20)
playerScrollingFrame.BackgroundTransparency = 1
Instance.new("UIListLayout", playerScrollingFrame).Padding = UDim.new(0, 2)

local whitelistFrame = Instance.new("Frame", mainScreenGui)
whitelistFrame.Name = "WhitelistFrame"
whitelistFrame.Size = UDim2.new(0, 150, 0, 180)
whitelistFrame.Position = UDim2.new(0, 330, 1, -190)
whitelistFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
whitelistFrame.BackgroundTransparency = 0.3
whitelistFrame.BorderSizePixel = 1
whitelistFrame.BorderColor3 = Color3.fromRGB(200, 200, 200)

local whitelistTitle = Instance.new("TextLabel", whitelistFrame)
whitelistTitle.Name = "Title"
whitelistTitle.Size = UDim2.new(1, 0, 0, 20)
whitelistTitle.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
whitelistTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
whitelistTitle.Text = "Whitelist Players"
whitelistTitle.Font = Enum.Font.SourceSansBold
whitelistTitle.TextSize = 14

local whitelistScrollingFrame = Instance.new("ScrollingFrame", whitelistFrame)
whitelistScrollingFrame.Name = "WhitelistList"
whitelistScrollingFrame.Size = UDim2.new(1, 0, 1, -20)
whitelistScrollingFrame.Position = UDim2.new(0, 0, 0, 20)
whitelistScrollingFrame.BackgroundTransparency = 1
Instance.new("UIListLayout", whitelistScrollingFrame).Padding = UDim.new(0, 2)

local function updateToolList()
	for _, child in ipairs(toolScrollingFrame:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
	for _, tool in ipairs(backpack:GetChildren()) do
		if tool:IsA("Tool") then
			local btn = Instance.new("TextButton", toolScrollingFrame)
			btn.Name = tool.Name
			btn.Size = UDim2.new(1, -5, 0, 25)
			btn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			btn.Text = tool.Name
			btn.Font = Enum.Font.SourceSans
			btn.TextSize = 14
			btn.MouseButton1Click:Connect(function()
				print("Selected tool:", tool.Name)
				selectedTool = tool
				if humanoid then humanoid:EquipTool(tool) end
				for _, otherBtn in ipairs(toolScrollingFrame:GetChildren()) do
					if otherBtn:IsA("TextButton") then otherBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70) end
				end
				btn.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
			end)
		end
	end
end

local function setGuardTarget(targetPlayer)
	if not targetPlayer then return end
	print("Switching guard target to " .. targetPlayer.Name .. "'s base.")
	baseOwner = targetPlayer
	local baseValue = targetPlayer:FindFirstChild("Configuration", true) and targetPlayer.Configuration:FindFirstChild("Base", true)
	if not baseValue or not baseValue.Value then
		warn("Could not find Configuration or Base Value for player: " .. targetPlayer.Name)
		return
	end
	local targetBaseName = baseValue.Value.Name
	local basesFolder = workspace:WaitForChild("Bases")
	local targetUserbase = basesFolder:FindFirstChild(targetBaseName)
	if targetUserbase then
		local targetHitbox = targetUserbase:FindFirstChild("CollectZoneHitbox")
		if targetHitbox then
			guardedHitbox = targetHitbox
			guardedHitbox.Transparency = 0.7
			guardedHitbox.Size = Vector3.new(50.51011, 50, 80.1099)
			guardedHitbox.CanCollide = false
			guardedHitbox.Anchored = true
			print("Successfully targeted " .. targetPlayer.Name .. "'s base. Traveling to new post.")
			currentAIState = "TRAVELING"
			humanoid:MoveTo(guardedHitbox.Position)
		else
			warn("Hitbox not found in " .. targetBaseName)
		end
	else
		warn("Base model not found: " .. targetBaseName)
	end
end

local function updatePlayerList()
	for _, child in ipairs(playerScrollingFrame:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
	for _, p in ipairs(Players:GetPlayers()) do
		local btn = Instance.new("TextButton", playerScrollingFrame)
		btn.Name = p.Name
		btn.Size = UDim2.new(1, -5, 0, 25)
		btn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Text = p.Name
		btn.Font = Enum.Font.SourceSans
		btn.TextSize = 14
		btn.MouseButton1Click:Connect(function()
			setGuardTarget(p)
			for _, otherBtn in ipairs(playerScrollingFrame:GetChildren()) do
				if otherBtn:IsA("TextButton") then otherBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70) end
			end
			btn.BackgroundColor3 = Color3.fromRGB(200, 120, 0)
		end)
	end
end

local function updateWhitelistGUI()
	for _, child in ipairs(whitelistScrollingFrame:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
	for _, p in ipairs(Players:GetPlayers()) do
		local btn = Instance.new("TextButton", whitelistScrollingFrame)
		btn.Name = p.Name
		btn.Size = UDim2.new(1, -5, 0, 25)
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Text = p.Name
		btn.Font = Enum.Font.SourceSans
		btn.TextSize = 14
		if whitelist[p.UserId] then
			btn.BackgroundColor3 = Color3.fromRGB(20, 140, 20)
		else
			btn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		end
		btn.MouseButton1Click:Connect(function()
			if whitelist[p.UserId] then
				print("Removed " .. p.Name .. " from whitelist.")
				whitelist[p.UserId] = nil
			else
				print("Added " .. p.Name .. " to whitelist.")
				whitelist[p.UserId] = true
			end
			updateWhitelistGUI()
		end)
	end
end

--===================================================================================
-- VOICELINE FUNCTION
--===================================================================================
local function say(category, extraText)
	if os.clock() - lastVoicelineTime < VOICELINE_COOLDOWN then return end
	
	local lines = voicelines[category]
	if not lines then return end
	
	local randomLine = lines[math.random(1, #lines)]
	
	if extraText then
		randomLine = randomLine .. extraText
	end
	
	local generalChannel = TextChatService.TextChannels:FindFirstChild("RBXGeneral")
	if generalChannel then
		generalChannel:SendAsync(randomLine)
		lastVoicelineTime = os.clock()
	end
	
end

--===================================================================================
-- COMBAT AND TARGETING LOGIC
--===================================================================================
local function findClosestTargetInZone()
	if not guardedHitbox then return nil end
	local closestTarget, minDistance = nil, math.huge
	for _, part in ipairs(workspace:GetPartsInPart(guardedHitbox)) do
		local targetChar = part.Parent
		local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
		if targetPlayer and targetPlayer ~= player and targetPlayer ~= baseOwner and not whitelist[targetPlayer.UserId] then
			local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")
			if targetHumanoid and targetHumanoid.Health > 0 then
				local dist = (character.HumanoidRootPart.Position - targetChar.HumanoidRootPart.Position).Magnitude
				if dist < minDistance then minDistance = dist; closestTarget = targetChar end
			end
		end
	end
	return closestTarget
end

--===================================================================================
-- AGILE MOVEMENT LOGIC
--===================================================================================
-- MODIFIED: This function is now only for direct movement, pathfinding is handled by the main AI brain.
local function handleAgileMovement(destination, myRootPart, targetCharacter)
	local origin = myRootPart.Position
	local direction = destination - origin
	
	local ray = workspace:Raycast(origin, direction.Unit * (direction.Magnitude + 5), raycastParams)
	
	if not ray or (targetCharacter and ray.Instance:IsDescendantOf(targetCharacter)) then
		humanoid:MoveTo(destination)
	else
		local obstacleHeight = ray.Position.Y - (origin.Y - myRootPart.Size.Y / 2)
		if obstacleHeight < STEP_HEIGHT_THRESHOLD then
			humanoid:MoveTo(destination)
		elseif obstacleHeight <= JUMP_HEIGHT_THRESHOLD then
			humanoid.Jump = true
			humanoid:MoveTo(destination)
		else
			-- If the obstacle is too high for agile movement, this is another trigger to use pathfinding.
			-- This is a fallback in case the 'stuck' detection fails.
			print("Obstacle is too high, attempting to pathfind...")
			currentAIState = "PATHFINDING_REQUEST" -- A temporary state to trigger pathfinding
		end
	end
end

--===================================================================================
-- CORE AI BRAIN
--===================================================================================
local function onHeartbeat(deltaTime)
	if not humanoid or humanoid.Health <= 0 or not guardedHitbox then return end
	
	local myRootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not myRootPart then return end
	
	-- MODIFIED: Stuck detection logic
	local isStuck = false
	local isChasing = (currentAIState == "CHASING" or currentAIState == "HUNTING")
	if isChasing then
		if (myRootPart.Position - lastPosition).Magnitude < 0.5 * deltaTime * 60 then -- Scaled by framerate
			stuckTimer = stuckTimer + deltaTime
		else
			stuckTimer = 0
		end
		
		if stuckTimer > STUCK_TIME_THRESHOLD then
			isStuck = true
			stuckTimer = 0
		end
	else
		stuckTimer = 0
	end
	lastPosition = myRootPart.Position
	
	
	-- Handle Traveling State
	if currentAIState == "TRAVELING" then
		if (myRootPart.Position - guardedHitbox.Position).Magnitude < 10 then
			say("traveling_end")
			currentAIState = "IDLE"
		end
		return
	end

	-- NEW: State to handle pathfinding requests
	local targetForPathfinding
	if currentAIState == "PATHFINDING_REQUEST" then
		targetForPathfinding = forcedTarget or findClosestTargetInZone()
		if targetForPathfinding then
			isStuck = true -- Force the 'isStuck' logic to run
			currentAIState = "CHASING" -- Revert to a state that can use pathfinding
		else
			currentAIState = "RETURNING" -- No target, just return
		end
	end

	-- NEW: Dedicated Pathfinding State
	if currentAIState == "PATHFINDING" then
		local targetCharacter = forcedTarget or findClosestTargetInZone()
		if not targetCharacter or not activePath then
			activePath = nil; currentAIState = "RETURNING"; return
		end
		
		local targetRootPart = targetCharacter:FindFirstChild("HumanoidRootPart")
		if not targetRootPart then
			activePath = nil; currentAIState = "RETURNING"; return
		end
		
		-- Check if the target has moved too far from the path's destination. If so, the path is stale.
		local pathDestination = activePath[#activePath].Position
		if (targetRootPart.Position - pathDestination).Magnitude > 20 then
			print("Target moved, recalculating path.")
			activePath = nil
			currentAIState = "CHASING" -- Revert to chasing to get a new path or attack
			return
		end

		-- Move to the current waypoint and check if we've arrived
		local waypointPosition = activePath[nextWaypointIndex].Position
		if (myRootPart.Position - waypointPosition).Magnitude < 4 then
			nextWaypointIndex = nextWaypointIndex + 1
			if nextWaypointIndex > #activePath then
				print("Path complete. Resuming normal chase.")
				activePath = nil
				currentAIState = "CHASING"
				return
			end
		end
		-- Move to the next waypoint
		humanoid:MoveTo(activePath[nextWaypointIndex].Position)
		return -- IMPORTANT: End the function here to prevent other logic from running
	end
	
	-- Handle Hunting State
	if currentAIState == "HUNTING" then
		local targetHumanoid = forcedTarget and forcedTarget:FindFirstChildOfClass("Humanoid")
		if not forcedTarget or not forcedTarget.Parent or not targetHumanoid or targetHumanoid.Health <= 0 then
			say("returning"); forcedTarget = nil; activePath = nil; currentAIState = "RETURNING"; return
		end
		
		local targetRootPart = forcedTarget:FindFirstChild("HumanoidRootPart")
		if not targetRootPart then return end
		
		local distanceToTarget = (myRootPart.Position - targetRootPart.Position).Magnitude
		if distanceToTarget <= ATTACK_RANGE then
			currentAIState = "CHASING" -- Transition to normal chase/attack logic
		else
			if isStuck then
				local path = PathfindingService:CreatePath(pathfindingParams)
				path:ComputeAsync(myRootPart.Position, targetRootPart.Position)
				if path.Status == Enum.PathStatus.Success and #path:GetWaypoints() > 1 then
					print("AI is stuck! Following a calculated path.")
					activePath = path:GetWaypoints(); nextWaypointIndex = 2; currentAIState = "PATHFINDING"
					humanoid:MoveTo(activePath[nextWaypointIndex].Position)
				end
			else
				humanoid:MoveTo(targetRootPart.Position)
			end
		end
		return
	end
	
	-- Main Combat Logic (Idle, Chasing, Attacking)
	local targetCharacter = findClosestTargetInZone()
	if not targetCharacter and currentAIState ~= "RETURNING" then
		targetCharacter = targetForPathfinding
	end

	if targetCharacter then
		local targetRootPart = targetCharacter:FindFirstChild("HumanoidRootPart")
		if not targetRootPart then return end
		
		local distanceToTarget = (myRootPart.Position - targetRootPart.Position).Magnitude
		
		if distanceToTarget <= STOPPING_DISTANCE then
			currentAIState = "ATTACKING"
			humanoid:MoveTo(myRootPart.Position)
			if not isAttacking and selectedTool and selectedTool.Parent == character then
				isAttacking = true; selectedTool:Activate(); task.wait(ATTACK_COOLDOWN); isAttacking = false
			end
		else
			if currentAIState ~= "CHASING" then say("engagement") end
			currentAIState = "CHASING"
			
			-- MODIFIED: Pathfinding trigger logic
			if isStuck then
				local path = PathfindingService:CreatePath(pathfindingParams)
				path:ComputeAsync(myRootPart.Position, targetRootPart.Position)
				if path.Status == Enum.PathStatus.Success and #path:GetWaypoints() > 1 then
					print("AI is stuck! Following a calculated path.")
					activePath = path:GetWaypoints(); nextWaypointIndex = 2; currentAIState = "PATHFINDING"
					humanoid:MoveTo(activePath[nextWaypointIndex].Position)
				else
					handleAgileMovement(targetRootPart.Position, myRootPart, targetCharacter)
				end
			else
				handleAgileMovement(targetRootPart.Position, myRootPart, targetCharacter)
			end
		end
	else
		activePath = nil -- Clear any path if the target is lost
		if (myRootPart.Position - guardedHitbox.Position).Magnitude > 5 then
			if currentAIState ~= "RETURNING" then say("returning") end
			currentAIState = "RETURNING"
			humanoid:MoveTo(guardedHitbox.Position)
		else
			if currentAIState ~= "IDLE" then currentAIState = "IDLE" end
		end
	end
end


--===================================================================================
-- HELPER FUNCTION FOR ROBUST PLAYER SEARCH
--===================================================================================
local function findPlayerByName(name)
	local foundPlayer = nil
	local lowerName = name:lower()
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name:lower():match("^" .. lowerName) then
			foundPlayer = p
			break
		end
	end
	return foundPlayer
end

--===================================================================================
-- COMMAND PARSER
--===================================================================================
local function onPlayerChatted(chattedPlayer, message)
	if chattedPlayer ~= baseOwner then return end
	
	local words = message:split(" ")
	if not words[1] then return end
	
	local command = string.lower(words[1])
	
	if command == ".attack" then
		local targetName = words[2]
		if not targetName then
			print("Command usage: .attack [PlayerName]")
			return
		end
		
		local targetPlayer = findPlayerByName(targetName)
		
		if targetPlayer and targetPlayer.Character then
			if targetPlayer == player then
				print("Command error: Cannot target self.")
				return
			end
			if targetPlayer == baseOwner then
				print("Command error: Cannot target the base owner.")
				return
			end
			
			print("Received attack command for: " .. targetPlayer.Name)
			activePath = nil -- Clear any previous path
			forcedTarget = targetPlayer.Character
			currentAIState = "HUNTING"
			say("hunting", targetPlayer.Name)
		else
			print("Command error: Could not find player starting with '" .. targetName .. "'.")
		end
	elseif command == ".stop" then
		if currentAIState == "HUNTING" or currentAIState == "PATHFINDING" then
			print("Received stop command.")
			activePath = nil -- Clear path on stop
			forcedTarget = nil
			currentAIState = "RETURNING"
			say("stopping")
		else
			print("Command info: Not currently in an attack state.")
		end
	end
	
end

--===================================================================================
-- INITIALIZATION
--===================================================================================
local function onPlayerAdded(newPlayer)
	updatePlayerList()
	updateWhitelistGUI()
	
	newPlayer.Chatted:Connect(function(message)
		onPlayerChatted(newPlayer, message)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, existingPlayer in ipairs(Players:GetPlayers()) do
	onPlayerAdded(existingPlayer)
end

Players.PlayerRemoving:Connect(function()
	updatePlayerList()
	updateWhitelistGUI()
end)

setGuardTarget(player)
updateToolList()
backpack.ChildAdded:Connect(updateToolList)
backpack.ChildRemoved:Connect(updateToolList)

if guardedHitbox then
	RunService.Heartbeat:Connect(onHeartbeat)
	print("Commandable Guard AI (V18 - Robust Pathfinding) is now active.")
else
	warn("AI could not start because no initial guard hitbox was found.")
end
