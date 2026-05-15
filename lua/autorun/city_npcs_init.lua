include("city_npcs/nav_metadata.lua")
 
list.Set("NPC", "city_npc", {
    Name = "City NPC",
    Class = "city_npc",
    Category = "Citizens"
})

if SERVER then
    AddCSLuaFile("city_npcs/nav_metadata.lua")
    AddCSLuaFile("city_npcs/cl_ui.lua")

    include("city_npcs/navigation.lua")
    AddCSLuaFile("city_npcs/navigation.lua")

    util.AddNetworkString("CityNPCs_UpdateNavType")
    util.AddNetworkString("CityNPCs_QueryNav")
    util.AddNetworkString("CityNPCs_QueryReply")

    net.Receive("CityNPCs_QueryNav", function(len, ply)
        if not IsValid(ply) or not navmesh then return end
        local pos = net.ReadVector()
        local area = navmesh.GetNearestNavArea(pos, false, 200)
        if not area then return end
        local meta = CityNPCs.GetNavMeta(area)
        local downTex = meta and meta.texture or "?"
        if not CityNPCs.IsUsableWorldTex(downTex) then
            downTex = CityNPCs.GetTexAtPos(area:GetCenter(), area)
        end
        local studioModel = ""
        if string.find(string.lower(downTex or ""), "**studio**", 1, true) then
            studioModel = CityNPCs.GetNearestStaticPropModel(area:GetCenter(), 260) or ""
        end
        local hasOverride = CityNPCs.GetAreaOverrideType(area) ~= nil
        local dbg = CityNPCs.GetAreaIndoorDebug(area)
        net.Start("CityNPCs_QueryReply")
        net.WriteUInt(area:GetID(), 32)
        net.WriteString(meta and meta.type or "other")
        net.WriteString(downTex)
        net.WriteString(studioModel)
        net.WriteBool(hasOverride)
        net.WriteUInt(dbg.sampleCount or 0, 8)
        net.WriteUInt(dbg.openSkySamples or 0, 8)
        net.WriteUInt(dbg.coveredSamples or 0, 8)
        net.WriteString(dbg.centerUpTexture or "?")
        net.WriteBool(dbg.isIndoors or false)
        net.Send(ply)
    end)

    net.Receive("CityNPCs_UpdateNavType", function(len, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() or not navmesh then return end

        local pos = net.ReadVector()
        local navType = net.ReadString()
        local removeOverride = net.ReadBool()

        local area = navmesh.GetNearestNavArea(pos, false, 200)
        if not area then
            ply:PrintMessage(HUD_PRINTTALK, "[CityNPCs] No nav area found near that position")
            return
        end

        if removeOverride then
            if CityNPCs.RemoveAreaOverride(area) then
                ply:PrintMessage(HUD_PRINTTALK, "[CityNPCs] Removed override for area #" .. area:GetID())
            else
                ply:PrintMessage(HUD_PRINTTALK, "[CityNPCs] Area #" .. area:GetID() .. " has no override")
            end
        else
            if not CityNPCs.NavTypes[navType] then
                ply:PrintMessage(HUD_PRINTTALK, "[CityNPCs] Invalid nav type: " .. tostring(navType))
                return
            end
            CityNPCs.SetAreaOverride(area, navType)
            ply:PrintMessage(HUD_PRINTTALK, "[CityNPCs] Override area #" .. area:GetID() .. " -> " .. navType)
        end
    end)

    hook.Remove("InitPostEntity", "CityNPCs_Startup")
    hook.Add("InitPostEntity", "CityNPCs_Startup", function()
        timer.Simple(1, CityNPCs.TagNavMesh)
    end)

    hook.Remove("NavMeshGenerated", "CityNPCs_ReTag")
    hook.Add("NavMeshGenerated", "CityNPCs_ReTag", function()
        timer.Simple(1, CityNPCs.TagNavMesh)
    end)

    hook.Remove("PostCleanupMap", "CityNPCs_CleanupTag")
    hook.Add("PostCleanupMap", "CityNPCs_CleanupTag", function()
        timer.Simple(1, CityNPCs.TagNavMesh)
    end)

    concommand.Remove("citynpc_spawn")
    concommand.Add("citynpc_spawn", function(ply, _, args)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:PrintMessage(HUD_PRINTTALK, "[CityNPCs] Admins only")
            return
        end
        local count = tonumber(args[1]) or 1
        count = math.Clamp(count, 1, 50)
        local spawned = 0
        local areas = navmesh and navmesh.GetAllNavAreas() or {}
        if not areas or #areas == 0 then
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[CityNPCs] No nav mesh found") end
            return
        end
        for i = 1, count do
            local area = areas[math.random(#areas)]
            if area then
                local center = area:GetCenter()
                local ent = ents.Create("city_npc")
                if IsValid(ent) then
                    ent:SetPos(center + Vector(0, 0, 10))
                    ent:Spawn()
                    spawned = spawned + 1
                end
            end
        end
        local msg = "[CityNPCs] Spawned " .. spawned .. " NPCs"
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, msg) end
        print(msg)
    end)

    concommand.Remove("citynpc_cleanup")
    concommand.Add("citynpc_cleanup", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then return end
        local count = 0
        for _, ent in ipairs(ents.FindByClass("city_npc")) do
            if IsValid(ent) then
                ent:Remove()
                count = count + 1
            end
        end
        local msg = "[CityNPCs] Removed " .. count .. " NPCs"
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, msg) end
        print(msg)
    end)

    print("[CityNPCs] Server loaded - commands: citynpc_spawn [n], citynpc_cleanup, citynpc_tag_nav")
end

if CLIENT then
    include("city_npcs/cl_ui.lua")
    print("[CityNPCs] Client loaded")
end
