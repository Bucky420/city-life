CityNPCs = CityNPCs or {}
CityNPCs.Modules = CityNPCs.Modules or {}

local Mod = {}
Mod.__index = Mod

local TURN_GESTURE_COOLDOWN = 0.5
local TURN_GESTURE_MIN_DELTA = 15

function Mod.AddTurnGesture(ent, yawDeltaDeg)
    if CurTime() < (ent._NextTurnTime or 0) then return end
    ent._NextTurnTime = CurTime() + TURN_GESTURE_COOLDOWN

    local absDelta = math.abs(yawDeltaDeg)
    if absDelta < TURN_GESTURE_MIN_DELTA then return end

    local turnAct
    if yawDeltaDeg < -45 then
        turnAct = ACT_GESTURE_TURN_RIGHT90
    elseif yawDeltaDeg < 0 then
        turnAct = ACT_GESTURE_TURN_RIGHT45
    elseif yawDeltaDeg <= 45 then
        turnAct = ACT_GESTURE_TURN_LEFT45
    else
        turnAct = ACT_GESTURE_TURN_LEFT90
    end

    local seqIdx = ent:SelectWeightedSequence(turnAct)
    if seqIdx and seqIdx >= 0 then
        local layerId = ent:AddGestureSequence(seqIdx, true)
        if layerId and layerId >= 0 then
            ent:SetLayerPriority(layerId, 100)
        end
    end
end

function Mod.TryTurnGesture(ent, targetPos)
    local yawDelta = math.deg(math.atan2(
        targetPos.y - ent:GetPos().y,
        targetPos.x - ent:GetPos().x
    )) - ent:GetAngles().y
    yawDelta = yawDelta % 360
    if yawDelta > 180 then yawDelta = yawDelta - 360 end
    Mod.AddTurnGesture(ent, yawDelta)
end

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

CityNPCs.Modules.gestures = Mod
