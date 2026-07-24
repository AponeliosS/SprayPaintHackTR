local Menu = {}

function Menu.Olustur(tiklamaFonksiyonu)
    -- Ekranda basit bir buton oluşturuyoruz
    local sg = Instance.new("ScreenGui", game:GetService("CoreGui"))
    local buton = Instance.new("TextButton", sg)
    buton.Size = UDim2.new(0, 200, 0, 50)
    buton.Position = UDim2.new(0.4, 0, 0.4, 0)
    buton.Text = "Otomatik Tiklamayi Tetikle"
    buton.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
    
    -- Butona basılınca main.lua'dan gelen fonksiyonu çalıştırır
    local aktif = false
    buton.MouseButton1Click:Connect(function()
        aktif = not aktif
        buton.Text = aktif and "CALISIYOR..." or "Otomatik Tiklamayi Tetikle"
        
        task.spawn(function()
            while aktif do
                tiklamaFonksiyonu() -- fonksiyonlar.lua'daki tıklamayı çağırır
                task.wait(0.1)
            end
        end)
    end)
end

return Menu
