script_name('Tactical Ping')
script_author('afk111')

local sampev = require 'lib.samp.events'
local memory = require 'memory'
local vkeys = require 'vkeys'
local imgui = require 'mimgui'
local inicfg = require 'inicfg'
local bit = require 'bit'
local encoding = require 'encoding'

encoding.default = 'CP1251'
local u8 = encoding.UTF8

local function cp(s) return u8:decode(s) end

-- ============ АВТООБНОВЛЕНИЕ ============
local SCRIPT_VERSION = "1.0.0"
local UPDATE_URL_VERSION = "https://raw.githubusercontent.com/vatryshka227/tactical-ping/refs/heads/main/versions.txt"
local UPDATE_URL_SCRIPT  = "https://raw.githubusercontent.com/vatryshka227/tactical-ping/main/TacticalPing_FB.lua"
local UPDATE_TMP = getWorkingDirectory() .. "\\TacticalPing_update.lua"

local update_state = {
    checking = false,
    downloading = false,
    status = "Нажмите кнопку для проверки",
    remote_version = nil
}

local function parse_version(v)
    if not v then return 0, 0, 0 end
    local a, b, c = v:match("(%d+)%.(%d+)%.(%d+)")
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

local function is_newer(remote, local_)
    local r1, r2, r3 = parse_version(remote)
    local l1, l2, l3 = parse_version(local_)
    if r1 ~= l1 then return r1 > l1 end
    if r2 ~= l2 then return r2 > l2 end
    return r3 > l3
end

local function check_and_update(silent)
    if update_state.checking or update_state.downloading then return end
    update_state.checking = true
    update_state.status = "Проверка обновлений..."

    lua_thread.create(function()
        local tmp_ver = getWorkingDirectory() .. "\\tp_ver.tmp"
        if doesFileExist(tmp_ver) then os.remove(tmp_ver) end

        downloadUrlToFile(UPDATE_URL_VERSION, tmp_ver)

        local t = 0
        while not doesFileExist(tmp_ver) and t < 8000 do
            wait(100); t = t + 100
        end

        if not doesFileExist(tmp_ver) then
            update_state.checking = false
            update_state.status = "Ошибка: не удалось скачать versions.txt"
            if not silent then
                sampAddChatMessage(cp("{FF0000}[Tactical Ping] {FFFFFF}Не удалось проверить обновления (версия)."), -1)
            end
            return
        end

        local f = io.open(tmp_ver, "r")
        local remote_ver = f and f:read("*a") or ""
        if f then f:close() end
        os.remove(tmp_ver)
        remote_ver = remote_ver:gsub("%s+", "")

        update_state.remote_version = remote_ver
        update_state.checking = false

        if not is_newer(remote_ver, SCRIPT_VERSION) then
            update_state.status = "Актуальная версия (" .. SCRIPT_VERSION .. ")"
            if not silent then
                sampAddChatMessage(cp(string.format("{00FF88}[Tactical Ping] {FFFFFF}У вас последняя версия: {FFFF00}%s", SCRIPT_VERSION)), -1)
            end
            return
        end

        update_state.downloading = true
        update_state.status = "Скачивание " .. remote_ver .. "..."
        sampAddChatMessage(cp(string.format("{00FF88}[Tactical Ping] {FFFFFF}Найдена новая версия {FFFF00}%s{FFFFFF}. Скачиваю...", remote_ver)), -1)

        if doesFileExist(UPDATE_TMP) then os.remove(UPDATE_TMP) end
        downloadUrlToFile(UPDATE_URL_SCRIPT, UPDATE_TMP)

        t = 0
        while not doesFileExist(UPDATE_TMP) and t < 20000 do
            wait(100); t = t + 100
        end

        if not doesFileExist(UPDATE_TMP) then
            update_state.downloading = false
            update_state.status = "Ошибка скачивания скрипта"
            sampAddChatMessage(cp("{FF0000}[Tactical Ping] {FFFFFF}Не удалось скачать обновление."), -1)
            return
        end

        local uf = io.open(UPDATE_TMP, "r")
        local content = uf and uf:read("*a") or ""
        if uf then uf:close() end
        if #content < 500 then
            os.remove(UPDATE_TMP)
            update_state.downloading = false
            update_state.status = "Ошибка: файл повреждён"
            sampAddChatMessage(cp("{FF0000}[Tactical Ping] {FFFFFF}Скачанный файл повреждён или пуст."), -1)
            return
        end

        local this_file = thisScript().path
        local outf = io.open(this_file, "w")
        if outf then
            outf:write(content)
            outf:close()
        end
        os.remove(UPDATE_TMP)

        update_state.downloading = false
        update_state.status = "Обновлено до " .. remote_ver .. ". Введите /mreload"
        sampAddChatMessage(cp(string.format("{00FF88}[Tactical Ping] {FFFFFF}Обновлено до {FFFF00}%s{FFFFFF}. Введите {FFFF00}/mreload TacticalPing_FB", remote_ver)), -1)
    end)
end
-- ============ КОНЕЦ АВТООБНОВЛЕНИЯ ============

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
    imgui.SetNextWindowSize(imgui.ImVec2(420, 400), imgui.Cond.FirstUseEver)
    imgui.Begin("Настройки Tactical Ping", menu_state, imgui.WindowFlags.NoCollapse)

    local changed = false

    imgui.PushItemWidth(180)
    if imgui.ColorEdit3("Цвет метки", c_color) then changed = true end
    if imgui.SliderInt("Размер", c_size, 4, 20) then changed = true end
    if imgui.SliderFloat("Задержка (сек)", c_cooldown, 1.0, 15.0, "%.1f") then changed = true end
    if imgui.SliderFloat("Время жизни (сек)", c_lifetime, 3.0, 30.0, "%.1f") then changed = true end
    if imgui.SliderFloat("Дальность (м)", c_render_dist, 100.0, 2000.0, "%.0f") then changed = true end
    if imgui.Checkbox("Уведомления о новых метках", c_notifications) then changed = true end
    if imgui.Checkbox("Звук уведомления", c_notification_sound) then changed = true end
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

    -- ===== Блок автообновления =====
    imgui.Separator()
    imgui.Text("Версия: " .. SCRIPT_VERSION)
    if update_state.remote_version and update_state.remote_version ~= "" then
        imgui.Text("На GitHub: " .. update_state.remote_version)
    end
    imgui.TextColored(imgui.ImVec4(0.8, 0.8, 0.8, 1.0), update_state.status)

    if update_state.checking or update_state.downloading then
        imgui.TextColored(imgui.ImVec4(1.0, 0.8, 0.2, 1.0), "Подождите...")
    else
        if imgui.Button("Проверить обновления", imgui.ImVec2(200, 0)) then
            check_and_update(false)
        end
    end
    -- ===== Конец блока автообновления =====

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
        sampAddChatMessage(cp(string.format("{00FF88}[Tactical Ping] {FFFFFF}%s поставил метку. Расстояние: {FFFF00}%.0f м", tostring(author), dist)), -1)
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

    -- SA-MP blip: addSpriteBlipForCoord(x, y, z, icon)
    -- icon 41 = radar_waypoint (стрелка цели)
    local blip = addSpriteBlipForCoord(x, y, z, 41)
    changeBlipColour(blip, 2) -- 2 = зелёный (палитра SA)

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
    sampAddChatMessage(cp("{00FF88}[Tactical Ping] {FFFFFF}Все метки очищены."), -1)
end

function toggle_last_ping_pin()
    local ping = active_pings[#active_pings]
    if not ping then
        sampAddChatMessage(cp("{FFAA00}[Tactical Ping] {FFFFFF}Нет активных меток."), -1)
        return
    end
    ping.pinned = not ping.pinned
    if ping.pinned then
        sampAddChatMessage(cp("{00FF88}[Tactical Ping] {FFFFFF}Последняя метка закреплена и не исчезнет по таймеру."), -1)
    else
        ping.time = os.clock()
        sampAddChatMessage(cp("{00FF88}[Tactical Ping] {FFFFFF}Закрепление снято."), -1)
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

        sampAddChatMessage(cp(string.format("{00FF00}[Tactical Ping] {FFFFFF}Marker sent via {FFFF00}/fb {FFFFFF}[Point: %d, %d, %d]", send_x, send_y, send_z)), -1)
        sampSendChat(string.format("/fb TPING %d %d %d %s", send_x, send_y, send_z, random_letters))

        last_ping_time = current_time
    else
        local time_left = cfg.settings.cooldown - time_passed
        sampAddChatMessage(cp(string.format("{FF0000}[Tactical Ping] {FFFFFF}Подождите %.1f сек. перед следующей меткой!", time_left)), -1)
    end
end

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    ping_font = renderCreateFont('Tahoma', 11, 5)
    math.randomseed(os.time() + math.floor(os.clock() * 1000000))

    local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    myName = sampGetPlayerNickname(myId)

    sampAddChatMessage(cp(string.format("{00FF00}[Tactical Ping] {FFFFFF}Скрипт загружен! Версия: {FFFF00}%s", SCRIPT_VERSION)), -1)
    sampAddChatMessage(cp("{00FF00}[Tactical Ping] {FFFFFF}Меню: {FFFF00}/pmenu {FFFFFF}| Закрепить: {FFFF00}/ppin {FFFFFF}| Очистить: {FFFF00}/pclear"), -1)

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

    lua_thread.create(function()
        wait(5000)
        check_and_update(true)
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
                        local text = cp(string.format("ЦЕЛЬ [%.1fм]\nОт: %s%s", dist, ping.author, pin_mark))
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
            if active_pings[i].author == myName and (os.clock() - active_pings[i].time) < 3.0 then
                if active_pings[i].blip then removeBlip(active_pings[i].blip) end
                table.remove(active_pings, i)
                sampAddChatMessage(cp("{FF0000}[Tactical Ping] {FFFFFF}Отмена: Вы не состоите в группе!"), -1)
                break
            end
        end
        return
    end

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
