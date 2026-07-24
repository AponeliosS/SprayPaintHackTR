--!strict
-- AutoSpray shared configuration.
-- GitHub/Rojo path: src/ReplicatedStorage/AutoSpray/Config.lua

local Config = {
    Version = 1,

    -- If the experience is owned by a user, the owner is allowed automatically.
    -- Group-owned experiences must add developer UserIds here.
    AdminUserIds = {
        -- [123456789] = true,
    },

    AllowAllInStudio = true,
    AllowAllPrivateServers = true,

    -- Mark paintable parts with AutoSprayCanvas=true when this is enabled.
    RequireCanvasAttribute = false,
    CanvasAttributeName = "AutoSprayCanvas",

    MaxCanvasResolution = 1024,
    RecommendedMaxResolution = 256,
    MaxPaletteEntries = 256,
    MaxStrokeCount = 2_000_000,
    MaxEncodedDocumentBytes = 12 * 1024 * 1024,
    MaxDecodedStrokeBytes = 16 * 1024 * 1024,

    MaxCanvasSideStuds = 160,
    MaxTargetDistanceStuds = 350,

    -- GitHub raw JSON loading.
    AllowHttpDocuments = true,
    AllowedHttpHosts = {
        ["raw.githubusercontent.com"] = true,
        ["gist.githubusercontent.com"] = true,
    },
    MaxHttpDocumentBytes = 12 * 1024 * 1024,

    DocumentChunkStrokes = 900,
    MaxSegmentsPerEvent = 96,
    SnapshotRowsPerChunk = 24,

    -- Server-side abuse protection.
    MaxPaintedPixelsPerSecond = 12_000,
    MaxPoseEventsPerSecond = 24,

    -- Automatic drawing defaults.
    Drawing = {
        PixelsPerSecond = 260,
        TravelPixelsPerSecond = 900,
        PixelsPerSegment = 6,
        NetworkFlushInterval = 0.055,
        LiftBetweenStrokes = true,
        SurfaceOffsetStuds = 0.025,
        BrushScale = 1.04,
    },

    Realistic = {
        Enabled = true,
        JitterStuds = 0.010,
        BeamWidth = 0.025,
        PoseSendInterval = 1 / 18,
        ReticleSizeStuds = 0.085,

        -- Leave empty to disable custom assets.
        SpraySoundId = "",
        SpraySoundVolume = 0.45,
        SprayAnimationId = "",
    },

    UI = {
        DisplayOrder = 5000,
        StartHidden = false,
    },
}

return Config
