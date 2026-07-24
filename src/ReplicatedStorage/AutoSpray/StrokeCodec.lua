--!strict
-- Compact AutoSpray document codec.
-- Each stroke occupies seven bytes:
--   y:uint16, xStart:uint16, xEnd:uint16, paletteIndex:uint8

local EncodingService = game:GetService("EncodingService")

local Codec = {}

Codec.VERSION = 1
Codec.STROKE_BYTES = 7
Codec.CODEC_RAW = "raw-base64-run7"
Codec.CODEC_ZSTD = "zstd-base64-run7"

local function validInteger(value: any): boolean
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and math.floor(value) == value
end

local function normalizePaletteEntry(value: any): string?
    if type(value) ~= "string" then
        return nil
    end

    local cleaned = string.upper(string.gsub(value, "#", ""))
    if #cleaned == 6 then
        cleaned ..= "FF"
    end

    if #cleaned ~= 8 or string.match(cleaned, "^[%x]+$") == nil then
        return nil
    end

    return cleaned
end

function Codec.PaletteBytes(entry: string): (number, number, number, number)
    local cleaned = normalizePaletteEntry(entry)
    if not cleaned then
        return 0, 0, 0, 0
    end

    return tonumber(string.sub(cleaned, 1, 2), 16) or 0,
        tonumber(string.sub(cleaned, 3, 4), 16) or 0,
        tonumber(string.sub(cleaned, 5, 6), 16) or 0,
        tonumber(string.sub(cleaned, 7, 8), 16) or 0
end

function Codec.EncodeDocument(
    width: number,
    height: number,
    palette: { string },
    strokes: { { number } },
    name: string?,
    useCompression: boolean?
): { [string]: any }
    assert(validInteger(width) and width > 0 and width <= 65535, "Invalid width")
    assert(validInteger(height) and height > 0 and height <= 65535, "Invalid height")
    assert(type(palette) == "table" and #palette >= 1 and #palette <= 256, "Invalid palette")
    assert(type(strokes) == "table", "Invalid strokes")

    local normalizedPalette = table.create(#palette)
    for index, entry in ipairs(palette) do
        local normalized = normalizePaletteEntry(entry)
        assert(normalized ~= nil, `Invalid palette entry at {index}`)
        normalizedPalette[index] = normalized
    end

    local raw = buffer.create(#strokes * Codec.STROKE_BYTES)

    for index, stroke in ipairs(strokes) do
        assert(type(stroke) == "table", `Invalid stroke at {index}`)

        local y = stroke[1]
        local xStart = stroke[2]
        local xEnd = stroke[3]
        local paletteIndex = stroke[4]

        assert(validInteger(y) and y >= 0 and y < height, `Invalid stroke y at {index}`)
        assert(validInteger(xStart) and xStart >= 0 and xStart < width, `Invalid stroke xStart at {index}`)
        assert(validInteger(xEnd) and xEnd >= 0 and xEnd < width, `Invalid stroke xEnd at {index}`)
        assert(validInteger(paletteIndex) and paletteIndex >= 0 and paletteIndex <= 255, `Invalid palette index at {index}`)
        assert(normalizedPalette[paletteIndex + 1] ~= nil, `Missing palette entry at {index}`)

        local offset = (index - 1) * Codec.STROKE_BYTES
        buffer.writeu16(raw, offset, y)
        buffer.writeu16(raw, offset + 2, xStart)
        buffer.writeu16(raw, offset + 4, xEnd)
        buffer.writeu8(raw, offset + 6, paletteIndex)
    end

    local codecName = Codec.CODEC_RAW
    local payload = raw

    if useCompression ~= false and #strokes > 0 then
        local ok, compressed = pcall(function()
            return EncodingService:CompressBuffer(
                raw,
                Enum.CompressionAlgorithm.Zstd,
                7
            )
        end)

        if ok and compressed and buffer.len(compressed) < buffer.len(raw) then
            codecName = Codec.CODEC_ZSTD
            payload = compressed
        end
    end

    local encodedBuffer = EncodingService:Base64Encode(payload)
    local encodedString = buffer.tostring(encodedBuffer)

    return {
        version = Codec.VERSION,
        name = name or "AutoSpray Image",
        width = width,
        height = height,
        palette = normalizedPalette,
        strokeCount = #strokes,
        codec = codecName,
        data = encodedString,
    }
end

function Codec.ValidateMetadata(document: any, limits: { [string]: any }?): (boolean, string?)
    if type(document) ~= "table" then
        return false, "Document must be a table."
    end

    if document.version ~= Codec.VERSION then
        return false, `Unsupported document version: {tostring(document.version)}`
    end

    local maxResolution = limits and limits.MaxCanvasResolution or 1024
    local maxPalette = limits and limits.MaxPaletteEntries or 256
    local maxStrokes = limits and limits.MaxStrokeCount or 2_000_000
    local maxEncoded = limits and limits.MaxEncodedDocumentBytes or 12 * 1024 * 1024

    if not validInteger(document.width)
        or document.width < 1
        or document.width > maxResolution
    then
        return false, "Invalid document width."
    end

    if not validInteger(document.height)
        or document.height < 1
        or document.height > maxResolution
    then
        return false, "Invalid document height."
    end

    if type(document.palette) ~= "table"
        or #document.palette < 1
        or #document.palette > maxPalette
    then
        return false, "Invalid document palette."
    end

    for index, entry in ipairs(document.palette) do
        if not normalizePaletteEntry(entry) then
            return false, `Invalid palette entry at {index}.`
        end
    end

    if not validInteger(document.strokeCount)
        or document.strokeCount < 0
        or document.strokeCount > maxStrokes
    then
        return false, "Invalid stroke count."
    end

    if document.codec ~= Codec.CODEC_RAW and document.codec ~= Codec.CODEC_ZSTD then
        return false, "Unsupported stroke codec."
    end

    if type(document.data) ~= "string" or #document.data > maxEncoded then
        return false, "Invalid or oversized encoded data."
    end

    return true
end

function Codec.DecodeDocument(
    document: any,
    limits: { [string]: any }?
): ({ [string]: any }?, string?)
    local valid, metadataError = Codec.ValidateMetadata(document, limits)
    if not valid then
        return nil, metadataError
    end

    local decodedBase64
    local base64Ok, base64Error = pcall(function()
        decodedBase64 = EncodingService:Base64Decode(
            buffer.fromstring(document.data)
        )
    end)

    if not base64Ok or not decodedBase64 then
        return nil, `Base64 decode failed: {tostring(base64Error)}`
    end

    local raw = decodedBase64

    if document.codec == Codec.CODEC_ZSTD then
        local expectedSize = EncodingService:GetDecompressedBufferSize(
            decodedBase64,
            Enum.CompressionAlgorithm.Zstd
        )

        local maxDecoded = limits and limits.MaxDecodedStrokeBytes
            or 16 * 1024 * 1024

        if not expectedSize or expectedSize > maxDecoded then
            return nil, "Compressed document has an invalid decompressed size."
        end

        local decompressOk, decompressedOrError = pcall(function()
            return EncodingService:DecompressBuffer(
                decodedBase64,
                Enum.CompressionAlgorithm.Zstd
            )
        end)

        if not decompressOk or not decompressedOrError then
            return nil, `Zstd decode failed: {tostring(decompressedOrError)}`
        end

        raw = decompressedOrError
    end

    local requiredBytes = document.strokeCount * Codec.STROKE_BYTES
    if buffer.len(raw) ~= requiredBytes then
        return nil, `Stroke buffer size mismatch. Expected {requiredBytes}, got {buffer.len(raw)}.`
    end

    local palette = table.create(#document.palette)
    for index, entry in ipairs(document.palette) do
        palette[index] = normalizePaletteEntry(entry) :: string
    end

    return {
        Version = document.version,
        Name = tostring(document.name or "AutoSpray Image"),
        Width = document.width,
        Height = document.height,
        Palette = palette,
        StrokeCount = document.strokeCount,
        StrokeBuffer = raw,
        Codec = document.codec,
    }
end

function Codec.ReadStroke(
    strokeBuffer: buffer,
    index: number
): (number, number, number, number)
    local offset = (index - 1) * Codec.STROKE_BYTES
    return buffer.readu16(strokeBuffer, offset),
        buffer.readu16(strokeBuffer, offset + 2),
        buffer.readu16(strokeBuffer, offset + 4),
        buffer.readu8(strokeBuffer, offset + 6)
end

function Codec.CopyStrokeChunk(
    strokeBuffer: buffer,
    startIndex: number,
    count: number
): buffer
    local sourceOffset = (startIndex - 1) * Codec.STROKE_BYTES
    local byteCount = count * Codec.STROKE_BYTES
    local output = buffer.create(byteCount)

    if byteCount > 0 then
        buffer.copy(output, 0, strokeBuffer, sourceOffset, byteCount)
    end

    return output
end

function Codec.CountPixelsInStroke(xStart: number, xEnd: number): number
    return math.abs(xEnd - xStart) + 1
end

return Codec
