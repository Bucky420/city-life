CityNPCs = CityNPCs or {}
CityNPCs.Modules = CityNPCs.Modules or {}

local Mod = {}
Mod.__index = Mod

local TRACE_DIST = 72
local FOOT_RADIUS = 2.5
local VISUAL_Z_RATE = 0.07

function Mod.Draw(ent)
    ent:SetIK(true)
    ent:SetupBones()

    local lFootBone = ent:LookupBone("ValveBiped.Bip01_L_Foot")
    local rFootBone = ent:LookupBone("ValveBiped.Bip01_R_Foot")

    local groundZ = nil
    local fwd = ent:GetForward()
    local footFwd = Vector(fwd.x, fwd.y, 0):GetNormalized() * 4

    if lFootBone then
        local mat = ent:GetBoneMatrix(lFootBone)
        if mat then
            local start = mat:GetTranslation() + footFwd
            local tr = util.TraceHull({
                start = start,
                endpos = start - Vector(0, 0, TRACE_DIST),
                mins = Vector(-FOOT_RADIUS, -FOOT_RADIUS, 0),
                maxs = Vector(FOOT_RADIUS, FOOT_RADIUS, 1),
                filter = ent,
                mask = MASK_SOLID
            })
            if tr.Hit then
                groundZ = tr.HitPos.z
            end
        end
    end

    if rFootBone then
        local mat = ent:GetBoneMatrix(rFootBone)
        if mat then
            local start = mat:GetTranslation() + footFwd
            local tr = util.TraceHull({
                start = start,
                endpos = start - Vector(0, 0, TRACE_DIST),
                mins = Vector(-FOOT_RADIUS, -FOOT_RADIUS, 0),
                maxs = Vector(FOOT_RADIUS, FOOT_RADIUS, 1),
                filter = ent,
                mask = MASK_SOLID
            })
            if tr.Hit then
                if groundZ then
                    groundZ = math.min(groundZ, tr.HitPos.z)
                else
                    groundZ = tr.HitPos.z
                end
            end
        end
    end

    if groundZ then
        local pos = ent:GetPos()
        ent._VisualZ = Lerp(VISUAL_Z_RATE, ent._VisualZ or groundZ, groundZ)
        ent:SetPos(Vector(pos.x, pos.y, ent._VisualZ))
        ent:SetupBones()
        ent:DrawModel()
        ent:SetPos(pos)
    else
        ent:DrawModel()
    end
end

function Mod.OnRemove(ent)
    ent._VisualZ = nil
end

CityNPCs.Modules.z = Mod
