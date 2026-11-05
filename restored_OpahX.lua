-- OpahX / OpahHelper
-- Roblox puzzle helper: ESP, passcode tracking and instant prompts.

while not game:IsLoaded() do
    task.wait()
end

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local LocalPlayer = Players.LocalPlayer

local Airflow = assert(loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau"
)))()

local settings = {
    EspKey = false,
    EspKeypad = false,
    EspNote = false,
    EspPadlock = false,
    EspFlipFlop = false,
    EspWardNear = false,
    EspOpah = false,
    InstantPrompt = false,
    AutoFarm = false,
    AutoExecute = true,
    SkipCutscene = false,
    UpdateDelay = 1,
    UiKeybind = "LeftAlt",
    FarmKeybind = "None",
}

local KINDS = {
    Key = { flag = "EspKey", color = "Blue", name = "ItemESP" },
    Keypad = { flag = "EspKeypad", color = "Green", name = "ItemESP" },
    Note = { flag = "EspNote", color = "Yellow", name = "EvidenceESP" },
    Padlock = { flag = "EspPadlock", color = "Red", name = "ItemESP" },
    FlipFlop = { flag = "EspFlipFlop", color = "Purple", name = "ItemESP", limit = 3 },
    Wardrobe = { flag = "EspWardNear", color = "Blue", name = "ItemESP", limit = 1 },
    Opah = { flag = "EspOpah", color = "Red", name = "GhostESP" },
}

local connections = {}
local espEntries = {}
local COLORS
local espGui
local closed = false
local promptHooksReady = false
local pendingScan = {}
local passcode
local noteText
local heldKeys

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    connections[#connections + 1] = connection
    return connection
end

local function guiParent()
    if gethui then
        return gethui()
    end
    return CoreGui
end

local function ensureEspGui()
    if espGui then
        return
    end
    espGui = Instance.new("ScreenGui")
    espGui.Name = "OpahX_ESP"
    espGui.ResetOnSpawn = false
    espGui.IgnoreGuiInset = true
    espGui.DisplayOrder = 998
    espGui.Parent = guiParent()

    COLORS = {
        Red = Color3.fromRGB(255, 70, 70),
        Blue = Color3.fromRGB(70, 140, 255),
        Green = Color3.fromRGB(70, 255, 90),
        Yellow = Color3.fromRGB(255, 235, 70),
        Purple = Color3.fromRGB(190, 100, 255),
    }
end

local function partOf(instance)
    if instance:IsA("BasePart") then
        return instance
    end
    if instance:IsA("Model") then
        return instance.PrimaryPart
            or instance:FindFirstChild("HumanoidRootPart")
            or instance:FindFirstChildWhichIsA("BasePart", true)
    end
    return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function playerPosition()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return root and root.Position
end

local function distanceText(distance)
    return string.format("%.1f", distance) .. " studs"
end

local function displayValue(value)
    if type(value) == "table" then
        local parts = {}
        for _, entry in ipairs(value) do
            parts[#parts + 1] = tostring(entry)
        end
        return table.concat(parts, ", ")
    end
    return tostring(value)
end

local function classifyName(name)
    local lower = string.lower(name)
    if lower:find("keypad", 1, true) then
        return "Keypad"
    end
    if lower:find("passcode", 1, true) or lower:find("note", 1, true) then
        return "Note"
    end
    if lower:find("padlock", 1, true) or lower:find("lock", 1, true) then
        return "Padlock"
    end
    if lower:find("flip", 1, true) then
        return "FlipFlop"
    end
    if lower:find("wardrobe", 1, true) then
        return "Wardrobe"
    end
    if lower:find("opah", 1, true) then
        return "Opah"
    end
    if lower:find("key", 1, true) then
        return "Key"
    end
    return nil
end

local function classify(instance)
    local itemType = instance:GetAttribute("ItemType")
    if type(itemType) == "string" then
        local lower = string.lower(itemType)
        if lower == "key" then
            return "Key"
        end
        if lower == "passcode" or lower == "note" then
            return "Note"
        end
    end
    return classifyName(instance.Name)
end

local function colorNameOf(instance, kind)
    local keyColor = instance:GetAttribute("KeyColor")
    if type(keyColor) == "string" and COLORS[keyColor] then
        return keyColor
    end
    return KINDS[kind].color
end

local function noteCodeFrom(instance)
    local gui = instance:FindFirstChild("Paper", true)
    gui = gui and gui:FindFirstChild("Writing", true)
    local code = gui and gui:FindFirstChild("Code", true)
    return code and code.Text or nil
end

local function rememberNote(value)
    if type(value) ~= "string" then
        return
    end
    noteText = value
    local compact = value:gsub("%s+", "")
    if compact:match("^%d%d%d+$") then
        passcode = compact
        return
    end
    local digits = value:match("%d%d%d+")
    if digits and string.lower(value):find("code", 1, true) then
        passcode = digits
    end
end

local function createEntry(instance, kind)
    local definition = KINDS[kind]
    ensureEspGui()
    local colorName = colorNameOf(instance, kind)
    local color = COLORS[colorName]
    local adornee = partOf(instance)
    if not adornee then
        return
    end

    local outline = instance:IsA("Model") and instance or adornee

    local highlight = Instance.new("Highlight")
    highlight.Name = definition.name
    highlight.Adornee = outline
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = 1
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Enabled = false
    highlight.Parent = espGui

    local billboard = Instance.new("BillboardGui")
    billboard.Name = definition.name .. "Label"
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.fromOffset(180, 34)
    billboard.StudsOffset = Vector3.new(0, 2.4, 0)
    billboard.Adornee = adornee
    billboard.Enabled = false
    billboard.Parent = espGui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.TextColor3 = color
    label.TextStrokeTransparency = 0.35
    label.Text = kind
    label.Parent = billboard

    espEntries[instance] = {
        kind = kind,
        colorName = colorName,
        name = instance.Name,
        adornee = adornee,
        highlight = highlight,
        billboard = billboard,
        label = label,
        distance = math.huge,
    }
end

local function removeEntry(instance)
    local entry = espEntries[instance]
    if not entry then
        return
    end
    if entry.highlight then
        entry.highlight:Destroy()
    end
    if entry.billboard then
        entry.billboard:Destroy()
    end
    espEntries[instance] = nil
end

local function isPlayerPart(instance)
    local model = instance:FindFirstAncestorOfClass("Model")
    return model ~= nil and Players:GetPlayerFromCharacter(model) ~= nil
end

local function scan(instance)
    if closed or not instance or not instance.Parent then
        return
    end
    if instance:IsA("ProximityPrompt") then
        if settings.InstantPrompt then
            instance.HoldDuration = 0
        end
        return
    end
    local kind = classify(instance)
    if not kind then
        -- attributes can replicate a frame after the instance itself, so retry
        if instance:IsA("Model") or instance:IsA("BasePart") then
            local attempts = pendingScan[instance]
            if attempts == nil then
                attempts = 0
            end
            if attempts < 5 then
                pendingScan[instance] = attempts + 1
                task.delay(0.5, function()
                    pendingScan[instance] = nil
                    if instance.Parent then
                        scan(instance)
                    end
                end)
            else
                pendingScan[instance] = nil
            end
        end
        return
    end
    pendingScan[instance] = nil
    if not (instance:IsA("Model") or instance:IsA("BasePart")) then
        return
    end
    if espEntries[instance] then
        return
    end
    if isPlayerPart(instance) then
        return
    end
    if instance:IsA("BasePart") then
        local parent = instance.Parent
        if parent and parent:IsA("Model") and classify(parent) then
            return
        end
    end

    createEntry(instance, kind)

    if kind == "Note" then
        local text = instance:GetAttribute("Text") or instance:GetAttribute("Code")
        if type(text) ~= "string" then
            text = noteCodeFrom(instance)
        end
        if type(text) == "string" then
            rememberNote(text)
        end
    end
end

local function scanRemoved(instance)
    removeEntry(instance)
    for child in pairs(espEntries) do
        if child:IsDescendantOf(instance) then
            removeEntry(child)
        end
    end
end

local function labelFor(entry)
    local kind = entry.kind
    if kind == "Keypad" then
        return "Keypad [" .. (passcode or "?") .. "]"
    elseif kind == "Note" then
        return "Passcode Note [" .. (passcode or "?") .. "]"
    elseif kind == "Wardrobe" then
        return "Nearest Wardrobe [" .. distanceText(entry.distance) .. "]"
    elseif kind == "Opah" then
        return "OPAH [" .. distanceText(entry.distance) .. "]"
    elseif kind == "Padlock" then
        return "Padlock [" .. distanceText(entry.distance) .. "]"
    elseif kind == "FlipFlop" then
        return "Flip Flop [" .. distanceText(entry.distance) .. "]"
    elseif kind == "Key" and entry.colorName then
        return entry.colorName .. " Key [" .. distanceText(entry.distance) .. "]"
    end
    return entry.name .. " [" .. distanceText(entry.distance) .. "]"
end

local function applyVisibility()
    local grouped = {}
    for instance, entry in pairs(espEntries) do
        if not instance.Parent or not entry.adornee or not entry.adornee.Parent then
            removeEntry(instance)
        else
            local list = grouped[entry.kind]
            if not list then
                list = {}
                grouped[entry.kind] = list
            end
            list[#list + 1] = entry
        end
    end

    for kind, definition in pairs(KINDS) do
        local list = grouped[kind] or {}
        table.sort(list, function(a, b)
            return a.distance < b.distance
        end)
        local enabled = settings[definition.flag]
        for index, entry in ipairs(list) do
            local visible = enabled and (definition.limit == nil or index <= definition.limit)
            entry.highlight.Enabled = visible
            entry.billboard.Enabled = visible
        end
    end
end

local function updateEntries()
    if next(espEntries) == nil then
        return
    end
    local origin = playerPosition()
    for instance, entry in pairs(espEntries) do
        if not instance.Parent or not entry.adornee or not entry.adornee.Parent then
            removeEntry(instance)
        else
            if origin then
                entry.distance = (entry.adornee.Position - origin).Magnitude
            end
            entry.label.Text = labelFor(entry)
        end
    end
    applyVisibility()
end

local function countKind(kind)
    local total = 0
    for instance, entry in pairs(espEntries) do
        if instance.Parent and entry.kind == kind then
            total = total + 1
        end
    end
    return total
end

local function nearestOf(kind)
    local origin = playerPosition()
    local best, bestDistance
    for instance, entry in pairs(espEntries) do
        if instance.Parent and entry.kind == kind then
            local distance = origin and (entry.adornee.Position - origin).Magnitude or entry.distance
            if not bestDistance or distance < bestDistance then
                best, bestDistance = instance, distance
            end
        end
    end
    return best, bestDistance
end

local function enableInstantPrompt()
    for _, instance in ipairs(Workspace:GetDescendants()) do
        if instance:IsA("ProximityPrompt") then
            instance.HoldDuration = 0
        end
    end

    if promptHooksReady then
        return
    end
    promptHooksReady = true

    connect(ProximityPromptService.PromptShown, function(prompt)
        if settings.InstantPrompt then
            prompt.HoldDuration = 0
        end
    end)

    connect(ProximityPromptService.PromptButtonHoldBegan, function(prompt)
        if settings.InstantPrompt then
            prompt.HoldDuration = 0
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Auto farm: open the drawer hiding a key, grab it, then pop its padlock
-- ---------------------------------------------------------------------------

local FARM_RANGE = 9
local FARM_TIMEOUT = 5
local FARM_SETTLE = 0.3
local FARM_ATTEMPTS = 3
local ESCAPE_TIMEOUT = 45

local farmState = {
    running = false,
    status = "Idle",
    opened = 0,
    total = 0,
}

local function setFarmStatus(text)
    farmState.status = text
end

local function codeFromNote(note)
    for _, label in ipairs(note:GetDescendants()) do
        if label:IsA("TextLabel") and label.Name == "Code" then
            local digits = label.Text:gsub("%D", "")
            if #digits > 0 then
                return digits
            end
        end
    end
    return note:GetAttribute("Code") or note:GetAttribute("Passcode")
end


local farmToggle

local function characterRoot()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function farmAlive()
    return farmState.running and not closed
end

local function waitFor(predicate, timeout)
    local deadline = os.clock() + timeout
    while farmAlive() do
        if predicate() then
            return true
        end
        if os.clock() >= deadline then
            return false
        end
        task.wait(0.05)
    end
    return false
end

local function teleportTo(position)
    local root = characterRoot()
    if not root then
        return false
    end
    root.AssemblyLinearVelocity = Vector3.zero
    root.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0))
    return true
end

local function inRangeOf(position)
    local root = characterRoot()
    return root ~= nil and (root.Position - position).Magnitude < FARM_RANGE
end

local function settleAt(position)
    -- the server only accepts an interaction from the position it last saw, so
    -- give the teleport a moment to replicate before firing anything
    if not teleportTo(position) then
        return false
    end
    task.wait(FARM_SETTLE)
    return inRangeOf(position)
end

local function fireUntil(position, fire, predicate, timeout)
    for _ = 1, FARM_ATTEMPTS do
        if not farmAlive() then
            return false
        end
        if settleAt(position) then
            pcall(fire)
            if waitFor(predicate, timeout) then
                return true
            end
        end
        task.wait(0.2)
    end
    return false
end

local function puzzlePromptOf(instance)
    return instance:FindFirstChild("PuzzlePrompt", true)
        or instance:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function keyModelOf(color)
    local items = Workspace:FindFirstChild("PuzzleItems")
    if not items then
        return nil
    end
    for _, item in ipairs(items:GetChildren()) do
        if item:GetAttribute("ItemType") == "Key" and item:GetAttribute("KeyColor") == color then
            return item
        end
    end
    return nil
end

local function padlockOpened(lock)
    -- the server drops the click detector range to zero once the padlock falls off
    local click = lock:FindFirstChild("PuzzleClick")
    return click == nil or click.MaxActivationDistance <= 0
end

local function nearestDrawerPrompt(position)
    local chests = Workspace:FindFirstChild("PuzzleChests")
    if not chests then
        return nil
    end
    -- a drawer that still awaits opening has its prompt enabled; a drawer left
    -- open has it disabled, so keep it only as a fallback
    local best, bestDistance
    local fallback, fallbackDistance
    for _, prompt in ipairs(chests:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            local part = prompt.Parent and prompt.Parent.Parent
            if part and part:IsA("BasePart") then
                local distance = (part.Position - position).Magnitude
                if prompt.Enabled then
                    if not bestDistance or distance < bestDistance then
                        best, bestDistance = prompt, distance
                    end
                elseif not fallbackDistance or distance < fallbackDistance then
                    fallback, fallbackDistance = prompt, distance
                end
            end
        end
    end
    return best or fallback
end

local function collectKey(color)
    local key = keyModelOf(color)
    if not key then
        return "No " .. color .. " key left"
    end
    local keyPart = key:FindFirstChild("Root") or partOf(key)
    local prompt = puzzlePromptOf(key)
    if not (keyPart and prompt) then
        return color .. " key is not pickable"
    end

    if not prompt.Enabled then
        local drawer = nearestDrawerPrompt(keyPart.Position)
        local drawerPart = drawer and drawer.Parent and drawer.Parent.Parent
        if not (drawerPart and drawerPart:IsA("BasePart")) then
            return "No drawer holds the " .. color .. " key"
        end
        local opened = fireUntil(drawerPart.Position, function()
            -- the drawer prompt toggles, so never fire one that is already open
            if not prompt.Enabled then
                fireproximityprompt(drawer)
            end
        end, function()
            return prompt.Enabled
        end, FARM_TIMEOUT)
        if not opened then
            return "The " .. color .. " drawer stayed shut"
        end
    end

    local picked = fireUntil(keyPart.Position, function()
        fireproximityprompt(prompt)
    end, function()
        return LocalPlayer:GetAttribute("HeldKeyColor") == color
    end, FARM_TIMEOUT)
    if not picked then
        return "Could not pick up the " .. color .. " key"
    end
    return nil
end

local function openPadlock(lock)
    local padlock = lock:FindFirstChild("Padlock")
    local target = padlock and partOf(padlock) or partOf(lock)
    local click = lock:FindFirstChild("PuzzleClick")
    if not (target and click) then
        return false
    end

    return fireUntil(target.Position, function()
        fireclickdetector(click, 1)
    end, function()
        return padlockOpened(lock)
    end, FARM_TIMEOUT)
end

local function noteModel()
    local items = Workspace:FindFirstChild("PuzzleItems")
    if not items then
        return nil
    end
    for _, item in ipairs(items:GetChildren()) do
        if item:GetAttribute("ItemType") == "Passcode" then
            return item
        end
    end
    return nil
end

local function keypadOpened()
    if Workspace:GetAttribute("PuzzleCompleted") == true then
        return true
    end
    local door = Workspace:FindFirstChild("FrontDoor")
    local keypad = door and door:FindFirstChild("Keypad")
    local click = keypad and keypad:FindFirstChild("PuzzleClick")
    return click ~= nil and click.MaxActivationDistance <= 0
end

local function collectNote()
    local note = noteModel()
    if not note then
        return nil, "No passcode note left"
    end
    local notePart = note:FindFirstChild("Root") or partOf(note)
    local prompt = puzzlePromptOf(note)
    if not (notePart and prompt) then
        return nil, "The passcode note is not pickable"
    end

    local code = codeFromNote(note)

    if not prompt.Enabled then
        local drawer = nearestDrawerPrompt(notePart.Position)
        local drawerPart = drawer and drawer.Parent and drawer.Parent.Parent
        if not (drawerPart and drawerPart:IsA("BasePart")) then
            return nil, "No drawer holds the passcode note"
        end
        local opened = fireUntil(drawerPart.Position, function()
            if not prompt.Enabled then
                fireproximityprompt(drawer)
            end
        end, function()
            return prompt.Enabled
        end, FARM_TIMEOUT)
        if not opened then
            return nil, "The passcode note drawer stayed shut"
        end
        code = codeFromNote(note) or code
    end

    if type(code) ~= "string" or #code == 0 then
        return nil, "The passcode note has no code"
    end

    -- the note is destroyed once it is in hand, so read the code before grabbing it
    fireUntil(notePart.Position, function()
        fireproximityprompt(prompt)
    end, function()
        return LocalPlayer:GetAttribute("HeldItem") ~= nil
    end, FARM_TIMEOUT)

    return code
end

local function openKeypad()
    local door = Workspace:FindFirstChild("FrontDoor")
    local keypad = door and door:FindFirstChild("Keypad")
    local plate = keypad and keypad:FindFirstChild("Plate", true)
    local prompt = keypad and puzzlePromptOf(keypad)
    if not (plate and prompt) then
        return "Keypad not found"
    end

    local code = collectNote()
    if not code then
        return "No door code found"
    end

    local submit = ReplicatedStorage:FindFirstChild("PuzzleShared")
    submit = submit and submit:FindFirstChild("Remotes")
    submit = submit and submit:FindFirstChild("SubmitPasscode")
    if not submit then
        return "SubmitPasscode remote missing"
    end

    setFarmStatus("Entering code " .. code)
    local entered = fireUntil(plate.Position, function()
        fireproximityprompt(prompt)
    end, function()
        local gui = LocalPlayer:FindFirstChild("PlayerGui")
        gui = gui and gui:FindFirstChild("PuzzleGui")
        gui = gui and gui:FindFirstChild("Keypad")
        return gui ~= nil and gui.Visible
    end, FARM_TIMEOUT)
    if not entered then
        return "The keypad would not open"
    end

    local ok, result = pcall(function()
        return submit:InvokeServer(code)
    end)
    if not ok then
        return "Code " .. code .. " was rejected"
    end
    if result == false then
        return "Code " .. code .. " was rejected"
    end
    return nil
end

local function cutsceneRemote()
    local shared = ReplicatedStorage:FindFirstChild("Cutscenes")
    return shared and shared:FindFirstChild("Remote")
end

local function escapeOnBike()
    local marker = Workspace:FindFirstChild("Cutscenes")
    marker = marker and marker:FindFirstChild("Markers")
    marker = marker and marker:FindFirstChild("BikePark")
    if not marker then
        return "No bike marker found"
    end

    local function onMarker()
        local root = characterRoot()
        return root ~= nil and (root.Position - marker.Position).Magnitude <= 4
    end

    -- The bike carries a cloned rider, not a real seat, so boarding is invisible
    -- on the humanoid. The outro sequence is: opening (camera scriptable) -> run
    -- phase (camera handed back, boarding happens) -> drive-off (camera taken
    -- again). Only the hand-back proves the run phase has begun, so wait for that
    -- before trusting any camera reading, and take the server's OutroBoarded
    -- message as the stronger signal when it arrives.
    local remote = cutsceneRemote()
    local boarded = false
    local listener
    if remote then
        listener = remote.OnClientEvent:Connect(function(name, payload)
            if name == "OutroBoarded" and type(payload) == "table" and payload.userId == LocalPlayer.UserId then
                boarded = true
            end
        end)
    end

    setFarmStatus("Running for the bike")
    local tookCamera = false
    local runPhase = false
    local deadline = os.clock() + ESCAPE_TIMEOUT
    while farmAlive() and not boarded and os.clock() < deadline do
        if Workspace.CurrentCamera.CameraType == Enum.CameraType.Scriptable then
            if runPhase then
                boarded = true
                break
            end
            tookCamera = true
        elseif tookCamera then
            runPhase = true
        end

        -- hold the marker: the game boards whoever is standing on it when the
        -- run phase opens, and the cutscene may have moved us before that
        if not onMarker() then
            teleportTo(marker.Position)
        end
        task.wait(0.2)
    end

    if listener then
        listener:Disconnect()
    end
    if not boarded then
        return "Stood at the bike, but the escape never started"
    end
    setFarmStatus("Escaping on the bike")
    return nil
end

local function runAutoFarm()
    local door = Workspace:FindFirstChild("FrontDoor")
    local folder = door and door:FindFirstChild("PuzzleLocks")
    if not folder then
        setFarmStatus("PuzzleLocks not found")
        return
    end

    local pending = {}
    local total = 0
    for _, lock in ipairs(folder:GetChildren()) do
        if lock:IsA("Model") then
            total = total + 1
            if not padlockOpened(lock) then
                pending[#pending + 1] = lock
            end
        end
    end

    farmState.total = total
    farmState.opened = total - #pending

    if #pending == 0 then
        setFarmStatus("All padlocks open")
    end

    for _, lock in ipairs(pending) do
        if not farmAlive() then
            return
        end
        local color = lock:GetAttribute("KeyColor")
        if type(color) ~= "string" then
            setFarmStatus("Skipped " .. lock.Name .. ", no KeyColor")
            return
        end

        if LocalPlayer:GetAttribute("HeldKeyColor") ~= color then
            setFarmStatus("Fetching the " .. color .. " key")
            local reason = collectKey(color)
            if reason then
                setFarmStatus(reason)
                return
            end
        end

        setFarmStatus("Opening " .. lock.Name)
        if not openPadlock(lock) then
            setFarmStatus("Could not open " .. lock.Name)
            return
        end
        farmState.opened = farmState.opened + 1
        task.wait(0.3)
    end

    setFarmStatus("All padlocks open")

    if farmAlive() and not keypadOpened() then
        setFarmStatus("Opening the keypad")
        local reason = openKeypad()
        if reason then
            setFarmStatus(reason)
            return
        end
        waitFor(keypadOpened, FARM_TIMEOUT)
    end

    if farmAlive() then
        setFarmStatus("Door open, running for the bike")
        local reason = escapeOnBike()
        if reason then
            setFarmStatus(reason)
            return
        end
    end
end

local function startAutoFarm()
    if farmState.running then
        return
    end
    farmState.running = true
    task.spawn(function()
        runAutoFarm()
        if farmState.running then
            farmState.running = false
            settings.AutoFarm = false
            if farmToggle then
                farmToggle:Set(false, true)
            end
        end
    end)
end

local function stopAutoFarm()
    if not farmState.running then
        return
    end
    farmState.running = false
    setFarmStatus("Stopped")
end

local function setAutoFarm(enabled, silent)
    settings.AutoFarm = enabled
    if farmToggle then
        farmToggle:Set(enabled, silent ~= false)
    end
    if enabled then
        startAutoFarm()
    else
        stopAutoFarm()
    end
end

-- ---------------------------------------------------------------------------
-- Auto execute: re-arm the script's own hooks once the game place is loaded
-- ---------------------------------------------------------------------------

local function inGamePlace()
    -- the lobby has neither of these; both only exist in the playable place
    return Workspace:FindFirstChild("FrontDoor") ~= nil
        and Workspace:FindFirstChild("PuzzleItems") ~= nil
end

local autoExecuteArmed = true

local function onEnterGamePlace()
    -- the lobby teleport swaps every instance the ESP was watching, so rescan
    pendingScan = {}
    for _, instance in ipairs(Workspace:GetDescendants()) do
        scan(instance)
    end
    if settings.InstantPrompt then
        enableInstantPrompt()
    end
    applyVisibility()
    setFarmStatus("Ready in game place")
end

local function watchForGamePlace()
    task.spawn(function()
        while not closed do
            if inGamePlace() then
                if autoExecuteArmed then
                    autoExecuteArmed = false
                    if settings.AutoExecute then
                        onEnterGamePlace()
                    end
                end
            else
                autoExecuteArmed = true
            end
            task.wait(1)
        end
    end)
end


-- ---------------------------------------------------------------------------
-- Auto skip cutscene: press the game's own skip vote as soon as it appears
-- ---------------------------------------------------------------------------

local function cutsceneSkipButton()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local gui = playerGui and playerGui:FindFirstChild("CutsceneGui")
    return gui and gui:FindFirstChild("SkipButton", true)
end

local function skipCutscene()
    local button = cutsceneSkipButton()
    if not (button and button.Visible) then
        return false
    end
    -- the game greys the button out once our vote is already registered
    if button.AutoButtonColor == false then
        return false
    end
    firesignal(button.Activated)
    return true
end

task.spawn(function()
    while not closed do
        if settings.SkipCutscene then
            pcall(skipCutscene)
        end
        task.wait(0.2)
    end
end)


task.spawn(function()
    for _, instance in ipairs(Workspace:GetDescendants()) do
        scan(instance)
    end
end)

connect(Workspace.DescendantAdded, function(instance)
    if instance:IsA("ProximityPrompt") then
        if settings.InstantPrompt then
            instance.HoldDuration = 0
        end
        return
    end
    scan(instance)
end)

connect(Workspace.DescendantRemoving, function(instance)
    if instance:IsA("ProximityPrompt") then
        return
    end
    scanRemoved(instance)
end)

task.spawn(function()
    while not closed do
        updateEntries()
        task.wait(0.5)
    end
end)

task.spawn(function()
    local shared = ReplicatedStorage:WaitForChild("PuzzleShared", 10)
    if not shared then
        return
    end
    local remotes = shared:WaitForChild("Remotes", 10)
    if not remotes then
        return
    end
    local remote = remotes:WaitForChild("PuzzleRemote", 10)
    if not remote then
        return
    end

    connect(remote.OnClientEvent, function(...)
        local args = { ... }
        for _, value in ipairs(args) do
            if type(value) == "table" then
                for key, entry in pairs(value) do
                    local lower = string.lower(tostring(key))
                    if lower:find("code", 1, true) or lower:find("pass", 1, true) then
                        local digits = tostring(entry):match("%d%d%d+")
                        if digits then
                            passcode = digits
                        end
                    elseif lower:find("note", 1, true) or lower:find("text", 1, true) then
                        rememberNote(tostring(entry))
                    end
                end
            elseif type(value) == "string" then
                local trimmed = value:match("^%s*(.-)%s*$")
                if trimmed:match("^%d%d%d+$") then
                    passcode = trimmed
                elseif string.lower(trimmed):find("code", 1, true) then
                    local digits = trimmed:match("%d%d%d+")
                    if digits then
                        passcode = digits
                    end
                elseif #trimmed > 3 then
                    rememberNote(trimmed)
                end
            end
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- Interface (Airflow UI)
-- ---------------------------------------------------------------------------

local noteParagraph

local TOOL_NAME = "Malam Sama Opah"

local function sanitizeFolder(name)
    local cleaned = tostring(name or ""):gsub("[%c/\\:%*%?\"<>|]", "")
    cleaned = cleaned:gsub("%.%.+", "."):gsub("^[%s%.]+", ""):gsub("[%s%.]+$", "")
    return cleaned
end

local function gameFolderName()
    -- game.Name is unreliable on the client (can report the experience type), so prefer the place page name
    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId)
    end)
    local name = ok and info and info.Name or nil
    name = sanitizeFolder(name)
    if name == "" then
        name = sanitizeFolder(game.Name)
    end
    if name == "" then
        name = "Place" .. tostring(game.PlaceId)
    end
    return name
end

local CONFIG_FOLDER = "PecelHub/" .. gameFolderName() .. "/Config"

local window = Airflow:CreateWindow({
    Name = TOOL_NAME,
    Subtitle = "Made by BriannnKece",
    Theme = "Midnight",
    ToggleUIKeybind = settings.UiKeybind,
    Size = UDim2.fromOffset(640, 480),
    MinSize = Vector2.new(520, 360),
    ConfigurationSaving = { Enabled = true, FolderName = CONFIG_FOLDER, FileName = "default", AutoSave = true },
    Home = {
        Name = "Home",
        Stats = { "FPS", "Ping", "Time" },
    },
})

local espTab = window:CreateTab({ Name = "ESP", Desc = "Object highlighting", Icon = "scan-eye" })
local infoTab = window:CreateTab({ Name = "Info", Desc = "Live puzzle readout", Icon = "info" })
local configTab = window:CreateTab({ Name = "Settings", Desc = "Keybind and config files", Icon = "settings" })

espTab:CreateSection("Objects")

local espToggleOptions = {
    { key = "EspKey", name = "ESP Key", desc = "Colour-coded key outlines", icon = "key-round" },
    { key = "EspKeypad", name = "ESP Keypad", desc = "Front door keypad", icon = "grid-3x3" },
    { key = "EspNote", name = "ESP Passcode Note", desc = "Note holding the door code", icon = "scroll" },
    { key = "EspPadlock", name = "ESP Padlock", desc = "Padlocks on the front door", icon = "lock" },
    { key = "EspFlipFlop", name = "ESP Flip Flop", desc = "Nearest three only", icon = "footprints" },
    { key = "EspWardNear", name = "ESP Wardrobe", desc = "Nearest hiding wardrobe", icon = "door-closed" },
    { key = "EspOpah", name = "ESP Opah", desc = "Track the ghost", icon = "ghost" },
}

for _, option in ipairs(espToggleOptions) do
    espTab:CreateToggle({
        Name = option.name,
        Desc = option.desc,
        Icon = option.icon,
        CurrentValue = settings[option.key],
        Flag = option.key,
        Callback = function(value)
            settings[option.key] = value
            applyVisibility()
        end,
    })
end

espTab:CreateSection("Interaction")

local promptToggle = espTab:CreateToggle({
    Name = "Instant Prompt",
    Desc = "Skip proximity prompt hold time",
    Icon = "zap",
    CurrentValue = settings.InstantPrompt,
    Flag = "InstantPrompt",
    Callback = function(value)
        settings.InstantPrompt = value
        if value then
            enableInstantPrompt()
        end
    end,
})

espTab:CreateSlider({
    Name = "Update Delay",
    Desc = "How often distances refresh",
    Icon = "timer",
    Range = { 0.1, 9 },
    Increment = 0.1,
    Suffix = " s",
    CurrentValue = settings.UpdateDelay,
    Flag = "UpdateDelay",
    Callback = function(value)
        settings.UpdateDelay = value
    end,
})

espTab:CreateSection("Automation")

farmToggle = espTab:CreateToggle({
    Name = "Auto Farm Padlocks",
    Desc = "Grab every key, pop the padlocks, enter the door code, then board the bike",
    Icon = "key-round",
    CurrentValue = settings.AutoFarm,
    Flag = "AutoFarm",
    Callback = function(value)
        setAutoFarm(value)
    end,
})

espTab:CreateKeybind({
    Name = "Auto Farm Keybind",
    Desc = "Start or stop the farm without opening this window",
    Icon = "keyboard",
    CurrentKeybind = settings.FarmKeybind,
    Flag = "FarmKeybind",
    OnChanged = function(key)
        settings.FarmKeybind = key and key.Name or "None"
    end,
    Callback = function()
        setAutoFarm(not farmState.running)
    end,
})

espTab:CreateToggle({
    Name = "Auto Execute In Game",
    Desc = "Re-arm the ESP and prompt hooks by itself when the game place loads",
    Icon = "zap",
    CurrentValue = settings.AutoExecute,
    Flag = "AutoExecute",
    Callback = function(value)
        settings.AutoExecute = value
        if value and inGamePlace() then
            onEnterGamePlace()
        end
    end,
})

espTab:CreateToggle({
    Name = "Auto Skip Cutscene",
    Desc = "Vote to skip every cutscene the moment its button shows up",
    Icon = "timer",
    CurrentValue = settings.SkipCutscene,
    Flag = "SkipCutscene",
    Callback = function(value)
        settings.SkipCutscene = value
    end,
})

infoTab:CreateSection("Objects")

infoTab:CreateLabel({
    Text = "Keys -",
    Update = function()
        return "Keys " .. countKind("Key")
            .. "  |  Flip Flops " .. countKind("FlipFlop")
            .. "  |  Wardrobes " .. countKind("Wardrobe")
    end,
    UpdateRate = 0.5,
})

infoTab:CreateLabel({
    Text = "Passcode -",
    Update = function()
        local text = "Code " .. (passcode or "-")
        if heldKeys then
            text = text .. "  |  Held " .. displayValue(heldKeys)
        end
        return text
    end,
    UpdateRate = 0.5,
})

infoTab:CreateLabel({
    Text = "Wardrobe -",
    Update = function()
        local wardrobe, distance = nearestOf("Wardrobe")
        if not wardrobe or not distance then
            return "Nearest wardrobe -"
        end
        return "Nearest wardrobe " .. wardrobe.Name .. " [" .. distanceText(distance) .. "]"
    end,
    UpdateRate = 0.5,
})

infoTab:CreateSection("Automation")

infoTab:CreateLabel({
    Text = "Auto farm -",
    Update = function()
        return "Auto farm " .. farmState.status
            .. "  |  Padlocks " .. farmState.opened .. "/" .. farmState.total
    end,
    UpdateRate = 0.5,
})

infoTab:CreateSection("Passcode Note")

noteParagraph = infoTab:CreateParagraph({
    Title = "Note text",
    Content = "Waiting for the note to be picked up.",
})

configTab:CreateSection("Interface")

configTab:CreateKeybind({
    Name = "Toggle UI",
    Desc = "Show or hide this window",
    Icon = "keyboard",
    CurrentKeybind = settings.UiKeybind,
    Flag = "UiKeybind",
    OnChanged = function(key)
        settings.UiKeybind = key and key.Name or "LeftAlt"
        window:SetKeybind(settings.UiKeybind)
    end,
})

configTab:CreateSection("Config files")

configTab:CreateLabel({ Text = "Folder: " .. CONFIG_FOLDER })

configTab:CreateConfigManager({ Name = "Configs" })

task.spawn(function()
    while not closed do
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local opah = Workspace:FindFirstChild("Opah")
        local opahRoot = opah and opah:FindFirstChild("HumanoidRootPart")
        heldKeys = LocalPlayer:GetAttribute("PuzzleHeldCode")

        if settings.EspOpah and root and opahRoot and espEntries[opah] then
            espEntries[opah].distance = (opahRoot.Position - root.Position).Magnitude
        end

        task.wait(settings.UpdateDelay)
    end
end)

task.spawn(function()
    while not closed do
        local text = noteText or "Waiting for the note to be picked up."
        if noteParagraph:Get() ~= text then
            noteParagraph:Set(text)
        end
        task.wait(0.5)
    end
end)

local loaded = window:LoadConfig()
window:SetKeybind(settings.UiKeybind)
if not loaded then
    promptToggle:Set(settings.InstantPrompt, true)
end
if settings.AutoFarm then
    -- a saved config can leave the toggle on; loading it fires the callback and
    -- starts a farm thread, so shut that thread down rather than only the knob
    setAutoFarm(false, true)
    settings.AutoFarm = false
end

watchForGamePlace()

if settings.InstantPrompt then
    enableInstantPrompt()
end
applyVisibility()

window.Gui.Destroying:Once(function()
    closed = true
    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    if espGui then
        espGui:Destroy()
    end
end)
