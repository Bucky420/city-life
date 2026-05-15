CityNPCs = CityNPCs or {}
CityNPCs.ActiveNPCs = CityNPCs.ActiveNPCs or {}
CityNPCs.AreaOccupancy = CityNPCs.AreaOccupancy or {}

function CityNPCs.UpdateOccupancy()
    if not navmesh then return end
    CityNPCs.AreaOccupancy = {}
    for _, npc in ipairs(CityNPCs.ActiveNPCs) do
        if IsValid(npc) then
            local area = navmesh.GetNavArea(npc:GetPos(), 50)
            if area then
                CityNPCs.AreaOccupancy[area] = (CityNPCs.AreaOccupancy[area] or 0) + 1
            end
        end
    end
end

function CityNPCs.GetNavCost(area)
    local meta = CityNPCs.GetNavMeta(area)
    if not meta then return 10 end
    local typeInfo = CityNPCs.NavTypes[meta.type]
    if not typeInfo then return 10 end
    local cost = typeInfo.cost
    local occ = CityNPCs.AreaOccupancy[area] or 0
    if occ > 0 then
        cost = cost * (1 + occ * 2.5)
    end
    return cost
end

function CityNPCs.BuildPath(ent, startPos, endPos)
    local path = Path("Follow")
    path:SetMinLookAheadDistance(300)
    path:Compute(ent, startPos, endPos, function(area)
        return CityNPCs.GetNavCost(area)
    end)
    if path:IsValid() then
        return path
    end
    return nil
end

function CityNPCs.FindDestination(npc, maxDist)
    if not IsValid(npc) or not navmesh then return nil end
    local areas = navmesh.GetAllNavAreas()
    if not areas or #areas == 0 then return nil end

    local npcPos = npc:GetPos()
    local npcArea = navmesh.GetNearestNavArea(npcPos, false, 100)
    local npcZ = npcArea and npcArea:GetCenter().z or npcPos.z
    maxDist = maxDist or math.random(1500, 4000)

    local preferred, fallback = {}, {}

    for _, area in ipairs(areas) do
        local center = area:GetCenter()
        local dx = center.x - npcPos.x
        local dy = center.y - npcPos.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 400 and dist < maxDist and math.abs(center.z - npcZ) < 36 then
            local meta = CityNPCs.GetNavMeta(area)
            local t = meta and meta.type or "other"
            if t == "sidewalk" or t == "crosswalk" then
                table.insert(preferred, area)
            elseif t == "path" or t == "other" then
                table.insert(fallback, area)
            end
        end
    end

    local chosen
    if #preferred > 0 then
        chosen = preferred[math.random(#preferred)]
    elseif #fallback > 0 then
        chosen = fallback[math.random(#fallback)]
    end

    if not chosen then return nil end
    return chosen:GetCenter()
end

timer.Remove("CityNPCs_OccUpdate")
timer.Create("CityNPCs_OccUpdate", 3, 0, CityNPCs.UpdateOccupancy)
