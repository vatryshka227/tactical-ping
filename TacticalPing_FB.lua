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
local SCRIPT_VERSION = "1.0.7"
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
        dedupe_radius = 12.0,
        show_distance = true,
        show_author = true,
        font_name = "Tahoma",
        font_size = 11,
        font_flags = 5,
        font_color = {1.0, 1.0, 1.0},
        alpha = 1.0
    }
}, iniFileName)

if type(cfg.settings.ping_color) ~= "table" then cfg.settings.ping_color = {0.2, 1.0, 0.2} end
if not cfg.settings.ping_size then cfg.settings.ping_size = 8 end
if cfg.settings.notifications == nil then cfg.settings.notifications = true end
if cfg.settings.notification_sound == nil then cfg.settings.notification_sound = true end
if not cfg.settings.dedupe_radius then cfg.settings.dedupe_radius = 12.0 end
if cfg.settings.show_distance == nil then cfg.settings.show_distance = true end
if cfg.settings.show_author == nil then cfg.settings.show_author = true end
if not cfg.settings.font_name then cfg.settings.font_name = "Tahoma" end
if not cfg.settings.font_size then cfg.settings.font_size = 11 end
if not cfg.settings.font_flags then cfg.settings.font_flags = 5 end
if type(cfg.settings.font_color) ~= "table" then cfg.settings.font_color = {1.0, 1.0, 1.0} end
if not cfg.settings.alpha then cfg.settings.alpha = 1.0 end

-- Кэш декодированных строк (один раз при загрузке)
local STR_GOAL = cp("ЦЕЛЬ")
local STR_FROM = cp("От:")
local STR_M = cp("м")

local font_list = {
    "Tahoma", "Arial", "Verdana", "Courier New",
    "Impact", "Comic Sans MS", "Times New Roman"
}
local font_flags_list = {
    {name = "Обычный", flag = 4},
    {name = "Жирный", flag = 5},
    {name = "Курсив", flag = 6},
    {name = "Жирный + Курсив", flag = 7},
    {name = "С тенью", flag = 20}
}

local menu_state = imgui.new.bool(false)
local c_cooldown = imgui.new.float(cfg.settings.cooldown)
local c_lifetime = imgui.new.float(cfg.settings.ping_lifetime)
local c_render_dist = imgui.new.float(cfg.settings.render_dist)
local c_size = imgui.new.int(cfg.settings.ping_size)
local c_color = imgui.new.float[3](cfg.settings.ping_color[1], cfg.settings.ping_color[2], cfg.settings.ping_color[3])
local c_notifications = imgui.new.bool(cfg.settings.notifications)
local c_notification_sound = imgui.new.bool(cfg.settings.notification_sound)
local c_show_distance = imgui.new.bool(cfg.settings.show_distance)
local c_show_author = imgui.new.bool(cfg.settings.show_author)
local c_font_size = imgui.new.int(cfg.settings.font_size)
local c_font_flags = imgui.new.int(cfg.settings.font_flags)
local c_font_color = imgui.new.float[3](cfg.settings.font_color[1], cfg.settings.font_color[2], cfg.settings.font_color[3])
local c_alpha = imgui.new.float(cfg.settings.alpha)

local active_pings = {}
local last_ping_time = 0
local ping_font = nil
local current_font_name = cfg.settings.font_name
local current_font_flags = cfg.settings.font_flags
local myName = "Unknown"

local function rebuild_font()
    ping_font = renderCreateFont(current_font_name, cfg.settings.font_size, current_font_flags)
end

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
    imgui.SetNextWindowSize(imgui.ImVec2(460, 560), imgui.Cond.FirstUseEver)
    imgui.Begin("Настройки Tactical Ping", menu_state, imgui.WindowFlags.NoCollapse)

    local changed = false

    if imgui.CollapsingHeader("Основные") then
        imgui.PushItemWidth(180)
        if imgui.ColorEdit3("Цвет метки", c_color) then changed = true end
        if imgui.SliderInt("Размер метки", c_size, 4, 20) then changed = true end
        if imgui.SliderFloat("Задержка (сек)", c_cooldown, 1.0, 15.0, "%.1f") then changed = true end
        if imgui.SliderFloat("Время жизни (сек)", c_lifetime, 3.0, 30.0, "%.1f") then changed = true end
        if imgui.SliderFloat("Дальность (м)", c_render_dist, 100.0, 2000.0, "%.0f") then changed = true end
        imgui.PopItemWidth()
    end

    if imgui.CollapsingHeader("Текст метки") then
        if imgui.Checkbox("Показывать дистанцию", c_show_distance) then changed = true end
        if imgui.Checkbox("Показывать имя автора", c_show_author) then changed = true end

        imgui.PushItemWidth(180)

        if imgui.BeginCombo("Шрифт", current_font_name) then
            for _, name in ipairs(font_list) do
                local selected = (name == current_font_name)
                if imgui.Selectable(name, selected) then
                    current_font_name = name
                    cfg.settings.font_name = name
                    rebuild_font()
                    changed = true
                end
                if selected then imgui.SetItemDefaultFocus() end
            end
            imgui.EndCombo()
        end

        if imgui.SliderInt("Размер шрифта", c_font_size, 8, 30) then
            cfg.settings.font_size = c_font_size[0]
            rebuild_font()
            changed = true
        end

        local current_flag_name = "Обычный"
        for _, f in ipairs(font_flags_list) do
            if f.flag == current_font_flags then current_flag_name = f.name end
        end
        if imgui.BeginCombo("Стиль шрифта", current_flag_name) then
            for _, f in ipairs(font_flags_list) do
                local selected = (f.flag == current_font_flags)
                if imgui.Selectable(f.name, selected) then
                    current_font_flags = f.flag
                    cfg.settings.font_flags = f.flag
                    rebuild_font()
                    changed = true
                end
                if selected then imgui.SetItemDefaultFocus() end
            end
            imgui.EndCombo()
        end

        if imgui.ColorEdit3("Цвет текста", c_font_color) then
            cfg.settings.font_color = {c_font_color[0], c_font_color[1], c_font_color[2]}
            changed = true
        end

        if imgui.SliderFloat("Прозрачность", c_alpha, 0.1, 1.0, "%.2f") then
            cfg.settings.alpha = c_alpha[0]
            changed = true
        end

        imgui.PopItemWidth()
    end

    if imgui.CollapsingHeader("Уведомления") then
        if imgui.Checkbox("Уведомления о новых метках", c_notifications) then changed = true end
        if imgui.Checkbox("Звук уведомления", c_notification_sound) then changed = true end
    end

    if changed then
        cfg.settings.cooldown = c_cooldown[0]
        cfg.settings.ping_lifetime = c_lifetime[0]
        cfg.settings.render_dist = c_render_dist[0]
        cfg.settings.ping_size = c_size[0]
        cfg.settings.ping_color = {c_color[0], c_color[1], c_color[2]}
        cfg.settings.notifications = c_notifications[0]
        cfg.settings.notification_sound = c_notification_sound[0]
        cfg.settings.show_distance = c_show_distance[0]
        cfg.settings.show_author = c_show_author[0]
        inicfg.save(cfg, iniFileName)
    end

    if imgui.CollapsingHeader("Обновление") then
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
    end

    imgui.End()
end)

function get_dx_ping_color()
    local r = math.floor(cfg.settings.ping_color[1] * 255)
    local g = math.floor(cfg.settings.ping_color[2] * 255)
    local b = math.floor(cfg.settings.ping_color[3] * 255)
    local a = math.floor(cfg.settings.alpha * 255)
    return bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b)
end

function get_dx_font_color()
    local r = math.floor(cfg.settings.font_color[1] * 255)
    local g = math.floor(cfg.settings.font_color[2] * 255)
    local b = math.floor(cfg.settings.font_color[3] * 255)
    local a = math.floor(cfg.settings.alpha * 255)
    return bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b)
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

-- Удаляет все метки указанного автора (кроме закреплённых)
local function remove_pings_by_author(author)
    for i = #active_pings, 1, -1 do
        local ping = active_pings[i]
        if ping.author == author and not ping.pinned then
            if ping.blip then removeBlip(ping.blip) end
            table.remove(active_pings, i)
        end
    end
end

local function add_ping(x, y, z, author, local_ping)
    -- Удаляем старые метки этого же автора
    remove_pings_by_author(author)

    local duplicate = find_duplicate_ping(x, y, z)
    if duplicate then
        if not duplicate.pinned then duplicate.time = os.clock() end
        return duplicate, false
    end

    local blip = addSpriteBlipForCoord(x, y, z, 41)
    changeBlipColour(blip, 2)

    local ping = {
        x = x, y = y, z = z,
        time = os.clock(),
        author = author,
        blip = blip,
        pinned = false
    }
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

        add_ping(tx, ty, tz, myName, true)

        sampAddChatMessage(cp(string.format("{00FF00}[Tactical Ping] {FFFFFF}Marker sent via {FFFF00}/fb {FFFFFF}[Point: %d, %d, %d]", send_x, send_y, send_z)), -1)
        sampSendChat(string.format("/fb %d %d %d", send_x, send_y, send_z))

        last_ping_time = current_time
    else
        local time_left = cfg.settings.cooldown - time_passed
        sampAddChatMessage(cp(string.format("{FF0000}[Tactical Ping] {FFFFFF}Подождите %.1f сек. перед следующей меткой!", time_left)), -1)
    end
end

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    current_font_name = cfg.settings.font_name
    current_font_flags = cfg.settings.font_flags
    rebuild_font()
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
                        local author_str = STR_FROM .. " " .. ping.author .. pin_mark
                        local dist_str = string.format("[%.1f%s]", dist, STR_M)

                        local text
                        if cfg.settings.show_distance and cfg.settings.show_author then
                            text = STR_GOAL .. " " .. dist_str .. "\n" .. author_str
                        elseif cfg.settings.show_distance then
                            text = STR_GOAL .. " " .. dist_str
                        elseif cfg.settings.show_author then
                            text = author_str
                        else
                            text = ""
                        end

                        renderFontDrawText(ping_font, text, sx + p_sz + 4, sy - 12, get_dx_font_color())
                    end
                end
            end
        end
    end
end

function sampev.onServerMessage(color, text)
    local clean_text = text:gsub("{%x%x%x%x%x%x}", "")

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

    local author, tx_str, ty_str, tz_str = clean_text:match("([%w_]+)%[%d+%]:%s*%(%(%s*([-]?%d+)%s+([-]?%d+)%s+([-]?%d+)")

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
