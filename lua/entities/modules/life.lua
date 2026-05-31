CityNPCs = CityNPCs or {}
CityNPCs.Modules = CityNPCs.Modules or {}

local Mod = {}
Mod.__index = Mod

-- Head look-at settings
local HEAD_BONE = "ValveBiped.Bip01_Head1"
local EYE_BONES = {
    "ValveBiped.Bip01_Eye_R",
    "ValveBiped.Bip01_Eye_L",
}

local HEAD_YAW_LIMIT = 60
local HEAD_PITCH_LIMIT = 30
local EYE_YAW_LIMIT = 15
local EYE_PITCH_LIMIT = 10

-- Ambient sound settings
local AMBIENT_SOUNDS = {
    "vo/npc/male01/answer01.wav",
    "vo/npc/male01/answer02.wav",
    "vo/npc/male01/answer03.wav",
    "vo/npc/male01/answer04.wav",
    "vo/npc/male01/answer05.wav",
    "vo/npc/male01/answer06.wav",
    "vo/npc/male01/answer07.wav",
    "vo/npc/male01/answer08.wav",
    "vo/npc/male01/answer09.wav",
    "vo/npc/male01/answer10.wav",
    "vo/npc/male01/answer11.wav",
    "vo/npc/male01/answer12.wav",
    "vo/npc/male01/answer13.wav",
    "vo/npc/male01/answer14.wav",
    "vo/npc/male01/answer15.wav",
    "vo/npc/male01/answer16.wav",
    "vo/npc/male01/answer17.wav",
    "vo/npc/male01/answer18.wav",
    "vo/npc/male01/answer19.wav",
    "vo/npc/male01/answer20.wav",
    "physics/flesh/flesh_impact_bullet1.wav",
    "physics/flesh/flesh_impact_bullet2.wav",
    "physics/flesh/flesh_impact_bullet3.wav",
    "physics/flesh/flesh_impact_bullet4.wav",
    "physics/flesh/flesh_impact_bullet5.wav",
    "player/footsteps/concrete1.wav",
    "player/footsteps/concrete2.wav",
    "player/footsteps/concrete3.wav",
    "player/footsteps/concrete4.wav",
}

local HEAD_TURN_SPEED = 4
local AMBIENT_MIN_INTERVAL = 8
local AMBIENT_MAX_INTERVAL = 25

-- CLIENT ONLY: Update head and eye pose parameters
function Mod.Think(ent)
    local headBone = ent:LookupBone(HEAD_BONE)
    if not headBone or headBone < 0 then return end

    local myPos = ent:GetPos()

    -- Find nearest visible player within range
    local lookTarget
    local nearestDist = 800

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then
            local dist = myPos:DistToSqr(ply:GetPos())
            if dist < nearestDist * nearestDist then
                local toPly = (ply:GetPos() - myPos):GetNormalized()
                if ent:GetForward():Dot(toPly) > 0 then
                    lookTarget = ply:GetPos() + Vector(0, 0, 60)
                    nearestDist = math.sqrt(dist)
                end
            end
        end
    end

    if not lookTarget then
        local randAng = Angle(0, math.random(0, 360), 0)
        lookTarget = myPos + randAng:Forward() * math.random(100, 300)
    end

    local headMat = ent:GetBoneMatrix(headBone)
    if not headMat then return end
    local headPos = headMat:GetTranslation()
    local dir = (lookTarget - headPos):GetNormalized()
    local ang = dir:Angle()

    local targetYaw = math.Clamp(math.AngleDifference(ang.y, ent:GetAngles().y), -HEAD_YAW_LIMIT, HEAD_YAW_LIMIT)
    local targetPitch = math.Clamp(math.AngleDifference(ang.p, ent:GetAngles().p), -HEAD_PITCH_LIMIT, HEAD_PITCH_LIMIT)

    local curYaw = ent._HeadYaw or 0
    local curPitch = ent._HeadPitch or 0
    local rate = FrameTime() * HEAD_TURN_SPEED
    ent._HeadYaw = Lerp(rate, curYaw, targetYaw)
    ent._HeadPitch = Lerp(rate, curPitch, targetPitch)

    ent:SetPoseParameter("head_yaw", ent._HeadYaw)
    ent:SetPoseParameter("head_pitch", ent._HeadPitch)

    ent:SetPoseParameter("eye_yaw", math.Clamp(ent._HeadYaw * 0.8, -EYE_YAW_LIMIT, EYE_YAW_LIMIT))
    ent:SetPoseParameter("eye_pitch", math.Clamp(ent._HeadPitch * 0.8, -EYE_PITCH_LIMIT, EYE_PITCH_LIMIT))
end

-- SERVER: Initialize ambient sound timer
function Mod.Init(ent)
    ent._NextAmbientSound = CurTime() + math.random(AMBIENT_MIN_INTERVAL, AMBIENT_MAX_INTERVAL)
end

-- SERVER: Think hook for ambient sounds
function Mod.ThinkServer(ent)
    if CurTime() < (ent._NextAmbientSound or 0) then return end
    ent._NextAmbientSound = CurTime() + math.random(AMBIENT_MIN_INTERVAL, AMBIENT_MAX_INTERVAL)

    local snd = AMBIENT_SOUNDS[math.random(#AMBIENT_SOUNDS)]
    ent:EmitSound(snd, 70, math.random(90, 110), 0.6)
end

CityNPCs.Modules.life = Mod
