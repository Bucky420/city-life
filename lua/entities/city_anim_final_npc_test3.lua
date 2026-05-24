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

	local actName = CL_ACT_NAMES[self:GetNWInt("DebugActID", 0)] or "?"
	local footsAbove = 0
	local totalGap = 0
	local floorSum, floorCount = 0, 0
	local footMinZ, footMaxZ = math.huge, -math.huge
	local dbgParts = {}

	for _, fb in ipairs(FOOT_BONES) do
		local id = self:LookupBone(fb.name)
		if id then
			local fpos = self:GetBonePosition(id)
			if fpos then
				footMinZ = math.min(footMinZ, fpos.z)
				footMaxZ = math.max(footMaxZ, fpos.z)

				local fmat = self:GetBoneMatrix(id)
				local fwdZ, rgtZ, upZ = 0, 0, 0
				local fwd = Vector(0, 0, 0)
				if fmat then
					fwdZ = fmat:GetForward().z
					rgtZ = fmat:GetRight().z
					upZ = fmat:GetUp().z
					fwd = fmat:GetForward()
				end

				local function doTrace(origin)
					local tr = util.TraceLine({
						start = origin + Vector(0, 0, 4),
						endpos = origin - Vector(0, 0, 16),
						filter = self,
						mask = MASK_SOLID
					})
					if tr.Hit then
						if tr.HitNormal and tr.HitNormal.z > 0.7 then
							return math.max(0, origin.z - tr.HitPos.z), tr.HitPos.z
						end
					elseif tr.StartSolid then
						return 0, origin.z
					end
					return nil, nil
				end

				local centerGap, centerFloor = doTrace(fpos)
				local heelGap, heelFloor = doTrace(fpos + fwd * -4)
				local toeGap, toeFloor = doTrace(fpos + fwd * 4)

				local sampleGaps = { heelGap, centerGap, toeGap }
				local gaps = {}
				if centerGap then table.insert(gaps, { gap = centerGap, floor = centerFloor }) end
				if heelGap then table.insert(gaps, { gap = heelGap, floor = heelFloor }) end
				if toeGap then table.insert(gaps, { gap = toeGap, floor = toeFloor }) end
				local gap, bestFloorZ
				if #gaps > 0 then
					table.sort(gaps, function(a, b) return a.gap < b.gap end)
					gap = gaps[1].gap
					bestFloorZ = gaps[1].floor
				else
					gap = 20
				end

			local function fmtG(v) return v and string.format("%.1f", v) or "-" end
			local gapStr = fmtG(sampleGaps[1]) .. "/" .. fmtG(sampleGaps[2]) .. "/" .. fmtG(sampleGaps[3])
				table.insert(dbgParts, string.format("%s:%s f:%.2f r:%.2f u:%.2f",
					fb.label, gapStr, fwdZ, rgtZ, upZ))
				if bestFloorZ then
					table.insert(dbgParts, string.format("fl:%.1f", bestFloorZ))
				end
				self._FootHov = self._FootHov or {}
				local tiltOK = fwdZ > -0.85
				local prevHov = self._FootHov[id]
				local thresh = prevHov and 4 or 5.5
				local isHov = tiltOK and gap > thresh
				if isHov then
					self._FootHov[id] = true
					footsAbove = footsAbove + 1
					totalGap = totalGap + gap
					if bestFloorZ then
						floorSum = floorSum + bestFloorZ
						floorCount = floorCount + 1
					end
				else
					self._FootHov[id] = nil
				end
			end
		end
	end
	self._DbgFootGaps = table.concat(dbgParts, " ")
	local footSpan = footMaxZ - footMinZ
	local bothHovering = footsAbove >= 1 and footSpan < 10

	if CurTime() - (self._DbgNextThink or 0) > 0.5 then
		self._DbgNextThink = CurTime()
		Msg(string.format("[FT] %s ft:%s span:%.1f sv:%.1f sz:%.1f %s\n",
			actName, self._DbgFootGaps, footSpan, svPos.z, self._SmoothZ,
			bothHovering and "HOVER" or ""))
	end

	local legHalf = 16

	if bothHovering then
		self._CorrUntil = CurTime() + 0.5
		local avgGap = totalGap / footsAbove
		local desired = 4
		local excess = avgGap - desired
		if excess > 0 then
			self._SmoothZ = math.max(self._SmoothZ - excess * dt * 15, svPos.z - legHalf)
		end
	elseif self._CorrUntil and CurTime() < self._CorrUntil then
	else
		self._CorrUntil = nil
		local diff = svPos.z - self._SmoothZ
		self._SmoothZ = self._SmoothZ + diff * math.min(dt * 4, 1)
	end

	self:SetPos(Vector(svPos.x, svPos.y, self._SmoothZ))
end

end
