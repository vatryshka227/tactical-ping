script_name('Tactical Ping')
script_author('afk111')

local sampev = require 'lib.samp.events'
local memory = require 'memory'
local vkeys = require 'vkeys'
local imgui = require 'mimgui'
local inicfg = require 'inicfg'
local bit = require 'bit'
local encoding = require 'encoding'

-- файл в UTF-8, в чат уходит CP1251 через cp()
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local function cp(s) return u8:decode(s) end

-- локализация часто вызываемых функций (критично для FPS)
local floor = math.floor
local abs = math.abs
local sqrt = math.sqrt
local sin = math.sin
local cos = math.cos
local max = math.max
local min = math.min
local huge = math.huge
local clock = os.clock
local format = string.format
local find = string.find
local match = string.match
local gsub = string.gsub
local byte = string.byte
local lower = string.lower
local insert = table.insert
local remove = table.remove
local bor = bit.bor
local lshift = bit.lshift

local sampAddChatMessage = sampAddChatMessage
local getCharCoordinates = getCharCoordinates
local getDistanceBetweenCoords3d = getDistanceBetweenCoords3d
local getScreenResolution = getScreenResolution
local getActiveCameraCoordinates = getActiveCameraCoordinates
local getActiveCameraPointAt = getActiveCameraPointAt
local convert3DCoordsToScreen = convert3DCoordsToScreen
local renderDrawBox = renderDrawBox
local renderDrawLine = renderDrawLine
local renderFontDrawText = renderFontDrawText
local renderGetFontDrawTextLength = renderGetFontDrawTextLength
local renderGetFontDrawHeight = renderGetFontDrawHeight
local renderCreateFont = renderCreateFont
local renderReleaseFont = renderReleaseFont
local isPauseMenuActive = isPauseMenuActive
local sampIsCursorActive = sampIsCursorActive
local sampIsChatInputActive = sampIsChatInputActive
local sampIsDialogActive = sampIsDialogActive
local wasKeyPressed = wasKeyPressed
local sampIsLocalPlayerSpawned = sampIsLocalPlayerSpawned
local isCharDead = isCharDead
local addSpriteBlipForCoord = addSpriteBlipForCoord
local createCheckpoint = createCheckpoint
local removeBlip = removeBlip
local deleteCheckpoint = deleteCheckpoint
local changeBlipColour = changeBlipColour
local addOneOffSound = addOneOffSound
local processLineOfSight = processLineOfSight
local convertScreenCoordsToWorld3D = convertScreenCoordsToWorld3D
local convertGameScreenCoordsToWindowScreenCoords = convertGameScreenCoordsToWindowScreenCoords
local getGroundZFor3dCoord = getGroundZFor3dCoord
local doesFileExist = doesFileExist
local getWorkingDirectory = getWorkingDirectory
local thisScript = thisScript
local wait = wait
local downloadUrlToFile = downloadUrlToFile
local loadstring = loadstring
local getFolderPath = getFolderPath

local function msg(text)
    sampAddChatMessage(cp("{55D4C0}[Tactical Ping] {E8F0F2}" .. text), -1)
end

local SCRIPT_VERSION = "1.5.11"

local iniFileName = 'TacticalPing.ini'
local cfg_defaults = {
    settings = {
        cooldown = 5.0,
        ping_lifetime = 8.0,
        render_dist = 700.0,
        ping_size = 9,
        ping_r = 0.35, ping_g = 0.82, ping_b = 0.72,
        notifications = true,
        notification_sound = true,
        dedupe_radius = 12.0,
        show_distance = true,
        show_author = true,
        show_lifetime = true,
        font_name = "Tahoma",
        font_size = 12,
        font_flags = 5,
        font_r = 0.95, font_g = 0.97, font_b = 0.98,
        alpha = 0.92,
        icon_type = 4,
        offscreen_arrows = true,
        offscreen_margin = 56,
        offscreen_size = 16,
        ping_key = vkeys.VK_MBUTTON,
        fade_time = 1.4,
        author_colors = true,
        incoming_cooldown = 2.0,
        fb_color = 0,
        auto_update = true,
        track_interval = 5.0,
        track_move_threshold = 12.0,
        track_mode = 2,
        arrive_remove = true,
        arrive_radius = 4.0,
        arrive_grace = 1.5,
        icon_v2 = false,
        look_version = 0
    }
}
local cfg = inicfg.load(cfg_defaults, iniFileName)

if type(cfg) ~= "table" then cfg = {} end
if type(cfg.settings) ~= "table" then cfg.settings = {} end
for k, v in pairs(cfg_defaults.settings) do
    if type(cfg.settings[k]) ~= type(v) then cfg.settings[k] = v end
end
inicfg.save(cfg, iniFileName)

local STR_GOAL = cp("ЦЕЛЬ")
local STR_M = cp("м")
local STR_KM = cp("км")
local STR_NOGROUP = cp("%[Ошибка%] Вы не состоите в группе!")

local PING_PATTERN = "([%w_%[%]%.%$@=%(%)]+)%[%d+%]:%s*%(%(%s*([-]?%d+)%s+([-]?%d+)%s+([-]?%d+)"

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
    {name = "Крест", id = 3},
    {name = "Кольцо (рекомендуется)", id = 4}
}

local S = cfg.settings
if S.track_interval < 2.0 then S.track_interval = 2.0 end
if not S.icon_v2 then
    S.icon_type = 4
    S.icon_v2 = true
    inicfg.save(cfg, iniFileName)
end
if S.look_version < 3 then
    local old_mint = abs(S.ping_r - 0.30) < 0.02 and abs(S.ping_g - 0.90) < 0.02 and abs(S.ping_b - 0.60) < 0.02
    local old_green = abs(S.ping_r - 0.2) < 0.02 and abs(S.ping_g - 1.0) < 0.02 and abs(S.ping_b - 0.2) < 0.02
    if old_mint or old_green then
        S.ping_r, S.ping_g, S.ping_b = 0.35, 0.82, 0.72
        S.font_r, S.font_g, S.font_b = 0.95, 0.97, 0.98
        S.alpha = 0.92
        S.fade_time = 1.4
        S.ping_size = 9
        S.font_size = 12
    end
    S.look_version = 3
    inicfg.save(cfg, iniFileName)
end
if S.track_mode ~= 0 and S.track_mode ~= 1 and S.track_mode ~= 2 then S.track_mode = 2 end

local menu_state = imgui.new.bool(false)
local c_cooldown = imgui.new.float(S.cooldown)
local c_lifetime = imgui.new.float(S.ping_lifetime)
local c_render_dist = imgui.new.float(S.render_dist)
local c_size = imgui.new.int(S.ping_size)
local c_color = imgui.new.float[3](S.ping_r, S.ping_g, S.ping_b)
local c_notifications = imgui.new.bool(S.notifications)
local c_notification_sound = imgui.new.bool(S.notification_sound)
local c_show_distance = imgui.new.bool(S.show_distance)
local c_show_author = imgui.new.bool(S.show_author)
local c_show_lifetime = imgui.new.bool(S.show_lifetime)
local c_font_size = imgui.new.int(S.font_size)
local c_font_color = imgui.new.float[3](S.font_r, S.font_g, S.font_b)
local c_alpha = imgui.new.float(S.alpha)
local c_offscreen_arrows = imgui.new.bool(S.offscreen_arrows)
local c_offscreen_margin = imgui.new.int(S.offscreen_margin)
local c_offscreen_size = imgui.new.int(S.offscreen_size)
local c_fade = imgui.new.float(S.fade_time)
local c_author_colors = imgui.new.bool(S.author_colors)
local c_incoming_cd = imgui.new.float(S.incoming_cooldown)
local c_auto_update = imgui.new.bool(S.auto_update)
local c_track_interval = imgui.new.float(S.track_interval)
local c_track_move_threshold = imgui.new.float(S.track_move_threshold)
local c_arrive_remove = imgui.new.bool(S.arrive_remove ~= false)
local c_arrive_radius = imgui.new.float(tonumber(S.arrive_radius) or 4.0)

local active_pings = {}
local last_ping_time = 0
local ping_font = nil
local ping_font_small = nil
local font_rebuild_at = nil
local save_at = nil
local binding_key = false
local bind_ready = 0
local learning_color = false
local tracking = false
local last_track = 0
local last_track_x, last_track_y, last_track_z = nil, nil, nil
local last_incoming = {}
local author_cache = {}

-- кэш для отрисовки (обновляется раз в кадр)
local frame_resX, frame_resY = 0, 0
local frame_px, frame_py, frame_pz = 0, 0, 0
local frame_now = 0

local dlstatus = require('moonloader').download_status
local UPDATE_URL_VERSION = "https://raw.githubusercontent.com/vatryshka227/tactical-ping/refs/heads/main/versions.txt"
local UPDATE_URL_SCRIPT  = "https://raw.githubusercontent.com/vatryshka227/tactical-ping/main/TacticalPing_FB.lua"
local UPDATE_TMP_VER = getWorkingDirectory() .. "\\tp_ver.tmp"
local UPDATE_TMP = getWorkingDirectory() .. "\\TacticalPing_update.lua"

local update_state = {
    busy = false,
    status = "Нажмите кнопку для проверки",
    remote_version = nil
}

local function parse_version(v)
    local a, b, c = (v or ""):match("(%d+)%.(%d+)%.(%d+)")
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

local function is_newer(remote, local_)
    local r1, r2, r3 = parse_version(remote)
    local l1, l2, l3 = parse_version(local_)
    if r1 ~= l1 then return r1 > l1 end
    if r2 ~= l2 then return r2 > l2 end
    return r3 > l3
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function download_file(url, path, timeout_ms)
    if doesFileExist(path) then os.remove(path) end
    local finished = false
    downloadUrlToFile(url, path, function(id, status)
        if status == dlstatus.STATUS_ENDDOWNLOADDATA then finished = true end
    end)
    local t = 0
    while not finished and t < timeout_ms do
        wait(100)
        t = t + 100
    end
    return finished and doesFileExist(path)
end

local function check_and_update(silent)
    if update_state.busy then return end
    update_state.busy = true
    update_state.status = "Проверка обновлений..."

    lua_thread.create(function()
        local function fail(status, chat_text)
            update_state.busy = false
            update_state.status = status
            if doesFileExist(UPDATE_TMP) then os.remove(UPDATE_TMP) end
            if chat_text and not silent then
                msg(chat_text)
            end
        end

        local ok = download_file(UPDATE_URL_VERSION, UPDATE_TMP_VER, 8000)
        local remote_ver = ok and read_file(UPDATE_TMP_VER) or nil
        if doesFileExist(UPDATE_TMP_VER) then os.remove(UPDATE_TMP_VER) end
        if not remote_ver then
            return fail("Ошибка: не удалось скачать versions.txt", "Не удалось проверить обновления.")
        end
        remote_ver = (remote_ver:gsub("%s+", ""))
        if not remote_ver:match("^%d+%.%d+%.%d+$") then
            return fail("Ошибка: некорректный versions.txt", "Файл версии на сервере повреждён.")
        end

        update_state.remote_version = remote_ver

        if not is_newer(remote_ver, SCRIPT_VERSION) then
            update_state.busy = false
            update_state.status = "Актуальная версия (" .. SCRIPT_VERSION .. ")"
            if not silent then
                msg(format("Версия актуальная: {A8E8D8}%s", SCRIPT_VERSION))
            end
            return
        end

        update_state.status = "Скачивание " .. remote_ver .. "..."
        msg(format("Найдена версия {A8E8D8}%s{E8F0F2}, скачиваю...", remote_ver))

        if not download_file(UPDATE_URL_SCRIPT, UPDATE_TMP, 20000) then
            return fail("Ошибка скачивания скрипта", "Не удалось скачать обновление.")
        end

        local content = read_file(UPDATE_TMP)
        os.remove(UPDATE_TMP)
        if not content or #content < 2000
           or not content:find("script_name", 1, true)
           or not content:find("function main", 1, true) then
            return fail("Ошибка: файл повреждён", "Скачанный файл повреждён или пуст.")
        end

        local compiled = loadstring(content)
        if not compiled then
            return fail("Ошибка: в скачанном файле синтаксическая ошибка", "Скачанный файл не компилируется, обновление отменено.")
        end

        local this_file = thisScript().path
        local current = read_file(this_file)
        if current then
            local bak = io.open(this_file .. ".bak", "wb")
            if bak then bak:write(current) bak:close() end
        end

        local outf = io.open(this_file, "wb")
        if not outf then
            return fail("Ошибка: не удалось записать файл", "Не удалось записать обновление.")
        end
        outf:write(content)
        outf:close()

        update_state.busy = false
        update_state.status = "Обновлено до " .. remote_ver .. ". Перезагрузка..."
        msg(format("Обновлено до {A8E8D8}%s{E8F0F2}, перезагрузка. Старая версия в .bak", remote_ver))
        wait(1500)
        thisScript():reload()
    end)
end

local function save_cfg()
    save_at = nil
    inicfg.save(cfg, iniFileName)
end

local function schedule_save()
    save_at = clock() + 1.0
end

local function rebuild_font()
    font_rebuild_at = nil
    local old, old_small = ping_font, ping_font_small
    ping_font = renderCreateFont(S.font_name, S.font_size, S.font_flags)
    ping_font_small = renderCreateFont(S.font_name, max(8, S.font_size - 2), S.font_flags)
    if old then renderReleaseFont(old) end
    if old_small then renderReleaseFont(old_small) end
end

local function request_font_rebuild()
    font_rebuild_at = clock() + 0.25
end

local function get_my_name()
    local ok, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if ok then
        return sampGetPlayerNickname(id) or ""
    end
    return ""
end

local function pack_color(r, g, b, a)
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    if r < 0 then r = 0 elseif r > 1 then r = 1 end
    if g < 0 then g = 0 elseif g > 1 then g = 1 end
    if b < 0 then b = 0 elseif b > 1 then b = 1 end
    return bor(
        lshift(floor(a * 255 + 0.5), 24),
        lshift(floor(r * 255 + 0.5), 16),
        lshift(floor(g * 255 + 0.5), 8),
        floor(b * 255 + 0.5)
    )
end

local function hsv2rgb(h, s, v)
    local i = floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q end
end

local function author_rgb(name)
    local c = author_cache[name]
    if not c then
        local h = 0
        for i = 1, #name do h = (h * 31 + byte(name, i)) % 360 end
        local r, g, b = hsv2rgb(h / 360, 0.42, 0.88)
        c = {r, g, b}
        author_cache[name] = c
    end
    return c[1], c[2], c[3]
end

local function get_ping_rgb(ping)
    if S.author_colors and not ping.own then
        return author_rgb(ping.author)
    end
    return S.ping_r, S.ping_g, S.ping_b
end

local function input_blocked()
    return isPauseMenuActive() or sampIsCursorActive() or sampIsChatInputActive() or sampIsDialogActive()
end

local function key_name(k)
    return vkeys.id_to_name(k) or tostring(k)
end

local function start_binding()
    binding_key = true
    bind_ready = clock() + 0.3
end

local function start_learning()
    learning_color = true
    msg("Ждём групповую метку, цвет сообщения запомнится.")
end

local function set_tracking(on)
    tracking = on
    last_track = 0
    last_track_x, last_track_y, last_track_z = nil, nil, nil
    if on then
        local how
        if S.track_mode == 0 then
            how = format("каждые {A8E8D8}%.1f{E8F0F2} сек.", S.track_interval)
        elseif S.track_mode == 1 then
            how = format("при перемещении на {A8E8D8}%.1f м{E8F0F2}", S.track_move_threshold)
        else
            how = format("каждые {A8E8D8}%.1f{E8F0F2} сек. или при перемещении на {A8E8D8}%.1f м{E8F0F2}", S.track_interval, S.track_move_threshold)
        end
        msg("Слежение включено: " .. how .. ". Выключить: {A8E8D8}/ptrack")
    else
        msg("Слежение выключено.")
    end
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- isPointOnScreen режет всё за дальностью прорисовки, поэтому дальнюю точку
-- подтягиваем по лучу из камеры
local FAR_PROJECT = 200.0
local FAR_PROJECT_INV = 1.0 / FAR_PROJECT

local function project_point(x, y, z)
    local camx, camy, camz = getActiveCameraCoordinates()
    local lx, ly, lz = getActiveCameraPointAt()
    local vx, vy, vz = x - camx, y - camy, z - camz
    local dot = vx * (lx - camx) + vy * (ly - camy) + vz * (lz - camz)
    local len2 = vx * vx + vy * vy + vz * vz
    if len2 > FAR_PROJECT * FAR_PROJECT then
        local k = FAR_PROJECT / sqrt(len2)
        vx, vy, vz = vx * k, vy * k, vz * k
    end
    local sx, sy = convert3DCoordsToScreen(camx + vx, camy + vy, camz + vz)
    return sx, sy, dot > 0
end

local function draw_ping_icon(sx, sy, size, color)
    local half = size * 0.5
    local icon = S.icon_type

    if icon == 0 then
        renderDrawBox(sx - half, sy - half, size, size, color)
    elseif icon == 1 then
        for i = 0, size - 1 do
            local w = size - i
            renderDrawBox(sx - w * 0.5, sy - half + i, w, 1, color)
        end
    elseif icon == 2 then
        for i = 0, size - 1 do
            local w = (i <= half) and (i * 2) or ((size - i) * 2)
            if w < 1 then w = 1 end
            renderDrawBox(sx - w * 0.5, sy - half + i, w, 1, color)
        end
    elseif icon == 3 then
        local q = size * 0.25
        renderDrawBox(sx - half, sy - q * 0.5, size, q, color)
        renderDrawBox(sx - q * 0.5, sy - half, q, size, color)
    end
end

-- оптимизированная дуга: меньше сегментов на малых радиусах, шаг по углу
local function draw_arc(cx, cy, radius, fraction, segments, width, color)
    if fraction <= 0 or not radius or radius < 1.0 then return end
    if fraction > 1 then fraction = 1 end
    width = max(1, floor(width + 0.5))
    segments = max(4, floor(segments or 16))
    local n = max(1, floor(segments * fraction + 0.5))
    local step = (2 * 3.14159265 * fraction) / n
    local a = -1.5707963 -- -pi/2
    local px = cx + cos(a) * radius
    local py = cy + sin(a) * radius
    for i = 1, n do
        a = a + step
        local x = cx + cos(a) * radius
        local y = cy + sin(a) * radius
        renderDrawLine(px, py, x, y, width, color)
        px, py = x, y
    end
end

local function draw_disc(cx, cy, radius, color)
    cx = floor(cx + 0.5)
    cy = floor(cy + 0.5)
    local r = max(1, floor(radius + 0.5))
    local r2 = r * r
    for dy = -r, r do
        local w = floor(sqrt(r2 - dy * dy) * 2 + 0.5)
        if w < 1 then w = 1 end
        renderDrawBox(cx - floor(w * 0.5), cy + dy, w, 1, color)
    end
end

local function draw_down_pointer(cx, tip_y, width, height, color)
    cx = floor(cx + 0.5)
    tip_y = floor(tip_y + 0.5)
    height = max(2, floor(height + 0.5))
    local inv_h = 1 / height
    for i = 0, height - 1 do
        local w = max(1, floor(width * (1 - i * inv_h) + 0.5))
        renderDrawBox(cx - floor(w * 0.5), tip_y - height + i, w, 1, color)
    end
end

-- кольцо-булавка: остриё точно в мировой точке (sx, sy)
local function draw_ring_marker(sx, sy, ping, r, g, b, alpha, now, dist, left)
    sx = floor(sx + 0.5)
    sy = floor(sy + 0.5)

    local born_age = now - ping.born

    local spawn_scale, spawn_alpha = 1.0, 1.0
    if born_age < 0.40 then
        local u = born_age * 2.5
        local e = 1 - (1 - u) * (1 - u) * (1 - u)
        spawn_scale = 1.35 - 0.35 * e
        spawn_alpha = e
    end

    local dist_scale = clamp(1.18 - dist * 0.002222, 0.72, 1.18)
    local R0 = S.ping_size * 1.1 * dist_scale
    local pulse = 1 + 0.02 * sin(now * 2.6)
    local R = R0 * spawn_scale * pulse
    local a = alpha * spawn_alpha
    local seg = clamp(floor(R * 3.2), 20, 48) -- меньше сегментов → меньше draw calls

    local stem = max(5, floor(R0 * 0.55 + 0.5))
    local cy = sy - stem - R

    local col = pack_color(r, g, b, a)
    local soft_dark = pack_color(0.02, 0.03, 0.04, a * 0.55)
    local glow = pack_color(r, g, b, a * 0.16)

    if born_age < 0.55 then
        local u = born_age * 1.81818
        local fade = (1 - u) * (1 - u)
        draw_arc(sx, sy, max(2, R0 * 0.6 * (1 + 1.4 * u)), 1, seg, 2, pack_color(r, g, b, alpha * fade * 0.4))
    end

    local R_out = max(2, R + 2.0)
    local R_mid = max(1.5, R + 1.0)
    local R_in  = max(1.0, R - 1.0)
    local R_main = max(1.5, R)

    draw_arc(sx, cy, R_out, 1, seg, 2, glow)
    draw_arc(sx, cy, R_mid, 1, seg, 1, soft_dark)
    draw_arc(sx, cy, R_in,  1, seg, 1, soft_dark)

    if S.show_lifetime and not ping.pinned then
        draw_arc(sx, cy, R_main, 1, seg, 2, pack_color(r, g, b, a * 0.22))
        draw_arc(sx, cy, R_main, clamp(left / S.ping_lifetime, 0, 1), seg, 2, col)
    else
        draw_arc(sx, cy, R_main, 1, seg, 2, col)
    end

    local dot = max(2, R0 * 0.14)
    draw_disc(sx, cy, dot + 1.3, soft_dark)
    draw_disc(sx, cy, dot, col)

    local pw = max(3, R0 * 0.55)
    draw_down_pointer(sx, sy, pw, stem, col)
    draw_disc(sx, sy, 1.6, soft_dark)
    draw_disc(sx, sy, 1.1, col)

    return R_main + 3, cy
end

local function draw_ping_label(x, y, ping, dist, r, g, b, alpha)
    local big, small = ping_font, ping_font_small
    if not big or not small or not x or not y then return end

    local line1
    if S.show_distance then
        if dist >= 1000 then
            line1 = format("%.1f %s", dist * 0.001, STR_KM)
        else
            line1 = format("%d %s", floor(dist + 0.5), STR_M)
        end
    else
        line1 = STR_GOAL
    end
    local line2 = S.show_author and ping.author or nil

    local w1 = tonumber(renderGetFontDrawTextLength(big, line1)) or 40
    local h1 = tonumber(renderGetFontDrawHeight(big)) or 12
    local w2, h2 = 0, 0
    if line2 then
        w2 = tonumber(renderGetFontDrawTextLength(small, line2)) or 30
        h2 = tonumber(renderGetFontDrawHeight(small)) or 10
    end

    local pad = 6
    local w = max(8, max(w1, w2) + pad * 2 + 3)
    local h = max(8, h1 + h2 + pad * 2 - 1)
    local top = y - h * 0.5

    local bg = pack_color(0.04, 0.05, 0.07, alpha * 0.55)
    local bg_edge = pack_color(0.04, 0.05, 0.07, alpha * 0.35)
    renderDrawBox(x + 2, top, max(1, w - 4), h, bg)
    renderDrawBox(x + 1, top + 1, max(1, w - 2), max(1, h - 2), bg)
    renderDrawBox(x, top + 2, w, max(1, h - 4), bg_edge)
    renderDrawBox(x, top + 2, 3, max(1, h - 4), pack_color(r, g, b, alpha * 0.85))

    local tx = x + pad + 2
    local ty = top + pad - 1
    local shadow = pack_color(0, 0, 0, alpha * 0.65)
    local text_col = pack_color(S.font_r, S.font_g, S.font_b, alpha)

    renderFontDrawText(big, line1, tx + 1, ty + 1, shadow)
    renderFontDrawText(big, line1, tx, ty, text_col)

    if line2 then
        local ty2 = ty + h1
        renderFontDrawText(small, line2, tx + 1, ty2 + 1, shadow)
        renderFontDrawText(small, line2, tx, ty2, pack_color(0.72, 0.78, 0.82, alpha * 0.92))
    end

    if ping.pinned then
        local pcx, pcy = x + w + 7, top + h * 0.5 - 2
        local pc = pack_color(r, g, b, alpha * 0.95)
        draw_disc(pcx, pcy, 2.8, pc)
        renderDrawLine(pcx, pcy + 3, pcx - 2, pcy + 9, 2, pc)
    end
end

-- лёгкая стрелка: 3 линии контура + 1 fill, без pulse и без 3 слоёв
local function draw_offscreen_arrow(ping, r, g, b, alpha)
    local cx, cy = frame_resX * 0.5, frame_resY * 0.5

    local sx, sy, in_front = project_point(ping.x, ping.y, ping.z)
    if not sx or not sy then return end

    local dx, dy = sx - cx, sy - cy
    if not in_front then dx, dy = -dx, -dy end

    local len = sqrt(dx * dx + dy * dy)
    if len < 0.001 then
        dx, dy = 0, 1
        len = 1
    end
    local inv = 1 / len
    dx, dy = dx * inv, dy * inv

    local margin = S.offscreen_margin
    local hw, hh = cx - margin, cy - margin
    local tx = abs(dx) > 1e-4 and hw / abs(dx) or huge
    local ty = abs(dy) > 1e-4 and hh / abs(dy) or huge
    local t = min(tx, ty)
    local ax, ay = cx + dx * t, cy + dy * t

    local sz = S.offscreen_size
    local tip_len = sz * 0.7
    local base_half = sz * 0.55
    local perp_x, perp_y = -dy, dx

    local tip_x = ax + dx * tip_len
    local tip_y = ay + dy * tip_len
    local bx = ax - dx * tip_len * 0.45
    local by = ay - dy * tip_len * 0.45
    local b1x = bx + perp_x * base_half
    local b1y = by + perp_y * base_half
    local b2x = bx - perp_x * base_half
    local b2y = by - perp_y * base_half

    -- тонкий fill (2 линии вместо 9)
    local mid_x = (b1x + b2x) * 0.5
    local mid_y = (b1y + b2y) * 0.5
    local col = pack_color(r, g, b, alpha * 0.9)
    local dark = pack_color(0.02, 0.03, 0.04, alpha * 0.55)
    renderDrawLine(tip_x, tip_y, mid_x, mid_y, 3, col)
    renderDrawLine(tip_x, tip_y, b1x, b1y, 2, col)
    renderDrawLine(tip_x, tip_y, b2x, b2y, 2, col)
    -- контур
    renderDrawLine(tip_x, tip_y, b1x, b1y, 1, dark)
    renderDrawLine(tip_x, tip_y, b2x, b2y, 1, dark)
    renderDrawLine(b1x, b1y, b2x, b2y, 1, dark)
end

imgui.OnInitialize(function()
    local io = imgui.GetIO()
    io.IniFilename = nil

    local font_path = getFolderPath(0x14) .. '\\arial.ttf'
    if doesFileExist(font_path) then
        io.Fonts:AddFontFromFileTTF(font_path, 16, nil, io.Fonts:GetGlyphRangesCyrillic())
    end

    local style = imgui.GetStyle()
    local colors = style.Colors

    style.WindowRounding = 10.0
    style.FrameRounding = 6.0
    style.GrabRounding = 5.0
    style.ScrollbarRounding = 6.0
    style.TabRounding = 6.0
    style.WindowPadding = imgui.ImVec2(14, 12)
    style.FramePadding = imgui.ImVec2(8, 5)
    style.ItemSpacing = imgui.ImVec2(8, 7)
    style.ItemInnerSpacing = imgui.ImVec2(6, 4)
    style.ScrollbarSize = 12.0

    colors[imgui.Col.WindowBg]          = imgui.ImVec4(0.07, 0.08, 0.09, 0.96)
    colors[imgui.Col.ChildBg]           = imgui.ImVec4(0.08, 0.09, 0.10, 0.60)
    colors[imgui.Col.PopupBg]           = imgui.ImVec4(0.09, 0.10, 0.11, 0.96)
    colors[imgui.Col.Text]              = imgui.ImVec4(0.90, 0.92, 0.94, 1.00)
    colors[imgui.Col.TextDisabled]      = imgui.ImVec4(0.50, 0.52, 0.55, 1.00)
    colors[imgui.Col.Border]            = imgui.ImVec4(0.18, 0.22, 0.24, 0.60)
    colors[imgui.Col.BorderShadow]      = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)

    colors[imgui.Col.FrameBg]           = imgui.ImVec4(0.13, 0.15, 0.17, 1.00)
    colors[imgui.Col.FrameBgHovered]    = imgui.ImVec4(0.18, 0.22, 0.24, 1.00)
    colors[imgui.Col.FrameBgActive]     = imgui.ImVec4(0.22, 0.28, 0.30, 1.00)

    colors[imgui.Col.TitleBg]           = imgui.ImVec4(0.09, 0.11, 0.12, 1.00)
    colors[imgui.Col.TitleBgActive]     = imgui.ImVec4(0.11, 0.15, 0.16, 1.00)
    colors[imgui.Col.TitleBgCollapsed]  = imgui.ImVec4(0.07, 0.08, 0.09, 0.80)

    colors[imgui.Col.Button]            = imgui.ImVec4(0.16, 0.20, 0.22, 1.00)
    colors[imgui.Col.ButtonHovered]     = imgui.ImVec4(0.22, 0.32, 0.34, 1.00)
    colors[imgui.Col.ButtonActive]      = imgui.ImVec4(0.28, 0.42, 0.44, 1.00)

    colors[imgui.Col.CheckMark]         = imgui.ImVec4(0.40, 0.82, 0.75, 1.00)
    colors[imgui.Col.SliderGrab]        = imgui.ImVec4(0.35, 0.72, 0.68, 1.00)
    colors[imgui.Col.SliderGrabActive]  = imgui.ImVec4(0.45, 0.88, 0.82, 1.00)
    colors[imgui.Col.Header]            = imgui.ImVec4(0.16, 0.22, 0.24, 0.80)
    colors[imgui.Col.HeaderHovered]     = imgui.ImVec4(0.22, 0.32, 0.34, 0.90)
    colors[imgui.Col.HeaderActive]      = imgui.ImVec4(0.28, 0.40, 0.42, 1.00)

    colors[imgui.Col.ScrollbarBg]       = imgui.ImVec4(0.08, 0.09, 0.10, 0.60)
    colors[imgui.Col.ScrollbarGrab]     = imgui.ImVec4(0.22, 0.26, 0.28, 1.00)
    colors[imgui.Col.ScrollbarGrabHovered] = imgui.ImVec4(0.30, 0.36, 0.38, 1.00)
    colors[imgui.Col.ScrollbarGrabActive]  = imgui.ImVec4(0.38, 0.48, 0.50, 1.00)

    colors[imgui.Col.Separator]         = imgui.ImVec4(0.20, 0.24, 0.26, 0.70)
    colors[imgui.Col.SeparatorHovered]  = imgui.ImVec4(0.35, 0.55, 0.52, 0.80)
    colors[imgui.Col.SeparatorActive]   = imgui.ImVec4(0.40, 0.70, 0.65, 1.00)
end)

imgui.OnFrame(function() return menu_state[0] end, function()
    imgui.SetNextWindowSize(imgui.ImVec2(470, 700), imgui.Cond.FirstUseEver)
    if not imgui.Begin("Настройки Tactical Ping", menu_state, imgui.WindowFlags.NoCollapse) then
        imgui.End()
        return
    end

    local changed = false

    if imgui.CollapsingHeader("Основные") then
        imgui.PushItemWidth(180)
        if imgui.ColorEdit3("Цвет метки", c_color) then changed = true end
        if imgui.SliderInt("Размер метки", c_size, 4, 20) then changed = true end
        if imgui.SliderFloat("Задержка (сек)", c_cooldown, 1.0, 15.0, "%.1f") then changed = true end
        if imgui.SliderFloat("Время жизни (сек)", c_lifetime, 3.0, 30.0, "%.1f") then changed = true end
        if imgui.SliderFloat("Затухание (сек)", c_fade, 0.0, 3.0, "%.1f") then changed = true end
        if imgui.SliderFloat("Дальность (м)", c_render_dist, 100.0, 5000.0, "%.0f") then changed = true end

        local current_icon_name = "Квадрат"
        for _, icon in ipairs(icon_list) do
            if icon.id == S.icon_type then current_icon_name = icon.name end
        end
        if imgui.BeginCombo("Иконка метки", current_icon_name) then
            for _, icon in ipairs(icon_list) do
                local selected = (icon.id == S.icon_type)
                if imgui.Selectable(icon.name, selected) then
                    S.icon_type = icon.id
                    changed = true
                end
                if selected then imgui.SetItemDefaultFocus() end
            end
            imgui.EndCombo()
        end
        imgui.PopItemWidth()

        if imgui.Checkbox("Свой цвет для каждого игрока", c_author_colors) then changed = true end

        if imgui.Checkbox("Удалять свою метку при подходе", c_arrive_remove) then changed = true end
        if c_arrive_remove[0] then
            imgui.PushItemWidth(180)
            if imgui.SliderFloat("Радиус подхода (м)", c_arrive_radius, 1.0, 15.0, "%.1f") then changed = true end
            imgui.PopItemWidth()
        end

        imgui.Text("Клавиша метки: " .. key_name(S.ping_key))
        if binding_key then
            imgui.TextColored(imgui.ImVec4(0.82, 0.75, 0.42, 1.0), "Нажмите клавишу (Esc - отмена)")
        else
            if imgui.Button("Изменить клавишу", imgui.ImVec2(200, 0)) then
                start_binding()
            end
        end
    end

    if imgui.CollapsingHeader("Авто-метка на себя") then
        local mode_names = {"По секундам", "По метрам", "По секундам и метрам"}
        imgui.PushItemWidth(220)
        if imgui.BeginCombo("Режим обновления", mode_names[S.track_mode + 1] or mode_names[3]) then
            for i, name in ipairs(mode_names) do
                local selected = (S.track_mode == i - 1)
                if imgui.Selectable(name, selected) then
                    S.track_mode = i - 1
                    changed = true
                end
                if selected then imgui.SetItemDefaultFocus() end
            end
            imgui.EndCombo()
        end

        if S.track_mode ~= 1 then
            if imgui.SliderFloat("Интервал (сек)", c_track_interval, 2.0, 30.0, "%.1f") then changed = true end
        end
        if S.track_mode ~= 0 then
            if imgui.SliderFloat("Расстояние (м)", c_track_move_threshold, 1.0, 50.0, "%.1f") then changed = true end
        end
        imgui.PopItemWidth()

        imgui.Text("Статус:")
        if tracking then
            imgui.SameLine()
            imgui.TextColored(imgui.ImVec4(0.35, 0.82, 0.70, 1.0), "ВКЛ")
            if imgui.Button("Выключить авто-метку", imgui.ImVec2(200, 0)) then
                set_tracking(false)
            end
        else
            imgui.SameLine()
            imgui.TextColored(imgui.ImVec4(0.85, 0.55, 0.35, 1.0), "ВЫКЛ")
            if imgui.Button("Включить авто-метку", imgui.ImVec2(200, 0)) then
                set_tracking(true)
            end
        end
    end

    if imgui.CollapsingHeader("Текст метки") then
        if imgui.Checkbox("Показывать дистанцию", c_show_distance) then changed = true end
        if imgui.Checkbox("Показывать имя автора", c_show_author) then changed = true end
        if imgui.Checkbox("Показывать время жизни", c_show_lifetime) then changed = true end

        imgui.PushItemWidth(180)

        if imgui.BeginCombo("Шрифт", S.font_name) then
            for _, name in ipairs(font_list) do
                local selected = (name == S.font_name)
                if imgui.Selectable(name, selected) then
                    S.font_name = name
                    request_font_rebuild()
                    changed = true
                end
                if selected then imgui.SetItemDefaultFocus() end
            end
            imgui.EndCombo()
        end

        if imgui.SliderInt("Размер шрифта", c_font_size, 8, 30) then
            S.font_size = c_font_size[0]
            request_font_rebuild()
            changed = true
        end

        local current_flag_name = "Обычный"
        for _, f in ipairs(font_flags_list) do
            if f.flag == S.font_flags then current_flag_name = f.name end
        end
        if imgui.BeginCombo("Стиль шрифта", current_flag_name) then
            for _, f in ipairs(font_flags_list) do
                local selected = (f.flag == S.font_flags)
                if imgui.Selectable(f.name, selected) then
                    S.font_flags = f.flag
                    request_font_rebuild()
                    changed = true
                end
                if selected then imgui.SetItemDefaultFocus() end
            end
            imgui.EndCombo()
        end

        if imgui.ColorEdit3("Цвет текста", c_font_color) then
            S.font_r, S.font_g, S.font_b = c_font_color[0], c_font_color[1], c_font_color[2]
            changed = true
        end

        if imgui.SliderFloat("Прозрачность", c_alpha, 0.1, 1.0, "%.2f") then
            S.alpha = c_alpha[0]
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

    if imgui.CollapsingHeader("Защита от спама") then
        imgui.PushItemWidth(180)
        if imgui.SliderFloat("Пауза между метками игрока (сек)", c_incoming_cd, 0.0, 10.0, "%.1f") then changed = true end
        imgui.PopItemWidth()

        if S.fb_color ~= 0 then
            imgui.TextColored(imgui.ImVec4(0.40, 0.82, 0.65, 1.0), "Фильтр цвета чата: включён")
        else
            imgui.TextColored(imgui.ImVec4(0.82, 0.75, 0.42, 1.0), "Фильтр цвета чата: выключен")
        end
        if learning_color then
            imgui.TextColored(imgui.ImVec4(0.82, 0.75, 0.42, 1.0), "Ждём групповую метку...")
        else
            if imgui.Button("Откалибровать цвет", imgui.ImVec2(200, 0)) then
                start_learning()
            end
        end
        if S.fb_color ~= 0 then
            if imgui.Button("Выключить фильтр", imgui.ImVec2(200, 0)) then
                S.fb_color = 0
                changed = true
            end
        end
    end

    if imgui.CollapsingHeader("Обновление") then
        imgui.Text("Версия: " .. SCRIPT_VERSION)
        if update_state.remote_version then
            imgui.Text("На GitHub: " .. update_state.remote_version)
        end
        imgui.TextColored(imgui.ImVec4(0.72, 0.76, 0.78, 1.0), update_state.status)
        if imgui.Checkbox("Проверять обновления при запуске", c_auto_update) then changed = true end

        if update_state.busy then
            imgui.TextColored(imgui.ImVec4(0.82, 0.75, 0.42, 1.0), "Подождите...")
        else
            if imgui.Button("Проверить обновления", imgui.ImVec2(200, 0)) then
                check_and_update(false)
            end
        end
    end

    if changed then
        S.cooldown = c_cooldown[0]
        S.ping_lifetime = c_lifetime[0]
        S.render_dist = c_render_dist[0]
        S.ping_size = c_size[0]
        S.ping_r, S.ping_g, S.ping_b = c_color[0], c_color[1], c_color[2]
        S.notifications = c_notifications[0]
        S.notification_sound = c_notification_sound[0]
        S.show_distance = c_show_distance[0]
        S.show_author = c_show_author[0]
        S.show_lifetime = c_show_lifetime[0]
        S.offscreen_arrows = c_offscreen_arrows[0]
        S.offscreen_margin = c_offscreen_margin[0]
        S.offscreen_size = c_offscreen_size[0]
        S.fade_time = c_fade[0]
        S.author_colors = c_author_colors[0]
        S.incoming_cooldown = c_incoming_cd[0]
        S.auto_update = c_auto_update[0]
        S.track_interval = max(2.0, c_track_interval[0])
        S.track_move_threshold = max(1.0, c_track_move_threshold[0])
        S.arrive_remove = c_arrive_remove[0]
        S.arrive_radius = max(1.0, c_arrive_radius[0])
        schedule_save()
    end

    imgui.End()
end)

local function destroy_ping(ping)
    if ping.blip then
        removeBlip(ping.blip)
        ping.blip = nil
    end
    if ping.checkpoint then
        deleteCheckpoint(ping.checkpoint)
        ping.checkpoint = nil
    end
end

local function remove_ping(i)
    destroy_ping(active_pings[i])
    remove(active_pings, i)
end

local function notify_ping(author, x, y, z)
    if S.notifications then
        local dist = getDistanceBetweenCoords3d(frame_px, frame_py, frame_pz, x, y, z)
        msg(format("%s поставил метку, {A8E8D8}%.0f м", tostring(author), dist))
    end
    if S.notification_sound then
        addOneOffSound(0.0, 0.0, 0.0, 1056)
    end
end

local function find_duplicate_ping(x, y, z)
    local radius = S.dedupe_radius or 12.0
    local r2 = radius * radius
    for i = #active_pings, 1, -1 do
        local ping = active_pings[i]
        local dx, dy, dz = ping.x - x, ping.y - y, ping.z - z
        if dx * dx + dy * dy + dz * dz <= r2 then
            return ping
        end
    end
    return nil
end

local function remove_pings_by_author(author)
    for i = #active_pings, 1, -1 do
        local ping = active_pings[i]
        if ping.author == author and not ping.pinned then
            remove_ping(i)
        end
    end
end

local function add_ping(x, y, z, author, local_ping)
    remove_pings_by_author(author)

    local duplicate = find_duplicate_ping(x, y, z)
    if duplicate then
        if not duplicate.pinned then duplicate.time = clock() end
        return duplicate, false
    end

    x = tonumber(x) or 0
    y = tonumber(y) or 0
    z = tonumber(z) or 0

    local blip = addSpriteBlipForCoord(x, y, z, 41)
    local checkpoint = createCheckpoint(1, x, y, z, x, y, z, 5.0)
    if blip then changeBlipColour(blip, 2) end

    local now = clock()
    local ping = {
        x = x, y = y, z = z,
        time = now,
        born = now,
        author = author,
        own = local_ping and true or false,
        blip = blip,
        checkpoint = checkpoint,
        pinned = false
    }
    insert(active_pings, ping)
    if not local_ping then notify_ping(author, x, y, z) end
    return ping, true
end

local function clear_all_pings()
    for i = #active_pings, 1, -1 do
        remove_ping(i)
    end
    msg("Метки очищены.")
end

local function toggle_last_ping_pin()
    local ping = active_pings[#active_pings]
    if not ping then
        msg("Нет активных меток.")
        return
    end
    ping.pinned = not ping.pinned
    if ping.pinned then
        msg("Метка закреплена.")
    else
        ping.time = clock()
        msg("Метка откреплена.")
    end
end

local function send_ping_at(tx, ty, tz, silent)
    local send_x = floor(tx + 0.5)
    local send_y = floor(ty + 0.5)
    local send_z = floor(tz + 0.5)

    if not silent then
        add_ping(tx, ty, tz, get_my_name(), true)
        msg(format("Метка отправлена: %d %d %d", send_x, send_y, send_z))
    end
    sampSendChat(format("/fb %d %d %d", send_x, send_y, send_z))
end

local function cooldown_ok()
    local time_passed = clock() - last_ping_time
    if time_passed >= S.cooldown then
        return true
    end
    msg(format("Подождите %.1f сек.", S.cooldown - time_passed))
    return false
end

local function place_ping_marker()
    if not cooldown_ok() then return end

    local start_x, start_y
    if memory.getuint8(0xB6F1A8) == 53 then
        start_x, start_y = convertGameScreenCoordsToWindowScreenCoords(339.5, 179.2)
    else
        start_x, start_y = frame_resX * 0.5, frame_resY * 0.5
    end

    local cam_x, cam_y, cam_z = getActiveCameraCoordinates()
    local cross_x, cross_y, cross_z = convertScreenCoordsToWorld3D(start_x, start_y, S.render_dist)

    local result, pointer = processLineOfSight(cam_x, cam_y, cam_z, cross_x, cross_y, cross_z, true, true, false, true, true, false, false)

    local tx, ty, tz
    if result and pointer then
        tx, ty, tz = pointer.pos[1], pointer.pos[2], pointer.pos[3] + 0.5
    else
        tx, ty, tz = cross_x, cross_y, cross_z
    end

    send_ping_at(tx, ty, tz)
    last_ping_time = clock()
end

local function place_self_ping()
    if not cooldown_ok() then return end
    local px, py, pz = getCharCoordinates(PLAYER_PED)
    send_ping_at(px, py, pz)
    last_ping_time = clock()
end

local TRACK_MIN_INTERVAL = 2.0

local function tracking_ping(px, py, pz)
    local now = clock()
    if now - last_track < TRACK_MIN_INTERVAL then return false end

    send_ping_at(px, py, pz, true)
    last_track = now
    last_track_x, last_track_y, last_track_z = px, py, pz
    return true
end

local function tracking_update(px, py, pz)
    if not tracking then return end
    if not sampIsLocalPlayerSpawned() or isCharDead(PLAYER_PED) then return end

    local mode = S.track_mode or 2
    local fire = false

    if last_track_x == nil then
        fire = true
    else
        local interval = max(TRACK_MIN_INTERVAL, S.track_interval or 5.0)
        local interval_ready = (clock() - last_track) >= interval

        local dx = px - last_track_x
        local dy = py - last_track_y
        local dz = pz - last_track_z
        local threshold = max(1.0, S.track_move_threshold or 12.0)
        local moved = (dx * dx + dy * dy + dz * dz) >= threshold * threshold

        if mode == 0 then
            fire = interval_ready
        elseif mode == 1 then
            fire = moved
        else
            fire = moved or interval_ready
        end
    end

    if fire then tracking_ping(px, py, pz) end
end

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    rebuild_font()

    msg(format("v%s | {A8E8D8}/pmenu /ppin /pclear /pself /ptrack /pcolor", SCRIPT_VERSION))

    sampRegisterChatCommand('ping', place_ping_marker)
    sampRegisterChatCommand('pself', place_self_ping)
    sampRegisterChatCommand('ptrack', function() set_tracking(not tracking) end)
    sampRegisterChatCommand('pmenu', function() menu_state[0] = not menu_state[0] end)
    sampRegisterChatCommand('ppin', toggle_last_ping_pin)
    sampRegisterChatCommand('pclear', clear_all_pings)
    sampRegisterChatCommand('pcolor', function(arg)
        if arg and lower(arg):find("off") then
            S.fb_color = 0
            learning_color = false
            schedule_save()
            msg("Фильтр цвета выключен.")
        else
            start_learning()
        end
    end)

    lua_thread.create(function()
        wait(5000)
        if S.auto_update then check_and_update(true) end
    end)

    while true do
        wait(0)

        frame_now = clock()
        if font_rebuild_at and frame_now >= font_rebuild_at then rebuild_font() end
        if save_at and frame_now >= save_at then save_cfg() end

        if binding_key then
            if frame_now > bind_ready then
                if wasKeyPressed(vkeys.VK_ESCAPE) then
                    binding_key = false
                else
                    for k = 2, 254 do
                        if k ~= vkeys.VK_ESCAPE and wasKeyPressed(k) then
                            S.ping_key = k
                            binding_key = false
                            schedule_save()
                            msg(format("Клавиша метки: {A8E8D8}%s", key_name(k)))
                            break
                        end
                    end
                end
            end
        elseif wasKeyPressed(S.ping_key) and not input_blocked() then
            place_ping_marker()
        end

        frame_px, frame_py, frame_pz = getCharCoordinates(PLAYER_PED)
        frame_resX, frame_resY = getScreenResolution()

        tracking_update(frame_px, frame_py, frame_pz)

        local n = #active_pings
        if n == 0 then goto continue end

        local lifetime = S.ping_lifetime
        local fade = S.fade_time
        local alpha0 = S.alpha
        local arrive = S.arrive_remove
        local arrive_r = max(1.0, S.arrive_radius or 4.0)
        local arrive_r2 = arrive_r * arrive_r
        local grace = S.arrive_grace or 1.5
        local offscreen = S.offscreen_arrows
        local icon4 = (S.icon_type == 4)

        for i = n, 1, -1 do
            local ping = active_pings[i]
            local age = frame_now - ping.time

            if not ping.pinned and age > lifetime then
                remove_ping(i)
            else
                local alpha = alpha0
                local left = lifetime - age
                if not ping.pinned and fade > 0 and left < fade then
                    alpha = alpha * max(left, 0) / fade
                end

                local arrived = false
                if arrive and ping.own and not ping.pinned then
                    if (frame_now - ping.born) >= grace then
                        local dx = frame_px - ping.x
                        local dy = frame_py - ping.y
                        local dz = frame_pz - ping.z
                        if dx * dx + dy * dy + dz * dz <= arrive_r2 then
                            remove_ping(i)
                            arrived = true
                        end
                    end
                end

                if not arrived then
                    local r, g, b = get_ping_rgb(ping)
                    local sx, sy, in_front = project_point(ping.x, ping.y, ping.z)

                    if in_front and sx and sy and sx >= 0 and sy >= 0 and sx <= frame_resX and sy <= frame_resY then
                        local dist = getDistanceBetweenCoords3d(frame_px, frame_py, frame_pz, ping.x, ping.y, ping.z)
                        local extent, label_y
                        if icon4 then
                            extent, label_y = draw_ring_marker(sx, sy, ping, r, g, b, alpha, frame_now, dist, left)
                        else
                            draw_ping_icon(sx, sy, S.ping_size, pack_color(r, g, b, alpha))
                            extent = S.ping_size * 0.5 + 2
                            label_y = sy
                        end
                        draw_ping_label(sx + extent + 6, label_y or sy, ping, dist, r, g, b, alpha)
                    elseif offscreen then
                        draw_offscreen_arrow(ping, r, g, b, alpha)
                    end
                end
            end
        end

        ::continue::
    end
end

function sampev.onServerMessage(color, text)
    local clean_text = gsub(text, "{%x%x%x%x%x%x}", "")

    if find(clean_text, STR_NOGROUP, 1, true) then
        local my_name = get_my_name()
        if tracking then
            tracking = false
            msg("Слежение выключено: вы не в группе.")
        end
        for i = #active_pings, 1, -1 do
            if active_pings[i].author == my_name and (clock() - active_pings[i].time) < 3.0 then
                remove_ping(i)
                msg("Вы не состоите в группе, метка отменена.")
                break
            end
        end
        return
    end

    local author, x_str, y_str, z_str = match(clean_text, PING_PATTERN)
    if not (author and x_str and y_str and z_str) then return end

    if learning_color then
        learning_color = false
        S.fb_color = color
        schedule_save()
        msg("Цвет чата запомнен, метки из других чатов игнорируются.")
    end

    if S.fb_color ~= 0 and color ~= S.fb_color then return end

    if author == get_my_name() then return end

    local now = clock()
    local last = last_incoming[author]
    if last and now - last < S.incoming_cooldown then return end
    last_incoming[author] = now

    local tx, ty, tz = tonumber(x_str), tonumber(y_str), tonumber(z_str)
    if not (tx and ty and tz) then return end

    if tz == 0 then
        local ground = getGroundZFor3dCoord(tx, ty, 300.0)
        if type(ground) == "number" and ground ~= 0 then tz = ground end
    end

    add_ping(tx, ty, tz, author, false)
end

function onScriptTerminate(script, quitGame)
    if script == thisScript() then
        for _, ping in ipairs(active_pings) do
            destroy_ping(ping)
        end
        if save_at then inicfg.save(cfg, iniFileName) end
        if ping_font then renderReleaseFont(ping_font) end
        if ping_font_small then renderReleaseFont(ping_font_small) end
    end
end
