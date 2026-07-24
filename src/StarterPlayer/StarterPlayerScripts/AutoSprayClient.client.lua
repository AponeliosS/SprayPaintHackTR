--!strict
-- AutoSpray client/UI/renderer/realistic drawing controller.
-- GitHub/Rojo path:
-- src/StarterPlayer/StarterPlayerScripts/AutoSprayClient.client.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local AssetService = game:GetService("AssetService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- BOOT STATUS
---------------------------------------------------------------------

local bootGui = Instance.new("ScreenGui")
bootGui.Name = "AutoSprayBoot"
bootGui.ResetOnSpawn = false
bootGui.DisplayOrder = 100000
bootGui.Parent = playerGui

local bootLabel = Instance.new("TextLabel")
bootLabel.AnchorPoint = Vector2.new(0, 0.5)
bootLabel.Position = UDim2.new(0, 18, 0.5, 0)
bootLabel.Size = UDim2.fromOffset(480, 58)
bootLabel.BackgroundColor3 = Color3.fromRGB(19, 22, 29)
bootLabel.BorderSizePixel = 0
bootLabel.Text = "AutoSpray istemcisi başlatılıyor..."
bootLabel.TextColor3 = Color3.fromRGB(241, 245, 255)
bootLabel.TextSize = 14
bootLabel.Font = Enum.Font.GothamBold
bootLabel.Parent = bootGui

local bootCorner = Instance.new("UICorner")
bootCorner.CornerRadius = UDim.new(0, 10)
bootCorner.Parent = bootLabel

local function main()
    -----------------------------------------------------------------
    -- SHARED
    -----------------------------------------------------------------

    local rootFolder = ReplicatedStorage:WaitForChild("AutoSpray", 20)
    assert(rootFolder, "ReplicatedStorage.AutoSpray not found.")

    local Main = require(rootFolder:WaitForChild("Main"))
    local Config = Main.Config
    local StrokeCodec = Main.StrokeCodec

    local ControlFunction = rootFolder:WaitForChild("ControlFunction") :: RemoteFunction
    local ControlEvent = rootFolder:WaitForChild("ControlEvent") :: RemoteEvent
    local CanvasEvent = rootFolder:WaitForChild("CanvasEvent") :: RemoteEvent

    local mouse = player:GetMouse()
    local camera = Workspace.CurrentCamera
    local random = Random.new()

    -----------------------------------------------------------------
    -- STATE
    -----------------------------------------------------------------

    local currentDocument: { [string]: any }? = nil
    local previewImage: EditableImage? = nil
    local previewBuffer: buffer? = nil
    local loadingDocument = false

    local selectedPart: BasePart? = nil
    local firstCorner: Vector3? = nil
    local secondCorner: Vector3? = nil
    local surfaceNormal: Vector3? = nil
    local surfaceAxisU: Vector3? = nil
    local surfaceAxisV: Vector3? = nil
    local selecting = false
    local selectionStage = 0

    local drawState = "Idle" -- Idle / Running / Paused / Stopping
    local currentSessionId: string? = nil
    local sprayEquipped = false
    local currentHex = "#FFFFFF"
    local currentBrushSize = 0.1

    local renderers: { [string]: { [string]: any } } = {}
    local sprayVfx: { [number]: { [string]: any } } = {}

    local selectionFolder = Instance.new("Folder")
    selectionFolder.Name = "_AutoSpraySelection"
    selectionFolder.Parent = Workspace

    local localVfxFolder = Instance.new("Folder")
    localVfxFolder.Name = "_AutoSprayVfx"
    localVfxFolder.Parent = Workspace

    mouse.TargetFilter = selectionFolder

    -----------------------------------------------------------------
    -- HELPERS
    -----------------------------------------------------------------

    local function clampInteger(
        text: string,
        fallback: number,
        minimum: number,
        maximum: number
    ): number
        local value = tonumber(text)
        if value == nil then
            return fallback
        end

        return math.clamp(
            math.floor(value + 0.5),
            minimum,
            maximum
        )
    end

    local function rgbHex(red: number, green: number, blue: number): string
        return string.format("#%02X%02X%02X", red, green, blue)
    end

    local function paletteBytes(palette: { string }): { { number } }
        local output = table.create(#palette)

        for index, entry in ipairs(palette) do
            local red, green, blue, alpha =
                StrokeCodec.PaletteBytes(entry)
            output[index] = { red, green, blue, alpha }
        end

        return output
    end

    local function destroyEditable(image: EditableImage?)
        if image then
            pcall(function()
                image:Destroy()
            end)
        end
    end

    local function createEditable(width: number, height: number): EditableImage?
        local ok, result = pcall(function()
            return AssetService:CreateEditableImage({
                Size = Vector2.new(width, height),
            })
        end)

        if ok then
            return result
        end

        warn("[AutoSpray] EditableImage create failed:", result)
        return nil
    end

    local function invoke(action: string, ...: any): (boolean, any)
        local arguments = table.pack(...)

        local ok, success, payload = pcall(function()
            return ControlFunction:InvokeServer(
                action,
                table.unpack(arguments, 1, arguments.n)
            )
        end)

        if not ok then
            return false, success
        end

        if success ~= true then
            return false, payload
        end

        return true, payload
    end

    -----------------------------------------------------------------
    -- UI BUILDERS
    -----------------------------------------------------------------

    local gui = Instance.new("ScreenGui")
    gui.Name = "AutoSprayGui"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = Config.UI.DisplayOrder
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "Main"
    mainFrame.AnchorPoint = Vector2.new(0, 0.5)
    mainFrame.Position = UDim2.new(0, 18, 0.5, 0)
    mainFrame.Size = UDim2.fromOffset(540, 700)
    mainFrame.BackgroundColor3 = Color3.fromRGB(19, 22, 29)
    mainFrame.BorderSizePixel = 0
    mainFrame.Visible = not Config.UI.StartHidden
    mainFrame.Parent = gui

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 14)
    mainCorner.Parent = mainFrame

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Color3.fromRGB(70, 80, 102)
    mainStroke.Transparency = 0.16
    mainStroke.Parent = mainFrame

    local mainPadding = Instance.new("UIPadding")
    mainPadding.PaddingLeft = UDim.new(0, 14)
    mainPadding.PaddingRight = UDim.new(0, 14)
    mainPadding.PaddingTop = UDim.new(0, 12)
    mainPadding.PaddingBottom = UDim.new(0, 12)
    mainPadding.Parent = mainFrame

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = mainFrame

    local function round(object: GuiObject, radius: number?)
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, radius or 8)
        corner.Parent = object
    end

    local function addStroke(object: GuiObject, color: Color3?)
        local stroke = Instance.new("UIStroke")
        stroke.Color = color or Color3.fromRGB(64, 73, 92)
        stroke.Transparency = 0.30
        stroke.Parent = object
    end

    local function makeLabel(
        parent: Instance,
        text: string,
        height: number,
        size: number,
        bold: boolean?
    ): TextLabel
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 0, height)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = Color3.fromRGB(235, 239, 249)
        label.TextSize = size
        label.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = parent
        return label
    end

    local function makeButton(
        parent: Instance,
        text: string,
        color: Color3
    ): TextButton
        local button = Instance.new("TextButton")
        button.AutoButtonColor = false
        button.Size = UDim2.new(1, 0, 1, 0)
        button.BackgroundColor3 = color
        button.BorderSizePixel = 0
        button.Text = text
        button.TextColor3 = Color3.fromRGB(247, 249, 255)
        button.TextSize = 12
        button.Font = Enum.Font.GothamBold
        button.Parent = parent
        round(button, 8)

        local baseColor = color

        button.MouseEnter:Connect(function()
            TweenService:Create(button, TweenInfo.new(0.10), {
                BackgroundColor3 = baseColor:Lerp(Color3.new(1, 1, 1), 0.08),
            }):Play()
        end)

        button.MouseLeave:Connect(function()
            TweenService:Create(button, TweenInfo.new(0.10), {
                BackgroundColor3 = baseColor,
            }):Play()
        end)

        return button
    end

    local function makeInput(
        parent: Instance,
        placeholder: string,
        text: string?
    ): TextBox
        local box = Instance.new("TextBox")
        box.Size = UDim2.new(1, 0, 1, 0)
        box.BackgroundColor3 = Color3.fromRGB(31, 35, 45)
        box.BorderSizePixel = 0
        box.Text = text or ""
        box.PlaceholderText = placeholder
        box.PlaceholderColor3 = Color3.fromRGB(122, 131, 151)
        box.TextColor3 = Color3.fromRGB(242, 245, 255)
        box.TextSize = 12
        box.Font = Enum.Font.Gotham
        box.ClearTextOnFocus = false
        box.Parent = parent
        round(box, 8)
        addStroke(box)
        return box
    end

    -----------------------------------------------------------------
    -- TITLE
    -----------------------------------------------------------------

    local titleRow = Instance.new("Frame")
    titleRow.Size = UDim2.new(1, 0, 0, 32)
    titleRow.BackgroundTransparency = 1
    titleRow.LayoutOrder = 1
    titleRow.Parent = mainFrame

    local title = makeLabel(
        titleRow,
        "AUTO SPRAY — FULL SERVER SYSTEM",
        32,
        17,
        true
    )
    title.Size = UDim2.new(1, -42, 1, 0)

    local hideHolder = Instance.new("Frame")
    hideHolder.AnchorPoint = Vector2.new(1, 0)
    hideHolder.Position = UDim2.fromScale(1, 0)
    hideHolder.Size = UDim2.fromOffset(36, 29)
    hideHolder.BackgroundTransparency = 1
    hideHolder.Parent = titleRow

    local hideButton = makeButton(
        hideHolder,
        "—",
        Color3.fromRGB(53, 59, 73)
    )

    local subtitle = makeLabel(
        mainFrame,
        "Module veya GitHub raw JSON • sunucu görünür • gerçekçi spray",
        18,
        10,
        false
    )
    subtitle.TextColor3 = Color3.fromRGB(148, 157, 179)
    subtitle.LayoutOrder = 2

    -----------------------------------------------------------------
    -- MODULE LOAD
    -----------------------------------------------------------------

    local moduleRow = Instance.new("Frame")
    moduleRow.Size = UDim2.new(1, 0, 0, 42)
    moduleRow.BackgroundTransparency = 1
    moduleRow.LayoutOrder = 3
    moduleRow.Parent = mainFrame

    local moduleInputHolder = Instance.new("Frame")
    moduleInputHolder.Size = UDim2.new(1, -204, 1, 0)
    moduleInputHolder.BackgroundTransparency = 1
    moduleInputHolder.Parent = moduleRow

    local moduleBox = makeInput(
        moduleInputHolder,
        "ServerStorage/AutoSprayImages modül adı",
        "Example"
    )

    local moduleLoadHolder = Instance.new("Frame")
    moduleLoadHolder.Position = UDim2.new(1, -196, 0, 0)
    moduleLoadHolder.Size = UDim2.fromOffset(92, 42)
    moduleLoadHolder.BackgroundTransparency = 1
    moduleLoadHolder.Parent = moduleRow

    local moduleLoadButton = makeButton(
        moduleLoadHolder,
        "MODÜLÜ YÜKLE",
        Color3.fromRGB(46, 112, 211)
    )

    local refreshHolder = Instance.new("Frame")
    refreshHolder.AnchorPoint = Vector2.new(1, 0)
    refreshHolder.Position = UDim2.fromScale(1, 0)
    refreshHolder.Size = UDim2.fromOffset(96, 42)
    refreshHolder.BackgroundTransparency = 1
    refreshHolder.Parent = moduleRow

    local refreshButton = makeButton(
        refreshHolder,
        "LİSTE",
        Color3.fromRGB(72, 81, 101)
    )

    -----------------------------------------------------------------
    -- URL LOAD
    -----------------------------------------------------------------

    local urlRow = Instance.new("Frame")
    urlRow.Size = UDim2.new(1, 0, 0, 42)
    urlRow.BackgroundTransparency = 1
    urlRow.LayoutOrder = 4
    urlRow.Parent = mainFrame

    local urlInputHolder = Instance.new("Frame")
    urlInputHolder.Size = UDim2.new(1, -124, 1, 0)
    urlInputHolder.BackgroundTransparency = 1
    urlInputHolder.Parent = urlRow

    local urlBox = makeInput(
        urlInputHolder,
        "https://raw.githubusercontent.com/.../image.json",
        ""
    )

    local urlLoadHolder = Instance.new("Frame")
    urlLoadHolder.AnchorPoint = Vector2.new(1, 0)
    urlLoadHolder.Position = UDim2.fromScale(1, 0)
    urlLoadHolder.Size = UDim2.fromOffset(116, 42)
    urlLoadHolder.BackgroundTransparency = 1
    urlLoadHolder.Parent = urlRow

    local urlLoadButton = makeButton(
        urlLoadHolder,
        "URL'DEN YÜKLE",
        Color3.fromRGB(94, 67, 184)
    )

    local moduleListLabel = makeLabel(
        mainFrame,
        "Modül listesi için LİSTE düğmesine bas.",
        22,
        10,
        false
    )
    moduleListLabel.TextColor3 = Color3.fromRGB(139, 148, 169)
    moduleListLabel.TextTruncate = Enum.TextTruncate.AtEnd
    moduleListLabel.LayoutOrder = 5

    -----------------------------------------------------------------
    -- PREVIEW
    -----------------------------------------------------------------

    local previewCard = Instance.new("Frame")
    previewCard.Size = UDim2.new(1, 0, 0, 180)
    previewCard.BackgroundColor3 = Color3.fromRGB(27, 31, 40)
    previewCard.BorderSizePixel = 0
    previewCard.LayoutOrder = 6
    previewCard.Parent = mainFrame
    round(previewCard, 9)
    addStroke(previewCard)

    local previewCaption = Instance.new("TextLabel")
    previewCaption.Position = UDim2.fromOffset(9, 5)
    previewCaption.Size = UDim2.new(1, -18, 0, 18)
    previewCaption.BackgroundTransparency = 1
    previewCaption.Text = "SUNUCUDAN YÜKLENEN ÇIKTI ÖNİZLEMESİ"
    previewCaption.TextColor3 = Color3.fromRGB(163, 172, 194)
    previewCaption.TextSize = 10
    previewCaption.Font = Enum.Font.GothamBold
    previewCaption.TextXAlignment = Enum.TextXAlignment.Left
    previewCaption.Parent = previewCard

    local previewBackground = Instance.new("Frame")
    previewBackground.Position = UDim2.fromOffset(8, 27)
    previewBackground.Size = UDim2.new(1, -16, 1, -35)
    previewBackground.BackgroundColor3 = Color3.fromRGB(40, 44, 54)
    previewBackground.BorderSizePixel = 0
    previewBackground.Parent = previewCard
    round(previewBackground, 7)

    local previewLabel = Instance.new("ImageLabel")
    previewLabel.Size = UDim2.fromScale(1, 1)
    previewLabel.BackgroundTransparency = 1
    previewLabel.ScaleType = Enum.ScaleType.Fit
    previewLabel.ResampleMode = Enum.ResamplerMode.Pixelated
    previewLabel.Parent = previewBackground
    round(previewLabel, 7)

    local previewEmpty = Instance.new("TextLabel")
    previewEmpty.AnchorPoint = Vector2.new(0.5, 0.5)
    previewEmpty.Position = UDim2.fromScale(0.5, 0.5)
    previewEmpty.Size = UDim2.new(1, -16, 0, 38)
    previewEmpty.BackgroundTransparency = 1
    previewEmpty.Text = "Henüz belge yüklenmedi"
    previewEmpty.TextColor3 = Color3.fromRGB(116, 125, 145)
    previewEmpty.TextSize = 11
    previewEmpty.Font = Enum.Font.Gotham
    previewEmpty.Parent = previewBackground

    -----------------------------------------------------------------
    -- SETTINGS
    -----------------------------------------------------------------

    local settingsRow = Instance.new("Frame")
    settingsRow.Size = UDim2.new(1, 0, 0, 58)
    settingsRow.BackgroundTransparency = 1
    settingsRow.LayoutOrder = 7
    settingsRow.Parent = mainFrame

    local settingsLayout = Instance.new("UIListLayout")
    settingsLayout.FillDirection = Enum.FillDirection.Horizontal
    settingsLayout.Padding = UDim.new(0, 7)
    settingsLayout.Parent = settingsRow

    local function makeSetting(
        captionText: string,
        defaultText: string
    ): TextBox
        local holder = Instance.new("Frame")
        holder.Size = UDim2.new(1 / 3, -5, 1, 0)
        holder.BackgroundTransparency = 1
        holder.Parent = settingsRow

        local caption = Instance.new("TextLabel")
        caption.Size = UDim2.new(1, 0, 0, 17)
        caption.BackgroundTransparency = 1
        caption.Text = captionText
        caption.TextColor3 = Color3.fromRGB(150, 159, 180)
        caption.TextSize = 9
        caption.Font = Enum.Font.GothamMedium
        caption.TextXAlignment = Enum.TextXAlignment.Left
        caption.Parent = holder

        local inputHolder = Instance.new("Frame")
        inputHolder.Position = UDim2.fromOffset(0, 20)
        inputHolder.Size = UDim2.new(1, 0, 0, 36)
        inputHolder.BackgroundTransparency = 1
        inputHolder.Parent = holder

        return makeInput(inputHolder, "", defaultText)
    end

    local paintSpeedBox = makeSetting(
        "Boyama piksel/sn",
        tostring(Config.Drawing.PixelsPerSecond)
    )
    local travelSpeedBox = makeSetting(
        "Hareket piksel/sn",
        tostring(Config.Drawing.TravelPixelsPerSecond)
    )
    local segmentBox = makeSetting(
        "Ağ segmenti",
        tostring(Config.Drawing.PixelsPerSegment)
    )

    -----------------------------------------------------------------
    -- AREA / TOOL / CONTROLS
    -----------------------------------------------------------------

    local selectHolder = Instance.new("Frame")
    selectHolder.Size = UDim2.new(1, 0, 0, 39)
    selectHolder.BackgroundTransparency = 1
    selectHolder.LayoutOrder = 8
    selectHolder.Parent = mainFrame

    local selectButton = makeButton(
        selectHolder,
        "ÇİZİM ALANINI SEÇ",
        Color3.fromRGB(101, 67, 201)
    )

    local sprayFrame = Instance.new("Frame")
    sprayFrame.Size = UDim2.new(1, 0, 0, 52)
    sprayFrame.BackgroundColor3 = Color3.fromRGB(27, 31, 40)
    sprayFrame.BorderSizePixel = 0
    sprayFrame.LayoutOrder = 9
    sprayFrame.Parent = mainFrame
    round(sprayFrame, 8)
    addStroke(sprayFrame)

    local swatch = Instance.new("Frame")
    swatch.Position = UDim2.fromOffset(9, 9)
    swatch.Size = UDim2.fromOffset(34, 34)
    swatch.BackgroundColor3 = Color3.new(1, 1, 1)
    swatch.BorderSizePixel = 0
    swatch.Parent = sprayFrame
    round(swatch, 6)
    addStroke(swatch, Color3.fromRGB(230, 230, 230))

    local sprayTitle = Instance.new("TextLabel")
    sprayTitle.Position = UDim2.fromOffset(52, 5)
    sprayTitle.Size = UDim2.new(1, -62, 0, 20)
    sprayTitle.BackgroundTransparency = 1
    sprayTitle.Text = "Spray kuşanılmadı • Klavyeden 1"
    sprayTitle.TextColor3 = Color3.fromRGB(235, 239, 249)
    sprayTitle.TextSize = 11
    sprayTitle.Font = Enum.Font.GothamBold
    sprayTitle.TextXAlignment = Enum.TextXAlignment.Left
    sprayTitle.Parent = sprayFrame

    local sprayDetail = Instance.new("TextLabel")
    sprayDetail.Position = UDim2.fromOffset(52, 25)
    sprayDetail.Size = UDim2.new(1, -62, 0, 18)
    sprayDetail.BackgroundTransparency = 1
    sprayDetail.Text = "HEX #FFFFFF • Fırça 0.100 stud"
    sprayDetail.TextColor3 = Color3.fromRGB(149, 158, 179)
    sprayDetail.TextSize = 10
    sprayDetail.Font = Enum.Font.Gotham
    sprayDetail.TextXAlignment = Enum.TextXAlignment.Left
    sprayDetail.Parent = sprayFrame

    local controls = Instance.new("Frame")
    controls.Size = UDim2.new(1, 0, 0, 39)
    controls.BackgroundTransparency = 1
    controls.LayoutOrder = 10
    controls.Parent = mainFrame

    local controlsLayout = Instance.new("UIListLayout")
    controlsLayout.FillDirection = Enum.FillDirection.Horizontal
    controlsLayout.Padding = UDim.new(0, 6)
    controlsLayout.Parent = controls

    local startHolder = Instance.new("Frame")
    startHolder.Size = UDim2.new(0.38, -4, 1, 0)
    startHolder.BackgroundTransparency = 1
    startHolder.Parent = controls

    local startButton = makeButton(
        startHolder,
        "BAŞLAT",
        Color3.fromRGB(39, 154, 99)
    )

    local pauseHolder = Instance.new("Frame")
    pauseHolder.Size = UDim2.new(0.32, -4, 1, 0)
    pauseHolder.BackgroundTransparency = 1
    pauseHolder.Parent = controls

    local pauseButton = makeButton(
        pauseHolder,
        "DURAKLAT",
        Color3.fromRGB(202, 137, 46)
    )

    local stopHolder = Instance.new("Frame")
    stopHolder.Size = UDim2.new(0.30, -4, 1, 0)
    stopHolder.BackgroundTransparency = 1
    stopHolder.Parent = controls

    local stopButton = makeButton(
        stopHolder,
        "DURDUR",
        Color3.fromRGB(192, 67, 74)
    )

    local progressBack = Instance.new("Frame")
    progressBack.Size = UDim2.new(1, 0, 0, 10)
    progressBack.BackgroundColor3 = Color3.fromRGB(34, 39, 49)
    progressBack.BorderSizePixel = 0
    progressBack.LayoutOrder = 11
    progressBack.Parent = mainFrame
    round(progressBack, 99)

    local progressFill = Instance.new("Frame")
    progressFill.Size = UDim2.fromScale(0, 1)
    progressFill.BackgroundColor3 = Color3.fromRGB(52, 185, 128)
    progressFill.BorderSizePixel = 0
    progressFill.Parent = progressBack
    round(progressFill, 99)

    local statsLabel = makeLabel(
        mainFrame,
        "Belge yüklenmedi.",
        19,
        10,
        false
    )
    statsLabel.TextColor3 = Color3.fromRGB(143, 152, 173)
    statsLabel.LayoutOrder = 12

    local statusLabel = makeLabel(
        mainFrame,
        "Importer ile modül oluştur veya GitHub raw JSON yükle.",
        38,
        11,
        false
    )
    statusLabel.TextWrapped = true
    statusLabel.TextColor3 = Color3.fromRGB(168, 177, 198)
    statusLabel.LayoutOrder = 13

    local reopenButton = Instance.new("TextButton")
    reopenButton.Position = UDim2.fromOffset(18, 82)
    reopenButton.Size = UDim2.fromOffset(52, 52)
    reopenButton.BackgroundColor3 = Color3.fromRGB(45, 112, 211)
    reopenButton.BorderSizePixel = 0
    reopenButton.Text = "SPR"
    reopenButton.TextColor3 = Color3.new(1, 1, 1)
    reopenButton.TextSize = 11
    reopenButton.Font = Enum.Font.GothamBold
    reopenButton.Visible = Config.UI.StartHidden
    reopenButton.Parent = gui
    round(reopenButton, 99)

    -----------------------------------------------------------------
    -- UI STATE
    -----------------------------------------------------------------

    local function setStatus(text: string, isError: boolean?)
        statusLabel.Text = text
        statusLabel.TextColor3 = isError
            and Color3.fromRGB(255, 119, 127)
            or Color3.fromRGB(168, 177, 198)
    end

    local function setProgress(value: number)
        value = math.clamp(value, 0, 1)
        TweenService:Create(progressFill, TweenInfo.new(0.07), {
            Size = UDim2.fromScale(value, 1),
        }):Play()
    end

    local function setPanelVisible(visible: boolean)
        mainFrame.Visible = visible
        reopenButton.Visible = not visible
    end

    local function updateSprayHud()
        local color = Color3.new(1, 1, 1)
        pcall(function()
            color = Color3.fromHex(string.sub(currentHex, 2))
        end)

        swatch.BackgroundColor3 = color
        sprayTitle.Text = sprayEquipped
            and "Spray kuşanıldı • Slot 1"
            or "Spray kuşanılmadı • Klavyeden 1"
        sprayDetail.Text = string.format(
            "HEX %s • Fırça %.3f stud",
            currentHex,
            currentBrushSize
        )
    end

    hideButton.Activated:Connect(function()
        setPanelVisible(false)
    end)

    reopenButton.Activated:Connect(function()
        setPanelVisible(true)
    end)

    -----------------------------------------------------------------
    -- CANVAS RENDERERS
    -----------------------------------------------------------------

    local function destroyRenderer(sessionId: string)
        local renderer = renderers[sessionId]
        if not renderer then
            return
        end

        renderers[sessionId] = nil
        destroyEditable(renderer.Image)

        if renderer.SurfaceGui and renderer.SurfaceGui.Parent then
            renderer.SurfaceGui:Destroy()
        end
    end

    local function createRenderer(sessionId: string, payload: any)
        if type(payload) ~= "table" then
            return
        end

        local part = payload.canvasPart
        local width = tonumber(payload.width)
        local height = tonumber(payload.height)
        local palette = payload.palette

        if typeof(part) ~= "Instance"
            or not part:IsA("BasePart")
            or not width
            or not height
            or type(palette) ~= "table"
        then
            return
        end

        if renderers[sessionId] then
            return
        end

        width = math.floor(width)
        height = math.floor(height)

        local image = createEditable(width, height)
        if not image then
            return
        end

        local pixelBuffer = buffer.create(width * height * 4)
        image:WritePixelsBuffer(
            Vector2.zero,
            Vector2.new(width, height),
            pixelBuffer
        )

        local surfaceGui = Instance.new("SurfaceGui")
        surfaceGui.Name = `_AutoSpraySurface_{sessionId}`
        surfaceGui.Face = Enum.NormalId.Front
        surfaceGui.AlwaysOnTop = false
        surfaceGui.LightInfluence = 0
        surfaceGui.Brightness = 1
        surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
        surfaceGui.CanvasSize = Vector2.new(width, height)
        surfaceGui.Adornee = part
        surfaceGui.Parent = part

        local imageLabel = Instance.new("ImageLabel")
        imageLabel.Size = UDim2.fromScale(1, 1)
        imageLabel.BackgroundTransparency = 1
        imageLabel.BorderSizePixel = 0
        imageLabel.ScaleType = Enum.ScaleType.Stretch
        imageLabel.ResampleMode = Enum.ResamplerMode.Pixelated
        imageLabel.ImageContent = Content.fromObject(image)
        imageLabel.Parent = surfaceGui

        renderers[sessionId] = {
            Part = part,
            Width = width,
            Height = height,
            Palette = palette,
            PaletteBytes = paletteBytes(palette),
            PixelBuffer = pixelBuffer,
            Image = image,
            SurfaceGui = surfaceGui,
            ImageLabel = imageLabel,
        }
    end

    local function applyRendererSegments(
        sessionId: string,
        segmentBuffer: buffer
    )
        local renderer = renderers[sessionId]
        if not renderer then
            return
        end

        local segmentCount =
            buffer.len(segmentBuffer) / StrokeCodec.STROKE_BYTES

        for index = 1, segmentCount do
            local y, xStart, xEnd, paletteIndex =
                StrokeCodec.ReadStroke(segmentBuffer, index)

            local color = renderer.PaletteBytes[paletteIndex + 1]
            if color
                and y < renderer.Height
                and xStart < renderer.Width
                and xEnd < renderer.Width
            then
                local minimumX = math.min(xStart, xEnd)
                local maximumX = math.max(xStart, xEnd)
                local length = maximumX - minimumX + 1
                local rowBuffer = buffer.create(length * 4)

                for pixelIndex = 0, length - 1 do
                    local rowOffset = pixelIndex * 4
                    buffer.writeu8(rowBuffer, rowOffset, color[1])
                    buffer.writeu8(rowBuffer, rowOffset + 1, color[2])
                    buffer.writeu8(rowBuffer, rowOffset + 2, color[3])
                    buffer.writeu8(rowBuffer, rowOffset + 3, color[4])

                    local fullOffset =
                        (y * renderer.Width + minimumX + pixelIndex) * 4
                    buffer.writeu8(renderer.PixelBuffer, fullOffset, color[1])
                    buffer.writeu8(renderer.PixelBuffer, fullOffset + 1, color[2])
                    buffer.writeu8(renderer.PixelBuffer, fullOffset + 2, color[3])
                    buffer.writeu8(renderer.PixelBuffer, fullOffset + 3, color[4])
                end

                renderer.Image:WritePixelsBuffer(
                    Vector2.new(minimumX, y),
                    Vector2.new(length, 1),
                    rowBuffer
                )
            end
        end
    end

    local function applySnapshot(
        sessionId: string,
        yStart: number,
        rowCount: number,
        chunk: buffer
    )
        local renderer = renderers[sessionId]
        if not renderer then
            return
        end

        local expected = renderer.Width * rowCount * 4
        if buffer.len(chunk) ~= expected then
            return
        end

        buffer.copy(
            renderer.PixelBuffer,
            yStart * renderer.Width * 4,
            chunk,
            0,
            expected
        )

        renderer.Image:WritePixelsBuffer(
            Vector2.new(0, yStart),
            Vector2.new(renderer.Width, rowCount),
            chunk
        )
    end

    -----------------------------------------------------------------
    -- REALISTIC SPRAY VFX
    -----------------------------------------------------------------

    local function findSprayTool(userId: number): Tool?
        local targetPlayer = Players:GetPlayerByUserId(userId)
        local character = targetPlayer and targetPlayer.Character
        if not character then
            return nil
        end

        local tool = character:FindFirstChild("AutoSprayCan")
        if tool and tool:IsA("Tool") then
            return tool
        end

        return nil
    end

    local function destroySprayVfx(userId: number)
        local vfx = sprayVfx[userId]
        if not vfx then
            return
        end

        sprayVfx[userId] = nil

        if vfx.Beam and vfx.Beam.Parent then
            vfx.Beam:Destroy()
        end
        if vfx.Target and vfx.Target.Parent then
            vfx.Target:Destroy()
        end
    end

    local function ensureSprayVfx(userId: number): { [string]: any }?
        local existing = sprayVfx[userId]
        if existing
            and existing.Target.Parent
            and existing.Beam.Parent
        then
            return existing
        end

        destroySprayVfx(userId)

        local tool = findSprayTool(userId)
        if not tool then
            return nil
        end

        local handle = tool:FindFirstChild("Handle")
        local nozzle = handle and handle:FindFirstChild("Nozzle")

        if not handle
            or not handle:IsA("BasePart")
            or not nozzle
            or not nozzle:IsA("Attachment")
        then
            return nil
        end

        local target = Instance.new("Part")
        target.Name = `_SprayTarget_{userId}`
        target.Anchored = true
        target.CanCollide = false
        target.CanTouch = false
        target.CanQuery = false
        target.CastShadow = false
        target.Transparency = 1
        target.Size = Vector3.new(0.05, 0.05, 0.05)
        target.Parent = localVfxFolder

        local targetAttachment = Instance.new("Attachment")
        targetAttachment.Name = "Target"
        targetAttachment.Parent = target

        local beam = Instance.new("Beam")
        beam.Name = "_AutoSprayBeam"
        beam.Attachment0 = nozzle
        beam.Attachment1 = targetAttachment
        beam.Enabled = false
        beam.FaceCamera = true
        beam.Width0 = Config.Realistic.BeamWidth
        beam.Width1 = Config.Realistic.BeamWidth * 0.45
        beam.LightEmission = 0.35
        beam.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.35),
            NumberSequenceKeypoint.new(1, 0.78),
        })
        beam.Parent = handle

        local mist = Instance.new("ParticleEmitter")
        mist.Name = "_AutoSprayImpactMist"
        mist.Enabled = false
        mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
        mist.Rate = 75
        mist.Lifetime = NumberRange.new(0.08, 0.18)
        mist.Speed = NumberRange.new(0.08, 0.28)
        mist.SpreadAngle = Vector2.new(180, 180)
        mist.LightEmission = 0.25
        mist.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.07),
            NumberSequenceKeypoint.new(1, 0.015),
        })
        mist.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.2),
            NumberSequenceKeypoint.new(1, 1),
        })
        mist.Parent = targetAttachment

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "_AutoSprayReticle"
        billboard.AlwaysOnTop = true
        billboard.Size = UDim2.fromOffset(14, 14)
        billboard.Enabled = false
        billboard.Parent = target

        local dot = Instance.new("Frame")
        dot.AnchorPoint = Vector2.new(0.5, 0.5)
        dot.Position = UDim2.fromScale(0.5, 0.5)
        dot.Size = UDim2.fromOffset(8, 8)
        dot.BackgroundColor3 = Color3.new(1, 1, 1)
        dot.BorderSizePixel = 0
        dot.Parent = billboard
        round(dot, 99)

        local vfx = {
            Tool = tool,
            Handle = handle,
            Nozzle = nozzle,
            Target = target,
            TargetAttachment = targetAttachment,
            Beam = beam,
            Mist = mist,
            Billboard = billboard,
            Dot = dot,
        }

        sprayVfx[userId] = vfx
        return vfx
    end

    local function setSprayPoseLocal(
        userId: number,
        position: Vector3,
        color: Color3,
        active: boolean
    )
        local vfx = ensureSprayVfx(userId)
        if not vfx then
            return
        end

        vfx.Target.Position = position
        vfx.Beam.Color = ColorSequence.new(color)
        vfx.Mist.Color = ColorSequence.new(color)
        vfx.Dot.BackgroundColor3 = color

        vfx.Beam.Enabled = active and Config.Realistic.Enabled
        vfx.Mist.Enabled = active and Config.Realistic.Enabled
        vfx.Billboard.Enabled = active

        local toolEmitter = vfx.Nozzle:FindFirstChild("SprayMist")
        if toolEmitter and toolEmitter:IsA("ParticleEmitter") then
            toolEmitter.Color = ColorSequence.new(color)
            toolEmitter.Enabled = active and Config.Realistic.Enabled
        end

        local sound = vfx.Handle:FindFirstChild("SprayLoop")
        if sound and sound:IsA("Sound") then
            if active and not sound.IsPlaying then
                sound:Play()
            elseif not active and sound.IsPlaying then
                sound:Stop()
            end
        end
    end

    -----------------------------------------------------------------
    -- CANVAS EVENTS
    -----------------------------------------------------------------

    CanvasEvent.OnClientEvent:Connect(function(action: any, ...: any)
        if action == "CanvasCreate" then
            local sessionId, payload = ...
            if type(sessionId) == "string" then
                createRenderer(sessionId, payload)
            end
        elseif action == "CanvasSegments" then
            local sessionId, segmentBuffer = ...
            if type(sessionId) == "string"
                and typeof(segmentBuffer) == "buffer"
            then
                applyRendererSegments(sessionId, segmentBuffer)
            end
        elseif action == "CanvasSnapshot" then
            local sessionId, yStart, rowCount, chunk = ...
            if type(sessionId) == "string"
                and type(yStart) == "number"
                and type(rowCount) == "number"
                and typeof(chunk) == "buffer"
            then
                applySnapshot(sessionId, yStart, rowCount, chunk)
            end
        elseif action == "CanvasRemove" then
            local sessionId = ...
            if type(sessionId) == "string" then
                destroyRenderer(sessionId)
            end
        elseif action == "SprayPose" then
            local userId, position, color, active = ...
            if type(userId) == "number"
                and typeof(position) == "Vector3"
                and typeof(color) == "Color3"
                and type(active) == "boolean"
            then
                setSprayPoseLocal(userId, position, color, active)
            end
        end
    end)

    -----------------------------------------------------------------
    -- DOCUMENT PREVIEW
    -----------------------------------------------------------------

    local function loadPreview(metadata: { [string]: any })
        loadingDocument = true
        setProgress(0)
        setStatus("Belge stroke verisi sunucudan alınıyor...")

        destroyEditable(previewImage)
        previewImage = createEditable(metadata.width, metadata.height)
        previewBuffer = buffer.create(metadata.width * metadata.height * 4)

        if not previewImage or not previewBuffer then
            loadingDocument = false
            setStatus("Önizleme EditableImage oluşturulamadı.", true)
            return
        end

        previewImage:WritePixelsBuffer(
            Vector2.zero,
            Vector2.new(metadata.width, metadata.height),
            previewBuffer
        )
        previewLabel.ImageContent = Content.fromObject(previewImage)
        previewEmpty.Visible = false

        local colors = paletteBytes(metadata.palette)
        local startIndex = 1
        local chunkSize = Config.DocumentChunkStrokes
        local chunksSinceWrite = 0

        while startIndex <= metadata.strokeCount do
            local ok, response = invoke(
                "GetDocumentChunk",
                metadata.documentId,
                startIndex,
                chunkSize
            )

            if not ok then
                loadingDocument = false
                setStatus(`Önizleme chunk hatası: {tostring(response)}`, true)
                return
            end

            local chunk = response.data
            local count = response.count

            if typeof(chunk) ~= "buffer" or count <= 0 then
                break
            end

            for index = 1, count do
                local y, xStart, xEnd, paletteIndex =
                    StrokeCodec.ReadStroke(chunk, index)
                local color = colors[paletteIndex + 1]

                if color then
                    local step = xEnd >= xStart and 1 or -1
                    local x = xStart

                    while true do
                        local offset = (y * metadata.width + x) * 4
                        buffer.writeu8(previewBuffer, offset, color[1])
                        buffer.writeu8(previewBuffer, offset + 1, color[2])
                        buffer.writeu8(previewBuffer, offset + 2, color[3])
                        buffer.writeu8(previewBuffer, offset + 3, color[4])

                        if x == xEnd then
                            break
                        end
                        x += step
                    end
                end
            end

            startIndex += count
            chunksSinceWrite += 1

            if chunksSinceWrite >= 5
                or startIndex > metadata.strokeCount
            then
                previewImage:WritePixelsBuffer(
                    Vector2.zero,
                    Vector2.new(metadata.width, metadata.height),
                    previewBuffer
                )
                chunksSinceWrite = 0
                task.wait()
            end

            setProgress(
                math.clamp(
                    (startIndex - 1) / math.max(metadata.strokeCount, 1),
                    0,
                    1
                )
            )
        end

        previewImage:WritePixelsBuffer(
            Vector2.zero,
            Vector2.new(metadata.width, metadata.height),
            previewBuffer
        )

        currentDocument = metadata
        currentDocument.PaletteBytes = colors
        loadingDocument = false
        setProgress(1)

        statsLabel.Text = string.format(
            "%s • %dx%d • %d renk • %d stroke",
            metadata.name,
            metadata.width,
            metadata.height,
            #metadata.palette,
            metadata.strokeCount
        )

        if metadata.recommendedWarning then
            setStatus(
                "Belge hazır. 256 üzeri çözünürlük çalışır fakat çizim ve ağ süresi ciddi artar."
            )
        else
            setStatus("Belge hazır. Şimdi çizim alanını seç.")
        end
    end

    local function handleLoadedDocument(metadata: any)
        if type(metadata) ~= "table" then
            setStatus("Sunucudan geçersiz belge bilgisi geldi.", true)
            return
        end

        task.spawn(loadPreview, metadata)
    end

    moduleLoadButton.Activated:Connect(function()
        if loadingDocument or drawState ~= "Idle" then
            setStatus("Şu anda yeni belge yüklenemez.", true)
            return
        end

        setStatus("Modül sunucuda açılıyor...")
        local ok, result = invoke("LoadModule", moduleBox.Text)

        if not ok then
            setStatus(`Modül yüklenemedi: {tostring(result)}`, true)
            return
        end

        handleLoadedDocument(result)
    end)

    urlLoadButton.Activated:Connect(function()
        if loadingDocument or drawState ~= "Idle" then
            setStatus("Şu anda yeni belge yüklenemez.", true)
            return
        end

        setStatus("GitHub raw JSON sunucudan indiriliyor...")
        local ok, result = invoke("LoadUrl", urlBox.Text)

        if not ok then
            setStatus(`URL yüklenemedi: {tostring(result)}`, true)
            return
        end

        handleLoadedDocument(result)
    end)

    refreshButton.Activated:Connect(function()
        local ok, result = invoke("ListModules")

        if not ok then
            moduleListLabel.Text = `Liste alınamadı: {tostring(result)}`
            return
        end

        if #result == 0 then
            moduleListLabel.Text =
                "ServerStorage/AutoSprayImages içinde ModuleScript yok."
        else
            moduleListLabel.Text =
                "Modüller: " .. table.concat(result, ", ")
        end
    end)

    -----------------------------------------------------------------
    -- SELECTION
    -----------------------------------------------------------------

    local function clearSelectionPreview()
        selectionFolder:ClearAllChildren()
    end

    local function makeSelectionPart(name: string): Part
        local part = Instance.new("Part")
        part.Name = name
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CastShadow = false
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(43, 211, 255)
        part.Transparency = 0.12
        part.Parent = selectionFolder
        return part
    end

    local function marker(position: Vector3, name: string)
        local part = makeSelectionPart(name)
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(0.14, 0.14, 0.14)
        part.Position = position
    end

    local function line(pointA: Vector3, pointB: Vector3, name: string)
        local distance = (pointB - pointA).Magnitude
        if distance < 0.001 then
            return
        end

        local part = makeSelectionPart(name)
        part.Size = Vector3.new(0.035, 0.035, distance)
        part.CFrame = CFrame.lookAt((pointA + pointB) / 2, pointB)
    end

    local function getSurfaceBasis(
        part: BasePart,
        normalWorld: Vector3
    ): (Vector3, Vector3)
        local localNormal = part.CFrame:VectorToObjectSpace(normalWorld)
        local x = math.abs(localNormal.X)
        local y = math.abs(localNormal.Y)
        local z = math.abs(localNormal.Z)

        local localU
        local localV

        if x >= y and x >= z then
            localU = localNormal.X >= 0
                and Vector3.new(0, 0, 1)
                or Vector3.new(0, 0, -1)
            localV = Vector3.new(0, 1, 0)
        elseif y >= x and y >= z then
            localU = Vector3.new(1, 0, 0)
            localV = localNormal.Y >= 0
                and Vector3.new(0, 0, 1)
                or Vector3.new(0, 0, -1)
        else
            localU = localNormal.Z >= 0
                and Vector3.new(-1, 0, 0)
                or Vector3.new(1, 0, 0)
            localV = Vector3.new(0, 1, 0)
        end

        return part.CFrame:VectorToWorldSpace(localU).Unit,
            part.CFrame:VectorToWorldSpace(localV).Unit
    end

    local function raycastMouse(): RaycastResult?
        camera = Workspace.CurrentCamera
        if not camera then
            return nil
        end

        local ray = mouse.UnitRay
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude

        local excluded = {
            selectionFolder,
            localVfxFolder,
        }

        local canvases = Workspace:FindFirstChild("AutoSprayCanvases")
        if canvases then
            table.insert(excluded, canvases)
        end

        if player.Character then
            table.insert(excluded, player.Character)
        end

        params.FilterDescendantsInstances = excluded
        params.IgnoreWater = true

        return Workspace:Raycast(
            ray.Origin,
            ray.Direction * 2000,
            params
        )
    end

    local function updateSelectionPreview()
        clearSelectionPreview()

        if not firstCorner or not surfaceNormal then
            return
        end

        local offset =
            surfaceNormal * Config.Drawing.SurfaceOffsetStuds

        marker(firstCorner + offset, "FirstCorner")

        if not secondCorner or not surfaceAxisU or not surfaceAxisV then
            return
        end

        local delta = secondCorner - firstCorner
        local width = delta:Dot(surfaceAxisU)
        local height = delta:Dot(surfaceAxisV)

        local a = firstCorner + offset
        local b = firstCorner + surfaceAxisU * width + offset
        local c = firstCorner + surfaceAxisV * height + offset
        local d = firstCorner
            + surfaceAxisU * width
            + surfaceAxisV * height
            + offset

        marker(d, "SecondCorner")
        line(a, b, "Top")
        line(a, c, "Left")
        line(b, d, "Right")
        line(c, d, "Bottom")
    end

    local function beginSelection()
        if drawState ~= "Idle" then
            setStatus("Çizim sırasında alan değiştirilemez.", true)
            return
        end

        if not currentDocument then
            setStatus("Önce bir belge yükle.", true)
            return
        end

        selectedPart = nil
        firstCorner = nil
        secondCorner = nil
        surfaceNormal = nil
        surfaceAxisU = nil
        surfaceAxisV = nil

        selecting = true
        selectionStage = 1
        clearSelectionPreview()

        setStatus("1/2: Çizimin ilk köşesine tıkla. ESC iptal.")
    end

    local function selectionClick()
        local hit = raycastMouse()
        if not hit or not hit.Instance:IsA("BasePart") then
            setStatus("Bir BasePart yüzeyine tıkla.", true)
            return
        end

        local part = hit.Instance :: BasePart

        if selectionStage == 1 then
            selectedPart = part
            firstCorner = hit.Position
            surfaceNormal = hit.Normal.Unit
            surfaceAxisU, surfaceAxisV =
                getSurfaceBasis(part, surfaceNormal)

            selectionStage = 2
            updateSelectionPreview()
            setStatus("2/2: Aynı yüzeyde karşı köşeye tıkla.")
            return
        end

        if not selectedPart
            or not firstCorner
            or not surfaceNormal
            or not surfaceAxisU
            or not surfaceAxisV
        then
            beginSelection()
            return
        end

        if part ~= selectedPart then
            setStatus("İkinci köşe aynı parçanın üzerinde olmalı.", true)
            return
        end

        if hit.Normal.Unit:Dot(surfaceNormal) < 0.96 then
            setStatus("İkinci köşe aynı yüzeyde olmalı.", true)
            return
        end

        local planeDistance =
            (hit.Position - firstCorner):Dot(surfaceNormal)
        local projected =
            hit.Position - surfaceNormal * planeDistance
        local delta = projected - firstCorner
        local width = delta:Dot(surfaceAxisU)
        local height = delta:Dot(surfaceAxisV)

        if math.abs(width) < 0.25 or math.abs(height) < 0.25 then
            setStatus("Seçilen alan çok küçük.", true)
            return
        end

        secondCorner = firstCorner
            + surfaceAxisU * width
            + surfaceAxisV * height

        selecting = false
        selectionStage = 0
        updateSelectionPreview()

        currentBrushSize = (
            math.abs(width) / currentDocument.width
            + math.abs(height) / currentDocument.height
        ) * 0.5 * Config.Drawing.BrushScale

        updateSprayHud()

        setStatus(string.format(
            "Alan hazır: %.2f × %.2f stud • otomatik fırça %.3f",
            math.abs(width),
            math.abs(height),
            currentBrushSize
        ))
    end

    selectButton.Activated:Connect(beginSelection)

    -----------------------------------------------------------------
    -- TOOL
    -----------------------------------------------------------------

    local function refreshToolState(): boolean
        local character = player.Character
        local tool = character and character:FindFirstChild("AutoSprayCan")
        sprayEquipped = tool ~= nil and tool:IsA("Tool")
        updateSprayHud()
        return sprayEquipped
    end

    local function equipSpray()
        ControlEvent:FireServer("EquipTool")

        task.delay(0.18, function()
            local character = player.Character
            local backpack = player:FindFirstChildOfClass("Backpack")
            local humanoid = character
                and character:FindFirstChildOfClass("Humanoid")

            if not character or not backpack or not humanoid then
                return
            end

            local tool = backpack:FindFirstChild("AutoSprayCan")
                or character:FindFirstChild("AutoSprayCan")

            if tool and tool:IsA("Tool") then
                if tool.Parent ~= character then
                    humanoid:EquipTool(tool)
                end

                task.wait()
                refreshToolState()
                ensureSprayVfx(player.UserId)
                setStatus("Spray kuşanıldı. Başlatabilirsin.")
            else
                setStatus("Sunucu Spray Tool oluşturamadı.", true)
            end
        end)
    end

    -----------------------------------------------------------------
    -- DRAWING HELPERS
    -----------------------------------------------------------------

    local lastPoseSentAt = 0

    local function sendPose(
        position: Vector3,
        color: Color3,
        active: boolean,
        force: boolean?
    )
        setSprayPoseLocal(
            player.UserId,
            position,
            color,
            active
        )

        local now = os.clock()
        if force
            or now - lastPoseSentAt >= Config.Realistic.PoseSendInterval
        then
            lastPoseSentAt = now
            ControlEvent:FireServer(
                "SprayPose",
                position,
                color,
                active
            )
        end
    end

    local function waitWhilePaused(): boolean
        while drawState == "Paused" do
            RunService.Heartbeat:Wait()
        end

        return drawState ~= "Stopping"
    end

    local function animateTarget(
        fromPosition: Vector3,
        toPosition: Vector3,
        duration: number,
        color: Color3,
        active: boolean
    ): boolean
        duration = math.max(duration, 0)

        if duration <= 0.001 then
            sendPose(toPosition, color, active, true)
            return drawState ~= "Stopping"
        end

        local startedAt = os.clock()

        while true do
            if not waitWhilePaused() then
                return false
            end

            local alpha = math.clamp(
                (os.clock() - startedAt) / duration,
                0,
                1
            )

            local basePosition = fromPosition:Lerp(toPosition, alpha)
            local jitter = Vector3.zero

            if active
                and Config.Realistic.Enabled
                and Config.Realistic.JitterStuds > 0
                and surfaceAxisU
                and surfaceAxisV
            then
                jitter = surfaceAxisU
                    * random:NextNumber(
                        -Config.Realistic.JitterStuds,
                        Config.Realistic.JitterStuds
                    )
                    + surfaceAxisV
                    * random:NextNumber(
                        -Config.Realistic.JitterStuds,
                        Config.Realistic.JitterStuds
                    )
            end

            sendPose(basePosition + jitter, color, active, alpha >= 1)

            if alpha >= 1 then
                break
            end

            RunService.Heartbeat:Wait()
        end

        return drawState ~= "Stopping"
    end

    local function encodeSegmentBatch(segments: { { number } }): buffer
        local output = buffer.create(
            #segments * StrokeCodec.STROKE_BYTES
        )

        for index, segment in ipairs(segments) do
            local offset = (index - 1) * StrokeCodec.STROKE_BYTES
            buffer.writeu16(output, offset, segment[1])
            buffer.writeu16(output, offset + 2, segment[2])
            buffer.writeu16(output, offset + 4, segment[3])
            buffer.writeu8(output, offset + 6, segment[4])
        end

        return output
    end

    local function runDrawing()
        if drawState ~= "Idle" then
            setStatus("Zaten aktif çizim var.", true)
            return
        end

        if loadingDocument or not currentDocument then
            setStatus("Önce belge yükle ve önizlemenin bitmesini bekle.", true)
            return
        end

        if not selectedPart
            or not firstCorner
            or not secondCorner
            or not surfaceNormal
            or not surfaceAxisU
            or not surfaceAxisV
        then
            setStatus("Önce çizim alanını seç.", true)
            return
        end

        if not refreshToolState() then
            setStatus("Önce klavyeden 1'e basıp Spray'i kuşan.", true)
            return
        end

        local delta = secondCorner - firstCorner
        local signedWidth = delta:Dot(surfaceAxisU)
        local signedHeight = delta:Dot(surfaceAxisV)
        local widthStuds = math.abs(signedWidth)
        local heightStuds = math.abs(signedHeight)
        local center = (firstCorner + secondCorner) * 0.5
            + surfaceNormal * Config.Drawing.SurfaceOffsetStuds

        local canvasCFrame = CFrame.fromMatrix(
            center,
            surfaceAxisU,
            surfaceAxisV,
            -surfaceNormal
        )

        local startOk, startResult = invoke(
            "StartCanvas",
            currentDocument.documentId,
            {
                target = selectedPart,
                canvasCFrame = canvasCFrame,
                widthStuds = widthStuds,
                heightStuds = heightStuds,
            }
        )

        if not startOk then
            setStatus(`Tuval başlatılamadı: {tostring(startResult)}`, true)
            return
        end

        currentSessionId = startResult.sessionId
        drawState = "Running"
        pauseButton.Text = "DURAKLAT"
        setProgress(0)

        local paintSpeed = clampInteger(
            paintSpeedBox.Text,
            Config.Drawing.PixelsPerSecond,
            5,
            20_000
        )
        local travelSpeed = clampInteger(
            travelSpeedBox.Text,
            Config.Drawing.TravelPixelsPerSecond,
            20,
            50_000
        )
        local pixelsPerSegment = clampInteger(
            segmentBox.Text,
            Config.Drawing.PixelsPerSegment,
            1,
            64
        )

        paintSpeedBox.Text = tostring(paintSpeed)
        travelSpeedBox.Text = tostring(travelSpeed)
        segmentBox.Text = tostring(pixelsPerSegment)

        currentBrushSize = (
            widthStuds / currentDocument.width
            + heightStuds / currentDocument.height
        ) * 0.5 * Config.Drawing.BrushScale
        updateSprayHud()

        local flipX = signedWidth < 0
        local flipY = signedHeight > 0

        local function pixelWorld(x: number, y: number): Vector3
            local tx = (x + 0.5) / currentDocument.width
            local ty = (y + 0.5) / currentDocument.height

            return firstCorner
                + surfaceAxisU * (signedWidth * tx)
                + surfaceAxisV * (signedHeight * ty)
                + surfaceNormal * Config.Drawing.SurfaceOffsetStuds
        end

        local function mapX(x: number): number
            return flipX
                and currentDocument.width - 1 - x
                or x
        end

        local function mapY(y: number): number
            return flipY
                and currentDocument.height - 1 - y
                or y
        end

        local segmentQueue = {}
        local lastFlush = os.clock()

        local function flushSegments(force: boolean?)
            if #segmentQueue == 0 or not currentSessionId then
                return
            end

            local now = os.clock()
            if not force
                and #segmentQueue < Config.MaxSegmentsPerEvent
                and now - lastFlush
                    < Config.Drawing.NetworkFlushInterval
            then
                return
            end

            local payload = encodeSegmentBatch(segmentQueue)
            ControlEvent:FireServer(
                "PaintSegments",
                currentSessionId,
                payload
            )

            table.clear(segmentQueue)
            lastFlush = now
        end

        local lastWorldPosition: Vector3? = nil
        local strokeIndex = 1
        local chunkSize = Config.DocumentChunkStrokes
        local colors = currentDocument.PaletteBytes

        while strokeIndex <= currentDocument.strokeCount do
            if drawState == "Stopping" then
                break
            end

            local chunkOk, response = invoke(
                "GetDocumentChunk",
                currentDocument.documentId,
                strokeIndex,
                chunkSize
            )

            if not chunkOk then
                drawState = "Stopping"
                setStatus(`Stroke chunk alınamadı: {tostring(response)}`, true)
                break
            end

            local chunk = response.data
            local count = response.count

            if typeof(chunk) ~= "buffer" or count <= 0 then
                break
            end

            for localIndex = 1, count do
                if drawState == "Stopping" then
                    break
                end

                if not waitWhilePaused() then
                    break
                end

                local y, xStart, xEnd, paletteIndex =
                    StrokeCodec.ReadStroke(chunk, localIndex)
                local rgba = colors[paletteIndex + 1]

                if rgba and rgba[4] > 0 then
                    local color = Color3.fromRGB(
                        rgba[1],
                        rgba[2],
                        rgba[3]
                    )

                    currentHex = rgbHex(
                        rgba[1],
                        rgba[2],
                        rgba[3]
                    )
                    updateSprayHud()

                    local startWorld = pixelWorld(xStart, y)

                    if lastWorldPosition then
                        local cellSize = math.max(
                            (
                                widthStuds / currentDocument.width
                                + heightStuds / currentDocument.height
                            ) * 0.5,
                            0.0001
                        )

                        local travelPixels =
                            (startWorld - lastWorldPosition).Magnitude
                            / cellSize
                        local travelDuration =
                            travelPixels / travelSpeed

                        sendPose(
                            lastWorldPosition,
                            color,
                            false,
                            true
                        )

                        if not animateTarget(
                            lastWorldPosition,
                            startWorld,
                            travelDuration,
                            color,
                            false
                        ) then
                            break
                        end
                    else
                        sendPose(startWorld, color, false, true)
                    end

                    local direction = xEnd >= xStart and 1 or -1
                    local currentX = xStart

                    while true do
                        if drawState == "Stopping"
                            or not waitWhilePaused()
                        then
                            break
                        end

                        local remaining =
                            math.abs(xEnd - currentX) + 1
                        local segmentLength =
                            math.min(pixelsPerSegment, remaining)
                        local nextX =
                            currentX
                            + direction * (segmentLength - 1)

                        local segmentStartWorld =
                            pixelWorld(currentX, y)
                        local segmentEndWorld =
                            pixelWorld(nextX, y)
                        local duration =
                            segmentLength / paintSpeed

                        if not animateTarget(
                            segmentStartWorld,
                            segmentEndWorld,
                            duration,
                            color,
                            true
                        ) then
                            break
                        end

                        table.insert(segmentQueue, {
                            mapY(y),
                            mapX(currentX),
                            mapX(nextX),
                            paletteIndex,
                        })
                        flushSegments(false)

                        lastWorldPosition = segmentEndWorld

                        if nextX == xEnd then
                            break
                        end

                        currentX = nextX + direction
                    end

                    if Config.Drawing.LiftBetweenStrokes
                        and lastWorldPosition
                    then
                        sendPose(
                            lastWorldPosition,
                            color,
                            false,
                            true
                        )
                    end
                end

                local globalStrokeIndex =
                    strokeIndex + localIndex - 1

                setProgress(
                    globalStrokeIndex
                        / math.max(currentDocument.strokeCount, 1)
                )

                if globalStrokeIndex % 20 == 0 then
                    setStatus(string.format(
                        "Çiziliyor... %d%% • %s • stroke %d/%d",
                        math.floor(
                            globalStrokeIndex
                                / math.max(
                                    currentDocument.strokeCount,
                                    1
                                )
                                * 100
                            + 0.5
                        ),
                        currentHex,
                        globalStrokeIndex,
                        currentDocument.strokeCount
                    ))
                end
            end

            strokeIndex += count
        end

        flushSegments(true)

        if lastWorldPosition then
            sendPose(
                lastWorldPosition,
                Color3.new(1, 1, 1),
                false,
                true
            )
        end

        if currentSessionId then
            ControlEvent:FireServer("Finish", currentSessionId)
        end

        local stopped = drawState == "Stopping"
        drawState = "Idle"
        pauseButton.Text = "DURAKLAT"
        currentSessionId = nil

        if stopped then
            setStatus("Çizim durduruldu; boyanan bölüm sunucuda kaldı.")
        else
            setProgress(1)
            setStatus("Çizim tamamlandı ve tüm oyunculara gösterildi.")
        end
    end

    -----------------------------------------------------------------
    -- BUTTONS / INPUT
    -----------------------------------------------------------------

    startButton.Activated:Connect(function()
        task.spawn(runDrawing)
    end)

    pauseButton.Activated:Connect(function()
        if drawState == "Running" then
            drawState = "Paused"
            pauseButton.Text = "DEVAM ET"
            setStatus("Çizim duraklatıldı.")
        elseif drawState == "Paused" then
            drawState = "Running"
            pauseButton.Text = "DURAKLAT"
            setStatus("Çizime devam ediliyor...")
        else
            setStatus("Duraklatılacak aktif çizim yok.", true)
        end
    end)

    stopButton.Activated:Connect(function()
        if drawState ~= "Running" and drawState ~= "Paused" then
            setStatus("Durdurulacak aktif çizim yok.", true)
            return
        end

        drawState = "Stopping"
        setStatus("Çizim güvenli biçimde durduruluyor...")
    end)

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if input.KeyCode == Enum.KeyCode.F6 then
            setPanelVisible(not mainFrame.Visible)
            return
        end

        if input.KeyCode == Enum.KeyCode.One then
            equipSpray()
            return
        end

        if input.KeyCode == Enum.KeyCode.Escape and selecting then
            selecting = false
            selectionStage = 0
            clearSelectionPreview()
            setStatus("Alan seçimi iptal edildi.")
            return
        end

        if gameProcessed then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseButton1
            and selecting
        then
            selectionClick()
        end
    end)

    player.CharacterAdded:Connect(function()
        sprayEquipped = false
        destroySprayVfx(player.UserId)
        updateSprayHud()
    end)

    -----------------------------------------------------------------
    -- PANEL DRAG
    -----------------------------------------------------------------

    do
        local dragging = false
        local dragStart = Vector2.zero
        local startPosition = mainFrame.Position

        titleRow.InputBegan:Connect(function(input)
            if input.UserInputType
                == Enum.UserInputType.MouseButton1
            then
                dragging = true
                dragStart = input.Position
                startPosition = mainFrame.Position
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging
                and input.UserInputType
                    == Enum.UserInputType.MouseMovement
            then
                local delta = input.Position - dragStart
                mainFrame.Position = UDim2.new(
                    startPosition.X.Scale,
                    startPosition.X.Offset + delta.X,
                    startPosition.Y.Scale,
                    startPosition.Y.Offset + delta.Y
                )
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType
                == Enum.UserInputType.MouseButton1
            then
                dragging = false
            end
        end)
    end

    -----------------------------------------------------------------
    -- READY
    -----------------------------------------------------------------

    updateSprayHud()
    setProgress(0)

    if bootGui.Parent then
        bootGui:Destroy()
    end

    print("[AutoSpray] Client ready.")
end

local ok, errorMessage = xpcall(main, function(message)
    return debug.traceback(tostring(message), 2)
end)

if not ok then
    warn("[AutoSpray] Client boot error:\n" .. tostring(errorMessage))

    if bootGui.Parent then
        bootLabel.Text =
            "AUTO SPRAY BAŞLATMA HATASI\nF9 konsolundaki kırmızı hatayı gönder."
        bootLabel.TextWrapped = true
        bootLabel.TextColor3 = Color3.fromRGB(255, 122, 130)
        bootLabel.Size = UDim2.fromOffset(540, 76)
    end
end
