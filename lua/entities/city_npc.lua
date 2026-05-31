AddCSLuaFile()

ENT.Type = "nextbot"
ENT.Base = "city_base_npc"
ENT.PrintName = "City NPC"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Author = "City NPCs"
ENT.Purpose = "Wandering citizen NPCs using nav mesh"
ENT.Instructions = "Spawn and they will walk on sidewalks"

ENT.Config = {
    Model = "models/Humans/Group03/male_01.mdl",
    WalkSpeed = 60,
    RunSpeed = 150,
    Accel = 400,
    Decel = 400,
    StepHeight = 18,
    MaxYawRate = 180,
    Health = 100,
}

-- Inherits all modules from city_base_npc, just override config

if SERVER then

function ENT:OnContact(ent)
    if ent:IsPlayer() then
        self.BlockedBy = ent
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
            CityNPCs.Modules.move.MoveBackwards(self, blockPlayer:GetPos(), 100)
            local startPos = self:GetPos()
            local savedFwd = self:GetForward()
            local tr = util.TraceHull({
                start = startPos,
                endpos = startPos - savedFwd * 500,
                mins = self:OBBMins(),
                maxs = self:OBBMaxs(),
                filter = { self, blockPlayer },
                mask = MASK_SOLID
            })
            local maxDist = math.max(40, math.min(tr.Fraction * 500 - 40, 180))
            CityNPCs.Modules.move.SetSpeed(self, 200)
            while (self:GetPos() - startPos):Length() < maxDist do
                self.loco:FaceTowards(self:GetPos() + savedFwd * 200)
                self.loco:Approach(self:GetPos() - savedFwd * 100, 1)
                coroutine.yield()
            end
            CityNPCs.Modules.move.SetSpeed(self, 60)
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
            CityNPCs.Modules.move.SetSpeed(self, 60)
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

function ENT:OnRemove()
    if CityNPCs and CityNPCs.ActiveNPCs then
        for i, npc in ipairs(CityNPCs.ActiveNPCs) do
            if npc == self then
                table.remove(CityNPCs.ActiveNPCs, i)
                break
            end
        end
    end

    for _, mod in ipairs(self.Modules) do
        if mod.OnRemove then mod.OnRemove(self) end
    end
end

end

if CLIENT then
    language.Add("city_npc", "City NPC")
end
