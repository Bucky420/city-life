AddCSLuaFile()

ENT.Type = "nextbot"
ENT.Base = "base_nextbot"

ENT.PrintName = "City Base NPC"
ENT.Spawnable = false
ENT.AdminOnly = false
ENT.Author = "City NPCs"
ENT.Purpose = "Base entity with modular systems - do not spawn directly"
ENT.Instructions = "Inherit from this entity and override RunBehaviour"

-- Default config - override in derived entities
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

-- Default modules as string names (resolved at runtime to avoid circular loading)
-- z must be last since it modifies position in Draw
ENT.ModuleNames = { "move", "turn", "life", "z" } 

-- Lazy module resolution (runs on both SERVER and CLIENT)
function ENT:ResolveModules()
    if self.Modules then return end
    self.Modules = {}
    if self.ModuleNames then
        for _, name in ipairs(self.ModuleNames) do
            local mod = CityNPCs.Modules[name]
            if mod then
                table.insert(self.Modules, mod)
            end
        end
    end
end

if SERVER then

function ENT:Initialize()
    local cfg = self.Config

    self:ResolveModules()

    self:SetModel(cfg.Model)
    self:SetIK(true)

    self:PhysicsInit(SOLID_BBOX) 
    self:SetMoveType(MOVETYPE_STEP)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionGroup(COLLISION_GROUP_NPC)
    self:SetHealth(cfg.Health)
    self:SetMaxHealth(cfg.Health)
    self:SetUseType(SIMPLE_USE)

    self.loco:SetDesiredSpeed(cfg.WalkSpeed)
    self.loco:SetAcceleration(cfg.Accel)
    self.loco:SetDeceleration(cfg.Decel)
    self.loco:SetStepHeight(cfg.StepHeight)
    self.loco:SetMaxYawRate(cfg.MaxYawRate)

    self:StartActivity(ACT_IDLE)

    -- Run module Init hooks
    for _, mod in ipairs(self.Modules) do
        if mod.Init then mod.Init(self) end
    end
end

function ENT:BodyUpdate()
    for _, mod in ipairs(self.Modules) do
        if mod.BodyUpdate then mod.BodyUpdate(self) end
    end
end

function ENT:OnRemove()
    self:ResolveModules()
    for _, mod in ipairs(self.Modules) do
        if mod.OnRemove then mod.OnRemove(self) end
    end
end

function ENT:AcceptInput(name, activator)
    if name ~= "Use" then return end
    if not IsValid(activator) or not activator:IsPlayer() or not activator:Alive() then return end
    self.Commander = (self.Commander == activator) and nil or activator
    return true
end

end

if CLIENT then

function ENT:Draw()
    self:ResolveModules()
    local didDraw = false
    for _, mod in ipairs(self.Modules) do
        if mod.Draw then
            mod.Draw(self)
            didDraw = true
        end
    end
    if not didDraw then
        self:DrawModel()
    end
end

function ENT:Think()
    self:ResolveModules()
    for _, mod in ipairs(self.Modules) do
        if mod.Think then mod.Think(self) end
    end
end

end
