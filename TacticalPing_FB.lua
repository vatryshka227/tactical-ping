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
local SCRIPT_VERSION = "1.0.14"
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
        show_lifetime = true,
        font_name = "Tahoma",
        font_size = 11,
        font_flags = 5,
        font_color = {1.0, 1.0, 1.0},
        alpha = 1.0,
        icon_type = 0,
        offscreen_arrows = true,
        offscreen_margin = 60,
        offscreen_size = 18
    }
}, iniFileName)

if type(cfg.settings.ping_color) ~= "table" then cfg.settings.ping_color = {0.2, 1.0, 0.2} end
if not cfg.settings.ping_size then cfg.settings.ping_size = 8 end
if cfg.settings.notifications == nil then cfg.settings.notifications = true end
if cfg.settings.notification_sound == nil then cfg.settings.notification_sound = true end
if not cfg.settings.dedupe_radius then cfg.settings.dedupe_radius = 12.0 end
if cfg.settings.show_distance == nil then cfg.settings.show_distance = true end
if cfg.settings.show_author == nil then cfg.settings.show_author = true end
if cfg.settings.show_lifetime == nil then cfg.settings.show_lifetime = true end
if not cfg.settings.font_name then cfg.settings.font_name = "Tahoma" end
if not cfg.settings.font_size then cfg.settings.font_size = 11 end
if not cfg.settings.font_flags then cfg.settings.font_flags = 5 end
if type(cfg.settings.font_color) ~= "table" then cfg.settings.font_color = {1.0, 1.0, 1.0} end
if not cfg.settings.alpha then cfg.settings.alpha = 1.0 end
if cfg.settings.icon_type == nil then cfg.settings.icon_type = 0 end
if cfg.settings.offscreen_arrows == nil then cfg.settings.offscreen_arrows = true end
if not cfg.settings.offscreen_margin then cfg.settings.offscreen_margin = 60 end
if not cfg.settings.offscreen_size then cfg.settings.offscreen_size = 18 end

-- Кэш декодированных строк (один раз при загрузке)
local STR_GOAL = cp("ЦЕЛЬ")
local STR_FROM = cp("От:")
local STR_M = cp("м")
local STR_LEFT = cp("ост.")

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
local icon_list = {
    {name = "Квадрат", id = 0},
    {name = "Треугольник", id = 1},
    {name = "Ромб", id = 2},
    {name = "Крест", id = 3}
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
local c_show_lifetime = imgui.new.bool(cfg.settings.show_lifetime)
local c_font_size = imgui.new.int(cfg.settings.font_size)
local c_font_flags = imgui.new.int(cfg.settings.font_flags)
local c_font_color = imgui.new.float[3](cfg.settings.font_color[1], cfg.settings.font_color[2], cfg.settings.font_color[3])
local c_alpha = imgui.new.float(cfg.settings.alpha)
local c_offscreen_arrows = imgui.new.bool(cfg.settings.offscreen_arrows)
local c_offscreen_margin = imgui.new.int(cfg.settings.offscreen_margin)
local c_offscreen_size = imgui.new.int(cfg.settings.offscreen_size)

local active_pings = {}
local last_ping_time = 0
local ping_font = nil
local current_font_name = cfg.settings.font_name
local current_font_flags = cfg.settings.font_flags
local current_icon_id = cfg.settings.icon_type
local myName = "Unknown"

local function rebuild_font()
    ping_font = renderCreateFont(current_font_name, cfg.settings.font_size, current_font_flags)
end

-- Отрисовка иконки метки в мире
local function draw_ping_icon(sx, sy, size, color)
    local half = size / 2

    if current_icon_id == 0 then
        renderDrawBox(sx - half, sy - half, size, size, color)
    elseif current_icon_id == 1 then
        for i = 0, size - 1 do
            local w = size - i * 2
            if w < 1 then break end
            renderDrawBox(sx - w/2, sy - half + i, w, 1, color)
        end
    elseif current_icon_id == 2 then
        for i = 0, size - 1 do
            local w
            if i <= half then
                w = i * 2
            else
                w = (size - i) * 2
            end
            if w < 1 then w = 1 end
            renderDrawBox(sx - w/2, sy - half + i, w, 1, color)
        end
    elseif current_icon_id == 3 then
        renderDrawBox(sx - half, sy - size/8, size, size/4, color)
        renderDrawBox(sx - size/8, sy - half, size/4, size, color)
    end
end

-- Стрелка-указатель у края экрана
local function draw_offscreen_arrow(px, py, pz)
    local resX, resY = getScreenResolution()
    local cx, cy = resX / 2, resY / 2

    local screen_x, screen_y = convert3DCoordsToScreen(px, py, pz)
    if not screen_x or not screen_y then return end

    local margin = cfg.settings.offscreen_margin
    local arrow_size = cfg.settings.offscreen_size

    if screen_x > margin and screen_x < resX - margin
       and screen_y > margin and screen_y < resY - margin then
        return
    end

    local dir_x = screen_x - cx
    local dir_y = screen_y - cy
    local len = math.sqrt(dir_x * dir_x + dir_y * dir_y)
    if len < 0.001 then return end
    dir_x = dir_x / len
    dir_y = dir_y / len

    local ax = math.max(margin, math.min(resX - margin, screen_x))
    local ay = math.max(margin, math.min(resY - margin, screen_y))

    local perp_x = -dir_y
    local perp_y = dir_x

    local tip_len = arrow_size * 0.7
    local base_half = arrow_size * 0.6

    local tip_x = ax + dir_x * tip_len
    local tip_y = ay + dir_y * tip_len
    local base1_x = ax - dir_x * tip_len * 0.5 + perp_x * base_half
    local base1_y = ay - dir_y * tip_len * 0.5 + perp_y * base_half
    local base2_x = ax - dir_x * tip_len * 0.5 - perp_x * base_half
    local base2_y = ay - dir_y * tip_len * 0.5 - perp_y * base_half

    local color = get_dx_ping_color()

    local steps = math.max(4, math.floor(arrow_size))
    for s = 0, steps do
        local t = s / steps
        local lx1 = base1_x + (tip_x - base1_x) * t
        local ly1 = base1_y + (tip_y - base1_y) * t
        local lx2 = base2_x + (tip_x - base2_x) * t
        local ly2 = base2_y + (tip_y - base2_y) * t

        local line_len = math.sqrt((lx2-lx1)^2 + (ly2-ly1)^2)
        local line_steps = math.max(1, math.floor(line_len))
        for k = 0, line_steps do
            local tt = k / line_steps
            local dot_x = lx1 + (lx2 - lx1) * tt
            local dot_y = ly1 + (ly2 - ly1) * tt
            renderDrawBox(dot_x - 1, dot_y - 1, 2, 2, color)
        end
    end
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
    imgui.SetNextWindowSize(imgui.ImVec2(460, 680), imgui.Cond.FirstUseEver)
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

        imgui.PushItemWidth(180)
        local current_icon_name = "Квадрат"
        for _, icon in ipairs(icon_list) do
            if icon.id == current_icon_id then current_icon_name = icon.name end
        end
        if imgui.BeginCombo("Иконка метки", current_icon_name) then
            for _, icon in ipairs(icon_list) do
                local selected = (icon.id == current_icon_id)
                if imgui.Selectable(icon.name, selected) then
                    current_icon_id = icon.id
                    cfg.settings.icon_type = icon.id
                    changed = true
                end
                if selected then imgui.SetItemDefaultFocus() end
            end
            imgui.EndCombo()
        end
        imgui.PopItemWidth()
    end

    if imgui.CollapsingHeader("Текст метки") then
        if imgui.Checkbox("Показывать дистанцию", c_show_distance) then changed = true end
        if imgui.Checkbox("Показывать имя автора", c_show_author) then changed = true end
        if imgui.Checkbox("Показывать время жизни", c_show_lifetime) then changed = true end

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

    if imgui.CollapsingHeader("Стрелки за экраном") then
        if imgui.Checkbox("Показывать стрелки", c_offscreen_arrows) then changed = true end
        imgui.PushItemWidth(180)
        if imgui.SliderInt("Отступ от края", c_offscreen_margin, 20, 150) then changed = true end
        if imgui.SliderInt("Размер стрелки", c_offscreen_size, 10, 40) then changed = true end
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
        cfg.settings.show_lifetime = c_show_lifetime[0]
        cfg.settings.offscreen_arrows = c_offscreen_arrows[0]
        cfg.settings.offscreen_margin = c_offscreen_margin[0]
        cfg.settings.offscreen_size = c_offscreen_size[0]
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

local function remove_pings_by_author(author)
    for i = #active_pings, 1, -1 do
        local ping = active_pings[i]
        if ping.author == author and not ping.pinned then
            if ping.blip then removeBlip(ping.blip) end
            if ping.checkpoint then
                deleteCheckpoint(ping.checkpoint)
                ping.checkpoint = nil
            end
            table.remove(active_pings, i)
        end
    end
end

local function add_ping(x, y, z, author, local_ping)
    remove_pings_by_author(author)

    local duplicate = find_duplicate_ping(x, y, z)
    if duplicate then
        if not duplicate.pinned then duplicate.time = os.clock() end
        return duplicate, false
    end

    local blip = addSpriteBlipForCoord(x, y, z, 41)
    local checkpoint = createCheckpoint(1, x, y, z, x, y, z, 5.0)
    changeBlipColour(blip, 2)

    local ping = {
        x = x, y = y, z = z,
        time = os.clock(),
        author = author,
        blip = blip,
        checkpoint = checkpoint,
        pinned = false
    }
    table.insert(active_pings, ping)
    if not local_ping then notify_ping(author, x, y, z) end
    return ping, true
end

function clear_all_pings()
    for i = #active_pings, 1, -1 do
        local ping = active_pings[i]
        if ping.blip then removeBlip(ping.blip) end
        if ping.checkpoint then
            deleteCheckpoint(ping.checkpoint)
            ping.checkpoint = nil
        end
        table.remove(active_pings, i)
    end
    sampAddChatMessage(cp("{00FF88}[Tactical Ping] {FFFFFF}Все метки и чекпоинты очищены."), -1)
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

local function send_ping_at(tx, ty, tz)
    local send_x = math.floor(tx)
    local send_y = math.floor(ty)
    local send_z = math.floor(tz)

    add_ping(tx, ty, tz, myName, true)

    sampAddChatMessage(cp(string.format("{00FF00}[Tactical Ping] {FFFFFF}Marker sent via {FFFF00}/fb {FFFFFF}[Point: %d, %d, %d]", send_x, send_y, send_z)), -1)
    sampSendChat(string.format("/fb %d %d %d", send_x, send_y, send_z))
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

        send_ping_at(tx, ty, tz)
        last_ping_time = current_time
    else
        local time_left = cfg.settings.cooldown - time_passed
        sampAddChatMessage(cp(string.format("{FF0000}[Tactical Ping] {FFFFFF}Подождите %.1f сек. перед следующей меткой!", time_left)), -1)
    end
end

function place_self_ping()
    local current_time = os.clock()
    local time_passed = current_time - last_ping_time

    if time_passed >= cfg.settings.cooldown then
        local px, py, pz = getCharCoordinates(PLAYER_PED)
        send_ping_at(px, py, pz)
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
    current_icon_id = cfg.settings.icon_type
    rebuild_font()
    math.randomseed(os.time() + math.floor(os.clock() * 1000000))

    local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    myName = sampGetPlayerNickname(myId)

    sampAddChatMessage(cp(string.format("{00FF00}[Tactical Ping] {FFFFFF}Скрипт загружен! Версия: {FFFF00}%s", SCRIPT_VERSION)), -1)
    sampAddChatMessage(cp("{00FF00}[Tactical Ping] {FFFFFF}Меню: {FFFF00}/pmenu {FFFFFF}| Закрепить: {FFFF00}/ppin {FFFFFF}| Очистить: {FFFF00}/pclear {FFFFFF}| На себя: {FFFF00}/pself"), -1)

    sampRegisterChatCommand('ping', function()
        place_ping_marker()
    end)

    sampRegisterChatCommand('pself', function()
        place_self_ping()
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
                if ping.checkpoint then
                    deleteCheckpoint(ping.checkpoint)
                    ping.checkpoint = nil
                end
                table.remove(active_pings, i)
            else
                local on_screen = isPointOnScreen(ping.x, ping.y, ping.z, 0.0)

                if on_screen then
                    local sx, sy = convert3DCoordsToScreen(ping.x, ping.y, ping.z)
                    if sx and sy then
                        local px, py, pz = getCharCoordinates(PLAYER_PED)
                        local dist = getDistanceBetweenCoords3d(px, py, pz, ping.x, ping.y, ping.z)

                        local p_sz = cfg.settings.ping_size
                        local render_color = get_dx_ping_color()

                        draw_ping_icon(sx, sy, p_sz, render_color)

                        local pin_mark = ping.pinned and " [PIN]" or ""

                        local dist_str = ""
                        if cfg.settings.show_distance then
                            dist_str = string.format("[%.1f%s]", dist, STR_M)
                        end

                        local lifetime_str = ""
                        if cfg.settings.show_lifetime and not ping.pinned then
                            local left = cfg.settings.ping_lifetime - (os.clock() - ping.time)
                            if left < 0 then left = 0 end
                            lifetime_str = string.format(" (%s %.1f)", STR_LEFT, left)
                        end

                        local author_str = ""
                        if cfg.settings.show_author then
                            author_str = STR_FROM .. " " .. ping.author .. pin_mark
                        end

                        local first_line = STR_GOAL
                        if dist_str ~= "" then first_line = first_line .. " " .. dist_str end
                        first_line = first_line .. lifetime_str

                        local text = first_line
                        if author_str ~= "" then
                            text = text .. "\n" .. author_str
                        end

                        renderFontDrawText(ping_font, text, sx + p_sz + 4, sy - 12, get_dx_font_color())
                    end
                else
                    if cfg.settings.offscreen_arrows then
                        draw_offscreen_arrow(ping.x, ping.y, ping.z)
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
                if active_pings[i].checkpoint then
                    deleteCheckpoint(active_pings[i].checkpoint)
                    active_pings[i].checkpoint = nil
                end
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
            if ping.checkpoint then deleteCheckpoint(ping.checkpoint) end
        end
    end
end
