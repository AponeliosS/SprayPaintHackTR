--!strict
-- AutoSpray Full Lua - ONE FILE STUDIO INSTALLER
--
-- ÇALIŞTIRMA YERİ:
--   Roblox Studio > View > Command Bar
--
-- Bu dosya canlı oyunda/executor içinde çalıştırılmak için değildir.
-- GitHub'daki kaynakları indirir ve doğru Script türleriyle doğru servislere kurar.
--
-- Varsayılan depo:
--   https://github.com/AponeliosS/SprayPaintHackTR
--
-- Kurulumdan önce Studio:
--   Game Settings > Security > Allow HTTP Requests = ON
--
-- Command Bar'a bu dosyanın tamamını yapıştırıp Enter'a bas.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

---------------------------------------------------------------------
-- AYARLAR
---------------------------------------------------------------------

local REPOSITORY_OWNER = "AponeliosS"
local REPOSITORY_NAME = "SprayPaintHackTR"
local BRANCH = "main"

local RAW_BASE = string.format(
    "https://raw.githubusercontent.com/%s/%s/%s/",
    REPOSITORY_OWNER,
    REPOSITORY_NAME,
    BRANCH
)

local FILES = {
    {
        path = "src/ReplicatedStorage/AutoSpray/Main.lua",
        className = "ModuleScript",
        name = "Main",
        destination = { "ReplicatedStorage", "AutoSpray" },
    },
    {
        path = "src/ReplicatedStorage/AutoSpray/Config.lua",
        className = "ModuleScript",
        name = "Config",
        destination = { "ReplicatedStorage", "AutoSpray" },
    },
    {
        path = "src/ReplicatedStorage/AutoSpray/StrokeCodec.lua",
        className = "ModuleScript",
        name = "StrokeCodec",
        destination = { "ReplicatedStorage", "AutoSpray" },
    },
    {
        path = "src/ServerScriptService/AutoSprayServer.server.lua",
        className = "Script",
        name = "AutoSprayServer",
        destination = { "ServerScriptService" },
    },
    {
        path = "src/StarterPlayer/StarterPlayerScripts/AutoSprayClient.client.lua",
        className = "LocalScript",
        name = "AutoSprayClient",
        destination = { "StarterPlayer", "StarterPlayerScripts" },
    },
    {
        path = "src/ServerStorage/AutoSprayImages/Example.lua",
        className = "ModuleScript",
        name = "Example",
        destination = { "ServerStorage", "AutoSprayImages" },
    },
}

---------------------------------------------------------------------
-- YARDIMCILAR
---------------------------------------------------------------------

local ROOTS = {
    ReplicatedStorage = ReplicatedStorage,
    ServerScriptService = ServerScriptService,
    ServerStorage = ServerStorage,
    StarterPlayer = StarterPlayer,
}

local function log(message: string)
    print("[AutoSpray Installer] " .. message)
end

local function warnInstaller(message: string)
    warn("[AutoSpray Installer] " .. message)
end

local function fetchSource(relativePath: string): string
    local url = RAW_BASE .. relativePath
    log("İndiriliyor: " .. url)

    local success, bodyOrError = pcall(function()
        return HttpService:GetAsync(url, true)
    end)

    if not success then
        error(
            string.format(
                "HTTP isteği başarısız:\n%s\n%s",
                url,
                tostring(bodyOrError)
            )
        )
    end

    local body = bodyOrError

    if type(body) ~= "string" or body == "" then
        error("Boş kaynak döndü: " .. url)
    end

    -- GitHub 404 sayfası veya HTML yanlışlıkla Lua Source yapılmasın.
    local lower = string.lower(body)
    if string.find(lower, "<!doctype html", 1, true)
        or string.find(lower, "<html", 1, true)
        or string.find(lower, "404: not found", 1, true)
    then
        error("Geçerli Lua kaynağı yerine HTML/404 döndü: " .. url)
    end

    return body
end

local function ensureFolder(parent: Instance, name: string): Folder
    local existing = parent:FindFirstChild(name)

    if existing then
        if existing:IsA("Folder") then
            return existing
        end

        error(
            string.format(
                "%s altında %s var ama Folder değil.",
                parent:GetFullName(),
                name
            )
        )
    end

    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    return folder
end

local function resolveDestination(parts: { string }): Instance
    local rootName = parts[1]
    local current = ROOTS[rootName]

    if not current then
        error("Bilinmeyen root service: " .. tostring(rootName))
    end

    for index = 2, #parts do
        local name = parts[index]

        -- StarterPlayerScripts zaten özel bir container'dır.
        if current == StarterPlayer and name == "StarterPlayerScripts" then
            current = StarterPlayer:WaitForChild("StarterPlayerScripts")
        else
            current = ensureFolder(current, name)
        end
    end

    return current
end

local function replaceScript(
    className: string,
    name: string,
    parent: Instance,
    source: string
): LuaSourceContainer
    local existing = parent:FindFirstChild(name)

    if existing then
        if existing:IsA("LuaSourceContainer") then
            existing:Destroy()
        else
            error(
                string.format(
                    "%s altında %s bulundu fakat script türü değil.",
                    parent:GetFullName(),
                    name
                )
            )
        end
    end

    local object = Instance.new(className)
    object.Name = name

    -- Command Bar / Plugin güvenlik bağlamında Source yazılabilir.
    (object :: any).Source = source

    -- Server ve client scriptleri tüm kurulum bitene kadar çalışmasın.
    if object:IsA("BaseScript") then
        object.Disabled = true
    end

    object.Parent = parent

    return object :: any
end

local function enableInstalledScripts()
    local server = ServerScriptService:FindFirstChild("AutoSprayServer")
    if server and server:IsA("Script") then
        server.Disabled = false
    end

    local client = StarterPlayer.StarterPlayerScripts:FindFirstChild(
        "AutoSprayClient"
    )
    if client and client:IsA("LocalScript") then
        client.Disabled = false
    end
end

local function validateInstallation()
    local autoSprayFolder = ReplicatedStorage:FindFirstChild("AutoSpray")
    assert(autoSprayFolder, "ReplicatedStorage/AutoSpray eksik.")
    assert(autoSprayFolder:FindFirstChild("Main"), "Main eksik.")
    assert(autoSprayFolder:FindFirstChild("Config"), "Config eksik.")
    assert(
        autoSprayFolder:FindFirstChild("StrokeCodec"),
        "StrokeCodec eksik."
    )

    assert(
        ServerScriptService:FindFirstChild("AutoSprayServer"),
        "AutoSprayServer eksik."
    )

    assert(
        StarterPlayer.StarterPlayerScripts:FindFirstChild(
            "AutoSprayClient"
        ),
        "AutoSprayClient eksik."
    )

    local imageFolder = ServerStorage:FindFirstChild("AutoSprayImages")
    assert(imageFolder, "ServerStorage/AutoSprayImages eksik.")
    assert(imageFolder:FindFirstChild("Example"), "Example eksik.")
end

---------------------------------------------------------------------
-- KURULUM
---------------------------------------------------------------------

local recording = nil

pcall(function()
    recording = ChangeHistoryService:TryBeginRecording(
        "Install AutoSpray Full Lua"
    )
end)

local installed = {}

local success, installError = xpcall(function()
    log("Kurulum başlıyor.")
    log("Raw base: " .. RAW_BASE)

    -- Önce bütün dosyaları indir. Bir URL bozuksa yarım kurulum yapılmasın.
    local sources = {}

    for _, file in ipairs(FILES) do
        sources[file.path] = fetchSource(file.path)
    end

    log("Tüm GitHub kaynakları indirildi.")

    -- Kaynaklar başarıyla geldikten sonra nesneleri oluştur.
    for _, file in ipairs(FILES) do
        local destination = resolveDestination(file.destination)
        local object = replaceScript(
            file.className,
            file.name,
            destination,
            sources[file.path]
        )

        table.insert(installed, object)

        log(
            string.format(
                "Kuruldu: %s (%s)",
                object:GetFullName(),
                file.className
            )
        )
    end

    validateInstallation()
    enableInstalledScripts()

    log("Kurulum tamamlandı.")
    log("Şimdi Config ModuleScript içindeki AdminUserIds tablosunu düzenle.")
    log("Play testi için panelde Example modülünü yükle.")
end, function(message)
    return debug.traceback(tostring(message), 2)
end)

if recording then
    pcall(function()
        ChangeHistoryService:FinishRecording(
            recording,
            success
                and Enum.FinishRecordingOperation.Commit
                or Enum.FinishRecordingOperation.Cancel
        )
    end)
end

if not success then
    warnInstaller("Kurulum başarısız:\n" .. tostring(installError))

    -- Bu çalıştırmada oluşturulan nesneleri geri temizle.
    for index = #installed, 1, -1 do
        local object = installed[index]
        if object and object.Parent then
            object:Destroy()
        end
    end

    error("AutoSpray kurulamadı. Output ayrıntılarını kontrol et.")
end

print("============================================================")
print("AUTO SPRAY FULL LUA BAŞARIYLA KURULDU")
print("ReplicatedStorage/AutoSpray")
print("ServerScriptService/AutoSprayServer")
print("StarterPlayer/StarterPlayerScripts/AutoSprayClient")
print("ServerStorage/AutoSprayImages/Example")
print("============================================================")
