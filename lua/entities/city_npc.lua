AddCSLuaFile()

ENT.Type = "nextbot"
ENT.Base = "base_nextbot"
ENT.PrintName = "City NPC"
ENT.Spawnable = false
ENT.AdminOnly = false
ENT.Author = "City NPCs"
ENT.Purpose = "Wandering citizen NPCs using nav mesh"
ENT.Instructions = "Spawn and they will walk on sidewalks"


function ENT:Initialize()
   
        self:SetModel("models/Humans/Group03/male_01.mdl")
    if SERVER then


        self:PhysicsInit(SOLID_BBOX)
        self:SetMoveType(MOVETYPE_STEP)
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionGroup(COLLISION_GROUP_NPC)
        self:SetHealth(100)
        self:SetMaxHealth(100)
        self:SetIK(true)
        self.loco:SetDesiredSpeed(60)
        self.loco:SetAcceleration(400)
        self.loco:SetDeceleration(400)
        self.loco:SetStepHeight(18)
        self.loco:SetMaxYawRate(360)
        self:StartActivity(ACT_IDLE)
    end
end

function ENT:BodyUpdate()
    if not SERVER then return end

    local curPos = self:GetPos()
    local delta = curPos - (self._LastBodyPos or curPos)
    self._LastBodyPos = curPos
    local speed = delta:Length2D() / (FrameTime() or 0.016)

    if speed > 5 then
        if self:GetActivity() ~= ACT_WALK then
            self:StartActivity(ACT_WALK)
        end
    else
        if self:GetActivity() ~= ACT_IDLE then
            self:StartActivity(ACT_IDLE)
        end
    end

    self:BodyMoveXY()
end

function ENT:OnRemove()
    if CityNPCs and CityNPCs.ActiveNPCs then
        for i, npc in ipairs(CityNPCs.ActiveNPCs) do
            if npc == self then
                table.remove(CityNPCs.ActiveNPCs, i)
                break
            end
        end
    end
end

function ENT:RunBehaviour()
    while self:IsValid() and self:Health() > 0 do
        local players = ents.FindInSphere(self:GetPos(), 50)
        local blocked = false

        for _, p in ipairs(players) do
            if p:IsPlayer() then
                local dot = self:GetForward():Dot((p:GetPos() - self:GetPos()):GetNormalized())
                if dot > 0.7 then
                    blocked = true
                    break
                end
            end
        end

        if blocked then
            self.loco:SetDesiredSpeed(30)
            self:MoveToPos(self:GetPos() - self:GetForward() * 30, {
                tolerance = 10,
                maxage = 1
            })
            coroutine.wait(0.2)
            continue
        end

        local dest = CityNPCs.FindDestination(self)
        if not dest then
            coroutine.wait(1)
            continue
        end

        local path = CityNPCs.BuildPath(self, self:GetPos(), dest)
        if path then
            self.loco:SetDesiredSpeed(60)
            self:MoveToPos(dest, {
                path = path,
                look_ahead = 200,
                tolerance = 30,
                maxage = 10,
                draw = false
            })
        end

        self.loco:SetDesiredSpeed(0)
        coroutine.wait(math.random(2, 5))
    end
end

function ENT:Draw()
    self:DrawModel()
end

if CLIENT then
    language.Add("city_npc", "City NPC")
end
