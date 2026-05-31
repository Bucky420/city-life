AddCSLuaFile()

ENT.Type = "nextbot"
ENT.Base = "base_nextbot"
ENT.PrintName = "Test v1"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Author = "City NPCs"
ENT.Purpose = "HL2-style citizen NPC with squad follow + turn gestures"
ENT.Instructions = "Press +USE to recruit. Follows commander."

local FOLLOW_STOP_DIST = 75
local FOLLOW_START_DIST = 110
local FOLLOW_RUN_DIST = 450
local FOLLOW_LOST_DIST = 3000

function ENT:Initialize()

    self:SetModel("models/Humans/Group03/male_01.mdl")
    self:SetIK(true)
    if SERVER then
        self:PhysicsInit(SOLID_BBOX)
        self:SetMoveType(MOVETYPE_STEP)
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionGroup(COLLISION_GROUP_NPC)
        self:SetHealth(100)
        self:SetMaxHealth(100)
        self:SetUseType(SIMPLE_USE)
        self.loco:SetAcceleration(400)
        self.loco:SetDeceleration(400)
        self.loco:SetStepHeight(18)
        self.loco:SetMaxYawRate(360)
      
        self.Commander = nil
        self.NextTurnTime = 0
    end
end

function ENT:AcceptInput(name, activator, caller, data)
    if SERVER and name == "Use" and IsValid(activator) and activator:IsPlayer() and activator:Alive() then
        if self.Commander == activator then
            self.Commander = nil
        else
            self.Commander = activator
        end
        return true
    end
end

function ENT:BodyUpdate()
    if not SERVER then return end
    local vel = self.loco:GetVelocity():Length2D()
    local act = self:GetActivity()
                    self.loco:SetAcceleration(200)
                    self.loco:SetDesiredSpeed(20)
    local isIdle = vel < 5
    self:SetNWBool("PlantFeet", isIdle)
    if vel > 120 then
        if act ~= ACT_RUN then
            self:StartActivity(ACT_RUN)
        end
        self:BodyMoveXY()
    elseif isIdle then
        if act ~= ACT_IDLE then
            self:StartActivity(ACT_IDLE)
           
        end
          self:BodyMoveXY()
    elseif act == ACT_RUN and vel < 60 then
        self:StartActivity(ACT_WALK)
        self:BodyMoveXY()
    elseif act == ACT_IDLE then
        self:StartActivity(ACT_WALK)
        self:BodyMoveXY()
    else
        self:BodyMoveXY()
    end
end

function ENT:AddTurnGesture(yawDeltaDeg)
    if CurTime() < self.NextTurnTime then return end
    self.NextTurnTime = CurTime() + 0.5

    local absDelta = math.abs(yawDeltaDeg)
    if absDelta < 15 then return end

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

    local seqIdx = self:SelectWeightedSequence(turnAct)
    if seqIdx and seqIdx >= 0 then
        local layerId = self:AddGestureSequence(seqIdx, true)
        if layerId and layerId >= 0 then
            self:SetLayerPriority(layerId, 10)
        end
    end
end

function ENT:RunBehaviour()
    while self:IsValid() and self:Health() > 0 do
        if self.Commander and IsValid(self.Commander) and self.Commander:Alive() then
            local cmdPos = self.Commander:GetPos()
            local dist = self:GetPos():Distance(cmdPos)

            if dist > FOLLOW_LOST_DIST then
                self.Commander = nil
                coroutine.wait(1)
                continue
            end

            if dist > FOLLOW_STOP_DIST then
                local speed = dist > FOLLOW_RUN_DIST and 350 or (dist > FOLLOW_START_DIST and 100 or 60)
                self.loco:SetDesiredSpeed(speed)

                while dist > FOLLOW_STOP_DIST do
                    cmdPos = self.Commander:GetPos()
                    dist = self:GetPos():Distance(cmdPos)
                    if dist > FOLLOW_LOST_DIST then break end
                    self.loco:FaceTowards(cmdPos)
                    self.loco:Approach(cmdPos, 1)
                    local delta = (math.deg(math.atan2(cmdPos.y - self:GetPos().y, cmdPos.x - self:GetPos().x)) - self:GetAngles().y) % 360
                    if delta > 180 then delta = delta - 360 end
                    self:AddTurnGesture(delta)
                    coroutine.yield()
                end
            end

            self.loco:SetDesiredSpeed(1)
            coroutine.wait(1)
        else
            self.Commander = nil
            coroutine.wait(1)
        end
    end
end

 