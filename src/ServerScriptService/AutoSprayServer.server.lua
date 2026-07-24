--!strict
-- AutoSpray authoritative server.
-- GitHub/Rojo path: src/ServerScriptService/AutoSprayServer.server.lua
--
-- Responsibilities:
--   * Loads compressed stroke documents from ServerStorage modules or HTTPS JSON.
--   * Creates replicated canvas parts and authoritative pixel buffers.
--   * Validates/rate-limits paint segments.
--   * Broadcasts canvas updates and realistic spray poses to every client.
--   * Streams completed canvas snapshots to late joiners.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local rootFolder = ReplicatedStorage:WaitForChild("AutoSpray")
local Main = require(rootFolder:WaitForChild("Main"))
local Config = Main.Config
local StrokeCodec = Main.StrokeCodec

---------------------------------------------------------------------
-- REMOTES / FOLDERS
---------------------------------------------------------------------

local function getOrCreate(className: string, name: string, parent: Instance): Instance
    local existing = parent:FindFirstChild(name)
    if existing then
        assert(existing.ClassName == className, `{parent:GetFullName()}.{name} must be {className}`)
        return existing
    end

    local object = Instance.new(className)
    object.Name = name
    object.Parent = parent
    return object
end

local ControlFunction = getOrCreate("RemoteFunction", "ControlFunction", rootFolder) :: RemoteFunction
local ControlEvent = getOrCreate("RemoteEvent", "ControlEvent", rootFolder) :: RemoteEvent
local CanvasEvent = getOrCreate("RemoteEvent", "CanvasEvent", rootFolder) :: RemoteEvent

local imageFolder = ServerStorage:FindFirstChild("AutoSprayImages")
if not imageFolder then
    imageFolder = Instance.new("Folder")
    imageFolder.Name = "AutoSprayImages"
    imageFolder.Parent = ServerStorage
end

local canvasFolder = Workspace:FindFirstChild("AutoSprayCanvases")
if not canvasFolder then
    canvasFolder = Instance.new("Folder")
    canvasFolder.Name = "AutoSprayCanvases"
    canvasFolder.Parent = Workspace
end

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------

local loadedDocuments: { [Player]: { [string]: any } } = {}
local activeDocumentId: { [Player]: string } = {}

local sessions: { [string]: { [string]: any } } = {}
local activeSessionByPlayer: { [Player]: string } = {}

local pixelLimiters: { [Player]: { tokens: number, updatedAt: number } } = {}
local poseLimiters: { [Player]: { count: number, windowStarted: number } } = {}

---------------------------------------------------------------------
-- AUTHORIZATION
---------------------------------------------------------------------

local function isAllowed(player: Player): boolean
    if Config.AdminUserIds[player.UserId] == true then
        return true
    end

    if game.CreatorType == Enum.CreatorType.User
        and player.UserId == game.CreatorId
    then
        return true
    end

    if RunService:IsStudio() and Config.AllowAllInStudio then
        return true
    end

    if game.PrivateServerId ~= "" and Config.AllowAllPrivateServers then
        return true
    end

    return false
end

local function requireAllowed(player: Player): (boolean, string?)
    if not isAllowed(player) then
        return false, "AutoSpray permission denied."
    end
    return true
end

---------------------------------------------------------------------
-- TOOL
---------------------------------------------------------------------

local TOOL_NAME = "AutoSprayCan"

local function findTool(player: Player): Tool?
    local character = player.Character
    if character then
        local equipped = character:FindFirstChild(TOOL_NAME)
        if equipped and equipped:IsA("Tool") then
            return equipped
        end
    end

    local backpack = player:FindFirstChildOfClass("Backpack")
    if backpack then
        local stored = backpack:FindFirstChild(TOOL_NAME)
        if stored and stored:IsA("Tool") then
            return stored
        end
    end

    return nil
end

local function createTool(player: Player): Tool
    local existing = findTool(player)
    if existing then
        return existing
    end

    local tool = Instance.new("Tool")
    tool.Name = TOOL_NAME
    tool.ToolTip = "Auto Spray Paint"
    tool.RequiresHandle = true
    tool.CanBeDropped = false
    tool:SetAttribute("AutoSprayTool", true)
    tool:SetAttribute("ColorHex", "#FFFFFF")
    tool:SetAttribute("BrushSize", 0.1)

    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Shape = Enum.PartType.Cylinder
    handle.Size = Vector3.new(0.42, 0.92, 0.42)
    handle.Material = Enum.Material.Metal
    handle.Color = Color3.fromRGB(210, 214, 223)
    handle.CanCollide = false
    handle.CanTouch = false
    handle.CanQuery = false
    handle.Massless = true
    handle.Parent = tool

    local nozzle = Instance.new("Attachment")
    nozzle.Name = "Nozzle"
    nozzle.Position = Vector3.new(0, 0.48, 0)
    nozzle.Parent = handle

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "SprayMist"
    emitter.Enabled = false
    emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
    emitter.Rate = 90
    emitter.Lifetime = NumberRange.new(0.08, 0.17)
    emitter.Speed = NumberRange.new(5, 8)
    emitter.SpreadAngle = Vector2.new(14, 14)
    emitter.Drag = 8
    emitter.LightEmission = 0.35
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.055),
        NumberSequenceKeypoint.new(1, 0.015),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.15),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Parent = nozzle

    if Config.Realistic.SpraySoundId ~= "" then
        local sound = Instance.new("Sound")
        sound.Name = "SprayLoop"
        sound.SoundId = Config.Realistic.SpraySoundId
        sound.Volume = Config.Realistic.SpraySoundVolume
        sound.Looped = true
        sound.RollOffMaxDistance = 45
        sound.Parent = handle
    end

    tool.Grip = CFrame.new(0, -0.25, 0)
        * CFrame.Angles(0, 0, math.rad(90))

    local backpack = player:FindFirstChildOfClass("Backpack")
    tool.Parent = backpack or player

    return tool
end

local function equipTool(player: Player)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local backpack = player:FindFirstChildOfClass("Backpack")

    if not humanoid or not backpack then
        return
    end

    local tool = createTool(player)
    tool.Parent = backpack
    humanoid:EquipTool(tool)
end

---------------------------------------------------------------------
-- DOCUMENT HELPERS
---------------------------------------------------------------------

local function metadataFor(documentId: string, decoded: { [string]: any }): { [string]: any }
    return {
        documentId = documentId,
        name = decoded.Name,
        width = decoded.Width,
        height = decoded.Height,
        palette = decoded.Palette,
        strokeCount = decoded.StrokeCount,
        recommendedWarning = math.max(decoded.Width, decoded.Height)
            > Config.RecommendedMaxResolution,
    }
end

local function rememberDocument(player: Player, decoded: { [string]: any }): { [string]: any }
    local documentId = HttpService:GenerateGUID(false)

    loadedDocuments[player] = loadedDocuments[player] or {}
    loadedDocuments[player][documentId] = decoded
    activeDocumentId[player] = documentId

    return metadataFor(documentId, decoded)
end

local function loadModuleDocument(player: Player, moduleName: any): ({ [string]: any }?, string?)
    if type(moduleName) ~= "string"
        or #moduleName < 1
        or #moduleName > 80
        or string.match(moduleName, "^[%w_%- ]+$") == nil
    then
        return nil, "Invalid module name."
    end

    local module = imageFolder:FindFirstChild(moduleName)
    if not module or not module:IsA("ModuleScript") then
        return nil, "Image module not found."
    end

    local requireOk, rawOrError = pcall(require, module)
    if not requireOk then
        return nil, `Image module failed: {tostring(rawOrError)}`
    end

    local decoded, decodeError = StrokeCodec.DecodeDocument(rawOrError, Config)
    if not decoded then
        return nil, decodeError
    end

    return rememberDocument(player, decoded)
end

local function parseHttpsHost(url: string): string?
    local host = string.match(url, "^https://([^/%?#]+)")
    if not host then
        return nil
    end

    host = string.lower(host)
    host = string.gsub(host, ":%d+$", "")
    return host
end

local function loadUrlDocument(player: Player, url: any): ({ [string]: any }?, string?)
    if not Config.AllowHttpDocuments then
        return nil, "HTTP document loading is disabled."
    end

    if type(url) ~= "string" or #url < 10 or #url > 2048 then
        return nil, "Invalid URL."
    end

    local host = parseHttpsHost(url)
    if not host or Config.AllowedHttpHosts[host] ~= true then
        return nil, "URL host is not allowed in Config.AllowedHttpHosts."
    end

    local requestOk, bodyOrError = pcall(function()
        return HttpService:GetAsync(url, true)
    end)

    if not requestOk then
        return nil, `HTTP request failed: {tostring(bodyOrError)}`
    end

    local body = bodyOrError
    if type(body) ~= "string" or #body > Config.MaxHttpDocumentBytes then
        return nil, "HTTP document is empty or too large."
    end

    local jsonOk, rawOrError = pcall(function()
        return HttpService:JSONDecode(body)
    end)

    if not jsonOk then
        return nil, `JSON decode failed: {tostring(rawOrError)}`
    end

    local decoded, decodeError = StrokeCodec.DecodeDocument(rawOrError, Config)
    if not decoded then
        return nil, decodeError
    end

    return rememberDocument(player, decoded)
end

local function listImageModules(): { string }
    local names = {}

    for _, child in ipairs(imageFolder:GetChildren()) do
        if child:IsA("ModuleScript") then
            table.insert(names, child.Name)
        end
    end

    table.sort(names, function(a, b)
        return string.lower(a) < string.lower(b)
    end)

    return names
end

local function getPlayerDocument(player: Player, documentId: any): ({ [string]: any }?, string?)
    if type(documentId) ~= "string" then
        return nil, "Invalid document ID."
    end

    local playerDocuments = loadedDocuments[player]
    local decoded = playerDocuments and playerDocuments[documentId]

    if not decoded then
        return nil, "Document is not loaded for this player."
    end

    return decoded
end

---------------------------------------------------------------------
-- CANVAS / PIXELS
---------------------------------------------------------------------

local function validTarget(player: Player, target: any): BasePart?
    if typeof(target) ~= "Instance"
        or not target:IsA("BasePart")
        or not target:IsDescendantOf(Workspace)
    then
        return nil
    end

    if Config.RequireCanvasAttribute
        and target:GetAttribute(Config.CanvasAttributeName) ~= true
    then
        return nil
    end

    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        if (root.Position - target.Position).Magnitude > Config.MaxTargetDistanceStuds then
            return nil
        end
    end

    return target
end

local function paletteCache(palette: { string }): { { number } }
    local output = table.create(#palette)

    for index, entry in ipairs(palette) do
        local r, g, b, a = StrokeCodec.PaletteBytes(entry)
        output[index] = { r, g, b, a }
    end

    return output
end

local function createCanvasSession(
    player: Player,
    decoded: { [string]: any },
    payload: any
): ({ [string]: any }?, string?)
    if type(payload) ~= "table" then
        return nil, "Invalid canvas payload."
    end

    local target = validTarget(player, payload.target)
    if not target then
        return nil, "Invalid target surface."
    end

    if typeof(payload.canvasCFrame) ~= "CFrame" then
        return nil, "Invalid canvas CFrame."
    end

    local widthStuds = tonumber(payload.widthStuds)
    local heightStuds = tonumber(payload.heightStuds)

    if not widthStuds
        or not heightStuds
        or widthStuds < 0.1
        or heightStuds < 0.1
        or widthStuds > Config.MaxCanvasSideStuds
        or heightStuds > Config.MaxCanvasSideStuds
    then
        return nil, "Invalid canvas size."
    end

    local previousSessionId = activeSessionByPlayer[player]
    if previousSessionId then
        local previous = sessions[previousSessionId]
        if previous and not previous.Finished then
            CanvasEvent:FireAllClients("CanvasRemove", previousSessionId)
            previous.CanvasPart:Destroy()
            sessions[previousSessionId] = nil
        end
    end

    local sessionId = HttpService:GenerateGUID(false)

    local canvasPart = Instance.new("Part")
    canvasPart.Name = `AutoSprayCanvas_{player.UserId}`
    canvasPart.Anchored = true
    canvasPart.CanCollide = false
    canvasPart.CanTouch = false
    canvasPart.CanQuery = false
    canvasPart.CastShadow = false
    canvasPart.Transparency = 1
    canvasPart.Size = Vector3.new(widthStuds, heightStuds, 0.012)
    canvasPart.CFrame = payload.canvasCFrame
    canvasPart:SetAttribute("AutoSpraySessionId", sessionId)
    canvasPart:SetAttribute("OwnerUserId", player.UserId)
    canvasPart:SetAttribute("ImageName", decoded.Name)
    canvasPart.Parent = canvasFolder

    local session = {
        Id = sessionId,
        Player = player,
        Document = decoded,
        Target = target,
        CanvasPart = canvasPart,
        PixelBuffer = buffer.create(decoded.Width * decoded.Height * 4),
        PaletteBytes = paletteCache(decoded.Palette),
        Width = decoded.Width,
        Height = decoded.Height,
        WidthStuds = widthStuds,
        HeightStuds = heightStuds,
        Finished = false,
        CreatedAt = os.time(),
    }

    sessions[sessionId] = session
    activeSessionByPlayer[player] = sessionId

    CanvasEvent:FireAllClients("CanvasCreate", sessionId, {
        canvasPart = canvasPart,
        width = decoded.Width,
        height = decoded.Height,
        palette = decoded.Palette,
        ownerUserId = player.UserId,
        imageName = decoded.Name,
    })

    return {
        sessionId = sessionId,
        width = decoded.Width,
        height = decoded.Height,
    }
end

local function consumePixelBudget(player: Player, pixelCount: number): boolean
    local now = os.clock()
    local limiter = pixelLimiters[player]

    if not limiter then
        limiter = {
            tokens = Config.MaxPaintedPixelsPerSecond,
            updatedAt = now,
        }
        pixelLimiters[player] = limiter
    end

    local elapsed = math.max(0, now - limiter.updatedAt)
    limiter.updatedAt = now
    limiter.tokens = math.min(
        Config.MaxPaintedPixelsPerSecond,
        limiter.tokens + elapsed * Config.MaxPaintedPixelsPerSecond
    )

    if pixelCount > limiter.tokens then
        return false
    end

    limiter.tokens -= pixelCount
    return true
end

local function applySegments(player: Player, sessionId: any, segmentBuffer: any)
    if type(sessionId) ~= "string"
        or typeof(segmentBuffer) ~= "buffer"
    then
        return
    end

    local session = sessions[sessionId]
    if not session
        or session.Player ~= player
        or session.Finished
    then
        return
    end

    local byteLength = buffer.len(segmentBuffer)
    if byteLength == 0 or byteLength % StrokeCodec.STROKE_BYTES ~= 0 then
        return
    end

    local segmentCount = byteLength / StrokeCodec.STROKE_BYTES
    if segmentCount > Config.MaxSegmentsPerEvent then
        return
    end

    local totalPixels = 0

    for index = 1, segmentCount do
        local y, xStart, xEnd, paletteIndex =
            StrokeCodec.ReadStroke(segmentBuffer, index)

        if y >= session.Height
            or xStart >= session.Width
            or xEnd >= session.Width
            or session.PaletteBytes[paletteIndex + 1] == nil
        then
            return
        end

        totalPixels += StrokeCodec.CountPixelsInStroke(xStart, xEnd)
    end

    if not consumePixelBudget(player, totalPixels) then
        return
    end

    for index = 1, segmentCount do
        local y, xStart, xEnd, paletteIndex =
            StrokeCodec.ReadStroke(segmentBuffer, index)

        local color = session.PaletteBytes[paletteIndex + 1]
        local step = xEnd >= xStart and 1 or -1
        local x = xStart

        while true do
            local offset = (y * session.Width + x) * 4
            buffer.writeu8(session.PixelBuffer, offset, color[1])
            buffer.writeu8(session.PixelBuffer, offset + 1, color[2])
            buffer.writeu8(session.PixelBuffer, offset + 2, color[3])
            buffer.writeu8(session.PixelBuffer, offset + 3, color[4])

            if x == xEnd then
                break
            end
            x += step
        end
    end

    CanvasEvent:FireAllClients("CanvasSegments", sessionId, segmentBuffer)
end

local function sendSnapshot(player: Player, sessionId: string, session: { [string]: any })
    if not session.CanvasPart.Parent then
        return
    end

    CanvasEvent:FireClient(player, "CanvasCreate", sessionId, {
        canvasPart = session.CanvasPart,
        width = session.Width,
        height = session.Height,
        palette = session.Document.Palette,
        ownerUserId = session.Player.UserId,
        imageName = session.Document.Name,
    })

    local rowsPerChunk = math.max(1, Config.SnapshotRowsPerChunk)

    for yStart = 0, session.Height - 1, rowsPerChunk do
        if not player.Parent or not session.CanvasPart.Parent then
            return
        end

        local rowCount = math.min(rowsPerChunk, session.Height - yStart)
        local byteCount = session.Width * rowCount * 4
        local chunk = buffer.create(byteCount)

        buffer.copy(
            chunk,
            0,
            session.PixelBuffer,
            yStart * session.Width * 4,
            byteCount
        )

        CanvasEvent:FireClient(
            player,
            "CanvasSnapshot",
            sessionId,
            yStart,
            rowCount,
            chunk
        )

        task.wait()
    end
end

---------------------------------------------------------------------
-- SPRAY POSE REPLICATION
---------------------------------------------------------------------

local function allowPose(player: Player): boolean
    local now = os.clock()
    local limiter = poseLimiters[player]

    if not limiter or now - limiter.windowStarted >= 1 then
        poseLimiters[player] = {
            count = 1,
            windowStarted = now,
        }
        return true
    end

    limiter.count += 1
    return limiter.count <= Config.MaxPoseEventsPerSecond
end

local function relaySprayPose(
    player: Player,
    worldPosition: any,
    color: any,
    active: any
)
    if typeof(worldPosition) ~= "Vector3"
        or typeof(color) ~= "Color3"
        or type(active) ~= "boolean"
        or not allowPose(player)
    then
        return
    end

    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if root and root:IsA("BasePart") then
        if (worldPosition - root.Position).Magnitude > Config.MaxTargetDistanceStuds then
            return
        end
    end

    CanvasEvent:FireAllClients(
        "SprayPose",
        player.UserId,
        worldPosition,
        color,
        active
    )
end

---------------------------------------------------------------------
-- REMOTE FUNCTION
---------------------------------------------------------------------

ControlFunction.OnServerInvoke = function(player: Player, action: any, ...: any)
    local allowed, permissionError = requireAllowed(player)
    if not allowed then
        return false, permissionError
    end

    if action == "ListModules" then
        return true, listImageModules()
    end

    if action == "LoadModule" then
        local moduleName = ...
        local metadata, loadError = loadModuleDocument(player, moduleName)
        if not metadata then
            return false, loadError
        end
        return true, metadata
    end

    if action == "LoadUrl" then
        local url = ...
        local metadata, loadError = loadUrlDocument(player, url)
        if not metadata then
            return false, loadError
        end
        return true, metadata
    end

    if action == "GetDocumentChunk" then
        local documentId, startIndexValue, countValue = ...
        local decoded, documentError = getPlayerDocument(player, documentId)
        if not decoded then
            return false, documentError
        end

        local startIndex = math.floor(tonumber(startIndexValue) or 1)
        local requestedCount = math.floor(tonumber(countValue) or 0)

        if startIndex < 1 or startIndex > decoded.StrokeCount + 1 then
            return false, "Invalid chunk start."
        end

        local maxCount = math.max(1, Config.DocumentChunkStrokes)
        local count = math.clamp(requestedCount, 0, maxCount)
        count = math.min(count, decoded.StrokeCount - startIndex + 1)

        local chunk = StrokeCodec.CopyStrokeChunk(
            decoded.StrokeBuffer,
            startIndex,
            count
        )

        return true, {
            startIndex = startIndex,
            count = count,
            data = chunk,
            done = startIndex + count > decoded.StrokeCount,
        }
    end

    if action == "StartCanvas" then
        local documentId, payload = ...
        local decoded, documentError = getPlayerDocument(player, documentId)
        if not decoded then
            return false, documentError
        end

        local result, startError = createCanvasSession(player, decoded, payload)
        if not result then
            return false, startError
        end

        return true, result
    end

    return false, "Unknown AutoSpray action."
end

---------------------------------------------------------------------
-- REMOTE EVENT
---------------------------------------------------------------------

ControlEvent.OnServerEvent:Connect(function(player: Player, action: any, ...: any)
    if not isAllowed(player) or type(action) ~= "string" then
        return
    end

    if action == "EquipTool" then
        equipTool(player)
        return
    end

    if action == "PaintSegments" then
        local sessionId, segmentBuffer = ...
        applySegments(player, sessionId, segmentBuffer)
        return
    end

    if action == "SprayPose" then
        local position, color, active = ...
        relaySprayPose(player, position, color, active)
        return
    end

    local sessionId = ...
    if type(sessionId) ~= "string" then
        return
    end

    local session = sessions[sessionId]
    if not session or session.Player ~= player then
        return
    end

    if action == "Finish" then
        session.Finished = true
        if activeSessionByPlayer[player] == sessionId then
            activeSessionByPlayer[player] = nil
        end
        CanvasEvent:FireAllClients("SprayPose", player.UserId, Vector3.zero, Color3.new(1, 1, 1), false)
    elseif action == "Cancel" then
        sessions[sessionId] = nil
        if activeSessionByPlayer[player] == sessionId then
            activeSessionByPlayer[player] = nil
        end
        CanvasEvent:FireAllClients("CanvasRemove", sessionId)
        session.CanvasPart:Destroy()
    end
end)

---------------------------------------------------------------------
-- JOIN / LEAVE
---------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player: Player)
    task.delay(2, function()
        if not player.Parent then
            return
        end

        for sessionId, session in pairs(sessions) do
            if session.CanvasPart.Parent then
                sendSnapshot(player, sessionId, session)
            end
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
    loadedDocuments[player] = nil
    activeDocumentId[player] = nil
    pixelLimiters[player] = nil
    poseLimiters[player] = nil

    local sessionId = activeSessionByPlayer[player]
    if sessionId then
        local session = sessions[sessionId]
        if session and not session.Finished then
            sessions[sessionId] = nil
            CanvasEvent:FireAllClients("CanvasRemove", sessionId)
            session.CanvasPart:Destroy()
        end
        activeSessionByPlayer[player] = nil
    end
end)

print("[AutoSpray] Server ready.")
