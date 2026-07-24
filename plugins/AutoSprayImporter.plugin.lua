--!strict
-- AutoSpray Studio image importer.
-- Save this script as a Local Plugin.
--
-- Features:
--   * Imports PNG/JPG/JPEG/WEBP/BMP from the computer.
--   * Output resolution up to 1024×1024.
--   * Adaptive median-cut palette with up to 255 opaque colors.
--   * Optional Floyd-Steinberg dithering.
--   * Converts pixels to serpentine same-color strokes.
--   * Zstd + Base64 compact stroke document.
--   * Creates ServerStorage/AutoSprayImages/<Name> ModuleScript.
--   * Copies GitHub-ready JSON to the clipboard.

local StudioService = game:GetService("StudioService")
local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local MAX_OUTPUT_SIDE = 1024
local MAX_SOURCE_SIDE = 4096
local MAX_OPAQUE_COLORS = 255
local STROKE_BYTES = 7

---------------------------------------------------------------------
-- TOOLBAR / WIDGET
---------------------------------------------------------------------

local toolbar = plugin:CreateToolbar("Auto Spray")
local toolbarButton = toolbar:CreateButton(
    "AutoSprayImporter",
    "Import an image and create an AutoSpray stroke document",
    ""
)
toolbarButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(
    Enum.InitialDockState.Right,
    true,
    false,
    430,
    760,
    370,
    560
)

local widget
local widgetOk, widgetResult = pcall(function()
    return plugin:CreateDockWidgetPluginGuiAsync(
        "AutoSprayImporterFull",
        widgetInfo
    )
end)

if widgetOk then
    widget = widgetResult
else
    widget = plugin:CreateDockWidgetPluginGui(
        "AutoSprayImporterFull",
        widgetInfo
    )
end

widget.Title = "Auto Spray Importer"
widget.Enabled = false

---------------------------------------------------------------------
-- UI BUILDERS
---------------------------------------------------------------------

local root = Instance.new("Frame")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(21, 24, 31)
root.BorderSizePixel = 0
root.Parent = widget

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.PaddingTop = UDim.new(0, 12)
padding.PaddingBottom = UDim.new(0, 12)
padding.Parent = root

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = root

local function round(object: GuiObject, radius: number?)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 8)
    corner.Parent = object
end

local function addStroke(object: GuiObject)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(65, 74, 94)
    stroke.Transparency = 0.28
    stroke.Parent = object
end

local function makeLabel(
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
    label.TextWrapped = true
    label.Parent = root
    return label
end

local function makeInput(
    placeholder: string,
    text: string,
    height: number?
): TextBox
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, 0, 0, height or 38)
    box.BackgroundColor3 = Color3.fromRGB(31, 35, 45)
    box.BorderSizePixel = 0
    box.Text = text
    box.PlaceholderText = placeholder
    box.PlaceholderColor3 = Color3.fromRGB(122, 131, 151)
    box.TextColor3 = Color3.fromRGB(242, 245, 255)
    box.TextSize = 12
    box.Font = Enum.Font.Gotham
    box.ClearTextOnFocus = false
    box.Parent = root
    round(box, 8)
    addStroke(box)
    return box
end

local function makeButton(
    text: string,
    color: Color3,
    height: number?
): TextButton
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 0, height or 39)
    button.BackgroundColor3 = color
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = Color3.fromRGB(248, 250, 255)
    button.TextSize = 12
    button.Font = Enum.Font.GothamBold
    button.Parent = root
    round(button, 8)
    return button
end

local title = makeLabel("AUTO SPRAY IMAGE IMPORTER", 28, 16, true)
title.LayoutOrder = 1

local intro = makeLabel(
    "Yerel görseli adaptif palet ve dithering ile stroke belgesine dönüştürür. "
        .. "1024 çıktı mümkündür; fotoğraflarda 128–256 daha pratiktir.",
    48,
    10,
    false
)
intro.TextColor3 = Color3.fromRGB(155, 164, 185)
intro.LayoutOrder = 2

local selectButton = makeButton(
    "PC'DEN GÖRSEL SEÇ",
    Color3.fromRGB(46, 112, 211)
)
selectButton.LayoutOrder = 3

local nameBox = makeInput("Belge/modül adı", "MyImage")
nameBox.LayoutOrder = 4

local settingsRow = Instance.new("Frame")
settingsRow.Size = UDim2.new(1, 0, 0, 58)
settingsRow.BackgroundTransparency = 1
settingsRow.LayoutOrder = 5
settingsRow.Parent = root

local settingsLayout = Instance.new("UIListLayout")
settingsLayout.FillDirection = Enum.FillDirection.Horizontal
settingsLayout.Padding = UDim.new(0, 6)
settingsLayout.Parent = settingsRow

local function makeSmallSetting(
    captionText: string,
    defaultText: string
): TextBox
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(0.25, -5, 1, 0)
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

    local box = Instance.new("TextBox")
    box.Position = UDim2.fromOffset(0, 20)
    box.Size = UDim2.new(1, 0, 0, 36)
    box.BackgroundColor3 = Color3.fromRGB(31, 35, 45)
    box.BorderSizePixel = 0
    box.Text = defaultText
    box.TextColor3 = Color3.fromRGB(242, 245, 255)
    box.TextSize = 11
    box.Font = Enum.Font.Gotham
    box.ClearTextOnFocus = false
    box.Parent = holder
    round(box, 8)
    addStroke(box)
    return box
end

local widthBox = makeSmallSetting("Genişlik", "256")
local heightBox = makeSmallSetting("Yükseklik", "256")
local paletteBox = makeSmallSetting("Renk", "255")
local alphaBox = makeSmallSetting("Alfa", "24")

local optionsRow = Instance.new("Frame")
optionsRow.Size = UDim2.new(1, 0, 0, 38)
optionsRow.BackgroundTransparency = 1
optionsRow.LayoutOrder = 6
optionsRow.Parent = root

local ditherButton = Instance.new("TextButton")
ditherButton.Size = UDim2.new(0.5, -4, 1, 0)
ditherButton.BackgroundColor3 = Color3.fromRGB(44, 137, 102)
ditherButton.BorderSizePixel = 0
ditherButton.Text = "DITHERING: AÇIK"
ditherButton.TextColor3 = Color3.fromRGB(248, 250, 255)
ditherButton.TextSize = 11
ditherButton.Font = Enum.Font.GothamBold
ditherButton.Parent = optionsRow
round(ditherButton, 8)

local ratioButton = Instance.new("TextButton")
ratioButton.AnchorPoint = Vector2.new(1, 0)
ratioButton.Position = UDim2.fromScale(1, 0)
ratioButton.Size = UDim2.new(0.5, -4, 1, 0)
ratioButton.BackgroundColor3 = Color3.fromRGB(94, 67, 184)
ratioButton.BorderSizePixel = 0
ratioButton.Text = "ORAN KORU: AÇIK"
ratioButton.TextColor3 = Color3.fromRGB(248, 250, 255)
ratioButton.TextSize = 11
ratioButton.Font = Enum.Font.GothamBold
ratioButton.Parent = optionsRow
round(ratioButton, 8)

local processButton = makeButton(
    "ADAPTİF PALETLE DÖNÜŞTÜR",
    Color3.fromRGB(39, 154, 99)
)
processButton.LayoutOrder = 7
processButton.Active = false

local previewFrame = Instance.new("Frame")
previewFrame.Size = UDim2.new(1, 0, 0, 240)
previewFrame.BackgroundColor3 = Color3.fromRGB(29, 33, 42)
previewFrame.BorderSizePixel = 0
previewFrame.LayoutOrder = 8
previewFrame.Parent = root
round(previewFrame, 9)
addStroke(previewFrame)

local previewLabel = Instance.new("ImageLabel")
previewLabel.Position = UDim2.fromOffset(8, 8)
previewLabel.Size = UDim2.new(1, -16, 1, -16)
previewLabel.BackgroundTransparency = 1
previewLabel.ScaleType = Enum.ScaleType.Fit
previewLabel.ResampleMode = Enum.ResamplerMode.Pixelated
previewLabel.Parent = previewFrame
round(previewLabel, 7)

local outputRow = Instance.new("Frame")
outputRow.Size = UDim2.new(1, 0, 0, 40)
outputRow.BackgroundTransparency = 1
outputRow.LayoutOrder = 9
outputRow.Parent = root

local moduleButton = Instance.new("TextButton")
moduleButton.Size = UDim2.new(0.5, -4, 1, 0)
moduleButton.BackgroundColor3 = Color3.fromRGB(46, 112, 211)
moduleButton.BorderSizePixel = 0
moduleButton.Text = "MODÜL OLUŞTUR"
moduleButton.TextColor3 = Color3.fromRGB(248, 250, 255)
moduleButton.TextSize = 11
moduleButton.Font = Enum.Font.GothamBold
moduleButton.Active = false
moduleButton.Parent = outputRow
round(moduleButton, 8)

local copyButton = Instance.new("TextButton")
copyButton.AnchorPoint = Vector2.new(1, 0)
copyButton.Position = UDim2.fromScale(1, 0)
copyButton.Size = UDim2.new(0.5, -4, 1, 0)
copyButton.BackgroundColor3 = Color3.fromRGB(94, 67, 184)
copyButton.BorderSizePixel = 0
copyButton.Text = "GITHUB JSON KOPYALA"
copyButton.TextColor3 = Color3.fromRGB(248, 250, 255)
copyButton.TextSize = 11
copyButton.Font = Enum.Font.GothamBold
copyButton.Active = false
copyButton.Parent = outputRow
round(copyButton, 8)

local statusLabel = makeLabel(
    "Görsel bekleniyor.",
    70,
    10,
    false
)
statusLabel.TextColor3 = Color3.fromRGB(163, 172, 193)
statusLabel.LayoutOrder = 10

---------------------------------------------------------------------
-- STATE / BASIC HELPERS
---------------------------------------------------------------------

local selectedImage: EditableImage? = nil
local selectedName = "MyImage"
local processedImage: EditableImage? = nil
local processedDocument: { [string]: any }? = nil
local processedJson = ""
local processing = false
local ditheringEnabled = true
local preserveRatio = true

local function setStatus(text: string, isError: boolean?)
    statusLabel.Text = text
    statusLabel.TextColor3 = isError
        and Color3.fromRGB(255, 119, 127)
        or Color3.fromRGB(163, 172, 193)
end

local function clampInteger(
    box: TextBox,
    fallback: number,
    minimum: number,
    maximum: number
): number
    local value = tonumber(box.Text)
    if value == nil then
        value = fallback
    end

    value = math.clamp(
        math.floor(value + 0.5),
        minimum,
        maximum
    )
    box.Text = tostring(value)
    return value
end

local function sanitizeName(text: string): string
    local cleaned = string.gsub(text, "[^%w_%-]", "_")
    cleaned = string.gsub(cleaned, "_+", "_")
    cleaned = string.sub(cleaned, 1, 64)

    if cleaned == "" then
        cleaned = "AutoSprayImage"
    end

    if string.match(cleaned, "^%d") then
        cleaned = "Image_" .. cleaned
    end

    return cleaned
end

local function destroyEditable(image: EditableImage?)
    if image then
        pcall(function()
            image:Destroy()
        end)
    end
end

local function hexByte(value: number): string
    return string.format("%02X", math.clamp(math.floor(value + 0.5), 0, 255))
end

local function colorHex(
    red: number,
    green: number,
    blue: number,
    alpha: number
): string
    return hexByte(red)
        .. hexByte(green)
        .. hexByte(blue)
        .. hexByte(alpha)
end

local function clampByte(value: number): number
    return math.clamp(math.floor(value + 0.5), 0, 255)
end

---------------------------------------------------------------------
-- IMAGE IMPORT
---------------------------------------------------------------------

local function editableFromFile(file: Instance): (EditableImage?, string?)
    local attempts = {}

    table.insert(attempts, function()
        local temporaryId = (file :: any):GetTemporaryId()
        return AssetService:CreateEditableImageAsync(
            Content.fromUri(tostring(temporaryId))
        )
    end)

    table.insert(attempts, function()
        return AssetService:CreateEditableImageAsync(
            Content.fromObject(file)
        )
    end)

    for _, attempt in ipairs(attempts) do
        local ok, result = pcall(attempt)
        if ok and result then
            return result
        end
    end

    return nil, "Studio could not create an EditableImage from the selected file."
end

local function selectImage()
    if processing then
        return
    end

    setStatus("Dosya seçici açılıyor...")

    local file = StudioService:PromptImportFileAsync({
        "png",
        "jpg",
        "jpeg",
        "webp",
        "bmp",
    })

    if not file then
        setStatus("Dosya seçilmedi.", true)
        return
    end

    local image, imageError = editableFromFile(file)
    if not image then
        setStatus(imageError or "Görsel açılamadı.", true)
        return
    end

    local size = image.Size
    if size.X < 1
        or size.Y < 1
        or size.X > MAX_SOURCE_SIDE
        or size.Y > MAX_SOURCE_SIDE
    then
        image:Destroy()
        setStatus(
            `Kaynak boyutu desteklenmiyor: {size.X}x{size.Y}. Maksimum {MAX_SOURCE_SIDE}.`,
            true
        )
        return
    end

    destroyEditable(selectedImage)
    selectedImage = image

    selectedName = sanitizeName(file.Name)
    nameBox.Text = selectedName

    widthBox.Text = tostring(math.min(256, math.floor(size.X)))
    if preserveRatio then
        heightBox.Text = tostring(math.max(
            1,
            math.min(
                MAX_OUTPUT_SIDE,
                math.floor(
                    tonumber(widthBox.Text)
                        * size.Y
                        / size.X
                    + 0.5
                )
            )
        ))
    else
        heightBox.Text = tostring(math.min(256, math.floor(size.Y)))
    end

    previewLabel.ImageContent = Content.fromObject(image)
    processButton.Active = true

    setStatus(string.format(
        "Kaynak hazır: %s • %dx%d. Çıktı ayarlarını seçip dönüştür.",
        selectedName,
        size.X,
        size.Y
    ))
end

---------------------------------------------------------------------
-- RESAMPLING
---------------------------------------------------------------------

local function readPixel(
    source: buffer,
    width: number,
    x: number,
    y: number
): (number, number, number, number)
    local offset = (y * width + x) * 4
    return buffer.readu8(source, offset),
        buffer.readu8(source, offset + 1),
        buffer.readu8(source, offset + 2),
        buffer.readu8(source, offset + 3)
end

local function resampleBilinear(
    source: buffer,
    sourceWidth: number,
    sourceHeight: number,
    outputWidth: number,
    outputHeight: number
): buffer
    local output = buffer.create(outputWidth * outputHeight * 4)

    for y = 0, outputHeight - 1 do
        local sourceY =
            (y + 0.5) * sourceHeight / outputHeight - 0.5
        local y0 = math.clamp(math.floor(sourceY), 0, sourceHeight - 1)
        local y1 = math.clamp(y0 + 1, 0, sourceHeight - 1)
        local fy = math.clamp(sourceY - y0, 0, 1)

        for x = 0, outputWidth - 1 do
            local sourceX =
                (x + 0.5) * sourceWidth / outputWidth - 0.5
            local x0 = math.clamp(math.floor(sourceX), 0, sourceWidth - 1)
            local x1 = math.clamp(x0 + 1, 0, sourceWidth - 1)
            local fx = math.clamp(sourceX - x0, 0, 1)

            local r00, g00, b00, a00 =
                readPixel(source, sourceWidth, x0, y0)
            local r10, g10, b10, a10 =
                readPixel(source, sourceWidth, x1, y0)
            local r01, g01, b01, a01 =
                readPixel(source, sourceWidth, x0, y1)
            local r11, g11, b11, a11 =
                readPixel(source, sourceWidth, x1, y1)

            local function interpolate(
                v00: number,
                v10: number,
                v01: number,
                v11: number
            ): number
                local top = v00 + (v10 - v00) * fx
                local bottom = v01 + (v11 - v01) * fx
                return top + (bottom - top) * fy
            end

            local offset = (y * outputWidth + x) * 4
            buffer.writeu8(output, offset, clampByte(interpolate(r00, r10, r01, r11)))
            buffer.writeu8(output, offset + 1, clampByte(interpolate(g00, g10, g01, g11)))
            buffer.writeu8(output, offset + 2, clampByte(interpolate(b00, b10, b01, b11)))
            buffer.writeu8(output, offset + 3, clampByte(interpolate(a00, a10, a01, a11)))
        end

        if y % 24 == 0 then
            task.wait()
        end
    end

    return output
end

---------------------------------------------------------------------
-- ADAPTIVE MEDIAN-CUT PALETTE
---------------------------------------------------------------------

local function buildColorBins(
    pixels: buffer,
    width: number,
    height: number,
    alphaCutoff: number
): { { [string]: number } }
    local map = {}

    for index = 0, width * height - 1 do
        local offset = index * 4
        local alpha = buffer.readu8(pixels, offset + 3)

        if alpha >= alphaCutoff then
            local red = buffer.readu8(pixels, offset)
            local green = buffer.readu8(pixels, offset + 1)
            local blue = buffer.readu8(pixels, offset + 2)

            -- Four bits per channel gives at most 4096 adaptive samples.
            local key =
                math.floor(red / 16) * 256
                + math.floor(green / 16) * 16
                + math.floor(blue / 16)

            local bin = map[key]
            if not bin then
                bin = {
                    r = 0,
                    g = 0,
                    b = 0,
                    count = 0,
                }
                map[key] = bin
            end

            bin.r += red
            bin.g += green
            bin.b += blue
            bin.count += 1
        end
    end

    local bins = {}

    for _, bin in pairs(map) do
        table.insert(bins, {
            r = bin.r / bin.count,
            g = bin.g / bin.count,
            b = bin.b / bin.count,
            count = bin.count,
        })
    end

    return bins
end

local function makeBox(items: { { [string]: number } }): { [string]: any }
    local rMin = 255
    local rMax = 0
    local gMin = 255
    local gMax = 0
    local bMin = 255
    local bMax = 0
    local total = 0

    for _, color in ipairs(items) do
        rMin = math.min(rMin, color.r)
        rMax = math.max(rMax, color.r)
        gMin = math.min(gMin, color.g)
        gMax = math.max(gMax, color.g)
        bMin = math.min(bMin, color.b)
        bMax = math.max(bMax, color.b)
        total += color.count
    end

    local rRange = rMax - rMin
    local gRange = gMax - gMin
    local bRange = bMax - bMin
    local largestRange = math.max(rRange, gRange, bRange)

    return {
        items = items,
        total = total,
        rRange = rRange,
        gRange = gRange,
        bRange = bRange,
        score = largestRange * math.sqrt(math.max(total, 1)),
    }
end

local function splitBox(box: { [string]: any }): ({ [string]: any }?, { [string]: any }?)
    local items = box.items
    if #items <= 1 then
        return nil, nil
    end

    local channel = "r"
    if box.gRange >= box.rRange and box.gRange >= box.bRange then
        channel = "g"
    elseif box.bRange >= box.rRange and box.bRange >= box.gRange then
        channel = "b"
    end

    table.sort(items, function(a, b)
        return a[channel] < b[channel]
    end)

    local half = box.total / 2
    local running = 0
    local splitIndex = 1

    for index, color in ipairs(items) do
        running += color.count
        splitIndex = index
        if running >= half then
            break
        end
    end

    splitIndex = math.clamp(splitIndex, 1, #items - 1)

    local leftItems = table.create(splitIndex)
    local rightItems = table.create(#items - splitIndex)

    for index = 1, splitIndex do
        leftItems[index] = items[index]
    end

    for index = splitIndex + 1, #items do
        rightItems[index - splitIndex] = items[index]
    end

    return makeBox(leftItems), makeBox(rightItems)
end

local function boxAverage(box: { [string]: any }): { number }
    local red = 0
    local green = 0
    local blue = 0
    local total = 0

    for _, color in ipairs(box.items) do
        red += color.r * color.count
        green += color.g * color.count
        blue += color.b * color.count
        total += color.count
    end

    total = math.max(total, 1)

    return {
        clampByte(red / total),
        clampByte(green / total),
        clampByte(blue / total),
    }
end

local function buildAdaptivePalette(
    bins: { { [string]: number } },
    desiredColors: number
): { { number } }
    if #bins == 0 then
        return {}
    end

    local boxes = { makeBox(bins) }

    while #boxes < desiredColors do
        local bestIndex = nil
        local bestScore = -1

        for index, box in ipairs(boxes) do
            if #box.items > 1 and box.score > bestScore then
                bestIndex = index
                bestScore = box.score
            end
        end

        if not bestIndex then
            break
        end

        local selected = table.remove(boxes, bestIndex)
        local left, right = splitBox(selected)

        if not left or not right then
            table.insert(boxes, selected)
            break
        end

        table.insert(boxes, left)
        table.insert(boxes, right)

        if #boxes % 16 == 0 then
            task.wait()
        end
    end

    local palette = table.create(#boxes)

    for index, box in ipairs(boxes) do
        palette[index] = boxAverage(box)
    end

    return palette
end

---------------------------------------------------------------------
-- PALETTE MAPPING + DITHERING
---------------------------------------------------------------------

local function nearestPaletteIndex(
    red: number,
    green: number,
    blue: number,
    palette: { { number } },
    cache: { [number]: number }
): number
    local cacheKey =
        math.floor(red / 8) * 1024
        + math.floor(green / 8) * 32
        + math.floor(blue / 8)

    local cached = cache[cacheKey]
    if cached then
        return cached
    end

    local bestIndex = 1
    local bestDistance = math.huge

    for index, color in ipairs(palette) do
        local dr = red - color[1]
        local dg = green - color[2]
        local db = blue - color[3]

        -- Slightly perceptual RGB weighting.
        local distance =
            dr * dr * 0.30
            + dg * dg * 0.59
            + db * db * 0.11

        if distance < bestDistance then
            bestDistance = distance
            bestIndex = index
        end
    end

    cache[cacheKey] = bestIndex
    return bestIndex
end

local function mapPixelsToPalette(
    source: buffer,
    width: number,
    height: number,
    palette: { { number } },
    alphaCutoff: number,
    useDithering: boolean
): (buffer, buffer)
    local output = buffer.create(width * height * 4)
    local indices = buffer.create(width * height)
    local cache = {}

    local errorR = table.create(width + 2, 0)
    local errorG = table.create(width + 2, 0)
    local errorB = table.create(width + 2, 0)
    local nextR = table.create(width + 2, 0)
    local nextG = table.create(width + 2, 0)
    local nextB = table.create(width + 2, 0)

    for y = 0, height - 1 do
        local reverse = useDithering and y % 2 == 1
        local startX = reverse and width - 1 or 0
        local endX = reverse and 0 or width - 1
        local direction = reverse and -1 or 1
        local x = startX

        while true do
            local pixelOffset = (y * width + x) * 4
            local alpha = buffer.readu8(source, pixelOffset + 3)

            if alpha < alphaCutoff or #palette == 0 then
                buffer.writeu8(indices, y * width + x, 0)
                buffer.writeu8(output, pixelOffset, 0)
                buffer.writeu8(output, pixelOffset + 1, 0)
                buffer.writeu8(output, pixelOffset + 2, 0)
                buffer.writeu8(output, pixelOffset + 3, 0)
            else
                local errorIndex = x + 2
                local red = math.clamp(
                    buffer.readu8(source, pixelOffset)
                        + (useDithering and errorR[errorIndex] or 0),
                    0,
                    255
                )
                local green = math.clamp(
                    buffer.readu8(source, pixelOffset + 1)
                        + (useDithering and errorG[errorIndex] or 0),
                    0,
                    255
                )
                local blue = math.clamp(
                    buffer.readu8(source, pixelOffset + 2)
                        + (useDithering and errorB[errorIndex] or 0),
                    0,
                    255
                )

                local paletteIndex = nearestPaletteIndex(
                    red,
                    green,
                    blue,
                    palette,
                    cache
                )
                local color = palette[paletteIndex]

                -- 0 is transparent, opaque colors are 1..255.
                buffer.writeu8(indices, y * width + x, paletteIndex)
                buffer.writeu8(output, pixelOffset, color[1])
                buffer.writeu8(output, pixelOffset + 1, color[2])
                buffer.writeu8(output, pixelOffset + 2, color[3])
                buffer.writeu8(output, pixelOffset + 3, 255)

                if useDithering then
                    local er = red - color[1]
                    local eg = green - color[2]
                    local eb = blue - color[3]

                    local forwardIndex = errorIndex + direction
                    local backwardNext = errorIndex - direction
                    local forwardNext = errorIndex + direction

                    errorR[forwardIndex] += er * 7 / 16
                    errorG[forwardIndex] += eg * 7 / 16
                    errorB[forwardIndex] += eb * 7 / 16

                    nextR[backwardNext] += er * 3 / 16
                    nextG[backwardNext] += eg * 3 / 16
                    nextB[backwardNext] += eb * 3 / 16

                    nextR[errorIndex] += er * 5 / 16
                    nextG[errorIndex] += eg * 5 / 16
                    nextB[errorIndex] += eb * 5 / 16

                    nextR[forwardNext] += er * 1 / 16
                    nextG[forwardNext] += eg * 1 / 16
                    nextB[forwardNext] += eb * 1 / 16
                end
            end

            if x == endX then
                break
            end
            x += direction
        end

        if useDithering then
            errorR, nextR = nextR, table.create(width + 2, 0)
            errorG, nextG = nextG, table.create(width + 2, 0)
            errorB, nextB = nextB, table.create(width + 2, 0)
        end

        if y % 18 == 0 then
            task.wait()
        end
    end

    return output, indices
end

---------------------------------------------------------------------
-- STROKES / DOCUMENT ENCODING
---------------------------------------------------------------------

local function createStrokes(
    indices: buffer,
    width: number,
    height: number
): { { number } }
    local strokes = {}

    for y = 0, height - 1 do
        local reverse = y % 2 == 1
        local direction = reverse and -1 or 1
        local x = reverse and width - 1 or 0
        local endX = reverse and 0 or width - 1

        while true do
            local paletteIndex =
                buffer.readu8(indices, y * width + x)

            if paletteIndex == 0 then
                if x == endX then
                    break
                end
                x += direction
            else
                local startX = x
                local strokeEnd = x
                local nextX = x + direction

                while nextX >= 0
                    and nextX < width
                    and buffer.readu8(
                        indices,
                        y * width + nextX
                    ) == paletteIndex
                do
                    strokeEnd = nextX
                    nextX += direction
                end

                table.insert(strokes, {
                    y,
                    startX,
                    strokeEnd,
                    paletteIndex,
                })

                if nextX < 0 or nextX >= width then
                    break
                end
                x = nextX
            end
        end

        if y % 32 == 0 then
            task.wait()
        end
    end

    return strokes
end

local function encodeDocument(
    name: string,
    width: number,
    height: number,
    palette: { string },
    strokes: { { number } }
): { [string]: any }
    local raw = buffer.create(#strokes * STROKE_BYTES)

    for index, stroke in ipairs(strokes) do
        local offset = (index - 1) * STROKE_BYTES
        buffer.writeu16(raw, offset, stroke[1])
        buffer.writeu16(raw, offset + 2, stroke[2])
        buffer.writeu16(raw, offset + 4, stroke[3])
        buffer.writeu8(raw, offset + 6, stroke[4])
    end

    local codec = "raw-base64-run7"
    local payload = raw

    if #strokes > 0 then
        local ok, compressed = pcall(function()
            return EncodingService:CompressBuffer(
                raw,
                Enum.CompressionAlgorithm.Zstd,
                9
            )
        end)

        if ok
            and compressed
            and buffer.len(compressed) < buffer.len(raw)
        then
            codec = "zstd-base64-run7"
            payload = compressed
        end
    end

    local encoded = EncodingService:Base64Encode(payload)

    return {
        version = 1,
        name = name,
        width = width,
        height = height,
        palette = palette,
        strokeCount = #strokes,
        codec = codec,
        data = buffer.tostring(encoded),
    }
end

local function luaQuote(text: string): string
    return string.format("%q", text)
end

local function moduleSource(document: { [string]: any }): string
    local paletteLines = table.create(#document.palette)

    for index, entry in ipairs(document.palette) do
        paletteLines[index] = "        " .. luaQuote(entry) .. ","
    end

    return table.concat({
        "--!strict",
        "-- Generated by AutoSprayImporter.plugin.lua",
        "return {",
        "    version = 1,",
        "    name = " .. luaQuote(document.name) .. ",",
        "    width = " .. tostring(document.width) .. ",",
        "    height = " .. tostring(document.height) .. ",",
        "    palette = {",
        table.concat(paletteLines, "\n"),
        "    },",
        "    strokeCount = " .. tostring(document.strokeCount) .. ",",
        "    codec = " .. luaQuote(document.codec) .. ",",
        "    data = [[" .. document.data .. "]],",
        "}",
        "",
    }, "\n")
end

---------------------------------------------------------------------
-- PROCESS
---------------------------------------------------------------------

local function processImage()
    if processing or not selectedImage then
        return
    end

    processing = true
    processButton.Active = false
    moduleButton.Active = false
    copyButton.Active = false

    local outputWidth = clampInteger(
        widthBox,
        256,
        1,
        MAX_OUTPUT_SIDE
    )
    local outputHeight = clampInteger(
        heightBox,
        256,
        1,
        MAX_OUTPUT_SIDE
    )
    local desiredColors = clampInteger(
        paletteBox,
        255,
        2,
        MAX_OPAQUE_COLORS
    )
    local alphaCutoff = clampInteger(
        alphaBox,
        24,
        0,
        255
    )
    local documentName = sanitizeName(nameBox.Text)
    nameBox.Text = documentName

    local sourceSize = selectedImage.Size
    local sourceWidth = math.floor(sourceSize.X)
    local sourceHeight = math.floor(sourceSize.Y)

    setStatus("1/6 Kaynak pikseller okunuyor...")

    local readOk, sourceOrError = pcall(function()
        return selectedImage:ReadPixelsBuffer(
            Vector2.zero,
            Vector2.new(sourceWidth, sourceHeight)
        )
    end)

    if not readOk then
        processing = false
        processButton.Active = true
        setStatus(
            "Kaynak pikseller okunamadı: "
                .. tostring(sourceOrError),
            true
        )
        return
    end

    setStatus("2/6 Yüksek kaliteli bilinear küçültme yapılıyor...")
    local resampled = resampleBilinear(
        sourceOrError,
        sourceWidth,
        sourceHeight,
        outputWidth,
        outputHeight
    )

    setStatus("3/6 Adaptif renk kutuları çıkarılıyor...")
    local bins = buildColorBins(
        resampled,
        outputWidth,
        outputHeight,
        alphaCutoff
    )

    setStatus(string.format(
        "4/6 Median-cut palet üretiliyor (%d hedef renk, %d örnek kutu)...",
        desiredColors,
        #bins
    ))
    local opaquePalette = buildAdaptivePalette(
        bins,
        desiredColors
    )

    setStatus(
        ditheringEnabled
            and "5/6 Floyd-Steinberg dithering ve en yakın renk eşlemesi..."
            or "5/6 Adaptif palete en yakın renk eşlemesi..."
    )

    local processedPixels, paletteIndices =
        mapPixelsToPalette(
            resampled,
            outputWidth,
            outputHeight,
            opaquePalette,
            alphaCutoff,
            ditheringEnabled
        )

    setStatus("6/6 Aynı renkli pikseller gerçek spray stroke'larına çevriliyor...")
    local strokes = createStrokes(
        paletteIndices,
        outputWidth,
        outputHeight
    )

    local documentPalette = table.create(#opaquePalette + 1)
    documentPalette[1] = "00000000"

    for index, color in ipairs(opaquePalette) do
        documentPalette[index + 1] = colorHex(
            color[1],
            color[2],
            color[3],
            255
        )
    end

    local document = encodeDocument(
        documentName,
        outputWidth,
        outputHeight,
        documentPalette,
        strokes
    )

    local json = HttpService:JSONEncode(document)

    destroyEditable(processedImage)
    processedImage = AssetService:CreateEditableImage({
        Size = Vector2.new(outputWidth, outputHeight),
    })

    if processedImage then
        processedImage:WritePixelsBuffer(
            Vector2.zero,
            Vector2.new(outputWidth, outputHeight),
            processedPixels
        )
        previewLabel.ImageContent = Content.fromObject(processedImage)
    end

    processedDocument = document
    processedJson = json
    processing = false
    processButton.Active = true
    moduleButton.Active = true
    copyButton.Active = true

    local rawBytes = #strokes * STROKE_BYTES
    local encodedKilobytes = #document.data / 1024
    local jsonKilobytes = #json / 1024

    setStatus(string.format(
        "Hazır: %dx%d • %d toplam palet rengi • %d stroke • "
            .. "ham %.1f KB • sıkıştırılmış Base64 %.1f KB • JSON %.1f KB. "
            .. "Modül oluşturabilir veya GitHub JSON'u kopyalayabilirsin.",
        outputWidth,
        outputHeight,
        #documentPalette,
        #strokes,
        rawBytes / 1024,
        encodedKilobytes,
        jsonKilobytes
    ))
end

---------------------------------------------------------------------
-- OUTPUT
---------------------------------------------------------------------

local function createModule()
    if not processedDocument then
        setStatus("Önce bir görsel dönüştür.", true)
        return
    end

    local folder = ServerStorage:FindFirstChild("AutoSprayImages")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "AutoSprayImages"
        folder.Parent = ServerStorage
    end

    local moduleName = sanitizeName(processedDocument.name)
    local existing = folder:FindFirstChild(moduleName)

    if existing then
        existing:Destroy()
    end

    local module = Instance.new("ModuleScript")
    module.Name = moduleName
    module.Source = moduleSource(processedDocument)
    module:SetAttribute("AutoSprayImage", true)
    module:SetAttribute("Width", processedDocument.width)
    module:SetAttribute("Height", processedDocument.height)
    module:SetAttribute("StrokeCount", processedDocument.strokeCount)
    module.Parent = folder

    setStatus(
        `Modül oluşturuldu: ServerStorage/AutoSprayImages/{moduleName}`
    )
end

local function copyJson()
    if processedJson == "" then
        setStatus("Önce bir görsel dönüştür.", true)
        return
    end

    local ok, copyError = pcall(function()
        (StudioService :: any):CopyToClipboard(processedJson)
    end)

    if ok then
        setStatus(
            "GitHub-ready JSON panoya kopyalandı. "
                .. "GitHub'da .json dosyasına yapıştır, sonra Raw URL'yi oyun paneline gir."
        )
    else
        setStatus(
            "Panoya kopyalama başarısız: "
                .. tostring(copyError)
                .. ". Oluşturulan ModuleScript yöntemini kullan.",
            true
        )
    end
end

---------------------------------------------------------------------
-- EVENTS
---------------------------------------------------------------------

toolbarButton.Click:Connect(function()
    widget.Enabled = not widget.Enabled
end)

selectButton.Activated:Connect(selectImage)
processButton.Activated:Connect(function()
    task.spawn(processImage)
end)
moduleButton.Activated:Connect(createModule)
copyButton.Activated:Connect(copyJson)

ditherButton.Activated:Connect(function()
    ditheringEnabled = not ditheringEnabled
    ditherButton.Text = ditheringEnabled
        and "DITHERING: AÇIK"
        or "DITHERING: KAPALI"
    ditherButton.BackgroundColor3 = ditheringEnabled
        and Color3.fromRGB(44, 137, 102)
        or Color3.fromRGB(83, 88, 101)
end)

ratioButton.Activated:Connect(function()
    preserveRatio = not preserveRatio
    ratioButton.Text = preserveRatio
        and "ORAN KORU: AÇIK"
        or "ORAN KORU: KAPALI"
    ratioButton.BackgroundColor3 = preserveRatio
        and Color3.fromRGB(94, 67, 184)
        or Color3.fromRGB(83, 88, 101)
end)

widthBox.FocusLost:Connect(function()
    if preserveRatio and selectedImage then
        local width = clampInteger(
            widthBox,
            256,
            1,
            MAX_OUTPUT_SIDE
        )

        heightBox.Text = tostring(math.max(
            1,
            math.min(
                MAX_OUTPUT_SIDE,
                math.floor(
                    width
                        * selectedImage.Size.Y
                        / selectedImage.Size.X
                    + 0.5
                )
            )
        ))
    end
end)

heightBox.FocusLost:Connect(function()
    if preserveRatio and selectedImage then
        local height = clampInteger(
            heightBox,
            256,
            1,
            MAX_OUTPUT_SIDE
        )

        widthBox.Text = tostring(math.max(
            1,
            math.min(
                MAX_OUTPUT_SIDE,
                math.floor(
                    height
                        * selectedImage.Size.X
                        / selectedImage.Size.Y
                    + 0.5
                )
            )
        ))
    end
end)

plugin.Unloading:Connect(function()
    destroyEditable(selectedImage)
    destroyEditable(processedImage)
end)
