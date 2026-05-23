AddCSLuaFile()

ENT.Type = "nextbot"
ENT.Base = "base_nextbot"
ENT.PrintName = "Final Anim Test NPC v3"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Author = "City NPCs"
ENT.Purpose = "Final anim test: turning, stairs, IK, motion, backup on touch"
ENT.Instructions = "Press +USE to recruit. Follows commander, backs up when close."

local FOLLOW_STOP_DIST = 75
local FOLLOW_START_DIST = 110
local FOLLOW_RUN_DIST = 450
local FOLLOW_LOST_DIST = 3000
local BACKUP_DIST = 60

if SERVER then

function ENT:Initialize()
	self:SetModel("models/Humans/Group03/male_01.mdl")
	self:SetIK(true)
	self:PhysicsInit(SOLID_BBOX)
	self:SetMoveType(MOVETYPE_STEP)
	self:SetSolid(SOLID_BBOX)
	self:SetCollisionGroup(COLLISION_GROUP_NPC)
	self:SetHealth(100)
	self:SetMaxHealth(100)
	self:SetUseType(SIMPLE_USE)
	self.loco:SetAcceleration(400)
	self.loco:SetDeceleration(400)
	self.loco:SetStepHeight(24)
	self.loco:SetMaxYawRate(360)
	self.Commander = nil
	self.NextTurnTime = 0
	self._PrevCmdDist = 0
end

function ENT:AcceptInput(name, activator, caller, data)
	if SERVER and name == "Use" and IsValid(activator) and activator:IsPlayer() and activator:Alive() then
		self.Commander = self.Commander == activator and nil or activator
		return true
	end
end

function ENT:BodyUpdate()
	if not SERVER then return end
	local vel = self.loco:GetVelocity():Length2D()
	local act = self:GetActivity()
	local newAct

	if vel > 120 then
		newAct = ACT_RUN
	elseif vel < 5 then
		newAct = ACT_IDLE
	else
		newAct = ACT_WALK
	end

	if newAct ~= act then
		local cyc = self:GetCycle()
		self:StartActivity(newAct)
		if (act == ACT_WALK or act == ACT_RUN) and (newAct == ACT_WALK or newAct == ACT_RUN) then
			self:SetCycle(cyc)
		end
	end

	self:BodyMoveXY()

	self:SetNWFloat("DebugServerZ", self:GetPos().z)
	self:SetNWFloat("DebugVel", vel)
	self:SetNWInt("DebugActID", newAct)
	self:SetNWString("DebugSeq", self:GetSequenceName(self:GetSequence()) or "")
	self:SetNWFloat("DebugCycle", self:GetCycle())
	self:SetNWFloat("DebugRate", self:GetPlaybackRate())
end



function ENT:AddTurnGesture(yawDeltaDeg)
	if CurTime() < self.NextTurnTime then return end
	self.NextTurnTime = CurTime() + 0.5

	local absDelta = math.abs(yawDeltaDeg)
	if absDelta < 15 then return end

	local turnAct, turnName
	if yawDeltaDeg < -45 then
		turnAct = ACT_GESTURE_TURN_RIGHT90
		turnName = "R90"
	elseif yawDeltaDeg < 0 then
		turnAct = ACT_GESTURE_TURN_RIGHT45
		turnName = "R45"
	elseif yawDeltaDeg <= 45 then
		turnAct = ACT_GESTURE_TURN_LEFT45
		turnName = "L45"
	else
		turnAct = ACT_GESTURE_TURN_LEFT90
		turnName = "L90"
	end

	local seqIdx = self:SelectWeightedSequence(turnAct)
	if seqIdx and seqIdx >= 0 then
		local layerId = self:AddGestureSequence(seqIdx, true)
		if layerId and layerId >= 0 then
			self:SetLayerPriority(layerId, 100)
		end
	end

	self:SetNWString("DebugTurn", turnName)
end

function ENT:RunBehaviour()
	while self:IsValid() and self:Health() > 0 do
		if self.Commander and IsValid(self.Commander) and self.Commander:Alive() then
			local cmdPos = self.Commander:GetPos()
			local dist = self:GetPos():Distance(cmdPos)

			self:SetNWString("DebugCmdName", self.Commander:Nick())
			self:SetNWFloat("DebugCmdDist", dist)

			if dist > FOLLOW_LOST_DIST then
				self.Commander = nil
				self:SetNWString("DebugStatus", "LOST")
				coroutine.wait(1)
				continue
			end

			if dist > FOLLOW_STOP_DIST then
				local speed = dist > FOLLOW_RUN_DIST and 300 or (dist > FOLLOW_START_DIST and 100 or 60)
				self.loco:SetDesiredSpeed(speed)

				while self.Commander and IsValid(self.Commander) and self.Commander:Alive() do
					cmdPos = self.Commander:GetPos()
					dist = self:GetPos():Distance(cmdPos)

					if dist > FOLLOW_LOST_DIST then self.Commander = nil; break end
					if dist <= FOLLOW_STOP_DIST then break end

					self:SetNWString("DebugStatus", speed > 100 and "RUNNING" or "FOLLOWING")
					self:SetNWFloat("DebugCmdDist", dist)

					self.loco:FaceTowards(cmdPos)
					self.loco:Approach(cmdPos, 1)

					local yawDelta = (math.deg(math.atan2(cmdPos.y - self:GetPos().y, cmdPos.x - self:GetPos().x)) - self:GetAngles().y) % 360
					if yawDelta > 180 then yawDelta = yawDelta - 360 end
					self:SetNWFloat("DebugYawDelta", yawDelta)
					self:AddTurnGesture(yawDelta)

					coroutine.yield()
				end
			else
				local prevDist = self._PrevCmdDist
				self._PrevCmdDist = dist

				if dist < BACKUP_DIST and dist < prevDist and prevDist > 0 then
					self:SetNWString("DebugStatus", "BACKING")
					self.loco:SetDesiredSpeed(40)
					self.loco:FaceTowards(cmdPos)
					self.loco:Approach(self:GetPos() - self:GetForward() * 80, 1)
				else
					self:SetNWString("DebugStatus", "IDLE")
					self.loco:SetDesiredSpeed(1)
					coroutine.wait(0.5)
				end
				coroutine.yield()
			end
		else
			self.Commander = nil
			self:SetNWString("DebugStatus", "IDLE")
			self:SetNWString("DebugCmdName", "")
			self:SetNWFloat("DebugCmdDist", 0)
			coroutine.wait(1)
		end
	end
end

end -- SERVER

if CLIENT then

surface.CreateFont("CityNPCDbgFinal", {
	font = "Consolas",
	size = 13,
	weight = 600,
})

local CL_ACT_NAMES = {
	[ACT_IDLE] = "ACT_IDLE",
	[ACT_WALK] = "ACT_WALK",
	[ACT_RUN] = "ACT_RUN",
	[ACT_TURN_LEFT] = "ACT_TURN_LEFT",
	[ACT_TURN_RIGHT] = "ACT_TURN_RIGHT",
}

local FOOT_BONES = {
	{ name = "ValveBiped.Bip01_L_Foot", label = "L" },
	{ name = "ValveBiped.Bip01_R_Foot", label = "R" },
}

function ENT:Think()
	local dt = FrameTime() or 0.0167
	local svPos = self:GetPos()
	self._SmoothZ = self._SmoothZ or svPos.z

	self:SetPos(Vector(svPos.x, svPos.y, self._SmoothZ))
	self:SetupBones()

	local footBones = {
		{ name = "ValveBiped.Bip01_L_Foot", tag = "L" },
		{ name = "ValveBiped.Bip01_R_Foot", tag = "R" },
	}

	local footsAbove = 0
	local totalGap = 0
	local dbgParts = {}

	for _, fb in ipairs(footBones) do
		local id = self:LookupBone(fb.name)
		if id then
			local fpos = self:GetBonePosition(id)
			if fpos then
				local traceStart = Vector(fpos.x, fpos.y, fpos.z + 4)
				local tr = util.TraceLine({
					start = traceStart,
					endpos = fpos - Vector(0, 0, 16),
					filter = self,
					mask = MASK_NPCSOLID
				})
				local gap
				if tr.Hit then
					gap = math.max(0, fpos.z - tr.HitPos.z)
				elseif tr.StartSolid then
					gap = 0
				else
					gap = 20
				end
				table.insert(dbgParts, string.format("%s:%.1f", fb.tag, gap))
				if gap > 2 then
					footsAbove = footsAbove + 1
					totalGap = totalGap + gap
				end
			end
		end
	end
	self._DbgFootGaps = table.concat(dbgParts, " ")

	local vel = self:GetNWFloat("DebugVel", 0)

	if vel < 5 and footsAbove >= 1 then
		local avgGap = totalGap / footsAbove
		local excess = avgGap - 3
		if excess > 0 then
			self._SmoothZ = self._SmoothZ - excess * dt * 12
		end
		self._Corrected = true
	elseif vel >= 5 then
		self._Corrected = false
		local diff = svPos.z - self._SmoothZ
		self._SmoothZ = self._SmoothZ + diff * math.min(dt * 8, 1)
	end

	self:SetPos(Vector(svPos.x, svPos.y, self._SmoothZ))
end

hook.Add("HUDPaint", "CityNPCFinalDebug", function()
	for _, ent in ipairs(ents.FindByClass("city_anim_final_npc_test3")) do
		local origin = ent:GetPos() + Vector(0, 0, 96)
		local screen = origin:ToScreen()
		if not screen.visible then continue end

		local actID = ent:GetNWInt("DebugActID", ACT_IDLE)
		local actName = CL_ACT_NAMES[actID] or tostring(actID)
		local seqName = ent:GetNWString("DebugSeq", "?")
		local cycle = ent:GetNWFloat("DebugCycle", 0)
		local rate = ent:GetNWFloat("DebugRate", 1)

		local status = ent:GetNWString("DebugStatus", "?")
		local vel = ent:GetNWFloat("DebugVel", 0)
		local yawDelta = ent:GetNWFloat("DebugYawDelta", 0)
		local turnVal = ent:GetNWString("DebugTurn", "-")
		local cmdName = ent:GetNWString("DebugCmdName", "")
		local cmdDist = ent:GetNWFloat("DebugCmdDist", 0)

		local moveX = ent:GetPoseParameter("move_x") or 0
		local moveY = ent:GetPoseParameter("move_y") or 0
		local moveScale = ent:GetPoseParameter("move_scale") or 0

		ent:SetupBones()
		local footStr = ""
		for _, fb in ipairs(FOOT_BONES) do
			local id = ent:LookupBone(fb.name)
			if id then
				local pos = ent:GetBonePosition(id)
				if pos then
					local lp = ent:WorldToLocal(pos)
					footStr = footStr .. string.format(" %s:%.0f %.0f %.0f", fb.label, lp.x, lp.y, lp.z)
				end
			end
		end

		local pos = ent:GetPos()
		local posStr = string.format("%.0f %.0f %.0f", pos.x, pos.y, pos.z)

		surface.SetFont("CityNPCDbgFinal")
		surface.SetTextColor(Color(255, 255, 100, 255))

		local line1 = string.format("[%s] spd:%.1f yawΔ:%+.0f %s seq:%s cyc:%.2f rt:%.1f", actName, vel, yawDelta, turnVal, seqName, cycle, rate)
		local w1 = surface.GetTextSize(line1)
		surface.SetTextPos(screen.x - w1 / 2, screen.y - 60)
		surface.DrawText(line1)

		local cmdPart = cmdName ~= "" and string.format(" cmd:%s dist:%.0f", cmdName, cmdDist) or ""
		local line2 = string.format("pos:%s  [%s]%s", posStr, status, cmdPart)
		local w2 = surface.GetTextSize(line2)
		surface.SetTextPos(screen.x - w2 / 2, screen.y - 44)
		surface.DrawText(line2)

		local smoothZ = ent._SmoothZ or 0
		local zLine = string.format("ft:%s sz:%.1f sv:%.1f", ent._DbgFootGaps or "?", smoothZ, pos.z)
		local line3 = string.format("mx:%.2f my:%.2f ms:%.2f%s", moveX, moveY, moveScale, footStr)
		local w3 = surface.GetTextSize(line3)
		local wz = surface.GetTextSize(zLine)
		surface.SetTextPos(screen.x - math.max(w3, wz) / 2, screen.y - 28)
		surface.DrawText(zLine)
		surface.SetTextPos(screen.x - w3 / 2, screen.y - 12)
		surface.DrawText(line3)
	end
end)

function ENT:Draw()
	self:DrawModel()
end

end
