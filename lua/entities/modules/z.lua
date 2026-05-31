CityNPCs = CityNPCs or {}
CityNPCs.Modules = CityNPCs.Modules or {}

local Mod = {}
Mod.__index = Mod

local TRACE_DIST = 72
local FOOT_RADIUS = 2.5
local SMOOTH_RATE = 0.15
local VISUAL_Z_RATE = 0.08

-- CLIENT ONLY: Compute foot IK Z offset before drawing
function Mod.Draw(ent)
    local pos = ent:GetPos()

    ent:SetIK(true)
    ent:SetupBones()

    local lFootBone = ent:LookupBone("ValveBiped.Bip01_L_Foot")
    local rFootBone = ent:LookupBone("ValveBiped.Bip01_R_Foot")

    local lFootRaw, rFootRaw

    if lFootBone and lFootBone >= 0 then
        local mat = ent:GetBoneMatrix(lFootBone)
        if mat then lFootRaw = mat:GetTranslation() end
    end
    if rFootBone and rFootBone >= 0 then
        local mat = ent:GetBoneMatrix(rFootBone)
        if mat then rFootRaw = mat:GetTranslation() end
    end

    local minGroundZ, maxGroundZ
    local fwd = ent:GetForward()
    local footForward = Vector(fwd.x, fwd.y, 0):GetNormalized() * 4
    local r = FOOT_RADIUS

    if lFootRaw then
        local lStart = lFootRaw + footForward
        local lEnd = lStart - Vector(0, 0, TRACE_DIST)
        local lTr = util.TraceHull({
            start = lStart,
            endpos = lEnd,
            mins = Vector(-r, -r, 0),
            maxs = Vector(r, r, 1),
            filter = ent,
            mask = MASK_SOLID
        })
        if lTr.Hit then
            minGroundZ = lTr.HitPos.z
            maxGroundZ = lTr.HitPos.z
            ent._LeftFootDist = lStart.z - lTr.HitPos.z
            ent._LeftFootHitZ = lTr.HitPos.z
        else
            ent._LeftFootDist = 99
            ent._LeftFootHitZ = nil
        end
        ent._LeftFootLocalZ = lFootRaw.z - pos.z
    end

    if rFootRaw then
        local rStart = rFootRaw + footForward
        local rEnd = rStart - Vector(0, 0, TRACE_DIST)
        local rTr = util.TraceHull({
            start = rStart,
            endpos = rEnd,
            mins = Vector(-r, -r, 0),
            maxs = Vector(r, r, 1),
            filter = ent,
            mask = MASK_SOLID
        })
        if rTr.Hit then
            if minGroundZ then
                minGroundZ = math.min(minGroundZ, rTr.HitPos.z)
                maxGroundZ = math.max(maxGroundZ, rTr.HitPos.z)
            else
                minGroundZ = rTr.HitPos.z
                maxGroundZ = rTr.HitPos.z
            end
            ent._RightFootDist = rStart.z - rTr.HitPos.z
            ent._RightFootHitZ = rTr.HitPos.z
        else
            ent._RightFootDist = 99
            ent._RightFootHitZ = nil
        end
        ent._RightFootLocalZ = rFootRaw.z - pos.z
    end

    if minGroundZ and maxGroundZ then
        local stepHeight = 18
        ent._StepOrigin = ent._StepOrigin or pos.z

        minGroundZ = math.min(minGroundZ, pos.z)
        maxGroundZ = math.min(maxGroundZ, pos.z)

        ent._SmoothMinZ = Lerp(SMOOTH_RATE, ent._SmoothMinZ or minGroundZ, minGroundZ)
        ent._SmoothMaxZ = Lerp(SMOOTH_RATE, ent._SmoothMaxZ or maxGroundZ, maxGroundZ)

        ent._StepOrigin = ent._StepOrigin * 0.2 + ent._SmoothMinZ * 0.8

        local bias = math.Clamp((ent._SmoothMaxZ - ent._SmoothMinZ) - stepHeight, 0, stepHeight)
        ent._DbgBlendOff = math.Clamp(ent._StepOrigin - pos.z, -stepHeight + bias, 0)
        ent._SmoothOff = Lerp(SMOOTH_RATE, ent._SmoothOff or ent._DbgBlendOff, ent._DbgBlendOff)

        ent._DbgMinZ = minGroundZ
        ent._DbgMaxZ = maxGroundZ
    else
        ent._DbgBlendOff = 0
        ent._DbgMinZ = pos.z
        ent._DbgMaxZ = pos.z
        ent._StepOrigin = pos.z
        ent._SmoothMinZ = nil
        ent._SmoothMaxZ = nil
    end

    local targetZ = pos.z + (ent._SmoothOff or 0)
    ent._VisualZ = Lerp(VISUAL_Z_RATE, ent._VisualZ or targetZ, targetZ)
    ent:SetPos(Vector(pos.x, pos.y, ent._VisualZ))
    ent:SetupBones()
    ent:DrawModel()
    ent:SetPos(pos)
end

function Mod.OnRemove(ent)
    ent._SmoothMinZ = nil
    ent._SmoothMaxZ = nil
    ent._VisualZ = nil
    ent._StepOrigin = nil
    ent._SmoothOff = nil
end

CityNPCs.Modules.z = Mod
