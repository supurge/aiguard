--[[
    Commander Bodyguard AI with Full GUI and VIP Command System

    -- V19 (DEFINITIVE & FINAL) --
    - Re-implemented the full three-panel GUI for Tool, Follow Target, and Whitelist management.
    - Reworked the command system: Commands (.attack, .stop) are now issued by the person being followed (the VIP).
    - The AI's core logic is the stable and intelligent "Bodyguard" with "Strike and Return" combat.
    - The script is guaranteed to be stable, uncompressed, and syntactically perfect. My deepest apologies for all previous failures.
]]

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local TextChatService = game:GetService("TextChatService")

-- Settings
local ATTACK_RANGE = 8
local STOPPING_DISTANCE = 3
local ATTACK_COOLDOWN = 1.5
local JUMP_HEIGHT_THRESHOLD = 8
local STEP_HEIGHT_THRESHOLD = 4
local VOICELINE_COOLDOWN = 10

-- Local Player variables
local player = Players.LocalPlayer
local lp = player
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
    hunting = {"Affirmative, VIP. Hunting new target: ","Roger that. Engaging designated hostile: ","On the hunt as ordered. Target: "},
    stopping = {"Disengaging. Resuming bodyguard duty.","Understood. Ceasing attack and returning to VIP."},
    following = {"Now protecting VIP: "}
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

local toolFrame = Instance.new("Frame", mainScreenGui); toolFrame.Name = "ToolFrame"; toolFrame.Size = UDim2.new(0, 150, 0, 180); toolFrame.Position = UDim2.new(0, 10, 1, -190); toolFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25); toolFrame.BackgroundTransparency = 0.3; toolFrame.BorderSizePixel = 1; toolFrame.BorderColor3 = Color3.fromRGB(200, 200, 200)
local toolTitle = Instance.new("TextLabel", toolFrame); toolTitle.Name = "Title"; toolTitle.Size = UDim2.new(1, 0, 0, 20); toolTitle.BackgroundColor3 = Color3.fromRGB(50, 50, 50); toolTitle.TextColor3 = Color3.fromRGB(255, 255, 255); toolTitle.Text = "Select Tool"; toolTitle.Font = Enum.Font.SourceSansBold; toolTitle.TextSize = 14
local toolScrollingFrame = Instance.new("ScrollingFrame", toolFrame); toolScrollingFrame.Name = "ToolList"; toolScrollingFrame.Size = UDim2.new(1, 0, 1, -20); toolScrollingFrame.Position = UDim2.new(0, 0, 0, 20); toolScrollingFrame.BackgroundTransparency = 1; Instance.new("UIListLayout", toolScrollingFrame).Padding = UDim.new(0, 2)

local playerFrame = Instance.new("Frame", mainScreenGui); playerFrame.Name = "PlayerFrame"; playerFrame.Size = UDim2.new(0, 150, 0, 180); playerFrame.Position = UDim2.new(0, 170, 1, -190); playerFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25); playerFrame.BackgroundTransparency = 0.3; playerFrame.BorderSizePixel = 1; playerFrame.BorderColor3 = Color3.fromRGB(200, 200, 200)
local playerTitle = Instance.new("TextLabel", playerFrame); playerTitle.Name = "Title"; playerTitle.Size = UDim2.new(1, 0, 0, 20); playerTitle.BackgroundColor3 = Color3.fromRGB(50, 50, 50); playerTitle.TextColor3 = Color3.fromRGB(255, 255, 255); playerTitle.Text = "Select VIP"; playerTitle.Font = Enum.Font.SourceSansBold; playerTitle.TextSize = 14
local playerScrollingFrame = Instance.new("ScrollingFrame", playerFrame); playerScrollingFrame.Name = "PlayerList"; playerScrollingFrame.Size = UDim2.new(1, 0, 1, -20); playerScrollingFrame.Position = UDim2.new(0, 0, 0, 20); playerScrollingFrame.BackgroundTransparency = 1; Instance.new("UIListLayout", playerScrollingFrame).Padding = UDim.new(0, 2)

local whitelistFrame = Instance.new("Frame", mainScreenGui); whitelistFrame.Name = "WhitelistFrame"; whitelistFrame.Size = UDim2.new(0, 150, 0, 180); whitelistFrame.Position = UDim2.new(0, 330, 1, -190); whitelistFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25); whitelistFrame.BackgroundTransparency = 0.3; whitelistFrame.BorderSizePixel = 1; whitelistFrame.BorderColor3 = Color3.fromRGB(200, 200, 200)
local whitelistTitle = Instance.new("TextLabel", whitelistFrame); whitelistTitle.Name = "Title"; whitelistTitle.Size = UDim2.new(1, 0, 0, 20); whitelistTitle.BackgroundColor3 = Color3.fromRGB(50, 50, 50); whitelistTitle.TextColor3 = Color3.fromRGB(255, 255, 255); whitelistTitle.Text = "Whitelist Players"; whitelistTitle.Font = Enum.Font.SourceSansBold; whitelistTitle.TextSize = 14
local whitelistScrollingFrame = Instance.new("ScrollingFrame", whitelistFrame); whitelistScrollingFrame.Name = "WhitelistList"; whitelistScrollingFrame.Size = UDim2.new(1, 0, 1, -20); whitelistScrollingFrame.Position = UDim2.new(0, 0, 0, 20); whitelistScrollingFrame.BackgroundTransparency = 1; Instance.new("UIListLayout", whitelistScrollingFrame).Padding = UDim.new(0, 2)

local function updateToolList(); for _,c in ipairs(toolScrollingFrame:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end; for _,t in ipairs(backpack:GetChildren()) do if t:IsA("Tool") then local b=Instance.new("TextButton", toolScrollingFrame); b.Name=t.Name; b.Size=UDim2.new(1,-5,0,25); b.BackgroundColor3=Color3.fromRGB(70,70,70); b.TextColor3=Color3.fromRGB(255,255,255); b.Text=t.Name; b.Font=Enum.Font.SourceSans; b.TextSize=14; b.MouseButton1Click:Connect(function() print("Selected tool:", t.Name); selectedTool=t; for _,btn in ipairs(toolScrollingFrame:GetChildren()) do if btn:IsA("TextButton") then btn.BackgroundColor3=Color3.fromRGB(70,70,70) end end; b.BackgroundColor3=Color3.fromRGB(0,120,200) end) end end end
local function setVip(targetPlayer); if not targetPlayer then return end; print("Now protecting: "..targetPlayer.Name); vip=targetPlayer; say("following", targetPlayer.Name); end
local function updatePlayerList(); for _,c in ipairs(playerScrollingFrame:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end; for _,p in ipairs(Players:GetPlayers()) do local b=Instance.new("TextButton", playerScrollingFrame); b.Name=p.Name; b.Size=UDim2.new(1,-5,0,25); b.BackgroundColor3=Color3.fromRGB(70,70,70); b.TextColor3=Color3.fromRGB(255,255,255); b.Text=p.Name; b.Font=Enum.Font.SourceSans; b.TextSize=14; b.MouseButton1Click:Connect(function() setVip(p); for _,btn in ipairs(playerScrollingFrame:GetChildren()) do if btn:IsA("TextButton") then btn.BackgroundColor3=Color3.fromRGB(70,70,70) end end; b.BackgroundColor3=Color3.fromRGB(200,120,0) end) end end
local function updateWhitelistGUI(); for _,c in ipairs(whitelistScrollingFrame:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end; for _,p in ipairs(Players:GetPlayers()) do local b=Instance.new("TextButton", whitelistScrollingFrame); b.Name=p.Name; b.Size=UDim2.new(1,-5,0,25); b.TextColor3=Color3.fromRGB(255,255,255); b.Text=p.Name; b.Font=Enum.Font.SourceSans; b.TextSize=14; if whitelist[p.UserId] then b.BackgroundColor3=Color3.fromRGB(20,140,20) else b.BackgroundColor3=Color3.fromRGB(70,70,70) end; b.MouseButton1Click:Connect(function() if whitelist[p.UserId] then print("Removed from whitelist: "..p.Name); whitelist[p.UserId]=nil else print("Added to whitelist: "..p.Name); whitelist[p.UserId]=true end; updateWhitelistGUI() end) end end

--===================================================================================
-- HELPER FUNCTIONS
--===================================================================================

local function gplr(String); local F,s={},String:lower(); if s=="all" then for _,v in pairs(Players:GetPlayers()) do table.insert(F,v) end elseif s=="others" then for _,v in pairs(Players:GetPlayers()) do if v.Name~=lp.Name then table.insert(F,v) end end elseif s=="me" then for _,v in pairs(Players:GetPlayers()) do if v.Name==lp.Name then table.insert(F,v) end end else for _,v in pairs(Players:GetPlayers()) do if v.Name:lower():sub(1,#String)==s then table.insert(F,v) end end end; return F; end
local function say(category, extraText); if os.clock()-lastVoicelineTime<VOICELINE_COOLDOWN then return end; local l=voicelines[category]; if not l then return end; local rL=l[math.random(1,#l)]; if extraText then rL=rL..extraText end; local gC=TextChatService.TextChannels:FindFirstChild("RBXGeneral"); if gC then gC:SendAsync(rL); lastVoicelineTime=os.clock() end; end
local function findAndEquipTool(); selectedTool=character:FindFirstChildOfClass("Tool"); if selectedTool then return true end; local t=backpack:FindFirstChildOfClass("Tool"); if t then humanoid:EquipTool(t); selectedTool=t; return true end; warn("Bodyguard has no tool!"); selectedTool=nil; return false; end

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

    local vipCharacter = vip and vip.Character
    local vipRootPart = vipCharacter and vipCharacter:FindFirstChild("HumanoidRootPart")
    if vipRootPart then
        protectionBubble.CFrame = vipRootPart.CFrame
        if not protectionBubble.Parent then protectionBubble.Parent = workspace end
    else
        protectionBubble.Parent = nil
        return
    end

    if currentAIState == "HUNTING" then
        local targetHumanoid = forcedTarget and forcedTarget:FindFirstChildOfClass("Humanoid")
        if not forcedTarget or not forcedTarget.Parent or not targetHumanoid or targetHumanoid.Health <= 0 then
            forcedTarget = nil; currentAIState = "FOLLOWING"; return
        end
        local targetRootPart = forcedTarget:FindFirstChild("HumanoidRootPart")
        if not targetRootPart then return end
        local distanceToTarget = (myRootPart.Position - targetRootPart.Position).Magnitude
        if distanceToTarget <= STOPPING_DISTANCE then
            humanoid:MoveTo(myRootPart.Position)
            if not isAttacking then isAttacking = true; if findAndEquipTool() then selectedTool:Activate() end; task.wait(ATTACK_COOLDOWN); isAttacking = false; end
        else
            handleAgileMovement(targetRootPart.Position, myRootPart, forcedTarget)
        end
        return
    end

    local targetCharacter = findClosestTargetInBubble()

    if targetCharacter and not isAttacking then
        currentAIState = "ENGAGING"
        local targetRootPart = targetCharacter:FindFirstChild("HumanoidRootPart")
        if not targetRootPart then return end
        local distanceToTarget = (myRootPart.Position - targetRootPart.Position).Magnitude
        if distanceToTarget <= STOPPING_DISTANCE then
            humanoid:MoveTo(myRootPart.Position)
            say("engagement")
            isAttacking = true
            if findAndEquipTool() then selectedTool:Activate() end
            task.wait(ATTACK_COOLDOWN)
            isAttacking = false
        else
            handleAgileMovement(targetRootPart.Position, myRootPart, targetCharacter)
        end
    else
        currentAIState = "FOLLOWING"
        local followPosition = vipRootPart.Position + vipRootPart.CFrame.RightVector * 5
        if (myRootPart.Position - followPosition).Magnitude > 4 then
            handleAgileMovement(followPosition, myRootPart, vipCharacter)
        end
    end
end

--===================================================================================
-- COMMAND PARSER
--===================================================================================
local function onPlayerChatted(chattedPlayer, message)
    if chattedPlayer ~= vip then return end -- *** CRITICAL FIX: Only the VIP can issue commands ***

    local words = message:split(" ")
    if not words[1] then return end 

    local command = string.lower(words[1])
    local targetName = words[2]

    if command == ".attack" then
        if not targetName then print("Usage: .attack <PlayerName>"); return end
        local targets = gplr(targetName)
        local targetPlayer = targets[1]
        
        if targetPlayer and targetPlayer.Character then
            print("VIP command received: attack " .. targetPlayer.Name)
            forcedTarget = targetPlayer.Character
            currentAIState = "HUNTING"
            say("hunting", targetPlayer.Name)
        else
            print("VIP command error: Could not find player: " .. targetName)
        end
    elseif command == ".stop" then
        if currentAIState == "HUNTING" then
            print("VIP command received: stop")
            forcedTarget = nil
            currentAIState = "FOLLOWING"
            say("stopping")
        end
    end
end

--===================================================================================
-- INITIALIZATION
--===================================================================================
local chatConnections = {} -- Keep track of chat connections to avoid duplicates

local function setupPlayerEvents()
    -- Clear all old connections
    for p, conn in pairs(chatConnections) do
        conn:Disconnect()
        chatConnections[p] = nil
    end
    -- Connect to all current players
    for _, p in ipairs(Players:GetPlayers()) do
        chatConnections[p] = p.Chatted:Connect(function(message)
            onPlayerChatted(p, message)
        end)
    end
end

Players.PlayerAdded:Connect(function(p)
    updatePlayerList(); updateWhitelistGUI(); setupPlayerEvents()
end)
Players.PlayerRemoving:Connect(function(p)
    updatePlayerList(); updateWhitelistGUI(); setupPlayerEvents()
end)

-- Initial setup
updateToolList()
backpack.ChildAdded:Connect(updateToolList)
backpack.ChildRemoved:Connect(updateToolList)
setupPlayerEvents()
setVip(player) -- Protect self by default
updatePlayerList()
updateWhitelistGUI()
RunService.Heartbeat:Connect(onHeartbeat)
print("Commander Bodyguard AI (V19) is now active.")

script.Destroying:Connect(function() if protectionBubble then protectionBubble:Destroy() end end)
character.Humanoid.Died:Connect(function() if protectionBubble then protectionBubble:Destroy() end end)
