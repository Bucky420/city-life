AddCSLuaFile()

ENT.Type = "nextbot"
ENT.Base = "base_nextbot"

ENT.PrintName = "Final Anim Test NPC v3"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Author = "City NPCs"

ENT.Purpose = "Minimal follow NPC with SetIK(true)"
ENT.Instructions = "Press +USE to recruit. Follows commander."

local FOLLOW_STOP_DIST = 75
local FOLLOW_RUN_DIST = 450
local FOLLOW_LOST_DIST = 30000

local FOLLOW_SPEED_WALK = 75
local FOLLOW_SPEED_RUN = 150

local TURN_GESTURE_COOLDOWN = 0.5
local TURN_GESTURE_MIN_DELTA = 15

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

	self.loco:SetDesiredSpeed(150)
	self.loco:SetAcceleration(200)
	self.loco:SetDeceleration(200)
	self.loco:SetStepHeight(18)
	self.loco:SetMaxYawRate(180)

	self:StartActivity(ACT_IDLE)

	self.Commander = nil
	self.NextTurnTime = 0
end

function ENT:BodyUpdate()
	local act = self:GetActivity()
	local speed = self.loco:GetVelocity():Length2D()
	local wantMove = speed > 20

	local newAct = wantMove and ACT_WALK or ACT_IDLE

	if newAct ~= act and newAct then
		self:StartActivity(newAct)
	end

	self:BodyMoveXY()
end

function ENT:AcceptInput(name, activator)
	if name ~= "Use" then return end
	if not IsValid(activator) or not activator:IsPlayer() or not activator:Alive() then return end

	self.Commander = (self.Commander == activator) and nil or activator
	return true
end

function ENT:AddTurnGesture(yawDeltaDeg)
	if CurTime() < self.NextTurnTime then return end
	self.NextTurnTime = CurTime() + TURN_GESTURE_COOLDOWN

	local absDelta = math.abs(yawDeltaDeg)
	if absDelta < TURN_GESTURE_MIN_DELTA then return end

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
			self:SetLayerPriority(layerId, 100)
		end
	end
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

				if not self._LastMovePrint or CurTime() - self._LastMovePrint > 5 then
					self._LastMovePrint = CurTime()
					print(self:GetClass() .. " [" .. self:EntIndex() .. "] moving to " .. self.Commander:Nick())
				end
				self.loco:SetDesiredSpeed(FOLLOW_SPEED_WALK)

				local stuckPos = self:GetPos()
				local stuckTime = 0

				while self.Commander and IsValid(self.Commander) and self.Commander:Alive() do
					cmdPos = self.Commander:GetPos()
					dist = self:GetPos():Distance(cmdPos)

					if dist > FOLLOW_LOST_DIST then
						break
					end
					if dist <= FOLLOW_STOP_DIST then
						break
					end

					self.loco:SetDesiredSpeed((dist > FOLLOW_RUN_DIST and FOLLOW_SPEED_RUN) or
						FOLLOW_SPEED_WALK)

					if self:GetPos():Distance(stuckPos) < 8 then
						stuckTime = stuckTime + FrameTime()
					else
						stuckPos = self:GetPos()
						stuckTime = 0
					end

					if stuckTime > 2 then
						print(self:GetClass() .. " [" .. self:EntIndex() .. "] is stuck, retrying...")
						break
					end

					self.loco:FaceTowards(cmdPos)
					self.loco:Approach(cmdPos, 1)

					local yawDelta = (math.deg(math.atan2(cmdPos.y - self:GetPos().y, cmdPos.x - self:GetPos().x)) - self:GetAngles().y) % 360
					if yawDelta > 180 then yawDelta = yawDelta - 360 end
					self:AddTurnGesture(yawDelta)

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

if CLIENT then

function ENT:Draw()
	self:SetIK(true)
	self:SetupBones()

	local lFootBone = self:LookupBone("ValveBiped.Bip01_L_Foot")
	local rFootBone = self:LookupBone("ValveBiped.Bip01_R_Foot")

	local TRACE_DIST = 72
	local HULL_R = 2.5
	local groundZ = nil
	local traceLen = 0
	local fwd = self:GetForward()
	local footFwd = Vector(fwd.x, fwd.y, 0):GetNormalized() * 4

	if lFootBone then
		local mat = self:GetBoneMatrix(lFootBone)
		if mat then
			local footPos = mat:GetTranslation()
			local start = footPos + footFwd
			local tr = util.TraceHull({
				start = start,
				endpos = start - Vector(0, 0, TRACE_DIST),
				mins = Vector(-HULL_R, -HULL_R, 0),
				maxs = Vector(HULL_R, HULL_R, 1),
				filter = self,
				mask = MASK_SOLID
			})
			if tr.Hit then
				groundZ = tr.HitPos.z
				traceLen = start.z - tr.HitPos.z
			end
		end
	end

	if rFootBone then
		local mat = self:GetBoneMatrix(rFootBone)
		if mat then
			local footPos = mat:GetTranslation()
			local start = footPos + footFwd
			local tr = util.TraceHull({
				start = start,
				endpos = start - Vector(0, 0, TRACE_DIST),
				mins = Vector(-HULL_R, -HULL_R, 0),
				maxs = Vector(HULL_R, HULL_R, 1),
				filter = self,
				mask = MASK_SOLID
			})
			if tr.Hit then
				if groundZ then
					groundZ = math.min(groundZ, tr.HitPos.z)
				else
					groundZ = tr.HitPos.z
				end
				traceLen = math.max(traceLen, start.z - tr.HitPos.z)
			end
		end
	end

	if groundZ then
		local pos = self:GetPos()

		self._VisualZ = Lerp(0.07, self._VisualZ or groundZ, groundZ)
		self:SetPos(Vector(pos.x, pos.y, self._VisualZ))
		self:SetupBones()
		self:DrawModel()
		self:SetPos(pos)
	else
		self:DrawModel()
	end
end

end
