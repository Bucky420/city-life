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

	self.loco:SetDesiredSpeed(100)
	self.loco:SetAcceleration(150)
	self.loco:SetDeceleration(200)
	self.loco:SetStepHeight(32)
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

	-- SDK-style speed scaling on stairs: slow animation when feet are at different heights
	-- Matches BuildVelocityScript's m_flPredictiveSpeedAdjust
	local groundDiff = math.abs((self._SmoothMaxZ or 0) - (self._SmoothMinZ or 0))
	local stairScale = 1.0
	if groundDiff > 1 then
		-- SDK: up stairs min 0.5, down stairs min 0.8
		stairScale = math.Clamp(1.1 - groundDiff / 16, 0.5, 1.0)
	end

	self:BodyMoveXY()

	-- Apply AFTER BodyMoveXY so it doesn't get overridden
	self:SetPlaybackRate(stairScale)
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

function ENT:PrintAnimEvents()
	if self._EventsPrinted then return end
	self._EventsPrinted = true

	local mdl = self:GetModel()
	local info = util.GetModelInfo(mdl)
	if not info or not info.Sequences then return end

	self._PlantCycles = {}

	print("=== Animation Events for " .. mdl .. " ===")

	for _, seq in ipairs(info.Sequences) do
		if seq.Events and #seq.Events > 0 then
			print(string.format("  Seq: %s (act: %s)", seq.Name, seq.Activity or "?"))
			for _, ev in ipairs(seq.Events) do
				print(string.format("    Cycle: %.4f  Event: %d  Name: %s  Type: %d",
					ev.Cycle, ev.Event, ev.Name or "?", ev.Type or 0))
				if seq.Name == "walk_all" and (ev.Event == 6006 or ev.Event == 6007) then
					self._PlantCycles[#self._PlantCycles + 1] = ev.Cycle
				end
			end
		end
	end

	print("=== End Animation Events ===")
end

function ENT:Draw()
	self:PrintAnimEvents()
	local pos = self:GetPos()

	-- Smooth the entity Z to prevent instant snaps from locomotion step-up
	self._SmoothPosZ = self._SmoothPosZ or pos.z
	self._SmoothPosZ = Lerp(0.05, self._SmoothPosZ, pos.z)
	local smoothPos = Vector(pos.x, pos.y, self._SmoothPosZ)

	-- Step 1: Enable IK on client (server SetIK doesn't propagate to nextbot client entity)
	self:SetIK(true)

	-- SetupBones at ORIGINAL position to get true animated bone positions
	self:SetupBones()

	local lFootBone = self:LookupBone("ValveBiped.Bip01_L_Foot")
	local rFootBone = self:LookupBone("ValveBiped.Bip01_R_Foot")

	-- Get actual bone world positions using matrix (wiki: GetBonePosition can be stale)
	local lFootRaw = nil
	local rFootRaw = nil

	if lFootBone and lFootBone >= 0 then
		local mat = self:GetBoneMatrix(lFootBone)
		if mat then lFootRaw = mat:GetTranslation() end
	end
	if rFootBone and rFootBone >= 0 then
		local mat = self:GetBoneMatrix(rFootBone)
		if mat then rFootRaw = mat:GetTranslation() end
	end

	-- Smooth foot bone positions so IK targets change gradually
	local lFootWorld = nil
	local rFootWorld = nil
	if lFootRaw then
		self._SmoothLFoot = self._SmoothLFoot or lFootRaw
		self._SmoothLFoot = Lerp(0.15, self._SmoothLFoot, lFootRaw)
		lFootWorld = self._SmoothLFoot
	end
	if rFootRaw then
		self._SmoothRFoot = self._SmoothRFoot or rFootRaw
		self._SmoothRFoot = Lerp(0.15, self._SmoothRFoot, rFootRaw)
		rFootWorld = self._SmoothRFoot
	end

	-- Step 2: Trace from each foot world position, track min AND max ground Z
	local r = 2.5

	local TRACE_DIST = 72
	local minGroundZ = nil
	local maxGroundZ = nil

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
			mask = MASK_SOLID
		})
		if lTr.Hit then
			minGroundZ = lTr.HitPos.z
			maxGroundZ = lTr.HitPos.z
			self._LeftFootDist = lStart.z - lTr.HitPos.z
			self._LeftFootHitZ = lTr.HitPos.z
		else
			self._LeftFootDist = 99
			self._LeftFootHitZ = nil
		end
		if CityNPCs and CityNPCs.DbgEnts and CityNPCs.DbgEnts[self:EntIndex()] then
			local isActive = math.abs(self._FootPush or 0) > 0.5 and self._DominantFoot == "left"
			local col = isActive and Color(255, 128, 0) or Color(0, 255, 0)
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
			mask = MASK_SOLID
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
			self._RightFootDist = rStart.z - rTr.HitPos.z
			self._RightFootHitZ = rTr.HitPos.z
		else
			self._RightFootDist = 99
			self._RightFootHitZ = nil
		end
		if CityNPCs and CityNPCs.DbgEnts and CityNPCs.DbgEnts[self:EntIndex()] then
			local isActive = math.abs(self._FootPush or 0) > 0.5 and self._DominantFoot == "right"
			local col = isActive and Color(255, 128, 0) or Color(0, 255, 0)
			local endPos = rTr.Hit and rTr.HitPos or rEnd
			debugoverlay.Cross(rStart, r, 0.01, col, true)
			debugoverlay.Cross(endPos, r, 0.01, col, true)
			debugoverlay.Line(rStart, endPos, 0.01, col, true)
		end
	end

	if minGroundZ and maxGroundZ then
		self._StepOrigin = self._StepOrigin or smoothPos.z

		local stepHeight = 18

		-- Clamp ground to entity level - floor can never be above the entity
		minGroundZ = math.min(minGroundZ, smoothPos.z)
		maxGroundZ = math.min(maxGroundZ, smoothPos.z)

		-- Smooth the raw trace Z before feeding to filter
		self._SmoothMinZ = Lerp(0.15, self._SmoothMinZ or minGroundZ, minGroundZ)
		self._SmoothMaxZ = Lerp(0.15, self._SmoothMaxZ or maxGroundZ, maxGroundZ)

		-- SDK formula: floor tracks min ground with 0.2/0.8 filter
		self._StepOrigin = self._StepOrigin * 0.2 + self._SmoothMinZ * 0.8

		local bias = math.Clamp((self._SmoothMaxZ - self._SmoothMinZ) - stepHeight, 0, stepHeight)

		self._DbgBlendOff = math.Clamp(self._StepOrigin - smoothPos.z, -stepHeight + bias, 0)

		-- Foot push: raises root motion Z when foot plants on higher ground
		-- Push target = how much higher the planted foot ground is vs current root
		local PUSH_STRENGTH = 0.5  -- tune: fraction of height difference to push
		local targetPush = 0
		local dominantFoot = nil
		if self._DbgBlendOff < -1 and self:GetSequenceName(self:GetSequence()) == "walk_all" then
			local plantCycles = self._PlantCycles
			if plantCycles and #plantCycles > 0 then
				local cycle = self:GetCycle()
				local past = 1
				local pastIdx = 1
				for i = 1, #plantCycles do
					local dt = (cycle - plantCycles[i]) % 1
					if dt < past then past = dt; pastIdx = i end
				end

				-- Lock dominant foot at engage, hold through push window
				if past < 0.12 then
					local footName = (pastIdx % 2 == 1) and "left" or "right"
					local footDist = footName == "left" and (self._LeftFootDist or 99) or (self._RightFootDist or 99)
					local otherDist = footName == "left" and (self._RightFootDist or 99) or (self._LeftFootDist or 99)
					if footDist < 12 and footDist < otherDist then
						self._LockedDominant = footName
					end
				end

				-- Use locked foot during push window
				if self._LockedDominant and past < 0.5 then
					dominantFoot = self._LockedDominant
					local footHitZ = dominantFoot == "left" and self._LeftFootHitZ or self._RightFootHitZ
					-- Push = how much higher the foot ground is vs current root
					local pushHeight = math.max((footHitZ or 0) - smoothPos.z, 0)
					targetPush = pushHeight * PUSH_STRENGTH
				else
					self._LockedDominant = nil
				end
			end
		else
			self._LockedDominant = nil
		end

		-- Reset push on sequence change
		if self._LastSequence ~= self:GetSequence() then
			self._FootPush = 0
			self._LastSequence = self:GetSequence()
		end

		-- Push raises root motion Z (can go above raw pos)
		self._FootPush = Lerp(0.08, self._FootPush or 0, targetPush)
		self._SmoothPosZ = self._SmoothPosZ + self._FootPush
		self._IkOffset = self._DbgBlendOff
		self._DominantFoot = dominantFoot

		self._DbgMinZ = minGroundZ
		self._DbgMaxZ = maxGroundZ
	else
		self._DbgBlendOff = 0
		self._DbgMinZ = smoothPos.z
		self._DbgMaxZ = smoothPos.z
		self._StepOrigin = smoothPos.z
		self._IkOffset = (self._IkOffset or 0) * 0.5
		self._SmoothMinZ = nil
		self._SmoothMaxZ = nil
	end

	-- Step 4: Apply offset and draw
	self:SetPos(Vector(smoothPos.x, smoothPos.y, smoothPos.z + (self._IkOffset or 0)))
	self:SetupBones()
	self:DrawModel()
	self:SetPos(pos)
end

end
