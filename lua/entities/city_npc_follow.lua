AddCSLuaFile()

ENT.Type = "nextbot"
ENT.Base = "city_base_npc"

ENT.PrintName = "City NPC (Follow)"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Author = "City NPCs"
ENT.Purpose = "Follows the commander when +USE'd"
ENT.Instructions = "Press +USE to recruit. Follows commander."

ENT.ModuleNames = { "move", "turn", "life", "z" }

ENT.Config = {
    Model = "models/Humans/Group03/male_01.mdl",
    WalkSpeed = 75,
    RunSpeed = 150,
    Accel = 200,
    Decel = 200,
    StepHeight = 18,
    MaxYawRate = 180,
    Health = 100,
}

local FOLLOW_STOP_DIST = 75
local FOLLOW_RUN_DIST = 450
local FOLLOW_LOST_DIST = 30000
local FOLLOW_SPEED_WALK = 75
local FOLLOW_SPEED_RUN = 150

if SERVER then

function ENT:AcceptInput(name, activator)
    if name ~= "Use" then return end
    if not IsValid(activator) or not activator:IsPlayer() or not activator:Alive() then return end
    self.Commander = (self.Commander == activator) and nil or activator
    return true
end

function ENT:RunBehaviour()
    while self:IsValid() and self:Health() > 0 do
        if self.Commander and IsValid(self.Commander) and self.Commander:Alive() then
            local cmdPos = self.Commander:GetPos()
            local dist = self:GetPos():Distance(cmdPos)

            if dist > FOLLOW_LOST_DIST then
                coroutine.wait(1)
                continue
            end

            if dist > FOLLOW_STOP_DIST then
                local toTarget = (cmdPos - self:GetPos()):GetNormalized()
                self.loco:FaceTowards(cmdPos)
                local faceStart = CurTime()
                while self:GetForward():Dot(toTarget) < 0.9 and CurTime() - faceStart < 0.5 do
                    toTarget = (cmdPos - self:GetPos()):GetNormalized()
                    self.loco:FaceTowards(cmdPos)
                    coroutine.yield()
                end

                self.loco:SetDesiredSpeed(FOLLOW_SPEED_WALK)

                local stuckPos = self:GetPos()
                local stuckTime = 0

                while self.Commander and IsValid(self.Commander) and self.Commander:Alive() do
                    cmdPos = self.Commander:GetPos()
                    dist = self:GetPos():Distance(cmdPos)

                    if dist > FOLLOW_LOST_DIST then break end
                    if dist <= FOLLOW_STOP_DIST then break end

                    local speed = dist > FOLLOW_RUN_DIST and FOLLOW_SPEED_RUN or FOLLOW_SPEED_WALK
                    self.loco:SetDesiredSpeed(speed)

                    if self:GetPos():Distance(stuckPos) < 8 then
                        stuckTime = stuckTime + FrameTime()
                    else
                        stuckPos = self:GetPos()
                        stuckTime = 0
                    end

                    if stuckTime > 2 then
                        break
                    end

                    self.loco:FaceTowards(cmdPos)
                    self.loco:Approach(cmdPos, 1)

                    coroutine.yield()
                end
            else
                coroutine.wait(1)
            end
        else
            self.Commander = nil
            coroutine.wait(1)
        end
    end
end

end

language.Add("city_npc_follow", "City NPC (Follow)")
