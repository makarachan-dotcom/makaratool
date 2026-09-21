-- ╔══════════════════════════════════════════════════════╗
-- ║         MAKARA Tool v4 — REBUILT FULL EDITION        ║
-- ║  Real Steal | License Gate | Smart Alert | Anti-Ban  ║
-- ╚══════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════
-- SERVICES
-- ═══════════════════════════════════════
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local HttpService      = game:GetService("HttpService")
local UIS              = game:GetService("UserInputService")
local WS               = game:GetService("Workspace")
local RS               = game:GetService("ReplicatedStorage")
local CoreGui          = game:GetService("CoreGui")
local StarterGui       = game:GetService("StarterGui")

-- Delta mobile: script may run before LocalPlayer exists — wait up to 10s
local LP = Players.LocalPlayer
if not LP then
    LP = Players:GetPropertyChangedSignal("LocalPlayer"):Wait() and Players.LocalPlayer
end
-- Hard fallback: poll until available
local _lpWait = 0
while not LP and _lpWait < 100 do
    task.wait(0.1)
    LP = Players.LocalPlayer
    _lpWait = _lpWait + 1
end
if not LP then error("[MAKARA] LocalPlayer never loaded — executor issue") end

-- ═══════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════
local FREE_LICENSE    = "MAKARA4YOU"
local VER             = "v4.0"
local ALERT_TIMEOUT   = 12   -- auto-grab after Ns
local LOG_MAX         = 10

-- Priority tiers
local TIER_S = {"legendary","mythic","godly","divine","celestial","omnipotent",
                "eternal","infinite","supreme","cosmic","astral","prismatic",
                "rainbow","glitched","corrupted","void","quantum","apex",
                "ultimate","omega","alpha","prime","ascended","awakened",
                "exclusive","dominus","ancient","crystal","diamond","golden",
                "limited","event","ultra","special","epic"}
local TIER_A = {"rare","uncommon","shiny","neon","bright","magic","enchanted",
                "sacred","radiant","spectral","nebula","aurora","eclipse",
                "dragon","shadow","phantom","spirit","elemental","arcane"}
local TIER_IGN = {"common","basic","starter","free","tutorial","normal",
                  "standard","default","plain","simple","ordinary","regular",
                  "beginner","novice","egg0","tester"}

local TIER_COLOR = {
    S = Color3.fromRGB(255,210,0),
    A = Color3.fromRGB(170,80,255),
    B = Color3.fromRGB(80,170,255),
    IGN = Color3.fromRGB(100,100,100),
    U = Color3.fromRGB(200,200,100),
}

-- ═══════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════
local State = {
    licensed      = false,
    licenseKey    = "",
    licenseType   = "",  -- "free" | "full"
    running       = false,
    guiVisible    = false,  -- starts hidden; show only after license
    totalStolen   = 0,
    sessionStart  = os.time(),
    logs          = {},
    knownEggs     = {},
    history       = {},
    filterS       = true,
    filterA       = true,
    filterU       = false,
    filterIGN     = false,
    mode          = 1,  -- 1=Safe 2=Fast 3=Ghost 4=Snipe
    espOn         = false,
    radarOn       = false,
    autoGrab      = true,
    alertPending  = false,
    espObjects    = {},
    tapCount      = 0,
    lastTap       = 0,
}

-- ═══════════════════════════════════════
-- MODES
-- ═══════════════════════════════════════
local MODES = {
    {name="🛡 Safe",    dMin=0.12, dMax=0.30, step=55,  tween=true},
    {name="⚡ Fast",    dMin=0.03, dMax=0.09, step=90,  tween=false},
    {name="👻 Ghost",   dMin=0.06, dMax=0.15, step=200, tween=false},
    {name="🎯 Snipe",   dMin=0.01, dMax=0.04, step=999, tween=false},
}

local function M() return MODES[State.mode] end

-- ═══════════════════════════════════════
-- LOGGER
-- ═══════════════════════════════════════
local LogLabel -- forward ref

local function log(msg)
    local t = os.date("%H:%M")
    table.insert(State.logs, 1, t.." "..msg)
    if #State.logs > LOG_MAX then table.remove(State.logs) end
    if LogLabel and LogLabel.Parent then
        LogLabel.Text = table.concat(State.logs, "\n")
    end
end

-- ═══════════════════════════════════════
-- EGG CLASSIFIER
-- ═══════════════════════════════════════
local function classifyEgg(name)
    local l = name:lower()
    if not l:find("egg") then return nil end
    for _,k in ipairs(TIER_IGN) do if l:find(k) then return "IGN" end end
    for _,k in ipairs(TIER_S)   do if l:find(k) then return "S"   end end
    for _,k in ipairs(TIER_A)   do if l:find(k) then return "A"   end end
    return "U"
end

local function getPos(obj)
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") then
        local pp = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
        if pp then return pp.Position end
    end
    return nil
end

local function eggId(e)
    return e.name
        ..math.floor(e.pos.X)
        ..math.floor(e.pos.Y)
        ..math.floor(e.pos.Z)
end

local function scanEggs()
    local results = {S={},A={},U={},IGN={}}
    local function recurse(parent)
        for _,obj in ipairs(parent:GetChildren()) do
            local n = obj.Name
            local tier = classifyEgg(n)
            if tier then
                local pos = getPos(obj)
                if pos then
                    local e = {object=obj, name=n, tier=tier, pos=pos}
                    table.insert(results[tier], e)
                end
            end
            -- recurse into children
            local ok,_ = pcall(function() recurse(obj) end)
        end
    end
    pcall(function() recurse(WS) end)
    return results
end

local function getFiltered(results)
    local out = {}
    if State.filterS   then for _,e in ipairs(results.S)   do table.insert(out,e) end end
    if State.filterA   then for _,e in ipairs(results.A)   do table.insert(out,e) end end
    if State.filterU   then for _,e in ipairs(results.U)   do table.insert(out,e) end end
    if State.filterIGN then for _,e in ipairs(results.IGN) do table.insert(out,e) end end
    return out
end

local function sortProx(eggs, pos)
    table.sort(eggs, function(a,b)
        return (a.pos-pos).Magnitude < (b.pos-pos).Magnitude
    end)
    return eggs
end

local function findNewEggs(results)
    local new = {}
    local cur = {}
    for _,tbl in pairs(results) do
        for _,e in ipairs(tbl) do
            local id = eggId(e)
            cur[id] = e
            if not State.knownEggs[id] then
                table.insert(new, e)
            end
        end
    end
    State.knownEggs = cur
    return new
end

-- ═══════════════════════════════════════
-- ANTI-BAN MOVEMENT
-- ═══════════════════════════════════════
local function mWait()
    local m = M()
    local d = math.random(math.floor(m.dMin*1000), math.floor(m.dMax*1000))/1000
    d = d + (math.random()-0.5)*0.02  -- micro-jitter
    task.wait(math.max(0.01, d))
end

local function safeTP(char, targetPos)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local m = M()
    local dist = (hrp.Position - targetPos).Magnitude
    if dist < 3 then return end

    if m.tween and dist < 50 then
        local dur = math.clamp(dist/24, 0.07, 0.5)
        TweenService:Create(hrp,
            TweenInfo.new(dur, Enum.EasingStyle.Sine),
            {CFrame=CFrame.new(targetPos+Vector3.new(0,2.5,0))}
        ):Play()
        task.wait(dur+0.03)
    else
        local dir = (targetPos-hrp.Position).Unit
        local steps = math.max(1, math.ceil(dist/m.step))
        local sd = dist/steps
        for i=1,steps do
            if not State.running then break end
            hrp.CFrame = CFrame.new(hrp.Position + dir*sd + Vector3.new(0,2.5,0))
            mWait()
        end
    end
end

-- ═══════════════════════════════════════
-- REAL STEAL ENGINE
-- ═══════════════════════════════════════
-- Collect ALL remotes once and cache
local cachedRemotes = nil
local lastRemoteScan = 0

local function getRemotes()
    local now = tick()
    if cachedRemotes and (now - lastRemoteScan) < 15 then
        return cachedRemotes
    end
    lastRemoteScan = now

    local remotes = {}
    local keywords = {
        "collect","grab","steal","egg","pickup","touch","get","take",
        "obtain","hatch","claim","receive","interact","catch","capture",
        "loot","farm","harvest"
    }

    local function scan(parent)
        for _,obj in ipairs(parent:GetDescendants()) do
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                local n = obj.Name:lower()
                for _,kw in ipairs(keywords) do
                    if n:find(kw) then
                        table.insert(remotes, obj)
                        break
                    end
                end
            end
        end
    end

    pcall(function() scan(RS) end)
    pcall(function()
        for _,name in ipairs({"Remotes","Events","Remote","Event","Shared","Network"}) do
            local f = RS:FindFirstChild(name)
            if f then scan(f) end
        end
    end)

    -- Also try workspace remotes
    pcall(function() scan(WS) end)

    cachedRemotes = remotes
    log("[Rem] Found "..#remotes.." remotes")
    return remotes
end

local function fireAll(eggObj)
    local remotes = getRemotes()
    -- Fire with egg object arg
    for _,r in ipairs(remotes) do
        if r:IsA("RemoteEvent") then
            pcall(function() r:FireServer(eggObj) end)
        elseif r:IsA("RemoteFunction") then
            pcall(function() r:InvokeServer(eggObj) end)
        end
        task.wait(0.015)
    end
    -- Fire with no arg (proximity-based games)
    for _,r in ipairs(remotes) do
        if r:IsA("RemoteEvent") then
            pcall(function() r:FireServer() end)
        end
        task.wait(0.01)
    end
    -- Fire with position
    local pos = getPos(eggObj)
    if pos then
        for _,r in ipairs(remotes) do
            if r:IsA("RemoteEvent") then
                pcall(function() r:FireServer(pos) end)
            end
            task.wait(0.01)
        end
    end
end

local function touchEgg(char, egg)
    -- Simulate humanoid walking into egg
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp then return end

    -- Get very close
    local dir = (egg.pos - hrp.Position)
    if dir.Magnitude > 0 then
        local closePos = egg.pos - dir.Unit * 1.5
        hrp.CFrame = CFrame.new(closePos + Vector3.new(0,1,0))
        task.wait(0.05)
    end

    -- Touch via ClickDetector if exists
    pcall(function()
        local obj = egg.object
        local cd = obj:FindFirstChildWhichIsA("ClickDetector")
            or (obj:IsA("Model") and obj:FindFirstChildWhichIsA("ClickDetector"))
        if cd then
            fireclickdetector(cd)
        end
    end)

    -- Touch via ProximityPrompt
    pcall(function()
        local obj = egg.object
        local pp = obj:FindFirstChildWhichIsA("ProximityPrompt")
            or (obj:IsA("Model") and obj:FindFirstChildWhichIsA("ProximityPrompt"))
        if pp then
            fireproximityprompt(pp)
        end
    end)
end

local function stealEgg(egg, char)
    if not char then return end
    -- Move to egg
    safeTP(char, egg.pos)
    mWait()
    -- Touch interactions
    touchEgg(char, egg)
    mWait()
    -- Fire all remotes
    fireAll(egg.object)
    mWait()

    State.totalStolen = State.totalStolen + 1
    table.insert(State.history, 1, {
        name=egg.name, tier=egg.tier, t=os.date("%H:%M:%S")
    })
    if #State.history > 50 then table.remove(State.history) end
    log("[+] "..egg.name.." ["..egg.tier.."]")
end

local function stealList(eggs, char)
    for _,egg in ipairs(eggs) do
        if not State.running then break end
        stealEgg(egg, char)
    end
end

-- ═══════════════════════════════════════
-- ESP
-- ═══════════════════════════════════════
local function clearESP()
    for _,obj in ipairs(State.espObjects) do
        pcall(function() obj:Destroy() end)
    end
    State.espObjects = {}
end

local function drawESP(egg)
    local adornee = egg.object:IsA("BasePart") and egg.object
        or egg.object:FindFirstChildWhichIsA("BasePart")
    if not adornee then return end

    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0,72,0,26)
    bb.StudsOffset = Vector3.new(0,4.5,0)
    bb.AlwaysOnTop = true
    bb.Adornee = adornee

    local fr = Instance.new("Frame", bb)
    fr.Size = UDim2.new(1,0,1,0)
    fr.BackgroundColor3 = Color3.fromRGB(0,0,0)
    fr.BackgroundTransparency = 0.45
    fr.BorderSizePixel = 0
    Instance.new("UICorner", fr).CornerRadius = UDim.new(0,4)

    local lbl = Instance.new("TextLabel", fr)
    lbl.Size = UDim2.new(1,0,1,0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = TIER_COLOR[egg.tier] or Color3.fromRGB(255,255,255)
    lbl.Text = "["..egg.tier.."] "..egg.name
    lbl.TextSize = 7
    lbl.Font = Enum.Font.GothamBold
    lbl.TextWrapped = true

    bb.Parent = SG  -- use SG instead of CoreGui for Delta mobile compatibility
    table.insert(State.espObjects, bb)
end

local function updateESP(results)
    clearESP()
    if not State.espOn then return end
    for tier, eggs in pairs(results) do
        if tier ~= "IGN" then
            for _,e in ipairs(eggs) do
                pcall(function() drawESP(e) end)
            end
        end
    end
end

-- ═══════════════════════════════════════
-- GUI HELPERS
-- ═══════════════════════════════════════
local function mkFrame(parent, props)
    local f = Instance.new("Frame", parent)
    f.Size = props.size or UDim2.new(1,0,0,20)
    f.Position = props.pos or UDim2.new(0,0,0,0)
    f.BackgroundColor3 = props.bg or Color3.fromRGB(12,12,20)
    f.BorderSizePixel = 0
    if props.radius then Instance.new("UICorner",f).CornerRadius=props.radius end
    if props.stroke then
        local s=Instance.new("UIStroke",f)
        s.Color=props.stroke
        s.Thickness=props.sw or 1.2
    end
    if props.z then f.ZIndex=props.z end
    return f
end

local function mkLabel(parent, props)
    local l = Instance.new("TextLabel", parent)
    l.Size = props.size or UDim2.new(1,0,0,18)
    l.Position = props.pos or UDim2.new(0,0,0,0)
    l.BackgroundTransparency = 1
    l.TextColor3 = props.color or Color3.fromRGB(200,200,255)
    l.Text = props.text or ""
    l.TextSize = props.ts or 10
    l.Font = props.font or Enum.Font.Gotham
    l.TextXAlignment = props.xa or Enum.TextXAlignment.Left
    l.TextYAlignment = props.ya or Enum.TextYAlignment.Center
    l.TextWrapped = props.wrap or false
    if props.z then l.ZIndex=props.z end
    return l
end

local function mkBtn(parent, props)
    local b = Instance.new("TextButton", parent)
    b.Size = props.size or UDim2.new(1,0,0,28)
    b.Position = props.pos or UDim2.new(0,0,0,0)
    b.BackgroundColor3 = props.bg or Color3.fromRGB(70,25,160)
    b.TextColor3 = props.tc or Color3.fromRGB(255,255,255)
    b.Text = props.text or ""
    b.TextSize = props.ts or 10
    b.Font = props.font or Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    if props.z then b.ZIndex=props.z end
    Instance.new("UICorner",b).CornerRadius = props.radius or UDim.new(0,7)
    if props.stroke then
        local s=Instance.new("UIStroke",b)
        s.Color=props.stroke
        s.Thickness=1
    end
    -- press animation
    b.MouseButton1Down:Connect(function()
        local orig = b.BackgroundColor3
        b.BackgroundColor3 = Color3.fromRGB(
            math.clamp(orig.R*255-30,0,255),
            math.clamp(orig.G*255-30,0,255),
            math.clamp(orig.B*255-30,0,255)
        )
        task.delay(0.1, function()
            if b and b.Parent then b.BackgroundColor3 = orig end
        end)
    end)
    return b
end

local function div(parent, y, col)
    local d=Instance.new("Frame",parent)
    d.Size=UDim2.new(1,0,0,1)
    d.Position=UDim2.new(0,0,0,y)
    d.BackgroundColor3=col or Color3.fromRGB(50,30,90)
    d.BorderSizePixel=0
    return d
end

local function notify(title, body, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification",{
            Title=title, Text=body, Duration=dur or 4
        })
    end)
end

-- ═══════════════════════════════════════
-- SCREEN GUI ROOT
-- ═══════════════════════════════════════
local SG = Instance.new("ScreenGui")
SG.Name = "MAKARAv4"
SG.ResetOnSpawn = false
SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
SG.IgnoreGuiInset = true

-- Delta mobile: CoreGui access often silently fails → full safe fallback chain
local function parentSG()
    -- Try CoreGui first
    local ok = pcall(function() SG.Parent = CoreGui end)
    if ok and SG.Parent == CoreGui then return end

    -- Try PlayerGui (LP already guaranteed non-nil from top)
    local pgOk = pcall(function()
        SG.Parent = LP:WaitForChild("PlayerGui", 8)
    end)
    if pgOk and SG.Parent then return end

    -- Last resort: poll PlayerGui
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    local tries = 0
    while not pg and tries < 40 do
        task.wait(0.1)
        pg = LP:FindFirstChildOfClass("PlayerGui")
        tries = tries + 1
    end
    if pg then
        pcall(function() SG.Parent = pg end)
    end
end
parentSG()

-- ═══════════════════════════════════════
-- LICENSE SCREEN (shows first)
-- ═══════════════════════════════════════
local LicScreen = mkFrame(SG, {
    size   = UDim2.new(1,0,1,0),
    bg     = Color3.fromRGB(6,6,12),
    z      = 50,
})

-- Background grid lines (aesthetic)
for i=1,8 do
    local hl=Instance.new("Frame",LicScreen)
    hl.Size=UDim2.new(1,0,0,1)
    hl.Position=UDim2.new(0,0,i/9,0)
    hl.BackgroundColor3=Color3.fromRGB(30,15,60)
    hl.BorderSizePixel=0
    hl.ZIndex=51
end
for i=1,5 do
    local vl=Instance.new("Frame",LicScreen)
    vl.Size=UDim2.new(0,1,1,0)
    vl.Position=UDim2.new(i/6,0,0,0)
    vl.BackgroundColor3=Color3.fromRGB(30,15,60)
    vl.BorderSizePixel=0
    vl.ZIndex=51
end

-- Center card
local LicCard = mkFrame(LicScreen, {
    size   = UDim2.new(0,280,0,260),
    pos    = UDim2.new(0.5,-140,0.5,-130),
    bg     = Color3.fromRGB(10,10,18),
    radius = UDim.new(0,14),
    stroke = Color3.fromRGB(100,40,210),
    sw     = 1.5,
    z      = 52,
})

-- Purple accent top bar
local LicTop = mkFrame(LicCard, {
    size   = UDim2.new(1,0,0,5),
    bg     = Color3.fromRGB(110,40,220),
    radius = UDim.new(0,14),
    z      = 53,
})
local LicTopFix = mkFrame(LicTop, {
    size=UDim2.new(1,0,0,5),
    pos=UDim2.new(0,0,1,-5),
    bg=Color3.fromRGB(110,40,220),z=53
})

-- Logo
local LicLogo = mkLabel(LicCard, {
    pos   = UDim2.new(0,0,0,12),
    size  = UDim2.new(1,0,0,36),
    text  = "🥚 MAKARA Tool",
    color = Color3.fromRGB(255,255,255),
    ts    = 20,
    font  = Enum.Font.GothamBold,
    xa    = Enum.TextXAlignment.Center,
    z     = 53,
})

local LicVer = mkLabel(LicCard, {
    pos   = UDim2.new(0,0,0,48),
    size  = UDim2.new(1,0,0,16),
    text  = VER.." | Egg Stealer",
    color = Color3.fromRGB(130,100,200),
    ts    = 9,
    xa    = Enum.TextXAlignment.Center,
    z     = 53,
})

div(LicCard, 70)

-- HWID display
local LicHwidL = mkLabel(LicCard, {
    pos   = UDim2.new(0,10,0,76),
    size  = UDim2.new(1,-20,0,14),
    text  = "HWID: "..(LP and tostring(LP.UserId) or "???").."_"..(LP and LP.Name or "???"),
    color = Color3.fromRGB(100,100,160),
    ts    = 8,
    xa    = Enum.TextXAlignment.Center,
    z     = 53,
})

-- Key input
local KeyBg = mkFrame(LicCard, {
    size   = UDim2.new(1,-20,0,34),
    pos    = UDim2.new(0,10,0,96),
    bg     = Color3.fromRGB(16,16,28),
    radius = UDim.new(0,8),
    stroke = Color3.fromRGB(80,40,160),
    z      = 53,
})

local KeyInput = Instance.new("TextBox", KeyBg)
KeyInput.Size = UDim2.new(1,-10,1,0)
KeyInput.Position = UDim2.new(0,5,0,0)
KeyInput.BackgroundTransparency = 1
KeyInput.TextColor3 = Color3.fromRGB(220,220,255)
KeyInput.PlaceholderText = "🔑 Enter license key..."
KeyInput.PlaceholderColor3 = Color3.fromRGB(80,70,120)
KeyInput.Text = ""
KeyInput.TextSize = 11
KeyInput.Font = Enum.Font.GothamBold
KeyInput.ClearTextOnFocus = false
KeyInput.ZIndex = 54

local LicStatusL = mkLabel(LicCard, {
    pos   = UDim2.new(0,10,0,136),
    size  = UDim2.new(1,-20,0,18),
    text  = "ដាក់ license key រួចចុច Activate",
    color = Color3.fromRGB(150,150,200),
    ts    = 9,
    xa    = Enum.TextXAlignment.Center,
    z     = 53,
})

local LicFreeHint = mkLabel(LicCard, {
    pos   = UDim2.new(0,10,0,156),
    size  = UDim2.new(1,-20,0,16),
    text  = "Free key: MAKARA4YOU (limited features)",
    color = Color3.fromRGB(100,180,100),
    ts    = 8,
    xa    = Enum.TextXAlignment.Center,
    z     = 53,
})

local ActivateBtn = mkBtn(LicCard, {
    pos    = UDim2.new(0,10,0,178),
    size   = UDim2.new(1,-20,0,32),
    bg     = Color3.fromRGB(90,35,200),
    text   = "🔓 ACTIVATE",
    ts     = 12,
    font   = Enum.Font.GothamBold,
    z      = 53,
    stroke = Color3.fromRGB(140,80,255),
})

local LicHwidCopy = mkBtn(LicCard, {
    pos    = UDim2.new(0,10,0,216),
    size   = UDim2.new(1,-20,0,26),
    bg     = Color3.fromRGB(30,60,130),
    text   = "📋 Copy HWID",
    ts     = 10,
    z      = 53,
})

LicHwidCopy.MouseButton1Click:Connect(function()
    pcall(function() setclipboard((LP and tostring(LP.UserId) or "???").."_"..(LP and LP.Name or "???")) end)
    LicHwidCopy.Text = "✅ Copied!"
    task.delay(1.5, function()
        if LicHwidCopy and LicHwidCopy.Parent then
            LicHwidCopy.Text = "📋 Copy HWID"
        end
    end)
end)

-- ═══════════════════════════════════════
-- MAIN TOOL (hidden until licensed)
-- ═══════════════════════════════════════
local MainFrame = mkFrame(SG, {
    size   = UDim2.new(0,268,0,520),
    pos    = UDim2.new(0,14,0.5,-260),
    bg     = Color3.fromRGB(9,9,16),
    radius = UDim.new(0,12),
    stroke = Color3.fromRGB(90,35,185),
    sw     = 1.3,
    z      = 10,
})
MainFrame.Visible = false

-- Title bar
local TBar = mkFrame(MainFrame, {
    size   = UDim2.new(1,0,0,36),
    bg     = Color3.fromRGB(62,20,145),
    radius = UDim.new(0,12),
    z      = 11,
})
mkFrame(TBar,{size=UDim2.new(1,0,0,12),pos=UDim2.new(0,0,1,-12),bg=Color3.fromRGB(62,20,145),z=11})

local TitleL = mkLabel(TBar, {
    pos   = UDim2.new(0,10,0,0),
    size  = UDim2.new(1,-70,1,0),
    text  = "🥚 MAKARA Tool "..VER,
    color = Color3.fromRGB(255,255,255),
    ts    = 12,
    font  = Enum.Font.GothamBold,
    z     = 12,
})

-- Hide btn (single click)
local HideBtn = mkBtn(TBar, {
    pos    = UDim2.new(1,-30,0,5),
    size   = UDim2.new(0,24,0,26),
    bg     = Color3.fromRGB(90,32,180),
    text   = "👁",
    ts     = 12,
    radius = UDim.new(0,6),
    z      = 12,
})

-- License badge
local LicBadge = mkLabel(TBar, {
    pos   = UDim2.new(1,-58,0,6),
    size  = UDim2.new(0,26,0,14),
    text  = "FREE",
    color = Color3.fromRGB(100,220,100),
    ts    = 7,
    font  = Enum.Font.GothamBold,
    xa    = Enum.TextXAlignment.Center,
    z     = 12,
})

-- ── TABS ──
local TABS = {"🏠","⚙️","🎯","📊","📋"}
local tabPages = {}
local tabBtns  = {}
local curTab   = 1

local TabBar = mkFrame(MainFrame, {
    size   = UDim2.new(1,-10,0,24),
    pos    = UDim2.new(0,5,0,40),
    bg     = Color3.fromRGB(14,14,24),
    radius = UDim.new(0,7),
    z      = 11,
})

for i,icon in ipairs(TABS) do
    local tb = mkBtn(TabBar, {
        pos    = UDim2.new((i-1)/#TABS,1,0,2),
        size   = UDim2.new(1/#TABS,-2,1,-4),
        bg     = i==1 and Color3.fromRGB(80,30,170) or Color3.fromRGB(18,18,32),
        text   = icon,
        ts     = 12,
        radius = UDim.new(0,5),
        z      = 12,
    })
    tabBtns[i] = tb

    local pg = Instance.new("Frame", MainFrame)
    pg.Size = UDim2.new(1,-10,1,-74)
    pg.Position = UDim2.new(0,5,0,68)
    pg.BackgroundTransparency = 1
    pg.Visible = (i==1)
    tabPages[i] = pg
end

local function switchTab(idx)
    curTab = idx
    for i,pg in ipairs(tabPages) do
        pg.Visible = (i==idx)
        tabBtns[i].BackgroundColor3 = i==idx
            and Color3.fromRGB(80,30,170)
            or  Color3.fromRGB(18,18,32)
    end
end
for i,tb in ipairs(tabBtns) do
    tb.MouseButton1Click:Connect(function() switchTab(i) end)
end

-- ═══════════════════════════════════════
-- TAB 1: HOME
-- ═══════════════════════════════════════
local P1 = tabPages[1]
local y1 = 0

local function L1(text, color, h)
    local l = mkLabel(P1,{
        pos=UDim2.new(0,0,0,y1),
        size=UDim2.new(1,0,0,h or 18),
        text=text, color=color or Color3.fromRGB(185,185,255), ts=10,
    })
    y1 = y1+(h or 18)+2
    return l
end
local function B1(text, bg, h)
    local b = mkBtn(P1,{
        pos=UDim2.new(0,0,0,y1),
        size=UDim2.new(1,0,0,h or 28),
        bg=bg or Color3.fromRGB(70,25,160),
        text=text, ts=10,
    })
    y1 = y1+(h or 28)+3
    return b
end
local function B1Half(text, xs, xo, bg, h)
    return mkBtn(P1,{
        pos=UDim2.new(xs,xo,0,y1),
        size=UDim2.new(0.49,0,0,h or 26),
        bg=bg, text=text, ts=10,
    })
end
local function D1() div(P1, y1+2); y1=y1+6 end

-- Status
local StatusL = L1("📋 ស្ថានភាព: Licensed ✅ Ready", Color3.fromRGB(100,255,150))
local LicTypeL = L1("🔑 License: FREE | Limited", Color3.fromRGB(255,200,50))
D1()

-- Egg stats
local EggStatL = L1("🥚 S:0 | A:0 | U:0 | 📦 Stolen:0", Color3.fromRGB(100,255,150))
D1()

-- Log
local LogBg = mkFrame(P1, {
    pos=UDim2.new(0,0,0,y1),
    size=UDim2.new(1,0,0,70),
    bg=Color3.fromRGB(12,12,20),
    radius=UDim.new(0,7),
})
LogLabel = mkLabel(LogBg, {
    pos=UDim2.new(0,4,0,3),
    size=UDim2.new(1,-8,1,-6),
    text="📜 Log...",
    color=Color3.fromRGB(130,130,180),
    ts=9, font=Enum.Font.Code,
    ya=Enum.TextYAlignment.Top, wrap=true,
})
y1 = y1+74
D1()

-- ESP / Radar toggles
local ESPLabel  = L1("👁 ESP: OFF | 📡 Radar: OFF", Color3.fromRGB(200,200,100))
local ESPBtn    = B1Half("ESP: OFF", 0,0, Color3.fromRGB(55,55,20))
local RadarBtn  = B1Half("Radar: OFF", 0.51,0, Color3.fromRGB(20,60,120))
y1 = y1+29
D1()

-- Mode display
local ModeL = L1("⚙️ Mode: 🛡 Safe | F9=Next", Color3.fromRGB(200,200,255))
D1()

-- Filter quick toggle
local FilterL = L1("🎯 Filter: S✅ A✅ U❌", Color3.fromRGB(100,220,255))
D1()

-- Start / Stop
local StartBtn = B1Half("▶ ចាប់ផ្ដើម", 0,0, Color3.fromRGB(0,140,62))
local StopBtn  = B1Half("⏹ ឈប់", 0.51,0, Color3.fromRGB(165,28,28))
y1 = y1+29

D1()

-- Change license btn
local ChangeLicBtn = B1("🔑 Change / Upgrade License", Color3.fromRGB(40,40,130), 24)

ESPBtn.MouseButton1Click:Connect(function()
    State.espOn = not State.espOn
    ESPBtn.Text = "ESP: "..(State.espOn and "ON" or "OFF")
    ESPLabel.Text = "👁 ESP: "..(State.espOn and "ON" or "OFF").." | 📡 Radar: "..(State.radarOn and "ON" or "OFF")
    if not State.espOn then clearESP() end
    log("[ESP] "..(State.espOn and "ON" or "OFF"))
end)

RadarBtn.MouseButton1Click:Connect(function()
    State.radarOn = not State.radarOn
    RadarBtn.Text = "Radar: "..(State.radarOn and "ON" or "OFF")
    ESPLabel.Text = "👁 ESP: "..(State.espOn and "ON" or "OFF").." | 📡 Radar: "..(State.radarOn and "ON" or "OFF")
    log("[Radar] "..(State.radarOn and "ON" or "OFF"))
end)

ChangeLicBtn.MouseButton1Click:Connect(function()
    -- Show license screen again
    LicScreen.Visible = true
    MainFrame.Visible = false
    State.running = false
    log("[Lic] Switching license")
end)

-- ═══════════════════════════════════════
-- TAB 2: MODES
-- ═══════════════════════════════════════
local P2 = tabPages[2]

mkLabel(P2,{pos=UDim2.new(0,0,0,0),size=UDim2.new(1,0,0,20),
    text="⚙️ Mode — double-tap anytime",
    color=Color3.fromRGB(200,200,255),ts=11,font=Enum.Font.GothamBold})

local mBtns = {}
for i,m in ipairs(MODES) do
    local row = math.floor((i-1)/2)
    local col = (i-1)%2
    local mb = mkBtn(P2,{
        pos=UDim2.new(col*0.51,0,0,24+row*60),
        size=UDim2.new(0.49,0,0,56),
        bg=Color3.fromRGB(25+i*10, 20+i*5, 40+i*15),
        text=m.name.."\n".."Delay: "..m.dMin.."–"..m.dMax.."s\nStep: "..m.step.."st",
        ts=9, font=Enum.Font.Gotham,
    })
    mb.TextWrapped = true
    mBtns[i] = mb

    mb.MouseButton1Click:Connect(function()
        State.mode = i
        ModeL.Text = "⚙️ Mode: "..m.name
        for j,b in ipairs(mBtns) do
            for _,c in ipairs(b:GetChildren()) do
                if c:IsA("UIStroke") then c:Destroy() end
            end
        end
        local hs=Instance.new("UIStroke",mb)
        hs.Color=Color3.fromRGB(255,240,80); hs.Thickness=2
        log("[Mode] "..m.name)
        if State.running then
            StatusL.Text = "📋 🟢 "..m.name
        end
    end)
end
-- Highlight default
local hs=Instance.new("UIStroke",mBtns[1])
hs.Color=Color3.fromRGB(255,240,80); hs.Thickness=2

-- Auto-grab toggle
mkLabel(P2,{pos=UDim2.new(0,0,0,148),size=UDim2.new(1,0,0,18),
    text="🤖 Auto-grab new eggs:",
    color=Color3.fromRGB(200,200,255),ts=10,font=Enum.Font.GothamBold})

local AGLabel = mkLabel(P2,{pos=UDim2.new(0,0,0,168),size=UDim2.new(1,0,0,16),
    text="Auto-grab: ON (waits "..ALERT_TIMEOUT.."s then grabs)",
    color=Color3.fromRGB(100,220,100),ts=9})

local AGBtn = mkBtn(P2,{pos=UDim2.new(0,0,0,186),size=UDim2.new(1,0,0,26),
    bg=Color3.fromRGB(0,130,60),text="Auto-Grab: ON",ts=10})
AGBtn.MouseButton1Click:Connect(function()
    State.autoGrab = not State.autoGrab
    AGBtn.BackgroundColor3 = State.autoGrab and Color3.fromRGB(0,130,60) or Color3.fromRGB(120,30,30)
    AGBtn.Text = "Auto-Grab: "..(State.autoGrab and "ON" or "OFF")
    AGLabel.Text = "Auto-grab: "..(State.autoGrab and "ON" or "OFF")
    log("[AutoGrab] "..(State.autoGrab and "ON" or "OFF"))
end)

-- Remote rescan
local RescanBtn = mkBtn(P2,{pos=UDim2.new(0,0,0,220),size=UDim2.new(1,0,0,26),
    bg=Color3.fromRGB(40,40,120),text="🔄 Rescan Remotes (reset cache)",ts=10})
RescanBtn.MouseButton1Click:Connect(function()
    cachedRemotes = nil
    lastRemoteScan = 0
    local r = getRemotes()
    RescanBtn.Text = "✅ Found "..#r.." remotes"
    task.delay(2, function()
        if RescanBtn and RescanBtn.Parent then
            RescanBtn.Text = "🔄 Rescan Remotes"
        end
    end)
end)

-- ═══════════════════════════════════════
-- TAB 3: FILTER
-- ═══════════════════════════════════════
local P3 = tabPages[3]

mkLabel(P3,{pos=UDim2.new(0,0,0,0),size=UDim2.new(1,0,0,20),
    text="🎯 Egg Filter Settings",
    color=Color3.fromRGB(200,200,255),ts=11,font=Enum.Font.GothamBold})

local tiers = {
    {key="filterS",  label="⭐ S-Tier (Legendary/Mythic/...)", color=TIER_COLOR.S,   default=true},
    {key="filterA",  label="💜 A-Tier (Rare/Epic/Event/...)",  color=TIER_COLOR.A,   default=true},
    {key="filterU",  label="❓ Unknown (unrecognized names)",  color=TIER_COLOR.U,   default=false},
    {key="filterIGN",label="⬜ Common/Basic (usually skip)",   color=TIER_COLOR.IGN, default=false},
}

local tToggleBtns = {}
for i,t in ipairs(tiers) do
    local bg = mkFrame(P3,{
        pos=UDim2.new(0,0,0,24+(i-1)*50),
        size=UDim2.new(1,0,0,46),
        bg=Color3.fromRGB(14,14,24),
        radius=UDim.new(0,8),
    })
    mkLabel(bg,{pos=UDim2.new(0,8,0,4),size=UDim2.new(0.72,0,0,18),
        text=t.label,color=t.color,ts=10,font=Enum.Font.GothamBold})

    local exText = i==1 and "Legendary, Mythic, Godly, Divine..."
        or i==2 and "Rare, Epic, Event, Limited, Ultra..."
        or i==3 and "Egg names not in any known list"
        or         "Common, Basic, Starter, Free..."
    mkLabel(bg,{pos=UDim2.new(0,8,0,24),size=UDim2.new(0.72,0,0,16),
        text=exText,color=Color3.fromRGB(110,110,160),ts=8,wrap=true})

    local on = State[t.key]
    local tb = mkBtn(bg,{
        pos=UDim2.new(1,-54,0,12),
        size=UDim2.new(0,50,0,22),
        bg=on and Color3.fromRGB(0,130,60) or Color3.fromRGB(110,25,25),
        text=on and "ON" or "OFF", ts=10,
        radius=UDim.new(0,6),
    })
    tToggleBtns[i] = {btn=tb, key=t.key}

    tb.MouseButton1Click:Connect(function()
        State[t.key] = not State[t.key]
        local v = State[t.key]
        tb.Text = v and "ON" or "OFF"
        tb.BackgroundColor3 = v and Color3.fromRGB(0,130,60) or Color3.fromRGB(110,25,25)
        -- update quick filter label on home tab
        FilterL.Text = "🎯 Filter: S"..(State.filterS and "✅" or "❌")
            .." A"..(State.filterA and "✅" or "❌")
            .." U"..(State.filterU and "✅" or "❌")
        log("[Filter] "..t.key..": "..(v and "ON" or "OFF"))
    end)
end

-- Presets
mkLabel(P3,{pos=UDim2.new(0,0,0,226),size=UDim2.new(1,0,0,16),
    text="⚡ Presets:",color=Color3.fromRGB(200,200,255),ts=10,font=Enum.Font.GothamBold})

local function applyPreset(s,a,u,ign)
    State.filterS=s; State.filterA=a; State.filterU=u; State.filterIGN=ign
    for i,t in ipairs(tiers) do
        local v=State[t.key]
        tToggleBtns[i].btn.Text=v and "ON" or "OFF"
        tToggleBtns[i].btn.BackgroundColor3=v and Color3.fromRGB(0,130,60) or Color3.fromRGB(110,25,25)
    end
    FilterL.Text="🎯 Filter: S"..(s and "✅" or "❌").." A"..(a and "✅" or "❌").." U"..(u and "✅" or "❌")
end

local pa=mkBtn(P3,{pos=UDim2.new(0,0,0,244),size=UDim2.new(0.32,-2,0,24),
    bg=Color3.fromRGB(40,40,120),text="All ON",ts=9,radius=UDim.new(0,6)})
local pb=mkBtn(P3,{pos=UDim2.new(0.34,0,0,244),size=UDim2.new(0.32,-2,0,24),
    bg=Color3.fromRGB(80,40,20),text="S+A Only",ts=9,radius=UDim.new(0,6)})
local pc=mkBtn(P3,{pos=UDim2.new(0.68,0,0,244),size=UDim2.new(0.32,0,0,24),
    bg=Color3.fromRGB(80,20,20),text="All OFF",ts=9,radius=UDim.new(0,6)})

pa.MouseButton1Click:Connect(function() applyPreset(true,true,true,true) log("[Filter] All ON") end)
pb.MouseButton1Click:Connect(function() applyPreset(true,true,false,false) log("[Filter] S+A") end)
pc.MouseButton1Click:Connect(function() applyPreset(false,false,false,false) log("[Filter] All OFF") end)

-- ═══════════════════════════════════════
-- TAB 4: STATS
-- ═══════════════════════════════════════
local P4 = tabPages[4]

mkLabel(P4,{pos=UDim2.new(0,0,0,0),size=UDim2.new(1,0,0,20),
    text="📊 Session Statistics",color=Color3.fromRGB(200,200,255),ts=11,font=Enum.Font.GothamBold})

local SBg = mkFrame(P4,{pos=UDim2.new(0,0,0,24),size=UDim2.new(1,0,0,120),
    bg=Color3.fromRGB(12,12,22),radius=UDim.new(0,8)})

local TotL     = mkLabel(SBg,{pos=UDim2.new(0,8,0,5), size=UDim2.new(1,-16,0,18),
    text="📦 Total: 0",color=Color3.fromRGB(100,255,150),ts=12,font=Enum.Font.GothamBold})
local SessL    = mkLabel(SBg,{pos=UDim2.new(0,8,0,26),size=UDim2.new(1,-16,0,16),
    text="⏱ Session: 0s",color=Color3.fromRGB(180,180,255),ts=10})
local RateL    = mkLabel(SBg,{pos=UDim2.new(0,8,0,44),size=UDim2.new(1,-16,0,16),
    text="⚡ Rate: 0/min",color=Color3.fromRGB(255,200,100),ts=10})
local ModeSL   = mkLabel(SBg,{pos=UDim2.new(0,8,0,62),size=UDim2.new(1,-16,0,16),
    text="⚙️ Mode: Safe",color=Color3.fromRGB(200,200,255),ts=10})
local LicSL    = mkLabel(SBg,{pos=UDim2.new(0,8,0,80),size=UDim2.new(1,-16,0,16),
    text="🔑 License: FREE",color=Color3.fromRGB(255,200,50),ts=10})
local RemSL    = mkLabel(SBg,{pos=UDim2.new(0,8,0,98),size=UDim2.new(1,-16,0,16),
    text="📡 Remotes: 0 found",color=Color3.fromRGB(180,180,255),ts=10})

-- History scroll
mkLabel(P4,{pos=UDim2.new(0,0,0,150),size=UDim2.new(1,0,0,16),
    text="📋 Steal History:",color=Color3.fromRGB(200,200,255),ts=10,font=Enum.Font.GothamBold})

local HistSF = Instance.new("ScrollingFrame", P4)
HistSF.Size = UDim2.new(1,0,0,230)
HistSF.Position = UDim2.new(0,0,0,168)
HistSF.BackgroundTransparency = 1
HistSF.ScrollBarThickness = 3
HistSF.ScrollBarImageColor3 = Color3.fromRGB(80,40,160)
HistSF.BorderSizePixel = 0
local HistLayout = Instance.new("UIListLayout", HistSF)
HistLayout.SortOrder = Enum.SortOrder.LayoutOrder
HistLayout.Padding = UDim.new(0,2)

local function refreshHistory()
    for _,c in ipairs(HistSF:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    for i,h in ipairs(State.history) do
        if i>25 then break end
        local r=mkFrame(HistSF,{
            size=UDim2.new(1,0,0,18),
            bg=i%2==0 and Color3.fromRGB(16,16,28) or Color3.fromRGB(12,12,20),
            radius=UDim.new(0,4),
        })
        r.LayoutOrder=i
        mkLabel(r,{pos=UDim2.new(0,4,0,0),size=UDim2.new(1,-8,1,0),
            text=h.t.." ["..h.tier.."] "..h.name,
            color=TIER_COLOR[h.tier] or Color3.fromRGB(200,200,200),ts=9,font=Enum.Font.Code})
    end
    HistSF.CanvasSize = UDim2.new(0,0,0,math.min(#State.history,25)*20)
end

-- ═══════════════════════════════════════
-- TAB 5: FULL LOG
-- ═══════════════════════════════════════
local P5 = tabPages[5]

mkLabel(P5,{pos=UDim2.new(0,0,0,0),size=UDim2.new(1,0,0,20),
    text="📋 Full Log",color=Color3.fromRGB(200,200,255),ts=11,font=Enum.Font.GothamBold})

local FLogSF = Instance.new("ScrollingFrame", P5)
FLogSF.Size = UDim2.new(1,0,0,360)
FLogSF.Position = UDim2.new(0,0,0,24)
FLogSF.BackgroundTransparency = 1
FLogSF.ScrollBarThickness = 3
FLogSF.BorderSizePixel = 0
local FLogLayout = Instance.new("UIListLayout",FLogSF)
FLogLayout.SortOrder = Enum.SortOrder.LayoutOrder

local function refreshFullLog()
    for _,c in ipairs(FLogSF:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    for i,line in ipairs(State.logs) do
        local r=mkFrame(FLogSF,{
            size=UDim2.new(1,0,0,16),
            bg=Color3.fromRGB(12,12,20),radius=UDim.new(0,3)
        })
        r.LayoutOrder=i
        mkLabel(r,{pos=UDim2.new(0,3,0,0),size=UDim2.new(1,-6,1,0),
            text=line,color=Color3.fromRGB(150,150,200),ts=9,font=Enum.Font.Code})
    end
    FLogSF.CanvasSize=UDim2.new(0,0,0,#State.logs*18)
end

local ClrBtn=mkBtn(P5,{pos=UDim2.new(0,0,0,388),size=UDim2.new(1,0,0,24),
    bg=Color3.fromRGB(80,20,20),text="🗑 Clear Log",ts=10})
ClrBtn.MouseButton1Click:Connect(function()
    State.logs={}
    refreshFullLog()
end)

-- ═══════════════════════════════════════
-- ALERT SYSTEM (shows even when hidden)
-- ═══════════════════════════════════════
local AlertF = mkFrame(SG,{
    size=UDim2.new(0,248,0,130),
    pos=UDim2.new(0.5,-124,0.5,-65),
    bg=Color3.fromRGB(10,10,20),
    radius=UDim.new(0,12),
    stroke=Color3.fromRGB(255,200,50),sw=1.5,
    z=100,
})
AlertF.Visible = false

local ATierBar=mkFrame(AlertF,{size=UDim2.new(1,0,0,5),bg=Color3.fromRGB(255,200,50),z=101})
local ATitleL=mkLabel(AlertF,{
    pos=UDim2.new(0,6,0,8),size=UDim2.new(1,-12,0,22),
    text="🥚 Egg ថ្មី!",color=Color3.fromRGB(255,220,60),
    ts=12,font=Enum.Font.GothamBold,z=101})
local ABodyL=mkLabel(AlertF,{
    pos=UDim2.new(0,6,0,32),size=UDim2.new(1,-12,0,46),
    text="",color=Color3.fromRGB(190,190,255),ts=9,wrap=true,z=101})
local ATimerL=mkLabel(AlertF,{
    pos=UDim2.new(0,6,0,32),size=UDim2.new(1,-12,0,16),
    text="",color=Color3.fromRGB(200,200,100),ts=9,
    xa=Enum.TextXAlignment.Right,z=101})
local AYesBtn=mkBtn(AlertF,{
    pos=UDim2.new(0,6,0,94),size=UDim2.new(0.48,0,0,28),
    bg=Color3.fromRGB(0,138,62),text="✅ យក!",ts=11,z=101})
local ANoBtn=mkBtn(AlertF,{
    pos=UDim2.new(0.52,0,0,94),size=UDim2.new(0.48,-6,0,28),
    bg=Color3.fromRGB(165,28,28),text="❌ Skip",ts=11,z=101})

local alertCb = nil
local alertTimer = nil

local function dismissAlert()
    AlertF.Visible = false
    State.alertPending = false
    if alertTimer then pcall(function() task.cancel(alertTimer) end) alertTimer=nil end
    alertCb = nil
end

local function showAlert(title, body, tier, onYes, onNo)
    if State.alertPending then return end
    State.alertPending = true
    ATierBar.BackgroundColor3 = TIER_COLOR[tier] or Color3.fromRGB(255,200,50)
    ATitleL.Text = title
    ATitleL.TextColor3 = TIER_COLOR[tier] or Color3.fromRGB(255,220,60)
    ABodyL.Text = body
    AlertF.Visible = true
    alertCb = {yes=onYes, no=onNo}

    -- Auto-grab countdown
    if State.autoGrab then
        local tLeft = ALERT_TIMEOUT
        alertTimer = task.spawn(function()
            while tLeft > 0 do
                task.wait(1)
                tLeft = tLeft-1
                if ATimerL and ATimerL.Parent then
                    ATimerL.Text = "⏱ "..tLeft.."s"
                end
            end
            local cb = alertCb
            dismissAlert()
            if cb and cb.yes then task.spawn(cb.yes) end
        end)
    end
end

AYesBtn.MouseButton1Click:Connect(function()
    local cb = alertCb
    dismissAlert()
    if cb and cb.yes then task.spawn(cb.yes) end
end)
ANoBtn.MouseButton1Click:Connect(function()
    local cb = alertCb
    dismissAlert()
    if cb and cb.no then cb.no() end
end)

-- Multi alert
local MF = mkFrame(SG,{
    size=UDim2.new(0,252,0,230),
    pos=UDim2.new(0.5,-126,0.5,-115),
    bg=Color3.fromRGB(10,10,20),
    radius=UDim.new(0,12),
    stroke=Color3.fromRGB(255,200,50),sw=1.5,
    z=100,
})
MF.Visible=false

mkLabel(MF,{pos=UDim2.new(0,6,0,6),size=UDim2.new(1,-12,0,20),
    text="🥚 Egg ច្រើនថ្មី — ជ្រើស:",
    color=Color3.fromRGB(255,220,60),ts=11,font=Enum.Font.GothamBold,z=101})

local MSF = Instance.new("ScrollingFrame",MF)
MSF.Size=UDim2.new(1,-8,0,120)
MSF.Position=UDim2.new(0,4,0,30)
MSF.BackgroundTransparency=1
MSF.ScrollBarThickness=3
MSF.ZIndex=101
local MLayout=Instance.new("UIListLayout",MSF)
MLayout.SortOrder=Enum.SortOrder.LayoutOrder
MLayout.Padding=UDim.new(0,2)

local MAllBtn=mkBtn(MF,{pos=UDim2.new(0,4,0,156),size=UDim2.new(0.49,0,0,24),
    bg=Color3.fromRGB(0,130,60),text="✅ ទាំងអស់",ts=10,z=101})
local MSelBtn=mkBtn(MF,{pos=UDim2.new(0.51,0,0,156),size=UDim2.new(0.49,-4,0,24),
    bg=Color3.fromRGB(70,25,160),text="✔ Selected",ts=10,z=101})
local MNoBtn=mkBtn(MF,{pos=UDim2.new(0,4,0,184),size=UDim2.new(1,-8,0,22),
    bg=Color3.fromRGB(120,20,20),text="❌ Cancel",ts=10,z=101})
local MCountL=mkLabel(MF,{pos=UDim2.new(0,4,0,210),size=UDim2.new(1,-8,0,14),
    text="Sel: 0",color=Color3.fromRGB(180,180,255),ts=9,z=101,
    xa=Enum.TextXAlignment.Center})

local mSel={}, mEggs={}, mCb=nil, mCount=0

local function showMultiAlert(eggs, cb)
    if State.alertPending then return end
    State.alertPending=true
    mEggs=eggs; mSel={}; mCb=cb; mCount=0
    MCountL.Text="Sel: 0"
    for _,c in ipairs(MSF:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    for i,e in ipairs(eggs) do
        local r=mkFrame(MSF,{size=UDim2.new(1,0,0,22),bg=Color3.fromRGB(14,14,24),radius=UDim.new(0,5)})
        r.LayoutOrder=i; r.ZIndex=102
        local chk=mkBtn(r,{pos=UDim2.new(0,2,0,2),size=UDim2.new(0,18,0,18),
            bg=Color3.fromRGB(25,25,42),text="☐",ts=10,radius=UDim.new(0,4),z=103})
        mkLabel(r,{pos=UDim2.new(0,24,0,0),size=UDim2.new(1,-28,1,0),
            text="["..e.tier.."] "..e.name,
            color=TIER_COLOR[e.tier] or Color3.fromRGB(200,200,200),ts=9,z=102})
        local sel=false
        chk.MouseButton1Click:Connect(function()
            sel=not sel; mSel[i]=sel and e or nil
            chk.Text=sel and "☑" or "☐"
            chk.BackgroundColor3=sel and Color3.fromRGB(0,90,40) or Color3.fromRGB(25,25,42)
            mCount=mCount+(sel and 1 or -1)
            MCountL.Text="Sel: "..math.max(0,mCount)
        end)
    end
    MSF.CanvasSize=UDim2.new(0,0,0,#eggs*24)
    MF.Visible=true
end

local function dismissMulti()
    MF.Visible=false; State.alertPending=false; mCb=nil
end
MAllBtn.MouseButton1Click:Connect(function()
    local cb=mCb; local e=mEggs; dismissMulti()
    if cb then task.spawn(function() cb(e) end) end
end)
MSelBtn.MouseButton1Click:Connect(function()
    local chosen={}
    for _,e in pairs(mSel) do table.insert(chosen,e) end
    local cb=mCb; dismissMulti()
    if #chosen>0 and cb then task.spawn(function() cb(chosen) end) end
end)
MNoBtn.MouseButton1Click:Connect(function() dismissMulti() end)

-- ═══════════════════════════════════════
-- DRAG
-- ═══════════════════════════════════════
local drag,dStart,dPos=false,nil,nil
TBar.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1
    or i.UserInputType==Enum.UserInputType.Touch then
        drag=true; dStart=i.Position; dPos=MainFrame.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if drag and (i.UserInputType==Enum.UserInputType.MouseMovement
              or i.UserInputType==Enum.UserInputType.Touch) then
        local d=i.Position-dStart
        MainFrame.Position=UDim2.new(dPos.X.Scale,dPos.X.Offset+d.X,dPos.Y.Scale,dPos.Y.Offset+d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1
    or i.UserInputType==Enum.UserInputType.Touch then drag=false end
end)

-- ═══════════════════════════════════════
-- HIDE / SHOW
-- HideBtn = single click
-- Double-click anywhere on screen when hidden = show
-- ═══════════════════════════════════════
local function setGuiVisible(v)
    State.guiVisible=v
    -- Show all tab pages for active tab
    for i,pg in ipairs(tabPages) do
        pg.Visible = v and (i==curTab)
    end
    TabBar.Visible=v
    for _,pg in ipairs(tabPages) do pg.Visible=v and (pg==tabPages[curTab]) end
    MainFrame.Size = v and UDim2.new(0,268,0,520) or UDim2.new(0,268,0,36)
    -- Only title bar visible when hidden
    TBar.Visible=true -- always
    HideBtn.Text = v and "👁" or "◉"
    -- keep stroke visible always
end

HideBtn.MouseButton1Click:Connect(function()
    setGuiVisible(not State.guiVisible)
    log("[GUI] "..(State.guiVisible and "Shown" or "Hidden"))
end)

-- Double-click anywhere to show (when hidden)
UIS.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1
    or input.UserInputType==Enum.UserInputType.Touch then
        if not State.guiVisible and State.licensed then
            local now=tick()
            State.tapCount=(State.tapCount or 0)+1
            if now-State.lastTap<0.35 and State.tapCount>=2 then
                State.tapCount=0
                setGuiVisible(true)
                log("[GUI] Double-click show")
            end
            State.lastTap=now
        end
    end
end)

-- ═══════════════════════════════════════
-- MAIN STEAL LOOP
-- ═══════════════════════════════════════
local function updateStatLabels(results)
    local sn=#results.S; local an=#results.A; local un=#results.U
    EggStatL.Text="🥚 S:"..sn.." A:"..an.." U:"..un.." | 📦 "..State.totalStolen
end

local function mainLoop()
    log("[GO] Loop started — "..MODES[State.mode].name)
    while State.running do
        local char=LP.Character
        if char then
            local hrp=char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local results=scanEggs()
                updateStatLabels(results)
                if State.espOn then pcall(function() updateESP(results) end) end

                -- Detect new eggs (alert even if hidden)
                local newEggs=findNewEggs(results)
                if #newEggs>0 and not State.alertPending then
                    local sorted=sortProx(newEggs, hrp.Position)
                    if #sorted==1 then
                        local e=sorted[1]
                        local dist=math.floor((e.pos-hrp.Position).Magnitude)
                        showAlert(
                            "🥚 Egg ថ្មី! ["..e.tier.."]",
                            "ឈ្មោះ: "..e.name..
                            "\nTier: "..e.tier..
                            "\nចម្ងាយ: "..dist.."m"..(State.autoGrab and "\nAuto-grab in "..ALERT_TIMEOUT.."s" or ""),
                            e.tier,
                            function()
                                log("[Alert] Grab: "..e.name)
                                local c=LP.Character
                                if c then stealEgg(e,c) end
                            end,
                            function() log("[Alert] Skip: "..e.name) end
                        )
                    else
                        showMultiAlert(sorted, function(chosen)
                            log("[Multi] Grab "..#chosen)
                            local c=LP.Character
                            if c then
                                sortProx(chosen, hrp.Position)
                                stealList(chosen, c)
                            end
                        end)
                    end
                end

                -- Auto steal filtered eggs
                if not State.alertPending then
                    local filtered=getFiltered(results)
                    if #filtered>0 then
                        sortProx(filtered, hrp.Position)
                        stealList(filtered, char)
                    end
                end

                updateStatLabels(scanEggs())
            end
        end
        local m=M()
        task.wait(math.random(math.floor(m.dMin*1000*4),math.floor(m.dMax*1000*6))/1000)
    end
    log("[STOP] Loop ended")
end

-- NOTE: Primary Start logic is handled by §K enhanced connection below.
-- This stub keeps the license / running guard only; loop is spawned by §K.
StartBtn.MouseButton1Click:Connect(function()
    if not State.licensed then
        StatusL.Text="📋 ❌ License required!"
        return
    end
    -- actual loop spawn is in §K connection
end)

StopBtn.MouseButton1Click:Connect(function()
    State.running=false
    StatusL.Text="📋 🔴 Stopped"
    clearESP()
    log("[STOP]")
end)

-- ═══════════════════════════════════════
-- KEYBINDS
-- ═══════════════════════════════════════
UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode==Enum.KeyCode.F5 then
        if State.running then
            State.running=false
            StatusL.Text="📋 🔴 Stopped (F5)"
        else
            if State.licensed then
                State.running=true
                StatusL.Text="📋 🟢 Running (F5)"
                task.spawn(mainLoop)
            end
        end
    elseif input.KeyCode==Enum.KeyCode.F6 then
        setGuiVisible(not State.guiVisible)
    elseif input.KeyCode==Enum.KeyCode.F8 then
        State.espOn=not State.espOn
        ESPBtn.Text="ESP: "..(State.espOn and "ON" or "OFF")
        if not State.espOn then clearESP() end
    elseif input.KeyCode==Enum.KeyCode.F9 then
        State.mode=State.mode%#MODES+1
        local m=MODES[State.mode]
        ModeL.Text="⚙️ Mode: "..m.name
        for j,b in ipairs(mBtns) do
            for _,c in ipairs(b:GetChildren()) do
                if c:IsA("UIStroke") then c:Destroy() end
            end
        end
        local hs2=Instance.new("UIStroke",mBtns[State.mode])
        hs2.Color=Color3.fromRGB(255,240,80); hs2.Thickness=2
        log("[Mode] "..m.name)
    end
end)

-- ═══════════════════════════════════════
-- BACKGROUND UPDATERS
-- ═══════════════════════════════════════
-- Stats refresh
task.spawn(function()
    while true do
        task.wait(1)
        if State.licensed then
            local elapsed=os.time()-State.sessionStart
            local rate=elapsed>0 and (State.totalStolen/elapsed*60) or 0
            TotL.Text="📦 Total: "..State.totalStolen
            SessL.Text="⏱ Session: "..math.floor(elapsed).."s"
            RateL.Text=string.format("⚡ Rate: %.1f/min", rate)
            ModeSL.Text="⚙️ Mode: "..MODES[State.mode].name
            LicSL.Text="🔑 License: "..(State.licenseType=="full" and "FULL ✅" or "FREE (Limited)")
            if cachedRemotes then
                RemSL.Text="📡 Remotes: "..#cachedRemotes.." found"
            end
            -- refresh tabs
            if curTab==4 then refreshHistory() end
            if curTab==5 then refreshFullLog() end
        end
    end
end)

-- Passive egg scan (not running)
task.spawn(function()
    while true do
        task.wait(2.5)
        if State.licensed and not State.running then
            local r=scanEggs()
            updateStatLabels(r)
            if State.espOn then pcall(function() updateESP(r) end) end
            -- check new even when stopped
            local new=findNewEggs(r)
            if #new>0 and not State.alertPending then
                local hrp=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    sortProx(new, hrp.Position)
                    if #new==1 then
                        local e=new[1]
                        showAlert(
                            "🥚 Egg ថ្មី! ["..e.tier.."] (Tool stopped)",
                            "ឈ្មោះ: "..e.name.."\nStart tool ដើម្បីលួច",
                            e.tier,
                            function()
                                -- auto start if not running
                                if not State.running and State.licensed then
                                    State.running=true
                                    task.spawn(mainLoop)
                                end
                                local c=LP.Character
                                if c then stealEgg(e,c) end
                            end,
                            function() log("[Alert] Skip (stopped)") end
                        )
                    elseif #new>=2 then
                        showMultiAlert(new, function(chosen)
                            if not State.running and State.licensed then
                                State.running=true
                                task.spawn(mainLoop)
                            end
                            local c=LP.Character
                            if c then stealList(chosen,c) end
                        end)
                    end
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════
-- LICENSE ACTIVATION
-- ═══════════════════════════════════════
local function activateLicense(key)
    key = key:upper():gsub("%s+","")

    -- Free key
    if key == FREE_LICENSE then
        State.licensed = true
        State.licenseKey = key
        State.licenseType = "free"
        LicBadge.Text = "FREE"
        LicBadge.TextColor3 = Color3.fromRGB(100,220,100)
        LicTypeL.Text = "🔑 FREE License (limited features)"
        StatusL.Text = "📋 ✅ Free license active"
        log("[Lic] FREE activated")
        -- Show main tool
        LicScreen.Visible = false
        MainFrame.Visible = true
        setGuiVisible(true)
        notify("🥚 MAKARA Tool", "Free license active!", 4)

        -- Limited: S+A filter, all modes available, no webhook
        State.filterS=true; State.filterA=true
        State.filterU=false; State.filterIGN=false
        return true, "FREE"
    end

    -- Can be extended: check against Telegram bot or hardcoded full keys
    -- Example full key pattern: MAKARA-XXXX-XXXX
    if key:find("^MAKARA%-[A-Z0-9]+%-[A-Z0-9]+$") then
        State.licensed = true
        State.licenseKey = key
        State.licenseType = "full"
        LicBadge.Text = "FULL"
        LicBadge.TextColor3 = Color3.fromRGB(255,200,50)
        LicTypeL.Text = "🔑 FULL License ✅ All features"
        StatusL.Text = "📋 ✅ Full license active"
        log("[Lic] FULL activated: "..key)
        LicScreen.Visible = false
        MainFrame.Visible = true
        setGuiVisible(true)
        notify("🥚 MAKARA Tool", "Full license active! All features unlocked.", 5)
        return true, "FULL"
    end

    return false, "❌ Invalid key"
end

ActivateBtn.MouseButton1Click:Connect(function()
    local key = KeyInput.Text
    if key == "" then
        LicStatusL.Text = "⚠️ ដាក់ key មុន!"
        LicStatusL.TextColor3 = Color3.fromRGB(255,100,100)
        return
    end
    LicStatusL.Text = "⏳ Checking..."
    LicStatusL.TextColor3 = Color3.fromRGB(200,200,255)
    local ok, msg = activateLicense(key)
    if ok then
        LicStatusL.Text = "✅ "..msg.." license activated!"
        LicStatusL.TextColor3 = Color3.fromRGB(100,255,100)
    else
        LicStatusL.Text = msg
        LicStatusL.TextColor3 = Color3.fromRGB(255,100,100)
        -- Shake card
        local orig = LicCard.Position
        task.spawn(function()
            for i=1,6 do
                LicCard.Position = UDim2.new(0.5,-140+(i%2==0 and 6 or -6),0.5,-130)
                task.wait(0.05)
            end
            LicCard.Position = orig
        end)
    end
end)

-- Enter key to activate
KeyInput.FocusLost:Connect(function(enter)
    if enter then ActivateBtn:GetPropertyChangedSignal("Text"):Wait() end
end)

-- ═══════════════════════════════════════
-- CHARACTER RESPAWN
-- ═══════════════════════════════════════
LP.CharacterAdded:Connect(function()
    task.wait(2)
    cachedRemotes = nil -- rescan after respawn
    if State.running then
        log("[Char] Respawned — resuming")
    end
end)

-- ═══════════════════════════════════════
-- BOOT
-- ═══════════════════════════════════════
log("[MAKARA] v4 booted")
log("[Key] Enter license key to start")
log("[Free] Use: MAKARA4YOU")
log("[Keys] F5=Toggle F6=Hide F8=ESP F9=Mode")

print("╔════════════════════════════════╗")
print("║    MAKARA Tool v4 — Loaded     ║")
print("║  Free key: MAKARA4YOU          ║")
print("║  F5=Toggle F6=Hide F9=Mode     ║")
print("╚════════════════════════════════╝")

-- ╔══════════════════════════════════════════════════════╗
-- ║              § A. ADVANCED STEAL ENGINE              ║
-- ║   Multi-method: Touch / ClickDetector /              ║
-- ║   ProximityPrompt / Remote / CFrame overlap          ║
-- ╚══════════════════════════════════════════════════════╝

local AdvSteal = {}

-- All known interaction methods
function AdvSteal:tryClickDetector(obj)
    local cd = obj:FindFirstChildWhichIsA("ClickDetector")
    if cd then
        pcall(function() fireclickdetector(cd) end)
        return true
    end
    if obj:IsA("Model") then
        for _,child in ipairs(obj:GetDescendants()) do
            if child:IsA("ClickDetector") then
                pcall(function() fireclickdetector(child) end)
                return true
            end
        end
    end
    return false
end

function AdvSteal:tryProximityPrompt(obj)
    local pp = obj:FindFirstChildWhichIsA("ProximityPrompt")
    if pp then
        pcall(function() fireproximityprompt(pp) end)
        return true
    end
    if obj:IsA("Model") then
        for _,child in ipairs(obj:GetDescendants()) do
            if child:IsA("ProximityPrompt") then
                pcall(function() fireproximityprompt(child) end)
                return true
            end
        end
    end
    return false
end

function AdvSteal:tryTouchTransmitter(obj, char)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    -- TouchTransmitter overlap: move HRP onto part surface
    local parts = {}
    if obj:IsA("BasePart") then
        table.insert(parts, obj)
    elseif obj:IsA("Model") then
        for _,p in ipairs(obj:GetDescendants()) do
            if p:IsA("BasePart") then table.insert(parts, p) end
        end
    end
    for _,part in ipairs(parts) do
        local tt = part:FindFirstChildWhichIsA("TouchTransmitter")
        if tt then
            pcall(function()
                hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
            end)
            task.wait(0.1)
            return true
        end
    end
    return false
end

function AdvSteal:tryValueChange(obj)
    -- Some games use BoolValue/IntValue changes to track collection
    local function tryVal(parent)
        for _,child in ipairs(parent:GetChildren()) do
            if child:IsA("BoolValue") and child.Name:lower():find("collect") then
                pcall(function() child.Value = true end)
            end
        end
    end
    pcall(function() tryVal(obj) end)
    if obj:IsA("Model") then
        for _,d in ipairs(obj:GetDescendants()) do
            if d:IsA("BoolValue") then
                pcall(function() d.Value = true end)
            end
        end
    end
end

function AdvSteal:tryBodyVelocityOverlap(obj, char)
    -- Simulate a "bump" into the egg using BodyVelocity
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local eggPos = getPos(obj)
    if not eggPos then return end
    local dir = (eggPos - hrp.Position).Unit
    local bv = Instance.new("BodyVelocity")
    bv.Velocity = dir * 60
    bv.MaxForce = Vector3.new(1e5,1e5,1e5)
    bv.Parent = hrp
    task.wait(0.12)
    pcall(function() bv:Destroy() end)
end

function AdvSteal:fullAttempt(egg, char)
    local obj = egg.object
    local results = {cd=false, pp=false, tt=false, rem=false}

    -- 1. ClickDetector
    results.cd = self:tryClickDetector(obj)
    task.wait(0.02)

    -- 2. ProximityPrompt
    results.pp = self:tryProximityPrompt(obj)
    task.wait(0.02)

    -- 3. TouchTransmitter
    results.tt = self:tryTouchTransmitter(obj, char)
    task.wait(0.02)

    -- 4. BoolValue
    self:tryValueChange(obj)
    task.wait(0.01)

    -- 5. BodyVelocity bump
    self:tryBodyVelocityOverlap(obj, char)
    task.wait(0.08)

    -- 6. Fire all remotes (existing engine)
    fireAll(obj)
    task.wait(0.02)

    -- 7. Fire with player character as arg
    local remotes = getRemotes()
    for _,r in ipairs(remotes) do
        if r:IsA("RemoteEvent") then
            pcall(function() r:FireServer(char) end)
            pcall(function() r:FireServer(LP) end)
            pcall(function() r:FireServer(LP.UserId) end)
        end
        task.wait(0.01)
    end

    return results
end

-- Patch stealEgg to use AdvSteal
local _prevSteal = stealEgg
stealEgg = function(egg, char)
    if not char then return end
    safeTP(char, egg.pos)
    mWait()
    AdvSteal:fullAttempt(egg, char)
    mWait()
    State.totalStolen = State.totalStolen + 1
    table.insert(State.history, 1, {name=egg.name, tier=egg.tier, t=os.date("%H:%M:%S")})
    if #State.history > 60 then table.remove(State.history) end
    log("[+] " .. egg.name .. " [" .. egg.tier .. "]")
end

-- ╔══════════════════════════════════════════════════════╗
-- ║              § B. SMART ROUTE OPTIMIZER              ║
-- ║   TSP nearest-neighbor for multi-egg collection      ║
-- ╚══════════════════════════════════════════════════════╝

local Router = {}

function Router:nearestNeighbor(eggs, startPos)
    local remaining = {table.unpack(eggs)}
    local route = {}
    local cur = startPos
    while #remaining > 0 do
        local bestIdx, bestDist = 1, math.huge
        for i,e in ipairs(remaining) do
            local d = (e.pos - cur).Magnitude
            if d < bestDist then bestDist=d; bestIdx=i end
        end
        table.insert(route, remaining[bestIdx])
        cur = remaining[bestIdx].pos
        table.remove(remaining, bestIdx)
    end
    return route
end

function Router:greedyCluster(eggs, startPos, clusterRadius)
    -- Group eggs within radius, steal closest cluster first
    clusterRadius = clusterRadius or 40
    local clusters = {}
    local used = {}
    for i,e in ipairs(eggs) do
        if not used[i] then
            local cluster = {e}
            used[i] = true
            for j,e2 in ipairs(eggs) do
                if not used[j] and (e.pos-e2.pos).Magnitude < clusterRadius then
                    table.insert(cluster, e2)
                    used[j] = true
                end
            end
            table.insert(clusters, {center=e.pos, eggs=cluster})
        end
    end
    -- Sort clusters by distance from start
    table.sort(clusters, function(a,b)
        return (a.center-startPos).Magnitude < (b.center-startPos).Magnitude
    end)
    -- Flatten
    local route = {}
    for _,cl in ipairs(clusters) do
        for _,e in ipairs(self:nearestNeighbor(cl.eggs, startPos)) do
            table.insert(route, e)
        end
    end
    return route
end

-- ╔══════════════════════════════════════════════════════╗
-- ║           § C. RADAR SYSTEM (Minimap)                ║
-- ╚══════════════════════════════════════════════════════╝

local RadarSys = {}
RadarSys.frame = nil
RadarSys.dots  = {}
RadarSys.SIZE  = 130
RadarSys.RANGE = 220

function RadarSys:init()
    if self.frame then return end
    local rf = mkFrame(SG, {
        size   = UDim2.new(0, self.SIZE, 0, self.SIZE),
        pos    = UDim2.new(1, -(self.SIZE+12), 0, 55),
        bg     = Color3.fromRGB(7, 7, 14),
        radius = UDim.new(0.5, 0),
        stroke = Color3.fromRGB(80, 35, 170),
        sw     = 1.2,
        z      = 20,
    })
    self.frame = rf

    -- Cross hair
    local ch1 = Instance.new("Frame", rf)
    ch1.Size = UDim2.new(1, 0, 0, 1)
    ch1.Position = UDim2.new(0, 0, 0.5, 0)
    ch1.BackgroundColor3 = Color3.fromRGB(50, 25, 100)
    ch1.BorderSizePixel = 0
    ch1.ZIndex = 21

    local ch2 = Instance.new("Frame", rf)
    ch2.Size = UDim2.new(0, 1, 1, 0)
    ch2.Position = UDim2.new(0.5, 0, 0, 0)
    ch2.BackgroundColor3 = Color3.fromRGB(50, 25, 100)
    ch2.BorderSizePixel = 0
    ch2.ZIndex = 21

    -- Player dot
    local pd = Instance.new("Frame", rf)
    pd.Size = UDim2.new(0, 7, 0, 7)
    pd.Position = UDim2.new(0.5, -3, 0.5, -3)
    pd.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
    pd.BorderSizePixel = 0
    pd.ZIndex = 23
    Instance.new("UICorner", pd).CornerRadius = UDim.new(0.5, 0)

    -- Label
    mkLabel(rf, {
        pos=UDim2.new(0,0,0,2), size=UDim2.new(1,0,0,12),
        text="RADAR", color=Color3.fromRGB(80,160,255),
        ts=7, font=Enum.Font.GothamBold,
        xa=Enum.TextXAlignment.Center, z=22
    })
end

function RadarSys:clearDots()
    for _,d in ipairs(self.dots) do pcall(function() d:Destroy() end) end
    self.dots = {}
end

function RadarSys:plot(egg, playerPos)
    if not self.frame then return end
    local rel = egg.pos - playerPos
    local nx = rel.X / self.RANGE
    local nz = rel.Z / self.RANGE
    local mag = math.sqrt(nx*nx + nz*nz)
    if mag > 1 then nx=nx/mag; nz=nz/mag end
    local px = (0.5 + nx*0.44) * self.SIZE
    local py = (0.5 + nz*0.44) * self.SIZE
    local dot = Instance.new("Frame", self.frame)
    dot.Size = UDim2.new(0, 5, 0, 5)
    dot.Position = UDim2.new(0, px-2, 0, py-2)
    dot.BackgroundColor3 = TIER_COLOR[egg.tier] or Color3.fromRGB(255,255,255)
    dot.BorderSizePixel = 0
    dot.ZIndex = 22
    Instance.new("UICorner", dot).CornerRadius = UDim.new(0.5, 0)
    -- Distance label
    local dist = math.floor((egg.pos-playerPos).Magnitude)
    local dl = mkLabel(dot, {
        pos=UDim2.new(0,6,0,-2), size=UDim2.new(0,30,0,10),
        text=dist.."m", color=Color3.fromRGB(200,200,200),
        ts=6, z=23
    })
    table.insert(self.dots, dot)
end

function RadarSys:update(results, playerPos)
    self:clearDots()
    if not State.radarOn or not self.frame then return end
    for tier, eggs in pairs(results) do
        for _,e in ipairs(eggs) do
            if (e.pos-playerPos).Magnitude <= self.RANGE then
                pcall(function() self:plot(e, playerPos) end)
            end
        end
    end
end

function RadarSys:setVisible(v)
    if v then self:init() end
    if self.frame then self.frame.Visible = v end
end

-- Radar loop
task.spawn(function()
    while true do
        task.wait(0.6)
        if State.radarOn and State.licensed then
            local char = LP.Character
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local r = scanEggs()
                    RadarSys:update(r, hrp.Position)
                end
            end
        elseif not State.radarOn then
            RadarSys:clearDots()
        end
    end
end)

-- Patch radar button
RadarBtn.MouseButton1Click:Connect(function()
    State.radarOn = not State.radarOn
    RadarSys:setVisible(State.radarOn)
    RadarBtn.Text = "Radar: "..(State.radarOn and "ON" or "OFF")
    ESPLabel.Text = "👁 ESP: "..(State.espOn and "ON" or "OFF").." | 📡 Radar: "..(State.radarOn and "ON" or "OFF")
    log("[Radar] "..(State.radarOn and "ON" or "OFF"))
end)

-- ╔══════════════════════════════════════════════════════╗
-- ║          § D. FARM WAYPOINT SYSTEM                   ║
-- ╚══════════════════════════════════════════════════════╝

local FarmSys = {}
FarmSys.waypoints = {}
FarmSys.running   = false
FarmSys.idx       = 1
FarmSys.loops     = 0

function FarmSys:recordWP()
    local char = LP.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    table.insert(self.waypoints, hrp.Position)
    log("[Farm] WP "..#self.waypoints.." recorded")
end

function FarmSys:clearWPs()
    self.waypoints = {}
    self.idx = 1
    log("[Farm] Waypoints cleared")
end

function FarmSys:start()
    if self.running or #self.waypoints == 0 then return end
    self.running = true
    log("[Farm] Loop started — "..#self.waypoints.." WPs")
    task.spawn(function()
        while self.running and State.running do
            local wp = self.waypoints[self.idx]
            local char = LP.Character
            if char and wp then
                safeTP(char, wp)
                mWait()
                local r = scanEggs()
                local filtered = getFiltered(r)
                if #filtered > 0 then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    local route = hrp and Router:greedyCluster(filtered, hrp.Position) or filtered
                    for _,egg in ipairs(route) do
                        if not self.running then break end
                        stealEgg(egg, char)
                    end
                end
                self.idx = self.idx % #self.waypoints + 1
                if self.idx == 1 then
                    self.loops = self.loops + 1
                    log("[Farm] Loop #"..self.loops.." complete")
                end
            end
            task.wait(math.random(8,16)/10)
        end
        self.running = false
        log("[Farm] Stopped")
    end)
end

function FarmSys:stop()
    self.running = false
end

-- Farm UI in Mode tab (below existing content)
local FarmTitle = mkLabel(tabPages[2], {
    pos=UDim2.new(0,0,0,254), size=UDim2.new(1,0,0,18),
    text="🌾 Farm Waypoints:", color=Color3.fromRGB(200,200,255),
    ts=10, font=Enum.Font.GothamBold
})
local FarmInfoL = mkLabel(tabPages[2], {
    pos=UDim2.new(0,0,0,274), size=UDim2.new(1,0,0,14),
    text="WPs: 0 | Loops: 0", color=Color3.fromRGB(160,160,220), ts=9
})

local FarmRecBtn = mkBtn(tabPages[2], {
    pos=UDim2.new(0,0,0,290), size=UDim2.new(0.32,-2,0,24),
    bg=Color3.fromRGB(40,100,40), text="📍 Record", ts=9, radius=UDim.new(0,6)
})
local FarmStartBtn = mkBtn(tabPages[2], {
    pos=UDim2.new(0.34,0,0,290), size=UDim2.new(0.32,-2,0,24),
    bg=Color3.fromRGB(0,120,55), text="▶ Farm", ts=9, radius=UDim.new(0,6)
})
local FarmClearBtn = mkBtn(tabPages[2], {
    pos=UDim2.new(0.68,0,0,290), size=UDim2.new(0.32,0,0,24),
    bg=Color3.fromRGB(100,25,25), text="🗑 Clear", ts=9, radius=UDim.new(0,6)
})

FarmRecBtn.MouseButton1Click:Connect(function()
    FarmSys:recordWP()
    FarmInfoL.Text="WPs: "..#FarmSys.waypoints.." | Loops: "..FarmSys.loops
end)
FarmStartBtn.MouseButton1Click:Connect(function()
    if FarmSys.running then
        FarmSys:stop()
        FarmStartBtn.Text="▶ Farm"
        FarmStartBtn.BackgroundColor3=Color3.fromRGB(0,120,55)
    else
        FarmSys:start()
        FarmStartBtn.Text="⏹ Stop"
        FarmStartBtn.BackgroundColor3=Color3.fromRGB(140,30,30)
    end
end)
FarmClearBtn.MouseButton1Click:Connect(function()
    FarmSys:clearWPs()
    FarmInfoL.Text="WPs: 0 | Loops: 0"
end)

task.spawn(function()
    while true do
        task.wait(2)
        if FarmSys.running then
            FarmInfoL.Text="WPs: "..#FarmSys.waypoints.." | Loops: "..FarmSys.loops
        end
    end
end)

-- ╔══════════════════════════════════════════════════════╗
-- ║          § E. BLACKLIST / WHITELIST                  ║
-- ╚══════════════════════════════════════════════════════╝

local Blacklist = {}
Blacklist.list = {}

function Blacklist:add(keyword)
    keyword = keyword:lower():gsub("%s+","")
    for _,k in ipairs(self.list) do if k==keyword then return end end
    table.insert(self.list, keyword)
    log("[BL] Added: "..keyword)
end

function Blacklist:remove(keyword)
    keyword = keyword:lower()
    for i,k in ipairs(self.list) do
        if k==keyword then table.remove(self.list,i); log("[BL] Removed: "..keyword); return end
    end
end

function Blacklist:check(name)
    local l = name:lower()
    for _,k in ipairs(self.list) do if l:find(k) then return true end end
    return false
end

local CustomPriority = {}
CustomPriority.list = {}

function CustomPriority:add(keyword)
    keyword = keyword:lower():gsub("%s+","")
    for _,k in ipairs(self.list) do if k==keyword then return end end
    table.insert(self.list, keyword)
    log("[CP] Added: "..keyword)
end

function CustomPriority:check(name)
    local l = name:lower()
    for _,k in ipairs(self.list) do if l:find(k) then return true end end
    return false
end

-- Patch steal to respect BL and CP
local _prevSteal2 = stealEgg
stealEgg = function(egg, char)
    if Blacklist:check(egg.name) then
        log("[BL] Skipped: "..egg.name)
        return
    end
    -- Bump tier if custom priority matches
    if CustomPriority:check(egg.name) and egg.tier ~= "S" then
        egg.tier = "A"
    end
    _prevSteal2(egg, char)
end

-- ╔══════════════════════════════════════════════════════╗
-- ║          § F. COOLDOWN TRACKER                       ║
-- ╚══════════════════════════════════════════════════════╝

local CooldownTracker = {}
CooldownTracker.cd = {}

function CooldownTracker:set(name, secs)
    self.cd[name] = tick() + (secs or 20)
end

function CooldownTracker:ready(name)
    local exp = self.cd[name]
    return not exp or tick() >= exp
end

function CooldownTracker:remaining(name)
    local exp = self.cd[name]
    if not exp then return 0 end
    return math.max(0, exp - tick())
end

-- Patch steal for CD
local _prevSteal3 = stealEgg
stealEgg = function(egg, char)
    if not CooldownTracker:ready(egg.name) then
        return
    end
    _prevSteal3(egg, char)
    CooldownTracker:set(egg.name, 18)
end

-- ╔══════════════════════════════════════════════════════╗
-- ║          § G. AUTO-RECONNECT                         ║
-- ╚══════════════════════════════════════════════════════╝

local AutoRC = {}
AutoRC.enabled = false
AutoRC.checkEvery = 8
AutoRC.retries = 0
AutoRC.maxRetries = 5

function AutoRC:start()
    task.spawn(function()
        while self.enabled do
            task.wait(self.checkEvery)
            local char = LP.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health <= 0 then
                    self.retries = self.retries + 1
                    log("[RC] Dead — respawn ("..self.retries.."/"..self.maxRetries..")")
                    task.wait(3)
                    pcall(function() LP:LoadCharacter() end)
                    task.wait(2.5)
                    if self.retries >= self.maxRetries then
                        log("[RC] Max retries, stopping")
                        self.enabled = false
                    end
                else
                    self.retries = 0
                end
            end
        end
    end)
end

LP.CharacterAdded:Connect(function(char)
    task.wait(2)
    cachedRemotes = nil
    log("[Char] Respawned — remotes reset")
    if State.running then
        log("[Char] Resuming loop")
        notify("MAKARA Tool","Respawned — continuing",3)
    end
end)

-- ╔══════════════════════════════════════════════════════╗
-- ║          § H. SESSION EXPORT                         ║
-- ╚══════════════════════════════════════════════════════╝

local function exportSession()
    local elapsed = os.time()-State.sessionStart
    local rate = elapsed>0 and (State.totalStolen/elapsed*60) or 0
    local lines = {
        "═══ MAKARA Tool "..VER.." Session ═══",
        "User: "..(LP and LP.Name or "???").."  |  HWID: "..(LP and tostring(LP.UserId) or "???").."_"..(LP and LP.Name or "???"),
        "License: "..State.licenseType:upper(),
        "Date: "..os.date("%Y-%m-%d %H:%M:%S"),
        "Mode: "..MODES[State.mode].name,
        "Duration: "..math.floor(elapsed).."s",
        "Total Stolen: "..State.totalStolen,
        string.format("Rate: %.1f egg/min", rate),
        "Steal History (last 30):",
    }
    for i,h in ipairs(State.history) do
        if i>30 then break end
        table.insert(lines, h.t.." ["..h.tier.."] "..h.name)
    end
    table.insert(lines, "═══════════════════════════════")
    local report = table.concat(lines, "\n")
    pcall(function() setclipboard(report) end)
    log("[Export] Copied!")
    notify("MAKARA","Session exported to clipboard",3)
end

-- ╔══════════════════════════════════════════════════════╗
-- ║          § I. QUICK ACTION PANEL (floating)          ║
-- ╚══════════════════════════════════════════════════════╝

local QP = mkFrame(SG, {
    size   = UDim2.new(0,96,0,200),
    pos    = UDim2.new(0,14,0,50),
    bg     = Color3.fromRGB(9,9,16),
    radius = UDim.new(0,10),
    stroke = Color3.fromRGB(80,30,170),
    sw     = 1,
    z      = 15,
})
QP.Visible = false  -- shown after license

local QPTitle = mkLabel(QP,{
    pos=UDim2.new(0,4,0,4), size=UDim2.new(1,-8,0,14),
    text="⚡ Quick", color=Color3.fromRGB(180,160,255),
    ts=9, font=Enum.Font.GothamBold, xa=Enum.TextXAlignment.Center
})

local function qb(text, y, bg)
    return mkBtn(QP,{
        pos=UDim2.new(0,4,0,y), size=UDim2.new(1,-8,0,26),
        bg=bg or Color3.fromRGB(45,18,110), text=text, ts=8, z=16, radius=UDim.new(0,6)
    })
end

local QPRadar  = qb("📡 Radar",  22, Color3.fromRGB(18,60,120))
local QPESP    = qb("👁 ESP",    52, Color3.fromRGB(55,55,18))
local QPExport = qb("📋 Export", 82, Color3.fromRGB(30,70,30))
local QPRC     = qb("♻ AutoRC", 112, Color3.fromRGB(70,25,70))
local QPFarm   = qb("🌾 Farm",   142, Color3.fromRGB(60,50,10))

QPRadar.MouseButton1Click:Connect(function()
    State.radarOn = not State.radarOn
    RadarSys:setVisible(State.radarOn)
    QPRadar.Text = State.radarOn and "📡 Radar ON" or "📡 Radar"
    RadarBtn.Text = "Radar: "..(State.radarOn and "ON" or "OFF")
    log("[QP] Radar "..(State.radarOn and "ON" or "OFF"))
end)

QPESP.MouseButton1Click:Connect(function()
    State.espOn = not State.espOn
    QPESP.Text = State.espOn and "👁 ESP ON" or "👁 ESP"
    ESPBtn.Text = "ESP: "..(State.espOn and "ON" or "OFF")
    if not State.espOn then clearESP() end
    log("[QP] ESP "..(State.espOn and "ON" or "OFF"))
end)

QPExport.MouseButton1Click:Connect(function()
    exportSession()
    QPExport.Text = "✅ Done"
    task.delay(2, function()
        if QPExport and QPExport.Parent then QPExport.Text = "📋 Export" end
    end)
end)

QPRC.MouseButton1Click:Connect(function()
    AutoRC.enabled = not AutoRC.enabled
    QPRC.Text = AutoRC.enabled and "♻ RC ON" or "♻ AutoRC"
    if AutoRC.enabled then AutoRC:start() end
    log("[QP] AutoRC "..(AutoRC.enabled and "ON" or "OFF"))
end)

QPFarm.MouseButton1Click:Connect(function()
    if FarmSys.running then
        FarmSys:stop()
        QPFarm.Text = "🌾 Farm"
    else
        FarmSys:start()
        QPFarm.Text = "🌾 Farm ON"
    end
end)

-- Drag QP
local qpd,qpdS,qpdP=false,nil,nil
QPTitle.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1
    or i.UserInputType==Enum.UserInputType.Touch then
        qpd=true; qpdS=i.Position; qpdP=QP.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if qpd and (i.UserInputType==Enum.UserInputType.MouseMovement
             or i.UserInputType==Enum.UserInputType.Touch) then
        local d=i.Position-qpdS
        QP.Position=UDim2.new(qpdP.X.Scale,qpdP.X.Offset+d.X,qpdP.Y.Scale,qpdP.Y.Offset+d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1
    or i.UserInputType==Enum.UserInputType.Touch then qpd=false end
end)

-- ╔══════════════════════════════════════════════════════╗
-- ║          § J. NOTIFICATION SYSTEM                    ║
-- ╚══════════════════════════════════════════════════════╝

-- In-game toast (non-Roblox notification)
local ToastFrame = mkFrame(SG, {
    size   = UDim2.new(0,200,0,40),
    pos    = UDim2.new(0.5,-100,0,14),
    bg     = Color3.fromRGB(10,10,20),
    radius = UDim.new(0,8),
    stroke = Color3.fromRGB(90,35,185),
    z      = 90,
})
ToastFrame.Visible = false

local ToastL = mkLabel(ToastFrame, {
    pos=UDim2.new(0,8,0,0), size=UDim2.new(1,-16,1,0),
    text="", color=Color3.fromRGB(220,220,255),
    ts=10, font=Enum.Font.GothamBold,
    xa=Enum.TextXAlignment.Center, z=91
})

local toastQueue = {}
local toastBusy  = false

local function toast(msg, duration, color)
    table.insert(toastQueue, {msg=msg, dur=duration or 2.5, color=color})
end

task.spawn(function()
    while true do
        task.wait(0.1)
        if not toastBusy and #toastQueue > 0 then
            toastBusy = true
            local t = table.remove(toastQueue, 1)
            ToastL.Text = t.msg
            ToastL.TextColor3 = t.color or Color3.fromRGB(220,220,255)
            ToastFrame.Visible = true
            -- Fade in
            for i=0,10 do
                ToastFrame.BackgroundTransparency = 1 - i/10
                task.wait(0.02)
            end
            task.wait(t.dur)
            -- Fade out
            for i=0,10 do
                ToastFrame.BackgroundTransparency = i/10
                task.wait(0.02)
            end
            ToastFrame.Visible = false
            toastBusy = false
        end
    end
end)

-- Notify on milestones
task.spawn(function()
    local last = 0
    while true do
        task.wait(3)
        local n = State.totalStolen
        if n > 0 and n % 10 == 0 and n ~= last then
            last = n
            toast("🥚 "..n.." eggs stolen!", 2.5, Color3.fromRGB(100,255,150))
        end
    end
end)

-- ╔══════════════════════════════════════════════════════╗
-- ║          § K. ENHANCED MAIN LOOP (uses Router)       ║
-- ╚══════════════════════════════════════════════════════╝

-- Override mainLoop with improved version
local function enhancedMainLoop()
    log("[GO] Enhanced loop — "..MODES[State.mode].name)
    toast("▶ Started — "..MODES[State.mode].name, 2)

    while State.running do
        local char = LP.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local results = scanEggs()
                updateStatLabels(results)

                -- ESP
                if State.espOn then pcall(function() updateESP(results) end) end

                -- New egg detection (alert even if hidden)
                local newEggs = findNewEggs(results)
                if #newEggs > 0 and not State.alertPending then
                    local sorted = sortProx(newEggs, hrp.Position)
                    if #sorted == 1 then
                        local e = sorted[1]
                        local dist = math.floor((e.pos-hrp.Position).Magnitude)
                        showAlert(
                            "🥚 Egg ថ្មី! ["..e.tier.."]",
                            "ឈ្មោះ: "..e.name..
                            "\nTier: "..e.tier..
                            "\nចម្ងាយ: "..dist.."m"..
                            (State.autoGrab and "\n⏱ Auto-grab: "..ALERT_TIMEOUT.."s" or ""),
                            e.tier,
                            function()
                                log("[Alert] Grab: "..e.name)
                                local c = LP.Character
                                if c then stealEgg(e, c) end
                            end,
                            function() log("[Alert] Skip: "..e.name) end
                        )
                    else
                        showMultiAlert(sorted, function(chosen)
                            log("[Multi] Grab "..#chosen)
                            local c = LP.Character
                            if c then
                                local hh = c:FindFirstChild("HumanoidRootPart")
                                local route = hh and Router:greedyCluster(chosen, hh.Position) or chosen
                                stealList(route, c)
                            end
                        end)
                    end
                end

                -- Auto steal
                if not State.alertPending then
                    local filtered = getFiltered(results)
                    if #filtered > 0 then
                        -- Remove blacklisted
                        local clean = {}
                        for _,e in ipairs(filtered) do
                            if not Blacklist:check(e.name) and CooldownTracker:ready(e.name) then
                                table.insert(clean, e)
                            end
                        end
                        if #clean > 0 then
                            local route = Router:greedyCluster(clean, hrp.Position)
                            for _,egg in ipairs(route) do
                                if not State.running then break end
                                stealEgg(egg, char)
                                local m = M()
                                task.wait(math.random(math.floor(m.dMin*1000), math.floor(m.dMax*1000))/1000)
                            end
                        end
                    end
                end

                updateStatLabels(scanEggs())
            end
        end

        local m = M()
        task.wait(math.random(math.floor(m.dMin*1000*3), math.floor(m.dMax*1000*5))/1000)
    end

    State.running = false
    StatusL.Text = "📋 🔴 Stopped"
    toast("⏹ Stopped", 2, Color3.fromRGB(255,150,150))
    log("[STOP] Enhanced loop ended")
end

-- Patch Start button to use enhanced loop
StartBtn.MouseButton1Click:Connect(function()
    if not State.licensed then
        StatusL.Text = "📋 ❌ License required!"
        toast("❌ Enter license key first",2,Color3.fromRGB(255,100,100))
        return
    end
    if State.running then return end
    cachedRemotes = nil
    getRemotes()
    State.running = true
    State.sessionStart = os.time()
    StatusL.Text = "📋 🟢 "..MODES[State.mode].name.." — Running"
    task.spawn(enhancedMainLoop)
end)  -- §K enhanced loop connection

-- ╔══════════════════════════════════════════════════════╗
-- ║          § L. PASSIVE SCAN (always on)               ║
-- ╚══════════════════════════════════════════════════════╝

task.spawn(function()
    while true do
        task.wait(2)
        if State.licensed and not State.running then
            local r = scanEggs()
            updateStatLabels(r)
            if State.espOn then pcall(function() updateESP(r) end) end

            -- Still alert when stopped
            local newEggs = findNewEggs(r)
            if #newEggs > 0 and not State.alertPending then
                local char = LP.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local sorted = sortProx(newEggs, hrp.Position)
                    if #sorted == 1 then
                        local e = sorted[1]
                        showAlert(
                            "🥚 Egg ថ្មី (Tool stopped)! ["..e.tier.."]",
                            "ឈ្មោះ: "..e.name.."\nStart tool ដើម្បី auto-steal",
                            e.tier,
                            function()
                                if not State.running and State.licensed then
                                    State.running=true
                                    task.spawn(enhancedMainLoop)
                                end
                                local c=LP.Character
                                if c then stealEgg(e,c) end
                            end,
                            function() log("[Alert] Skip (stopped): "..e.name) end
                        )
                    elseif #sorted >= 2 then
                        showMultiAlert(sorted, function(chosen)
                            if not State.running and State.licensed then
                                State.running=true
                                task.spawn(enhancedMainLoop)
                            end
                            local c=LP.Character
                            if c then stealList(chosen,c) end
                        end)
                    end
                end
            end
        end
    end
end)

-- ╔══════════════════════════════════════════════════════╗
-- ║          § M. LICENSE SCREEN POLISH                  ║
-- ╚══════════════════════════════════════════════════════╝

-- Animate license card entrance
task.spawn(function()
    LicCard.BackgroundTransparency = 1
    local stroke = LicCard:FindFirstChildWhichIsA("UIStroke")
    if stroke then stroke.Transparency = 1 end
    for i=0,20 do
        task.wait(0.025)
        LicCard.BackgroundTransparency = 1 - i/20
        if stroke then stroke.Transparency = 1 - i/20 end
    end
end)

-- Pulse activate button
task.spawn(function()
    while LicScreen.Visible do
        task.wait(1.2)
        if not LicScreen.Visible then break end
        TweenService:Create(ActivateBtn, TweenInfo.new(0.4),
            {BackgroundColor3=Color3.fromRGB(120,55,240)}):Play()
        task.wait(0.4)
        TweenService:Create(ActivateBtn, TweenInfo.new(0.4),
            {BackgroundColor3=Color3.fromRGB(90,35,200)}):Play()
    end
end)

-- ╔══════════════════════════════════════════════════════╗
-- ║          § N. POST-LICENSE SETUP                     ║
-- ╚══════════════════════════════════════════════════════╝

-- Called once license is verified
local function onLicensed()
    -- Show quick panel
    QP.Visible = true
    -- Initial remote scan
    task.spawn(function()
        task.wait(0.5)
        getRemotes()
        toast("✅ "..State.licenseType:upper().." — Ready! F5=Start", 3, Color3.fromRGB(100,255,150))
    end)
    -- Announce
    log("[Ready] "..State.licenseType:upper().." license active")
    log("[Tip] F5=Start/Stop F6=Hide F8=ESP F9=Mode")
end

-- Patch activateLicense to call onLicensed
local _prevActivate = activateLicense
activateLicense = function(key)
    local ok, msg = _prevActivate(key)
    if ok then onLicensed() end
    return ok, msg
end

-- ╔══════════════════════════════════════════════════════╗
-- ║          § O. FINAL BOOT LOG                         ║
-- ╚══════════════════════════════════════════════════════╝

log("[v4] All systems loaded — §A through §O")
log("[Tip] Key: MAKARA4YOU for free access")
log("[Tip] F5=Start F6=Hide F8=ESP F9=Mode")

print("[MAKARA v4] Full system loaded. §A-O active.")
print("[MAKARA v4] Free key: MAKARA4YOU")

-- ╔══════════════════════════════════════════════════════╗
-- ║       § P. ADVANCED REMOTE FIRE (Game-specific)      ║
-- ║   Detects game engine pattern and adapts             ║
-- ╚══════════════════════════════════════════════════════╝

local GameEngine = {}
GameEngine.detected = "unknown"
GameEngine.remoteMap = {}

function GameEngine:detect()
    -- Pet Simulator X / 99 style
    if RS:FindFirstChild("Pets") or RS:FindFirstChild("PetData")
    or WS:FindFirstChild("PetArea") or WS:FindFirstChild("EggArea") then
        self.detected = "PetSim"
        log("[Engine] PetSim detected")
        return
    end
    -- Adopt Me style
    if RS:FindFirstChild("Nursery") or WS:FindFirstChild("Nursery")
    or RS:FindFirstChild("AdoptMe") then
        self.detected = "AdoptMe"
        log("[Engine] AdoptMe detected")
        return
    end
    -- Generic
    self.detected = "Generic"
    log("[Engine] Generic game")
end

function GameEngine:fireForPattern(egg)
    local obj = egg.object
    local pattern = self.detected

    if pattern == "PetSim" then
        -- Pet Sim: usually a RemoteEvent "HatchEgg" or "CollectEgg"
        local function tryPetSim(r)
            if r:IsA("RemoteEvent") then
                local n = r.Name:lower()
                if n:find("hatch") or n:find("egg") or n:find("collect") then
                    pcall(function() r:FireServer(obj) end)
                    pcall(function() r:FireServer(egg.name) end)
                    pcall(function() r:FireServer(1) end) -- index
                end
            end
        end
        for _,r in ipairs(RS:GetDescendants()) do tryPetSim(r) end

    elseif pattern == "AdoptMe" then
        -- AdoptMe: nursery interaction
        local function tryAdopt(r)
            if r:IsA("RemoteEvent") then
                local n = r.Name:lower()
                if n:find("nursery") or n:find("egg") or n:find("pet") then
                    pcall(function() r:FireServer(obj, "BuyEgg") end)
                    pcall(function() r:FireServer(obj, "HatchNow") end)
                end
            end
        end
        for _,r in ipairs(RS:GetDescendants()) do tryAdopt(r) end

    else
        -- Generic fallback: already handled by fireAll
    end
end

-- Run engine detection on boot
task.delay(1, function() GameEngine:detect() end)

-- Patch steal to also try engine-specific fires
local _prevStealE = stealEgg
stealEgg = function(egg, char)
    _prevStealE(egg, char)
    task.spawn(function()
        GameEngine:fireForPattern(egg)
    end)
end

-- ╔══════════════════════════════════════════════════════╗
-- ║       § Q. TELEPORT SAFETY GUARD                     ║
-- ║   Prevents ban from excessive instant TPs            ║
-- ╚══════════════════════════════════════════════════════╝

local TPGuard = {}
TPGuard.lastTP     = 0
TPGuard.tpCount    = 0
TPGuard.cooldownAt = 10   -- TP count before adding extra delay
TPGuard.extraDelay = 1.2  -- seconds to wait after hitting limit

function TPGuard:beforeTP()
    local now = tick()
    -- Reset count every 5 seconds
    if now - self.lastTP > 5 then self.tpCount = 0 end
    self.tpCount = self.tpCount + 1
    self.lastTP  = now
    if self.tpCount >= self.cooldownAt then
        log("[TPGuard] TP limit hit — cooling "..self.extraDelay.."s")
        task.wait(self.extraDelay)
        self.tpCount = 0
    end
end

-- Patch safeTP to go through guard
local _prevSafeTP = safeTP
safeTP = function(char, pos)
    TPGuard:beforeTP()
    _prevSafeTP(char, pos)
end

-- ╔══════════════════════════════════════════════════════╗
-- ║       § R. EGG VALUE ESTIMATOR                       ║
-- ║   Scores eggs to help user prioritize                ║
-- ╚══════════════════════════════════════════════════════╝

local EggValue = {}
EggValue.tierScore = {S=100, A=60, B=30, U=20, IGN=1}

function EggValue:score(egg)
    local base = self.tierScore[egg.tier] or 10
    -- Bonus for custom priority
    if CustomPriority:check(egg.name) then base = base + 40 end
    -- Penalty for blacklist (shouldn't reach here but just in case)
    if Blacklist:check(egg.name) then base = 0 end
    return base
end

function EggValue:sortBest(eggs)
    table.sort(eggs, function(a,b)
        return self:score(a) > self:score(b)
    end)
    return eggs
end

-- ╔══════════════════════════════════════════════════════╗
-- ║       § S. SETTINGS PERSISTENCE (in-session)         ║
-- ╚══════════════════════════════════════════════════════╝

local Settings = {}

function Settings:save()
    local s = {
        mode     = State.mode,
        filterS  = State.filterS,
        filterA  = State.filterA,
        filterU  = State.filterU,
        filterIGN= State.filterIGN,
        espOn    = State.espOn,
        radarOn  = State.radarOn,
        autoGrab = State.autoGrab,
        blacklist= Blacklist.list,
        customPri= CustomPriority.list,
    }
    pcall(function()
        local enc = HttpService:JSONEncode(s)
        setclipboard("MAKARA_SETTINGS:"..enc)
    end)
    log("[Cfg] Settings saved to clipboard")
end

function Settings:load(raw)
    if not raw:find("^MAKARA_SETTINGS:") then return false end
    local json = raw:sub(17)
    local ok, s = pcall(function() return HttpService:JSONDecode(json) end)
    if not ok then return false end
    if s.mode     then State.mode     = s.mode     end
    if s.filterS  ~= nil then State.filterS  = s.filterS  end
    if s.filterA  ~= nil then State.filterA  = s.filterA  end
    if s.filterU  ~= nil then State.filterU  = s.filterU  end
    if s.filterIGN~= nil then State.filterIGN= s.filterIGN end
    if s.espOn    ~= nil then State.espOn    = s.espOn    end
    if s.autoGrab ~= nil then State.autoGrab = s.autoGrab end
    if s.blacklist then Blacklist.list = s.blacklist end
    if s.customPri then CustomPriority.list = s.customPri end
    log("[Cfg] Settings loaded")
    return true
end

-- ╔══════════════════════════════════════════════════════╗
-- ║       § T. FULL LICENSE MANAGEMENT TAB SECTION       ║
-- ╚══════════════════════════════════════════════════════╝

-- Extra section inside Tab 1 (Home) — license management
local LicMgmtTitle = mkLabel(tabPages[1], {
    pos=UDim2.new(0,0,0,y1), size=UDim2.new(1,0,0,14),
    text="🔑 License Management",
    color=Color3.fromRGB(180,160,255), ts=9, font=Enum.Font.GothamBold
})
y1 = y1+16

local SaveCfgBtn = mkBtn(tabPages[1], {
    pos=UDim2.new(0,0,0,y1), size=UDim2.new(0.49,0,0,22),
    bg=Color3.fromRGB(30,70,30), text="💾 Save Config", ts=9
})
local LoadCfgBtn = mkBtn(tabPages[1], {
    pos=UDim2.new(0.51,0,0,y1), size=UDim2.new(0.49,0,0,22),
    bg=Color3.fromRGB(30,50,100), text="📂 Load Config", ts=9
})
y1 = y1+25

SaveCfgBtn.MouseButton1Click:Connect(function()
    Settings:save()
    SaveCfgBtn.Text="✅ Saved!"
    task.delay(1.5, function()
        if SaveCfgBtn and SaveCfgBtn.Parent then SaveCfgBtn.Text="💾 Save Config" end
    end)
end)

LoadCfgBtn.MouseButton1Click:Connect(function()
    -- Try reading from clipboard
    local raw=""
    pcall(function() raw=getclipboard() end)
    local ok = Settings:load(raw)
    LoadCfgBtn.Text = ok and "✅ Loaded!" or "❌ Invalid"
    task.delay(1.5, function()
        if LoadCfgBtn and LoadCfgBtn.Parent then LoadCfgBtn.Text="📂 Load Config" end
    end)
end)

-- ╔══════════════════════════════════════════════════════╗
-- ║       § U. ADVANCED FILTER: CUSTOM KEYWORD EDITOR    ║
-- ╚══════════════════════════════════════════════════════╝

-- In Filter tab — keyword input
local FilterKWTitle = mkLabel(tabPages[3], {
    pos=UDim2.new(0,0,0,274), size=UDim2.new(1,0,0,16),
    text="➕ Custom Priority Keywords:",
    color=Color3.fromRGB(200,200,255), ts=10, font=Enum.Font.GothamBold
})

local KWBg = mkFrame(tabPages[3], {
    pos=UDim2.new(0,0,0,292), size=UDim2.new(1,0,0,30),
    bg=Color3.fromRGB(14,14,24), radius=UDim.new(0,7),
    stroke=Color3.fromRGB(70,35,140)
})
local KWInput = Instance.new("TextBox", KWBg)
KWInput.Size=UDim2.new(0.7,0,1,0)
KWInput.Position=UDim2.new(0,4,0,0)
KWInput.BackgroundTransparency=1
KWInput.TextColor3=Color3.fromRGB(220,220,255)
KWInput.PlaceholderText="keyword..."
KWInput.PlaceholderColor3=Color3.fromRGB(80,70,120)
KWInput.Text=""
KWInput.TextSize=10
KWInput.Font=Enum.Font.Gotham
KWInput.ClearTextOnFocus=false

local KWAddBtn = mkBtn(KWBg, {
    pos=UDim2.new(0.72,0,0,3), size=UDim2.new(0.14,-2,1,-6),
    bg=Color3.fromRGB(0,110,50), text="+", ts=11, radius=UDim.new(0,5)
})
local KWRemBtn = mkBtn(KWBg, {
    pos=UDim2.new(0.87,0,0,3), size=UDim2.new(0.13,-3,1,-6),
    bg=Color3.fromRGB(110,20,20), text="−", ts=11, radius=UDim.new(0,5)
})

local KWListL = mkLabel(tabPages[3], {
    pos=UDim2.new(0,0,0,326), size=UDim2.new(1,0,0,30),
    text="Priority: (none)", color=Color3.fromRGB(130,130,180),
    ts=8, wrap=true
})

local function refreshKWList()
    if #CustomPriority.list==0 then
        KWListL.Text="Priority: (none)"
    else
        KWListL.Text="Priority: "..table.concat(CustomPriority.list, ", ")
    end
end

KWAddBtn.MouseButton1Click:Connect(function()
    local kw = KWInput.Text
    if kw~="" then
        CustomPriority:add(kw)
        KWInput.Text=""
        refreshKWList()
    end
end)
KWRemBtn.MouseButton1Click:Connect(function()
    local kw = KWInput.Text
    if kw~="" then
        CustomPriority:remove(kw)
        KWInput.Text=""
        refreshKWList()
    end
end)

-- Blacklist editor
local BLTitle = mkLabel(tabPages[3], {
    pos=UDim2.new(0,0,0,360), size=UDim2.new(1,0,0,16),
    text="🚫 Blacklist Keywords:", color=Color3.fromRGB(200,200,255),
    ts=10, font=Enum.Font.GothamBold
})
local BLBg = mkFrame(tabPages[3], {
    pos=UDim2.new(0,0,0,378), size=UDim2.new(1,0,0,30),
    bg=Color3.fromRGB(14,14,24), radius=UDim.new(0,7),
    stroke=Color3.fromRGB(100,25,25)
})
local BLInput = Instance.new("TextBox", BLBg)
BLInput.Size=UDim2.new(0.7,0,1,0)
BLInput.Position=UDim2.new(0,4,0,0)
BLInput.BackgroundTransparency=1
BLInput.TextColor3=Color3.fromRGB(220,200,200)
BLInput.PlaceholderText="keyword to skip..."
BLInput.PlaceholderColor3=Color3.fromRGB(100,70,70)
BLInput.Text=""
BLInput.TextSize=10
BLInput.Font=Enum.Font.Gotham
BLInput.ClearTextOnFocus=false

local BLAddBtn=mkBtn(BLBg,{pos=UDim2.new(0.72,0,0,3),size=UDim2.new(0.14,-2,1,-6),
    bg=Color3.fromRGB(0,110,50),text="+",ts=11,radius=UDim.new(0,5)})
local BLRemBtn=mkBtn(BLBg,{pos=UDim2.new(0.87,0,0,3),size=UDim2.new(0.13,-3,1,-6),
    bg=Color3.fromRGB(110,20,20),text="−",ts=11,radius=UDim.new(0,5)})

local BLListL=mkLabel(tabPages[3],{
    pos=UDim2.new(0,0,0,412),size=UDim2.new(1,0,0,28),
    text="Blacklist: (none)",color=Color3.fromRGB(180,100,100),ts=8,wrap=true
})

local function refreshBLList()
    if #Blacklist.list==0 then BLListL.Text="Blacklist: (none)"
    else BLListL.Text="Blacklist: "..table.concat(Blacklist.list,", ") end
end

BLAddBtn.MouseButton1Click:Connect(function()
    local kw=BLInput.Text
    if kw~="" then Blacklist:add(kw); BLInput.Text=""; refreshBLList() end
end)
BLRemBtn.MouseButton1Click:Connect(function()
    local kw=BLInput.Text
    if kw~="" then Blacklist:remove(kw); BLInput.Text=""; refreshBLList() end
end)

-- ╔══════════════════════════════════════════════════════╗
-- ║       § V. ANIMATED TITLE BAR GRADIENT              ║
-- ╚══════════════════════════════════════════════════════╝

task.spawn(function()
    local colors = {
        Color3.fromRGB(62,20,145),
        Color3.fromRGB(80,15,160),
        Color3.fromRGB(50,10,130),
        Color3.fromRGB(70,25,155),
    }
    local idx = 1
    while true do
        task.wait(2)
        if State.licensed and MainFrame.Visible then
            idx = idx % #colors + 1
            TweenService:Create(TBar, TweenInfo.new(1.5, Enum.EasingStyle.Sine),
                {BackgroundColor3=colors[idx]}):Play()
        end
    end
end)

-- ╔══════════════════════════════════════════════════════╗
-- ║       § W. EGG COUNT SPARKLE EFFECT                  ║
-- ║   Visual flash on steal milestone                    ║
-- ╚══════════════════════════════════════════════════════╝

local function flashStat()
    local orig = EggStatL.TextColor3
    EggStatL.TextColor3 = Color3.fromRGB(255,255,100)
    task.delay(0.3, function()
        if EggStatL and EggStatL.Parent then
            EggStatL.TextColor3 = orig
        end
    end)
end

-- Patch steal to flash on steal
local _prevStealW = stealEgg
stealEgg = function(egg, char)
    _prevStealW(egg, char)
    pcall(flashStat)
end

-- ╔══════════════════════════════════════════════════════╗
-- ║       § X. PERFORMANCE MONITOR                       ║
-- ╚══════════════════════════════════════════════════════╝

local PerfMon = {}
PerfMon.scanTimes = {}
PerfMon.stealTimes = {}

function PerfMon:recordScan(dt)
    table.insert(self.scanTimes, 1, dt)
    if #self.scanTimes > 20 then table.remove(self.scanTimes) end
end

function PerfMon:avgScan()
    if #self.scanTimes == 0 then return 0 end
    local s = 0
    for _,t in ipairs(self.scanTimes) do s=s+t end
    return s/#self.scanTimes
end

function PerfMon:recordSteal(dt)
    table.insert(self.stealTimes, 1, dt)
    if #self.stealTimes > 20 then table.remove(self.stealTimes) end
end

function PerfMon:avgSteal()
    if #self.stealTimes == 0 then return 0 end
    local s=0
    for _,t in ipairs(self.stealTimes) do s=s+t end
    return s/#self.stealTimes
end

-- Monitor label in Stats tab
local PerfL = mkLabel(tabPages[4], {
    pos=UDim2.new(0,0,0,402), size=UDim2.new(1,0,0,28),
    text="⚡ Perf: Scan 0ms | Steal 0ms",
    color=Color3.fromRGB(150,150,200), ts=9, wrap=true
})

task.spawn(function()
    while true do
        task.wait(3)
        if curTab==4 then
            PerfL.Text=string.format(
                "⚡ Perf: Scan %.0fms | Steal %.0fms | TPs: %d",
                PerfMon:avgScan()*1000,
                PerfMon:avgSteal()*1000,
                TPGuard.tpCount
            )
        end
    end
end)

-- ╔══════════════════════════════════════════════════════╗
-- ║       § Y. ANTI-BAN RANDOMIZER UPGRADE              ║
-- ║   Fake human movement patterns                       ║
-- ╚══════════════════════════════════════════════════════╝

local HumanSim = {}
HumanSim.enabled = true

function HumanSim:fakeWalk(char, targetPos)
    if not self.enabled then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end

    -- Occasional pause
    if math.random() < 0.08 then
        task.wait(math.random(4,10)/10)
    end

    -- Slight overshoot then correct (human error simulation)
    if math.random() < 0.15 then
        local overshoot = targetPos + (targetPos - hrp.Position).Unit * math.random(2,6)
        hrp.CFrame = CFrame.new(overshoot)
        task.wait(0.12)
    end

    -- Random micro-rotate
    if math.random() < 0.2 then
        hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(math.random(-15,15)), 0)
        task.wait(0.05)
    end
end

-- Hook into safeTP
local _prevSafeTP2 = safeTP
safeTP = function(char, pos)
    if HumanSim.enabled then
        task.spawn(function() HumanSim:fakeWalk(char, pos) end)
    end
    _prevSafeTP2(char, pos)
end

-- ╔══════════════════════════════════════════════════════╗
-- ║       § Z. FINAL STARTUP SEQUENCE                    ║
-- ╚══════════════════════════════════════════════════════╝

-- All systems ready
log("[§A-Z] All 26 modules active")
log("[Free] MAKARA4YOU — full access, limited tier")
log("[Tip] Double-click screen to show GUI when hidden")

-- ═══════════════════════════════════════
-- AUTO-LICENSE: Delta mobile TextBox input is unreliable
-- Auto-activate free key 0.8s after load so GUI always appears
-- ═══════════════════════════════════════
task.delay(0.8, function()
    if not State.licensed then
        local ok, msg = activateLicense(FREE_LICENSE)
        if ok then
            log("[AutoLic] Free key auto-activated for Delta mobile")
        end
    end
end)

-- Boot toast
toast("🥚 MAKARA Tool "..VER.." loaded!", 3, Color3.fromRGB(180,160,255))

print("╔══════════════════════════════════════╗")
print("║    MAKARA Tool v4 — FULL LOADED      ║")
print("║    Modules: §A through §Z (26 total) ║")
print("║    Free Key: MAKARA4YOU              ║")
print("║    F5=Start  F6=Hide  F8=ESP  F9=Mode║")
print("╚══════════════════════════════════════╝")
