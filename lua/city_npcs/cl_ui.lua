CityNPCs = CityNPCs or {}
CityNPCs.StaticPropDebug = CityNPCs.StaticPropDebug or {
    loaded = false,
    map = nil,
    props = {},
    lastError = nil,
}
 
local function readCStringFixed(str)
    return (str and str:match("^[^%z]+")) or ""
end

local function loadStaticPropsForDebug()
    local curMap = game.GetMap()
    if CityNPCs.StaticPropDebug.loaded and CityNPCs.StaticPropDebug.map == curMap then
        return
    end

    print("[CityNPCs][StaticDebug] Loading BSP static props for map: " .. tostring(curMap))

    CityNPCs.StaticPropDebug.loaded = true
    CityNPCs.StaticPropDebug.map = curMap
    CityNPCs.StaticPropDebug.props = {}
    CityNPCs.StaticPropDebug.lastError = nil

    local fl = file.Open("maps/" .. curMap .. ".bsp", "rb", "GAME")
    if not fl then
        CityNPCs.StaticPropDebug.lastError = "file.Open failed"
        print("[CityNPCs][StaticDebug] ERROR: file.Open failed for maps/" .. tostring(curMap) .. ".bsp")
        return
    end

    local ident = fl:Read(4)
    if ident ~= "VBSP" then
        CityNPCs.StaticPropDebug.lastError = "invalid BSP header"
        print("[CityNPCs][StaticDebug] ERROR: invalid BSP header: " .. tostring(ident))
        fl:Close()
        return
    end

    local bspVersion = fl:ReadLong()
    print("[CityNPCs][StaticDebug] BSP version: " .. tostring(bspVersion))

    local lumps = {}
    for i = 0, 63 do
        lumps[i] = {
            fileofs = fl:ReadLong(),
            filelen = fl:ReadLong(),
            lumpver = fl:ReadLong(),
            fourCC = fl:Read(4),
        }
    end
    fl:ReadLong()

    local gameLump = lumps[35]
    if not gameLump or gameLump.filelen <= 0 then
        CityNPCs.StaticPropDebug.lastError = "no game lump"
        print("[CityNPCs][StaticDebug] ERROR: no game lump or empty")
        fl:Close()
        return
    end

    print("[CityNPCs][StaticDebug] Game lump offset=" .. tostring(gameLump.fileofs) .. " len=" .. tostring(gameLump.filelen))

    fl:Seek(gameLump.fileofs)
    local gameLumpCount = fl:ReadLong()
    print("[CityNPCs][StaticDebug] Game lump entries: " .. tostring(gameLumpCount))
    local entries = {}
    for i = 1, gameLumpCount do
        entries[i] = {
            id = fl:Read(4),
            flags = fl:ReadShort(),
            version = fl:ReadShort(),
            fileofs = fl:ReadLong(),
            filelen = fl:ReadLong(),
        }
        print(string.format("[CityNPCs][StaticDebug] Entry %d id=%s ver=%d ofs=%d len=%d", i, tostring(entries[i].id), tonumber(entries[i].version) or -1, tonumber(entries[i].fileofs) or -1, tonumber(entries[i].filelen) or -1))
    end

    local foundSprp = false
    for _, entry in ipairs(entries) do
        if (entry.id == "sprp" or entry.id == "prps") and entry.version >= 4 and entry.version < 12 then
            foundSprp = true
            print("[CityNPCs][StaticDebug] Parsing " .. tostring(entry.id) .. " version " .. tostring(entry.version))
            fl:Seek(entry.fileofs)

            local dictCount = fl:ReadLong()
            print("[CityNPCs][StaticDebug] sprp dictCount=" .. tostring(dictCount))
            local dict = {}
            for i = 0, dictCount - 1 do
                dict[i] = readCStringFixed(fl:Read(128))
            end

            local leafCount = fl:ReadLong()
            print("[CityNPCs][StaticDebug] sprp leafCount=" .. tostring(leafCount))
            for i = 1, leafCount do
                fl:ReadUShort()
            end

            local propCount = fl:ReadLong()
            print("[CityNPCs][StaticDebug] sprp propCount=" .. tostring(propCount))
            for i = 1, propCount do
                local pos = Vector(fl:ReadFloat(), fl:ReadFloat(), fl:ReadFloat())
                fl:ReadFloat()
                fl:ReadFloat()
                fl:ReadFloat()

                if entry.version >= 11 then
                    fl:ReadShort()
                end

                local packed = fl:Read(2)
                local lo, hi = string.byte(packed, 1, 2)
                local typeIdx = (lo or 0) + (hi or 0) * 256
                local model = dict[typeIdx] or "?"

                fl:ReadShort()
                fl:ReadShort()
                fl:ReadByte()
                fl:ReadByte()
                fl:ReadLong()
                fl:ReadFloat()
                fl:ReadFloat()
                fl:ReadFloat()
                fl:ReadFloat()
                fl:ReadFloat()

                if entry.version >= 5 then fl:ReadFloat() end
                if entry.version == 6 or entry.version == 7 then
                    fl:ReadShort()
                    fl:ReadShort()
                end
                if entry.version >= 8 then
                    fl:ReadByte()
                    fl:ReadByte()
                    fl:ReadByte()
                    fl:ReadByte()
                end
                if entry.version >= 7 then fl:Read(4) end
                if entry.version >= 10 then fl:ReadFloat() end
                if entry.version == 9 then fl:ReadByte() end

                CityNPCs.StaticPropDebug.props[#CityNPCs.StaticPropDebug.props + 1] = {
                    pos = pos,
                    model = model,
                }
            end

            print("[CityNPCs][StaticDebug] Added props from this sprp: " .. tostring(propCount))
        end
    end

    if not foundSprp then
        CityNPCs.StaticPropDebug.lastError = "sprp lump not found"
        print("[CityNPCs][StaticDebug] ERROR: sprp lump not found")
    elseif #CityNPCs.StaticPropDebug.props == 0 then
        CityNPCs.StaticPropDebug.lastError = "sprp parsed, 0 props"
        print("[CityNPCs][StaticDebug] ERROR: sprp parsed but 0 props")
    end

    print("[CityNPCs][StaticDebug] Total cached static props: " .. tostring(#CityNPCs.StaticPropDebug.props))

    fl:Close()
end

local function findNearestStaticPropModel(pos, rayStart, rayDir, maxDist)
    loadStaticPropsForDebug()
    local props = CityNPCs.StaticPropDebug.props
    if not props or #props == 0 then return nil, nil, nil end

    maxDist = maxDist or 160
    local best
    local bestScore
    local limit2 = maxDist * maxDist
    local close = {}

    local useRay = rayStart and rayDir
    local normDir = useRay and rayDir:GetNormalized() or nil

    local function pointToRayDist2(p)
        if not useRay then return 0 end
        local toP = p - rayStart
        local t = toP:Dot(normDir)
        if t < 0 then return toP:LengthSqr() end
        local closest = rayStart + normDir * t
        return p:DistToSqr(closest)
    end

    for i = 1, #props do
        local d2 = props[i].pos:DistToSqr(pos)
        if d2 <= limit2 then
            local rayD2 = pointToRayDist2(props[i].pos)
            local score = d2 + rayD2 * 0.65

            close[#close + 1] = {
                model = props[i].model,
                hitDist = math.sqrt(d2),
                rayDist = math.sqrt(rayD2),
                score = score,
            }

            if not bestScore or score < bestScore then
                bestScore = score
                best = close[#close]
            end
        end
    end

    if not best then return nil, nil, nil end

    table.sort(close, function(a, b) return a.score < b.score end)
    local alts = {}
    for i = 1, math.min(3, #close) do
        alts[i] = close[i]
    end

    return best.model, best.hitDist, alts
end

concommand.Remove("citynpc_debug_reload_staticprops")
concommand.Add("citynpc_debug_reload_staticprops", function()
    CityNPCs.StaticPropDebug.loaded = false
    CityNPCs.StaticPropDebug.map = nil
    CityNPCs.StaticPropDebug.props = {}
    CityNPCs.StaticPropDebug.lastError = nil
    print("[CityNPCs][StaticDebug] Manual reload requested")
    loadStaticPropsForDebug()
end)

surface.CreateFont("CityNPCs_NavHUD", {
    font = "Tahoma",
    size = 20,
    weight = 800,
    antialias = true,
})

surface.CreateFont("CityNPCs_NavHUD_Small", {
    font = "Tahoma",
    size = 18,
    weight = 700,
    antialias = true,
})

CityNPCs.NavQuery = CityNPCs.NavQuery or {
    areaID = -1,
    navType = "",
    tex = "",
    studioModel = "",
    hasOverride = false,
    lastQuery = -1,
    lastUpdate = 0,
    sampleCount = 0,
    openSkySamples = 0,
    coveredSamples = 0,
    centerUpTexture = "?",
    isIndoors = false,
}
CityNPCs.PendingMenu = nil

hook.Add("HUDPaint", "CityNPCs_LookTexHUD", function()
    local cvar = GetConVar("nav_edit")
    if not cvar or cvar:GetInt() ~= 1 then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local tr = util.TraceLine({
        start = EyePos(),
        endpos = EyePos() + ply:GetAimVector() * 10000,
        filter = ply,
        mask = MASK_SHOT,
    })
    if not tr.Hit then return end

    local lookTex = tr.HitTexture or "?"
    draw.SimpleTextOutlined("Look tex: " .. lookTex, "CityNPCs_NavHUD_Small", ScrW() / 2, 26, Color(230, 230, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 220))

    if not input.IsKeyDown(KEY_LSHIFT) and not input.IsKeyDown(KEY_RSHIFT) then
        return
    end

    if string.find(lookTex, "**", 1, true) then
        local ent = tr.Entity
        if not IsValid(ent) then
            local fallback = ply:GetEyeTrace()
            if fallback and IsValid(fallback.Entity) then
                ent = fallback.Entity
            end
        end
        local cls = IsValid(ent) and ent:GetClass() or "none"
        local model = IsValid(ent) and (ent:GetModel() or "none") or "none"
        draw.SimpleTextOutlined("Hit class: " .. cls, "CityNPCs_NavHUD_Small", ScrW() / 2, 46, Color(230, 200, 160), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 220))
        draw.SimpleTextOutlined("Hit model: " .. model, "CityNPCs_NavHUD_Small", ScrW() / 2, 66, Color(230, 200, 160), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 220))

        if not IsValid(ent) then
            local staticModel, dist, candidates = findNearestStaticPropModel(tr.HitPos, tr.StartPos, tr.Normal, 220)
            local st = CityNPCs.StaticPropDebug
            draw.SimpleTextOutlined("Static cache: " .. tostring(#(st.props or {})) .. " props", "CityNPCs_NavHUD_Small", ScrW() / 2, 86, Color(180, 220, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 220))
            if staticModel then
                draw.SimpleTextOutlined("Static model: " .. staticModel, "CityNPCs_NavHUD_Small", ScrW() / 2, 106, Color(180, 230, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 220))
                draw.SimpleTextOutlined(string.format("Static dist: %.1f", dist), "CityNPCs_NavHUD_Small", ScrW() / 2, 126, Color(180, 230, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 220))
                if candidates and candidates[2] then
                    draw.SimpleTextOutlined("Alt 1: " .. candidates[2].model, "CityNPCs_NavHUD_Small", ScrW() / 2, 146, Color(170, 210, 170), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 220))
                end
                if candidates and candidates[3] then
                    draw.SimpleTextOutlined("Alt 2: " .. candidates[3].model, "CityNPCs_NavHUD_Small", ScrW() / 2, 166, Color(170, 210, 170), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 220))
                end
            else
                local msg = st.lastError and ("Static error: " .. st.lastError) or "Static model: not found"
                draw.SimpleTextOutlined(msg, "CityNPCs_NavHUD_Small", ScrW() / 2, 106, Color(230, 180, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 220))
            end
        end
    end
end)

local function OpenNavMenu(hitPos, tex, currentType)
    if not hitPos then return end
    tex = tex or "?"
    local navType = currentType or CityNPCs.NavQuery.navType
    if navType == "" then navType = "other" end
    local types = {"sidewalk", "crosswalk", "path", "road", "grass", "indoors", "building", "other"}

    local menu = DermaMenu()
    menu:AddOption("Nav at crosshair", nil):SetEnabled(false)
    menu:AddOption("Current: " .. (CityNPCs.NavTypes[navType] and CityNPCs.NavTypes[navType].name or navType), nil):SetEnabled(false)
    menu:AddSpacer()

    for _, t in ipairs(types) do
        local info = CityNPCs.NavTypes[t]
        local name = info and info.name or t
        local label = name
        menu:AddOption(label, function()
            net.Start("CityNPCs_UpdateNavType")
            net.WriteVector(hitPos)
            net.WriteString(t)
            net.WriteBool(false)
            net.SendToServer()
        end):SetChecked(t == navType)
    end

    if CityNPCs.NavQuery.hasOverride then
        menu:AddSpacer()
        menu:AddOption("Remove override", function()
            net.Start("CityNPCs_UpdateNavType")
            net.WriteVector(hitPos)
            net.WriteString("")
            net.WriteBool(true)
            net.SendToServer()
        end)
    end

    menu:AddSpacer()
    menu:AddOption("Retag all from server", function()
        RunConsoleCommand("citynpc_tag_nav")
    end)

    menu:Open()
end

net.Receive("CityNPCs_QueryReply", function()
    CityNPCs.NavQuery.areaID = net.ReadUInt(32)
    CityNPCs.NavQuery.navType = net.ReadString()
    CityNPCs.NavQuery.tex = net.ReadString()
    CityNPCs.NavQuery.studioModel = net.ReadString()
    CityNPCs.NavQuery.hasOverride = net.ReadBool()
    CityNPCs.NavQuery.sampleCount = net.ReadUInt(8)
    CityNPCs.NavQuery.openSkySamples = net.ReadUInt(8)
    CityNPCs.NavQuery.coveredSamples = net.ReadUInt(8)
    CityNPCs.NavQuery.centerUpTexture = net.ReadString()
    CityNPCs.NavQuery.isIndoors = net.ReadBool()
    CityNPCs.NavQuery.lastUpdate = CurTime()

    if CityNPCs.PendingMenu then
        OpenNavMenu(CityNPCs.PendingMenu.hitPos, CityNPCs.PendingMenu.tex, CityNPCs.NavQuery.navType)
        CityNPCs.PendingMenu = nil
    end
end)

hook.Add("HUDPaint", "CityNPCs_NavEditHUD", function()
    local cvar = GetConVar("nav_edit")
    if not cvar or cvar:GetInt() ~= 1 then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local tr = ply:GetEyeTrace()
    if not tr.HitPos or not tr.Hit then return end
    if tr.HitNormal.z < 0.7 then return end

    if CityNPCs.NavQuery.areaID < 0 or CurTime() - CityNPCs.NavQuery.lastQuery > 0.4 then
        CityNPCs.NavQuery.lastQuery = CurTime()
        net.Start("CityNPCs_QueryNav")
        net.WriteVector(tr.HitPos)
        net.SendToServer()
    end

    if CityNPCs.NavQuery.areaID < 0 or CityNPCs.NavQuery.lastUpdate < CurTime() - 5 then
        draw.SimpleTextOutlined("Querying nav...", "CityNPCs_NavHUD_Small", ScrW() / 2 - 35, ScrH() / 2 - 70, Color(150, 150, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 200))
        return
    end

    local cx, cy = ScrW() / 2 - 35, ScrH() / 2
    local y = cy - 70
    local navType = CityNPCs.NavQuery.navType
    local tex = CityNPCs.NavQuery.tex
    local typeInfo = CityNPCs.NavTypes[navType]
    local displayName = typeInfo and typeInfo.name or navType
    local color = typeInfo and typeInfo.color or Color(255, 255, 255)

    draw.SimpleTextOutlined("Down tex: " .. tex, "CityNPCs_NavHUD_Small", cx, y, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 200))
    if string.find(string.lower(tex or ""), "**studio**", 1, true) then
        local modelText = CityNPCs.NavQuery.studioModel ~= "" and CityNPCs.NavQuery.studioModel or "(no nearby static model)"
        draw.SimpleTextOutlined("Studio model: " .. modelText, "CityNPCs_NavHUD_Small", cx, y + 24, Color(180, 230, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 200))
        y = y + 24
    end
    draw.SimpleTextOutlined("Type: " .. displayName, "CityNPCs_NavHUD_Small", cx, y + 24, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200))

    if CityNPCs.NavQuery.hasOverride then
        draw.SimpleTextOutlined("Override: YES", "CityNPCs_NavHUD_Small", cx, y + 48, Color(255, 210, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200))
    end

    local sampleCount = CityNPCs.NavQuery.sampleCount or 0
    local sky = CityNPCs.NavQuery.openSkySamples or 0
    local ceiling = CityNPCs.NavQuery.coveredSamples or 0
    local centerUpTexture = CityNPCs.NavQuery.centerUpTexture or "?"
    local isIndoors = CityNPCs.NavQuery.isIndoors
    local indoorText = isIndoors and "YES" or "NO"
    local indoorColor = isIndoors and Color(255, 120, 120) or Color(120, 255, 120)

    local detailsY = y + 48
    if CityNPCs.NavQuery.hasOverride then
        detailsY = detailsY + 24
    end

    draw.SimpleTextOutlined("Indoor: " .. indoorText, "CityNPCs_NavHUD", cx, detailsY, indoorColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200))

    local showExtra = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
    if showExtra then
        draw.SimpleTextOutlined("Sky: " .. sky .. "/" .. sampleCount, "CityNPCs_NavHUD_Small", cx, detailsY + 26, Color(180, 220, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 200))
        draw.SimpleTextOutlined("Ceiling: " .. ceiling .. "/" .. sampleCount, "CityNPCs_NavHUD_Small", cx, detailsY + 50, Color(220, 220, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 200))
        draw.SimpleTextOutlined("Up tex: " .. centerUpTexture, "CityNPCs_NavHUD_Small", cx, detailsY + 74, Color(210, 190, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 200))
        draw.SimpleTextOutlined("Right-click to change", "CityNPCs_NavHUD_Small", cx, detailsY + 98, Color(180, 180, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 200))
    else
        draw.SimpleTextOutlined("Hold SHIFT for details", "CityNPCs_NavHUD_Small", cx, detailsY + 26, Color(160, 160, 160), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 200))
        draw.SimpleTextOutlined("Right-click to change", "CityNPCs_NavHUD_Small", cx, detailsY + 50, Color(180, 180, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 200))
    end
end)

hook.Add("GUIMousePressed", "CityNPCs_NavMenu", function(code, aimVector)
    if code ~= MOUSE_RIGHT then return end
    if not IsValid(g_ContextMenu) or not g_ContextMenu:IsVisible() then return end
    local cvar = GetConVar("nav_edit")
    if not cvar or cvar:GetInt() ~= 1 then return end

    local tr = util.TraceLine({
        start = EyePos(),
        endpos = EyePos() + aimVector * 5000,
        mask = MASK_SOLID,
    })
    if not tr.Hit then return end

    CityNPCs.PendingMenu = { hitPos = tr.HitPos, tex = tr.HitTexture }
    net.Start("CityNPCs_QueryNav")
    net.WriteVector(tr.HitPos)
    net.SendToServer()
end)
