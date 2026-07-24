-- GitHub linklerinizden kodları canlı olarak indirip hafızaya yükler
-- (NOT: Buradaki linkleri kendi GitHub linklerinizle değiştireceksiniz)
local fonksiyonDeposu = loadstring(game:HttpGet("https://githubusercontent.com"))()
local menuDeposu = loadstring(game:HttpGet("https://githubusercontent.com"))()

-- Menüyü oluştur ve içine eylemi enjekte et!
menuDeposu.Olustur(fonksiyonDeposu.otomatikTikla)
