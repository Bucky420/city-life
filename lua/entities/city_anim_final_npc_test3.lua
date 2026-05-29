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
local FOLLOW_START_DIST = 110
local FOLLOW_RUN_DIST = 450
local FOLLOW_LOST_DIST  = 30000

local FOLLOW_SPEED_WALK = 85
local FOLLOW_SPEED_RUN = 150
local FOLLOW_SPEED_IDLE = 60

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

	self.loco:SetDesiredSpeed(60)
	self.loco:SetAcceleration(300)
	self.loco:SetDeceleration(300)
	self.loco:SetStepHeight(18)
	self.loco:SetMaxYawRate(180)

	self:StartActivity(ACT_IDLE)

	self.Commander = nil
	self.NextTurnTime = 0
	self._DesiredSpeed = 0
end

function ENT:BodyUpdate()
	local act = self:GetActivity()
	local speed = self.loco:GetVelocity():Length2D()
	local wantMove = speed > 5

	local newAct = wantMove and ACT_WALK or ACT_IDLE

	if newAct ~= act and newAct then
		local cycle
		if act == ACT_IDLE and newAct == ACT_WALK then
			cycle = self:GetCycle()
		end
		self:StartActivity(newAct)
		if cycle then
			self:SetCycle(cycle)
		end
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
				self._DesiredSpeed = 1

				local toTarget = (cmdPos - self:GetPos()):GetNormalized()
				self.loco:FaceTowards(cmdPos)
				local faceStart = CurTime()
				while self:GetForward():Dot(toTarget) < 0.95 and CurTime() - faceStart < 2 do
					toTarget = (cmdPos - self:GetPos()):GetNormalized()
					self.loco:FaceTowards(cmdPos) 
					coroutine.yield()
				end

				if not self._LastMovePrint or CurTime() - self._LastMovePrint > 5 then
					self._LastMovePrint = CurTime()
					print(self:GetClass() .. " [" .. self:EntIndex() .. "] moving to " .. self.Commander:Nick())
				end
				self._DesiredSpeed = (dist > FOLLOW_RUN_DIST and FOLLOW_SPEED_RUN) or
					(dist > FOLLOW_START_DIST and FOLLOW_SPEED_WALK) or
					FOLLOW_SPEED_IDLE
				self.loco:SetDesiredSpeed(self._DesiredSpeed)

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
				self._DesiredSpeed = 0
				coroutine.wait(1)
			end
		else
			self._DesiredSpeed = 0
			self.Commander = nil
			coroutine.wait(1)
		end
	end
end

end

if CLIENT then

function ENT:FireAnimationEvent(pos, ang, event, name)
end

function ENT:Draw()
	local pos = self:GetPos()
	-- Step 1: Enable IK on client (server SetIK doesn't propagate to nextbot client entity)
	self:SetIK(true)

	-- SetupBones at ORIGINAL position to get true animated bone positions
	self:SetupBones()

	local lFootBone = self:LookupBone("ValveBiped.Bip01_L_Foot")
	local rFootBone = self:LookupBone("ValveBiped.Bip01_R_Foot")

	-- Get actual bone world positions using matrix (wiki: GetBonePosition can be stale)
	local lFootWorld = nil
	local rFootWorld = nil

	if lFootBone and lFootBone >= 0 then
		local mat = self:GetBoneMatrix(lFootBone)
		if mat then lFootWorld = mat:GetTranslation() end
	end
	if rFootBone and rFootBone >= 0 then
		local mat = self:GetBoneMatrix(rFootBone)
		if mat then rFootWorld = mat:GetTranslation() end
	end

	-- Step 2: Trace from each foot world position, track min AND max ground Z
	local r = 2.5

	local TRACE_DIST = 48
	local minGroundZ = nil
	local maxGroundZ = nil

	-- Offset trace origin forward from ankle to foot center (~4 units)
	local fwd = self:GetForward()
	local footForward = Vector(fwd.x, fwd.y, 0):GetNormalized() * 4

	if lFootWorld then
		local lStart = lFootWorld + footForward
		local lEnd = lStart - Vector(0, 0, TRACE_DIST)
		local lTr = util.TraceHull({
			start = lStart,
			endpos = lEnd,
			mins = Vector(-r, -r, 0),
			maxs = Vector(r, r, 1),
			filter = self,
			mask = MASK_NPCSOLID_BRUSHONLY
		})
		if lTr.Hit then
			minGroundZ = lTr.HitPos.z
			maxGroundZ = lTr.HitPos.z
		end
		if CityNPCs and CityNPCs.DbgEnts and CityNPCs.DbgEnts[self:EntIndex()] then
			local col = lTr.Hit and Color(0, 255, 0) or Color(255, 0, 0)
			local endPos = lTr.Hit and lTr.HitPos or lEnd
			debugoverlay.Cross(lStart, r, 0.01, col, true)
			debugoverlay.Cross(endPos, r, 0.01, col, true)
			debugoverlay.Line(lStart, endPos, 0.01, col, true)
		end
	end

	if rFootWorld then
		local rStart = rFootWorld + footForward
		local rEnd = rStart - Vector(0, 0, TRACE_DIST)
		local rTr = util.TraceHull({
			start = rStart,
			endpos = rEnd,
			mins = Vector(-r, -r, 0),
			maxs = Vector(r, r, 1),
			filter = self,
			mask = MASK_NPCSOLID_BRUSHONLY
		})
		if rTr.Hit then
			if minGroundZ then
				minGroundZ = math.min(minGroundZ, rTr.HitPos.z)
			else
				minGroundZ = rTr.HitPos.z
			end
			if maxGroundZ then
				maxGroundZ = math.max(maxGroundZ, rTr.HitPos.z)
			else
				maxGroundZ = rTr.HitPos.z
			end
		end
		if CityNPCs and CityNPCs.DbgEnts and CityNPCs.DbgEnts[self:EntIndex()] then
			local col = rTr.Hit and Color(0, 255, 0) or Color(255, 0, 0)
			local endPos = rTr.Hit and rTr.HitPos or rEnd
			debugoverlay.Cross(rStart, r, 0.01, col, true)
			debugoverlay.Cross(endPos, r, 0.01, col, true)
			debugoverlay.Line(rStart, endPos, 0.01, col, true)
		end
	end

	if minGroundZ and maxGroundZ then
		self._StepOrigin = self._StepOrigin or pos.z

		local stepHeight = 18

		self._StepOrigin = self._StepOrigin * 0.95 + minGroundZ * 0.05

		local bias = math.Clamp((maxGroundZ - minGroundZ) - stepHeight, 0, stepHeight)

		self._DbgBlendOff = math.Clamp(self._StepOrigin - pos.z, -stepHeight + bias, 0)
		self._IkOffset = self._DbgBlendOff

		self._DbgMinZ = minGroundZ
		self._DbgMaxZ = maxGroundZ
	else
		self._DbgBlendOff = 0
		self._DbgMinZ = pos.z
		self._DbgMaxZ = pos.z
		self._StepOrigin = pos.z
		self._IkOffset = (self._IkOffset or 0) * 0.5
	end

	-- Step 4: Apply offset and draw
	self:SetPos(Vector(pos.x, pos.y, pos.z + (self._IkOffset or 0)))
	self:SetupBones()
	self:DrawModel()
	self:SetPos(pos)
end

end
