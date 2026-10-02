script_name('Tactical Ping')
script_author('afk111')

local sampev = require 'lib.samp.events'
local memory = require 'memory'
local vkeys = require 'vkeys'
local imgui = require 'mimgui'
local inicfg = require 'inicfg'
local bit = require 'bit'
local encoding = require 'encoding'

-- Файл должен быть сохранён в UTF-8 (без BOM). Для чата строки перекодируются в CP1251.
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local function cp(s) return u8:decode(s) end

local SCRIPT_VERSION = "1.1.0"

-- ============ НАСТРОЙКИ ============
local iniFileName = 'TacticalPing.ini'
-- inicfg не умеет хранить таблицы, поэтому цвета лежат в отдельных ключах.
-- Недостающие ключи inicfg.load подставляет из значений по умолчанию сам.
local cfg = inicfg.load({
    settings = {
        cooldown = 5.0,
        ping_lifetime = 8.0,
        render_dist = 700.0,
        ping_size = 8,
        ping_r = 0.2, ping_g = 1.0, ping_b = 0.2,
        notifications = true,
        notification_sound = true,
        dedupe_radius = 12.0,
        show_distance = true,
        show_author = true,
        show_lifetime = true,
        font_name = "Tahoma",
        font_size = 11,
        font_flags = 5,
        font_r = 1.0, font_g = 1.0, font_b = 1.0,
        alpha = 1.0,
        icon_type = 0,
        offscreen_arrows = true,
        offscreen_margin = 60,
        offscreen_size = 18,
        ping_key = vkeys.VK_MBUTTON,
        fade_time = 1.0,
        author_colors = true,
        incoming_cooldown = 2.0,
        fb_color = 0,
        auto_update = true
    }
}, iniFileName)
inicfg.save(cfg, iniFileName)

-- Строки, декодированные один раз при загрузке
local STR_GOAL = cp("ЦЕЛЬ")
local STR_FROM = cp("От:")
local STR_M = cp("м")
local STR_LEFT = cp("ост.")
local STR_NOGROUP = cp("%[Ошибка%] Вы не состоите в группе!")

-- Формат: Ник[ID]: (( X Y Z
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
    {name = "Крест", id = 3}
}

-- ============ ПЕРЕМЕННЫЕ imgui ============
local S = cfg.settings
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

-- ============ СОСТОЯНИЕ ============
local active_pings = {}
local last_ping_time = 0
local ping_font = nil
local font_rebuild_at = nil
local save_at = nil
local binding_key = false
local bind_ready = 0
local learning_color = false
local last_incoming = {}
local author_cache = {}

-- ============ АВТООБНОВЛЕНИЕ ============
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

-- Ждёт именно окончания загрузки (callback), а не просто появления файла.
-- Вызывать только из lua_thread (внутри используется wait).
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
                sampAddChatMessage(cp("{FF0000}[Tactical Ping] {FFFFFF}" .. chat_text), -1)
            end
        end

        -- 1. Версия на сервере
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
                sampAddChatMessage(cp(string.format("{00FF88}[Tactical Ping] {FFFFFF}У вас последняя версия: {FFFF00}%s", SCRIPT_VERSION)), -1)
            end
            return
        end

        -- 2. Скачивание новой версии
        update_state.status = "Скачивание " .. remote_ver .. "..."
        sampAddChatMessage(cp(string.format("{00FF88}[Tactical Ping] {FFFFFF}Найдена новая версия {FFFF00}%s{FFFFFF}. Скачиваю...", remote_ver)), -1)

        if not download_file(UPDATE_URL_SCRIPT, UPDATE_TMP, 20000) then
            return fail("Ошибка скачивания скрипта", "Не удалось скачать обновление.")
        end

        -- 3. Проверка содержимого: это должен быть целый Lua-скрипт
        local content = read_file(UPDATE_TMP)
        os.remove(UPDATE_TMP)
        if not content or #content < 2000
           or not content:find("script_name", 1, true)
           or not content:find("function main", 1, true) then
            return fail("Ошибка: файл повреждён", "Скачанный файл повреждён или пуст.")
        end

        -- 4. Бэкап текущей версии и замена
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
        sampAddChatMessage(cp(string.format("{00FF88}[Tactical Ping] {FFFFFF}Обновлено до {FFFF00}%s{FFFFFF}. Скрипт перезагрузится. Старая версия сохранена в .bak", remote_ver)), -1)
        wait(1500)
        thisScript():reload()
    end)
end

-- ============ ВСПОМОГАТЕЛЬНОЕ ============
local function save_cfg()
    save_at = nil
    inicfg.save(cfg, iniFileName)
end

-- Сохранение с задержкой, чтобы не писать на диск каждый кадр при движении слайдера
local function schedule_save()
    save_at = os.clock() + 1.0
end

local function rebuild_font()
    font_rebuild_at = nil
    local old = ping_font
    ping_font = renderCreateFont(S.font_name, S.font_size, S.font_flags)
    if old then renderReleaseFont(old) end
end

local function request_font_rebuild()
    font_rebuild_at = os.clock() + 0.25
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
    return bit.bor(
        bit.lshift(math.floor(a * 255 + 0.5), 24),
        bit.lshift(math.floor(r * 255 + 0.5), 16),
        bit.lshift(math.floor(g * 255 + 0.5), 8),
        math.floor(b * 255 + 0.5)
    )
end

local function hsv2rgb(h, s, v)
    local i = math.floor(h * 6)
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

-- Стабильный цвет для каждого ника
local function author_rgb(name)
    local c = author_cache[name]
    if not c then
        local h = 0
        for i = 1, #name do h = (h * 31 + name:byte(i)) % 360 end
        local r, g, b = hsv2rgb(h / 360, 0.75, 1.0)
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
    bind_ready = os.clock() + 0.3
end

local function start_learning()
    learning_color = true
    sampAddChatMessage(cp("{FFAA00}[Tactical Ping] {FFFFFF}Ждём групповую метку. Поставьте метку через /fb или попросите союзника - цвет сообщения запомнится."), -1)
end

-- ============ ОТРИСОВКА ============
local function draw_ping_icon(sx, sy, size, color)
    local half = size / 2
    local icon = S.icon_type

    if icon == 0 then
        renderDrawBox(sx - half, sy - half, size, size, color)
    elseif icon == 1 then
        -- треугольник вершиной вниз
        for i = 0, size - 1 do
            local w = size - i
            renderDrawBox(sx - w / 2, sy - half + i, w, 1, color)
        end
    elseif icon == 2 then
        for i = 0, size - 1 do
            local w
            if i <= half then w = i * 2 else w = (size - i) * 2 end
            if w < 1 then w = 1 end
            renderDrawBox(sx - w / 2, sy - half + i, w, 1, color)
        end
    elseif icon == 3 then
        renderDrawBox(sx - half, sy - size / 8, size, size / 4, color)
        renderDrawBox(sx - size / 8, sy - half, size / 4, size, color)
    end
end

-- Стрелка у края экрана (направление считается от центра, метки за спиной учитываются)
local function draw_offscreen_arrow(ping, color)
    local resX, resY = getScreenResolution()
    local cx, cy = resX / 2, resY / 2

    local sx, sy = convert3DCoordsToScreen(ping.x, ping.y, ping.z)
    if not sx or not sy then return end

    local dx, dy = sx - cx, sy - cy

    -- Для точек позади камеры экранные координаты зеркальны - разворачиваем направление
    local camx, camy, camz = getActiveCameraCoordinates()
    local lx, ly, lz = getActiveCameraPointAt()
    local dot = (ping.x - camx) * (lx - camx) + (ping.y - camy) * (ly - camy) + (ping.z - camz) * (lz - camz)
    if dot < 0 then dx, dy = -dx, -dy end

    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then
        dx, dy, len = 0, 1, 1 -- метка точно за спиной: стрелка вниз
    end
    dx, dy = dx / len, dy / len

    -- Точка пересечения луча из центра с прямоугольником с отступом
    local margin = S.offscreen_margin
    local hw, hh = cx - margin, cy - margin
    local tx = math.abs(dx) > 1e-4 and hw / math.abs(dx) or math.huge
    local ty = math.abs(dy) > 1e-4 and hh / math.abs(dy) or math.huge
    local t = math.min(tx, ty)
    local ax, ay = cx + dx * t, cy + dy * t

    local size = S.offscreen_size
    local tip_len = size * 0.7
    local base_half = size * 0.6
    local perp_x, perp_y = -dy, dx

    local tip_x, tip_y = ax + dx * tip_len, ay + dy * tip_len
    local bx, by = ax - dx * tip_len * 0.5, ay - dy * tip_len * 0.5
    local b1x, b1y = bx + perp_x * base_half, by + perp_y * base_half
    local b2x, b2y = bx - perp_x * base_half, by - perp_y * base_half

    -- Заливка треугольника линиями от вершины к основанию (мало вызовов отрисовки)
    local steps = 6
    for k = 0, steps do
        local f = k / steps
        renderDrawLine(tip_x, tip_y, b1x + (b2x - b1x) * f, b1y + (b2y - b1y) * f, 2, color)
    end
    renderDrawLine(b1x, b1y, b2x, b2y, 2, color)
end

-- ============ МЕНЮ ============
imgui.OnInitialize(function()
    local io = imgui.GetIO()
    io.IniFilename = nil

    -- Кириллический шрифт, иначе русский текст в меню показывается как "????"
    local font_path = getFolderPath(0x14) .. '\\arial.ttf'
    if doesFileExist(font_path) then
        io.Fonts:AddFontFromFileTTF(font_path, 16, nil, io.Fonts:GetGlyphRangesCyrillic())
    end

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

imgui.OnFrame(function() return menu_state[0] end, function()
    imgui.SetNextWindowSize(imgui.ImVec2(460, 680), imgui.Cond.FirstUseEver)
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
        if imgui.SliderFloat("Дальность (м)", c_render_dist, 100.0, 2000.0, "%.0f") then changed = true end

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

        imgui.Text("Клавиша метки: " .. key_name(S.ping_key))
        if binding_key then
            imgui.TextColored(imgui.ImVec4(1.0, 0.8, 0.2, 1.0), "Нажмите клавишу (Esc - отмена)")
        else
            if imgui.Button("Изменить клавишу", imgui.ImVec2(200, 0)) then
                start_binding()
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
            imgui.TextColored(imgui.ImVec4(0.3, 1.0, 0.3, 1.0), "Фильтр цвета чата: включён")
        else
            imgui.TextColored(imgui.ImVec4(1.0, 0.8, 0.2, 1.0), "Фильтр цвета чата: выключен")
        end
        if learning_color then
            imgui.TextColored(imgui.ImVec4(1.0, 0.8, 0.2, 1.0), "Ждём групповую метку...")
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
        imgui.TextColored(imgui.ImVec4(0.8, 0.8, 0.8, 1.0), update_state.status)
        if imgui.Checkbox("Проверять обновления при запуске", c_auto_update) then changed = true end

        if update_state.busy then
            imgui.TextColored(imgui.ImVec4(1.0, 0.8, 0.2, 1.0), "Подождите...")
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
        schedule_save()
    end

    imgui.End()
end)

-- ============ МЕТКИ ============
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
    table.remove(active_pings, i)
end

local function notify_ping(author, x, y, z)
    if S.notifications then
        local px, py, pz = getCharCoordinates(PLAYER_PED)
        local dist = getDistanceBetweenCoords3d(px, py, pz, x, y, z)
        sampAddChatMessage(cp(string.format("{00FF88}[Tactical Ping] {FFFFFF}%s поставил метку. Расстояние: {FFFF00}%.0f м", tostring(author), dist)), -1)
    end
    if S.notification_sound then
        addOneOffSound(0.0, 0.0, 0.0, 1056)
    end
end

local function find_duplicate_ping(x, y, z)
    local radius = tonumber(S.dedupe_radius) or 12.0
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
            remove_ping(i)
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
        own = local_ping and true or false,
        blip = blip,
        checkpoint = checkpoint,
        pinned = false
    }
    table.insert(active_pings, ping)
    if not local_ping then notify_ping(author, x, y, z) end
    return ping, true
end

local function clear_all_pings()
    for i = #active_pings, 1, -1 do
        remove_ping(i)
    end
    sampAddChatMessage(cp("{00FF88}[Tactical Ping] {FFFFFF}Все метки и чекпоинты очищены."), -1)
end

local function toggle_last_ping_pin()
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

-- ============ ОТПРАВКА МЕТКИ ============
local function send_ping_at(tx, ty, tz)
    -- Округляем, а не отбрасываем дробную часть, чтобы метка у союзников не уезжала вниз
    local send_x = math.floor(tx + 0.5)
    local send_y = math.floor(ty + 0.5)
    local send_z = math.floor(tz + 0.5)

    add_ping(tx, ty, tz, get_my_name(), true)

    sampAddChatMessage(cp(string.format("{00FF00}[Tactical Ping] {FFFFFF}Метка отправлена через {FFFF00}/fb {FFFFFF}[Точка: %d, %d, %d]", send_x, send_y, send_z)), -1)
    sampSendChat(string.format("/fb %d %d %d", send_x, send_y, send_z))
end

local function cooldown_ok()
    local time_passed = os.clock() - last_ping_time
    if time_passed >= S.cooldown then
        return true
    end
    sampAddChatMessage(cp(string.format("{FF0000}[Tactical Ping] {FFFFFF}Подождите %.1f сек. перед следующей меткой!", S.cooldown - time_passed)), -1)
    return false
end

local function place_ping_marker()
    if not cooldown_ok() then return end

    local start_x, start_y
    -- 0xB6F1A8 - режим камеры; 53 - режим прицеливания, прицел смещён от центра экрана
    if memory.getuint8(0xB6F1A8) == 53 then
        start_x, start_y = convertGameScreenCoordsToWindowScreenCoords(339.5, 179.2)
    else
        local resX, resY = getScreenResolution()
        start_x, start_y = resX / 2, resY / 2
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
    last_ping_time = os.clock()
end

local function place_self_ping()
    if not cooldown_ok() then return end
    local px, py, pz = getCharCoordinates(PLAYER_PED)
    send_ping_at(px, py, pz)
    last_ping_time = os.clock()
end

-- ============ ГЛАВНЫЙ ЦИКЛ ============
function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    rebuild_font()
    math.randomseed(os.time() + math.floor(os.clock() * 1000000))

    sampAddChatMessage(cp(string.format("{00FF00}[Tactical Ping] {FFFFFF}Скрипт загружен! Версия: {FFFF00}%s", SCRIPT_VERSION)), -1)
    sampAddChatMessage(cp("{00FF00}[Tactical Ping] {FFFFFF}Меню: {FFFF00}/pmenu {FFFFFF}| Закрепить: {FFFF00}/ppin {FFFFFF}| Очистить: {FFFF00}/pclear {FFFFFF}| На себя: {FFFF00}/pself {FFFFFF}| Фильтр цвета: {FFFF00}/pcolor"), -1)

    sampRegisterChatCommand('ping', place_ping_marker)
    sampRegisterChatCommand('pself', place_self_ping)
    sampRegisterChatCommand('pmenu', function() menu_state[0] = not menu_state[0] end)
    sampRegisterChatCommand('ppin', toggle_last_ping_pin)
    sampRegisterChatCommand('pclear', clear_all_pings)
    sampRegisterChatCommand('pcolor', function(arg)
        if arg and arg:lower():find("off") then
            S.fb_color = 0
            learning_color = false
            schedule_save()
            sampAddChatMessage(cp("{00FF88}[Tactical Ping] {FFFFFF}Фильтр цвета чата выключен."), -1)
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

        if font_rebuild_at and os.clock() >= font_rebuild_at then rebuild_font() end
        if save_at and os.clock() >= save_at then save_cfg() end

        -- Назначение клавиши
        if binding_key then
            if os.clock() > bind_ready then
                if wasKeyPressed(vkeys.VK_ESCAPE) then
                    binding_key = false
                else
                    for k = 2, 254 do
                        if k ~= vkeys.VK_ESCAPE and wasKeyPressed(k) then
                            S.ping_key = k
                            binding_key = false
                            schedule_save()
                            sampAddChatMessage(cp(string.format("{00FF88}[Tactical Ping] {FFFFFF}Клавиша метки: {FFFF00}%s", key_name(k))), -1)
                            break
                        end
                    end
                end
            end
        elseif wasKeyPressed(S.ping_key) and not input_blocked() then
            place_ping_marker()
        end

        -- Отрисовка и удаление меток
        local now = os.clock()
        local px, py, pz = getCharCoordinates(PLAYER_PED)

        for i = #active_pings, 1, -1 do
            local ping = active_pings[i]
            local age = now - ping.time

            if not ping.pinned and age > S.ping_lifetime then
                remove_ping(i)
            else
                local alpha = S.alpha
                local left = S.ping_lifetime - age
                if not ping.pinned and S.fade_time > 0 and left < S.fade_time then
                    alpha = alpha * math.max(left, 0) / S.fade_time
                end

                local r, g, b = get_ping_rgb(ping)
                local color = pack_color(r, g, b, alpha)

                if isPointOnScreen(ping.x, ping.y, ping.z, 0.0) then
                    local sx, sy = convert3DCoordsToScreen(ping.x, ping.y, ping.z)
                    if sx and sy then
                        local p_sz = S.ping_size
                        draw_ping_icon(sx, sy, p_sz, color)

                        local first_line = STR_GOAL
                        if S.show_distance then
                            local dist = getDistanceBetweenCoords3d(px, py, pz, ping.x, ping.y, ping.z)
                            first_line = first_line .. string.format(" [%.1f%s]", dist, STR_M)
                        end
                        if S.show_lifetime and not ping.pinned then
                            first_line = first_line .. string.format(" (%s %.1f)", STR_LEFT, math.max(left, 0))
                        end

                        local text = first_line
                        if S.show_author then
                            text = text .. "\n" .. STR_FROM .. " " .. ping.author .. (ping.pinned and " [PIN]" or "")
                        end

                        local font_color = pack_color(S.font_r, S.font_g, S.font_b, alpha)
                        renderFontDrawText(ping_font, text, sx + p_sz + 4, sy - 12, font_color)
                    end
                elseif S.offscreen_arrows then
                    draw_offscreen_arrow(ping, color)
                end
            end
        end
    end
end

-- ============ ЧАТ ============
function sampev.onServerMessage(color, text)
    local clean_text = (text:gsub("{%x%x%x%x%x%x}", ""))

    if clean_text:find(STR_NOGROUP) then
        local my_name = get_my_name()
        for i = #active_pings, 1, -1 do
            if active_pings[i].author == my_name and (os.clock() - active_pings[i].time) < 3.0 then
                remove_ping(i)
                sampAddChatMessage(cp("{FF0000}[Tactical Ping] {FFFFFF}Отмена: Вы не состоите в группе!"), -1)
                break
            end
        end
        return
    end

    local author, x_str, y_str, z_str = clean_text:match(PING_PATTERN)
    if not (author and x_str and y_str and z_str) then return end

    -- Калибровка: запоминаем цвет настоящего группового сообщения
    if learning_color then
        learning_color = false
        S.fb_color = color
        schedule_save()
        sampAddChatMessage(cp("{00FF88}[Tactical Ping] {FFFFFF}Цвет группового чата запомнен, остальные сообщения вида (( X Y Z будут игнорироваться."), -1)
    end

    -- Фильтр по цвету: сообщения из /b и других чатов не должны ставить метки
    if S.fb_color ~= 0 and color ~= S.fb_color then return end

    if author == get_my_name() then return end

    -- Защита от спама метками
    local now = os.clock()
    local last = last_incoming[author]
    if last and now - last < S.incoming_cooldown then return end
    last_incoming[author] = now

    local tx, ty, tz = tonumber(x_str), tonumber(y_str), tonumber(z_str)
    if not (tx and ty and tz) then return end

    -- Используем присланную высоту; землю берём только если высота не передана
    if tz == 0 then
        local ground = getGroundZFor3dCoord(tx, ty, 300.0)
        if ground and ground ~= 0 then tz = ground end
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
    end
end
