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

if CLIENT then
    local FOOT_NAMES = { "ValveBiped.Bip01_L_Foot", "ValveBiped.Bip01_R_Foot" }
    local CALF_NAMES = { "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_R_Calf" }
    local PELVIS_NAME = "ValveBiped.Bip01_Pelvis"

    function ENT:Draw()
        if not self._FootIds then
            self._FootIds = {}
            self._FootNames = {}
            for _, name in ipairs(FOOT_NAMES) do
                local id = self:LookupBone(name)
                self._FootIds[#self._FootIds + 1] = id
                if id then self._FootNames[id] = name end
            end
            self._CalfIds = {}
            for _, name in ipairs(CALF_NAMES) do
                local id = self:LookupBone(name)
                self._CalfIds[#self._CalfIds + 1] = id
            end
            self._PelvisId = self:LookupBone(PELVIS_NAME)
            self._WasMoving = true
        end

        local plant = self:GetNWBool("PlantFeet")

        if not self._DFC then self._DFC = 0 end
        self._DFC = self._DFC + 1

        if plant then
            if self._WasMoving then
                self._WasMoving = false
                self._FootSlide = {}
            end

            self:SetupBones()

            local entPos = self:GetPos()
            local entRight = self:GetAngles():Right()

            local centerPos = entPos
            if self._PelvisId then
                local pelvisMat = self:GetBoneMatrix(self._PelvisId)
                if pelvisMat then
                    centerPos = pelvisMat:GetTranslation()
                end
            end

            for i, id in ipairs(self._FootIds) do
                if not id then continue end

                local footMat = self:GetBoneMatrix(id)
                if not footMat then continue end
                local footPos = footMat:GetTranslation()

                local parentId = self:GetBoneParent(id)
                if not parentId or parentId < 0 then continue end
                local parentMat = self:GetBoneMatrix(parentId)
                if not parentMat then continue end

                local sign = (i == 1) and -1 or 1
                local targetPos = centerPos + entRight * sign * 8
                targetPos.z = footPos.z

                local wdx = targetPos.x - footPos.x
                local wdy = targetPos.y - footPos.y
                local wdz = 0

                local pAng = parentMat:GetAngles()
                local localDelta = WorldToLocal(Vector(wdx, wdy, wdz), Angle(0,0,0), Vector(0,0,0), pAng)

                if not self._FootSlide then self._FootSlide = {} end
                if not self._FootSlide[id] then self._FootSlide[id] = Vector(0,0,0) end
                self._FootSlide[id] = self._FootSlide[id] + (localDelta - self._FootSlide[id]) * 0.25
                local sm = self._FootSlide[id]

                self:ManipulateBonePosition(id, sm)
            end

            self:SetupBones()

            if self._DFC % 30 == 0 then
                local fwd = self:GetAngles():Forward()
                local right = self:GetAngles():Right()
                local s = "[FOOT]"
                for _, id in ipairs(self._FootIds) do
                    if id then
                        local m = self:GetBoneMatrix(id)
                        if m then
                            local rel = m:GetTranslation() - centerPos
                            local f = rel:Dot(fwd)
                            local r = rel:Dot(right)
                        s = s .. string.format(" f%.1f r%.1f", f, r)
                end
            end
            if id then
                local sign = (i == 1) and -1 or 1
                local t = centerPos + right * sign * 8
                local rel = t - centerPos
                        local f = rel:Dot(fwd)
                        local r = rel:Dot(right)
                        s = s .. string.format(" f%.1f r%.1f", f, r)
                    end
                end
                print(s)
            end

        elseif not self._WasMoving then
            self._WasMoving = true
        end

        self:DrawModel()
    end
end