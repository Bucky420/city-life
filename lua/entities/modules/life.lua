CityNPCs = CityNPCs or {}
CityNPCs.Modules = CityNPCs.Modules or {}

local Mod = {}
Mod.__index = Mod

-- Head look-at settings
local HEAD_BONE = "ValveBiped.Bip01_Head1"

local HEAD_YAW_LIMIT = 60
local HEAD_PITCH_LIMIT = 30
local EYE_YAW_LIMIT = 25
local EYE_PITCH_LIMIT = 15
local EYE_SACCADE_MIN = 0.3
local EYE_SACCADE_MAX = 2.5
local BLINK_MIN = 3
local BLINK_MAX = 8
local BROW_MIN = 2
local BROW_MAX = 6

-- Greeting sounds played on spawn
local GREET_SOUNDS = {
    "vo/npc/male01/goodness01.wav",
    "vo/npc/male01/hello01.wav",
    "vo/npc/male01/question01.wav",
    "vo/npc/male01/question02.wav",
    "vo/npc/male01/question05.wav",
    "vo/npc/male01/question06.wav",
    "vo/npc/male01/answer01.wav",
    "vo/npc/male01/answer04.wav",
    "vo/npc/male01/answer09.wav",
    "vo/npc/male01/answer14.wav",
    "vo/npc/male01/answer16.wav",
    "vo/npc/male01/answer20.wav",
}

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

local TALK_DURATION_GREET = 2.5
local TALK_DURATION_AMBIENT = 2

local HEAD_TURN_SPEED = 4
local AMBIENT_MIN_INTERVAL = 8
local AMBIENT_MAX_INTERVAL = 25

-- CLIENT ONLY: Full face animation (head, eyes, brows, mouth, blink)
function Mod.Think(ent)
    local headBone = ent:LookupBone(HEAD_BONE)
    if not headBone or headBone < 0 then return end

    local myPos = ent:GetPos()
    local headMat = ent:GetBoneMatrix(headBone)
    if not headMat then return end
    local headPos = headMat:GetTranslation()

    local lookTarget
    local nearestDist = 800
    local hasTarget = false

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then
            local dist = myPos:DistToSqr(ply:GetPos())
            if dist < nearestDist * nearestDist then
                local toPly = (ply:GetPos() - myPos):GetNormalized()
                if ent:GetForward():Dot(toPly) > 0 then
                    lookTarget = ply:EyePos()
                    nearestDist = math.sqrt(dist)
                    hasTarget = true
                end
            end
        end
    end

    if not lookTarget then
        lookTarget = myPos
        lookTarget.z = headPos.z
    end

    -- Head rotation
    local dir = (lookTarget - headPos):GetNormalized()
    local ang = dir:Angle()

    local targetYaw = math.Clamp(math.AngleDifference(ang.y, ent:GetAngles().y), -HEAD_YAW_LIMIT, HEAD_YAW_LIMIT)
    local targetPitch = math.Clamp(math.AngleDifference(ang.p, ent:GetAngles().p), -HEAD_PITCH_LIMIT, HEAD_PITCH_LIMIT)

    local rate = FrameTime() * HEAD_TURN_SPEED
    ent._HeadYaw = Lerp(rate, ent._HeadYaw or 0, targetYaw)
    ent._HeadPitch = Lerp(rate, ent._HeadPitch or 0, targetPitch)
    ent:SetPoseParameter("head_yaw", ent._HeadYaw)
    ent:SetPoseParameter("head_pitch", ent._HeadPitch)

    -- Eye tracking via SetEyeTarget (engine handles flex controllers)
    if hasTarget then
        ent:SetEyeTarget(lookTarget)
    else
        -- Random saccades when no target
        if CurTime() > (ent._NextEyeSaccade or 0) then
            ent._NextEyeSaccade = CurTime() + math.random() * (EYE_SACCADE_MAX - EYE_SACCADE_MIN) + EYE_SACCADE_MIN
            ent._EyeSaccadeTarget = ent._EyeSaccadeTarget or myPos
            local randAng = Angle(0, math.random(0, 360), 0)
            ent._EyeSaccadeTarget = myPos + randAng:Forward() * math.random(50, 200)
            ent._EyeSaccadeTarget.z = headPos.z + math.random(-10, 10)
        end
        if ent._EyeSaccadeTarget then
            ent:SetEyeTarget(ent._EyeSaccadeTarget)
        end
    end

    -- Blinking
    if CurTime() > (ent._NextBlink or 0) then
        ent._NextBlink = CurTime() + math.random() * (BLINK_MAX - BLINK_MIN) + BLINK_MIN
        ent._BlinkUntil = CurTime() + 0.12
    end

    if ent._BlinkUntil and CurTime() < ent._BlinkUntil then
        local t = (ent._BlinkUntil - CurTime()) / 0.12
        local lid = math.abs(t - 0.5) * 2
        lid = 1 - lid
        ent:SetPoseParameter("eye_lid_open", lid)
    else
        ent:SetPoseParameter("eye_lid_open", 0)
    end

    -- Eyebrows (random subtle movement)
    if CurTime() > (ent._NextBrowChange or 0) then
        ent._NextBrowChange = CurTime() + math.random() * (BROW_MAX - BROW_MIN) + BROW_MIN
        ent._BrowTarget = (math.random() * 0.8 - 0.2)
        ent._BrowAngryTarget = math.random() * 0.3
    end

    local browRate = FrameTime() * 3
    ent._BrowSmooth = Lerp(browRate, ent._BrowSmooth or 0, ent._BrowTarget or 0)
    ent._BrowAngrySmooth = Lerp(browRate, ent._BrowAngrySmooth or 0, ent._BrowAngryTarget or 0)
    ent:SetPoseParameter("eyebrow_up_down", ent._BrowSmooth)
    ent:SetPoseParameter("eyebrow_angry", ent._BrowAngrySmooth)

    -- Mouth animation
    if ent:GetNWFloat("TalkingUntil", 0) > CurTime() then
        ent:SetPoseParameter("mouth_open", (math.sin(CurTime() * 15) * 0.5 + 0.5) * 0.6)
    else
        ent:SetPoseParameter("mouth_open", 0)
    end
end

-- SERVER: Initialize ambient sound timer and spawn greeting
function Mod.Init(ent)
    local snd = GREET_SOUNDS[math.random(#GREET_SOUNDS)]
    ent:EmitSound(snd, 70, math.random(90, 110), 0.6)
    ent:SetNWFloat("TalkingUntil", CurTime() + TALK_DURATION_GREET)

    -- Per-entity timer for ambient sounds only
    local id = "citynpc_life_" .. ent:EntIndex()
    timer.Create(id, 1, 0, function()
        if not IsValid(ent) then timer.Remove(id) return end
        if CurTime() < (ent._NextAmbientSound or 0) then return end
        ent._NextAmbientSound = CurTime() + math.random(AMBIENT_MIN_INTERVAL, AMBIENT_MAX_INTERVAL)

        local snd = AMBIENT_SOUNDS[math.random(#AMBIENT_SOUNDS)]
        ent:EmitSound(snd, 70, math.random(90, 110), 0.6)
        ent:SetNWFloat("TalkingUntil", CurTime() + TALK_DURATION_AMBIENT)
    end)
end

-- SERVER: Clean up timer when entity is removed
function Mod.OnRemove(ent)
    timer.Remove("citynpc_life_" .. ent:EntIndex())
end

CityNPCs.Modules.life = Mod
