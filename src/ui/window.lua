local Config = require("src.config")
local Screen = require("src.utils.screen")
local Pal = require("src.utils.palette")
local U = require("src.utils.util")

local Window = {
    drag = nil, pressed = nil, captured = false,
    maximized = false, restore = nil, hwnd = nil,
    mx = -1, my = -1,
}
local BAR = Config.ui.chrome

local ffi
local user32
local sdl
if Screen.chromeOn then
    local found, lib = pcall(require, "ffi")
    if found then
        ffi = lib
        pcall(ffi.cdef, [[
            typedef struct { long left; long top; long right; long bottom; } RECT;
            typedef struct { long x; long y; } POINT;
            typedef struct { unsigned long cbSize; RECT rcMonitor; RECT rcWork; unsigned long dwFlags; } MONITORINFO;
            void* GetActiveWindow(void);
            void* FindWindowA(const char* class, const char* title);
            int IsWindow(void* hwnd);
            int ShowWindow(void* hwnd, int command);
            int GetWindowRect(void* hwnd, RECT* rect);
            int GetCursorPos(POINT* point);
            short GetAsyncKeyState(int key);
            void* MonitorFromWindow(void* hwnd, unsigned int flags);
            void* MonitorFromPoint(POINT point, unsigned int flags);
            int GetMonitorInfoW(void* monitor, MONITORINFO* info);
            int SetWindowPos(void* hwnd, void* after, int x, int y, int w, int h, unsigned int flags);
            void* CreateWindowExA(unsigned int exStyle, const char* class, const char* name, unsigned int style,
                int x, int y, int w, int h, void* parent, void* menu, void* instance, void* param);
            int SetLayeredWindowAttributes(void* hwnd, unsigned int color, unsigned char alpha, unsigned int flags);
            int SystemParametersInfoW(unsigned int, unsigned int, void*, unsigned int);
            typedef struct SDL_Window SDL_Window;
            SDL_Window* SDL_GetKeyboardFocus(void);
            SDL_Window* SDL_GetMouseFocus(void);
            SDL_Window* SDL_GetWindowFromID(unsigned int id);
            const char* SDL_GetWindowTitle(SDL_Window* window);
            void SDL_SetWindowSize(SDL_Window* window, int w, int h);
            void SDL_SetWindowPosition(SDL_Window* window, int x, int y);
        ]])
        local loaded, libUser = pcall(ffi.load, "user32")
        if loaded then user32 = libUser end
        local loadedSDL, libSDL = pcall(ffi.load, "SDL2")
        if loadedSDL then sdl = libSDL end
    end
end

local SWP_NOSIZE = 0x0001
local SWP_NOZORDER = 0x0004
local SWP_NOACTIVATE = 0x0010
local SWP_SHOWWINDOW = 0x0040
local WS_POPUP = 0x80000000
local SS_GRAYRECT = 0x00000005
local WS_EX_LAYERED = 0x00080000
local WS_EX_TOOLWINDOW = 0x00000080
local WS_EX_TOPMOST = 0x00000008
local WS_EX_TRANSPARENT = 0x00000020
local WS_EX_NOACTIVATE = 0x08000000
local LWA_ALPHA = 0x00000002
local SW_HIDE = 0
local MONITOR_DEFAULTTONEAREST = 2
local SPI_GETWORKAREA = 0x0030
local MOVE_FLAGS = SWP_NOSIZE + SWP_NOZORDER + SWP_NOACTIVATE
local OVERLAY_STYLE = WS_POPUP + SS_GRAYRECT
local OVERLAY_EXSTYLE = WS_EX_LAYERED + WS_EX_TOOLWINDOW + WS_EX_TOPMOST + WS_EX_TRANSPARENT + WS_EX_NOACTIVATE
local VK_LBUTTON = 0x01
local DRAG_THRESHOLD = 3
local DOUBLE_CLICK_TIME = 0.35
local DOUBLE_CLICK_DIST = 8

local function enabled()
    return Screen.chromeH and Screen.chromeH > 0
end

local function buttons()
    local x = love.graphics.getWidth() - BAR.buttonW * 3
    return {
        { id = "min", x = x, y = 0, w = BAR.buttonW, h = BAR.height },
        { id = "max", x = x + BAR.buttonW, y = 0, w = BAR.buttonW, h = BAR.height },
        { id = "close", x = x + BAR.buttonW * 2, y = 0, w = BAR.buttonW, h = BAR.height },
    }
end

local function windowHandle()
    if not user32 then return nil end
    if Window.hwnd and user32.IsWindow(Window.hwnd) == 0 then Window.hwnd = nil end
    if not Window.hwnd then
        local hwnd = user32.FindWindowA(nil, Config.app.name)
        if hwnd == nil or hwnd == ffi.NULL then hwnd = user32.GetActiveWindow() end
        Window.hwnd = hwnd
    end
    if Window.hwnd == nil or Window.hwnd == ffi.NULL then return nil end
    return Window.hwnd
end

local function screenMouse()
    if ffi and user32 then
        local point = ffi.new("POINT")
        if user32.GetCursorPos(point) ~= 0 then
            return tonumber(point.x), tonumber(point.y)
        end
    end
    local wx, wy = love.window.getPosition()
    local mx, my = love.mouse.getPosition()
    return wx + mx, wy + my
end

local function leftDown()
    if ffi and user32 then return user32.GetAsyncKeyState(VK_LBUTTON) < 0 end
    return love.mouse.isDown(1)
end

local function windowPosition()
    if ffi and user32 then
        local hwnd = windowHandle()
        if hwnd then
            local rect = ffi.new("RECT")
            if user32.GetWindowRect(hwnd, rect) ~= 0 then
                return tonumber(rect.left), tonumber(rect.top)
            end
        end
    end
    return love.window.getPosition()
end

local function rectArea(rect)
    local x, y = tonumber(rect.left), tonumber(rect.top)
    return { x = x, y = y, w = tonumber(rect.right) - x, h = tonumber(rect.bottom) - y }
end

local function desktopWork()
    local rect = ffi.new("RECT")
    if user32 and user32.SystemParametersInfoW(SPI_GETWORKAREA, 0, rect, 0) ~= 0 then
        return rectArea(rect)
    end
    local w, h = love.window.getDesktopDimensions()
    return { x = 0, y = 0, w = w, h = h }
end

local function monitorWork(monitor)
    if not (ffi and user32) or monitor == nil or monitor == ffi.NULL then return desktopWork() end
    local info = ffi.new("MONITORINFO")
    info.cbSize = ffi.sizeof(info)
    if user32.GetMonitorInfoW(monitor, info) == 0 then return desktopWork() end
    return rectArea(info.rcWork)
end

local function windowWork()
    local hwnd = windowHandle()
    if not (ffi and user32) or not hwnd then return desktopWork() end
    return monitorWork(user32.MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST))
end

local function cursorWork(x, y)
    if not (ffi and user32) then return desktopWork() end
    return monitorWork(user32.MonitorFromPoint(ffi.new("POINT", x, y), MONITOR_DEFAULTTONEAREST))
end

local function sdlWindow()
    if not sdl then return nil end
    local win = sdl.SDL_GetKeyboardFocus()
    if win == nil or win == ffi.NULL then win = sdl.SDL_GetMouseFocus() end
    if win ~= nil and win ~= ffi.NULL then return win end
    for id = 1, 64 do
        win = sdl.SDL_GetWindowFromID(id)
        if win ~= nil and win ~= ffi.NULL then
            local title = sdl.SDL_GetWindowTitle(win)
            if title ~= nil and ffi.string(title) == Config.app.name then return win end
        end
    end
end

local function moveWindow(x, y)
    local hwnd = windowHandle()
    if hwnd and user32 then
        user32.SetWindowPos(hwnd, ffi.NULL, x, y, 0, 0, MOVE_FLAGS)
    else
        love.window.setPosition(x, y)
    end
end

local function placeWindow(x, y, w, h)
    local win = sdlWindow()
    if win then
        sdl.SDL_SetWindowSize(win, w, h)
        sdl.SDL_SetWindowPosition(win, x, y)
    else
        local chrome = Screen.chromeOn and BAR.height or 0
        local ok = pcall(love.window.setMode, w, h, {
            fullscreen = false,
            borderless = Screen.chromeOn,
            resizable = not Screen.chromeOn,
            vsync = 1,
            minwidth = Config.window.minWidth,
            minheight = Config.window.minHeight + chrome,
        })
        if ok then pcall(love.window.setPosition, x, y) end
    end
    Screen.resize(w, h)
end

local function hideSnap()
    Window.snapArea = nil
    if Window.overlay and Window.snapShown and user32 then
        user32.ShowWindow(Window.overlay, SW_HIDE)
        Window.snapShown = false
    end
end

local function showSnap(area)
    if not (ffi and user32) then return end
    if not Window.overlay then
        local hwnd = user32.CreateWindowExA(OVERLAY_EXSTYLE, "STATIC", "", OVERLAY_STYLE,
            0, 0, 0, 0, ffi.NULL, ffi.NULL, ffi.NULL, ffi.NULL)
        if hwnd == nil or hwnd == ffi.NULL then return end
        user32.SetLayeredWindowAttributes(hwnd, 0, BAR.snapAlpha, LWA_ALPHA)
        Window.overlay = hwnd
    end
    local inset = BAR.snapInset
    local topmost = ffi.cast("void*", -1)
    user32.SetWindowPos(Window.overlay, topmost, area.x + inset, area.y + inset,
        area.w - inset * 2, area.h - inset * 2, SWP_NOACTIVATE + SWP_SHOWWINDOW)
    Window.snapShown = true
    Window.snapArea = area
end

local function updateSnap(sx, sy)
    local drag = Window.drag
    if not drag or not drag.moved then hideSnap(); return end
    local area = cursorWork(sx, sy)
    if sy <= area.y + BAR.snap then
        showSnap(area)
    else
        hideSnap()
    end
end

local function releaseDragToNormal(drag, sx, sy)
    local restore = Window.restore
    if not restore then
        Window.maximized = false
        return
    end
    Window.restore = nil
    Window.maximized = false
    placeWindow(restore.x, restore.y, restore.w, restore.h)
    local nx = math.floor(sx - drag.ratio * restore.w)
    local ny = math.floor(sy - BAR.height / 2)
    moveWindow(nx, ny)
    drag.sx, drag.sy = sx, sy
    drag.wx, drag.wy = nx, ny
    drag.x, drag.y = nx, ny
    drag.moved = true
    drag.maximized = false
end

function Window:reset()
    self.drag, self.pressed, self.captured = nil, nil, false
    self.maximized, self.restore = false, nil
    self.mx, self.my = -1, -1
    hideSnap()
end

function Window.setVisible(visible)
    local hwnd = windowHandle()
    if hwnd then
        if not visible then hideSnap() end
        user32.ShowWindow(hwnd, visible and 5 or 0)
    end
end

function Window:buttonAt(x, y)
    for _, button in ipairs(buttons()) do
        if U.inRect(x, y, button.x, button.y, button.w, button.h) then
            return button.id
        end
    end
end

function Window:beginDrag()
    local sx, sy = screenMouse()
    local wx, wy = windowPosition()
    local width = math.max(1, love.graphics.getWidth())
    self.drag = {
        sx = sx, sy = sy, wx = wx, wy = wy, x = wx, y = wy,
        maximized = self.maximized, moved = false,
        ratio = U.clamp((sx - wx) / width, 0.1, 0.9),
    }
end

function Window:finishDrag()
    if not self.drag then return end
    local area = self.snapArea
    self.drag = nil
    hideSnap()
    if area then self:maximize(area) end
end

function Window:update()
    if not enabled() then
        if self.drag or self.overlay then self:reset() end
        self.mx, self.my = -1, -1
        return
    end

    self.mx, self.my = love.mouse.getPosition()
    local down = leftDown()
    local drag = self.drag
    if drag then
        if not down then
            self:finishDrag()
        else
            local sx, sy = screenMouse()
            local moved = math.abs(sx - drag.sx) + math.abs(sy - drag.sy)
            if drag.maximized and moved >= DRAG_THRESHOLD then
                releaseDragToNormal(drag, sx, sy)
                self.drag = drag
            end
            if not drag.maximized then
                local x = drag.wx + sx - drag.sx
                local y = drag.wy + sy - drag.sy
                if x ~= drag.x or y ~= drag.y then
                    drag.x, drag.y = x, y
                    drag.moved = true
                    moveWindow(x, y)
                end
                updateSnap(sx, sy)
            end
        end
    end
    if not down then self.pressed, self.captured = nil, false end
end

function Window:mousepressed(x, y, button)
    if not enabled() or y >= BAR.height then return false end
    self.captured = true
    if button ~= 1 then return true end

    local id = self:buttonAt(x, y)
    if id then
        self.pressed = id
        return true
    end

    local now = love.timer.getTime()
    local last = self.last
    self.last = { t = now, x = x, y = y }
    if last and now - last.t <= DOUBLE_CLICK_TIME
        and math.abs(x - last.x) < DOUBLE_CLICK_DIST and math.abs(y - last.y) < DOUBLE_CLICK_DIST then
        self.last = nil
        self:toggleMax()
        return true
    end

    self:beginDrag()
    return true
end

function Window:mousereleased(x, y, button)
    if not self.captured then return false end
    self.captured = false

    local id = self.pressed
    self.pressed = nil
    self:finishDrag()
    if button == 1 and id and self:buttonAt(x, y) == id then self:activate(id) end
    return true
end

function Window:activate(id)
    if id == "close" then
        love.event.quit()
    elseif id == "min" then
        love.window.minimize()
    elseif id == "max" then
        self:toggleMax()
    end
end

function Window:maximize(area)
    if self.maximized then return end
    local x, y = windowPosition()
    local w, h = love.graphics.getDimensions()
    local target = area or windowWork()
    self.restore = { x = x, y = y, w = w, h = h }
    self.maximized = true
    self.drag = nil
    hideSnap()
    placeWindow(target.x, target.y, target.w, target.h)
end

function Window:restoreMax()
    local restore = self.restore
    if not restore then return end
    self.restore, self.maximized, self.drag = nil, false, nil
    hideSnap()
    placeWindow(restore.x, restore.y, restore.w, restore.h)
end

function Window:toggleMax()
    if self.maximized then self:restoreMax() else self:maximize() end
end

local function drawIcon(id, cx, cy, maximized)
    love.graphics.setLineWidth(2)
    Pal.set(Pal.C)
    if id == "min" then
        love.graphics.rectangle("fill", cx - 6, cy + 5, 12, 2)
    elseif id == "max" and maximized then
        love.graphics.rectangle("line", cx - 2, cy - 6, 8, 8)
        love.graphics.rectangle("line", cx - 6, cy - 2, 8, 8)
    elseif id == "max" then
        love.graphics.rectangle("line", cx - 5, cy - 5, 10, 10)
    elseif id == "close" then
        love.graphics.line(cx - 5, cy - 5, cx + 5, cy + 5)
        love.graphics.line(cx - 5, cy + 5, cx + 5, cy - 5)
    end
    love.graphics.setLineWidth(1)
end

function Window:draw()
    if not enabled() then return end

    local w = love.graphics.getWidth()
    Pal.set(Pal.N)
    love.graphics.rectangle("fill", 0, 0, w, BAR.height)
    Pal.set(Pal.I)
    love.graphics.rectangle("fill", 0, BAR.height - 2, w, 2)

    local hover = self:buttonAt(self.mx or -1, self.my or -1)
    for _, button in ipairs(buttons()) do
        if hover == button.id then
            Pal.set(self.pressed == button.id and Pal.I or Pal.B)
            love.graphics.rectangle("fill", button.x + 2, 2, button.w - 4, BAR.height - 4)
        end
        drawIcon(button.id, button.x + button.w / 2, button.y + button.h / 2, self.maximized)
    end
end

return Window
