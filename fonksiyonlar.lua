local Fonksiyonlar = {}

-- Otomatik tıklama eylemi
function Fonksiyonlar.otomatikTikla()
    -- Önceki mesajda bahsettiğimiz gizli sanal tıklama servisi
    local vim = game:GetService("VirtualInputManager")
    vim:SendMouseButtonEvent(500, 500, 0, true, game, 1) -- Fareye bas
    task.wait(0.05)
    vim:SendMouseButtonEvent(500, 500, 0, false, game, 1) -- Fareyi bırak
end

return Fonksiyonlar
