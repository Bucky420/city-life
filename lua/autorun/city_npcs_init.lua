include("city_npcs/nav_metadata.lua")

-- Load modules (shared, needed before entities reference them)
include("entities/modules/move.lua")
include("entities/modules/z.lua")
include("entities/modules/gestures.lua")
include("entities/modules/life.lua")
include("entities/modules/npc_debug.lua")
 
list.Set("NPC", "city_npc", {
    Name = "City NPC", 
    Class = "city_npc",
    Category = "Citizens"
})

list.Set("NPC", "city_npc_follow", {
    Name = "City NPC (Follow)",
    Class = "city_npc_follow",
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

list.Set("NPC", "city_anim_test05_base_ai", {
    Name = "Test v5 (base_ai)",
    Class = "city_anim_test05_base_ai",
    Category = "Citizens"
})

if SERVER then
    AddCSLuaFile("city_npcs/nav_metadata.lua")
    AddCSLuaFile("city_npcs/cl_ui.lua")
    AddCSLuaFile("city_npcs/cl_anim_viewer.lua")
    AddCSLuaFile("entities/modules/move.lua")
    AddCSLuaFile("entities/modules/z.lua")
    AddCSLuaFile("entities/modules/gestures.lua")
    AddCSLuaFile("entities/modules/life.lua")
    AddCSLuaFile("entities/modules/npc_debug.lua")

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

    local cityNpcClasses = {
        ["city_npc"] = true,
        ["city_npc_follow"] = true,
        ["city_anim_test_npc"] = true,
        ["city_anim_test02_npc"] = true,
        ["city_anim_final_npc_test3"] = true,
        ["city_anim_test04_player"] = true,
        ["city_anim_test05_base_ai"] = true,
        ["npc_citizen"] = true,
    }

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
        for _, ent in ipairs(ents.FindByClass("city_npc_follow")) do
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
        if not cityNpcClasses[cls] then
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[CityNPCs] Look at a city NPC entity") end
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
        if not cityNpcClasses[cls] then
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[CityNPCs] Look at a city NPC entity") end
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

    concommand.Remove("citynpc_dump_animevents")
    concommand.Add("citynpc_dump_animevents", function(ply)
        local target = ply:GetEyeTrace().Entity
        local cls = IsValid(target) and target:GetClass() or ""
        if not cityNpcClasses[cls] then
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[CityNPCs] Look at a city NPC entity") end
            return
        end
        local mdl = target:GetModel()
        local info = util.GetModelInfo(mdl)
        if not info or not info.Sequences then
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[CityNPCs] No ModelInfo available for " .. mdl) end
            return
        end
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "--- Animation Events (" .. mdl .. ") ---") end
        local totalEvents = 0
        for _, seq in ipairs(info.Sequences) do
            if seq.Events and #seq.Events > 0 then
                if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "Seq: " .. seq.Name .. " (" .. #seq.Events .. " events)") end
                totalEvents = totalEvents + #seq.Events
                for _, ev in ipairs(seq.Events) do
                    if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, string.format("  [%s] Cycle:%.3f Event:%d Name:%s Type:%d Options:%s", seq.Name, ev.Cycle, ev.Event, ev.Name, ev.Type, ev.Options)) end
                end
            end
        end
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "--- End (" .. totalEvents .. " total events) ---") end
    end)

    CityNPCs.ServerDbgEnts = CityNPCs.ServerDbgEnts or {}

    local function serverDebugMessage(ply, msg)
        print(msg)
        if IsValid(ply) then
            ply:PrintMessage(HUD_PRINTCONSOLE, msg)
            ply:PrintMessage(HUD_PRINTTALK, msg)
        end
    end

    concommand.Remove("citynpc_debug_entity")
    concommand.Add("citynpc_debug_entity", function(ply)
        if not IsValid(ply) then
            print("[CityNPCs] citynpc_debug_entity must be run by a player")
            return
        end

        local target = ply:GetEyeTrace().Entity
        if not IsValid(target) then
            serverDebugMessage(ply, "[CityNPCs] Look at an entity first")
            return
        end

        local idx = target:EntIndex()
        if CityNPCs.ServerDbgEnts[idx] then
            CityNPCs.ServerDbgEnts[idx] = nil
            serverDebugMessage(ply, "[CityNPCs] Server Debug OFF for " .. target:GetClass() .. " [" .. idx .. "]")
        else
            CityNPCs.ServerDbgEnts[idx] = { ent = target, owner = ply, nextPrint = 0 }
            serverDebugMessage(ply, "[CityNPCs] Server Debug ON for " .. target:GetClass() .. " [" .. idx .. "] model=" .. tostring(target:GetModel()) .. " isnpc=" .. tostring(target:IsNPC()))
        end
    end)

    hook.Remove("Think", "CityNPCs_ServerDebugEntity")
    hook.Add("Think", "CityNPCs_ServerDebugEntity", function()
        for idx, data in pairs(CityNPCs.ServerDbgEnts) do
            local ent = data.ent
            if not IsValid(ent) then
                CityNPCs.ServerDbgEnts[idx] = nil
            elseif CurTime() >= data.nextPrint then
                data.nextPrint = CurTime() + 0.5

                local pos = ent:GetPos()
                local vel = ent:GetVelocity():Length2D()
                local seq = ent:GetSequenceName(ent:GetSequence()) or "?"
                local commander = ent.Commander
                local follow = IsValid(commander)
                local target = ent:GetNWVector("CityV5MoveTarget", vector_origin)
                local fDist = ent:GetNWFloat("CityV5FollowDist", -1)

                serverDebugMessage(data.owner, string.format(
                    "[SDBG %s#%d] pos=%.1f,%.1f,%.1f vel=%.1f seq=%s isnpc=%s follow=%s fDist=%.1f tgt=%.1f,%.1f,%.1f",
                    ent:GetClass(), ent:EntIndex(), pos.x, pos.y, pos.z, vel, seq, tostring(ent:IsNPC()), tostring(follow), fDist, target.x, target.y, target.z
                ))
            end
        end
    end)

    print("[CityNPCs] Server loaded - commands: citynpc_spawn [n], citynpc_cleanup")
end

if CLIENT then
    include("city_npcs/cl_ui.lua")
    include("city_npcs/cl_anim_viewer.lua")
	print("[CityNPCs] Client debug commands loaded")

    CityNPCs = CityNPCs or {}
    CityNPCs.DbgEnts = CityNPCs.DbgEnts or {}
    local dbgFrame = 0
    local modelFootCycleCache = {}

    local function getModelFootCycles(model)
        if not model then return nil end
        if modelFootCycleCache[model] then return modelFootCycleCache[model] end

        local cache = {}
        local mi = util.GetModelInfo(model)
        if mi and mi.Sequences then
            for _, seq in ipairs(mi.Sequences) do
                local evt6006, evt6007
                if seq.Events then
                    for _, ev in ipairs(seq.Events) do
                        if ev.Event == 6006 then evt6006 = ev.Cycle end
                        if ev.Event == 6007 then evt6007 = ev.Cycle end
                    end
                end
                if evt6006 and evt6007 then
                    cache[seq.Name] = { left = evt6006, right = evt6007 }
                end
            end
        end

        modelFootCycleCache[model] = cache
        return cache
    end

    local function getOverlayInfo(ent)
        if not ent.IsValidLayer or not ent.GetLayerSequence then return "unsupported" end

        local parts = {}
        for slot = 0, 15 do
            local okValid, valid = pcall(ent.IsValidLayer, ent, slot)
            if okValid and valid then
                local _, seq = pcall(ent.GetLayerSequence, ent, slot)
                local _, weight = pcall(ent.GetLayerWeight, ent, slot)
                local _, layerCycle = pcall(ent.GetLayerCycle, ent, slot)
                local _, rate = pcall(ent.GetLayerPlaybackRate, ent, slot)

                seq = tonumber(seq) or -1
                weight = tonumber(weight) or 0
                layerCycle = tonumber(layerCycle) or 0
                rate = tonumber(rate) or 0

                if seq >= 0 or weight > 0 then
                    parts[#parts + 1] = string.format("%d:%d:%s c%.2f w%.2f r%.2f", slot, seq, ent:GetSequenceName(seq) or "?", layerCycle, weight, rate)
                end
            end
        end

        return (#parts > 0) and table.concat(parts, "|") or "none"
    end

    local function getSequenceDebug(ent, seq, cycle)
        local playbackRate = ent.GetPlaybackRate and ent:GetPlaybackRate() or -1
        local groundSpeed = ent.GetSequenceGroundSpeed and ent:GetSequenceGroundSpeed(seq) or -1
        local moveDist = ent.GetSequenceMoveDist and ent:GetSequenceMoveDist(seq) or -1
        local deltaXY = 0
        local deltaZ = 0

        if ent.GetSequenceMovement then
            local state = ent._CityNPCsDebugState or {}
            local lastSeq = state.LastSeq or seq
            local lastCycle = state.LastCycle or cycle
            local startCycle = (lastSeq == seq) and lastCycle or cycle
            local endCycle = cycle
            if lastSeq == seq and cycle < startCycle then
                endCycle = cycle + 1
            end
            local ok, delta = ent:GetSequenceMovement(seq, startCycle, endCycle)
            if ok and isvector(delta) then
                deltaXY = delta:Length2D()
                deltaZ = delta.z
            end
            state.LastSeq = seq
            state.LastCycle = cycle
            ent._CityNPCsDebugState = state
        end

        return playbackRate, groundSpeed, moveDist, deltaXY, deltaZ
    end

    local function safeActivity(ent)
        if not ent.GetActivity then return "?" end
        local ok, act = pcall(ent.GetActivity, ent)
        return ok and act or "?"
    end

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
            print("[CityNPCs] Debug OFF for " .. target:GetClass() .. " [" .. idx .. "] tracked=" .. table.Count(CityNPCs.DbgEnts))
        else
            CityNPCs.DbgEnts[idx] = target
            print("[CityNPCs] Debug ON for " .. target:GetClass() .. " [" .. idx .. "] model=" .. tostring(target:GetModel()) .. " tracked=" .. table.Count(CityNPCs.DbgEnts))
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

            local STEP_HEIGHT = 18
            local HULL_R = 2.5
            local PLANTED_FOOT_Z = 5.5
            local GROUND_Z_DEADZONE = 0.5
            local state = ent._CityNPCsDebugState or {}
            ent._CityNPCsDebugState = state

            local hullZ = ent:GetPos().z
            local traceZ = state.VisualZ or state.LastGroundZ or hullZ
            local cycle = ent:GetCycle()
            local seq = ent:GetSequence()
            local seqName = ent:GetSequenceName(seq) or "?"
            local playbackRate, seqGroundSpeed, seqMoveDist, seqDeltaXY, seqDeltaZ = getSequenceDebug(ent, seq, cycle)
            local footCycle = getModelFootCycles(ent:GetModel())
            footCycle = footCycle and footCycle[seqName]

            local activeFoot = "left"
            if footCycle then
                local function cycleDist(a, b)
                    local d = math.abs(a - b)
                    return math.min(d, math.abs(d - 1))
                end
                activeFoot = (cycleDist(cycle, footCycle.left) < cycleDist(cycle, footCycle.right)) and "left" or "right"
            end

            local function footLocalZ(bone)
                if not bone or bone < 0 then return nil end
                local m = ent:GetBoneMatrix(bone)
                if not m then return nil end
                return ent:WorldToLocal(m:GetTranslation()).z
            end

            local function doTrace(bone, footName)
                if not bone or bone < 0 then return nil end
                local mat = ent:GetBoneMatrix(bone)
                if not mat then return nil end
                local footPos = mat:GetTranslation()
                local tr = util.TraceHull({
                    start = Vector(footPos.x, footPos.y, traceZ + STEP_HEIGHT + 2),
                    endpos = Vector(footPos.x, footPos.y, traceZ - STEP_HEIGHT - 2),
                    mins = Vector(-HULL_R, -HULL_R, 0),
                    maxs = Vector(HULL_R, HULL_R, 1),
                    filter = ent,
                    mask = MASK_SOLID
                })
                return tr.Hit and tr.HitPos.z or nil
            end

            local leftHit = doTrace(lFootBone, "L")
            local rightHit = doTrace(rFootBone, "R")
            local minGroundZ = leftHit and rightHit and math.min(leftHit, rightHit) or leftHit or rightHit
            local maxGroundZ = leftHit and rightHit and math.max(leftHit, rightHit) or leftHit or rightHit
            local activeLocalZ = (activeFoot == "left") and footLocalZ(lFootBone) or footLocalZ(rFootBone)
            local activePlanted = activeLocalZ and activeLocalZ < PLANTED_FOOT_Z

            local groundZ
            if activeFoot == "left" then
                groundZ = (activePlanted and leftHit) or state.LastGroundZ or leftHit or rightHit
            else
                groundZ = (activePlanted and rightHit) or state.LastGroundZ or rightHit or leftHit
            end

            if groundZ then
                groundZ = math.Clamp(groundZ, traceZ - STEP_HEIGHT, traceZ + STEP_HEIGHT)
                if state.LastGroundZ and math.abs(groundZ - state.LastGroundZ) < GROUND_Z_DEADZONE then
                    groundZ = state.LastGroundZ
                end

                state.EstIkFloor = groundZ
                local renderOffset = math.Clamp(state.EstIkFloor - hullZ, -STEP_HEIGHT, 0)
                state.RenderZ = hullZ + renderOffset

                state.LastGroundZ = groundZ
                state.VisualZ = groundZ
            end

            local function fmtZ(v)
                return v and string.format("%.1f", v) or "?"
            end

            local cls = ent:GetClass()
            local label = ent.CityDebugLabel and ent:CityDebugLabel() or ((cls == "npc_citizen") and "stock" or "test")
            local extra = ""
            if cls == "city_anim_test05_base_ai" then
                local target = ent:GetNWVector("CityV5MoveTarget", vector_origin)
                extra = " follow=" .. tostring(ent:GetNWBool("CityV5Following", false)) ..
                    " fDist=" .. fmtZ(ent:GetNWFloat("CityV5FollowDist", -1)) ..
                    " tgt=" .. fmtZ(target.x) .. "," .. fmtZ(target.y) .. "," .. fmtZ(target.z)
            elseif cls == "city_anim_final_npc_test3" then
                local serverZ = ent:GetNWFloat("CityV3ServerOriginZ", hullZ)
                extra = " srvZ=" .. fmtZ(serverZ) ..
                    " zDelta=" .. fmtZ(hullZ - serverZ) ..
                    " spd=" .. fmtZ(ent:GetNWFloat("CityV3MoveSpeed", 0)) ..
                    " desired=" .. fmtZ(ent:GetNWFloat("CityV3DesiredSpeed", -1))
            end

            print("[DBG " .. label .. " " .. cls .. "#" .. ent:EntIndex() .. "] CYCLE=" .. string.format("%.3f", cycle) ..
                " active=" .. activeFoot ..
                " Lz=" .. fmtZ(footLocalZ(lFootBone)) ..
                " Rz=" .. fmtZ(footLocalZ(rFootBone)) ..
                " gZ=" .. (groundZ and string.format("%.1f", groundZ) or "nil") ..
                " minZ=" .. fmtZ(minGroundZ) ..
                " maxZ=" .. fmtZ(maxGroundZ) ..
                " estZ=" .. fmtZ(state.EstIkFloor) ..
                " rZ=" .. fmtZ(state.RenderZ) ..
                " seq=" .. seq .. ":" .. seqName ..
                " act=" .. tostring(safeActivity(ent)) ..
                " pb=" .. fmtZ(playbackRate) ..
                " gspd=" .. fmtZ(seqGroundSpeed) ..
                " mdist=" .. fmtZ(seqMoveDist) ..
                " seqDxy=" .. fmtZ(seqDeltaXY) ..
                " seqDz=" .. fmtZ(seqDeltaZ) ..
                " overlays=" .. getOverlayInfo(ent) ..
                " model=" .. (ent:GetModel() or "?") ..
                " hullZ=" .. string.format("%.1f", hullZ) .. extra)
        end
    end)

    concommand.Remove("citynpc_debug_flexes")
    concommand.Add("citynpc_debug_flexes", function()
        local target = LocalPlayer():GetEyeTrace().Entity
        if not IsValid(target) then
            print("[CityNPCs] Look at an entity first")
            return
        end
        local n = target:GetFlexNum()
        if not n or n == 0 then
            print("[CityNPCs] Entity has no flex controllers")
            return
        end
        print("[CityNPCs] --- Flex Controllers (" .. n .. ") on " .. target:GetClass() .. " ---")
        for i = 0, n - 1 do
            local name = target:GetFlexName(i)
            local w = target:GetFlexWeight(i)
            local t = target:GetFlexType(i)
            if name and name ~= "" then
                print(string.format("  [%d] %s  type=%s  weight=%.3f", i, name, t or "?", w or 0))
            end
        end
        print("[CityNPCs] --- End ---")
    end)

    print("[CityNPCs] Client loaded")
end
