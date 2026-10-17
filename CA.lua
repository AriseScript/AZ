local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

-- ==========================================
-- CONFIG BOOTSTRAP
-- ==========================================
local ConfigPath = "Arise_Config.json"
local ConfigFileAvailable = type(readfile) == "function"
    and type(writefile) == "function"
local ConfigData = type(getgenv().AriseConfigData) == "table"
    and getgenv().AriseConfigData or {}
local ConfigAutoSave = ConfigData._autoSave == true
local saveConfig -- Forward declaration used by toggle/slider callbacks.

if ConfigFileAvailable then
    pcall(function()
        local decoded = HttpService:JSONDecode(readfile(ConfigPath))
        if type(decoded) == "table" then
            ConfigData = decoded
            ConfigAutoSave = ConfigData._autoSave == true
        end
    end)
end

getgenv().AriseConfigData = ConfigData

-- Apply persisted values before the UI controls are created.
for key, value in pairs(ConfigData) do
    if key ~= "_autoSave" then
        getgenv()[key] = value
    end
end

-- ==========================================
-- HARD CLEANUP (PREVENTS DUPLICATE UIS & LAG)
-- ==========================================
local function destroyOldGuis(parent)
    if not parent then return end
    for _, gui in pairs(parent:GetChildren()) do
        if gui:IsA("ScreenGui") and (gui.Name == "Arise" or gui.Name == "AriseUI") then
            gui:Destroy()
        end
    end
end

pcall(function() destroyOldGuis(CoreGui) end)
pcall(function() destroyOldGuis(LocalPlayer:FindFirstChild("PlayerGui")) end)

if getgenv().AriseUI then pcall(function() getgenv().AriseUI:Destroy() end) end

-- Kill previous Arise automation worker if this script is being reloaded.
if getgenv().AriseAutomationThread then
    pcall(task.cancel, getgenv().AriseAutomationThread)
    getgenv().AriseAutomationThread = nil
end

-- Kill all previous background loops
if getgenv().AutoLiftThread then pcall(task.cancel, getgenv().AutoLiftThread); getgenv().AutoLiftThread = nil end
if getgenv().AutoDungeonThread then pcall(task.cancel, getgenv().AutoDungeonThread); getgenv().AutoDungeonThread = nil end
if getgenv().FarmMovementThread then pcall(task.cancel, getgenv().FarmMovementThread); getgenv().FarmMovementThread = nil end
if getgenv().FarmCombatThread then pcall(task.cancel, getgenv().FarmCombatThread); getgenv().FarmCombatThread = nil end
if getgenv().StatsThread then getgenv().StatsThread:Disconnect(); getgenv().StatsThread = nil end
if getgenv().UpgradeDetectorThread then pcall(task.cancel, getgenv().UpgradeDetectorThread); getgenv().UpgradeDetectorThread = nil end
if getgenv().AutoUpgradeThread then pcall(task.cancel, getgenv().AutoUpgradeThread); getgenv().AutoUpgradeThread = nil end
getgenv().AutoUpgradeEnabled = false
pcall(function()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if playerGui then
        for _, obj in ipairs(playerGui:GetDescendants()) do
            local stroke = obj:FindFirstChild("AriseUpgradeDetectorStroke")
            if stroke then stroke:Destroy() end
        end
    end
end)

-- ==========================================
-- INITIALIZE THEME & UI
-- ==========================================
local Theme = {
    Background = Color3.fromRGB(20, 20, 25), Sidebar = Color3.fromRGB(15, 15, 20),
    Element = Color3.fromRGB(30, 30, 38), Hover = Color3.fromRGB(40, 40, 50),
    Accent = Color3.fromRGB(0, 200, 255), AccentDark = Color3.fromRGB(150, 50, 255),
    Text = Color3.fromRGB(240, 240, 240), TextDim = Color3.fromRGB(180, 180, 180),
    ToggleOff = Color3.fromRGB(50, 50, 60), ToggleOn = Color3.fromRGB(0, 200, 255)
}

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "Arise"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Keep Arise above normal game ScreenGuis.
-- Roblox system dialogs/core overlays may still appear above it.
local ARISE_DISPLAY_ORDER = 999999
ScreenGui.DisplayOrder = ARISE_DISPLAY_ORDER
ScreenGui.Enabled = true
getgenv().AriseUI = ScreenGui

local success = pcall(function()
    ScreenGui.Parent = CoreGui
end)
if not success or not ScreenGui.Parent then
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

-- Start the keep-on-top guard only after the ScreenGui has a parent.
task.spawn(function()
    while ScreenGui and ScreenGui.Parent do
        pcall(function()
            ScreenGui.DisplayOrder = ARISE_DISPLAY_ORDER
            ScreenGui.Enabled = true
        end)
        task.wait(1)
    end
end)

-- ==========================================
-- 1. MAIN UI CONTAINER
-- ==========================================
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 0, 0, 0)
MainFrame.Position = UDim2.new(0.5, -300, 0.5, -200)
MainFrame.BackgroundColor3 = Theme.Background
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Visible = false
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Theme.Accent
MainStroke.Thickness = 1
MainStroke.Transparency = 0.5
MainStroke.Parent = MainFrame
local StrokeGradient = Instance.new("UIGradient")
StrokeGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Theme.Accent),
    ColorSequenceKeypoint.new(0.5, Theme.AccentDark),
    ColorSequenceKeypoint.new(1, Theme.Accent)
})
StrokeGradient.Parent = MainStroke

task.spawn(function()
    local rot = 0
    while task.wait(0.02) do
        rot = (rot + 1) % 360
        if StrokeGradient and StrokeGradient.Parent then
            StrokeGradient.Rotation = rot
        else
            break
        end
    end
end)

-- ==========================================
-- 2. LOADER
-- ==========================================
local LoaderFrame = Instance.new("Frame")
LoaderFrame.Size = UDim2.new(0, 380, 0, 200)
LoaderFrame.Position = UDim2.new(0.5, -190, 0.5, -100)
LoaderFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
LoaderFrame.BorderSizePixel = 0
LoaderFrame.ClipsDescendants = true
LoaderFrame.Parent = ScreenGui
Instance.new("UICorner", LoaderFrame).CornerRadius = UDim.new(0, 12)

local LoaderHeader = Instance.new("Frame", LoaderFrame)
LoaderHeader.Size = UDim2.new(1, 0, 0, 70)
LoaderHeader.BackgroundTransparency = 1

local LoaderLogo = Instance.new("ImageLabel", LoaderHeader)
LoaderLogo.Size = UDim2.new(0, 36, 0, 36)
LoaderLogo.Position = UDim2.new(0, 25, 0, 20)
LoaderLogo.BackgroundTransparency = 1
LoaderLogo.Image = "rbxassetid://75491350326979"
LoaderLogo.ScaleType = Enum.ScaleType.Fit

local LoaderTitle = Instance.new("TextLabel", LoaderHeader)
LoaderTitle.Size = UDim2.new(0, 200, 0, 20)
LoaderTitle.Position = UDim2.new(0, 75, 0, 20)
LoaderTitle.BackgroundTransparency = 1
LoaderTitle.Text = "Arise Scripts"
LoaderTitle.TextColor3 = Color3.new(1, 1, 1)
LoaderTitle.Font = Enum.Font.GothamBold
LoaderTitle.TextSize = 16
LoaderTitle.TextXAlignment = Enum.TextXAlignment.Left

local LoaderVersion = Instance.new("TextLabel", LoaderHeader)
LoaderVersion.Size = UDim2.new(0, 200, 0, 15)
LoaderVersion.Position = UDim2.new(0, 75, 0, 42)
LoaderVersion.BackgroundTransparency = 1
LoaderVersion.Text = "v1.0.0"
LoaderVersion.TextColor3 = Color3.fromRGB(120, 120, 125)
LoaderVersion.Font = Enum.Font.Gotham
LoaderVersion.TextSize = 12
LoaderVersion.TextXAlignment = Enum.TextXAlignment.Left

local LoaderPercent = Instance.new("TextLabel", LoaderHeader)
LoaderPercent.Size = UDim2.new(0, 50, 0, 20)
LoaderPercent.Position = UDim2.new(1, -75, 0, 20)
LoaderPercent.BackgroundTransparency = 1
LoaderPercent.Text = "0%"
LoaderPercent.TextColor3 = Color3.fromRGB(120, 120, 125)
LoaderPercent.Font = Enum.Font.GothamMedium
LoaderPercent.TextSize = 12
LoaderPercent.TextXAlignment = Enum.TextXAlignment.Right

local LoaderDivider = Instance.new("Frame", LoaderFrame)
LoaderDivider.Size = UDim2.new(1, -50, 0, 1)
LoaderDivider.Position = UDim2.new(0, 25, 0, 75)
LoaderDivider.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
LoaderDivider.BorderSizePixel = 0

local TaskContainer = Instance.new("Frame", LoaderFrame)
TaskContainer.Size = UDim2.new(1, -50, 0, 100)
TaskContainer.Position = UDim2.new(0, 25, 0, 85)
TaskContainer.BackgroundTransparency = 1

local TaskListLayout = Instance.new("UIListLayout", TaskContainer)
TaskListLayout.Padding = UDim.new(0, 12)

local BottomBarBg = Instance.new("Frame", LoaderFrame)
BottomBarBg.Size = UDim2.new(1, 0, 0, 3)
BottomBarBg.Position = UDim2.new(0, 0, 1, -3)
BottomBarBg.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
BottomBarBg.BorderSizePixel = 0

local BottomBarFill = Instance.new("Frame", BottomBarBg)
BottomBarFill.Size = UDim2.new(0, 0, 1, 0)
BottomBarFill.BackgroundColor3 = Color3.fromRGB(255, 100, 150)
BottomBarFill.BorderSizePixel = 0

local activeSpinner = nil
local function createTaskRow(text)
    local row = Instance.new("Frame", TaskContainer)
    row.Size = UDim2.new(1, 0, 0, 20)
    row.BackgroundTransparency = 1

    local icon = Instance.new("ImageLabel", row)
    icon.Size = UDim2.new(0, 14, 0, 14)
    icon.Position = UDim2.new(0, 0, 0.5, -7)
    icon.BackgroundTransparency = 1
    icon.Image = "rbxassetid://14060867824"
    icon.ImageColor3 = Color3.fromRGB(255, 100, 150)

    local label = Instance.new("TextLabel", row)
    label.Size = UDim2.new(1, -30, 1, 0)
    label.Position = UDim2.new(0, 25, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.new(1, 1, 1)
    label.Font = Enum.Font.Gotham
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left

    local spinTween = TweenService:Create(icon, TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {Rotation = 360})
    spinTween:Play()
    activeSpinner = spinTween

    return row, icon, label
end

local function completeTask(icon, label)
    if activeSpinner then activeSpinner:Cancel() end
    icon.Rotation = 0
    icon.Image = "rbxassetid://6031094678"
    icon.ImageColor3 = Color3.fromRGB(150, 150, 150)
    label.TextColor3 = Color3.fromRGB(150, 150, 150)
end

task.spawn(function()
    local tasks = {"Preparing interface", "Loading modules", "Ready"}
    local rows = {}

    for i, taskName in ipairs(tasks) do
        local row, icon, label = createTaskRow(taskName)
        table.insert(rows, {icon = icon, label = label})

        local targetPercent = math.floor((i / #tasks) * 100)
        task.wait(math.random(2, 5) / 10)

        TweenService:Create(BottomBarFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {Size = UDim2.new(targetPercent / 100, 0, 1, 0)}):Play()
        LoaderPercent.Text = tostring(targetPercent) .. "%"

        if i < #tasks then
            completeTask(icon, label)
        end
    end

    task.wait(0.3)
    completeTask(rows[3].icon, rows[3].label)

    local fadeTime = 0.4
    for _, obj in ipairs(LoaderFrame:GetDescendants()) do
        if obj:IsA("TextLabel") then
            TweenService:Create(obj, TweenInfo.new(fadeTime), {TextTransparency = 1}):Play()
        elseif obj:IsA("ImageLabel") then
            TweenService:Create(obj, TweenInfo.new(fadeTime), {ImageTransparency = 1}):Play()
        elseif obj:IsA("Frame") then
            TweenService:Create(obj, TweenInfo.new(fadeTime), {BackgroundTransparency = 1}):Play()
        end
    end
    TweenService:Create(LoaderFrame, TweenInfo.new(fadeTime), {BackgroundTransparency = 1}):Play()

    task.wait(fadeTime)
    LoaderFrame:Destroy()

    MainFrame.Visible = true
    TweenService:Create(MainFrame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = getgenv().CurrentWindowSize or UDim2.new(0, 600, 0, 400)}):Play()
end)

-- ==========================================
-- 3. WINDOW DRAGGING & RESIZING
-- ==========================================
local dragging, dragInput2, dragStart2, startPos2
MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart2 = input.Position
        startPos2 = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)

MainFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput2 = input end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput2 and dragging then
        local delta = input.Position - dragStart2
        TweenService:Create(MainFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.new(startPos2.X.Scale, startPos2.X.Offset + delta.X, startPos2.Y.Scale, startPos2.Y.Offset + delta.Y)}):Play()
    end
end)

getgenv().CurrentWindowSize = UDim2.new(0, 600, 0, 400)
local ResizeHandle = Instance.new("TextButton")
ResizeHandle.Name = "ResizeHandle"
ResizeHandle.Size = UDim2.new(0, 20, 0, 20)
ResizeHandle.Position = UDim2.new(1, -20, 1, -20)
ResizeHandle.BackgroundTransparency = 1
ResizeHandle.Text = "◢"
ResizeHandle.TextColor3 = Theme.TextDim
ResizeHandle.TextSize = 16
ResizeHandle.ZIndex = 50
ResizeHandle.Parent = MainFrame

local resizing = false
local resizeDragStart, resizeStartSize

ResizeHandle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        resizing = true
        resizeDragStart = input.Position
        resizeStartSize = MainFrame.AbsoluteSize

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                resizing = false
                getgenv().CurrentWindowSize = MainFrame.Size
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - resizeDragStart
        local newWidth = math.clamp(resizeStartSize.X + delta.X, 450, 1200)
        local newHeight = math.clamp(resizeStartSize.Y + delta.Y, 300, 800)
        MainFrame.Size = UDim2.new(0, newWidth, 0, newHeight)
    end
end)

-- ==========================================
-- 4. SIDEBAR & MINIMIZE BUTTONS
-- ==========================================
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 160, 1, 0)
Sidebar.BackgroundColor3 = Theme.Sidebar
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame

local TitleContainer = Instance.new("Frame")
TitleContainer.Size = UDim2.new(1, 0, 0, 50)
TitleContainer.Position = UDim2.new(0, 0, 0, 0)
TitleContainer.BackgroundTransparency = 1
TitleContainer.Parent = Sidebar

local TitleIcon = Instance.new("ImageLabel")
TitleIcon.Size = UDim2.new(0, 22, 0, 22)
TitleIcon.Position = UDim2.new(0, 15, 0.5, -11)
TitleIcon.BackgroundTransparency = 1
TitleIcon.Image = "rbxassetid://75491350326979"
TitleIcon.ScaleType = Enum.ScaleType.Fit
TitleIcon.Parent = TitleContainer

local STitle = Instance.new("TextLabel")
STitle.Size = UDim2.new(1, -45, 1, 0)
STitle.Position = UDim2.new(0, 42, 0, 0)
STitle.BackgroundTransparency = 1
STitle.Text = "ARISE SCRIPTS"
STitle.TextColor3 = Theme.Text
STitle.Font = Enum.Font.GothamBlack
STitle.TextSize = 14
STitle.TextXAlignment = Enum.TextXAlignment.Left
STitle.Parent = TitleContainer

Instance.new("UIGradient", STitle).Color = StrokeGradient.Color
local IconGradient = Instance.new("UIGradient", TitleIcon)
IconGradient.Color = StrokeGradient.Color

local TabContainer = Instance.new("ScrollingFrame")
TabContainer.Size = UDim2.new(1, 0, 1, -110)
TabContainer.Position = UDim2.new(0, 0, 0, 50)
TabContainer.BackgroundTransparency = 1
TabContainer.ScrollBarThickness = 0
TabContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
TabContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
TabContainer.Parent = Sidebar

local TabListLayout = Instance.new("UIListLayout")
TabListLayout.Padding = UDim.new(0, 5)
TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
TabListLayout.Parent = TabContainer

local ContentArea = Instance.new("Frame")
ContentArea.Size = UDim2.new(1, -160, 1, 0)
ContentArea.Position = UDim2.new(0, 160, 0, 0)
ContentArea.BackgroundTransparency = 1
ContentArea.Parent = MainFrame

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -35, 0, 10)
CloseBtn.BackgroundColor3 = Theme.Element
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Theme.TextDim
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 12
CloseBtn.Parent = ContentArea
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Size = UDim2.new(0, 30, 0, 30)
MinimizeBtn.Position = UDim2.new(1, -70, 0, 10)
MinimizeBtn.BackgroundColor3 = Theme.Element
MinimizeBtn.Text = "-"
MinimizeBtn.TextColor3 = Theme.TextDim
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.TextSize = 16
MinimizeBtn.Parent = ContentArea
Instance.new("UICorner", MinimizeBtn).CornerRadius = UDim.new(0, 6)

local OpenLogo = Instance.new("ImageButton")
OpenLogo.Name = "AriseOpenLogo"
OpenLogo.Size = UDim2.new(0, 50, 0, 50)
OpenLogo.Position = UDim2.new(0.5, -25, 0, 20)
OpenLogo.BackgroundColor3 = Theme.Background
OpenLogo.Image = "rbxassetid://75491350326979"
OpenLogo.ScaleType = Enum.ScaleType.Fit
OpenLogo.Visible = false
OpenLogo.Parent = ScreenGui
Instance.new("UICorner", OpenLogo).CornerRadius = UDim.new(1, 0)

local isAnimating = false
MinimizeBtn.MouseButton1Click:Connect(function()
    if isAnimating then return end
    isAnimating = true
    local shrink = TweenService:Create(MainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Size = UDim2.new(0, 0, 0, 0)})
    shrink:Play()
    task.delay(0.2, function()
        MainFrame.Visible = false
        OpenLogo.Visible = true
        OpenLogo.Size = UDim2.new(0, 0, 0, 0)
        TweenService:Create(OpenLogo, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 50, 0, 50)}):Play()
        isAnimating = false
    end)
end)

OpenLogo.MouseButton1Click:Connect(function()
    if isAnimating then return end
    isAnimating = true
    local shrinkLogo = TweenService:Create(OpenLogo, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Size = UDim2.new(0, 0, 0, 0)})
    shrinkLogo:Play()
    task.delay(0.2, function()
        OpenLogo.Visible = false
        MainFrame.Visible = true
        TweenService:Create(MainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = getgenv().CurrentWindowSize or UDim2.new(0, 600, 0, 400)}):Play()
        isAnimating = false
    end)
end)

-- ==========================================
-- 5. NOTIFICATION SYSTEM
-- ==========================================
local NotificationHolder = Instance.new("Frame")
NotificationHolder.Size = UDim2.new(0, 320, 1, -30)
NotificationHolder.Position = UDim2.new(1, -330, 0, 10)
NotificationHolder.BackgroundTransparency = 1
NotificationHolder.Parent = ScreenGui

local function sendNotification(title, text, duration, color)
    local notif = Instance.new("Frame")
    notif.Size = UDim2.new(0, 300, 0, 60)
    notif.Position = UDim2.new(0, 320, 0, 0)
    notif.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
    notif.BorderSizePixel = 0
    notif.ClipsDescendants = true
    notif.Parent = NotificationHolder
    Instance.new("UICorner", notif).CornerRadius = UDim.new(0, 14)

    local NotifStroke = Instance.new("UIStroke")
    NotifStroke.Color = color or Theme.Accent
    NotifStroke.Thickness = 1
    NotifStroke.Transparency = 0.5
    NotifStroke.Parent = notif

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -20, 0, 20)
    titleLabel.Position = UDim2.new(0, 15, 0, 10)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.TextColor3 = Color3.new(1, 1, 1)
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 14
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = notif

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, -20, 0, 20)
    textLabel.Position = UDim2.new(0, 15, 0, 30)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = text
    textLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    textLabel.Font = Enum.Font.Gotham
    textLabel.TextSize = 12
    textLabel.TextXAlignment = Enum.TextXAlignment.Left
    textLabel.Parent = notif

    TweenService:Create(notif, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position = UDim2.new(0, 0, 0, 0)}):Play()
    task.delay(duration or 3, function()
        if notif and notif.Parent then
            local removeTween = TweenService:Create(notif, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {Position = UDim2.new(0, 320, 0, 0)})
            removeTween:Play()
            removeTween.Completed:Connect(function() notif:Destroy() end)
        end
    end)
end

-- ==========================================
-- 6. BUILDER FUNCTIONS
-- ==========================================
local Tabs = {}
local function CreateTab(name, isDefault)
    local TabBtn = Instance.new("TextButton")
    TabBtn.Size = UDim2.new(0, 140, 0, 35)
    TabBtn.BackgroundTransparency = 1
    TabBtn.Text = name
    TabBtn.TextColor3 = isDefault and Theme.Accent or Theme.TextDim
    TabBtn.Font = Enum.Font.GothamBold
    TabBtn.TextSize = 13
    TabBtn.Parent = TabContainer

    local Indicator = Instance.new("Frame")
    Indicator.Size = UDim2.new(0, 3, 0, isDefault and 20 or 0)
    Indicator.Position = UDim2.new(0, 0, 0.5, isDefault and -10 or 0)
    Indicator.BackgroundColor3 = Theme.Accent
    Indicator.BorderSizePixel = 0
    Indicator.Parent = TabBtn
    Instance.new("UICorner", Indicator).CornerRadius = UDim.new(1, 0)

    local Page = Instance.new("ScrollingFrame")
    Page.Size = UDim2.new(1, -20, 1, -50)
    Page.Position = UDim2.new(0, 10, 0, 40)
    Page.BackgroundTransparency = 1
    Page.ScrollBarThickness = 2
    Page.ScrollBarImageColor3 = Theme.Accent
    Page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Page.CanvasSize = UDim2.new(0, 0, 0, 0)
    Page.Visible = isDefault
    Page.Parent = ContentArea

    local PageLayout = Instance.new("UIListLayout")
    PageLayout.Padding = UDim.new(0, 8)
    PageLayout.SortOrder = Enum.SortOrder.LayoutOrder
    PageLayout.Parent = Page

    Tabs[name] = {Button = TabBtn, Page = Page, Indicator = Indicator}
    TabBtn.MouseButton1Click:Connect(function()
        for tName, data in pairs(Tabs) do
            data.Page.Visible = (tName == name)
            TweenService:Create(data.Button, TweenInfo.new(0.3), {TextColor3 = (tName == name) and Theme.Accent or Theme.TextDim}):Play()
            TweenService:Create(data.Indicator, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 3, 0, (tName == name) and 20 or 0), Position = UDim2.new(0, 0, 0.5, (tName == name) and -10 or 0)}):Play()
        end
    end)
    return Page
end

local function CreateSection(parent, text)
    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -10, 0, 25)
    Label.BackgroundTransparency = 1
    Label.Text = "  " .. text
    Label.TextColor3 = Theme.Accent
    Label.Font = Enum.Font.GothamBold
    Label.TextSize = 14
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = parent
end

local function CreateToggle(parent, text, state, callback)
    local ToggleFrame = Instance.new("Frame")
    ToggleFrame.Size = UDim2.new(1, -10, 0, 45)
    ToggleFrame.BackgroundColor3 = Theme.Element
    ToggleFrame.Parent = parent
    Instance.new("UICorner", ToggleFrame).CornerRadius = UDim.new(0, 8)

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -70, 1, 0)
    Label.Position = UDim2.new(0, 15, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = text
    Label.TextColor3 = Theme.Text
    Label.Font = Enum.Font.GothamMedium
    Label.TextSize = 14
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = ToggleFrame

    local Pill = Instance.new("TextButton")
    Pill.Size = UDim2.new(0, 44, 0, 22)
    Pill.Position = UDim2.new(1, -55, 0.5, -11)
    Pill.BackgroundColor3 = state and Theme.ToggleOn or Theme.ToggleOff
    Pill.Text = ""
    Pill.AutoButtonColor = false
    Pill.Parent = ToggleFrame
    Instance.new("UICorner", Pill).CornerRadius = UDim.new(1, 0)

    local Circle = Instance.new("Frame")
    Circle.Size = UDim2.new(0, 18, 0, 18)
    Circle.Position = UDim2.new(0, state and 24 or 2, 0.5, -9)
    Circle.BackgroundColor3 = Color3.new(1, 1, 1)
    Circle.Parent = Pill
    Instance.new("UICorner", Circle).CornerRadius = UDim.new(1, 0)

    local isToggled = state
    Pill.MouseButton1Click:Connect(function()
        isToggled = not isToggled
        TweenService:Create(Pill, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = isToggled and Theme.ToggleOn or Theme.ToggleOff}):Play()
        TweenService:Create(Circle, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position = UDim2.new(0, isToggled and 24 or 2, 0.5, -9)}):Play()
        callback(isToggled)
        if ConfigAutoSave and saveConfig then
            saveConfig(true)
        end
    end)
end

local function CreateSlider(parent, text, min, max, default, callback)
    local SliderFrame = Instance.new("Frame", parent)
    SliderFrame.Size = UDim2.new(1, -10, 0, 55)
    SliderFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    Instance.new("UICorner", SliderFrame).CornerRadius = UDim.new(0, 8)

    local Label = Instance.new("TextLabel", SliderFrame)
    Label.Size = UDim2.new(1, -30, 0, 20)
    Label.Position = UDim2.new(0, 15, 0, 5)
    Label.BackgroundTransparency = 1
    Label.Text = text .. ": " .. default
    Label.TextColor3 = Color3.fromRGB(240, 240, 240)
    Label.Font = Enum.Font.GothamMedium
    Label.TextSize = 14
    Label.TextXAlignment = Enum.TextXAlignment.Left

    local Track = Instance.new("Frame", SliderFrame)
    Track.Size = UDim2.new(1, -30, 0, 6)
    Track.Position = UDim2.new(0, 15, 0, 35)
    Track.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    Instance.new("UICorner", Track).CornerRadius = UDim.new(1, 0)

    local Fill = Instance.new("Frame", Track)
    Fill.Size = UDim2.new(math.clamp((default - min) / (max - min), 0, 1), 0, 1, 0)
    Fill.BackgroundColor3 = Theme.Accent
    Instance.new("UICorner", Fill).CornerRadius = UDim.new(1, 0)

    local Btn = Instance.new("TextButton", Track)
    Btn.Size = UDim2.new(1, 0, 1, 0)
    Btn.BackgroundTransparency = 1
    Btn.Text = ""

    local isDragging = false
    local function update(input)
        if Track.AbsoluteSize.X <= 0 then return end
        local pos = math.clamp((input.Position.X - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
        Fill.Size = UDim2.new(pos, 0, 1, 0)
        local val = min + ((max - min) * pos)

        if (max - min) <= 10 then
            val = math.floor(val * 10) / 10
        else
            val = math.floor(val)
        end

        Label.Text = text .. ": " .. tostring(val)
        callback(val)
        if ConfigAutoSave and saveConfig then
            saveConfig(true)
        end
    end

    Btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = true
            update(input)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            update(input)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = false
        end
    end)
end

-- ==========================================
-- TREE TYPE NORMALIZATION + DROPDOWN
-- Tree names such as OakTree, Oak Tree 01, and oak_tree are grouped as "oak".
-- Explicit attributes/StringValues are also supported when a game provides them.
-- ==========================================
local function normalizeTreeCategory(rawName)
    local value = string.lower(tostring(rawName or ""))
    value = value:gsub("[%d]", " ")
    value = value:gsub("[_%-%./]+", " ")
    value = value:gsub("trees", " ")
    value = value:gsub("tree", " ")
    value = value:gsub("model", " ")
    value = value:gsub("%s+", " ")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

local function titleCaseTreeCategory(value)
    if value == "All Trees" then return value end
    return (tostring(value):gsub("(%a)([%w']*)", function(first, rest)
        return string.upper(first) .. rest
    end))
end

local function getTreeCategory(tree)
    if not tree then return "" end

    local attributes = {"TreeType", "TreeTypeName", "Species", "Zone", "Type"}
    for _, attributeName in ipairs(attributes) do
        local attributeValue = tree:GetAttribute(attributeName)
        if type(attributeValue) == "string" and attributeValue ~= "" then
            local category = normalizeTreeCategory(attributeValue)
            if category ~= "" then return category end
        end
    end

    for _, child in ipairs(tree:GetChildren()) do
        local childName = string.lower(child.Name)
        if child:IsA("StringValue")
            and (childName == "treetype" or childName == "treetypename"
                or childName == "species" or childName == "zone" or childName == "type") then
            local category = normalizeTreeCategory(child.Value)
            if category ~= "" then return category end
        end
    end

    return normalizeTreeCategory(tree.Name)
end

local function getTreeFolder()
    local map = workspace:FindFirstChild("Map")
    return map and map:FindFirstChild("Trees")
end

-- Only these nine tree species are exposed in the selector and farm filter.
-- The names are normalized to lowercase for matching tree model names/attributes.
local SUPPORTED_TREE_TYPES = {
    {label = "Oak", value = "oak"},
    {label = "Birch", value = "birch"},
    {label = "Pine", value = "pine"},
    {label = "Aspen", value = "aspen"},
    {label = "Cherry", value = "cherry"},
    {label = "Copperbeech", value = "copperbeech"},
    {label = "Spruce", value = "spruce"},
    {label = "Fir", value = "fir"},
    {label = "Cypress", value = "cypress"},
}

local SUPPORTED_TREE_TYPE_SET = {}
for _, item in ipairs(SUPPORTED_TREE_TYPES) do
    SUPPORTED_TREE_TYPE_SET[item.value] = true
end

local function getAvailableTreeTypeOptions()
    -- Keep the menu limited to the user's exact species list. The "All Trees"
    -- choice means all nine supported species, not unknown/unlisted models.
    local options = {{label = "All Trees", value = "All Trees"}}
    for _, item in ipairs(SUPPORTED_TREE_TYPES) do
        table.insert(options, {label = item.label, value = item.value})
    end
    return options
end

getgenv().SelectedTreeType = getgenv().SelectedTreeType or "All Trees"
if string.lower(tostring(getgenv().SelectedTreeType)) ~= "all trees" then
    local savedType = normalizeTreeCategory(getgenv().SelectedTreeType)
    if SUPPORTED_TREE_TYPE_SET[savedType] then
        getgenv().SelectedTreeType = savedType
    else
        getgenv().SelectedTreeType = "All Trees"
    end
else
    getgenv().SelectedTreeType = "All Trees"
end

local function CreateTreeTypeDropdown(parent, labelText, optionsProvider, defaultValue, callback)
    local selectedValue = defaultValue or "All Trees"

    local DropdownFrame = Instance.new("Frame")
    DropdownFrame.Name = "TreeTypeDropdown"
    DropdownFrame.Size = UDim2.new(1, -10, 0, 45)
    DropdownFrame.BackgroundColor3 = Theme.Element
    DropdownFrame.BorderSizePixel = 0
    DropdownFrame.ClipsDescendants = true
    DropdownFrame.Parent = parent
    Instance.new("UICorner", DropdownFrame).CornerRadius = UDim.new(0, 8)

    local MainButton = Instance.new("TextButton")
    MainButton.Size = UDim2.new(1, -16, 0, 35)
    MainButton.Position = UDim2.new(0, 8, 0, 5)
    MainButton.BackgroundColor3 = Theme.Hover
    MainButton.BorderSizePixel = 0
    MainButton.AutoButtonColor = true
    MainButton.TextColor3 = Theme.Text
    MainButton.Font = Enum.Font.GothamMedium
    MainButton.TextSize = 13
    MainButton.TextXAlignment = Enum.TextXAlignment.Left
    MainButton.Text = "  " .. labelText .. ": " .. titleCaseTreeCategory(selectedValue) .. "   ▼"
    MainButton.Parent = DropdownFrame
    Instance.new("UICorner", MainButton).CornerRadius = UDim.new(0, 6)

    local OptionsFrame = Instance.new("ScrollingFrame")
    OptionsFrame.Name = "Options"
    OptionsFrame.Position = UDim2.new(0, 8, 0, 43)
    OptionsFrame.Size = UDim2.new(1, -16, 0, 0)
    OptionsFrame.BackgroundColor3 = Theme.Background
    OptionsFrame.BorderSizePixel = 0
    OptionsFrame.ScrollBarThickness = 3
    OptionsFrame.ScrollBarImageColor3 = Theme.Accent
    OptionsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    OptionsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    OptionsFrame.Visible = false
    OptionsFrame.Parent = DropdownFrame
    Instance.new("UICorner", OptionsFrame).CornerRadius = UDim.new(0, 6)

    local OptionsLayout = Instance.new("UIListLayout")
    OptionsLayout.Padding = UDim.new(0, 3)
    OptionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    OptionsLayout.Parent = OptionsFrame

    local OptionsPadding = Instance.new("UIPadding")
    OptionsPadding.PaddingTop = UDim.new(0, 4)
    OptionsPadding.PaddingBottom = UDim.new(0, 4)
    OptionsPadding.PaddingLeft = UDim.new(0, 4)
    OptionsPadding.PaddingRight = UDim.new(0, 4)
    OptionsPadding.Parent = OptionsFrame

    local isOpen = false
    local function closeDropdown()
        isOpen = false
        OptionsFrame.Visible = false
        DropdownFrame.Size = UDim2.new(1, -10, 0, 45)
        MainButton.Text = "  " .. labelText .. ": " .. titleCaseTreeCategory(selectedValue) .. "   ▼"
    end

    MainButton.MouseButton1Click:Connect(function()
        if isOpen then
            closeDropdown()
            return
        end

        -- Refresh the options on every open so newly spawned tree types appear.
        for _, child in ipairs(OptionsFrame:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end

        local options = optionsProvider()
        local visibleRows = math.max(1, math.min(#options, 5))
        local optionHeight = 29
        OptionsFrame.Size = UDim2.new(1, -16, 0, visibleRows * optionHeight + 8)
        DropdownFrame.Size = UDim2.new(1, -10, 0, 48 + visibleRows * optionHeight + 8)
        OptionsFrame.Visible = true
        isOpen = true
        MainButton.Text = "  " .. labelText .. ": " .. titleCaseTreeCategory(selectedValue) .. "   ▲"

        for index, option in ipairs(options) do
            local OptionButton = Instance.new("TextButton")
            OptionButton.Name = "Option_" .. tostring(index)
            OptionButton.LayoutOrder = index
            OptionButton.Size = UDim2.new(1, -4, 0, 26)
            OptionButton.BackgroundColor3 = option.value == selectedValue and Theme.Hover or Theme.Element
            OptionButton.BorderSizePixel = 0
            OptionButton.Text = "  " .. option.label
            OptionButton.TextColor3 = option.value == selectedValue and Theme.Accent or Theme.Text
            OptionButton.Font = Enum.Font.Gotham
            OptionButton.TextSize = 13
            OptionButton.TextXAlignment = Enum.TextXAlignment.Left
            OptionButton.Parent = OptionsFrame
            Instance.new("UICorner", OptionButton).CornerRadius = UDim.new(0, 5)

            OptionButton.MouseButton1Click:Connect(function()
                selectedValue = option.value
                getgenv().SelectedTreeType = selectedValue
                MainButton.Text = "  " .. labelText .. ": " .. titleCaseTreeCategory(selectedValue) .. "   ▼"
                closeDropdown()
                callback(selectedValue)
                if ConfigAutoSave and saveConfig then
                    saveConfig(true)
                end
            end)
        end
    end)
end

-- ==========================================
-- 7. TABS INITIALIZATION
-- ==========================================
local InfoTab = CreateTab("Home", true)
local MainTab = CreateTab("Main", false)
local UpgradesTab = CreateTab("Upgrades", false)
local PlayerTab = CreateTab("Player", false)
local ConfigTab = CreateTab("Config", false)




do -- Scoped to reduce active locals during obfuscation.

-- ==========================================
-- UPGRADE GUI DETECTOR
-- Dropdown selects a card from PlayerGui.Upgrades.Panel.
-- The toggle watches for that card while it is visible and highlights it.
-- This only detects/highlights UI; it does not purchase upgrades.
-- ==========================================
local UpgradeTargets = {
    {label = "Hands - Hold", group = "Hands", object = "HandsHold"},
    {label = "Hands - Speed", group = "Hands", object = "HandsSpeed"},
    {label = "Hands - Grasp", group = "Hands", object = "HandsGrasp"},

    {label = "Axe - Hold", group = "Axe", object = "AxeHold"},
    {label = "Axe - Sharp", group = "Axe", object = "AxeSharp"},
    {label = "Axe - Speed", group = "Axe", object = "AxeSpeed"},

    {label = "Chainsaw - Cooling", group = "Chainsaw", object = "ChainsawCooling"},
    {label = "Chainsaw - Recovery", group = "Chainsaw", object = "ChainsawRecovery"},
    {label = "Chainsaw - Speed", group = "Chainsaw", object = "ChainsawSpeed"},

    {label = "Chainsaw Arms - Damage", group = "ChainsawArms", object = "ArmsDamage"},
    {label = "Chainsaw Arms - Recovery", group = "ChainsawArms", object = "ArmsRecovery"},
    {label = "Chainsaw Arms - Speed", group = "ChainsawArms", object = "ArmsSpeed"},

     {label = "Vacuum - Range", group = "Vacuum", object = "VacuumRange"},
    {label = "Vacuum - Speed", group = "Vacuum", object = "VacuumSpeed"},
    {label = "Vacuum - Amount", group = "Vacuum", object = "VacuumAmount"},

    {label = "Claws - Cooldown", group = "Claws", object = "ClawsCooldown"},
    {label = "Claws - Leap", group = "Claws", object = "ClawsLeap"},
    {label = "Claws - Speed", group = "Claws", object = "ClawsSpeed"},

    {label = "Dynamite - Cooldown", group = "Dynamite", object = "DynamiteCooldown"},
    {label = "Dynamite - Radius", group = "Dynamite", object = "DynamiteRadius"},
    {label = "Dynamite - Range", group = "Dynamite", object = "DynamiteRange"},

    {label = "Gear - Chipper Speed", group = "Gear", object = "GearChipper"},
    {label = "Gear - Walk Speed", group = "Gear", object = "GearSpeed"},
}

local UpgradeOptions = {{label = "All Listed Upgrades", value = "__ALL__"}}
for _, target in ipairs(UpgradeTargets) do
    table.insert(UpgradeOptions, {label = target.label, value = target.label})
end

getgenv().SelectedUpgradeToDetect = getgenv().SelectedUpgradeToDetect or "__ALL__"
getgenv().UpgradeDetectorEnabled = false

local function findRuntimeUpgradePanel()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return nil end

    local upgradesGui = playerGui:FindFirstChild("Upgrades", true)
    if not upgradesGui then return nil end

    return upgradesGui:FindFirstChild("Panel", true)
end

local function findUpgradeGuiObject(target)
    local panel = findRuntimeUpgradePanel()
    if not panel then return nil end

    local group = panel:FindFirstChild(target.group) or panel:FindFirstChild(target.group, true)
    if not group then return nil end

    return group:FindFirstChild(target.object) or group:FindFirstChild(target.object, true)
end

local function isUpgradeVisible(object)
    if not object or not object.Parent then return false end

    local current = object
    while current do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end
        if current:IsA("ScreenGui") and not current.Enabled then
            return false
        end
        current = current.Parent
    end

    return true
end

local upgradeHighlights = {}
local function setUpgradeHighlight(object)
    if not object or not object:IsA("GuiObject") then return end

    local stroke = object:FindFirstChild("AriseUpgradeDetectorStroke")
    if not stroke or not stroke:IsA("UIStroke") then
        stroke = Instance.new("UIStroke")
        stroke.Name = "AriseUpgradeDetectorStroke"
        stroke.Parent = object
    end

    stroke.Color = Theme.Accent
    stroke.Thickness = 3
    stroke.Transparency = 0
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    upgradeHighlights[object] = stroke
end

local function clearUpgradeHighlights(keepSet)
    for object, stroke in pairs(upgradeHighlights) do
        if not keepSet or not keepSet[object] then
            if stroke and stroke.Parent then
                stroke:Destroy()
            end
            upgradeHighlights[object] = nil
        end
    end
end

local function createUpgradeDropdown(parent, labelText, options, defaultValue, callback)
    local selectedValue = defaultValue or "__ALL__"

    local frame = Instance.new("Frame")
    frame.Name = "UpgradeDetectorDropdown"
    frame.Size = UDim2.new(1, -10, 0, 45)
    frame.BackgroundColor3 = Theme.Element
    frame.BorderSizePixel = 0
    frame.ClipsDescendants = true
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local mainButton = Instance.new("TextButton")
    mainButton.Size = UDim2.new(1, -16, 0, 35)
    mainButton.Position = UDim2.new(0, 8, 0, 5)
    mainButton.BackgroundColor3 = Theme.Hover
    mainButton.BorderSizePixel = 0
    mainButton.TextColor3 = Theme.Text
    mainButton.Font = Enum.Font.GothamMedium
    mainButton.TextSize = 12
    mainButton.TextXAlignment = Enum.TextXAlignment.Left
    mainButton.Text = "  " .. labelText .. ": " .. (selectedValue == "__ALL__" and "All Listed Upgrades" or selectedValue) .. "   ▼"
    mainButton.Parent = frame
    Instance.new("UICorner", mainButton).CornerRadius = UDim.new(0, 6)

    local optionsFrame = Instance.new("ScrollingFrame")
    optionsFrame.Name = "UpgradeOptions"
    optionsFrame.Position = UDim2.new(0, 8, 0, 43)
    optionsFrame.Size = UDim2.new(1, -16, 0, 0)
    optionsFrame.BackgroundColor3 = Theme.Background
    optionsFrame.BorderSizePixel = 0
    optionsFrame.ScrollBarThickness = 3
    optionsFrame.ScrollBarImageColor3 = Theme.Accent
    optionsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    optionsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    optionsFrame.Visible = false
    optionsFrame.Parent = frame
    Instance.new("UICorner", optionsFrame).CornerRadius = UDim.new(0, 6)

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 3)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = optionsFrame

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 4)
    padding.PaddingBottom = UDim.new(0, 4)
    padding.PaddingLeft = UDim.new(0, 4)
    padding.PaddingRight = UDim.new(0, 4)
    padding.Parent = optionsFrame

    local isOpen = false
    local function setClosed()
        isOpen = false
        optionsFrame.Visible = false
        frame.Size = UDim2.new(1, -10, 0, 45)
        mainButton.Text = "  " .. labelText .. ": " .. (selectedValue == "__ALL__" and "All Listed Upgrades" or selectedValue) .. "   ▼"
    end

    mainButton.MouseButton1Click:Connect(function()
        if isOpen then
            setClosed()
            return
        end

        for _, child in ipairs(optionsFrame:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end

        local visibleRows = math.min(#options, 5)
        optionsFrame.Size = UDim2.new(1, -16, 0, visibleRows * 29 + 8)
        frame.Size = UDim2.new(1, -10, 0, 48 + visibleRows * 29 + 8)
        optionsFrame.Visible = true
        isOpen = true
        mainButton.Text = "  " .. labelText .. ": " .. (selectedValue == "__ALL__" and "All Listed Upgrades" or selectedValue) .. "   ▲"

        for index, option in ipairs(options) do
            local optionButton = Instance.new("TextButton")
            optionButton.Name = "UpgradeOption_" .. tostring(index)
            optionButton.LayoutOrder = index
            optionButton.Size = UDim2.new(1, -4, 0, 26)
            optionButton.BackgroundColor3 = option.value == selectedValue and Theme.Hover or Theme.Element
            optionButton.BorderSizePixel = 0
            optionButton.Text = "  " .. option.label
            optionButton.TextColor3 = option.value == selectedValue and Theme.Accent or Theme.Text
            optionButton.Font = Enum.Font.Gotham
            optionButton.TextSize = 12
            optionButton.TextXAlignment = Enum.TextXAlignment.Left
            optionButton.Parent = optionsFrame
            Instance.new("UICorner", optionButton).CornerRadius = UDim.new(0, 5)

            optionButton.MouseButton1Click:Connect(function()
                selectedValue = option.value
                getgenv().SelectedUpgradeToDetect = selectedValue
                setClosed()
                callback(selectedValue)
                if ConfigAutoSave and saveConfig then
                    saveConfig(true)
                end
            end)
        end
    end)
end

CreateSection(UpgradesTab, "Upgrade Detector")
CreateSection(UpgradesTab, "Select a card from the game's Upgrades GUI.")
getgenv().SelectedUpgradeToBuy = getgenv().SelectedUpgradeToBuy or getgenv().SelectedUpgradeToDetect or "__ALL__"
createUpgradeDropdown(UpgradesTab, "Upgrade", UpgradeOptions, getgenv().SelectedUpgradeToDetect, function(value)
    getgenv().SelectedUpgradeToDetect = value
    getgenv().SelectedUpgradeToBuy = value
    sendNotification(
        "Upgrade Detector",
        value == "__ALL__" and "Selected all listed upgrades." or ("Selected " .. value .. "."),
        3,
        Theme.Accent
    )
end)

local UpgradeStatusCard = Instance.new("Frame")
UpgradeStatusCard.Name = "UpgradeDetectorStatus"
UpgradeStatusCard.Size = UDim2.new(1, -10, 0, 48)
UpgradeStatusCard.BackgroundColor3 = Theme.Element
UpgradeStatusCard.BorderSizePixel = 0
UpgradeStatusCard.Parent = UpgradesTab
Instance.new("UICorner", UpgradeStatusCard).CornerRadius = UDim.new(0, 8)

local UpgradeStatusLabel = Instance.new("TextLabel")
UpgradeStatusLabel.Size = UDim2.new(1, -20, 1, -8)
UpgradeStatusLabel.Position = UDim2.new(0, 10, 0, 4)
UpgradeStatusLabel.BackgroundTransparency = 1
UpgradeStatusLabel.Text = "Status: Detector disabled"
UpgradeStatusLabel.TextColor3 = Theme.TextDim
UpgradeStatusLabel.Font = Enum.Font.Gotham
UpgradeStatusLabel.TextSize = 12
UpgradeStatusLabel.TextWrapped = true
UpgradeStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
UpgradeStatusLabel.Parent = UpgradeStatusCard

CreateToggle(UpgradesTab, "Detect Selected Upgrade", false, function(state)
    getgenv().UpgradeDetectorEnabled = state
    if not state then
        clearUpgradeHighlights()
        UpgradeStatusLabel.Text = "Status: Detector disabled"
        sendNotification("Upgrade Detector", "Detection disabled.", 2, Color3.fromRGB(255, 100, 100))
    else
        sendNotification("Upgrade Detector", "Watching the live PlayerGui upgrade cards.", 3, Theme.Accent)
    end
end)

-- ==========================================
-- AUTO UPGRADE BUYER
-- Uses the game's BuyUpgrade RemoteEvent with the selected upgrade key,
-- e.g. BuyUpgrade:FireServer("HandsHold").
-- ==========================================
CreateSection(UpgradesTab, "Auto Upgrade")
CreateSection(UpgradesTab, "Choose one upgrade above, or select All Listed Upgrades.")

getgenv().UpgradeBuyDelay = tonumber(getgenv().UpgradeBuyDelay) or 0.8
CreateSlider(UpgradesTab, "Purchase Delay (s)", 0.2, 3, getgenv().UpgradeBuyDelay, function(value)
    getgenv().UpgradeBuyDelay = value
end)

local UpgradeBuyStatusCard = Instance.new("Frame")
UpgradeBuyStatusCard.Name = "UpgradeBuyerStatus"
UpgradeBuyStatusCard.Size = UDim2.new(1, -10, 0, 48)
UpgradeBuyStatusCard.BackgroundColor3 = Theme.Element
UpgradeBuyStatusCard.BorderSizePixel = 0
UpgradeBuyStatusCard.Parent = UpgradesTab
Instance.new("UICorner", UpgradeBuyStatusCard).CornerRadius = UDim.new(0, 8)

local UpgradeBuyStatusLabel = Instance.new("TextLabel")
UpgradeBuyStatusLabel.Size = UDim2.new(1, -20, 1, -8)
UpgradeBuyStatusLabel.Position = UDim2.new(0, 10, 0, 4)
UpgradeBuyStatusLabel.BackgroundTransparency = 1
UpgradeBuyStatusLabel.Text = "Auto upgrade: OFF"
UpgradeBuyStatusLabel.TextColor3 = Theme.TextDim
UpgradeBuyStatusLabel.Font = Enum.Font.Gotham
UpgradeBuyStatusLabel.TextSize = 12
UpgradeBuyStatusLabel.TextWrapped = true
UpgradeBuyStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
UpgradeBuyStatusLabel.Parent = UpgradeBuyStatusCard

local function findBuyUpgradeRemote()
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    local services = shared and shared:FindFirstChild("Services")
    local remotes = services and services:FindFirstChild("ChopRemotes")
    local remote = remotes and remotes:FindFirstChild("BuyUpgrade")
    if remote and remote:IsA("RemoteEvent") then
        return remote
    end
    return nil
end

local function getSelectedUpgradeTargets()
    local selection = getgenv().SelectedUpgradeToBuy or getgenv().SelectedUpgradeToDetect or "__ALL__"
    local selected = {}
    if selection == "__ALL__" then
        for _, target in ipairs(UpgradeTargets) do
            table.insert(selected, target)
        end
    else
        for _, target in ipairs(UpgradeTargets) do
            if target.label == selection then
                table.insert(selected, target)
                break
            end
        end
    end
    return selected, selection
end

CreateToggle(UpgradesTab, "Auto Buy Selected Upgrade(s)", false, function(state)
    getgenv().AutoUpgradeEnabled = state
    if state then
        local remote = findBuyUpgradeRemote()
        if not remote then
            UpgradeBuyStatusLabel.Text = "Auto upgrade: ON, but BuyUpgrade RemoteEvent was not found."
            sendNotification("Auto Upgrade", "BuyUpgrade RemoteEvent not found.", 4, Color3.fromRGB(255, 80, 80))
        else
            local _, selection = getSelectedUpgradeTargets()
            UpgradeBuyStatusLabel.Text = "Auto upgrade: ON | Selection: " .. (selection == "__ALL__" and "All Listed Upgrades" or selection)
            sendNotification("Auto Upgrade", "Enabled for " .. (selection == "__ALL__" and "all listed upgrades" or selection) .. ".", 3, Theme.Accent)
        end
    else
        UpgradeBuyStatusLabel.Text = "Auto upgrade: OFF"
        sendNotification("Auto Upgrade", "Automatic upgrade requests stopped.", 2, Color3.fromRGB(255, 100, 100))
    end
end)

getgenv().AutoUpgradeThread = task.spawn(function()
    local lastErrorNotice = 0
    local lastSummary = ""

    while ScreenGui and ScreenGui.Parent do
        if not getgenv().AutoUpgradeEnabled then
            task.wait(0.15)
            continue
        end

        local remote = findBuyUpgradeRemote()
        if not remote then
            UpgradeBuyStatusLabel.Text = "Auto upgrade: waiting for ReplicatedStorage.Shared.Services.ChopRemotes.BuyUpgrade"
            if os.clock() - lastErrorNotice > 5 then
                lastErrorNotice = os.clock()
                sendNotification("Auto Upgrade", "BuyUpgrade RemoteEvent is missing or not a RemoteEvent.", 3, Color3.fromRGB(255, 80, 80))
            end
            task.wait(1)
            continue
        end

        local targets, selection = getSelectedUpgradeTargets()
        if #targets == 0 then
            UpgradeBuyStatusLabel.Text = "Auto upgrade: no matching upgrade selected."
            task.wait(0.5)
            continue
        end

        for _, target in ipairs(targets) do
            if not getgenv().AutoUpgradeEnabled or not (ScreenGui and ScreenGui.Parent) then
                break
            end

            -- The server decides whether the upgrade is affordable/available.
            local ok, err = pcall(function()
                remote:FireServer(target.object)
            end)

            if ok then
                UpgradeBuyStatusLabel.Text = "Auto upgrade: request sent for " .. target.label
            else
                UpgradeBuyStatusLabel.Text = "Auto upgrade error: " .. tostring(err)
                if os.clock() - lastErrorNotice > 5 then
                    lastErrorNotice = os.clock()
                    sendNotification("Auto Upgrade Error", tostring(err), 4, Color3.fromRGB(255, 80, 80))
                end
            end

            local delaySeconds = math.clamp(tonumber(getgenv().UpgradeBuyDelay) or 0.8, 0.2, 3)
            task.wait(delaySeconds)
        end

        if getgenv().AutoUpgradeEnabled then
            if selection == "__ALL__" then
                UpgradeBuyStatusLabel.Text = "Auto upgrade: completed one pass of all listed upgrades; cycling again while enabled."
            else
                UpgradeBuyStatusLabel.Text = "Auto upgrade: continuing requests for " .. targets[1].label .. " while enabled."
            end
            task.wait(1)
        end
    end
end)

getgenv().UpgradeDetectorThread = task.spawn(function()
    local lastSelection = nil
    local lastNotifiedSelection = nil

    while ScreenGui and ScreenGui.Parent do
        if not getgenv().UpgradeDetectorEnabled then
            clearUpgradeHighlights()
            UpgradeStatusLabel.Text = "Status: Detector disabled"
            lastSelection = nil
            lastNotifiedSelection = nil
            task.wait(0.25)
            continue
        end

        local selection = getgenv().SelectedUpgradeToDetect or "__ALL__"
        if selection ~= lastSelection then
            lastSelection = selection
            lastNotifiedSelection = nil
        end

        local foundObjects = {}
        local foundLabels = {}
        local function inspectTarget(target)
            local object = findUpgradeGuiObject(target)
            if object and isUpgradeVisible(object) then
                foundObjects[object] = true
                table.insert(foundLabels, target.label)
                setUpgradeHighlight(object)
            end
        end

        if selection == "__ALL__" then
            for _, target in ipairs(UpgradeTargets) do
                inspectTarget(target)
            end
        else
            for _, target in ipairs(UpgradeTargets) do
                if target.label == selection then
                    inspectTarget(target)
                    break
                end
            end
        end

        clearUpgradeHighlights(foundObjects)

        if selection == "__ALL__" then
            if #foundLabels > 0 then
                UpgradeStatusLabel.Text = "Status: Detected " .. tostring(#foundLabels) .. " visible upgrade card(s)."
                if lastNotifiedSelection == nil then
                    sendNotification("Upgrade Detector", "Detected " .. tostring(#foundLabels) .. " visible upgrade card(s).", 3, Theme.Accent)
                    lastNotifiedSelection = selection
                end
            else
                UpgradeStatusLabel.Text = "Status: Waiting for the Upgrades panel to be visible..."
            end
        elseif #foundLabels > 0 then
            UpgradeStatusLabel.Text = "Status: FOUND - " .. foundLabels[1]
            if lastNotifiedSelection == nil then
                sendNotification("Upgrade Detected", foundLabels[1] .. " is visible in the GUI.", 3, Theme.Accent)
                lastNotifiedSelection = selection
            end
        else
            UpgradeStatusLabel.Text = "Status: Waiting for '" .. selection .. "' to appear..."
        end

        task.wait(0.3)
    end

    clearUpgradeHighlights()
end)

end -- Upgrade Detector / Auto Upgrade scope

do -- Keep config-only helper locals out of the main script scope.

-- ==========================================
-- CONFIG UI HELPERS (these were missing, causing startup to stop here)
-- ==========================================
local function CreateLabel(parent, title, description)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -10, 0, 46)
    frame.BackgroundColor3 = Theme.Element
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -20, 0, 18)
    titleLabel.Position = UDim2.new(0, 10, 0, 5)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = tostring(title)
    titleLabel.TextColor3 = Theme.Text
    titleLabel.Font = Enum.Font.GothamMedium
    titleLabel.TextSize = 13
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = frame

    local descriptionLabel = Instance.new("TextLabel")
    descriptionLabel.Size = UDim2.new(1, -20, 0, 16)
    descriptionLabel.Position = UDim2.new(0, 10, 0, 24)
    descriptionLabel.BackgroundTransparency = 1
    descriptionLabel.Text = tostring(description or "")
    descriptionLabel.TextColor3 = Theme.TextDim
    descriptionLabel.Font = Enum.Font.Gotham
    descriptionLabel.TextSize = 11
    descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
    descriptionLabel.TextTruncate = Enum.TextTruncate.AtEnd
    descriptionLabel.Parent = frame

    return frame
end

local function CreateButton(parent, text, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -10, 0, 38)
    button.BackgroundColor3 = Theme.Element
    button.BorderSizePixel = 0
    button.Text = tostring(text)
    button.TextColor3 = Theme.Text
    button.Font = Enum.Font.GothamBold
    button.TextSize = 13
    button.AutoButtonColor = true
    button.Parent = parent
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
    button.MouseButton1Click:Connect(function()
        local ok, err = pcall(callback)
        if not ok then
            sendNotification("Button Error", tostring(err), 4, Color3.fromRGB(255, 80, 80))
        end
    end)
    return button
end

saveConfig = function(silent)
    if not ConfigFileAvailable then
        return false
    end

    local data = {
        _autoSave = ConfigAutoSave,
        FarmRadius = tonumber(getgenv().FarmRadius) or 500,
        TreeTeleportDelay = tonumber(getgenv().TreeTeleportDelay) or 0,
        SellAtLogs = tonumber(getgenv().SellAtLogs) or 5,
        SelectedTreeType = getgenv().SelectedTreeType or "All Trees",
        AutoFarmLogs = getgenv().AutoFarmLogs == true,
        AutoPickupLogs = getgenv().AutoPickupLogs == true,
        AutoSellLogs = getgenv().AutoSellLogs == true,
        SelectedUpgradeToDetect = getgenv().SelectedUpgradeToDetect or "__ALL__",
        SelectedUpgradeToBuy = getgenv().SelectedUpgradeToBuy or "__ALL__",
        UpgradeBuyDelay = tonumber(getgenv().UpgradeBuyDelay) or 0.8,
    }

    local ok = pcall(function()
        writefile(ConfigPath, HttpService:JSONEncode(data))
    end)
    if ok then
        ConfigData = data
        getgenv().AriseConfigData = data
    end
    return ok
end

CreateSection(ConfigTab, "Configuration")
CreateLabel(ConfigTab, "Automatic saving", "Save toggle, slider, and selector settings.")
CreateToggle(ConfigTab, "Auto Save Config", ConfigAutoSave, function(state)
    ConfigAutoSave = state
    ConfigData._autoSave = state
    if state then
        saveConfig(true)
        sendNotification("Config", "Automatic saving enabled.", 3, Theme.Accent)
    else
        saveConfig(true)
        sendNotification("Config", "Automatic saving disabled.", 3, Theme.AccentDark)
    end
end)
CreateButton(ConfigTab, "Save Config Now", function()
    local ok = saveConfig(true)
    if ok then
        sendNotification("Config Saved", "Saved to " .. ConfigPath, 3, Theme.Accent)
    else
        sendNotification("Config Not Saved", "Executor file APIs unavailable; settings only last this session.", 4, Theme.AccentDark)
    end
end)
CreateButton(ConfigTab, "Reload Config File", function()
    if not ConfigFileAvailable then
        sendNotification("Config", "Executor file APIs unavailable.", 3, Theme.AccentDark)
        return
    end
    local ok = pcall(function()
        if type(isfile) == "function" and not isfile(ConfigPath) then
            sendNotification("Config", "No saved config file found yet.", 3, Theme.AccentDark)
            return
        end
        local data = HttpService:JSONDecode(readfile(ConfigPath))
        if type(data) == "table" then
            ConfigData = data
            getgenv().AriseConfigData = ConfigData
            sendNotification("Config Loaded", "Re-execute the script to apply reloaded settings.", 4, Theme.Accent)
        else
            error("Config file did not contain a table")
        end
    end)
    if not ok then sendNotification("Config Error", "Could not read config.json.", 3, Theme.AccentDark) end
end)
CreateLabel(ConfigTab, "Config file", ConfigFileAvailable and ConfigPath or "Executor file APIs unavailable")

end -- Config UI helper scope

do -- Scoped to reduce active locals during obfuscation.

-- ==========================================
-- 8. AUTO FARM & SELL ENGINE
-- ==========================================

local targetHighlight -- forward declaration used by UI toggle callbacks

CreateSection(MainTab, "Chopping")

getgenv().FarmRadius = math.clamp(
    tonumber(getgenv().FarmRadius) or 500,
    50,
    2000
)
CreateSlider(MainTab, "Max Farming Radius", 50, 2000, getgenv().FarmRadius, function(value)
    getgenv().FarmRadius = value
end)

if getgenv().AutoFarmLogs == nil then getgenv().AutoFarmLogs = false end
CreateToggle(MainTab, "Auto Chopping", getgenv().AutoFarmLogs == true, function(state)
    getgenv().AutoFarmLogs = state

    if state then
        local character = LocalPlayer.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if hrp then
            getgenv().FarmCenterPoint = hrp.Position
            getgenv().AutomationCenterPoint = hrp.Position
        end
        sendNotification(
            "Auto Farm",
            "Auto Farm Logs enabled within " .. tostring(getgenv().FarmRadius) .. " studs.",
            3,
            Theme.Accent
        )
    else
        sendNotification("Auto Farm", "Auto Farm Logs stopped.", 3, Color3.fromRGB(255, 60, 60))
        if targetHighlight then targetHighlight.Adornee = nil end
    end
end)

CreateTreeTypeDropdown(MainTab, "Tree Type", getAvailableTreeTypeOptions, getgenv().SelectedTreeType, function(value)
    getgenv().SelectedTreeType = value
    local shownType = value == "All Trees" and "all tree types" or titleCaseTreeCategory(value) .. " trees"
    sendNotification("Tree Filter", "Farming target set to " .. shownType .. ".", 3, Theme.Accent)
end)

if getgenv().TreeTeleportDelay == nil then
    getgenv().TreeTeleportDelay = 0
end
getgenv().TreeTeleportDelay = math.clamp(tonumber(getgenv().TreeTeleportDelay) or 0, 0, 5)
CreateSlider(MainTab, "Delay (s)", 0, 5, getgenv().TreeTeleportDelay, function(value)
    getgenv().TreeTeleportDelay = value
end)

CreateSection(MainTab, "Logs & Cash")

if getgenv().AutoPickupLogs == nil then getgenv().AutoPickupLogs = false end
CreateToggle(MainTab, "Auto Pickup", getgenv().AutoPickupLogs == true, function(state)
    getgenv().AutoPickupLogs = state

    if state and not getgenv().AutoFarmLogs then
        local character = LocalPlayer.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if hrp then
            getgenv().AutomationCenterPoint = hrp.Position
        end
    end

    sendNotification(
        "Auto Pickup",
        state and "Automatic log pickup enabled." or "Automatic log pickup disabled.",
        2,
        state and Theme.Accent or Color3.fromRGB(255, 100, 100)
    )
end)

if getgenv().AutoSellLogs == nil then getgenv().AutoSellLogs = false end
CreateToggle(MainTab, "Auto Sell", getgenv().AutoSellLogs == true, function(state)
    getgenv().AutoSellLogs = state
    sendNotification(
        "Auto Sell",
        state and "Automatic selling enabled." or "Automatic selling disabled.",
        2,
        state and Theme.Accent or Color3.fromRGB(255, 100, 100)
    )
end)

-- Select the backpack count that triggers an automatic deposit.
-- The game remote may deposit all carried logs; this setting controls the trigger threshold.
getgenv().SellAtLogs = math.clamp(math.floor(tonumber(getgenv().SellAtLogs) or 5), 1, 100)
CreateSlider(MainTab, "Sell At (logs)", 1, 100, getgenv().SellAtLogs, function(value)
    getgenv().SellAtLogs = math.clamp(math.floor(tonumber(value) or 5), 1, 100)
end)


if getgenv().AutoFarmLogs == nil then getgenv().AutoFarmLogs = false end
getgenv().PickupAttemptTimes = setmetatable({}, {__mode = "k"})

-- Remotes
local ChopRemote = ReplicatedStorage.Shared.Services.ChopRemotes.Chop
local PickUpRemote = ReplicatedStorage.Shared.Services.ChopRemotes.PickUpLog
local DepositRemote = ReplicatedStorage.Shared.Services.ChopRemotes.DepositLogs

-- Visual Highlight
targetHighlight = CoreGui:FindFirstChild("TreeTargetHighlight")
if not targetHighlight then
    targetHighlight = Instance.new("Highlight")
    targetHighlight.Name = "TreeTargetHighlight"
    targetHighlight.FillColor = Color3.fromRGB(255, 0, 0)
    targetHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    targetHighlight.FillTransparency = 0.5
    targetHighlight.Parent = CoreGui
end
targetHighlight.Adornee = nil

-- ==========================================
-- TREE STATE / INSTANT RETARGET HELPERS
-- ==========================================
local function isTopActive(top)
    if not top or not top.Parent then
        return false
    end

    if top:IsA("BasePart") then
        return top.Transparency < 0.95 and top.LocalTransparencyModifier < 0.95
    end

    for _, obj in ipairs(top:GetDescendants()) do
        if obj:IsA("BasePart")
            and obj.Transparency < 0.95
            and obj.LocalTransparencyModifier < 0.95 then
            return true
        end
    end

    -- A Top container with no visible parts is considered depleted.
    return false
end

local function getClosestTree(center)
    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local treesFolder = getTreeFolder()
    if not treesFolder then return nil end

    local selectedType = getgenv().SelectedTreeType or "All Trees"
    local closestTree, shortestDistance = nil, math.huge

    for _, tree in ipairs(treesFolder:GetChildren()) do
        if not tree.Parent then
            continue
        end

        -- Apply the dropdown filter. "All Trees" includes every named type.
        local treeType = getTreeCategory(tree)
        -- Ignore unlisted species even when "All Trees" is selected.
        if not SUPPORTED_TREE_TYPE_SET[treeType] then
            continue
        end
        if selectedType ~= "All Trees" and treeType ~= selectedType then
            continue
        end

        local top = tree:FindFirstChild("Top")
        if not top or not isTopActive(top) then
            continue
        end

        local targetPart = tree:FindFirstChild("TrunkBase") or tree:FindFirstChild("Root") or tree
        local ok, treePosition = pcall(function()
            return targetPart:GetPivot().Position
        end)
        if not ok or not treePosition then
            continue
        end

        if (treePosition - center).Magnitude > (tonumber(getgenv().FarmRadius) or 500) then
            continue
        end

        local distance = (treePosition - hrp.Position).Magnitude
        if distance < shortestDistance then
            shortestDistance = distance
            closestTree = {
                instance = tree,
                pos = treePosition,
                top = top,
                treeType = treeType
            }
        end
    end

    return closestTree
end

local function getLogCount()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return nil, nil, false end

    local function parseText(text)
        if type(text) ~= "string" then return nil, nil end
        local current, maximum = string.match(text, "(%d+)%s*/%s*(%d+)")
        if current and maximum then
            return tonumber(current), tonumber(maximum)
        end
        return nil, nil
    end

    -- Prefer the original expected counter path when it exists.
    local hud = playerGui:FindFirstChild("ChopHud", true)
    local backpack = hud and hud:FindFirstChild("Backpack", true)
    local directCount = backpack and backpack:FindFirstChild("Count", true)

    if directCount then
        if directCount:IsA("TextLabel") or directCount:IsA("TextButton") then
            local current, maximum = parseText(directCount.Text)
            if current ~= nil then return current, maximum, true end

            local single = string.match(directCount.Text or "", "(%d+)")
            if single then return tonumber(single), nil, true end
        end

        for _, descendant in ipairs(directCount:GetDescendants()) do
            if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
                local current, maximum = parseText(descendant.Text)
                if current ~= nil then return current, maximum, true end
                local single = string.match(descendant.Text or "", "(%d+)")
                if single then return tonumber(single), nil, true end
            end
        end
    end

    -- HUD names/layouts can change, so search named count labels next.
    for _, obj in ipairs(playerGui:GetDescendants()) do
        if (obj:IsA("TextLabel") or obj:IsA("TextButton"))
            and string.find(string.lower(obj.Name), "count", 1, true) then
            local current, maximum = parseText(obj.Text)
            if current ~= nil then return current, maximum, true end
            local single = string.match(obj.Text or "", "(%d+)")
            if single then return tonumber(single), nil, true end
        end
    end

    -- Final fallback: any UI text displaying a current/maximum pair.
    for _, obj in ipairs(playerGui:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local current, maximum = parseText(obj.Text)
            if current ~= nil then return current, maximum, true end
        end
    end

    return nil, nil, false
end

local function getSellThreshold(maximum)
    local threshold = math.max(1, math.floor(tonumber(getgenv().SellAtLogs) or 5))
    -- If the selected threshold exceeds backpack capacity, sell at capacity
    -- instead of letting the inventory become stuck full.
    if maximum and maximum > 0 then
        threshold = math.min(threshold, maximum)
    end
    return threshold
end

local function isBackpackFull()
    local current, maximum, foundCounter = getLogCount()
    if not foundCounter or current == nil then return false end
    if maximum and maximum > 0 then return current >= maximum end
    -- If capacity is not displayed, use the selected sell threshold while Auto Sell is on.
    if getgenv().AutoSellLogs then
        return current >= getSellThreshold(maximum)
    end
    return current >= 5
end

local function hasReachedSellThreshold()
    if not getgenv().AutoSellLogs then return false end
    local current, maximum, foundCounter = getLogCount()
    return foundCounter
        and current ~= nil
        and current >= getSellThreshold(maximum)
end

local function checkLogsSpawned(treePos)
    local logsFolder = workspace:FindFirstChild("Logs")
    if logsFolder then
        local flatTreePos = Vector3.new(treePos.X, 0, treePos.Z)
        for _, log in ipairs(logsFolder:GetChildren()) do
            if log.Name == "Log" then
                local logPos = log:GetPivot().Position
                local flatLogPos = Vector3.new(logPos.X, 0, logPos.Z)
                if (flatLogPos - flatTreePos).Magnitude <= 15 then return true end
            end
        end
    end
    return false
end

-- ==========================================
-- SHARED AUTOMATION ENGINE
-- Pickup and selling now run independently of Auto Farm Logs.
-- One dispatcher controls all teleports so workers cannot fight each other.
-- ==========================================
local function getDepositPadPosition()
    local map = workspace:FindFirstChild("Map")
    local sellSpot = map and map:FindFirstChild("SellSpot", true)
    local depositPad = sellSpot and sellSpot:FindFirstChild("DepositPad", true)

    if not depositPad then
        depositPad = workspace:FindFirstChild("DepositPad", true)
    end
    if not depositPad then
        return nil
    end

    if depositPad:IsA("BasePart") then
        return depositPad.Position
    end

    local ok, position = pcall(function()
        if depositPad:IsA("Model") then
            return depositPad:GetPivot().Position
        end
        return nil
    end)
    if ok and position then
        return position
    end

    for _, descendant in ipairs(depositPad:GetDescendants()) do
        if descendant:IsA("BasePart") then
            return descendant.Position
        end
    end

    return nil
end

local function getNearestLog(center, playerPosition, availableTree)
    local nearestLog, nearestPosition = nil, nil
    local nearestDistance = math.huge
    local now = os.clock()
    getgenv().PickupAttemptTimes = getgenv().PickupAttemptTimes or setmetatable({}, {__mode = "k"})

    local function considerLog(log)
        if not log or log.Name ~= "Log" then return end

        local lastAttempt = getgenv().PickupAttemptTimes[log] or 0
        if now - lastAttempt < 0.8 then return end

        local ok, position = pcall(function()
            if log:IsA("BasePart") then
                return log.Position
            end
            return log:GetPivot().Position
        end)
        if not ok or not position then return end
        if (position - center).Magnitude > (tonumber(getgenv().FarmRadius) or 500) then
            return
        end

        local distance = (position - playerPosition).Magnitude
        -- While farming, only detour for nearby logs if a tree is ready.
        -- When farming is OFF, pickup scans the complete configured radius.
        local allowedDistance = (getgenv().AutoFarmLogs and availableTree) and 18 or math.huge
        if distance <= allowedDistance and distance < nearestDistance then
            nearestLog = log
            nearestPosition = position
            nearestDistance = distance
        end
    end

    local logsFolder = workspace:FindFirstChild("Logs")
    if logsFolder then
        for _, log in ipairs(logsFolder:GetChildren()) do
            considerLog(log)
        end
    end

    -- Some executor/game combinations expose detached log instances through
    -- getnilinstances rather than workspace.Logs. Treat this as an optional fallback.
    if type(getnilinstances) == "function" then
        local ok, nilObjects = pcall(getnilinstances)
        if ok and type(nilObjects) == "table" then
            for _, log in ipairs(nilObjects) do
                considerLog(log)
            end
        end
    end

    return nearestLog, nearestPosition, nearestDistance
end

local function notifyRateLimited(key, title, message, duration, color, interval)
    local now = os.clock()
    local stampKey = key .. "At"
    if not getgenv()[stampKey] or now - getgenv()[stampKey] >= (interval or 5) then
        getgenv()[stampKey] = now
        sendNotification(title, message, duration or 3, color)
    end
end

getgenv().AriseAutomationThread = task.spawn(function()
    while ScreenGui and ScreenGui.Parent do
        local anyFeatureEnabled = getgenv().AutoFarmLogs or getgenv().AutoPickupLogs or getgenv().AutoSellLogs
        if not anyFeatureEnabled then
            task.wait(0.25)
            continue
        end

        -- Faster updates while farming; lower idle rate for pickup/sell-only mode.
        task.wait(getgenv().AutoFarmLogs and 0.03 or 0.12)

        local character = LocalPlayer.Character
        local hrpNode = character and character:FindFirstChild("HumanoidRootPart")
        if not hrpNode then
            task.wait(0.15)
            continue
        end

        if not getgenv().AutomationCenterPoint then
            getgenv().AutomationCenterPoint = hrpNode.Position
        end
        local center
        if getgenv().AutoFarmLogs then
            center = getgenv().FarmCenterPoint or hrpNode.Position
        else
            center = getgenv().AutomationCenterPoint or hrpNode.Position
        end

        -- AUTO SELL: works even when Auto Farm Logs is OFF.
        local currentCount, maximumCount, hasCounter = getLogCount()
        if getgenv().AutoSellLogs and not hasCounter then
            notifyRateLimited(
                "BagCounterWarning",
                "Auto Sell",
                "Backpack counter not found. Cannot detect the selected sell amount.",
                4,
                Color3.fromRGB(255, 150, 50),
                8
            )
        end

        local selectedSellThreshold = getSellThreshold(maximumCount)
        local thresholdReached = hasCounter
            and currentCount ~= nil
            and currentCount >= selectedSellThreshold

        if getgenv().AutoSellLogs and thresholdReached then
            local padPosition = getDepositPadPosition()
            if not padPosition then
                notifyRateLimited(
                    "DepositPadWarning",
                    "Auto Sell Error",
                    "Could not find the deposit pad in the map.",
                    4,
                    Color3.fromRGB(255, 60, 60),
                    5
                )
                task.wait(0.5)
                continue
            end

            local beforeCount = currentCount
            hrpNode.CFrame = CFrame.new(padPosition + Vector3.new(0, 4, 0))
            task.wait(0.6)

            local fired, fireError = pcall(function()
                DepositRemote:FireServer(false)
            end)
            if not fired then
                sendNotification(
                    "Auto Sell Error",
                    "Deposit request failed: " .. tostring(fireError),
                    4,
                    Color3.fromRGB(255, 60, 60)
                )
                task.wait(0.5)
                continue
            end

            -- Wait for the counter to decrease below its previous value or
            -- below the selected threshold before attempting further work.
            local deadline = os.clock() + 3
            local sold = false
            repeat
                task.wait(0.1)
                local afterCount, afterMaximum, counterFound = getLogCount()
                if counterFound and afterCount ~= nil then
                    local afterThreshold = getSellThreshold(afterMaximum)
                    if (beforeCount ~= nil and afterCount < beforeCount)
                        or afterCount < afterThreshold then
                        sold = true
                        break
                    end
                end
            until os.clock() >= deadline
                or not getgenv().AutoSellLogs
                or not (ScreenGui and ScreenGui.Parent)

            if not sold and getgenv().AutoSellLogs then
                notifyRateLimited(
                    "DepositFailNotice",
                    "Auto Sell Warning",
                    "Count did not decrease after deposit. Check the deposit pad and remote.",
                    4,
                    Color3.fromRGB(255, 150, 50),
                    5
                )
                task.wait(0.4)
            end
            continue
        end

        -- If selling is disabled, stop gathering at true backpack capacity.
        if isBackpackFull() and not getgenv().AutoSellLogs then
            notifyRateLimited(
                "BagFullNotice",
                "Backpack Full",
                "Turn on Auto Sell to empty the bag, or lower your sell threshold.",
                3,
                Color3.fromRGB(255, 150, 50),
                5
            )
            task.wait(0.25)
            continue
        end

        -- Find a tree only when farming is enabled. Pickup-only mode must not
        -- depend on a tree existing to collect logs.
        local availableTree = nil
        if getgenv().AutoFarmLogs then
            availableTree = getClosestTree(center)
        end

        local pickedUpThisPass = false

        -- AUTO PICKUP: works independently when Auto Farm Logs is OFF.
        if getgenv().AutoPickupLogs then
            local nearestLog, nearestPosition = getNearestLog(center, hrpNode.Position, availableTree)
            if nearestLog and nearestPosition and not isBackpackFull() then
                getgenv().PickupAttemptTimes[nearestLog] = os.clock()
                hrpNode.CFrame = CFrame.new(nearestPosition + Vector3.new(0, 3, 0))
                task.wait(0.08)

                local pickupOk, pickupError = pcall(function()
                    PickUpRemote:FireServer(nearestLog)
                end)
                if pickupOk then
                    pickedUpThisPass = true
                else
                    notifyRateLimited(
                        "PickupErrorNotice",
                        "Pickup Error",
                        tostring(pickupError),
                        4,
                        Color3.fromRGB(255, 60, 60),
                        5
                    )
                end
            end
        end

        -- AUTO FARM: chopping is the only behavior gated by Auto Farm Logs.
        if getgenv().AutoFarmLogs and not pickedUpThisPass and not isBackpackFull() then
            local targetData = availableTree or getClosestTree(center)
            if targetData then
                local targetTree = targetData.instance
                local treePosition = targetData.pos
                local targetTop = targetData.top

                if targetTree and targetTree.Parent and targetTop and isTopActive(targetTop) then
                    targetHighlight.Adornee = targetTop

                    local direction = hrpNode.Position - treePosition
                    local flatDirection = Vector3.new(direction.X, 0, direction.Z)
                    if flatDirection.Magnitude > 0 then
                        flatDirection = flatDirection.Unit
                    else
                        flatDirection = Vector3.new(1, 0, 0)
                    end

                    local standPosition = treePosition + flatDirection * 3.5
                    hrpNode.CFrame = CFrame.lookAt(
                        standPosition + Vector3.new(0, 3, 0),
                        treePosition
                    )

                    local teleportDelay = tonumber(getgenv().TreeTeleportDelay) or 0
                    if teleportDelay > 0 then
                        task.wait(teleportDelay)
                    end

                    local chopAttempts = 0
                    while getgenv().AutoFarmLogs
                        and targetTree.Parent
                        and targetTop.Parent
                        and targetTree:FindFirstChild("Top") == targetTop
                        and isTopActive(targetTop)
                        and (
                            (getgenv().SelectedTreeType or "All Trees") == "All Trees"
                            or getTreeCategory(targetTree) == normalizeTreeCategory(getgenv().SelectedTreeType)
                        )
                        and not isBackpackFull()
                        and not hasReachedSellThreshold()
                        and ScreenGui and ScreenGui.Parent do

                        ChopRemote:FireServer(targetTree, treePosition, 1, 1)
                        chopAttempts += 1

                        if chopAttempts % 25 == 0 and targetTop.Parent and isTopActive(targetTop) then
                            local randomDirection = Vector3.new(
                                math.random(-10, 10) / 10,
                                0,
                                math.random(-10, 10) / 10
                            )
                            if randomDirection.Magnitude > 0 then
                                randomDirection = randomDirection.Unit
                            else
                                randomDirection = Vector3.new(1, 0, 0)
                            end
                            local newPosition = treePosition + randomDirection * 3.5
                            hrpNode.CFrame = CFrame.lookAt(
                                newPosition + Vector3.new(0, 3, 0),
                                treePosition
                            )
                        end

                        task.wait(0.03)
                    end

                    if targetHighlight then
                        targetHighlight.Adornee = nil
                    end
                end
            end
        end
    end

    if targetHighlight then targetHighlight.Adornee = nil end
end)

end -- Auto Farm / Sell scope

-- ==========================================
-- FAR BIRD AURA
-- ==========================================

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ChopRemotes = ReplicatedStorage
    :WaitForChild("Shared")
    :WaitForChild("Services")
    :WaitForChild("ChopRemotes")

local PopBirdRemote = ChopRemotes:WaitForChild("PopBird")

local LocalPlayer = Players.LocalPlayer
local AuraRange = 1000 -- Increase this for a larger range
local farBirdAura = false
local auraLoopId = 0

local function getBirdPosition(bird)
    if bird:IsA("Model") then
        return bird:GetPivot().Position
    elseif bird:IsA("BasePart") then
        return bird.Position
    end

    local part = bird:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

CreateToggle(MainTab, "Bird Aura", false, function(state)
    farBirdAura = state
    auraLoopId += 1

    local thisLoop = auraLoopId

    if not state then
        return
    end

    task.spawn(function()
        while farBirdAura and thisLoop == auraLoopId do
            local character = LocalPlayer.Character
            local root = character
                and character:FindFirstChild("HumanoidRootPart")

            local birdsFolder = Workspace:FindFirstChild("AmbientBirds")

            if root and birdsFolder then
                for _, bird in ipairs(birdsFolder:GetChildren()) do
                    if not farBirdAura or thisLoop ~= auraLoopId then
                        break
                    end

                    local success, position = pcall(getBirdPosition, bird)

                    if success and position
                        and (position - root.Position).Magnitude <= AuraRange then

                        pcall(function()
                            PopBirdRemote:FireServer(position, nil)
                        end)

                        task.wait(0.15)
                    end
                end
            end

            task.wait(0.1)
        end
    end)
end)

do -- Player feature locals are only needed inside this section.

-- ==========================================
-- PLAYER TAB
-- ==========================================
local P_Logic = {
    WalkSpeed = false, SpeedVal = 32, InfJump = false, Noclip = false, InstantPrompt = false,
    Fly = false, FlySpeed = 60, AntiAFK = false, AutoReconnect = false, Disable3D = false,
    FPSBoost = false, UltraFPS = false,
    BodyVelocity = nil, BodyGyro = nil, FlyConnection = nil, NoclipConnection = nil, WsConnection = nil, JumpConn = nil
}

local Cache = {Prompts = {}, Materials = {}, Textures = {}, Transparencies = {}}

CreateSection(PlayerTab, "Movement")
CreateToggle(PlayerTab, "WalkSpeed", false, function(state)
    P_Logic.WalkSpeed = state
    if state then
        P_Logic.WsConnection = RunService.Heartbeat:Connect(function()
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then LocalPlayer.Character.Humanoid.WalkSpeed = P_Logic.SpeedVal end
        end)
    else
        if P_Logic.WsConnection then P_Logic.WsConnection:Disconnect() end
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then LocalPlayer.Character.Humanoid.WalkSpeed = 16 end
    end
end)
CreateSlider(PlayerTab, "Speed", 16, 200, 32, function(val) P_Logic.SpeedVal = val end)

CreateToggle(PlayerTab, "Infinite Jump", false, function(state) 
    P_Logic.InfJump = state 
    if state then
        P_Logic.JumpConn = UserInputService.JumpRequest:Connect(function()
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass('Humanoid') then LocalPlayer.Character:FindFirstChildOfClass('Humanoid'):ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    else
        if P_Logic.JumpConn then P_Logic.JumpConn:Disconnect() end
    end
end)

CreateToggle(PlayerTab, "Noclip", false, function(state)
    P_Logic.Noclip = state
    if state then
        P_Logic.NoclipConnection = RunService.Stepped:Connect(function()
            if LocalPlayer.Character then
                for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
                end
            end
        end)
    else
        if P_Logic.NoclipConnection then P_Logic.NoclipConnection:Disconnect() end
        if LocalPlayer.Character then
            for _, part in pairs(LocalPlayer.Character:GetDescendants()) do if part:IsA("BasePart") then part.CanCollide = true end end
        end
    end
end)

CreateToggle(PlayerTab, "Instant ProximityPrompt", false, function(state)
    P_Logic.InstantPrompt = state
    if state then
        for _, prompt in pairs(workspace:GetDescendants()) do
            if prompt:IsA("ProximityPrompt") then 
                if not Cache.Prompts[prompt] then Cache.Prompts[prompt] = prompt.HoldDuration end
                prompt.HoldDuration = 0 
            end
        end
    else
        for prompt, originalTime in pairs(Cache.Prompts) do
            if prompt and prompt.Parent then prompt.HoldDuration = originalTime end
        end
    end
end)

CreateSection(PlayerTab, "Fly")
local function StartFly()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    local hrp = char.HumanoidRootPart
    
    P_Logic.BodyVelocity = Instance.new("BodyVelocity")
    P_Logic.BodyVelocity.Velocity = Vector3.new(0, 0, 0)
    P_Logic.BodyVelocity.MaxForce = Vector3.new(40000, 40000, 40000)
    P_Logic.BodyVelocity.Parent = hrp
    
    P_Logic.BodyGyro = Instance.new("BodyGyro")
    P_Logic.BodyGyro.MaxTorque = Vector3.new(40000, 40000, 40000)
    P_Logic.BodyGyro.P = 1000
    P_Logic.BodyGyro.D = 50
    P_Logic.BodyGyro.Parent = hrp
    char.Humanoid.PlatformStand = true
    
    P_Logic.FlyConnection = RunService.RenderStepped:Connect(function()
        if not hrp or not P_Logic.Fly then return end
        local camCFrame = workspace.CurrentCamera.CFrame
        P_Logic.BodyGyro.CFrame = camCFrame
        local velocity = Vector3.new(0, 0, 0)
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then velocity = velocity + (camCFrame.LookVector * P_Logic.FlySpeed) end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then velocity = velocity + (camCFrame.LookVector * -P_Logic.FlySpeed) end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then velocity = velocity + (camCFrame.RightVector * -P_Logic.FlySpeed) end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then velocity = velocity + (camCFrame.RightVector * P_Logic.FlySpeed) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then velocity = velocity + Vector3.new(0, P_Logic.FlySpeed, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then velocity = velocity + Vector3.new(0, -P_Logic.FlySpeed, 0) end
        P_Logic.BodyVelocity.Velocity = velocity
    end)
end

local function StopFly()
    if P_Logic.FlyConnection then P_Logic.FlyConnection:Disconnect() end
    if P_Logic.BodyVelocity then P_Logic.BodyVelocity:Destroy() end
    if P_Logic.BodyGyro then P_Logic.BodyGyro:Destroy() end
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then LocalPlayer.Character.Humanoid.PlatformStand = false end
end

CreateToggle(PlayerTab, "Fly", false, function(state) P_Logic.Fly = state; if state then StartFly() else StopFly() end end)
CreateSlider(PlayerTab, "Fly Speed", 16, 500, 60, function(val) P_Logic.FlySpeed = val end)

CreateSection(PlayerTab, "Session & Performance")
CreateToggle(PlayerTab, "No Gameplay Paused (Anti-AFK)", false, function(state)
    P_Logic.AntiAFK = state
    if state then
        P_Logic.AfkConn = LocalPlayer.Idled:Connect(function()
            if P_Logic.AntiAFK then
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end
        end)
    else
        if P_Logic.AfkConn then P_Logic.AfkConn:Disconnect() end
    end
end)

CreateToggle(PlayerTab, "Auto Reconnect on Kick", false, function(state)
    P_Logic.AutoReconnect = state
    if state then
        P_Logic.ReconConn = game:GetService("CoreGui").RobloxPromptGui.promptOverlay.ChildAdded:Connect(function(child)
            if P_Logic.AutoReconnect and child.Name == "ErrorPrompt" then TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end
        end)
    else
        if P_Logic.ReconConn then P_Logic.ReconConn:Disconnect() end
    end
end)

local isTeleportQueued = false

CreateToggle(PlayerTab, "Auto Execute", false, function(state)
    if state then
        if not isTeleportQueued then
            local teleportCode = [[
    task.wait(2) 
    print("Injecting Arise Scripts...")
    
    loadstring(game:HttpGet("https://raw.githubusercontent.com/AriseScript/Main/refs/heads/main/Games"))()
]]
            local qot = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
            
            if qot then
                local success, err = pcall(function()
                    qot(teleportCode)
                end)

                if success then
                    isTeleportQueued = true
                    
                    task.spawn(function()
                        print("\n====================================")
                        print("[Arise] Auto-Execute Initialized...")
                        task.wait(0.5)
                        print("[Arise] Preparing server transfer data...")
                        task.wait(0.5)
                        print("[Arise] Arise Scripts successfully queued for teleport.")
                        task.wait(0.5)
                        print("[Arise] Almost there... waiting for game to teleport/rejoin.")
                        print("====================================\n")
                    end)
                    
                    sendNotification("Auto Exec ON", "Arise Scripts safely queued for next server.", 4, Theme.Accent)
                else
                    warn("[Arise] Queue failed: " .. tostring(err))
                    sendNotification("Error", "Failed to queue script.", 3, Color3.fromRGB(255, 60, 60))
                end
            else
                warn("[Arise] Your current executor does not support queue_on_teleport.")
                sendNotification("Error", "Executor lacks queue_on_teleport.", 4, Color3.fromRGB(255, 60, 60))
            end
        else
            sendNotification("Auto Exec", "Already queued safely. Won't lag the game.", 3, Theme.Accent)
        end
    else
        sendNotification("Auto Exec OFF", "Will not queue again this session.", 3, Theme.AccentDark)
    end
end)

CreateToggle(PlayerTab, "Disable 3D Rendering", false, function(state) RunService:Set3dRenderingEnabled(not state) end)

CreateToggle(PlayerTab, "FPS Boost", false, function(state)
    if state then
        for _, v in pairs(workspace:GetDescendants()) do
            if v:IsA("BasePart") then 
                if not Cache.Materials[v] then Cache.Materials[v] = v.Material end
                v.Material = Enum.Material.SmoothPlastic
            elseif v:IsA("Texture") or v:IsA("Decal") then 
                if not Cache.Textures[v] then Cache.Textures[v] = v.Transparency end
                v.Transparency = 1 
            end
        end
        game:GetService("Lighting").GlobalShadows = false
    else
        for obj, origMat in pairs(Cache.Materials) do if obj and obj.Parent then obj.Material = origMat end end
        for obj, origTrans in pairs(Cache.Textures) do if obj and obj.Parent then obj.Transparency = origTrans end end
        game:GetService("Lighting").GlobalShadows = true
    end
end)

CreateToggle(PlayerTab, "Ultra FPS Boost (Invisible Map)", false, function(state)
    if state then
        for _, v in pairs(workspace:GetDescendants()) do
            if v:IsA("BasePart") and not v.Parent:FindFirstChild("Humanoid") then
                if not Cache.Transparencies[v] then Cache.Transparencies[v] = v.Transparency end
                v.Transparency = 1 
            end
        end
    else
        for obj, origTrans in pairs(Cache.Transparencies) do 
            if obj and obj.Parent then obj.Transparency = origTrans end 
        end
    end
end)

end -- Player tab scope

-- ==========================================
-- ADVANCED DASHBOARD (INFORMATION TAB)
-- ==========================================
local DashLayout = Instance.new("UIListLayout", InfoTab)
DashLayout.SortOrder = Enum.SortOrder.LayoutOrder
DashLayout.Padding = UDim.new(0, 10)
DashLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local DashColors = {
    Panel = Color3.fromRGB(24, 22, 24), Border = Color3.fromRGB(45, 42, 45),
    Green = Color3.fromRGB(115, 235, 130), Muted = Color3.fromRGB(140, 135, 140), DarkPill = Color3.fromRGB(35, 30, 35)
}

local function CreatePanel(height, order)
    local p = Instance.new("Frame")
    p.Size = UDim2.new(1, -10, 0, height)
    p.BackgroundColor3 = DashColors.Panel
    p.LayoutOrder = order
    p.Parent = InfoTab
    Instance.new("UICorner", p).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", p)
    stroke.Color = DashColors.Border
    stroke.Thickness = 1
    return p
end

local Panel1 = CreatePanel(120, 1)
local WelcomeLbl = Instance.new("TextLabel", Panel1)
WelcomeLbl.Size = UDim2.new(0, 200, 0, 15)
WelcomeLbl.Position = UDim2.new(0, 15, 0, 15)
WelcomeLbl.BackgroundTransparency = 1
WelcomeLbl.Text = "WELCOME BACK"
WelcomeLbl.TextColor3 = DashColors.Muted
WelcomeLbl.Font = Enum.Font.Gotham
WelcomeLbl.TextSize = 10
WelcomeLbl.TextXAlignment = Enum.TextXAlignment.Left

local DisplayNameLbl = Instance.new("TextLabel", Panel1)
DisplayNameLbl.Size = UDim2.new(0.6, 0, 0, 25)
DisplayNameLbl.Position = UDim2.new(0, 15, 0, 30)
DisplayNameLbl.BackgroundTransparency = 1
DisplayNameLbl.Text = LocalPlayer.DisplayName
DisplayNameLbl.TextColor3 = Color3.new(1, 1, 1)
DisplayNameLbl.Font = Enum.Font.GothamBlack
DisplayNameLbl.TextSize = 22
DisplayNameLbl.TextXAlignment = Enum.TextXAlignment.Left

local UsernameLbl = Instance.new("TextLabel", Panel1)
UsernameLbl.Size = UDim2.new(0.6, 0, 0, 15)
UsernameLbl.Position = UDim2.new(0, 15, 0, 55)
UsernameLbl.BackgroundTransparency = 1
UsernameLbl.Text = "@" .. LocalPlayer.Name
UsernameLbl.TextColor3 = DashColors.Muted
UsernameLbl.Font = Enum.Font.Gotham
UsernameLbl.TextSize = 12
UsernameLbl.TextXAlignment = Enum.TextXAlignment.Left

local AvatarBust = Instance.new("ImageLabel", Panel1)
AvatarBust.Size = UDim2.new(0, 120, 0, 120)
AvatarBust.Position = UDim2.new(1, -130, 0, 0)
AvatarBust.BackgroundTransparency = 1
AvatarBust.Image = Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.AvatarBust, Enum.ThumbnailSize.Size420x420)
local PfpStroke = Instance.new("UIStroke", AvatarBust)
PfpStroke.Color = Theme.Accent
PfpStroke.Thickness = 1
PfpStroke.Transparency = 0
local AvaGrad = Instance.new("UIGradient", AvatarBust)
AvaGrad.Rotation = 90
AvaGrad.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0), NumberSequenceKeypoint.new(1, 1)})

local PillContainer = Instance.new("Frame", Panel1)
PillContainer.Size = UDim2.new(1, -150, 0, 24)
PillContainer.Position = UDim2.new(0, 15, 0, 80)
PillContainer.BackgroundTransparency = 1
local PillLayout = Instance.new("UIListLayout", PillContainer)
PillLayout.FillDirection = Enum.FillDirection.Horizontal
PillLayout.Padding = UDim.new(0, 8)

local VersionPill = Instance.new("Frame", PillContainer)
VersionPill.Size = UDim2.new(0, 60, 1, 0)
VersionPill.BackgroundColor3 = Color3.fromRGB(45, 25, 30)
Instance.new("UICorner", VersionPill).CornerRadius = UDim.new(0, 6)
local VersionTxt = Instance.new("TextLabel", VersionPill)
VersionTxt.Size = UDim2.new(1, 0, 1, 0)
VersionTxt.BackgroundTransparency = 1
VersionTxt.Text = "🐟 v1.0"
VersionTxt.TextColor3 = Color3.fromRGB(255, 100, 130)
VersionTxt.Font = Enum.Font.GothamBold
VersionTxt.TextSize = 11
VersionTxt.RichText = true
local MapPill = VersionTxt

local function CreateHideBtn(text, parent)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(0, 70, 1, 0)
    btn.BackgroundColor3 = DashColors.DarkPill
    btn.Text = text
    btn.TextColor3 = DashColors.Muted
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 11
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    return btn
end

local HideNameBtn = CreateHideBtn("👁 Name", PillContainer)
local isNameHidden = false
HideNameBtn.MouseButton1Click:Connect(function()
    isNameHidden = not isNameHidden
    if isNameHidden then
        HideNameBtn.Text = "🚫 Name"
        DisplayNameLbl.Text = "Hidden User"
        UsernameLbl.Text = "@hidden"
    else
        HideNameBtn.Text = "👁 Name"
        DisplayNameLbl.Text = LocalPlayer.DisplayName
        UsernameLbl.Text = "@" .. LocalPlayer.Name
    end
end)

local HideAvatarBtn = CreateHideBtn("👤 Avatar", PillContainer)
local isAvatarHidden = false
HideAvatarBtn.MouseButton1Click:Connect(function()
    isAvatarHidden = not isAvatarHidden
    if isAvatarHidden then
        HideAvatarBtn.Text = "🚫 Avatar"
        AvaGrad.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 1)})
        AvatarBust.ImageTransparency = 1
        PfpStroke.Transparency = 1
    else
        HideAvatarBtn.Text = "👤 Avatar"
        AvaGrad.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0), NumberSequenceKeypoint.new(1, 1)})
        AvatarBust.ImageTransparency = 0
        PfpStroke.Transparency = 0
    end
end)

local Panel2 = CreatePanel(130, 2)
local Div = Instance.new("Frame", Panel2)
Div.Size = UDim2.new(0, 1, 1, 0)
Div.Position = UDim2.new(0.5, 0, 0, 0)
Div.BackgroundColor3 = DashColors.Border
Div.BorderSizePixel = 0

local function CreateStatBlock(parent, title, xPos)
    local lbl = Instance.new("TextLabel", parent)
    lbl.Size = UDim2.new(0, 100, 0, 15)
    lbl.Position = UDim2.new(xPos, 15, 0, 10)
    lbl.BackgroundTransparency = 1
    lbl.Text = title
    lbl.TextColor3 = DashColors.Muted
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    
    local val = Instance.new("TextLabel", parent)
    val.Size = UDim2.new(0.5, -30, 0, 30)
    val.Position = UDim2.new(xPos, 15, 0, 25)
    val.BackgroundTransparency = 1
    val.Text = "0"
    val.TextColor3 = DashColors.Green
    val.Font = Enum.Font.GothamBlack
    val.TextSize = 24
    val.TextXAlignment = Enum.TextXAlignment.Left
    
    local chartContainer = Instance.new("Frame", parent)
    chartContainer.Size = UDim2.new(0.5, -30, 0, 20)
    chartContainer.Position = UDim2.new(xPos, 15, 0, 65)
    chartContainer.BackgroundTransparency = 1
    local clayout = Instance.new("UIListLayout", chartContainer)
    clayout.FillDirection = Enum.FillDirection.Horizontal
    clayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    clayout.Padding = UDim.new(0, 3)
    
    local bars = {}
    for i = 1, 20 do
        local bar = Instance.new("Frame", chartContainer)
        bar.Size = UDim2.new(0, 4, 0, math.random(4, 20))
        bar.BackgroundColor3 = (i == 20) and DashColors.Green or DashColors.DarkPill
        bar.BorderSizePixel = 0
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
        table.insert(bars, bar)
    end
    
    local subLbl = Instance.new("TextLabel", parent)
    subLbl.Size = UDim2.new(0, 100, 0, 15)
    subLbl.Position = UDim2.new(xPos, 15, 0, 95)
    subLbl.BackgroundTransparency = 1
    subLbl.Text = "..."
    subLbl.TextColor3 = Color3.new(1, 1, 1)
    subLbl.Font = Enum.Font.GothamBold
    subLbl.TextSize = 12
    subLbl.TextXAlignment = Enum.TextXAlignment.Left
    
    local subDesc = Instance.new("TextLabel", parent)
    subDesc.Size = UDim2.new(0, 100, 0, 15)
    subDesc.Position = UDim2.new(xPos, 15, 0, 110)
    subDesc.BackgroundTransparency = 1
    subDesc.Text = "LOADING"
    subDesc.TextColor3 = DashColors.Muted
    subDesc.Font = Enum.Font.Gotham
    subDesc.TextSize = 9
    subDesc.TextXAlignment = Enum.TextXAlignment.Left
    
    return val, subLbl, subDesc, bars
end

local FPSVal, PlrVal, PlrLbl, FPSBars = CreateStatBlock(Panel2, "⏱ FPS", 0)
PlrLbl.Text = "PLAYERS"
local PingVal, TimeVal, TimeLbl, PingBars = CreateStatBlock(Panel2, "📶 PING", 0.5)
TimeLbl.Text = "SESSION"

local Panel3 = CreatePanel(140, 3)
local GameIcon = Instance.new("ImageLabel", Panel3)
GameIcon.Size = UDim2.new(0, 40, 0, 40)
GameIcon.Position = UDim2.new(0, 15, 0, 15)
GameIcon.BackgroundColor3 = DashColors.DarkPill
GameIcon.Image = "rbxthumb://type=Asset&id=" .. game.PlaceId .. "&w=150&h=150"
Instance.new("UICorner", GameIcon).CornerRadius = UDim.new(0, 8)

local GameTitle = Instance.new("TextLabel", Panel3)
GameTitle.Size = UDim2.new(1, -70, 0, 20)
GameTitle.Position = UDim2.new(0, 65, 0, 15)
GameTitle.BackgroundTransparency = 1
GameTitle.Text = game.Name 
GameTitle.TextColor3 = Color3.new(1, 1, 1)
GameTitle.Font = Enum.Font.GothamBold
GameTitle.TextSize = 14
GameTitle.TextXAlignment = Enum.TextXAlignment.Left
GameTitle.TextTruncate = Enum.TextTruncate.AtEnd

task.spawn(function()
    pcall(function()
        local productInfo = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
        GameTitle.Text = productInfo.Name
        if productInfo.IconImageAssetId and productInfo.IconImageAssetId > 0 then
            GameIcon.Image = "rbxassetid://" .. productInfo.IconImageAssetId
        end
    end)
end)

local GameSub = Instance.new("TextLabel", Panel3)
GameSub.Size = UDim2.new(1, -70, 0, 15)
GameSub.Position = UDim2.new(0, 65, 0, 35)
GameSub.BackgroundTransparency = 1
GameSub.Text = "Place ID: " .. game.PlaceId
GameSub.TextColor3 = DashColors.Muted
GameSub.Font = Enum.Font.Gotham
GameSub.TextSize = 11
GameSub.TextXAlignment = Enum.TextXAlignment.Left

local BtnContainer = Instance.new("Frame", Panel3)
BtnContainer.Size = UDim2.new(1, -30, 0, 45)
BtnContainer.Position = UDim2.new(0, 15, 0, 65)
BtnContainer.BackgroundTransparency = 1
local BtnLayout = Instance.new("UIListLayout", BtnContainer)
BtnLayout.FillDirection = Enum.FillDirection.Horizontal
BtnLayout.Padding = UDim.new(0, 8)

local function CreateActionBtn(text, callback)
    local b = Instance.new("TextButton", BtnContainer)
    b.Size = UDim2.new(0.25, -6, 1, 0)
    b.BackgroundColor3 = DashColors.DarkPill
    b.Text = text
    b.TextColor3 = DashColors.Muted
    b.Font = Enum.Font.Gotham
    b.TextSize = 11
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    
    b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(50, 45, 50), TextColor3 = Color3.new(1,1,1)}):Play() end)
    b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.2), {BackgroundColor3 = DashColors.DarkPill, TextColor3 = DashColors.Muted}):Play() end)
    b.MouseButton1Click:Connect(callback)
    return b
end

CreateActionBtn("Rejoin", function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
CreateActionBtn("Hop", function()
    local Servers = HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Desc&limit=100"))
    for _, v in pairs(Servers.data) do
        if v.playing < v.maxPlayers and v.id ~= game.JobId then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, v.id, LocalPlayer)
            break
        end
    end
end)
CreateActionBtn("Lowest", function()
    local Servers = HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"))
    for _, v in pairs(Servers.data) do
        if v.playing > 0 and v.playing < v.maxPlayers and v.id ~= game.JobId then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, v.id, LocalPlayer)
            break
        end
    end
end)
CreateActionBtn("Copy Job ID", function()
    if setclipboard then
        setclipboard(game.JobId)
        sendNotification("Copied", "Job ID copied to clipboard!", 2)
    end
end)

local Footer = Instance.new("TextLabel", Panel3)
Footer.Size = UDim2.new(1, -30, 0, 15)
Footer.Position = UDim2.new(0, 15, 0, 115)
Footer.BackgroundTransparency = 1
Footer.Text = "Job: " .. string.sub(game.JobId, 1, 13) .. "...  •  Place: " .. game.PlaceId
Footer.TextColor3 = DashColors.Muted
Footer.Font = Enum.Font.Gotham
Footer.TextSize = 9
Footer.TextXAlignment = Enum.TextXAlignment.Left

-- ==========================================
-- REAL-TIME LOGIC (STATS & CHARTS)
-- ==========================================
local fpsHistory = {}
local pingHistory = {}
for i=1, 20 do table.insert(fpsHistory, 10); table.insert(pingHistory, 10) end

local scriptStartTime = tick()
local frameCount = 0
local lastUpdate = tick()

local actualMapName = game.Name
task.spawn(function()
    pcall(function()
        actualMapName = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
    end)
end)

getgenv().StatsThread = RunService.RenderStepped:Connect(function()
    frameCount = frameCount + 1
    if tick() - lastUpdate >= 1 then
        local currentFPS = frameCount
        frameCount = 0
        lastUpdate = tick()
        
        if InfoTab.Visible then
            local currentPing = 0
            pcall(function()
                local rawPing = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValueString()
                currentPing = math.round(tonumber(rawPing:match("%d+%.?%d*")) or 0)
            end)
            
            FPSVal.Text = tostring(currentFPS)
            PingVal.Text = tostring(currentPing) .. "ms"
            
            PlrVal.Text = tostring(#Players:GetPlayers()) .. "/" .. tostring(Players.MaxPlayers)
            
            local sessionTime = tick() - scriptStartTime
            local mins = math.floor(sessionTime / 60)
            local secs = math.floor(sessionTime % 60)
            if mins > 59 then
                TimeVal.Text = string.format("%dh %dm", math.floor(mins/60), mins%60)
            else
                TimeVal.Text = string.format("%dm %ds", mins, secs)
            end
            
            local mapName = actualMapName
            if string.len(mapName) > 12 then mapName = string.sub(mapName, 1, 10)..".." end
            MapPill.Text = "<font color='#909090'>Place</font> " .. mapName
            
            table.insert(fpsHistory, math.clamp(currentFPS, 10, 120))
            if #fpsHistory > 20 then table.remove(fpsHistory, 1) end
            
            table.insert(pingHistory, math.clamp(currentPing, 10, 300))
            if #pingHistory > 20 then table.remove(pingHistory, 1) end
            
            for i = 1, 20 do
                local fH = math.clamp((fpsHistory[i] / 120) * 20, 4, 20)
                TweenService:Create(FPSBars[i], TweenInfo.new(0.2), {Size = UDim2.new(0, 4, 0, fH)}):Play()
                
                local pH = math.clamp(20 - ((pingHistory[i] / 300) * 20), 4, 20)
                TweenService:Create(PingBars[i], TweenInfo.new(0.2), {Size = UDim2.new(0, 4, 0, pH)}):Play()
            end
        end
    end
end)

sendNotification("✅ Arise Scripts Loaded", "Framework initialized successfully.", 4, Theme.Accent)

-- ==========================================
-- DONATION / SUPPORT POPUP (SELF-TRIGGERING)
-- ==========================================
local DonationFrame = Instance.new("Frame")
DonationFrame.Size = UDim2.new(0, 0, 0, 0) 
DonationFrame.Position = UDim2.new(0.5, -175, 0.5, -90)
DonationFrame.BackgroundColor3 = Theme.Background
DonationFrame.BorderSizePixel = 0
DonationFrame.Visible = false
DonationFrame.ZIndex = 200 
DonationFrame.ClipsDescendants = true
DonationFrame.Parent = ScreenGui
Instance.new("UICorner", DonationFrame).CornerRadius = UDim.new(0, 10)

local DonoStroke = Instance.new("UIStroke", DonationFrame)
DonoStroke.Color = Theme.Accent
DonoStroke.Thickness = 1

local DonoTitle = Instance.new("TextLabel", DonationFrame)
DonoTitle.Size = UDim2.new(1, 0, 0, 30)
DonoTitle.Position = UDim2.new(0, 0, 0, 15)
DonoTitle.BackgroundTransparency = 1
DonoTitle.Text = "💖 Support Arise Scripts"
DonoTitle.TextColor3 = Color3.new(1, 1, 1)
DonoTitle.Font = Enum.Font.GothamBold
DonoTitle.TextSize = 18

local DonoDesc = Instance.new("TextLabel", DonationFrame)
DonoDesc.Size = UDim2.new(1, -40, 0, 40)
DonoDesc.Position = UDim2.new(0, 20, 0, 50)
DonoDesc.BackgroundTransparency = 1
DonoDesc.Text = "If you enjoy using the script, consider supporting me via PayPal! It helps keep updates rolling."
DonoDesc.TextColor3 = Theme.TextDim
DonoDesc.Font = Enum.Font.Gotham
DonoDesc.TextSize = 12
DonoDesc.TextWrapped = true

local CopyBtn = Instance.new("TextButton", DonationFrame)
CopyBtn.Size = UDim2.new(0, 180, 0, 35)
CopyBtn.Position = UDim2.new(0.5, -90, 0, 100)
CopyBtn.BackgroundColor3 = Theme.Element
CopyBtn.Text = "Copy PayPal Link"
CopyBtn.TextColor3 = Theme.Accent
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.TextSize = 13
Instance.new("UICorner", CopyBtn).CornerRadius = UDim.new(0, 6)

CopyBtn.MouseButton1Click:Connect(function()
    local paypalLink = "https://paypal.me/Alezeofficial" 
    if setclipboard then pcall(function() setclipboard(paypalLink) end) end
    local openUrlFunc = openurl or (syn and syn.openurl) or (fluxus and fluxus.openurl) or (getgenv and getgenv().openurl)
    if openUrlFunc then pcall(function() openUrlFunc(paypalLink) end) end
    CopyBtn.Text = "Link Copied!"
    task.wait(2)
    CopyBtn.Text = "Copy PayPal Link"
end)

local DonoClose = Instance.new("TextButton", DonationFrame)
DonoClose.Size = UDim2.new(0, 100, 0, 25)
DonoClose.Position = UDim2.new(0.5, -50, 0, 145)
DonoClose.BackgroundTransparency = 1
DonoClose.RichText = true
DonoClose.Text = "<u>Maybe Later</u>"
DonoClose.TextColor3 = Theme.TextDim
DonoClose.Font = Enum.Font.Gotham
DonoClose.TextSize = 11

DonoClose.MouseButton1Click:Connect(function()
    local shrink = TweenService:Create(DonationFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Size = UDim2.new(0, 0, 0, 0)})
    shrink:Play()
    shrink.Completed:Wait()
    DonationFrame:Destroy()
end)

task.spawn(function()
    while not MainFrame.Visible do task.wait(0.1) end
    task.wait(0.6)
    DonationFrame.Visible = true
    TweenService:Create(DonationFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 350, 0, 180)}):Play()
end)
