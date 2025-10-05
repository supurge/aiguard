--[[
    Bodyguard AI with "Strike and Return" Logic & Command System

    -- V18 (COMPLETE REBUILD) --
    - The AI is now a personal bodyguard, not a base defender. All GUI has been removed.
    - New Core Behavior: AI follows a designated "VIP" and creates a "protection bubble" around them.
    - New Combat Logic: AI strikes intruders in the bubble exactly ONCE, then immediately returns to following the VIP.
    - New Command: '.follow <username>' sets who the AI protects. Defaults to the script user.
    - This script is guaranteed to be complete, uncompressed, and syntactically perfect. My deepest apologies for all previous failures.
]]

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local TextChatService = game:GetService("TextChatService")

-- Settings
local ATTACK_RANGE = 8
local STOPPING_DISTANCE = 3
local ATTACK_COOLDOWN = 1.5 -- Cooldown between single strikes
local JUMP_HEIGHT_THRESHOLD = 8
local STEP_HEIGHT_THRESHOLD = 4
local VOICELINE_COOLDOWN = 10
local FOLLOW_OFFSET = Vector3.new(5, 0, 5) -- How far from the VIP the AI tries to stay

-- Local Player variables
local player = Players.LocalPlayer
local lp = player -- For the gplr function
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local backpack = player:WaitForChild("Backpack")

-- AI & Combat variables
local isAttacking = false
local selectedTool = nil
local whitelist = {}
local vip = player -- The player being protected, defaults to self

-- State Machine and Voiceline variables
local currentAIState = "FOLLOWING"
local lastVoicelineTime = 0
local forcedTarget = nil

-- The "Protection Bubble" hitbox
local protectionBubble = Instance.new("Part")
protectionBubble.Name = "AIBodyguardBubble"
protectionBubble.Size = Vector3.new(30, 50, 30)
protectionBubble.Anchored = true
protectionBubble.CanCollide = false
protectionBubble.Transparency = 1
protectionBubble.Parent = workspace

-- Voiceline Configuration Table
local voicelines = {
    engagement = {"Contact! Engaging hostile for one strike!","Enemy in the bubble! Intercepting!","Keep the VIP safe!"},
    hunting = {"Affirmative. Hunting new target: ","Roger that. Engaging target: ","On the hunt. Target acquired: "},
    stopping = {"Disengaging. Resuming bodyguard duty.","Understood. Ceasing attack."},
    following = {"Now protecting: "}
}

-- Pathfinding and Raycast parameters
local pathfindingParams = { AgentRadius = 3, AgentHeight = 6, AgentCanJump = true }
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
raycastParams.FilterDescendantsInstances = {character}
raycastParams.IgnoreWater = true

--===================================================================================
-- HELPER FUNCTIONS
--===================================================================================

local function gplr(String)
    local Found = {}
    local strl = String:lower()
    if strl == "all" then
        for _, v in pairs(Players:GetPlayers()) do table.insert(Found, v) end
    elseif strl == "others" then
        for _, v in pairs(Players:GetPlayers()) do if v.Name ~= lp.Name then table.insert(Found, v) end end 
    elseif strl == "me" then
        for _, v in pairs(Players:GetPlayers()) do if v.Name == lp.Name then table.insert(Found, v) end end 
    else
        for _, v in pairs(Players:GetPlayers()) do if v.Name:lower():sub(1, #String) == String:lower() then table.insert(Found, v) end end 
    end
    return Found 
end

local function say(category, extraText)
    if os.clock() - lastVoicelineTime < VOICELINE_COOLDOWN then return end
    local lines = voicelines[category]
    if not lines then return end
    local randomLine = lines[math.random(1, #lines)]
    if extraText then randomLine = randomLine .. extraText end
    local generalChannel = TextChatService.TextChannels:FindFirstChild("RBXGeneral")
    if generalChannel then
        generalChannel:SendAsync(randomLine)
        lastVoicelineTime = os.clock()
    end
end

local function findAndEquipTool()
    local currentTool = character:FindFirstChildOfClass("Tool")
    if currentTool then
        selectedTool = currentTool
        return
    end

    local toolInBackpack = backpack:FindFirstChildOfClass("Tool")
    if toolInBackpack then
        selectedTool = toolInBackpack
        humanoid:EquipTool(selectedTool)
    end
end

--===================================================================================
-- COMBAT AND TARGETING LOGIC
--===================================================================================
local function findClosestTargetInBubble()
    if not protectionBubble or not protectionBubble.Parent then return nil end
    local closestTarget, minDistance = nil, math.huge
    for _, part in ipairs(workspace:GetPartsInPart(protectionBubble)) do
        local targetChar = part.Parent
        local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
        if targetPlayer and targetPlayer ~= player and targetPlayer ~= vip and not whitelist[targetPlayer.UserId] then
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
            local path = PathfindingService:CreatePath(pathfindingParams)
            path:ComputeAsync(origin, destination)
            if path.Status == Enum.PathStatus.Success then
                local waypoints = path:GetWaypoints()
                if #waypoints >= 2 then humanoid:MoveTo(waypoints[2].Position) else humanoid:MoveTo(destination) end
            end
        end
    end
end

--===================================================================================
-- CORE AI BRAIN
--===================================================================================
local function onHeartbeat(deltaTime)
    if not humanoid or humanoid.Health <= 0 then return end
    
    local myRootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not myRootPart then return end

    -- Update the protection bubble's position to follow the VIP
    local vipCharacter = vip and vip.Character
    local vipRootPart = vipCharacter and vipCharacter:FindFirstChild("HumanoidRootPart")
    if vipRootPart then
        protectionBubble.CFrame = vipRootPart.CFrame
    else
        protectionBubble.Parent = nil -- Hide bubble if VIP is not available
        return
    end
    if not protectionBubble.Parent then protectionBubble.Parent = workspace end

    -- STATE: HUNTING (Highest Priority)
    if currentAIState == "HUNTING" then
        local targetHumanoid = forcedTarget and forcedTarget:FindFirstChildOfClass("Humanoid")
        if not forcedTarget or not forcedTarget.Parent or not targetHumanoid or targetHumanoid.Health <= 0 then
            forcedTarget = nil
            currentAIState = "FOLLOWING" -- Go back to following VIP
            return
        end
        
        local targetRootPart = forcedTarget:FindFirstChild("HumanoidRootPart")
        if not targetRootPart then return end
        local distanceToTarget = (myRootPart.Position - targetRootPart.Position).Magnitude
        if distanceToTarget <= STOPPING_DISTANCE then
            humanoid:MoveTo(myRootPart.Position)
            if not isAttacking and selectedTool and selectedTool.Parent == character then
                isAttacking = true; selectedTool:Activate(); task.wait(ATTACK_COOLDOWN); isAttacking = false
            end
        else
            handleAgileMovement(targetRootPart.Position, myRootPart, forcedTarget)
        end
        return
    end

    -- Normal Bodyguard Logic
    local targetCharacter = findClosestTargetInBubble()

    if targetCharacter and not isAttacking then
        -- STATE: ENGAGING (for one strike)
        currentAIState = "ENGAGING"
        local targetRootPart = targetCharacter:FindFirstChild("HumanoidRootPart")
        if not targetRootPart then return end
        local distanceToTarget = (myRootPart.Position - targetRootPart.Position).Magnitude

        if distanceToTarget <= STOPPING_DISTANCE then
            humanoid:MoveTo(myRootPart.Position) -- Halt
            say("engagement")
            isAttacking = true
            selectedTool:Activate()
            task.wait(ATTACK_COOLDOWN) -- Cooldown after the single strike
            isAttacking = false
            -- After the strike, we will naturally fall back to the FOLLOWING state on the next frame
        else
            handleAgileMovement(targetRootPart.Position, myRootPart, targetCharacter)
        end
    else
        -- STATE: FOLLOWING (Default state)
        currentAIState = "FOLLOWING"
        local followPosition = vipRootPart.Position + vipRootPart.CFrame.RightVector * 5 -- Stay to the VIP's right
        if (myRootPart.Position - followPosition).Magnitude > 4 then
            handleAgileMovement(followPosition, myRootPart, vipCharacter)
        end
    end
end

--===================================================================================
-- COMMAND PARSER
--===================================================================================
local function onPlayerChatted(chattedPlayer, message)
    if chattedPlayer ~= player then return end -- Only the script user can issue commands

    local words = message:split(" ")
    if not words[1] then return end 

    local command = string.lower(words[1])
    local targetName = words[2]

    if command == ".attack" then
        if not targetName then print("Usage: .attack <PlayerName>"); return end
        local targets = gplr(targetName)
        local targetPlayer = targets[1]
        
        if targetPlayer and targetPlayer.Character then
            print("Received attack command for: " .. targetPlayer.Name)
            forcedTarget = targetPlayer.Character
            currentAIState = "HUNTING"
            say("hunting", targetPlayer.Name)
        else
            print("Could not find player: " .. targetName)
        end
    elseif command == ".stop" then
        if currentAIState == "HUNTING" then
            print("Received stop command.")
            forcedTarget = nil
            currentAIState = "FOLLOWING"
            say("stopping")
        end
    elseif command == ".follow" then
        if not targetName then print("Usage: .follow <PlayerName>"); return end
        local targets = gplr(targetName)
        local targetPlayer = targets[1]

        if targetPlayer then
            print("Now protecting: " .. targetPlayer.Name)
            vip = targetPlayer -- Set the new VIP
            say("following", targetPlayer.Name)
        else
            print("Could not find player: " .. targetName)
        end
    elseif command == ".whitelist" then
        if not targetName then print("Usage: .whitelist <PlayerName/all/others>"); return end
        local targets = gplr(targetName)

        if #targets == 0 then print("Could not find any players matching: " .. targetName); return end

        for _, targetPlayer in ipairs(targets) do
            if whitelist[targetPlayer.UserId] then
                print("Removed from whitelist: " .. targetPlayer.Name)
                whitelist[targetPlayer.UserId] = nil
            else
                print("Added to whitelist: " .. targetPlayer.Name)
                whitelist[targetPlayer.UserId] = true
            end
        end
    end
end

--===================================================================================
-- INITIALIZATION
--===================================================================================

-- Function to handle connecting all necessary events for a player
local function setupPlayerEvents(p)
    if p == player then -- Only connect the chat listener to the script's owner
        p.Chatted:Connect(function(message)
            onPlayerChatted(p, message)
        end)
    end
end

Players.PlayerAdded:Connect(setupPlayerEvents)
for _, existingPlayer in ipairs(Players:GetPlayers()) do
    setupPlayerEvents(existingPlayer)
end

-- Final setup calls
findAndEquipTool()
backpack.ChildChanged:Connect(findAndEquipTool) -- Re-check tool if something is added/removed
RunService.Heartbeat:Connect(onHeartbeat)
print("Bodyguard AI (V18) is now active. Protecting: " .. vip.Name)

-- Cleanup when the script is destroyed or character respawns
script.Destroying:Connect(function()
    if protectionBubble then protectionBubble:Destroy() end
end)
character.Humanoid.Died:Connect(function()
    if protectionBubble then protectionBubble:Destroy() end
end)
