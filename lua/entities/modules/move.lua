CityNPCs = CityNPCs or {}
CityNPCs.Modules = CityNPCs.Modules or {}

local Mod = {}
Mod.__index = Mod

-- ACT transitions based on velocity
function Mod.BodyUpdate(ent)
    local act = ent:GetActivity()
    local speed = ent.loco:GetVelocity():Length2D()
    local wantMove = speed > 20

    local newAct = wantMove and ACT_WALK or ACT_IDLE

    if newAct ~= act and newAct then
        ent:StartActivity(newAct)
    end

    ent:BodyMoveXY()
end

-- Move backwards away from a position
function Mod.MoveBackwards(ent, awayFrom, dist)
    dist = dist or 100
    local dir = (ent:GetPos() - awayFrom):GetNormalized()
    local target = ent:GetPos() + dir * dist
    ent.loco:FaceTowards(awayFrom)
    ent.loco:Approach(target, 1)
end

-- Strafe left or right while facing a target
function Mod.Strafe(ent, side, faceTarget)
    side = side or 1 -- 1 = right, -1 = left
    local right = ent:GetRight() * side * 100
    local target = ent:GetPos() + right
    if faceTarget then
        ent.loco:FaceTowards(faceTarget)
    end
    ent.loco:Approach(target, 1)
end

-- Jump
function Mod.Jump(ent, height)
    height = height or 200
    ent.loco:Jump()
    ent.loco:SetVelocity(Vector(0, 0, height))
end

-- Flinch - play a quick hurt gesture
function Mod.Flinch(ent)
    if CurTime() < (ent._NextFlinch or 0) then return end
    ent._NextFlinch = CurTime() + 0.5

    local seqIdx = ent:SelectWeightedSequence(ACT_FLINCH_CHEST)
    if seqIdx and seqIdx >= 0 then
        local layerId = ent:AddGestureSequence(seqIdx, true)
        if layerId and layerId >= 0 then
            ent:SetLayerPriority(layerId, 10)
        end
    end
end

-- Set desired speed with optional lerp
function Mod.SetSpeed(ent, speed, lerp)
    if lerp then
        local cur = ent.loco:GetDesiredSpeed()
        ent.loco:SetDesiredSpeed(Lerp(lerp, cur, speed))
    else
        ent.loco:SetDesiredSpeed(speed)
    end
end

CityNPCs.Modules.move = Mod
