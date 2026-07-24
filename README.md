# AutoSpray Full Lua

Bu depo; bilgisayardan görseli Studio eklentisiyle içe aktaran, görseli adaptif palet ve stroke verisine dönüştüren, oyunda gerçekçi spray hareketiyle otomatik çizen ve sonucu bütün istemcilere gösteren tam Luau paketidir.

## Dosya yapısı

```text
src/
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

plugins/
└─ AutoSprayImporter.plugin.lua
```

## 1. Roblox Studio kurulumu

Rojo kullanıyorsan:

```bash
rojo serve
```

Ardından Studio Rojo eklentisiyle `default.project.json` projesine bağlan.

Rojo kullanmıyorsan dosyaları yukarıdaki Explorer konumlarına normal Script, LocalScript ve ModuleScript olarak yerleştir.

## 2. İzin ayarları

Studio içinde:

```text
Game Settings
└─ Security
   ├─ Allow HTTP Requests = ON
   └─ Allow Mesh / Image APIs = ON
```

HTTP yalnızca GitHub raw JSON yüklemek için gerekir. ServerStorage içindeki image module yöntemi HTTP gerektirmez.

## 3. Yetki

`src/ReplicatedStorage/AutoSpray/Config.lua`:

```lua
AdminUserIds = {
    [KENDI_USER_ID] = true,
},
```

Kişisel hesaba ait experience içinde oyun sahibi otomatik yetkilidir. Group-owned experience için UserId ekle.

Private server içinde herkese izin vermek istemiyorsan:

```lua
AllowAllPrivateServers = false
```

## 4. Importer eklentisi

`plugins/AutoSprayImporter.plugin.lua` dosyasını Studio içinde Plugin Script olarak aç ve **Save as Local Plugin** seçeneğiyle kaydet.

Toolbar:

```text
Auto Spray
└─ AutoSprayImporter
```

Akış:

1. `PC'DEN GÖRSEL SEÇ`
2. Çıktı genişlik/yükseklik değerini belirle.
3. Renk sayısını belirle. Maksimum 255 opak renk + şeffaf renk.
4. Dithering açıkken fotoğraflardaki geçişler daha iyi korunur.
5. `ADAPTİF PALETLE DÖNÜŞTÜR`
6. İki çıktı seçeneğinden birini kullan:
   - `MODÜL OLUŞTUR`: `ServerStorage/AutoSprayImages` altında ModuleScript oluşturur.
   - `GITHUB JSON KOPYALA`: sıkıştırılmış belgeyi panoya kopyalar.

## 5. GitHub JSON

Importer'da `GITHUB JSON KOPYALA` dedikten sonra GitHub deposunda örneğin:

```text
images/my-image.json
```

dosyasına yapıştır.

Dosyanın **Raw** bağlantısını oyun panelindeki URL alanına gir:

```text
https://raw.githubusercontent.com/KULLANICI/DEPO/main/images/my-image.json
```

İzin verilen domainler `Config.AllowedHttpHosts` tablosundadır.

## 6. Oyun içi kullanım

1. ModuleScript adını girip `MODÜLÜ YÜKLE` veya GitHub raw JSON girip `URL'DEN YÜKLE`.
2. Önizlemenin tamamlanmasını bekle.
3. `ÇİZİM ALANINI SEÇ`.
4. Aynı duvar yüzeyinde iki karşı köşe seç.
5. Klavyeden `1` tuşuna bas ve AutoSprayCan aracını kuşan.
6. `BAŞLAT`.

Kontroller:

```text
F6      Paneli göster/gizle
1       Spray aracını kuşan
ESC     Alan seçimini iptal et
```

## 7. Kalite ve süre

Kaynak görsel 1024×1024 veya daha büyük olabilir. Importer çıktısı en fazla 1024×1024 olarak ayarlanmıştır.

Pratik öneriler:

```text
64–128     Logo, ikon, basit çizim
128–256    Çoğu detaylı görsel
256–512    Yüksek detay, uzun çizim süresi
1024       1.048.576 piksel; test ve güçlü cihazlar için
```

Fotoğraflar için:

```text
Renk: 192–255
Dithering: Açık
```

Düz logo ve pixel art için:

```text
Renk: 32–128
Dithering: Kapalı
```

## 8. Sunucu görünürlüğü

Roblox `EditableImage` nesnesini doğrudan ağ üzerinden çoğaltmadığı için sunucu:

1. Yetkili piksel tamponunu saklar.
2. Stroke segmentlerini doğrular.
3. Segmentleri bütün istemcilere yollar.
4. Her istemci aynı replicated canvas part üzerinde kendi EditableImage renderer'ını oluşturur.
5. Sonradan giren oyuncuya canvas snapshot satırları gönderilir.

Bu nedenle resim diğer oyuncuların bakış açısından da görünür.

## 9. Gerçekçi spray

Sistem işletim sistemi faresini veya sahte sol tık girdisini kullanmaz. Oyunun içinde:

- Spray kutusu oluşturur.
- Nozzle ile duvar arasında Beam gösterir.
- Boya renginde parçacık üretir.
- Stroke başlangıçlarına giderken spray'i kapatır.
- Aynı renkli satırları spray açık biçimde tarar.
- Hafif el titremesi uygular.
- Spray hedef pozunu bütün oyunculara çoğaltır.

`Config.Realistic` ve `Config.Drawing` değerlerinden hız, jitter, beam genişliği ve segment boyutu değiştirilebilir.

## 10. Güvenli tuval parçaları

Yalnızca belirli duvarları boyatmak için:

```lua
RequireCanvasAttribute = true
```

Sonra boyanabilir Part'lara şu Attribute'u ekle:

```text
AutoSprayCanvas = true
```

## 11. Önemli sınırlar

- Runtime tarafı doğrudan PNG/JPG byte verisini çözmez. PNG/JPG dönüştürme Studio importer eklentisinde yapılır.
- Runtime URL alanı görsel URL'si değil, importer tarafından üretilen stroke JSON'un HTTPS URL'sidir.
- 1024×1024 desteklenir fakat ağ, bellek ve süre maliyeti yüksektir.
- Tamamlanan canvas mevcut oyun sunucusu boyunca kalır. Sunucu yeniden başladığında kalıcı olması için ayrıca DataStore tabanlı kayıt katmanı gerekir.
