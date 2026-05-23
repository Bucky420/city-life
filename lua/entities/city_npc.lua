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
        self.loco:SetMaxYawRate(180)
    end
end

function ENT:OnContact(ent)
    if SERVER and ent:IsPlayer() then
        self.BlockedBy = ent
    end
end

function ENT:BodyUpdate()
    if not SERVER then return end
    local vel = self.loco:GetVelocity():Length2D()
    local act = self:GetActivity()

    if vel > 120 then 
        if act ~= ACT_RUN then
            self:StartActivity(ACT_RUN)
        end
        self:BodyMoveXY()
    elseif vel < 5 then
        if act ~= ACT_IDLE then
            self:StartActivity(ACT_IDLE)
        end
        self:FrameAdvance()
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
        local blockPlayer = self.BlockedBy
        self.BlockedBy = nil
        if not (blockPlayer and blockPlayer:IsValid()) then
            blockPlayer = nil
            for _, p in ipairs(ents.FindInSphere(self:GetPos(), 80)) do
                if p:IsPlayer() then
                    local toPlayer = (p:GetPos() - self:GetPos()):GetNormalized()
                    if self:GetForward():Dot(toPlayer) > -0.3 then
                        blockPlayer = p
                        break
                    end
                end
            end
        end

        if blockPlayer then
            local savedFwd = self:GetForward()
            local startPos = self:GetPos()
            local tr = util.TraceHull({
                start = startPos,
                endpos = startPos - savedFwd * 500,
                mins = self:OBBMins(),
                maxs = self:OBBMaxs(),
                filter = { self, blockPlayer },
                mask = MASK_SOLID
            })
            local maxDist = math.max(40, math.min(tr.Fraction * 500 - 40, 180))
            self.loco:SetDesiredSpeed(200)
            while (self:GetPos() - startPos):Length() < maxDist do
                self.loco:FaceTowards(self:GetPos() + savedFwd * 200)
                self.loco:Approach(self:GetPos() - savedFwd * 100, 1)
                coroutine.yield()
            end
            self.loco:SetDesiredSpeed(60)
            continue
        end

        local dest = CityNPCs.FindDestination(self)
        if not dest then
            self:StartActivity(ACT_IDLE)
            coroutine.wait(1)
            continue
        end

        local path = CityNPCs.BuildPath(self, self:GetPos(), dest)
        if path then
            local toDest = (dest - self:GetPos()):GetNormalized()
            if self:GetForward():Dot(toDest) < 0.95 then
                self.loco:FaceTowards(dest)
                while self:GetForward():Dot(toDest) < 0.95 do
                    self.loco:FaceTowards(dest)
                    coroutine.yield()
                end
            end
            self:StartActivity(ACT_WALK)
            self.loco:SetDesiredSpeed(60)
            self:MoveToPos(dest, {
                path = path,
                look_ahead = 300,
                tolerance = 30,
                maxage = 5,
                draw = false
            })
        end

        self:StartActivity(ACT_IDLE)
        coroutine.wait(math.random(1, 2))
    end
end

function ENT:Draw()
    self:DrawModel()
end

if CLIENT then
    language.Add("city_npc", "City NPC")
end
