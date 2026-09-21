-- ╔══════════════════════════════════════════════════════╗
-- ║          MAKARA Tool v4 — Luarmor-Style Loader       ║
-- ║   Paste THIS in your executor. Not the main script.  ║
-- ╚══════════════════════════════════════════════════════╝

-- ═══════════════════════════════
-- CONFIG — edit these 2 lines only
-- ═══════════════════════════════
local SCRIPT_URL = "https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/MAKARA_Tool_v4_fixed.lua"
local SCRIPT_KEY = "MAKARA4YOU"   -- set to nil if no key required: local SCRIPT_KEY = nil

-- ═══════════════════════════════
-- DO NOT EDIT BELOW
-- ═══════════════════════════════

local HttpService  = game:GetService("HttpService")
local Players      = game:GetService("Players")
local LP           = Players.LocalPlayer
local TweenService = game:GetService("TweenService")
local CoreGui      = game:GetService("CoreGui")

-- ───────────────────────────────
-- Splash screen
-- ───────────────────────────────
local function tryParent(gui)
    local ok = pcall(function() gui.Parent = CoreGui end)
    if not ok or gui.Parent ~= CoreGui then
        gui.Parent = LP.PlayerGui
    end
end

local SplashSG = Instance.new("ScreenGui")
SplashSG.Name = "MAKARASplash"
SplashSG.ResetOnSpawn = false
SplashSG.IgnoreGuiInset = true
tryParent(SplashSG)

local Overlay = Instance.new("Frame", SplashSG)
Overlay.Size = UDim2.new(1,0,1,0)
Overlay.BackgroundColor3 = Color3.fromRGB(5,5,10)
Overlay.BorderSizePixel = 0
Overlay.ZIndex = 100

local Card = Instance.new("Frame", Overlay)
Card.Size = UDim2.new(0,260,0,180)
Card.Position = UDim2.new(0.5,-130,0.5,-90)
Card.BackgroundColor3 = Color3.fromRGB(10,10,20)
Card.BorderSizePixel = 0
Card.ZIndex = 101
Instance.new("UICorner", Card).CornerRadius = UDim.new(0,14)
local cs = Instance.new("UIStroke", Card)
cs.Color = Color3.fromRGB(100,40,220); cs.Thickness = 1.4

local TopBar = Instance.new("Frame", Card)
TopBar.Size = UDim2.new(1,0,0,5)
TopBar.BackgroundColor3 = Color3.fromRGB(110,40,220)
TopBar.BorderSizePixel = 0
TopBar.ZIndex = 102
Instance.new("UICorner", TopBar).CornerRadius = UDim.new(0,14)
local TopFix = Instance.new("Frame", TopBar)
TopFix.Size = UDim2.new(1,0,0,5)
TopFix.Position = UDim2.new(0,0,1,-5)
TopFix.BackgroundColor3 = Color3.fromRGB(110,40,220)
TopFix.BorderSizePixel = 0
TopFix.ZIndex = 102

local function lbl(parent, text, y, ts, color, bold)
    local l = Instance.new("TextLabel", parent)
    l.Size = UDim2.new(1,-16,0,ts+4)
    l.Position = UDim2.new(0,8,0,y)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextSize = ts
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextColor3 = color or Color3.fromRGB(200,200,255)
    l.TextXAlignment = Enum.TextXAlignment.Center
    l.ZIndex = 102
    l.TextWrapped = true
    return l
end

local TitleL  = lbl(Card, "🥚 MAKARA Tool v4", 14, 18, Color3.fromRGB(255,255,255), true)
local SubL    = lbl(Card, "Loader — fetching script...", 38, 9, Color3.fromRGB(130,100,200))
local StatusL = lbl(Card, "⏳ Connecting...", 58, 10, Color3.fromRGB(200,200,100))
local KeyL    = lbl(Card, SCRIPT_KEY and ("🔑 Key: "..SCRIPT_KEY) or "🔑 No key required",
                    80, 8, Color3.fromRGB(100,200,100))

-- Progress bar
local PBBg = Instance.new("Frame", Card)
PBBg.Size = UDim2.new(1,-24,0,8)
PBBg.Position = UDim2.new(0,12,0,106)
PBBg.BackgroundColor3 = Color3.fromRGB(18,18,35)
PBBg.BorderSizePixel = 0
PBBg.ZIndex = 102
Instance.new("UICorner", PBBg).CornerRadius = UDim.new(0,4)

local PBFill = Instance.new("Frame", PBBg)
PBFill.Size = UDim2.new(0,0,1,0)
PBFill.BackgroundColor3 = Color3.fromRGB(110,40,220)
PBFill.BorderSizePixel = 0
PBFill.ZIndex = 103
Instance.new("UICorner", PBFill).CornerRadius = UDim.new(0,4)

local HwidL = lbl(Card, "HWID: "..(LP and tostring(LP.UserId) or "???").."_"..(LP and LP.Name or "???"),
                  122, 7, Color3.fromRGB(70,70,120))
local VerL  = lbl(Card, "v4.0 | Delta Mobile", 142, 8, Color3.fromRGB(80,60,140))

-- ───────────────────────────────
-- Progress animation helpers
-- ───────────────────────────────
local function setProgress(pct, statusText, statusColor)
    TweenService:Create(PBFill,
        TweenInfo.new(0.25, Enum.EasingStyle.Sine),
        {Size = UDim2.new(pct, 0, 1, 0)}
    ):Play()
    if statusText then
        StatusL.Text = statusText
        StatusL.TextColor3 = statusColor or Color3.fromRGB(200,200,100)
    end
end

local function closeSplash()
    TweenService:Create(Overlay,
        TweenInfo.new(0.4, Enum.EasingStyle.Sine),
        {BackgroundTransparency = 1}
    ):Play()
    TweenService:Create(Card,
        TweenInfo.new(0.35, Enum.EasingStyle.Sine),
        {BackgroundTransparency = 1}
    ):Play()
    task.delay(0.5, function()
        pcall(function() SplashSG:Destroy() end)
    end)
end

local function crashSplash(reason)
    setProgress(1, "❌ "..reason, Color3.fromRGB(255,80,80))
    PBFill.BackgroundColor3 = Color3.fromRGB(180,30,30)
    task.delay(4, function()
        pcall(function() SplashSG:Destroy() end)
    end)
end

-- ───────────────────────────────
-- Fade in splash
-- ───────────────────────────────
Overlay.BackgroundTransparency = 1
Card.BackgroundTransparency = 1
for i = 0, 10 do
    Overlay.BackgroundTransparency = 1 - i/10
    Card.BackgroundTransparency    = 1 - i/10
    task.wait(0.018)
end

-- ───────────────────────────────
-- Loader core
-- ───────────────────────────────
task.spawn(function()
    task.wait(0.2)

    -- Step 1: Key validation (client-side check before fetch)
    setProgress(0.15, "🔑 Validating key...", Color3.fromRGB(200,200,100))
    task.wait(0.3)

    if SCRIPT_KEY ~= nil then
        local keyOk = (type(SCRIPT_KEY) == "string" and #SCRIPT_KEY > 0)
        if not keyOk then
            crashSplash("Key is empty or invalid")
            return
        end
        setProgress(0.3, "✅ Key accepted", Color3.fromRGB(100,220,100))
    else
        setProgress(0.3, "✅ No key required", Color3.fromRGB(100,220,100))
    end
    task.wait(0.25)

    -- Step 2: Fetch script
    setProgress(0.5, "🌐 Fetching script...", Color3.fromRGB(200,200,100))
    SubL.Text = "Downloading from remote..."

    local rawScript = nil
    local fetchOk, fetchErr = pcall(function()
        rawScript = game:HttpGet(SCRIPT_URL, true)
    end)

    if not fetchOk or not rawScript or rawScript == "" then
        crashSplash("Fetch failed — check URL or internet")
        warn("[MAKARA Loader] Fetch error: " .. tostring(fetchErr))
        return
    end

    setProgress(0.72, "✅ Script fetched ("..math.floor(#rawScript/1024).."KB)", Color3.fromRGB(100,220,100))
    task.wait(0.2)

    -- Step 3: Inject key into script if script uses SCRIPT_KEY variable
    -- Also inject the free license key so the tool auto-activates
    if SCRIPT_KEY then
        -- Prepend key variable so any key-check in the fetched script can read it
        rawScript = 'local _LOADER_KEY = "'..tostring(SCRIPT_KEY)..'"\n' .. rawScript
    end

    -- Step 4: Compile and execute
    setProgress(0.88, "⚙️ Executing...", Color3.fromRGB(200,200,100))
    SubL.Text = "Running MAKARA Tool..."
    task.wait(0.15)

    local fn, compileErr = loadstring(rawScript)
    if not fn then
        crashSplash("Compile error — script may be obfuscated")
        warn("[MAKARA Loader] Compile err: " .. tostring(compileErr))
        return
    end

    local runOk, runErr = pcall(fn)
    if not runOk then
        crashSplash("Runtime error — "..tostring(runErr):sub(1,40))
        warn("[MAKARA Loader] Runtime err: " .. tostring(runErr))
        return
    end

    -- Step 5: Done
    setProgress(1, "✅ MAKARA Tool loaded!", Color3.fromRGB(100,255,150))
    SubL.Text = "Enjoy. 🥚"
    task.wait(1.2)
    closeSplash()
end)

