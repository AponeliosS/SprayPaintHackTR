# GitHub yükleme sırası

Depoda aşağıdaki klasörleri ve dosyaları aynı adlarla oluştur.

```text
AutoSpray-Full-Lua/
├─ README.md
├─ default.project.json
├─ plugins/
│  └─ AutoSprayImporter.plugin.lua
└─ src/
   ├─ ReplicatedStorage/
   │  └─ AutoSpray/
   │     ├─ Main.lua
   │     ├─ Config.lua
   │     └─ StrokeCodec.lua
   ├─ ServerScriptService/
   │  └─ AutoSprayServer.server.lua
   ├─ ServerStorage/
   │  └─ AutoSprayImages/
   │     └─ Example.lua
   └─ StarterPlayer/
      └─ StarterPlayerScripts/
         └─ AutoSprayClient.client.lua
```

## Bağlantı yapısı

```text
AutoSprayServer.server.lua ─┐
                            ├─ require(Main.lua)
AutoSprayClient.client.lua ─┘
                                  │
                                  ├─ Config.lua
                                  └─ StrokeCodec.lua
```

## Roblox'a aktarma

Önerilen yöntem Rojo:

```bash
rojo serve
```

Studio içindeki Rojo eklentisi ile `default.project.json` projesine bağlan.

Manuel kurulum yapıyorsan GitHub'daki dosyaları Explorer'da README içindeki konumlara
Script / LocalScript / ModuleScript olarak yerleştir.

## GitHub Raw JSON

Importer'ın ürettiği görsel JSON dosyalarını örneğin:

```text
images/resim-adi.json
```

konumuna yükle. Oyundaki URL alanına dosyanın GitHub **Raw** bağlantısını gir.

Bu URL yalnızca stroke görsel verisi içindir. Lua kaynak kodunu runtime'da `loadstring`
ile çalıştırmak için değildir.
