--!strict
-- AutoSpray shared entry module.
-- Both AutoSprayServer.server.lua and AutoSprayClient.client.lua require this file.

local folder = script.Parent

local Main = {
    Version = "1.0.0",
    Config = require(folder:WaitForChild("Config")),
    StrokeCodec = require(folder:WaitForChild("StrokeCodec")),
}

return table.freeze(Main)
