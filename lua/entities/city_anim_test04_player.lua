AddCSLuaFile()

ENT.Type = "nextbot"
ENT.Base = "base_nextbot"
ENT.PrintName = "Test v4 (player Anim)"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Author = "City NPCs"
ENT.Purpose = "Player model test: idle/walk/run with IK transitions"
ENT.Instructions = "Press +USE to call. Tests player model animation transitions."

local STOP_DIST = 100
local WALK_DIST = 350
local LOST_DIST = 3000
local WALK_SPEED = 100
local RUN_SPEED = 300

if SERVER then

function ENT:Initialize()
	self:SetModel("models/player/group01/male_01.mdl")
	self:SetIK(true)
	self:PhysicsInit(SOLID_BBOX)
	self:SetMoveType(MOVETYPE_STEP)
	self:SetSolid(SOLID_BBOX)
	self:SetCollisionGroup(COLLISION_GROUP_PLAYER)
	self:SetHealth(100)
	self:SetMaxHealth(100)
	self:SetUseType(SIMPLE_USE)
	self.loco:SetAcceleration(500)
	self.loco:SetDeceleration(500)
	self.loco:SetStepHeight(18)
	self.loco:SetMaxYawRate(360)
	self.Target = nil
	self._CurAct = nil
end

function ENT:AcceptInput(name, activator, caller, data)
	if SERVER and name == "Use" and IsValid(activator) and activator:IsPlayer() and activator:Alive() then
		self.Target = self.Target == activator and nil or activator
		return true
	end
end

function ENT:BodyUpdate()
	if not SERVER then return end
	local vel = self.loco:GetVelocity():Length2D()

	local act
	if vel > 200 then
		act = ACT_HL2MP_RUN
	elseif vel < 15 then
		act = ACT_HL2MP_IDLE
	else
		act = ACT_HL2MP_WALK
	end

	if act ~= self._CurAct then
		local cyc = self:GetCycle()
		self:StartActivity(act)
		if (self._CurAct == ACT_HL2MP_WALK or self._CurAct == ACT_HL2MP_RUN) and (act == ACT_HL2MP_WALK or act == ACT_HL2MP_RUN) then
			self:SetCycle(cyc)
		end
		self._CurAct = act
	end

	self:SetPoseParameter("move_x", math.Clamp(vel / 300, 0, 1))

	if self.Target and IsValid(self.Target) then
		local aimAng = (self.Target:GetPos() - self:GetPos()):Angle()
		local yawDiff = math.AngleDifference(aimAng.y, self:GetAngles().y)
		local pitchDiff = math.AngleDifference(aimAng.p, 0)
		self:SetPoseParameter("aim_yaw", yawDiff)
		self:SetPoseParameter("aim_pitch", pitchDiff)
	end

	self:SetNWString("DebugAct", act == ACT_HL2MP_IDLE and "IDLE" or act == ACT_HL2MP_WALK and "WALK" or "RUN")
	self:SetNWFloat("DebugVel", vel)

	self:BodyMoveXY()
end

function ENT:RunBehaviour()
	while self:IsValid() and self:Health() > 0 do
		if self.Target and IsValid(self.Target) and self.Target:Alive() then
			local tPos = self.Target:GetPos()
			local dist = self:GetPos():Distance(tPos)

			if dist > LOST_DIST then
				self.Target = nil
				coroutine.wait(1)
				continue
			end

			if dist > STOP_DIST then
				local speed = dist > WALK_DIST and RUN_SPEED or WALK_SPEED
				self.loco:SetDesiredSpeed(speed)

				while self.Target and IsValid(self.Target) and self.Target:Alive() do
					tPos = self.Target:GetPos()
					dist = self:GetPos():Distance(tPos)
					if dist > LOST_DIST then self.Target = nil; break end
					if dist <= STOP_DIST then break end
					self.loco:FaceTowards(tPos)
					self.loco:Approach(tPos, 1)
					coroutine.yield()
				end
			end

			self.loco:SetDesiredSpeed(1)
			coroutine.wait(1)
		else
			self.Target = nil
			coroutine.wait(1)
		end
	end
end

end

if CLIENT then

function ENT:Draw()
	self:DrawModel()
end

surface.CreateFont("CityNPCDbgV4", {
	font = "Consolas",
	size = 13,
	weight = 600,
})

hook.Add("HUDPaint", "CityNPCV4Debug", function()
	for _, ent in ipairs(ents.FindByClass("city_anim_test04_player")) do
		local origin = ent:GetPos() + Vector(0, 0, 96)
		local screen = origin:ToScreen()
		if not screen.visible then continue end

		local actName = ent:GetNWString("DebugAct", "?")
		local vel = ent:GetNWFloat("DebugVel", 0)
		local cycle = ent:GetCycle()
		local rate = ent:GetPlaybackRate()
		local seqName = ent:GetSequenceName(ent:GetSequence())
		local mx = ent:GetPoseParameter("move_x") or 0
		local ay = ent:GetPoseParameter("aim_yaw") or 0
		local ap = ent:GetPoseParameter("aim_pitch") or 0

		surface.SetFont("CityNPCDbgV4")
		surface.SetTextColor(Color(100, 255, 255, 255))

		local l1 = string.format("act:%s seq:%s spd:%.1f cyc:%.2f", actName, seqName, vel, cycle)
		local w1 = surface.GetTextSize(l1)
		surface.SetTextPos(screen.x - w1 / 2, screen.y - 50)
		surface.DrawText(l1)

		local l2 = string.format("mx:%.2f ay:%.1f ap:%.1f", mx, ay, ap)
		local w2 = surface.GetTextSize(l2)
		surface.SetTextPos(screen.x - w2 / 2, screen.y - 34)
		surface.DrawText(l2)
	end
end)

end
