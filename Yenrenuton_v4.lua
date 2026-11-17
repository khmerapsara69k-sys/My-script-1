--[[
    Yenrenuton [ALPHA]  (v4)
    UI: WindUI | Key: IN-ALPHA | Mobile / PC / Laptop

    CHANGES
    - AIMBOT: prediction (leads moving targets, leads along their movement when they back away,
      aims normally when they run toward you), projectile-speed mode, vertical toggle,
      on-screen KILL BUTTON + kill key so you can turn it off any time.
    - FLY / SPEED / JUMP POWER: now the Infinite Yield method
        Fly   = BodyGyro + BodyVelocity + PlatformStand, ControlModule move vector (mobile + PC)
        Speed = WalkSpeed property loop  |  TPWalk (TranslateBy)
        Jump  = JumpPower / JumpHeight (UseJumpPower aware) loop  |  Infinite Jump
    - ESP: Aura (Highlight) / Box (SelectionBox) / Both, plus HP | Distance | Team label.
    - Removed the custom reopen icon (WindUI's own open button is used).
    - Every numeric setting is a TEXT BOX (no sliders).

    NEW
    R6->R15, R15->R6 | Invisible | Ragdoll | TP Tool | Weather (local) | RTX (local)
    Headsit | Cape | Hang on back | Platform Tool | Freeze
]]

------------------------------------------------------------
-- Single-instance guard
------------------------------------------------------------
local genv = (getgenv and getgenv()) or _G
if genv.__YenrenutonUnload then pcall(genv.__YenrenutonUnload) end

------------------------------------------------------------
-- Services
------------------------------------------------------------
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local UserInputService    = game:GetService("UserInputService")
local TweenService        = game:GetService("TweenService")
local Workspace           = game:GetService("Workspace")
local CoreGui             = game:GetService("CoreGui")
local Lighting            = game:GetService("Lighting")
local MaterialService     = game:GetService("MaterialService")
local AvatarEditorService = game:GetService("AvatarEditorService")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

------------------------------------------------------------
-- Platform detection
------------------------------------------------------------
local Platform = {}
Platform.Touch    = UserInputService.TouchEnabled
Platform.Keyboard = UserInputService.KeyboardEnabled
Platform.Mobile   = Platform.Touch and not Platform.Keyboard
Platform.Laptop   = Platform.Keyboard and (Camera.ViewportSize.X < 1500)
Platform.PC       = Platform.Keyboard and not Platform.Laptop

local function getWindowSize()
    local vp = Camera.ViewportSize
    local w = math.clamp(vp.X - 40, 300, Platform.Mobile and 500 or 580)
    local h = math.clamp(vp.Y - 70, 220, Platform.Mobile and 320 or 460)
    return UDim2.fromOffset(w, h)
end

local function guiParent()
    local ok, h = pcall(function() return (gethui and gethui()) end)
    if ok and h then return h end
    local ok2 = pcall(function() return CoreGui.Name end)
    if ok2 then return CoreGui end
    return LocalPlayer:WaitForChild("PlayerGui")
end

------------------------------------------------------------
-- Load WindUI
------------------------------------------------------------
local WindUI = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
))()

------------------------------------------------------------
-- Maid
------------------------------------------------------------
local Maid = {}
Maid.__index = Maid
function Maid.new() return setmetatable({ _tasks = {} }, Maid) end
local function disposeTask(t)
    local ty = typeof(t)
    if ty == "RBXScriptConnection" then t:Disconnect()
    elseif ty == "Instance" then t:Destroy()
    elseif ty == "function" then pcall(t)
    elseif ty == "table" and t.Remove then pcall(function() t:Remove() end)
    elseif ty == "table" and t.Destroy then pcall(function() t:Destroy() end) end
end
function Maid:Give(task_, key)
    if key then self:Clear(key) end
    self._tasks[key or (#self._tasks + 1)] = task_
    return task_
end
function Maid:Clear(key)
    local t = self._tasks[key]
    if t ~= nil then self._tasks[key] = nil; disposeTask(t) end
end
function Maid:Destroy()
    for k, t in pairs(self._tasks) do self._tasks[k] = nil; disposeTask(t) end
end

local MainMaid = Maid.new()
local Feature  = {}
local function fmaid(name)
    if not Feature[name] then Feature[name] = Maid.new() end
    return Feature[name]
end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function getChar() return LocalPlayer.Character end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function getRoot()
    local c = getChar()
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end
local function isAlive(plr)
    local c = plr.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    return h ~= nil and h.Health > 0 and c:FindFirstChild("HumanoidRootPart") ~= nil
end
local function sameTeam(plr)
    return LocalPlayer.Team ~= nil and plr.Team == LocalPlayer.Team
end
local function isCharacterPart(part)
    local mdl = part:FindFirstAncestorOfClass("Model")
    return mdl ~= nil and mdl:FindFirstChildOfClass("Humanoid") ~= nil
end
local function notify(title, content, dur)
    pcall(function()
        WindUI:Notify({ Title = title, Content = content, Duration = dur or 3 })
    end)
end
local function playerNames()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then list[#list + 1] = p.Name end
    end
    table.sort(list)
    return list
end
local function esc(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
-- Every mover/constraint we create is tagged so the watchdog can sweep leftovers
local function tag(inst, owner)
    inst.Name = "Yen_" .. owner .. inst.ClassName
    inst:SetAttribute("YenOwner", owner)
    return inst
end
local function digitsOnly(s)
    local d = tostring(s):gsub("%D", "")
    return d
end

local UI = { Toggles = {}, Dropdowns = {} }
local function setToggle(key, v)
    local el = UI.Toggles[key]
    if el then pcall(function() el:Set(v) end) end
end

------------------------------------------------------------
-- Noclip manager (shared: Fling, Attach)
------------------------------------------------------------
local Noclip = { keys = {}, orig = setmetatable({}, { __mode = "k" }), conn = nil }
function Noclip.Acquire(key)
    Noclip.keys[key] = true
    if Noclip.conn then return end
    Noclip.conn = RunService.Stepped:Connect(function()
        local c = getChar()
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then
                if Noclip.orig[p] == nil then Noclip.orig[p] = p.CanCollide end
                p.CanCollide = false
            end
        end
    end)
end
function Noclip.Release(key)
    Noclip.keys[key] = nil
    if next(Noclip.keys) ~= nil then return end
    if Noclip.conn then Noclip.conn:Disconnect(); Noclip.conn = nil end
    for p, orig in pairs(Noclip.orig) do
        if p and p.Parent then p.CanCollide = orig end
        Noclip.orig[p] = nil
    end
end

------------------------------------------------------------
-- State
------------------------------------------------------------
local State = {
    Target = nil, -- shared "selected player"

    Fly   = { Enabled = false, Speed = 50 },
    Speed = { Enabled = false, Value = 32, Mode = "WalkSpeed (Yield)", TP = 2 },
    Jump  = { Enabled = false, Power = 50, Inf = false },

    ESP   = { Enabled = false, Mode = "Aura", HP = true, Distance = true, Team = true,
              TeamCheck = false, MaxDist = 2000, Fill = 60 },
    Xray  = { Enabled = false, Transparency = 70 },

    Aim   = { Enabled = false, FOV = 150, Smooth = 25, Part = "Head", TeamCheck = true,
              WallCheck = true, ShowFOV = true, HoldRMB = not Platform.Mobile,
              Predict = true, PredictTime = 0.12, ProjSpeed = 0, PredictVertical = false,
              KillKey = "K" },

    Ultra = { Enabled = false, Delay = 0, Range = 22, Cooldown = 0.35, MinTP = 10, MaxTP = 22,
              DashSpeed = 45, Dash = true, Projectiles = true, Strict = false, Ghost = true,
              TeamCheck = true, AnimId = "", Adapt = 1 },

    Orbit = { Enabled = false, Speed = 3, Radius = 8, Height = 0 },
    Fling = { Enabled = false, All = false },
    Spin  = { Enabled = false, Speed = 20 },
    Anim  = { Id = "", Speed = 1, Looped = true, Track = nil },

    Anti  = { Freeze = true, Tolerance = 0.5, Rubber = true },

    Invis   = { Enabled = false },
    Ragdoll = { Enabled = false },
    Freeze  = { Enabled = false, Pose = true },

    TPTool   = { Given = false, Height = 3 },
    PlatTool = { Given = false, Size = 12, Thick = 1, Trans = 0.3, Follow = true },

    Attach  = { HeadOffset = 1.4, HangDist = 1.15, CapeDist = 0.85 },

    Weather = { Name = "Clear", Intensity = 60 },
    RTX     = { Enabled = false, Quality = "Medium" },
}

local defaultWalkSpeed, defaultJumpPower, defaultJumpHeight = 16, 50, 7.2
do
    local h = getHum()
    if h then
        if h.WalkSpeed >= 1 then defaultWalkSpeed = h.WalkSpeed end
        if h.JumpPower >= 1 then defaultJumpPower = h.JumpPower end
        if h.JumpHeight >= 0.5 then defaultJumpHeight = h.JumpHeight end
    end
end

-- Text-box helper (replaces every slider)
local function NumBox(tab, title, default, lo, hi, apply, isInt)
    return tab:Input({
        Title = title,
        Desc = "Type a number (" .. tostring(lo) .. " to " .. tostring(hi) .. ")",
        Value = tostring(default),
        Placeholder = tostring(default),
        Callback = function(txt)
            local n = tonumber(txt)
            if not n then notify(title, "Please type a number.", 2); return end
            if isInt then n = math.floor(n + 0.5) end
            local c = math.clamp(n, lo, hi)
            if c ~= n then notify(title, "Clamped to " .. tostring(c), 2) end
            apply(c)
        end,
    })
end

local function Toggle(tab, key, title, initial, cb, desc)
    local el = tab:Toggle({ Title = title, Desc = desc, Value = initial, Callback = cb })
    if key then UI.Toggles[key] = el end
    return el
end

------------------------------------------------------------
-- Control vector (same source Infinite Yield uses for mobile fly)
------------------------------------------------------------
local ControlModule
local function getMoveVector()
    if not ControlModule then
        pcall(function()
            local pm = LocalPlayer:WaitForChild("PlayerScripts", 2):WaitForChild("PlayerModule", 2)
            ControlModule = require(pm:WaitForChild("ControlModule", 2))
        end)
    end
    if ControlModule then
        local ok, v = pcall(function() return ControlModule:GetMoveVector() end)
        if ok and typeof(v) == "Vector3" then return v end
    end
    local x = (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
    local z = (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
    return Vector3.new(x, 0, z)
end

------------------------------------------------------------
-- MOBILE FLY PAD (up / down)
------------------------------------------------------------
local MobileFly = { Up = false, Down = false, Gui = nil }

local function makeFlyPad()
    if MobileFly.Gui then return end
    local sg = Instance.new("ScreenGui")
    sg.Name = "YenFlyPad"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 999
    sg.Enabled = false
    sg.Parent = guiParent()

    local function mk(text, yScale, flag)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(62, 62)
        b.AnchorPoint = Vector2.new(1, 0.5)
        b.Position = UDim2.new(1, -24, yScale, 0)
        b.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
        b.BackgroundTransparency = 0.25
        b.Text = text
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 26
        b.AutoButtonColor = true
        b.Parent = sg
        Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
        local st = Instance.new("UIStroke", b)
        st.Color = Color3.fromRGB(120, 140, 255); st.Thickness = 2
        b.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
                MobileFly[flag] = true
            end
        end)
        b.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
                MobileFly[flag] = false
            end
        end)
    end
    mk("▲", 0.50, "Up")
    mk("▼", 0.64, "Down")
    MobileFly.Gui = sg
    MainMaid:Give(sg)
end

local function setFlyPad(visible)
    if not Platform.Touch then return end
    makeFlyPad()
    MobileFly.Gui.Enabled = visible
    if not visible then MobileFly.Up, MobileFly.Down = false, false end
end

------------------------------------------------------------
-- FLY  (Infinite Yield method: BodyGyro + BodyVelocity + PlatformStand)
------------------------------------------------------------
local function stopFly()
    fmaid("Fly"):Destroy()
    setFlyPad(false)
    local h = getHum()
    if h then h.PlatformStand = false end
    pcall(function() Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom end)
end

local function startFly()
    stopFly()
    local root, hum = getRoot(), getHum()
    if not (root and hum) or hum.Health <= 0 then return end
    local m = fmaid("Fly")

    local bg = tag(Instance.new("BodyGyro"), "Fly")
    bg.P = 9e4
    bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bg.CFrame = root.CFrame
    bg.Parent = root
    m:Give(bg)

    local bv = tag(Instance.new("BodyVelocity"), "Fly")
    bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bv.Velocity = Vector3.zero
    bv.Parent = root
    m:Give(bv)

    setFlyPad(true)

    m:Give(RunService.RenderStepped:Connect(function()
        if not (root.Parent and hum.Parent) or hum.Health <= 0 then return stopFly() end
        hum.PlatformStand = true
        local cam = Workspace.CurrentCamera
        local mv = getMoveVector()
        local up = 0
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E)
            or MobileFly.Up then up = up + 1 end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q)
            or MobileFly.Down then up = up - 1 end
        local dir = cam.CFrame.RightVector * mv.X + cam.CFrame.LookVector * -mv.Z + Vector3.new(0, up, 0)
        if dir.Magnitude > 1 then dir = dir.Unit end
        bv.Velocity = dir * State.Fly.Speed
        bg.CFrame = cam.CFrame
    end))
end

------------------------------------------------------------
-- SPEED  (Yield: WalkSpeed property loop | TPWalk)
------------------------------------------------------------
local function stopSpeed()
    fmaid("Speed"):Destroy()
    local h = getHum()
    if h then h.WalkSpeed = defaultWalkSpeed end
end

local function startSpeed()
    stopSpeed()
    local h0 = getHum()
    if h0 and h0.WalkSpeed >= 1 then defaultWalkSpeed = h0.WalkSpeed end
    local m = fmaid("Speed")

    if State.Speed.Mode == "WalkSpeed (Yield)" then
        local function apply()
            local h = getHum()
            if h and h.WalkSpeed ~= State.Speed.Value then h.WalkSpeed = State.Speed.Value end
        end
        apply()
        m:Give(RunService.Heartbeat:Connect(apply))
        if h0 then m:Give(h0:GetPropertyChangedSignal("WalkSpeed"):Connect(apply)) end
    else
        -- TPWalk (Yield): translate the character along MoveDirection
        m:Give(RunService.Heartbeat:Connect(function(dt)
            local c, h = getChar(), getHum()
            if c and h and h.Health > 0 and h.MoveDirection.Magnitude > 0 and not State.Fly.Enabled then
                c:TranslateBy(h.MoveDirection * State.Speed.TP * dt * 10)
            end
        end))
    end
end

------------------------------------------------------------
-- JUMP POWER  (Yield: JumpPower / JumpHeight depending on UseJumpPower)
------------------------------------------------------------
local function jumpApply(h)
    if h.UseJumpPower then
        if h.JumpPower ~= State.Jump.Power then h.JumpPower = State.Jump.Power end
    else
        if h.JumpHeight ~= State.Jump.Power then h.JumpHeight = State.Jump.Power end
    end
end

local function stopJump()
    fmaid("Jump"):Destroy()
    local h = getHum()
    if h then
        if h.UseJumpPower then h.JumpPower = defaultJumpPower else h.JumpHeight = defaultJumpHeight end
    end
end

local function startJump()
    stopJump()
    local h0 = getHum()
    if h0 then
        if h0.JumpPower >= 1 then defaultJumpPower = h0.JumpPower end
        if h0.JumpHeight >= 0.5 then defaultJumpHeight = h0.JumpHeight end
    end
    local m = fmaid("Jump")
    local function apply() local h = getHum(); if h then jumpApply(h) end end
    apply()
    m:Give(RunService.Heartbeat:Connect(apply))
    if h0 then
        m:Give(h0:GetPropertyChangedSignal("JumpPower"):Connect(apply))
        m:Give(h0:GetPropertyChangedSignal("JumpHeight"):Connect(apply))
        m:Give(h0:GetPropertyChangedSignal("UseJumpPower"):Connect(apply))
    end
end

local function setInfJump(on)
    State.Jump.Inf = on
    if not on then fmaid("InfJump"):Destroy(); return end
    fmaid("InfJump"):Give(UserInputService.JumpRequest:Connect(function()
        local h = getHum()
        if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end))
end

------------------------------------------------------------
-- ESP  (Aura | Box | Both  +  HP | Distance | Team label)
------------------------------------------------------------
local ESPObjects = {}

local function clearESP(plr)
    local o = ESPObjects[plr]
    if o then
        if o.hl then o.hl:Destroy() end
        if o.box then o.box:Destroy() end
        if o.gui then o.gui:Destroy() end
        ESPObjects[plr] = nil
    end
end

local function buildESP(plr)
    clearESP(plr)
    local char = plr.Character
    if not char then return end
    local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    if not head then return end

    local hl = Instance.new("Highlight")
    hl.Name = "YenESPAura"
    hl.FillTransparency = State.ESP.Fill / 100
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = char
    hl.Parent = char

    local box = Instance.new("SelectionBox")
    box.Name = "YenESPBox"
    box.Adornee = char
    box.LineThickness = 0.035
    box.SurfaceTransparency = 0.88
    box.Parent = char

    local gui = Instance.new("BillboardGui")
    gui.Name = "YenESPGui"
    gui.Adornee = head
    gui.AlwaysOnTop = true
    gui.Size = UDim2.fromOffset(160, 54)
    gui.StudsOffset = Vector3.new(0, 3.2, 0)
    gui.Parent = char

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextSize = Platform.Mobile and 12 or 13
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0.3
    label.RichText = true
    label.Text = ""
    label.Parent = gui

    ESPObjects[plr] = { hl = hl, box = box, gui = gui, label = label }
end

local function updateESP()
    local myRoot = getRoot()
    local mode = State.ESP.Mode
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local o = ESPObjects[plr]
            local char = plr.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and char:FindFirstChild("HumanoidRootPart")

            if not (hum and root and hum.Health > 0)
                or (State.ESP.TeamCheck and sameTeam(plr)) then
                if o then clearESP(plr) end
            else
                if not o or not o.hl.Parent then buildESP(plr); o = ESPObjects[plr] end
                if o then
                    local dist = myRoot and (myRoot.Position - root.Position).Magnitude or 0
                    local visible = dist <= State.ESP.MaxDist
                    local color = plr.Team and plr.TeamColor.Color or Color3.fromRGB(255, 70, 70)

                    o.hl.Enabled = visible and (mode == "Aura" or mode == "Both")
                    o.hl.FillColor = color
                    o.hl.OutlineColor = color
                    o.hl.FillTransparency = State.ESP.Fill / 100

                    o.box.Visible = visible and (mode == "Box" or mode == "Both")
                    o.box.Color3 = color
                    o.box.SurfaceColor3 = color

                    local lines = { string.format("<b>%s</b>", esc(plr.DisplayName)) }
                    if State.ESP.HP then
                        local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                        local c = Color3.fromHSV(pct * 0.33, 1, 1)
                        lines[#lines + 1] = string.format('<font color="#%s">HP: %d/%d</font>',
                            c:ToHex(), math.floor(hum.Health), math.floor(hum.MaxHealth))
                    end
                    if State.ESP.Distance then
                        lines[#lines + 1] = string.format("Dist: %dm", math.floor(dist))
                    end
                    if State.ESP.Team then
                        lines[#lines + 1] = string.format('<font color="#%s">Team: %s</font>',
                            color:ToHex(), esc(plr.Team and plr.Team.Name or "None"))
                    end
                    o.gui.Enabled = visible
                    o.label.Text = table.concat(lines, "\n")
                    o.gui.Size = UDim2.fromOffset(160, 14 * #lines + 6)
                end
            end
        end
    end
end

local function startESP()
    local m = fmaid("ESP")
    m:Give(RunService.Heartbeat:Connect(updateESP))
    m:Give(Players.PlayerRemoving:Connect(clearESP))
    m:Give(function() for p in pairs(ESPObjects) do clearESP(p) end end)
end
local function stopESP() fmaid("ESP"):Destroy() end

------------------------------------------------------------
-- X-RAY (1-100)
------------------------------------------------------------
local XrayOriginals = setmetatable({}, { __mode = "k" })

local function applyXray(part)
    if not part:IsA("BasePart") or isCharacterPart(part) then return end
    if XrayOriginals[part] == nil then XrayOriginals[part] = part.Transparency end
    part.Transparency = math.max(XrayOriginals[part], State.Xray.Transparency / 100)
end

local function stopXray()
    fmaid("Xray"):Destroy()
    for part, orig in pairs(XrayOriginals) do
        if part and part.Parent then part.Transparency = orig end
        XrayOriginals[part] = nil
    end
end

local function startXray()
    stopXray()
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("BasePart") then applyXray(d) end
    end
    fmaid("Xray"):Give(Workspace.DescendantAdded:Connect(function(d)
        if d:IsA("BasePart") then task.defer(applyXray, d) end
    end))
end

------------------------------------------------------------
-- AIMBOT (prediction + kill button)
------------------------------------------------------------
local FOVCircle
pcall(function()
    FOVCircle = Drawing.new("Circle")
    FOVCircle.Thickness = 1.5
    FOVCircle.NumSides = 64
    FOVCircle.Filled = false
    FOVCircle.Transparency = 1
    FOVCircle.Color = Color3.fromRGB(255, 255, 255)
    FOVCircle.Visible = false
    MainMaid:Give(function() FOVCircle:Remove() end)
end)

local function aimCenter()
    if Platform.Mobile then return Camera.ViewportSize / 2 end
    return UserInputService:GetMouseLocation()
end

local function hasLineOfSight(fromPos, targetPart)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { getChar(), Camera }
    local result = Workspace:Raycast(fromPos, targetPart.Position - fromPos, params)
    return result == nil or result.Instance:IsDescendantOf(targetPart.Parent)
end

-- smoothed per-player velocity (from position deltas, so it works even when
-- AssemblyLinearVelocity isn't replicated)
local PredTrack = {}
local function updateTracks(dt)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local c = plr.Character
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if r then
                local t = PredTrack[plr]
                if not t or t.root ~= r then
                    PredTrack[plr] = { root = r, last = r.Position, vel = Vector3.zero }
                else
                    if dt > 0 then
                        local inst = (r.Position - t.last) / dt
                        if inst.Magnitude > 400 then inst = Vector3.zero end -- ignore teleports
                        t.vel = t.vel:Lerp(inst, 0.35)
                    end
                    t.last = r.Position
                end
            end
        end
    end
end

-- Leads the target. Moving sideways / backing away -> aim ahead of their movement.
-- Running toward you -> normal aim (only sideways lead is kept).
local function aimPoint(plr, part)
    local pos = part.Position
    if not State.Aim.Predict then return pos end
    local tr = PredTrack[plr]
    if not tr then return pos end
    local vel = tr.vel
    if not State.Aim.PredictVertical then vel = Vector3.new(vel.X, 0, vel.Z) end

    local to = pos - Camera.CFrame.Position
    local dist = to.Magnitude
    if dist < 1 then return pos end
    local dir = to / dist

    local radial = vel:Dot(dir)            -- > 0: moving away from you
    local lateral = vel - dir * radial
    local t = (State.Aim.ProjSpeed > 0) and (dist / State.Aim.ProjSpeed) or State.Aim.PredictTime

    local lead
    if radial > 0 then
        lead = vel * t                     -- backing away: lead along their movement
    else
        lead = lateral * t                 -- coming at you: normal aim
    end
    return pos + lead
end

local function getAimTarget()
    local best, bestDist, bestPoint
    local center = aimCenter()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and isAlive(plr)
            and not (State.Aim.TeamCheck and sameTeam(plr)) then
            local part = plr.Character:FindFirstChild(State.Aim.Part)
                or plr.Character:FindFirstChild("HumanoidRootPart")
            if part then
                local pt = aimPoint(plr, part)
                local sp, onScreen = Camera:WorldToViewportPoint(pt)
                if onScreen then
                    local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    if d <= State.Aim.FOV and (not bestDist or d < bestDist)
                        and (not State.Aim.WallCheck or hasLineOfSight(Camera.CFrame.Position, part)) then
                        best, bestDist, bestPoint = part, d, pt
                    end
                end
            end
        end
    end
    return best, bestPoint
end

-- on-screen kill button
local AimButton
local function ensureAimButton()
    if AimButton then return end
    local sg = Instance.new("ScreenGui")
    sg.Name = "YenAimKill"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 1001
    sg.Enabled = false
    sg.Parent = guiParent()

    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(Platform.Mobile and 132 or 122, Platform.Mobile and 46 or 40)
    b.AnchorPoint = Vector2.new(1, 0)
    b.Position = UDim2.new(1, -16, 0, 70)
    b.BackgroundColor3 = Color3.fromRGB(150, 30, 40)
    b.BackgroundTransparency = 0.1
    b.Text = "AIMBOT ON\ntap to turn off"
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.AutoButtonColor = true
    b.Parent = sg
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
    local st = Instance.new("UIStroke", b)
    st.Color = Color3.fromRGB(255, 120, 130); st.Thickness = 2

    AimButton = { Gui = sg, Button = b }
    MainMaid:Give(sg)
end

local function stopAimbot(fromButton)
    State.Aim.Enabled = false
    fmaid("Aim"):Destroy()
    if AimButton then AimButton.Gui.Enabled = false end
    setToggle("Aim", false)
    if fromButton then notify("Aimbot", "Turned off.", 2) end
end

local function startAim()
    local m = fmaid("Aim")
    ensureAimButton()
    AimButton.Gui.Enabled = true
    m:Give(AimButton.Button.Activated:Connect(function() stopAimbot(true) end))

    m:Give(RunService.RenderStepped:Connect(function(dt)
        Camera = Workspace.CurrentCamera
        updateTracks(dt)
        if FOVCircle then
            FOVCircle.Visible = State.Aim.ShowFOV
            FOVCircle.Radius = State.Aim.FOV
            FOVCircle.Position = aimCenter()
        end
        if State.Aim.HoldRMB and not Platform.Mobile
            and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            return
        end
        local part, point = getAimTarget()
        if part then
            local alpha = 1 - (State.Aim.Smooth / 100) * 0.95
            Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, point), alpha)
        end
    end))
    m:Give(function()
        if FOVCircle then FOVCircle.Visible = false end
        if AimButton then AimButton.Gui.Enabled = false end
    end)
end

-- kill key (PC)
MainMaid:Give(UserInputService.InputBegan:Connect(function(input, processed)
    if processed or not State.Aim.Enabled then return end
    if input.UserInputType == Enum.UserInputType.Keyboard
        and input.KeyCode.Name:lower() == tostring(State.Aim.KillKey):lower() then
        stopAimbot(true)
    end
end))

------------------------------------------------------------
-- ULTRA INSTINCTS (instant teleport dodge)
------------------------------------------------------------
local lastDodge = 0
local lastAdaptNotify = 0
local dodgeTrack

local IgnoreAnimNames = {
    "idle", "walk", "run", "jump", "fall", "climb", "swim", "sit", "pose",
    "emote", "dance", "wave", "point", "cheer", "laugh", "toolnone", "equip",
}
local ActionPriorities = {
    [Enum.AnimationPriority.Action]  = true, [Enum.AnimationPriority.Action2] = true,
    [Enum.AnimationPriority.Action3] = true, [Enum.AnimationPriority.Action4] = true,
}

local function afterimage(char)
    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            local ghost = Instance.new("Part")
            ghost.Anchored, ghost.CanCollide, ghost.CanQuery, ghost.CanTouch = true, false, false, false
            ghost.Size = part.Size
            ghost.CFrame = part.CFrame
            ghost.Material = Enum.Material.Neon
            ghost.Color = Color3.fromRGB(190, 210, 255)
            ghost.Transparency = 0.4
            ghost.Parent = Workspace
            TweenService:Create(ghost, TweenInfo.new(0.35), { Transparency = 1 }):Play()
            task.delay(0.4, function() ghost:Destroy() end)
        end
    end
end

local function findSafeSpot(origin, threatPos, hum, root)
    local char = getChar()
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { char }

    local overlap = OverlapParams.new()
    overlap.FilterType = Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances = { char }

    local rigHeight = (hum.RigType == Enum.HumanoidRigType.R6) and 3 or (hum.HipHeight + root.Size.Y / 2)
    rigHeight = rigHeight + 0.3

    local minR = math.max(4, State.Ultra.MinTP * State.Ultra.Adapt)
    local maxR = math.max(minR + 1, State.Ultra.MaxTP * State.Ultra.Adapt)

    local best, bestScore
    for _ = 1, 16 do
        local ang = math.random() * math.pi * 2
        local rad = minR + math.random() * (maxR - minR)
        local cand = origin + Vector3.new(math.cos(ang) * rad, 0, math.sin(ang) * rad)

        local down = Workspace:Raycast(cand + Vector3.new(0, 30, 0), Vector3.new(0, -90, 0), rayParams)
        if down and down.Normal.Y > 0.6 then
            local pos = down.Position + Vector3.new(0, rigHeight, 0)
            if math.abs(pos.Y - origin.Y) < 25
                and #Workspace:GetPartBoundsInRadius(pos, 2.2, overlap) == 0 then
                local score = (pos - threatPos).Magnitude + math.random() * 6
                if not bestScore or score > bestScore then best, bestScore = pos, score end
            end
        end
    end
    return best, minR
end

local function performDodge(threat)
    local char, root, hum = getChar(), getRoot(), getHum()
    if not (char and root and hum) or hum.Health <= 0 then return end
    if not threat or not threat.Parent then return end
    if os.clock() - lastDodge < State.Ultra.Cooldown then return end
    lastDodge = os.clock()

    local origin = root.Position
    local threatPos = threat.Position
    local spot, minR = findSafeSpot(origin, threatPos, hum, root)
    if not spot then
        local away = (origin - threatPos) * Vector3.new(1, 0, 1)
        away = away.Magnitude > 0.1 and away.Unit or -root.CFrame.LookVector
        spot = origin + away * minR
    end

    if State.Ultra.Ghost then afterimage(char) end

    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    local faceAt = Vector3.new(threatPos.X, spot.Y, threatPos.Z)
    if (faceAt - spot).Magnitude > 0.5 then
        root.CFrame = CFrame.lookAt(spot, faceAt)
    else
        root.CFrame = CFrame.new(spot)
    end

    local id = State.Ultra.AnimId
    if id ~= "" then
        pcall(function()
            local d = digitsOnly(id)
            if d == "" then return end
            local anim = Instance.new("Animation")
            anim.AnimationId = "rbxassetid://" .. d
            if dodgeTrack then dodgeTrack:Stop(0.05) end
            dodgeTrack = hum:LoadAnimation(anim)
            dodgeTrack.Priority = Enum.AnimationPriority.Action4
            dodgeTrack.Looped = false
            dodgeTrack:Play(0.05)
            task.delay(0.8, function() if dodgeTrack then dodgeTrack:Stop(0.1) end end)
        end)
    end

    local moved = (spot - origin).Magnitude
    task.delay(0.25, function()
        local r = getRoot()
        if not (r and State.Anti.Rubber) then return end
        if moved > 8 and (r.Position - origin).Magnitude < 4 then
            State.Ultra.Adapt = math.max(0.35, State.Ultra.Adapt * 0.7)
            if os.clock() - lastAdaptNotify > 5 then
                lastAdaptNotify = os.clock()
                notify("Ultra Instincts", "Server pulled you back. Teleport range auto-reduced.", 3)
            end
        else
            State.Ultra.Adapt = math.min(1, State.Ultra.Adapt + 0.1)
        end
    end)
end

local function triggerDodge(src)
    if not State.Ultra.Enabled then return end
    if os.clock() - lastDodge < State.Ultra.Cooldown then return end
    local d = State.Ultra.Delay
    if d <= 0 then
        performDodge(src)
    else
        task.delay(d, function() if State.Ultra.Enabled then performDodge(src) end end)
    end
end

local function isAttackTrack(track)
    if track.Looped then return false end
    local name = (track.Name or ""):lower()
    for _, ignore in ipairs(IgnoreAnimNames) do
        if name:find(ignore, 1, true) then return false end
    end
    if State.Ultra.Strict then return ActionPriorities[track.Priority] == true end
    return track.Length <= 3
end

local function watchAttacker(plr)
    if plr == LocalPlayer then return end
    local m = fmaid("Ultra")
    local function hook(char)
        local hum  = char:WaitForChild("Humanoid", 5)
        local root = char:WaitForChild("HumanoidRootPart", 5)
        if not (hum and root) then return end
        local animator = hum:WaitForChild("Animator", 5)
        if not animator then return end
        m:Give(animator.AnimationPlayed:Connect(function(track)
            if not State.Ultra.Enabled then return end
            if State.Ultra.TeamCheck and sameTeam(plr) then return end
            local myRoot = getRoot()
            if not myRoot then return end
            local to = myRoot.Position - root.Position
            local dist = to.Magnitude
            if dist > State.Ultra.Range + 6 or dist < 0.1 then return end
            if not isAttackTrack(track) then return end
            local facing = root.CFrame.LookVector:Dot(to.Unit)
            if facing < (State.Ultra.Strict and 0.3 or -0.2) then return end
            triggerDodge(root)
        end))
    end
    if plr.Character then task.spawn(hook, plr.Character) end
    m:Give(plr.CharacterAdded:Connect(function(c) task.spawn(hook, c) end))
end

local function startUltra()
    local m = fmaid("Ultra")
    for _, p in ipairs(Players:GetPlayers()) do watchAttacker(p) end
    m:Give(Players.PlayerAdded:Connect(watchAttacker))

    m:Give(RunService.Heartbeat:Connect(function()
        if not (State.Ultra.Enabled and State.Ultra.Dash) then return end
        local myRoot = getRoot()
        if not myRoot then return end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and isAlive(plr)
                and not (State.Ultra.TeamCheck and sameTeam(plr)) then
                local r = plr.Character.HumanoidRootPart
                local to = myRoot.Position - r.Position
                local dist = to.Magnitude
                if dist < State.Ultra.Range and dist > 0.5 then
                    if r.AssemblyLinearVelocity:Dot(to / dist) > State.Ultra.DashSpeed then
                        triggerDodge(r)
                    end
                end
            end
        end
    end))

    m:Give(Workspace.DescendantAdded:Connect(function(d)
        if not (State.Ultra.Enabled and State.Ultra.Projectiles) then return end
        if not d:IsA("BasePart") or d.Anchored then return end
        task.defer(function()
            if not d.Parent then return end
            local myRoot, myChar = getRoot(), getChar()
            if not (myRoot and myChar) then return end
            if d:IsDescendantOf(myChar) or isCharacterPart(d) then return end
            if d.Size.Magnitude > 14 then return end
            local to = myRoot.Position - d.Position
            local dist = to.Magnitude
            if dist < 0.5 or dist > State.Ultra.Range * 5 then return end
            local closing = d.AssemblyLinearVelocity:Dot(to / dist)
            if closing < 40 then return end
            local t = dist / closing
            if t > 1.5 then return end
            task.delay(math.max(0, t - 0.15 - State.Ultra.Delay), function()
                if State.Ultra.Enabled and d.Parent then performDodge(d) end
            end)
        end)
    end))
end

------------------------------------------------------------
-- ORBIT (selected player)
------------------------------------------------------------
local function stopOrbit()
    fmaid("Orbit"):Destroy()
    local root = getRoot()
    if root then root.AssemblyLinearVelocity = Vector3.zero end
end
local function startOrbit()
    stopOrbit()
    local angle = 0
    fmaid("Orbit"):Give(RunService.Heartbeat:Connect(function(dt)
        local target = State.Target and Players:FindFirstChild(State.Target)
        local root = getRoot()
        if not (target and root and isAlive(target)) then return end
        local tRoot = target.Character.HumanoidRootPart
        angle = angle + dt * State.Orbit.Speed
        local offset = Vector3.new(math.cos(angle) * State.Orbit.Radius, State.Orbit.Height,
                                   math.sin(angle) * State.Orbit.Radius)
        root.CFrame = CFrame.lookAt(tRoot.Position + offset, tRoot.Position)
        root.AssemblyLinearVelocity = Vector3.zero
    end))
end

------------------------------------------------------------
-- FLING (selected player / everyone)
------------------------------------------------------------
local flingOrigin
local function stopFling()
    fmaid("Fling"):Destroy()
    Noclip.Release("Fling")
    local root = getRoot()
    if root then
        root.AssemblyAngularVelocity = Vector3.zero
        root.AssemblyLinearVelocity = Vector3.zero
        if flingOrigin then root.CFrame = flingOrigin end
    end
    flingOrigin = nil
end

local function startFling()
    stopFling()
    local root = getRoot()
    if not root then return end
    flingOrigin = root.CFrame
    Noclip.Acquire("Fling")
    fmaid("Fling"):Give(RunService.Heartbeat:Connect(function()
        local r = getRoot()
        if not r then return end
        local victims = {}
        if State.Fling.All then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and isAlive(p) then victims[#victims + 1] = p end
            end
        elseif State.Target then
            local p = Players:FindFirstChild(State.Target)
            if p and isAlive(p) then victims[1] = p end
        end
        local victim = victims[(math.floor(os.clock() * 4) % math.max(#victims, 1)) + 1]
        if victim then
            r.CFrame = victim.Character.HumanoidRootPart.CFrame
            r.AssemblyLinearVelocity = Vector3.new(9e5, 9e5, 9e5)
            r.AssemblyAngularVelocity = Vector3.new(0, 9e5, 0)
        end
    end))
end

------------------------------------------------------------
-- SPIN
------------------------------------------------------------
local function stopSpin() fmaid("Spin"):Destroy() end
local function startSpin()
    stopSpin()
    local root = getRoot()
    if not root then return end
    local m = fmaid("Spin")
    local att = tag(Instance.new("Attachment"), "Spin")
    att.Parent = root
    m:Give(att)
    local av = tag(Instance.new("AngularVelocity"), "Spin")
    av.Attachment0 = att
    av.MaxTorque = math.huge
    av.RelativeTo = Enum.ActuatorRelativeTo.World
    av.AngularVelocity = Vector3.new(0, State.Spin.Speed, 0)
    av.Parent = root
    m:Give(av)
    m:Give(RunService.Heartbeat:Connect(function()
        av.AngularVelocity = Vector3.new(0, State.Spin.Speed, 0)
    end))
end

------------------------------------------------------------
-- CUSTOM ANIMATION
------------------------------------------------------------
local function normalizeAnimId(raw)
    local d = digitsOnly(raw)
    return d ~= "" and ("rbxassetid://" .. d) or nil
end

local function stopAnim()
    if State.Anim.Track then
        pcall(function() State.Anim.Track:Stop(0.1); State.Anim.Track:Destroy() end)
        State.Anim.Track = nil
    end
end

local function playAnim()
    stopAnim()
    local hum = getHum()
    local id = normalizeAnimId(State.Anim.Id)
    if not hum then return notify("Animation", "No character found.") end
    if not id then return notify("Animation", "Place an animation ID first.") end

    local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
    local anim = Instance.new("Animation")
    anim.AnimationId = id
    local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
    if not ok or not track then return notify("Animation", "Failed to load that animation ID.") end

    track.Priority = Enum.AnimationPriority.Action4
    track.Looped = State.Anim.Looped
    track:Play(0.1, 1, State.Anim.Speed)
    State.Anim.Track = track
end

------------------------------------------------------------
-- ATTACH ENGINE: Headsit / Cape / Hang on back  (selected player, FE)
-- Your own character is positioned every frame, so the server replicates
-- the position and everyone sees it.
------------------------------------------------------------
local Attach = { Mode = nil }

local function stopAttach()
    fmaid("Attach"):Destroy()
    Noclip.Release("Attach")
    local h, r = getHum(), getRoot()
    if h then h.Sit = false; h.PlatformStand = false end
    if r then
        r.AssemblyLinearVelocity = Vector3.zero
        r.AssemblyAngularVelocity = Vector3.zero
    end
    Attach.Mode = nil
end

local function startAttach(mode)
    stopAttach()
    if not State.Target then
        notify(mode, "Pick a selected player first.", 3)
        return false
    end
    Attach.Mode = mode
    Noclip.Acquire("Attach")
    local m = fmaid("Attach")
    local t0 = os.clock()

    m:Give(RunService.Heartbeat:Connect(function()
        local r, h = getRoot(), getHum()
        local tp = State.Target and Players:FindFirstChild(State.Target)
        local tc = tp and tp.Character
        local tr = tc and tc:FindFirstChild("HumanoidRootPart")
        if not (r and h and tr) then return end

        r.AssemblyLinearVelocity = Vector3.zero
        r.AssemblyAngularVelocity = Vector3.zero

        local rot = tr.CFrame - tr.CFrame.Position
        local cf
        if mode == "Headsit" then
            h.Sit = true
            local head = tc:FindFirstChild("Head") or tr
            local p = head.Position + Vector3.new(0, head.Size.Y / 2 + State.Attach.HeadOffset, 0)
            cf = CFrame.new(p) * rot
        elseif mode == "Hang" then
            h.Sit = true
            cf = tr.CFrame * CFrame.new(0, 0.25, State.Attach.HangDist) * CFrame.Angles(math.rad(-12), 0, 0)
        else -- Cape
            h.PlatformStand = true
            local speedFactor = math.clamp(tr.AssemblyLinearVelocity.Magnitude / 16 * 14, 0, 38)
            local sway = 8 + speedFactor + math.sin((os.clock() - t0) * 2.6) * 4
            cf = tr.CFrame * CFrame.new(0, 1.1, State.Attach.CapeDist)
                * CFrame.Angles(-math.rad(sway), 0, 0) * CFrame.new(0, -2, 0)
        end
        r.CFrame = cf
    end))
    return true
end

local function attachToggle(mode, key, v)
    if v then
        for k, _ in pairs({ Headsit = 1, Cape = 1, Hang = 1 }) do
            if k ~= mode then setToggle(k, false) end
        end
        if not startAttach(mode) then setToggle(key, false) end
    else
        if Attach.Mode == mode then stopAttach() end
    end
end

------------------------------------------------------------
-- RAGDOLL (FE: joints replaced by ball sockets on your own character)
------------------------------------------------------------
local function ragdollOff()
    fmaid("Ragdoll"):Destroy()
    local c, h = getChar(), getHum()
    if c then
        for _, mo in ipairs(c:GetDescendants()) do
            if mo:IsA("Motor6D") and mo.Enabled == false then mo.Enabled = true end
        end
    end
    if h then
        h.PlatformStand = false
        pcall(function() h:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
end

local function ragdollOn()
    ragdollOff()
    local c, h = getChar(), getHum()
    if not (c and h) or h.Health <= 0 then return end
    local m = fmaid("Ragdoll")

    for _, mo in ipairs(c:GetDescendants()) do
        if mo:IsA("Motor6D") and mo.Part0 and mo.Part1 and mo.Part0.Name ~= "HumanoidRootPart" then
            local a0 = tag(Instance.new("Attachment"), "Ragdoll")
            a0.CFrame = mo.C0
            a0.Parent = mo.Part0
            local a1 = tag(Instance.new("Attachment"), "Ragdoll")
            a1.CFrame = mo.C1
            a1.Parent = mo.Part1
            local bs = tag(Instance.new("BallSocketConstraint"), "Ragdoll")
            bs.Attachment0 = a0
            bs.Attachment1 = a1
            bs.LimitsEnabled = true
            bs.UpperAngle = 70
            bs.TwistLimitsEnabled = true
            bs.TwistLowerAngle = -45
            bs.TwistUpperAngle = 45
            bs.Parent = mo.Part0
            mo.Enabled = false
            m:Give(a0); m:Give(a1); m:Give(bs)
        end
    end

    h.PlatformStand = true
    pcall(function() h:ChangeState(Enum.HumanoidStateType.Physics) end)
    m:Give(RunService.Heartbeat:Connect(function()
        local hh = getHum()
        if not hh or hh.Health <= 0 then return end
        hh.PlatformStand = true
        if hh:GetState() ~= Enum.HumanoidStateType.Physics then
            pcall(function() hh:ChangeState(Enum.HumanoidStateType.Physics) end)
        end
    end))
end

------------------------------------------------------------
-- FREEZE (FE: root anchored, optional pose freeze)
------------------------------------------------------------
local function stopFreeze()
    fmaid("Freeze"):Destroy()
    local r, h = getRoot(), getHum()
    if r then r.Anchored = false end
    if h then
        local animator = h:FindFirstChildOfClass("Animator")
        if animator then
            for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
                pcall(function() t:AdjustSpeed(1) end)
            end
        end
    end
end

local function startFreeze()
    stopFreeze()
    local r, h = getRoot(), getHum()
    if not (r and h) then return end
    local m = fmaid("Freeze")
    r.AssemblyLinearVelocity = Vector3.zero
    r.AssemblyAngularVelocity = Vector3.zero
    r.Anchored = true
    m:Give(RunService.Heartbeat:Connect(function()
        local rr, hh = getRoot(), getHum()
        if rr and not rr.Anchored then rr.Anchored = true end
        if State.Freeze.Pose and hh then
            local animator = hh:FindFirstChildOfClass("Animator")
            if animator then
                for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
                    if t.Speed ~= 0 then pcall(function() t:AdjustSpeed(0) end) end
                end
            end
        end
    end))
end

------------------------------------------------------------
-- INVISIBLE (FE: real character parked in the sky, you drive a local clone)
------------------------------------------------------------
local Invis = { On = false, Busy = false, Real = nil, Fake = nil }
local INVIS_SKY = Vector3.new(0, math.pi * 1000000, 0)

local function stopMovers()
    if State.Fly.Enabled then State.Fly.Enabled = false; stopFly(); setToggle("Fly", false) end
    if State.Spin.Enabled then State.Spin.Enabled = false; stopSpin(); setToggle("Spin", false) end
    if State.Fling.Enabled then State.Fling.Enabled = false; stopFling(); setToggle("Fling", false) end
    if State.Orbit.Enabled then State.Orbit.Enabled = false; stopOrbit(); setToggle("Orbit", false) end
    if State.Ragdoll.Enabled then State.Ragdoll.Enabled = false; ragdollOff(); setToggle("Ragdoll", false) end
    if State.Freeze.Enabled then State.Freeze.Enabled = false; stopFreeze(); setToggle("Freeze", false) end
    if Attach.Mode then
        local mode = Attach.Mode
        stopAttach()
        setToggle(mode, false)
    end
end

local function stopInvis()
    if not Invis.On then return end
    fmaid("Invis"):Destroy()
    local real, fake = Invis.Real, Invis.Fake
    Invis.On = false
    State.Invis.Enabled = false

    pcall(function()
        local fr = fake and fake:FindFirstChild("HumanoidRootPart")
        local rr = real and real:FindFirstChild("HumanoidRootPart")
        local dest = fr and fr.CFrame
        if real then
            real.Parent = Workspace
            LocalPlayer.Character = real
            if rr and dest then
                rr.CFrame = dest
                rr.AssemblyLinearVelocity = Vector3.zero
            end
            local h = real:FindFirstChildOfClass("Humanoid")
            if h then Workspace.CurrentCamera.CameraSubject = h end
        end
    end)
    if fake then pcall(function() fake:Destroy() end) end
    Invis.Real, Invis.Fake = nil, nil
end

local function startInvis()
    if Invis.On or Invis.Busy then return end
    local char, root, hum = getChar(), getRoot(), getHum()
    if not (char and root and hum) or hum.Health <= 0 then
        return notify("Invisible", "No character found.")
    end
    Invis.Busy = true
    stopMovers()

    task.spawn(function()
        local ok, err = pcall(function()
            char.Archivable = true
            local fake = char:Clone()
            -- strip any movers cloned along with the character
            for _, d in ipairs(fake:GetDescendants()) do
                if d:GetAttribute("YenOwner") then d:Destroy() end
            end
            for _, d in ipairs(fake:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.Transparency = (d.Name == "HumanoidRootPart") and 1 or 0.5
                end
            end

            local origCF = root.CFrame
            local cam = Workspace.CurrentCamera
            cam.CameraType = Enum.CameraType.Scriptable
            char:MoveTo(INVIS_SKY)
            task.wait(0.2)
            char.Parent = Lighting
            fake.Parent = Workspace
            local fr = fake:WaitForChild("HumanoidRootPart", 3)
            if fr then fr.CFrame = origCF end

            Invis.Real, Invis.Fake, Invis.On = char, fake, true
            State.Invis.Enabled = true
            LocalPlayer.Character = fake
            local fh = fake:FindFirstChildOfClass("Humanoid")
            if fh then cam.CameraSubject = fh end
            cam.CameraType = Enum.CameraType.Custom

            if fh then
                fmaid("Invis"):Give(fh.Died:Connect(function()
                    stopInvis()
                    setToggle("Invis", false)
                end))
            end
        end)
        Invis.Busy = false
        if not ok then
            pcall(function() Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom end)
            State.Invis.Enabled = false
            setToggle("Invis", false)
            notify("Invisible", "Failed: " .. tostring(err), 4)
        end
    end)
end

------------------------------------------------------------
-- R6 <-> R15 (saves the rig through the official avatar prompt, then respawns)
------------------------------------------------------------
local function switchRig(rig)
    local h = getHum()
    if not h then return notify("Rig", "No character found.") end
    if h.RigType == rig then
        return notify("Rig", "You are already " .. (rig == Enum.HumanoidRigType.R6 and "R6." or "R15."), 3)
    end
    task.spawn(function()
        local ok, desc = pcall(function() return h:GetAppliedDescription() end)
        if not ok or not desc then return notify("Rig", "Couldn't read your avatar.", 4) end
        local ok2, err = pcall(function() AvatarEditorService:PromptSaveAvatar(desc, rig) end)
        if not ok2 then return notify("Rig", "Avatar prompt unavailable: " .. tostring(err), 5) end
        local result = AvatarEditorService.PromptSaveAvatarCompleted:Wait()
        if result == Enum.AvatarPromptResult.Success then
            notify("Rig", "Saved. Respawning into the new rig...", 3)
            task.wait(0.4)
            pcall(function()
                local hh = getHum()
                if hh then hh.Health = 0 end
            end)
        else
            notify("Rig", "Cancelled or failed (" .. tostring(result) .. ").", 4)
        end
    end)
end

------------------------------------------------------------
-- TOOLS: TP Tool + Platform Tool
------------------------------------------------------------
local function getBackpack() return LocalPlayer:FindFirstChildOfClass("Backpack") end
local function removeTool(name)
    local bp = getBackpack()
    if bp then local t = bp:FindFirstChild(name); if t then t:Destroy() end end
    local c = getChar()
    if c then local t = c:FindFirstChild(name); if t then t:Destroy() end end
end

local function giveTPTool()
    removeTool("TP Tool")
    local bp = getBackpack()
    if not bp then return notify("TP Tool", "Backpack not found.") end
    local tool = Instance.new("Tool")
    tool.Name = "TP Tool"
    tool.ToolTip = "Click / tap to teleport"
    tool.RequiresHandle = false
    tool.CanBeDropped = false
    tool.Activated:Connect(function()
        local r = getRoot()
        local mouse = LocalPlayer:GetMouse()
        mouse.TargetFilter = getChar()
        local hit = mouse.Hit
        if r and hit then
            local rot = r.CFrame - r.CFrame.Position
            r.CFrame = CFrame.new(hit.Position + Vector3.new(0, State.TPTool.Height, 0)) * rot
            r.AssemblyLinearVelocity = Vector3.zero
        end
    end)
    tool.Parent = bp
    State.TPTool.Given = true
end

local PlatformPart
local function feetY()
    local r, h = getRoot(), getHum()
    if not (r and h) then return nil end
    local off = (h.RigType == Enum.HumanoidRigType.R6) and 3 or (h.HipHeight + r.Size.Y / 2)
    return r.Position.Y - off
end
local function destroyPlatform()
    if PlatformPart then PlatformPart:Destroy(); PlatformPart = nil end
end
local function applyPlatformProps()
    if not (PlatformPart and PlatformPart.Parent) then return end
    local S, T = State.PlatTool.Size, State.PlatTool.Thick
    local cf = PlatformPart.CFrame
    PlatformPart.Size = Vector3.new(S, T, S)
    PlatformPart.Transparency = State.PlatTool.Trans
    PlatformPart.CFrame = cf
end
local function placePlatform()
    local r, fy = getRoot(), feetY()
    if not (r and fy) then return end
    if not (PlatformPart and PlatformPart.Parent) then
        PlatformPart = Instance.new("Part")
        PlatformPart.Name = "YenPlatform"
        PlatformPart.Anchored = true
        PlatformPart.CanCollide = true
        PlatformPart.TopSurface = Enum.SurfaceType.Smooth
        PlatformPart.BottomSurface = Enum.SurfaceType.Smooth
        PlatformPart.Material = Enum.Material.SmoothPlastic
        PlatformPart.Color = Color3.fromRGB(120, 140, 255)
        PlatformPart.Parent = Workspace
    end
    local S, T = State.PlatTool.Size, State.PlatTool.Thick
    PlatformPart.Size = Vector3.new(S, T, S)
    PlatformPart.Transparency = State.PlatTool.Trans
    PlatformPart.CFrame = CFrame.new(r.Position.X, fy - T / 2 - 0.1, r.Position.Z)
end

local function givePlatformTool()
    removeTool("Platform")
    local bp = getBackpack()
    if not bp then return notify("Platform", "Backpack not found.") end
    local tool = Instance.new("Tool")
    tool.Name = "Platform"
    tool.ToolTip = "Click / tap to place a platform under your feet"
    tool.RequiresHandle = false
    tool.CanBeDropped = false
    tool.Activated:Connect(placePlatform)
    tool.Equipped:Connect(function()
        fmaid("PlatFollow"):Destroy()
        fmaid("PlatFollow"):Give(RunService.Heartbeat:Connect(function()
            local r = getRoot()
            if State.PlatTool.Follow and PlatformPart and PlatformPart.Parent and r then
                local y = PlatformPart.Position.Y
                PlatformPart.CFrame = CFrame.new(r.Position.X, y, r.Position.Z)
            end
        end))
    end)
    tool.Unequipped:Connect(function() fmaid("PlatFollow"):Destroy() end)
    tool.Parent = bp
    State.PlatTool.Given = true
end

------------------------------------------------------------
-- WEATHER (client-side only, NOT FE)
------------------------------------------------------------
local Weather = { Orig = nil }
local LIGHT_KEYS = { "Brightness", "ClockTime", "Ambient", "OutdoorAmbient", "FogColor", "FogStart",
    "FogEnd", "ColorShift_Top", "ColorShift_Bottom", "ExposureCompensation" }

local WeatherPresets = {
    Rain = { bright = 1.4, amb = Color3.fromRGB(95, 105, 120), out = Color3.fromRGB(85, 95, 110),
        fog = Color3.fromRGB(115, 125, 140), fogEnd = 1500, atm = 0.40, atmColor = Color3.fromRGB(155, 165, 180),
        cloud = 0.85, cloudColor = Color3.fromRGB(95, 100, 110), rain = true },
    Thunderstorm = { bright = 0.9, amb = Color3.fromRGB(60, 65, 80), out = Color3.fromRGB(55, 60, 75),
        fog = Color3.fromRGB(70, 75, 90), fogEnd = 1000, atm = 0.55, atmColor = Color3.fromRGB(110, 115, 130),
        cloud = 1, cloudColor = Color3.fromRGB(55, 58, 68), rain = true, heavy = true, lightning = true },
    Snow = { bright = 2.2, amb = Color3.fromRGB(150, 155, 165), out = Color3.fromRGB(165, 170, 180),
        fog = Color3.fromRGB(215, 220, 230), fogEnd = 1400, atm = 0.45, atmColor = Color3.fromRGB(225, 230, 240),
        cloud = 0.7, cloudColor = Color3.fromRGB(220, 225, 235), snow = true },
    Fog = { bright = 1.6, amb = Color3.fromRGB(130, 135, 140), out = Color3.fromRGB(135, 140, 145),
        fog = Color3.fromRGB(175, 180, 185), fogEnd = 700, atm = 0.8, atmColor = Color3.fromRGB(190, 195, 200),
        cloud = 0.5, cloudColor = Color3.fromRGB(170, 175, 180) },
    Sandstorm = { bright = 1.8, amb = Color3.fromRGB(170, 130, 80), out = Color3.fromRGB(180, 140, 85),
        fog = Color3.fromRGB(200, 160, 100), fogEnd = 500, atm = 0.75, atmColor = Color3.fromRGB(205, 160, 95),
        cloud = 0.3, cloudColor = Color3.fromRGB(190, 150, 90), sand = true },
    Sunset = { clock = 17.8, bright = 2.4, amb = Color3.fromRGB(120, 90, 85), out = Color3.fromRGB(150, 100, 90),
        fog = Color3.fromRGB(230, 150, 110), fogEnd = 4000, top = Color3.fromRGB(255, 170, 110) },
    Night = { clock = 0, bright = 0.4, amb = Color3.fromRGB(35, 40, 65), out = Color3.fromRGB(30, 35, 60),
        fog = Color3.fromRGB(15, 18, 30), fogEnd = 4000 },
}

local function weatherSnapshot()
    if Weather.Orig then return end
    local o = { light = {} }
    for _, k in ipairs(LIGHT_KEYS) do o.light[k] = Lighting[k] end
    local atm = Lighting:FindFirstChildOfClass("Atmosphere")
    if atm then
        o.atm = { Density = atm.Density, Offset = atm.Offset, Color = atm.Color, Decay = atm.Decay,
                  Glare = atm.Glare, Haze = atm.Haze }
    end
    local cl = Workspace.Terrain:FindFirstChildOfClass("Clouds")
    if cl then o.clouds = { Cover = cl.Cover, Density = cl.Density, Color = cl.Color, Enabled = cl.Enabled } end
    Weather.Orig = o
end

local function stopWeather()
    fmaid("Weather"):Destroy()
    local o = Weather.Orig
    if not o then return end
    for k, v in pairs(o.light) do pcall(function() Lighting[k] = v end) end
    local atm = Lighting:FindFirstChildOfClass("Atmosphere")
    if atm and o.atm then
        for k, v in pairs(o.atm) do pcall(function() atm[k] = v end) end
    end
    local cl = Workspace.Terrain:FindFirstChildOfClass("Clouds")
    if cl and o.clouds then
        for k, v in pairs(o.clouds) do pcall(function() cl[k] = v end) end
    end
    Weather.Orig = nil
end

local function makeEmitterPart(m)
    local p = Instance.new("Part")
    p.Name = "YenWeather"
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.Transparency = 1
    p.Size = Vector3.new(90, 1, 90)
    p.Parent = Workspace
    m:Give(p)
    m:Give(RunService.RenderStepped:Connect(function()
        local cam = Workspace.CurrentCamera
        if cam then p.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 45, 0)) end
    end))
    return p
end

local function applyWeather(name, intensity)
    stopWeather()
    if name == "Clear" then return end
    local p = WeatherPresets[name]
    if not p then return end
    weatherSnapshot()
    local k = math.clamp(intensity, 1, 100) / 100
    local m = fmaid("Weather")

    if p.clock then Lighting.ClockTime = p.clock end
    Lighting.Brightness = p.bright
    Lighting.Ambient = p.amb
    Lighting.OutdoorAmbient = p.out
    Lighting.FogColor = p.fog
    Lighting.FogStart = 0
    Lighting.FogEnd = p.fogEnd * (1.6 - k * 1.2)
    if p.top then Lighting.ColorShift_Top = p.top end

    if p.atm then
        local atm = Lighting:FindFirstChildOfClass("Atmosphere")
        if not atm then
            atm = Instance.new("Atmosphere")
            atm.Name = "YenAtmosphere"
            atm.Parent = Lighting
            m:Give(atm)
        end
        atm.Density = math.clamp(p.atm * (0.4 + k * 0.9), 0, 1)
        atm.Color = p.atmColor
        atm.Decay = p.atmColor
        atm.Haze = 1 + k * 2
        atm.Glare = 0
    end

    if p.cloud then
        local cl = Workspace.Terrain:FindFirstChildOfClass("Clouds")
        if not cl then
            cl = Instance.new("Clouds")
            cl.Parent = Workspace.Terrain
            m:Give(cl)
        end
        cl.Enabled = true
        cl.Cover = p.cloud
        cl.Density = 0.6 + k * 0.4
        cl.Color = p.cloudColor
    end

    if p.rain or p.snow or p.sand then
        local part = makeEmitterPart(m)
        local e = Instance.new("ParticleEmitter")
        e.LockedToPart = false
        e.EmissionDirection = Enum.NormalId.Bottom
        e.Parent = part
        if p.rain then
            e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
            e.Rate = (p.heavy and 1400 or 800) * k + 100
            e.Lifetime = NumberRange.new(0.8, 1.0)
            e.Speed = NumberRange.new(95, 115)
            e.SpreadAngle = Vector2.new(4, 4)
            e.Size = NumberSequence.new(0.18)
            e.Transparency = NumberSequence.new(0.35)
            e.Color = ColorSequence.new(Color3.fromRGB(190, 205, 225))
            e.Orientation = Enum.ParticleOrientation.VelocityParallel
            pcall(function() e.Squash = NumberSequence.new(-4) end)
            e.Acceleration = Vector3.new(-6, -40, 0)
        elseif p.snow then
            e.Texture = "rbxasset://textures/particles/smoke_main.dds"
            e.Rate = 450 * k + 40
            e.Lifetime = NumberRange.new(5, 7)
            e.Speed = NumberRange.new(6, 10)
            e.SpreadAngle = Vector2.new(25, 25)
            e.Size = NumberSequence.new(0.35)
            e.Transparency = NumberSequence.new(0.2)
            e.Color = ColorSequence.new(Color3.new(1, 1, 1))
            e.Acceleration = Vector3.new(3, -2, 1)
            e.RotSpeed = NumberRange.new(-40, 40)
        else
            e.Texture = "rbxasset://textures/particles/smoke_main.dds"
            e.Rate = 700 * k + 60
            e.Lifetime = NumberRange.new(2, 3)
            e.Speed = NumberRange.new(40, 60)
            e.SpreadAngle = Vector2.new(30, 30)
            e.Size = NumberSequence.new(3)
            e.Transparency = NumberSequence.new(0.65)
            e.Color = ColorSequence.new(Color3.fromRGB(205, 165, 105))
            e.Acceleration = Vector3.new(60, -4, 20)
        end
    end

    if p.lightning then
        local alive = true
        m:Give(function() alive = false end)
        task.spawn(function()
            while alive do
                task.wait(math.random(40, 100) / 10 / (0.5 + k))
                if not alive then break end
                local base = p.bright
                for _ = 1, math.random(1, 2) do
                    Lighting.Brightness = 6
                    task.wait(0.06)
                    Lighting.Brightness = base
                    task.wait(0.08)
                end
                Lighting.Brightness = 5
                TweenService:Create(Lighting, TweenInfo.new(0.45), { Brightness = base }):Play()
            end
        end)
    end
end

------------------------------------------------------------
-- RTX (client-side only, NOT FE)  WARNING: heavy on weak devices
------------------------------------------------------------
local RTX = { Orig = nil }
local RTX_PRESETS = {
    Low    = { bloom = 0.35, rays = 0.00, dof = false, soft = 0.30, spec = 1.0, diff = 1.0 },
    Medium = { bloom = 0.55, rays = 0.08, dof = false, soft = 0.15, spec = 1.2, diff = 1.0 },
    High   = { bloom = 0.75, rays = 0.15, dof = true,  soft = 0.05, spec = 1.5, diff = 1.0 },
}

local function rtxOff()
    fmaid("RTX"):Destroy()
    local o = RTX.Orig
    if not o then return end
    for k, v in pairs(o.light) do pcall(function() Lighting[k] = v end) end
    if o.tech ~= nil then
        pcall(function() sethiddenproperty(Lighting, "Technology", o.tech) end)
    end
    if o.mat ~= nil then pcall(function() MaterialService.Use2022Materials = o.mat end) end
    RTX.Orig = nil
end

local function rtxOn(quality)
    rtxOff()
    local q = RTX_PRESETS[quality] or RTX_PRESETS.Medium
    local m = fmaid("RTX")
    local o = { light = {} }
    for _, k in ipairs({ "ShadowSoftness", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "GlobalShadows" }) do
        local ok, v = pcall(function() return Lighting[k] end)
        if ok then o.light[k] = v end
    end
    local okT, tech = pcall(function() return gethiddenproperty(Lighting, "Technology") end)
    if okT then o.tech = tech end
    local okM, mat = pcall(function() return MaterialService.Use2022Materials end)
    if okM then o.mat = mat end
    RTX.Orig = o

    local okSet = pcall(function() sethiddenproperty(Lighting, "Technology", Enum.Technology.Future) end)
    if not okSet then
        notify("RTX", "Executor can't set Future lighting. Applying post-processing only.", 5)
    end
    pcall(function() Lighting.GlobalShadows = true end)
    pcall(function() Lighting.ShadowSoftness = q.soft end)
    pcall(function() Lighting.EnvironmentSpecularScale = q.spec end)
    pcall(function() Lighting.EnvironmentDiffuseScale = q.diff end)
    pcall(function() MaterialService.Use2022Materials = true end)

    local bloom = Instance.new("BloomEffect")
    bloom.Name = "YenRTXBloom"
    bloom.Intensity = q.bloom; bloom.Size = 24; bloom.Threshold = 0.9
    bloom.Parent = Lighting; m:Give(bloom)

    local cc = Instance.new("ColorCorrectionEffect")
    cc.Name = "YenRTXColor"
    cc.Contrast = 0.12; cc.Saturation = 0.18; cc.Brightness = 0.02
    cc.TintColor = Color3.fromRGB(255, 248, 240)
    cc.Parent = Lighting; m:Give(cc)

    if q.rays > 0 then
        local sr = Instance.new("SunRaysEffect")
        sr.Name = "YenRTXRays"
        sr.Intensity = q.rays; sr.Spread = 0.8
        sr.Parent = Lighting; m:Give(sr)
    end
    if q.dof then
        local dof = Instance.new("DepthOfFieldEffect")
        dof.Name = "YenRTXDof"
        dof.FarIntensity = 0.12; dof.NearIntensity = 0
        dof.FocusDistance = 60; dof.InFocusRadius = 45
        dof.Parent = Lighting; m:Give(dof)
    end
    notify("RTX", "Enabled (" .. quality .. "). If you lag, turn it off or lower the quality.", 5)
end

------------------------------------------------------------
-- ANTI-FREEZE WATCHDOG + UNSTICK
------------------------------------------------------------
local Watch = {}
local BadStates = {
    [Enum.HumanoidStateType.Physics]          = true,
    [Enum.HumanoidStateType.PlatformStanding] = true,
    [Enum.HumanoidStateType.Ragdoll]          = true,
    [Enum.HumanoidStateType.FallingDown]      = true,
}

local function held(key, cond, tol)
    if not cond then Watch[key] = nil; return false end
    Watch[key] = Watch[key] or os.clock()
    if os.clock() - Watch[key] > tol then Watch[key] = nil; return true end
    return false
end

local function sweepLeftoverMovers(container)
    for _, d in ipairs(container:GetDescendants()) do
        local owner = d:GetAttribute("YenOwner")
        if owner and not (State[owner] and State[owner].Enabled) then d:Destroy() end
    end
end

local function startWatchdog()
    local acc = 0
    MainMaid:Give(RunService.Heartbeat:Connect(function(dt)
        acc = acc + dt
        if acc < 0.2 then return end
        acc = 0
        if not State.Anti.Freeze then return end
        local c, h, r = getChar(), getHum(), getRoot()
        if not (c and h and r) or h.Health <= 0 then return end
        local tol = State.Anti.Tolerance

        if not State.Freeze.Enabled then
            if held("anchor", r.Anchored, tol) then r.Anchored = false end
        end

        local special = State.Fly.Enabled or State.Ragdoll.Enabled or Attach.Mode ~= nil
        if not special then
            if held("plat", h.PlatformStand, tol) then h.PlatformStand = false end
            if held("state", BadStates[h:GetState()] == true, tol + 0.5) then
                pcall(function() h:ChangeState(Enum.HumanoidStateType.Freefall) end)
            end
        end

        if not State.Speed.Enabled and held("ws", h.WalkSpeed < 1, tol + 1) then
            h.WalkSpeed = defaultWalkSpeed
        end
        if not State.Jump.Enabled then
            local low = h.UseJumpPower and h.JumpPower < 1 or ((not h.UseJumpPower) and h.JumpHeight < 0.5)
            if held("jp", low, tol + 1) then
                if h.UseJumpPower then h.JumpPower = defaultJumpPower else h.JumpHeight = defaultJumpHeight end
            end
        end

        sweepLeftoverMovers(r)
    end))
end

local function unstick()
    local c, h, r = getChar(), getHum(), getRoot()
    if not (c and h and r) then return notify("Unstick", "No character found.") end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and p.Anchored then p.Anchored = false end
    end
    sweepLeftoverMovers(c)
    h.PlatformStand = false
    h.Sit = false
    if not State.Speed.Enabled and h.WalkSpeed < 1 then h.WalkSpeed = defaultWalkSpeed end
    if not State.Jump.Enabled and h.JumpPower < 1 then h.JumpPower = defaultJumpPower end
    r.AssemblyLinearVelocity = Vector3.zero
    r.AssemblyAngularVelocity = Vector3.zero
    pcall(function() h:ChangeState(Enum.HumanoidStateType.Freefall) end)
    notify("Unstick", "Movement state reset.", 2)
end

------------------------------------------------------------
-- WINDOW
------------------------------------------------------------
local Window = WindUI:CreateWindow({
    Title  = "Yenrenuton[ALPHA]",
    Icon   = "zap",
    Author = "Yenrenuton",
    Folder = "Yenrenuton",
    Size   = getWindowSize(),
    Theme  = "Dark",
    KeySystem = {
        Key     = { "IN-ALPHA" },
        Note    = "Enter the key to continue. Alpha key: IN-ALPHA",
        SaveKey = true,
    },
})
pcall(function() Window:SetToggleKey(Enum.KeyCode.RightShift) end)
pcall(function() Window:EditOpenButton({ Title = "Yenrenuton", Icon = "zap", Draggable = true }) end)

------------------------------------------------------------
-- UNLOAD
------------------------------------------------------------
local function fullUnload()
    stopAimbot(false)
    if State.Fly.Enabled then stopFly() end
    if State.Speed.Enabled then stopSpeed() end
    if State.Jump.Enabled then stopJump() end
    if State.Fling.Enabled then stopFling() end
    if Attach.Mode then stopAttach() end
    if State.Ragdoll.Enabled then ragdollOff() end
    if State.Freeze.Enabled then stopFreeze() end
    if Invis.On then stopInvis() end
    stopWeather()
    rtxOff()
    stopXray()
    stopAnim()
    destroyPlatform()
    removeTool("TP Tool")
    removeTool("Platform")
    for _, m in pairs(Feature) do m:Destroy() end
    Noclip.Release("Fling"); Noclip.Release("Attach")
    local hum = getHum()
    if hum then hum.PlatformStand = false end
    MainMaid:Destroy()
    pcall(function() Window:Destroy() end)
    genv.__YenrenutonUnload = nil
end
genv.__YenrenutonUnload = fullUnload

------------------------------------------------------------
-- TABS
------------------------------------------------------------
local UtilityTab  = Window:Tab({ Title = "Utility",  Icon = "settings" })
local PlayerTab   = Window:Tab({ Title = "Player",   Icon = "user" })
local AvatarTab   = Window:Tab({ Title = "Avatar",   Icon = "shirt" })
local InteractTab = Window:Tab({ Title = "Interact", Icon = "users" })
local ToolsTab    = Window:Tab({ Title = "Tools",    Icon = "wrench" })
local WorldTab    = Window:Tab({ Title = "World",    Icon = "cloud" })

------------------------------------------------------------
-- UTILITY TAB
------------------------------------------------------------
UtilityTab:Section({ Title = "Settings" })
UtilityTab:Dropdown({
    Title = "Theme",
    Values = { "Dark", "Light", "Rose", "Plant", "Red", "Indigo", "Sky", "Violet", "Amber", "Emerald" },
    Value = "Dark",
    Callback = function(v) pcall(function() WindUI:SetTheme(v) end) end,
})
if Platform.Keyboard then
    UtilityTab:Keybind({
        Title = "Toggle UI Key",
        Value = "RightShift",
        Callback = function(v)
            local key = typeof(v) == "EnumItem" and v or Enum.KeyCode[v]
            if key then pcall(function() Window:SetToggleKey(key) end) end
        end,
    })
end
UtilityTab:Paragraph({
    Title = "Device",
    Desc  = Platform.Mobile and "Mobile detected. Touch controls enabled."
         or Platform.Laptop and "Laptop detected. Compact layout."
         or "PC detected.",
})

UtilityTab:Section({ Title = "Stability" })
Toggle(UtilityTab, nil, "Anti-Freeze Watchdog", State.Anti.Freeze, function(v) State.Anti.Freeze = v end)
NumBox(UtilityTab, "Freeze Tolerance (seconds)", State.Anti.Tolerance, 0.2, 5, function(v) State.Anti.Tolerance = v end)
Toggle(UtilityTab, nil, "Anti-Rubberband (auto-adapt teleport range)", State.Anti.Rubber,
    function(v) State.Anti.Rubber = v end)
UtilityTab:Button({ Title = "Unstick (force reset movement)", Callback = unstick })
UtilityTab:Button({ Title = "Unload Script (full remove)", Callback = fullUnload })

UtilityTab:Section({ Title = "Discord" })
UtilityTab:Button({
    Title = "Discord Link",
    Callback = function()
        notify("Discord", "sorry discord link is not input yet, wait for the script to be out of alpha To then. Get the link", 6)
    end,
})

UtilityTab:Section({ Title = "Credit" })
UtilityTab:Paragraph({
    Title = "Yenrenuton [ALPHA]",
    Desc  = "Script by Yenrenuton\nUI library: WindUI\nStatus: Alpha build, expect bugs.",
})

------------------------------------------------------------
-- PLAYER TAB: movement
------------------------------------------------------------
PlayerTab:Section({ Title = "Movement (Infinite Yield method)" })

Toggle(PlayerTab, "Fly", "Fly", false, function(v)
    if v == State.Fly.Enabled then return end
    State.Fly.Enabled = v
    if v then startFly() else stopFly() end
end, "W/A/S/D + Space/E up, Ctrl/Q down. Mobile: joystick + the arrow buttons.")
NumBox(PlayerTab, "Fly Speed", State.Fly.Speed, 1, 2000, function(v) State.Fly.Speed = v end)

Toggle(PlayerTab, "Speed", "Speed", false, function(v)
    if v == State.Speed.Enabled then return end
    State.Speed.Enabled = v
    if v then startSpeed() else stopSpeed() end
end)
NumBox(PlayerTab, "Walk Speed", State.Speed.Value, 0, 2000, function(v) State.Speed.Value = v end)
PlayerTab:Dropdown({ Title = "Speed Method", Values = { "WalkSpeed (Yield)", "TPWalk (Yield)" },
    Value = State.Speed.Mode,
    Callback = function(v)
        State.Speed.Mode = v
        if State.Speed.Enabled then startSpeed() end
    end })
NumBox(PlayerTab, "TPWalk Multiplier (1 = +10 studs/s)", State.Speed.TP, 0, 100, function(v) State.Speed.TP = v end)

Toggle(PlayerTab, "Jump", "Jump Power", false, function(v)
    if v == State.Jump.Enabled then return end
    State.Jump.Enabled = v
    if v then startJump() else stopJump() end
end, "Sets JumpPower, or JumpHeight if the game uses JumpHeight.")
NumBox(PlayerTab, "Jump Power", State.Jump.Power, 0, 2000, function(v) State.Jump.Power = v end)
Toggle(PlayerTab, "InfJump", "Infinite Jump", false, function(v) setInfJump(v) end)

------------------------------------------------------------
-- PLAYER TAB: visuals
------------------------------------------------------------
PlayerTab:Section({ Title = "Visuals" })
Toggle(PlayerTab, "ESP", "ESP", false, function(v)
    if v == State.ESP.Enabled then return end
    State.ESP.Enabled = v
    if v then startESP() else stopESP() end
end)
PlayerTab:Dropdown({ Title = "ESP Style", Values = { "Aura", "Box", "Both" }, Value = State.ESP.Mode,
    Callback = function(v) State.ESP.Mode = v end })
Toggle(PlayerTab, nil, "ESP: HP",       State.ESP.HP,       function(v) State.ESP.HP = v end)
Toggle(PlayerTab, nil, "ESP: Distance", State.ESP.Distance, function(v) State.ESP.Distance = v end)
Toggle(PlayerTab, nil, "ESP: Team",     State.ESP.Team,     function(v) State.ESP.Team = v end)
Toggle(PlayerTab, nil, "ESP: Hide Teammates", State.ESP.TeamCheck, function(v) State.ESP.TeamCheck = v end)
NumBox(PlayerTab, "ESP Max Distance", State.ESP.MaxDist, 50, 20000, function(v) State.ESP.MaxDist = v end)
NumBox(PlayerTab, "Aura Fill Transparency (0-100)", State.ESP.Fill, 0, 100, function(v) State.ESP.Fill = v end)

Toggle(PlayerTab, "Xray", "X-Ray", false, function(v)
    if v == State.Xray.Enabled then return end
    State.Xray.Enabled = v
    if v then startXray() else stopXray() end
end)
NumBox(PlayerTab, "X-Ray Transparency (1-100)", State.Xray.Transparency, 1, 100, function(v)
    State.Xray.Transparency = v
    if State.Xray.Enabled then
        for part, orig in pairs(XrayOriginals) do
            if part and part.Parent then part.Transparency = math.max(orig, v / 100) end
        end
    end
end)

------------------------------------------------------------
-- PLAYER TAB: combat
------------------------------------------------------------
PlayerTab:Section({ Title = "Aim-bot" })
Toggle(PlayerTab, "Aim", "Aim-bot", false, function(v)
    if v == State.Aim.Enabled then return end
    State.Aim.Enabled = v
    if v then
        startAim()
        notify("Aimbot", Platform.Mobile and "On. Tap the red button to turn it off."
            or ("On. Click the red button or press " .. State.Aim.KillKey:upper() .. " to turn it off."), 4)
    else
        stopAimbot(false)
    end
end)
PlayerTab:Dropdown({ Title = "Aim Part", Values = { "Head", "HumanoidRootPart", "UpperTorso", "Torso" },
    Value = State.Aim.Part, Callback = function(v) State.Aim.Part = v end })
NumBox(PlayerTab, "Aim FOV", State.Aim.FOV, 10, 1500, function(v) State.Aim.FOV = v end)
NumBox(PlayerTab, "Aim Smoothness (0 = instant, 100 = slow)", State.Aim.Smooth, 0, 100, function(v) State.Aim.Smooth = v end)
Toggle(PlayerTab, nil, "Aim: Team Check", State.Aim.TeamCheck, function(v) State.Aim.TeamCheck = v end)
Toggle(PlayerTab, nil, "Aim: Wall Check", State.Aim.WallCheck, function(v) State.Aim.WallCheck = v end)
if not Platform.Mobile then
    Toggle(PlayerTab, nil, "Aim: Hold Right Click", State.Aim.HoldRMB, function(v) State.Aim.HoldRMB = v end)
    PlayerTab:Input({ Title = "Aim Kill Key", Desc = "Press this key to turn the aimbot off", Value = State.Aim.KillKey,
        Placeholder = "K",
        Callback = function(txt)
            local t = tostring(txt or ""):gsub("%s", "")
            if t ~= "" and Enum.KeyCode[t:upper()] then State.Aim.KillKey = t:upper()
            else notify("Aim Kill Key", "Unknown key name.", 2) end
        end })
end
Toggle(PlayerTab, nil, "Aim: Show FOV Circle", State.Aim.ShowFOV, function(v) State.Aim.ShowFOV = v end)

PlayerTab:Section({ Title = "Aim-bot Prediction" })
Toggle(PlayerTab, nil, "Prediction (lead moving targets)", State.Aim.Predict, function(v) State.Aim.Predict = v end,
    "Aims beside the part, ahead of where they are going. Running at you = normal aim.")
NumBox(PlayerTab, "Prediction Time (seconds)", State.Aim.PredictTime, 0, 2, function(v) State.Aim.PredictTime = v end)
NumBox(PlayerTab, "Projectile Speed (0 = use time above)", State.Aim.ProjSpeed, 0, 10000, function(v) State.Aim.ProjSpeed = v end)
Toggle(PlayerTab, nil, "Predict Vertical Movement", State.Aim.PredictVertical, function(v) State.Aim.PredictVertical = v end)

------------------------------------------------------------
-- PLAYER TAB: ultra instincts
------------------------------------------------------------
PlayerTab:Section({ Title = "Ultra Instincts" })
Toggle(PlayerTab, "Ultra", "Ultra Instincts (teleport dodge)", false, function(v)
    if v == State.Ultra.Enabled then return end
    State.Ultra.Enabled = v
    if v then startUltra() else fmaid("Ultra"):Destroy() end
end)
NumBox(PlayerTab, "Reaction Delay (ms, 0 = instant)", 0, 0, 1000, function(v) State.Ultra.Delay = v / 1000 end)
NumBox(PlayerTab, "Detection Range", State.Ultra.Range, 5, 200, function(v) State.Ultra.Range = v end)
NumBox(PlayerTab, "Teleport Min Distance", State.Ultra.MinTP, 4, 80,
    function(v) State.Ultra.MinTP = v; State.Ultra.MaxTP = math.max(State.Ultra.MaxTP, v + 1) end)
NumBox(PlayerTab, "Teleport Max Distance", State.Ultra.MaxTP, 6, 120,
    function(v) State.Ultra.MaxTP = math.max(v, State.Ultra.MinTP + 1) end)
NumBox(PlayerTab, "Dodge Cooldown (ms)", math.floor(State.Ultra.Cooldown * 1000), 100, 5000,
    function(v) State.Ultra.Cooldown = v / 1000 end)
NumBox(PlayerTab, "Dash Detect Speed", State.Ultra.DashSpeed, 20, 300, function(v) State.Ultra.DashSpeed = v end)
Toggle(PlayerTab, nil, "Detect Dashes / Rushes", State.Ultra.Dash, function(v) State.Ultra.Dash = v end)
Toggle(PlayerTab, nil, "Detect Projectiles", State.Ultra.Projectiles, function(v) State.Ultra.Projectiles = v end)
Toggle(PlayerTab, nil, "Strict Animation Filter", State.Ultra.Strict, function(v) State.Ultra.Strict = v end)
Toggle(PlayerTab, nil, "Ignore Teammates", State.Ultra.TeamCheck, function(v) State.Ultra.TeamCheck = v end)
Toggle(PlayerTab, nil, "After-image Effect", State.Ultra.Ghost, function(v) State.Ultra.Ghost = v end)
PlayerTab:Input({ Title = "Dodge Animation ID (optional)", Placeholder = "e.g. 1234567890",
    Callback = function(v) State.Ultra.AnimId = v or "" end })

------------------------------------------------------------
-- AVATAR TAB
------------------------------------------------------------
AvatarTab:Section({ Title = "Rig" })
AvatarTab:Paragraph({
    Title = "R6 / R15",
    Desc  = "Uses Roblox's own avatar prompt, then respawns you. This changes your saved avatar type. "
         .. "Games that force a rig will ignore it.",
})
AvatarTab:Button({ Title = "R6 to R15", Callback = function() switchRig(Enum.HumanoidRigType.R15) end })
AvatarTab:Button({ Title = "R15 to R6", Callback = function() switchRig(Enum.HumanoidRigType.R6) end })

AvatarTab:Section({ Title = "Body" })
Toggle(AvatarTab, "Invis", "Invisible", false, function(v)
    if v then
        startInvis()
    else
        if Invis.On then stopInvis() end
        State.Invis.Enabled = false
    end
end, "Turns off Fly/Spin/Fling/Orbit/Ragdoll/Freeze/Attach when enabled. Your clone can't use tools.")
Toggle(AvatarTab, "Ragdoll", "Ragdoll", false, function(v)
    if v == State.Ragdoll.Enabled then return end
    State.Ragdoll.Enabled = v
    if v then ragdollOn() else ragdollOff() end
end)
Toggle(AvatarTab, "Freeze", "Freeze", false, function(v)
    if v == State.Freeze.Enabled then return end
    State.Freeze.Enabled = v
    if v then startFreeze() else stopFreeze() end
end, "Locks your character in place. Turn off to move again.")
Toggle(AvatarTab, nil, "Freeze: also freeze animation pose", State.Freeze.Pose, function(v)
    State.Freeze.Pose = v
    if not v and State.Freeze.Enabled then
        local h = getHum()
        local animator = h and h:FindFirstChildOfClass("Animator")
        if animator then
            for _, t in ipairs(animator:GetPlayingAnimationTracks()) do pcall(function() t:AdjustSpeed(1) end) end
        end
    end
end)

AvatarTab:Section({ Title = "Custom Animation" })
AvatarTab:Input({ Title = "Animation ID", Placeholder = "Paste animation ID here",
    Callback = function(v) State.Anim.Id = v or "" end })
NumBox(AvatarTab, "Animation Speed", State.Anim.Speed, 0.1, 10, function(v)
    State.Anim.Speed = v
    if State.Anim.Track then State.Anim.Track:AdjustSpeed(v) end
end)
Toggle(AvatarTab, nil, "Loop Animation", State.Anim.Looped, function(v)
    State.Anim.Looped = v
    if State.Anim.Track then State.Anim.Track.Looped = v end
end)
AvatarTab:Button({ Title = "Play Animation", Callback = playAnim })
AvatarTab:Button({ Title = "Stop Animation", Callback = stopAnim })

------------------------------------------------------------
-- INTERACT TAB (selected player)
------------------------------------------------------------
InteractTab:Section({ Title = "Selected Player" })
UI.Dropdowns.Target = InteractTab:Dropdown({
    Title = "Selected Player",
    Values = playerNames(),
    Callback = function(v) State.Target = v end,
})
InteractTab:Button({ Title = "Clear Selected Player", Callback = function()
    State.Target = nil
    notify("Selected Player", "Cleared.", 2)
end })

InteractTab:Section({ Title = "Attach [FE]" })
Toggle(InteractTab, "Headsit", "Headsit", false, function(v) attachToggle("Headsit", "Headsit", v) end,
    "Sit on the selected player's head.")
NumBox(InteractTab, "Headsit Height", State.Attach.HeadOffset, -3, 6, function(v) State.Attach.HeadOffset = v end)
Toggle(InteractTab, "Cape", "Cape", false, function(v) attachToggle("Cape", "Cape", v) end,
    "Your body hangs on their back like a cape and sways when they move.")
NumBox(InteractTab, "Cape Distance", State.Attach.CapeDist, 0, 6, function(v) State.Attach.CapeDist = v end)
Toggle(InteractTab, "Hang", "Hang on Back", false, function(v) attachToggle("Hang", "Hang", v) end,
    "Hug the selected player's back.")
NumBox(InteractTab, "Hang Distance", State.Attach.HangDist, 0, 6, function(v) State.Attach.HangDist = v end)

InteractTab:Section({ Title = "Orbit / Fling / Spin" })
Toggle(InteractTab, "Orbit", "Orbit Player", false, function(v)
    if v == State.Orbit.Enabled then return end
    State.Orbit.Enabled = v
    if v then
        if not State.Target then notify("Orbit", "Pick a selected player first.") end
        startOrbit()
    else stopOrbit() end
end)
NumBox(InteractTab, "Orbit Speed", State.Orbit.Speed, 0.1, 50, function(v) State.Orbit.Speed = v end)
NumBox(InteractTab, "Orbit Radius", State.Orbit.Radius, 1, 100, function(v) State.Orbit.Radius = v end)
NumBox(InteractTab, "Orbit Height", State.Orbit.Height, -50, 100, function(v) State.Orbit.Height = v end)

Toggle(InteractTab, "Fling", "Fling", false, function(v)
    if v == State.Fling.Enabled then return end
    State.Fling.Enabled = v
    if v then startFling() else stopFling() end
end)
Toggle(InteractTab, nil, "Fling: Target Everyone", State.Fling.All, function(v) State.Fling.All = v end)

Toggle(InteractTab, "Spin", "Spin", false, function(v)
    if v == State.Spin.Enabled then return end
    State.Spin.Enabled = v
    if v then startSpin() else stopSpin() end
end)
NumBox(InteractTab, "Spin Speed", State.Spin.Speed, 1, 500, function(v) State.Spin.Speed = v end)

------------------------------------------------------------
-- TOOLS TAB
------------------------------------------------------------
ToolsTab:Section({ Title = "TP Tool [FE]" })
ToolsTab:Button({ Title = "Get TP Tool", Callback = function()
    giveTPTool()
    notify("TP Tool", "Equip it, then click/tap to teleport.", 3)
end })
ToolsTab:Button({ Title = "Remove TP Tool", Callback = function()
    State.TPTool.Given = false
    removeTool("TP Tool")
end })
NumBox(ToolsTab, "TP Height Offset", State.TPTool.Height, 0, 50, function(v) State.TPTool.Height = v end)

ToolsTab:Section({ Title = "Platform Tool [Half FE]" })
ToolsTab:Paragraph({
    Title = "How it works",
    Desc  = "Click/tap with the tool to place a platform under your feet. Others can't see the platform, "
         .. "but they see you standing on air. Click again in mid-air to stack higher.",
})
ToolsTab:Button({ Title = "Get Platform Tool", Callback = function()
    givePlatformTool()
    notify("Platform", "Equip it, then click/tap to place a platform.", 3)
end })
ToolsTab:Button({ Title = "Remove Platform Tool + Platform", Callback = function()
    State.PlatTool.Given = false
    fmaid("PlatFollow"):Destroy()
    removeTool("Platform")
    destroyPlatform()
end })
NumBox(ToolsTab, "Platform Size (studs)", State.PlatTool.Size, 2, 2048, function(v)
    State.PlatTool.Size = v; applyPlatformProps()
end)
NumBox(ToolsTab, "Platform Thickness", State.PlatTool.Thick, 0.2, 50, function(v)
    State.PlatTool.Thick = v; applyPlatformProps()
end)
NumBox(ToolsTab, "Platform Transparency (0-100)", State.PlatTool.Trans * 100, 0, 100, function(v)
    State.PlatTool.Trans = v / 100; applyPlatformProps()
end)
Toggle(ToolsTab, nil, "Platform follows you (while tool is equipped)", State.PlatTool.Follow,
    function(v) State.PlatTool.Follow = v end)

------------------------------------------------------------
-- WORLD TAB (client-side only)
------------------------------------------------------------
WorldTab:Section({ Title = "Weather [Not FE]" })
WorldTab:Dropdown({
    Title = "Weather",
    Values = { "Clear", "Rain", "Thunderstorm", "Snow", "Fog", "Sandstorm", "Sunset", "Night" },
    Value = "Clear",
    Callback = function(v)
        State.Weather.Name = v
        applyWeather(v, State.Weather.Intensity)
    end,
})
NumBox(WorldTab, "Weather Intensity (1-100)", State.Weather.Intensity, 1, 100, function(v)
    State.Weather.Intensity = v
    if State.Weather.Name ~= "Clear" then applyWeather(State.Weather.Name, v) end
end)

WorldTab:Section({ Title = "RTX [Not FE]" })
WorldTab:Paragraph({
    Title = "WARNING",
    Desc  = "YOU MUST HAVE A GOOD PHONE/PC OR ELSE YOU WILL LAG. Only you see it.",
})
WorldTab:Dropdown({ Title = "RTX Quality", Values = { "Low", "Medium", "High" }, Value = State.RTX.Quality,
    Callback = function(v)
        State.RTX.Quality = v
        if State.RTX.Enabled then rtxOn(v) end
    end })
Toggle(WorldTab, "RTX", "Turn on RTX", false, function(v)
    if v == State.RTX.Enabled then return end
    State.RTX.Enabled = v
    if v then rtxOn(State.RTX.Quality) else rtxOff() end
end)

------------------------------------------------------------
-- Dropdown refresh + respawn handling
------------------------------------------------------------
local function refreshDropdowns()
    local names = playerNames()
    if UI.Dropdowns.Target then pcall(function() UI.Dropdowns.Target:Refresh(names) end) end
end
MainMaid:Give(Players.PlayerAdded:Connect(refreshDropdowns))
MainMaid:Give(Players.PlayerRemoving:Connect(function() task.defer(refreshDropdowns) end))

MainMaid:Give(LocalPlayer.CharacterAdded:Connect(function(c)
    -- swaps caused by Invisible are ours, ignore them
    if Invis.On and (c == Invis.Fake or c == Invis.Real) then return end
    if Invis.On then
        Invis.On = false
        State.Invis.Enabled = false
        fmaid("Invis"):Destroy()
        if Invis.Fake then pcall(function() Invis.Fake:Destroy() end) end
        Invis.Real, Invis.Fake = nil, nil
        setToggle("Invis", false)
    end
    task.wait(0.6)
    State.Ultra.Adapt = 1
    local h = getHum()
    if h then
        if h.WalkSpeed >= 1 then defaultWalkSpeed = h.WalkSpeed end
        if h.JumpPower >= 1 then defaultJumpPower = h.JumpPower end
        if h.JumpHeight >= 0.5 then defaultJumpHeight = h.JumpHeight end
    end
    if State.Fly.Enabled     then startFly()     end
    if State.Speed.Enabled   then startSpeed()   end
    if State.Jump.Enabled    then startJump()    end
    if State.Jump.Inf        then setInfJump(true) end
    if State.Orbit.Enabled   then startOrbit()   end
    if State.Fling.Enabled   then startFling()   end
    if State.Spin.Enabled    then startSpin()    end
    if State.Ragdoll.Enabled then ragdollOn()    end
    if State.Freeze.Enabled  then startFreeze()  end
    if Attach.Mode           then startAttach(Attach.Mode) end
    if State.TPTool.Given    then giveTPTool()   end
    if State.PlatTool.Given  then givePlatformTool() end
end))

------------------------------------------------------------
-- Launch
------------------------------------------------------------
startWatchdog()
notify("Yenrenuton [ALPHA]",
    Platform.Mobile and "Loaded. Close the menu and use the open button to bring it back."
    or "Loaded. RightShift toggles the UI, or use the open button after closing.", 5)
