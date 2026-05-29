include("city_npcs/nav_metadata.lua")

list.Set("NPC", "city_npc", {
    Name = "City NPC",
    Class = "city_npc",
    Category = "Citizens"
})

list.Set("NPC", "city_anim_test_npc", {
    Name = "Test v1",
    Class = "city_anim_test_npc",
    Category = "Citizens"
})

list.Set("NPC", "city_anim_test02_npc", {
    Name = "Test v2 (IK test)",
    Class = "city_anim_test02_npc",
    Category = "Citizens"
})

list.Set("NPC", "city_anim_final_npc_test3", {
    Name = "Test v3 (npc Anim)",
    Class = "city_anim_final_npc_test3",
    Category = "Citizens"
})

list.Set("NPC", "city_anim_test04_player", {
    Name = "Test v4 (player Anim)",
    Class = "city_anim_test04_player",
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

    concommand.Remove("citynpc_dump_pose")
    concommand.Add("citynpc_dump_pose", function(ply)
        local target = ply:GetEyeTrace().Entity
        local cls = IsValid(target) and target:GetClass() or ""
local allowedClasses = { ["city_npc"] = true, ["city_anim_test_npc"] = true, ["city_anim_test02_npc"] = true, ["city_anim_final_npc_test3"] = true, ["city_anim_test04_player"] = true }
            if not allowedClasses[cls] then
                if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[CityNPCs] Look at a city_npc / city_anim_test_npc / city_anim_test02_npc / city_anim_test04_player") end
                return
            end
            local n = target:GetNumPoseParameters()
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "--- Pose Params (" .. n .. ") ---") end
        for i = 0, n - 1 do
            local name = target:GetPoseParameterName(i)
            local minV, maxV = target:GetPoseParameterRange(i)
            local cur = target:GetPoseParameter(i)
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, i .. ": " .. name .. " range=[" .. minV .. "," .. maxV .. "] cur=" .. cur) end
        end
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "--- End ---") end
    end)

    concommand.Remove("citynpc_dump_anims")
    concommand.Add("citynpc_dump_anims", function(ply)
        local target = ply:GetEyeTrace().Entity
        local cls = IsValid(target) and target:GetClass() or ""
        local allowedClasses = { ["city_npc"] = true, ["city_anim_test_npc"] = true, ["city_anim_test02_npc"] = true, ["city_anim_final_npc_test3"] = true, ["city_anim_test04_player"] = true }
        if not allowedClasses[cls] then
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[CityNPCs] Look at a city_npc / city_anim_test_npc / city_anim_test02_npc / city_anim_test04_player") end
            return
        end
        local count = target:GetSequenceCount()
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "--- Sequences (" .. count .. ") ---") end
        local actMap = {}
        for i = 0, count - 1 do
            local name = target:GetSequenceName(i)
            local act = target:GetSequenceActivity(i)
            if not actMap[act] then actMap[act] = {} end
            table.insert(actMap[act], name)
        end
        for act, seqs in pairs(actMap) do
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, act .. " -> " .. table.concat(seqs, ", ")) end
        end
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "--- End ---") end
    end)

    print("[CityNPCs] Server loaded - commands: citynpc_spawn [n], citynpc_cleanup")
end

if CLIENT then
    include("city_npcs/cl_ui.lua")
    include("city_npcs/cl_anim_viewer.lua")

    CityNPCs = CityNPCs or {}
    CityNPCs.DbgEnts = CityNPCs.DbgEnts or {}
    local dbgFrame = 0

    concommand.Remove("citynpc_debug_entity")
    concommand.Add("citynpc_debug_entity", function()
        local target = LocalPlayer():GetEyeTrace().Entity
        if not IsValid(target) then
            print("[CityNPCs] Look at an entity first")
            return
        end
        local idx = target:EntIndex()
        if CityNPCs.DbgEnts[idx] then
            CityNPCs.DbgEnts[idx] = nil
            print("[CityNPCs] Debug OFF for " .. target:GetClass() .. " [" .. idx .. "]")
        else
            CityNPCs.DbgEnts[idx] = target
            print("[CityNPCs] Debug ON for " .. target:GetClass() .. " [" .. idx .. "]")
        end
    end)

    hook.Add("Think", "CityNPCs_DebugEntity", function()
        for idx, ent in pairs(CityNPCs.DbgEnts) do
            if not IsValid(ent) then CityNPCs.DbgEnts[idx] = nil end
        end

        dbgFrame = dbgFrame + 1
		if dbgFrame % 5 ~= 0 then return end

        for _, ent in pairs(CityNPCs.DbgEnts) do
            ent:SetupBones()

            local lFootBone = ent:LookupBone("ValveBiped.Bip01_L_Foot")
            local rFootBone = ent:LookupBone("ValveBiped.Bip01_R_Foot")

            local lStr, rStr = "L:?", "R:?"
            if lFootBone and lFootBone >= 0 then
                local mat = ent:GetBoneMatrix(lFootBone)
                if mat then
                    local fw = mat:GetTranslation()
                    local lz = string.format("%.1f", ent:WorldToLocal(fw).z)
                    local tr = util.TraceLine({start=fw, endpos=fw-Vector(0,0,48), filter=ent, mask=MASK_SOLID})
                    local d = tr.Hit and string.format("%.1f", fw.z-tr.HitPos.z) or "miss"
                    lStr = string.format("LZ:%s D:%s", lz, d)
                end
            end
            if rFootBone and rFootBone >= 0 then
                local mat = ent:GetBoneMatrix(rFootBone)
                if mat then
                    local fw = mat:GetTranslation()
                    local rz = string.format("%.1f", ent:WorldToLocal(fw).z)
                    local tr = util.TraceLine({start=fw, endpos=fw-Vector(0,0,48), filter=ent, mask=MASK_SOLID})
                    local d = tr.Hit and string.format("%.1f", fw.z-tr.HitPos.z) or "miss"
                    rStr = string.format("RZ:%s D:%s", rz, d)
                end
            end

            local seq = ent:GetSequence()
            local seqName = ent:GetSequenceName(seq) or "?"
            local spd = ent:GetVelocity():Length2D()
            local cls = ent:GetClass()
            local off = ent._IkOffset or 0
            local blend = ent._DbgBlendOff or 0
            local mn = ent._DbgMinZ or 0
            local mx = ent._DbgMaxZ or 0

            print(string.format("[DBG] %s[%d] Seq:%s Spd:%.1f %s %s Off:%.1f Bl:%.1f Mn:%.1f Mx:%.1f",
                cls, ent:EntIndex(), seqName, spd, lStr, rStr, off, blend, mn, mx))
        end
    end)

    print("[CityNPCs] Client loaded")
end
