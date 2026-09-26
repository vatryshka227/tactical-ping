script_name('Tactical Ping')
script_author('afk111')

local sampev = require 'lib.samp.events'
local memory = require 'memory'
local vkeys = require 'vkeys'
local imgui = require 'mimgui'
local inicfg = require 'inicfg'
local encoding = require 'encoding'
local bit = require 'bit'

encoding.default = 'CP1251'
local u8 = encoding.UTF8

local iniFileName = 'TacticalPing.ini'
local cfg = inicfg.load({
    settings = {
        cooldown = 5.0,
        ping_lifetime = 8.0,
        render_dist = 700.0,
        ping_size = 8,
        ping_color = {0.2, 1.0, 0.2},
        notifications = true,
        notification_sound = true,
        dedupe_radius = 12.0
    }
}, iniFileName)

if type(cfg.settings.ping_color) ~= "table" then cfg.settings.ping_color = {0.2, 1.0, 0.2} end
if not cfg.settings.ping_size then cfg.settings.ping_size = 8 end
if cfg.settings.notifications == nil then cfg.settings.notifications = true end
if cfg.settings.notification_sound == nil then cfg.settings.notification_sound = true end
if not cfg.settings.dedupe_radius then cfg.settings.dedupe_radius = 12.0 end

local menu_state = imgui.new.bool(false)
local c_cooldown = imgui.new.float(cfg.settings.cooldown)
local c_lifetime = imgui.new.float(cfg.settings.ping_lifetime)
local c_render_dist = imgui.new.float(cfg.settings.render_dist)
local c_size = imgui.new.int(cfg.settings.ping_size)
local c_color = imgui.new.float[3](cfg.settings.ping_color[1], cfg.settings.ping_color[2], cfg.settings.ping_color[3])
local c_notifications = imgui.new.bool(cfg.settings.notifications)
local c_notification_sound = imgui.new.bool(cfg.settings.notification_sound)

local active_pings = {}
local last_ping_time = 0
local ping_font = nil
local myName = "Unknown"

imgui.OnInitialize(function()
    local style = imgui.GetStyle()
    local colors = style.Colors
    style.WindowRounding = 8.0
    style.FrameRounding = 6.0
    colors[imgui.Col.WindowBg] = imgui.ImVec4(0.08, 0.08, 0.08, 0.95)
    colors[imgui.Col.FrameBg] = imgui.ImVec4(0.15, 0.15, 0.15, 1.0)
    colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.25, 0.25, 0.25, 1.0)
    colors[imgui.Col.FrameBgActive] = imgui.ImVec4(0.3, 0.3, 0.3, 1.0)
    colors[imgui.Col.Text] = imgui.ImVec4(0.9, 0.9, 0.9, 1.0)
    colors[imgui.Col.Button] = imgui.ImVec4(0.2, 0.2, 0.2, 1.0)
    colors[imgui.Col.ButtonHovered] = imgui.ImVec4(0.3, 0.3, 0.3, 1.0)
    colors[imgui.Col.ButtonActive] = imgui.ImVec4(0.4, 0.4, 0.4, 1.0)
end)

imgui.OnFrame(function() return menu_state[0] end, function(player)
    imgui.SetNextWindowSize(imgui.ImVec2(420, 290), imgui.Cond.FirstUseEver)
    imgui.Begin(u8"Настройки Tactical Ping", menu_state, imgui.WindowFlags.NoCollapse)
    
    local changed = false
    
    imgui.PushItemWidth(180)
    if imgui.ColorEdit3(u8"Цвет метки", c_color) then changed = true end
    if imgui.SliderInt(u8"Размер", c_size, 4, 20) then changed = true end
    if imgui.SliderFloat(u8"Задержка (сек)", c_cooldown, 1.0, 15.0, "%.1f") then changed = true end
    if imgui.SliderFloat(u8"Время жизни (сек)", c_lifetime, 3.0, 30.0, "%.1f") then changed = true end
    if imgui.SliderFloat(u8"Дальность (м)", c_render_dist, 100.0, 2000.0, "%.0f") then changed = true end
    if imgui.Checkbox("Notifications for new pings", c_notifications) then changed = true end
    if imgui.Checkbox("Notification sound", c_notification_sound) then changed = true end
    imgui.PopItemWidth()
    
    if changed then
        cfg.settings.cooldown = c_cooldown[0]
        cfg.settings.ping_lifetime = c_lifetime[0]
        cfg.settings.render_dist = c_render_dist[0]
        cfg.settings.ping_size = c_size[0]
        cfg.settings.ping_color = {c_color[0], c_color[1], c_color[2]}
        cfg.settings.notifications = c_notifications[0]
        cfg.settings.notification_sound = c_notification_sound[0]
        inicfg.save(cfg, iniFileName)
    end
    
    imgui.End()
end)

function get_dx_ping_color()
    local r = math.floor(cfg.settings.ping_color[1] * 255)
    local g = math.floor(cfg.settings.ping_color[2] * 255)
    local b = math.floor(cfg.settings.ping_color[3] * 255)
    return bit.bor(0xFF000000, bit.lshift(r, 16), bit.lshift(g, 8), b)
end

function generate_anti_flood_string(length)
    local str = ""
    for i = 1, length do
        str = str .. string.char(math.random(97, 122))
    end
    return str
end

local function notify_ping(author, x, y, z)
    if cfg.settings.notifications then
        local px, py, pz = getCharCoordinates(PLAYER_PED)
        local dist = getDistanceBetweenCoords3d(px, py, pz, x, y, z)
        sampAddChatMessage(string.format("{00FF88}[Tactical Ping] {FFFFFF}%s поставил метку. Расстояние: {FFFF00}%.0f м", tostring(author), dist), -1)
    end
    if cfg.settings.notification_sound then
        addOneOffSound(0.0, 0.0, 0.0, 1056)
    end
end

local function find_duplicate_ping(x, y, z)
    local radius = tonumber(cfg.settings.dedupe_radius) or 12.0
    for i = #active_pings, 1, -1 do
        local ping = active_pings[i]
        if getDistanceBetweenCoords3d(ping.x, ping.y, ping.z, x, y, z) <= radius then
            return ping
        end
    end
    return nil
end

local function add_ping(x, y, z, author, local_ping)
    local duplicate = find_duplicate_ping(x, y, z)
    if duplicate then
        if not duplicate.pinned then duplicate.time = os.clock() end
        return duplicate, false
    end
    local blip = addBlipForCoord(x, y, z)
    local ping = {x = x, y = y, z = z, time = os.clock(), author = author, blip = blip, pinned = false}
    table.insert(active_pings, ping)
    if not local_ping then notify_ping(author, x, y, z) end
    return ping, true
end

function clear_all_pings()
    for i = #active_pings, 1, -1 do
        if active_pings[i].blip then removeBlip(active_pings[i].blip) end
        table.remove(active_pings, i)
    end
    sampAddChatMessage("{00FF88}[Tactical Ping] {FFFFFF}Все метки очищены.", -1)
end

function toggle_last_ping_pin()
    local ping = active_pings[#active_pings]
    if not ping then
        sampAddChatMessage("{FFAA00}[Tactical Ping] {FFFFFF}Нет активных меток.", -1)
        return
    end
    ping.pinned = not ping.pinned
    if ping.pinned then
        sampAddChatMessage("{00FF88}[Tactical Ping] {FFFFFF}Последняя метка закреплена и не исчезнет по таймеру.", -1)
    else
        ping.time = os.clock()
        sampAddChatMessage("{00FF88}[Tactical Ping] {FFFFFF}Закрепление снято.", -1)
    end
end

function place_ping_marker()
    local current_time = os.clock()
    local time_passed = current_time - last_ping_time
    
    if time_passed >= cfg.settings.cooldown then
        local start_x, start_y
        
        if memory.getuint8(0xB6F1A8) == 53 then
            start_x, start_y = convertGameScreenCoordsToWindowScreenCoords(339.5, 179.2)
        else
            local resX, resY = getScreenResolution()
            start_x, start_y = resX / 2, resY / 2
        end
        
        local cam_x, cam_y, cam_z = getActiveCameraCoordinates()
        local cross_x, cross_y, cross_z = convertScreenCoordsToWorld3D(start_x, start_y, cfg.settings.render_dist)
        
        local result, pointer = processLineOfSight(cam_x, cam_y, cam_z, cross_x, cross_y, cross_z, true, true, false, true, true, false, false)
        
        local tx, ty, tz
        if result and pointer then
            tx, ty, tz = pointer.pos[1], pointer.pos[2], pointer.pos[3] + 0.5
        else
            tx, ty, tz = cross_x, cross_y, cross_z
        end
        
        local send_x = math.floor(tx)
        local send_y = math.floor(ty)
        local send_z = math.floor(tz)
        local random_letters = generate_anti_flood_string(math.random(2, 3))

        add_ping(tx, ty, tz, myName, true)

        sampAddChatMessage(string.format("{00FF00}[Tactical Ping] {FFFFFF}Marker sent via {FFFF00}/fb {FFFFFF}[Point: %d, %d, %d]", send_x, send_y, send_z), -1)
        -- TPING marks coordinate messages so ordinary faction chat is ignored.
        sampSendChat(string.format("/fb TPING %d %d %d %s", send_x, send_y, send_z, random_letters))
        
        last_ping_time = current_time
    else
        local time_left = cfg.settings.cooldown - time_passed
        sampAddChatMessage(string.format("{FF0000}[Tactical Ping] {FFFFFF}Подождите %.1f сек. перед следующей меткой!", time_left), -1)
    end
end

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end
    
    ping_font = renderCreateFont('Tahoma', 11, 5)
    math.randomseed(os.time() + tonumber(tostring({}):sub(8)))
    
    local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    myName = sampGetPlayerNickname(myId)
    
    sampAddChatMessage("{00FF00}[Tactical Ping] {FFFFFF}Скрипт загружен! Меню: {FFFF00}/pmenu {FFFFFF}| Закрепить: {FFFF00}/ppin {FFFFFF}| Очистить: {FFFF00}/pclear", -1)
    
    sampRegisterChatCommand('ping', function()
        place_ping_marker()
    end)
    
    sampRegisterChatCommand('pmenu', function()
        menu_state[0] = not menu_state[0]
    end)

    sampRegisterChatCommand('ppin', function()
        toggle_last_ping_pin()
    end)

    sampRegisterChatCommand('pclear', function()
        clear_all_pings()
    end)

    while true do 
        wait(0) 
        
        if wasKeyPressed(vkeys.VK_MBUTTON) and not isPauseMenuActive() and not sampIsCursorActive() then
            place_ping_marker()
        end
        
        for i = #active_pings, 1, -1 do
            local ping = active_pings[i]
            if not ping.pinned and os.clock() - ping.time > cfg.settings.ping_lifetime then
                if ping.blip then removeBlip(ping.blip) end
                table.remove(active_pings, i)
            else
                if isPointOnScreen(ping.x, ping.y, ping.z, 0.0) then
                    local sx, sy = convert3DCoordsToScreen(ping.x, ping.y, ping.z)
                    if sx and sy then
                        local px, py, pz = getCharCoordinates(PLAYER_PED)
                        local dist = getDistanceBetweenCoords3d(px, py, pz, ping.x, ping.y, ping.z)
                        
                        local p_sz = cfg.settings.ping_size
                        local render_color = get_dx_ping_color()
                        
                        renderDrawBox(sx - (p_sz/2), sy - (p_sz/2), p_sz, p_sz, render_color)
                        renderDrawBox(sx - (p_sz/4), sy - (p_sz/4), p_sz/2, p_sz/2, 0xFFFFFFFF)
                        
                        local pin_mark = ping.pinned and " [PIN]" or ""
                        local text = string.format("ЦЕЛЬ [%.1fм]\nОт: %s%s", dist, ping.author, pin_mark)
                        renderFontDrawText(ping_font, text, sx + p_sz + 4, sy - 12, render_color)
                    end
                end
            end
        end
    end
end

function sampev.onServerMessage(color, text)
    local clean_text = text:gsub("{.-}", "")
    
    if clean_text:find("%[Ошибка%] Вы не состоите в группе!") then
        for i = #active_pings, 1, -1 do
            if active_pings[i].author == "Я (Ты)" and (os.clock() - active_pings[i].time) < 3.0 then
                if active_pings[i].blip then removeBlip(active_pings[i].blip) end
                table.remove(active_pings, i)
                sampAddChatMessage("{FF0000}[Tactical Ping] {FFFFFF}Отмена: Вы не состоите в группе!", -1)
                break
            end
        end
        return
    end
    
    -- Expected organization chat: [F] ... Nick_Name[359]: (( TPING x y z token ))
    -- Only messages containing TPING are treated as map markers.
    local author, tx_str, ty_str, tz_str = clean_text:match("([%w_]+)%[%d+%]:.*TPING%s+([-]?%d+)%s+([-]?%d+)%s+([-]?%d+)%s+[%a]+")

    if author and tx_str and ty_str and tz_str then
        if author ~= myName then
            local tx, ty, tz_parsed = tonumber(tx_str), tonumber(ty_str), tonumber(tz_str)
            if tx and ty and tz_parsed then
                local tz = getGroundZFor3dCoord(tx, ty, 300.0)
                if tz == 0.0 then
                    tz = tz_parsed
                end

                add_ping(tx, ty, tz + 0.5, author, false)
            end
        end
    end
end

function onScriptTerminate(script, quitGame)
    if script == thisScript() then
        for i, ping in ipairs(active_pings) do
            if ping.blip then removeBlip(ping.blip) end
        end
    end
end
