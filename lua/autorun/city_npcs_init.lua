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
            local lKneeBone = ent:LookupBone("ValveBiped.Bip01_L_Calf")
            local rKneeBone = ent:LookupBone("ValveBiped.Bip01_R_Calf")
            local lThighBone = ent:LookupBone("ValveBiped.Bip01_L_Thigh")
            local rThighBone = ent:LookupBone("ValveBiped.Bip01_R_Thigh")
            local pelvisBone = ent:LookupBone("ValveBiped.Bip01_Pelvis")

            local lStr, rStr = "L:?", "R:?"
            local r = 2.5
            local fwd = ent:GetForward()
            local footForward = Vector(fwd.x, fwd.y, 0):GetNormalized() * 4
            if lFootBone and lFootBone >= 0 then
                local mat = ent:GetBoneMatrix(lFootBone)
                if mat then
                    local fw = mat:GetTranslation()
                    local lz = string.format("%.1f", ent:WorldToLocal(fw).z)
                    local lStart = fw + footForward
                    local tr = util.TraceHull({start=lStart, endpos=lStart-Vector(0,0,72), mins=Vector(-r,-r,0), maxs=Vector(r,r,1), filter=ent, mask=MASK_SOLID})
                    local d = tr.Hit and string.format("%.1f", tr.HitPos.z) or "miss"
                    lStr = string.format("LZ:%s HitZ:%s H:%s", lz, d, tr.Hit and "Y" or "N")
                end
            end
            if rFootBone and rFootBone >= 0 then
                local mat = ent:GetBoneMatrix(rFootBone)
                if mat then
                    local fw = mat:GetTranslation()
                    local rz = string.format("%.1f", ent:WorldToLocal(fw).z)
                    local rStart = fw + footForward
                    local tr = util.TraceHull({start=rStart, endpos=rStart-Vector(0,0,72), mins=Vector(-r,-r,0), maxs=Vector(r,r,1), filter=ent, mask=MASK_SOLID})
                    local d = tr.Hit and string.format("%.1f", tr.HitPos.z) or "miss"
                    rStr = string.format("RZ:%s HitZ:%s H:%s", rz, d, tr.Hit and "Y" or "N")
                end
            end

            local seq = ent:GetSequence()
            local seqName = ent:GetSequenceName(seq) or "?"
            local seqAct = ent:GetSequenceActivity(seq) or -1
            local groundSpeed = ent:GetSequenceGroundSpeed(seq) or 0
            local seqDur = ent:SequenceDuration(seq) or 0
            local spd = ent:GetVelocity():Length2D()
            local cls = ent:GetClass()
            local pos = ent:GetPos()
            local off = ent._IkOffset or 0
            local blend = ent._DbgBlendOff or 0
            local smoothOff = ent._SmoothOff or 0
            local push = ent._FootPush or 0
            local dom = ent._DominantFoot or "none"
            local mn = ent._DbgMinZ or 0
            local mx = ent._DbgMaxZ or 0
            local step = ent._StepOrigin or pos.z

            -- Extra info for stock NPCs: bone world Z, ground entity, cycle
            local boneInfo = ""
            if pelvisBone and pelvisBone >= 0 then
                local mat = ent:GetBoneMatrix(pelvisBone)
                if mat then boneInfo = string.format(" Pelv:%.1f", mat:GetTranslation().z) end
            end
            local groundInfo = ""
            local ge = ent:GetGroundEntity()
            if IsValid(ge) then groundInfo = " Gnd:" .. ge:GetClass() end
            local cycleInfo = string.format(" Cyc:%.2f", ent:GetCycle())
            local rateInfo = string.format(" Rate:%.2f", ent:GetPlaybackRate())
            local layerInfo = ""
            local numLayers = 0
            local ok, nl = pcall(function() return ent:GetNumAnimOverlays() end)
            if ok and nl then numLayers = nl end
            if numLayers > 0 then
                layerInfo = string.format(" Layers:%d", numLayers)
                for i = 0, numLayers - 1 do
                    local layer = ent:GetAnimOverlay(i)
                    if layer and layer:GetWeight() > 0 then
                        layerInfo = layerInfo .. string.format(" [%d:%s W:%.2f C:%.2f R:%.2f]",
                            i, ent:GetSequenceName(layer:GetSequence()) or "?",
                            layer:GetWeight(), layer:GetCycle(), layer:GetPlaybackRate())
                    end
                end
            end

            print(string.format("[DBG] %s[%d] Seq:%s Act:%d GS:%.1f Dur:%.2f Spd:%.1f Pos:%.1f SO:%.1f LZ:%.1f LHitZ:%.1f LLocZ:%.1f RZ:%.1f RHitZ:%.1f RLocZ:%.1f Off:%.1f Bl:%.1f SmOff:%.1f Psh:%.1f Dom:%s Mn:%.1f Mx:%.1f%s%s%s%s",
                cls, ent:EntIndex(), seqName, seqAct, groundSpeed, seqDur, spd, pos.z, step, ent._LeftFootDist or 0, ent._LeftFootHitZ or 0, ent._LeftFootLocalZ or 0, ent._RightFootDist or 0, ent._RightFootHitZ or 0, ent._RightFootLocalZ or 0, off, blend, smoothOff, push, dom, mn, mx, boneInfo, groundInfo, cycleInfo, rateInfo, layerInfo))
        end
    end)

    print("[CityNPCs] Client loaded")
end
