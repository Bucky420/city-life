CityNPCs = CityNPCs or {}
CityNPCs.NavMeta = CityNPCs.NavMeta or {}
CityNPCs.NavOverridesByAreaID = CityNPCs.NavOverridesByAreaID or {}
CityNPCs.IndoorSampleCache = CityNPCs.IndoorSampleCache or {}
CityNPCs.StaticPropTagCache = CityNPCs.StaticPropTagCache or {
    loaded = false,
    map = nil,
    props = {},
}

if SERVER then
    CreateConVar("citynpc_ceiling_trace_height", "400", FCVAR_ARCHIVE, "Upward trace height used for indoor ceiling checks")
end

CityNPCs.NavTypes = {
    sidewalk = { name = "Sidewalk", cost = 1, color = Color(0, 255, 100) },
    crosswalk = { name = "Crosswalk", cost = 2, color = Color(255, 255, 0) },
    path = { name = "Path", cost = 3, color = Color(255, 165, 0) },
    road = { name = "Road", cost = 8, color = Color(255, 70, 70) },
    grass = { name = "Grass", cost = 4, color = Color(0, 255, 50) },
    indoors = { name = "Indoors", cost = 500, color = Color(0, 255, 255) },
    building = { name = "Building", cost = 1000, color = Color(255, 50, 255) },
    other = { name = "Other", cost = 10, color = Color(150, 150, 150) },
}

CityNPCs.TextureKeywords = {
    sidewalk = { "sidewalk", "pavement", "footpath", "walkway", "patio", "curb" },
    crosswalk = { "crosswalk", "zebra", "crossing" },
    path = { "dirt", "gravel", "trail", "ground", "soil", "mud", "sand" },
    road = { "road", "asphalt", "street", "highway", "roadway", "tarmac", "lane", "drive", "streets" },
    grass = { "grass", "lawn", "field", "nature", "vegetation", "organic", "dirtgrass", "grassfloor" },
    indoors = { "carpet", "tile", "wood", "linoleum", "floor", "carpentry", "woodfloor", "tilefloor" },
    building = { "wall", "brick", "drywall", "ceiling", "cinderblock", "plaster", "concretewall", "cinder_block", "sheetrock" },
}

CityNPCs.ModelKeywords = {
    sidewalk = { "sidewalk", "pavement", "curb", "walkway", "footpath" },
    crosswalk = { "crosswalk", "zebra" },
    path = { "trail", "gravel", "dirt", "mud", "sand" },
    road = { "road", "street", "asphalt", "highway", "lane", "drive" },
    grass = { "grass", "bush", "hedge", "plant", "tree", "foliage" },
    indoors = { "carpet", "tile", "floor", "interior", "hall", "room" },
    building = { "wall", "brick", "window", "door", "building", "fence", "roof", "column", "stairs" },
}

local function readCStringFixed(str)
    return (str and str:match("^[^%z]+")) or ""
end

function CityNPCs.ClassifyByKeywords(value, keywordMap, order)
    local lower = string.lower(value or "")
    for _, navType in ipairs(order) do
        for _, kw in ipairs(keywordMap[navType] or {}) do
            if string.find(lower, kw, 1, true) then
                return navType
            end
        end
    end
    return "other"
end

function CityNPCs.IsUsableWorldTex(tex)
    if not tex or tex == "" or tex == "none" or tex == "?" then return false end
    if string.find(tex, "**", 1, true) then return false end
    return string.find(tex, "/", 1, true) ~= nil
end

function CityNPCs.GetAreaSamplePoints(area)
    if not area then return {} end

    local center = area:GetCenter()
    local points = { center }

    if not area.GetCorner then
        return points
    end

    local corners = {}
    for i = 0, 3 do
        local c = area:GetCorner(i)
        if c then
            corners[#corners + 1] = c
        end
    end

    if #corners < 4 then
        return points
    end

    local insetFactor = 0.22
    for i = 1, 4 do
        local c = corners[i]
        local inset = c + (center - c) * insetFactor
        points[#points + 1] = inset
    end

    return points
end

function CityNPCs.GetNavMeta(area)
    if not area then return nil end
    local meta = CityNPCs.NavMeta[area]
    if not meta then return nil end

    local overrideType = CityNPCs.GetAreaOverrideType(area)
    if overrideType then
        meta.type = overrideType
        meta.overridden = true
    else
        meta.overridden = false
    end

    return meta
end

function CityNPCs.SetNavMeta(area, data)
    if not area then return end
    CityNPCs.NavMeta[area] = data
end

function CityNPCs.GetAreaOverrideType(area)
    if not area then return nil end
    return CityNPCs.NavOverridesByAreaID[area:GetID()]
end

function CityNPCs.SaveNavOverrides()
    if CLIENT then return end
    local map = game.GetMap()
    local lines = { "v1" }
    for areaID, navType in pairs(CityNPCs.NavOverridesByAreaID) do
        lines[#lines + 1] = tostring(areaID) .. ":" .. tostring(navType)
    end
    file.Write("citylife_nav_overrides_" .. map .. ".txt", table.concat(lines, "\n"))
end

function CityNPCs.LoadNavOverrides()
    if CLIENT then return end
    CityNPCs.NavOverridesByAreaID = {}

    local map = game.GetMap()
    local raw = file.Read("citylife_nav_overrides_" .. map .. ".txt", "DATA")
    if not raw or raw == "" then return end

    local lines = string.Explode("\n", raw, false)
    local start = 1
    if lines[1] == "v1" then
        start = 2
    end

    for i = start, #lines do
        local line = string.Trim(lines[i] or "")
        if line ~= "" then
            local areaIDStr, navType = string.match(line, "^(%d+):([%w_]+)$")
            local areaID = tonumber(areaIDStr)
            if areaID and CityNPCs.NavTypes[navType] then
                CityNPCs.NavOverridesByAreaID[areaID] = navType
            end
        end
    end

    print("[CityNPCs] Loaded " .. tostring(table.Count(CityNPCs.NavOverridesByAreaID)) .. " nav overrides")
end

function CityNPCs.SetAreaOverride(area, navType)
    if CLIENT or not area or not CityNPCs.NavTypes[navType] then return false end

    CityNPCs.NavOverridesByAreaID[area:GetID()] = navType
    local meta = CityNPCs.NavMeta[area]
    if meta then
        meta.type = navType
        meta.overridden = true
    end
    CityNPCs.SaveNavOverrides()
    return true
end

function CityNPCs.RemoveAreaOverride(area)
    if CLIENT or not area then return false end
    local areaID = area:GetID()
    if not CityNPCs.NavOverridesByAreaID[areaID] then return false end

    CityNPCs.NavOverridesByAreaID[areaID] = nil
    local meta = CityNPCs.NavMeta[area]
    if meta then
        local tex = meta.texture or CityNPCs.GetTexAtPos(area:GetCenter(), area)
        local navType = CityNPCs.IsAreaIndoors(area) and "indoors" or CityNPCs.ClassifyTexture(tex)
        if string.find(string.lower(tex or ""), "**studio**", 1, true) then
            local staticModel = CityNPCs.GetNearestStaticPropModel(area:GetCenter(), 260)
            if staticModel then
                local fromModel = CityNPCs.ClassifyModel(staticModel)
                if fromModel ~= "other" then
                    navType = fromModel
                end
            end
        end
        meta.type = navType
        meta.overridden = false
    end

    CityNPCs.SaveNavOverrides()
    return true
end

function CityNPCs.GetTexAtPos(pos, area)
    local function isWorldSurface(tr)
        return tr.HitWorld or (IsValid(tr.Entity) and tr.Entity:GetClass() == "worldspawn")
    end

    local function traceAt(p)
        return util.TraceLine({
            start = p + Vector(0, 0, 5),
            endpos = p - Vector(0, 0, 50),
            mask = MASK_SOLID,
        })
    end

    local function validSurface(tr)
        local tex = tr.HitTexture or "none"
        return CityNPCs.IsUsableWorldTex(tex) and isWorldSurface(tr)
    end

    local tr = traceAt(pos)
    local tex = tr.HitTexture or "none"

    if (not CityNPCs.IsUsableWorldTex(tex) or not isWorldSurface(tr)) and area then
        local samples = CityNPCs.GetAreaSamplePoints(area)
        for i = 1, #samples do
            local tr2 = traceAt(samples[i])
            if validSurface(tr2) then
                return tr2.HitTexture
            end
        end
    end

    return tex
end

function CityNPCs.ClassifyTexture(tex)
    local order = {"road", "sidewalk", "crosswalk", "path", "grass", "building", "indoors"}
    return CityNPCs.ClassifyByKeywords(tex, CityNPCs.TextureKeywords, order)
end

function CityNPCs.ClassifyModel(model)
    local order = {"road", "sidewalk", "crosswalk", "path", "grass", "building", "indoors"}
    return CityNPCs.ClassifyByKeywords(model, CityNPCs.ModelKeywords, order)
end

function CityNPCs.LoadStaticPropsForTagging()
    if CLIENT then return end

    local curMap = game.GetMap()
    local cache = CityNPCs.StaticPropTagCache
    if cache.loaded and cache.map == curMap then return end

    cache.loaded = true
    cache.map = curMap
    cache.props = {}

    local fl = file.Open("maps/" .. curMap .. ".bsp", "rb", "GAME")
    if not fl then
        print("[CityNPCs] Static prop cache load failed: maps/" .. tostring(curMap) .. ".bsp not found")
        return
    end

    local ident = fl:Read(4)
    if ident ~= "VBSP" then
        fl:Close()
        return
    end

    fl:ReadLong()
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
        fl:Close()
        return
    end

    fl:Seek(gameLump.fileofs)
    local gameLumpCount = fl:ReadLong()
    local entries = {}
    for i = 1, gameLumpCount do
        entries[i] = {
            id = fl:Read(4),
            flags = fl:ReadShort(),
            version = fl:ReadShort(),
            fileofs = fl:ReadLong(),
            filelen = fl:ReadLong(),
        }
    end

    for _, entry in ipairs(entries) do
        if (entry.id == "sprp" or entry.id == "prps") and entry.version >= 4 and entry.version < 12 then
            fl:Seek(entry.fileofs)

            local dictCount = fl:ReadLong()
            local dict = {}
            for i = 0, dictCount - 1 do
                dict[i] = readCStringFixed(fl:Read(128))
            end

            local leafCount = fl:ReadLong()
            for i = 1, leafCount do
                fl:ReadUShort()
            end

            local propCount = fl:ReadLong()
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

                cache.props[#cache.props + 1] = {
                    pos = pos,
                    model = model,
                }
            end
        end
    end

    fl:Close()
    print("[CityNPCs] Static prop cache ready: " .. tostring(#cache.props) .. " props")
end

function CityNPCs.GetNearestStaticPropModel(pos, maxDist)
    if CLIENT then return nil end

    CityNPCs.LoadStaticPropsForTagging()
    local props = CityNPCs.StaticPropTagCache.props
    if not props or #props == 0 then return nil end

    local limit = (maxDist or 260)
    local limit2 = limit * limit
    local bestModel
    local bestD2

    for i = 1, #props do
        local d2 = props[i].pos:DistToSqr(pos)
        if d2 <= limit2 and (not bestD2 or d2 < bestD2) then
            bestD2 = d2
            bestModel = props[i].model
        end
    end

    return bestModel
end

function CityNPCs.GetAreaIndoorDebug(area)
    if not area then
        return {
            sampleCount = 0,
            openSkySamples = 0,
            coveredSamples = 0,
            centerUpTexture = "?",
            isIndoors = false,
        }
    end

    local sampleCount = 5
    local ceilingTraceHeight = 400
    local indoorRatioThreshold = 0.5
    local skyOutdoorThreshold = 0.5

    local coveredSamples = 0
    local openSkySamples = 0
    local centerUpTexture = "?"

    local cvarHeight = GetConVar("citynpc_ceiling_trace_height")
    if cvarHeight then
        ceilingTraceHeight = math.Clamp(cvarHeight:GetInt(), 128, 4096)
    end

    local function traceUp(point)
        return util.TraceLine({
            start = point + Vector(0, 0, 8),
            endpos = point + Vector(0, 0, ceilingTraceHeight),
            mask = MASK_SOLID_BRUSHONLY,
        })
    end

    local function traceSky(point)
        return util.TraceLine({
            start = point + Vector(0, 0, 8),
            endpos = point + Vector(0, 0, 16384),
            mask = MASK_VISIBLE_AND_NPCS,
        })
    end

    local cacheKey = area:GetID()
    local samples = CityNPCs.IndoorSampleCache[cacheKey]
    if not samples or #samples ~= sampleCount then
        samples = CityNPCs.GetAreaSamplePoints(area)
        if #samples < sampleCount then
            for i = #samples + 1, sampleCount do
                samples[i] = area:GetCenter()
            end
        end

        CityNPCs.IndoorSampleCache[cacheKey] = samples
    end

    local function isUsableTex(tex)
        if not tex or tex == "" or tex == "?" then return false end
        if string.find(tex, "**", 1, true) then return false end
        return true
    end

    local function pickFallbackUpTexture()
        for i = 2, sampleCount do
            local upTrace = traceUp(samples[i])
            if upTrace.HitSky then
                return "sky"
            end
            local tex = upTrace.HitTexture or "?"
            if isUsableTex(tex) then
                return tex
            end
        end
        return centerUpTexture
    end

    for i = 1, sampleCount do
        local sample = samples[i]

        local skyTrace = traceSky(sample)
        if skyTrace.HitSky then
            openSkySamples = openSkySamples + 1
            if i == 1 then
                centerUpTexture = "sky"
            end
        else
            local upTrace = traceUp(sample)
            if i == 1 then
                centerUpTexture = upTrace.HitTexture or "?"
            end
            local worldHit = upTrace.HitWorld or (IsValid(upTrace.Entity) and upTrace.Entity:GetClass() == "worldspawn")
            if upTrace.Hit and upTrace.Fraction < 1 and not upTrace.HitSky and worldHit then
                coveredSamples = coveredSamples + 1
            end
        end
    end

    if not isUsableTex(centerUpTexture) and centerUpTexture ~= "sky" then
        centerUpTexture = pickFallbackUpTexture()
    end

    local coveredRatio = coveredSamples / sampleCount
    local skyRatio = openSkySamples / sampleCount
    local isIndoors = coveredRatio >= indoorRatioThreshold and skyRatio < skyOutdoorThreshold

    return {
        sampleCount = sampleCount,
        openSkySamples = openSkySamples,
        coveredSamples = coveredSamples,
        centerUpTexture = centerUpTexture,
        isIndoors = isIndoors,
    }
end

function CityNPCs.IsAreaIndoors(area)
    return CityNPCs.GetAreaIndoorDebug(area).isIndoors
end

if SERVER then
    function CityNPCs.TagNavMesh()
        if not navmesh then print("[CityNPCs] Navmesh not available"); return end
        CityNPCs.LoadNavOverrides()
        CityNPCs.LoadStaticPropsForTagging()
        CityNPCs.NavMeta = {}
        CityNPCs.IndoorSampleCache = {}
        local areas = navmesh.GetAllNavAreas()
        if not areas then print("[CityNPCs] No nav mesh found"); return end
        local count = 0
        for _, area in ipairs(areas) do
            local center = area:GetCenter()
            local tex = CityNPCs.GetTexAtPos(center, area)
            local navType
            if CityNPCs.IsAreaIndoors(area) then
                navType = "indoors"
            else
                navType = CityNPCs.ClassifyTexture(tex)
                if string.find(string.lower(tex or ""), "**studio**", 1, true) then
                    local staticModel = CityNPCs.GetNearestStaticPropModel(center, 260)
                    if staticModel then
                        local fromModel = CityNPCs.ClassifyModel(staticModel)
                        if fromModel ~= "other" then
                            navType = fromModel
                        end
                    end
                end
            end
            local overrideType = CityNPCs.GetAreaOverrideType(area)
            if overrideType then
                navType = overrideType
            end
            CityNPCs.SetNavMeta(area, { type = navType, texture = tex, overridden = overrideType ~= nil })
            count = count + 1
        end
        print("[CityNPCs] Tagged " .. count .. " nav areas")
    end

    concommand.Remove("citynpc_tag_nav")
    concommand.Add("citynpc_tag_nav", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then
            ply:PrintMessage(HUD_PRINTTALK, "[CityNPCs] Only super admins can tag nav")
            return
        end
        CityNPCs.TagNavMesh()
    end)
end
