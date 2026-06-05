AddCSLuaFile()

ENT.Type = "nextbot"
ENT.Base = "base_nextbot"

ENT.PrintName = "Final Anim Test NPC v3"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Author = "City NPCs"

ENT.Purpose = "Minimal follow NPC with SetIK(true)"
ENT.Instructions = "Press +USE to recruit. Follows commander."

local FOLLOW_STOP_DIST = 48
local FOLLOW_LOST_DIST = 30000

local FOLLOW_SPEED_WALK = 80
local FOLLOW_SPEED_RUN = FOLLOW_SPEED_WALK
local FOLLOW_REPATH_INTERVAL = 0.25
local STAIR_SPEED_MIN_FACTOR = 0.5
local STAIR_SPEED_MAX = 55
local STAIR_CLIMB_RISE_SMOOTH = 0.35
local STAIR_CLIMB_FALL_SMOOTH = 0.08
local WALK_IDLE_OVERLAY_CYCLE = 0.20
local WALK_IDLE_OVERLAY_WEIGHT = 0.50
local DEBUG_INTERVAL = 0.05
local DEBUG_STILL_SPEED = 1
local DEBUG_STILL_MAX_SAMPLES = 6

local TURN_GESTURE_COOLDOWN = 0.5
local TURN_GESTURE_MIN_DELTA = 15

-- Citizen footstep events mark which foot should be treated as the current
-- contact foot for stair/IK checks.
local FOOTSTEP_EVENT_LEFT = 6006
local FOOTSTEP_EVENT_RIGHT = 6007
local modelFootCycleCache = {}

local function debugTimestamp()
	local frac = RealTime and (RealTime() % 1) or 0
	return os.date("%H:%M:%S") .. string.format(".%03d", math.floor(frac * 1000))
end

local function suppressStillDebug(ent, keyPrefix, moving, stateKey)
	local lastStateKey = keyPrefix .. "LastState"
	local sampleKey = keyPrefix .. "StillSamples"
	if moving or ent[lastStateKey] ~= stateKey then
		ent[lastStateKey] = stateKey
		ent[sampleKey] = 0
		return false
	end

	ent[sampleKey] = (ent[sampleKey] or 0) + 1
	return ent[sampleKey] > DEBUG_STILL_MAX_SAMPLES
end

local function getModelFootCycles(model)
	if not model then return nil end
	if modelFootCycleCache[model] then return modelFootCycleCache[model] end

	local cache = {}
	local mi = util.GetModelInfo(model)
	if mi and mi.Sequences then
		for _, seq in ipairs(mi.Sequences) do
			local leftCycle, rightCycle
			if seq.Events then
				for _, ev in ipairs(seq.Events) do
					if ev.Event == FOOTSTEP_EVENT_LEFT then leftCycle = ev.Cycle end
					if ev.Event == FOOTSTEP_EVENT_RIGHT then rightCycle = ev.Cycle end
				end
			end
			if leftCycle and rightCycle then
				cache[seq.Name] = { left = leftCycle, right = rightCycle }
			end
		end
	end

	modelFootCycleCache[model] = cache
	return cache
end

local function getEventContactFoot(ent)
	local cache = getModelFootCycles(ent:GetModel())
	local footCycle = cache and cache[ent:GetSequenceName(ent:GetSequence())]
	if not footCycle then return nil end

	local cycle = ent:GetCycle()
	local function cycleDist(a, b)
		local d = math.abs(a - b)
		return math.min(d, math.abs(d - 1))
	end

	return (cycleDist(cycle, footCycle.left) < cycleDist(cycle, footCycle.right)) and "left" or "right"
end

local function getEventFootWeights(ent)
	local cache = getModelFootCycles(ent:GetModel())
	local footCycle = cache and cache[ent:GetSequenceName(ent:GetSequence())]
	if not footCycle then return 1, 0 end

	local cycle = ent:GetCycle()
	local function cycleDist(a, b)
		local d = math.abs(a - b)
		return math.min(d, math.abs(d - 1))
	end

	local leftDist = cycleDist(cycle, footCycle.left)
	local rightDist = cycleDist(cycle, footCycle.right)
	local total = leftDist + rightDist
	if total <= 0.001 then return 1, 0 end

	return rightDist / total, leftDist / total
end

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

	self.loco:SetDesiredSpeed(FOLLOW_SPEED_WALK)
	self.loco:SetAcceleration(200)
	self.loco:SetDeceleration(200)
	self.loco:SetStepHeight(18)
	self.loco:SetMaxYawRate(180)

	self:StartActivity(ACT_IDLE)

	self.Commander = nil
	self.NextTurnTime = 0
	self.DebugEnabled = false
	self.NextDebugPrint = 0
	self.DebugLastPos = self:GetPos()
	self.DebugLastTime = CurTime()
	self:SetNWBool("CityV3Debug", false)
	self:SetNWBool("CityV3Following", false)
	self:SetNWFloat("CityV3FollowDist", -1)
	self:SetNWFloat("CityV3ServerOriginZ", self:GetPos().z)
	self:SetNWFloat("CityV3MoveSpeed", 0)
	self:SetNWFloat("CityV3ManualSpeed", 0)
	self:SetNWFloat("CityV3ForwardSpeed", 0)
	self:SetNWFloat("CityV3DesiredSpeed", self.loco:GetDesiredSpeed())
	self:SetNWVector("CityV3MoveTarget", vector_origin)
end

function ENT:SetDebugEnabled(ply, enabled)
	self.DebugEnabled = enabled
	self.DebugOwner = enabled and ply or nil
	self.NextDebugPrint = 0
	self:SetNWBool("CityV3Debug", enabled)
	print("[v3-nextbot] Debug " .. (enabled and "ON" or "OFF") .. " for #" .. self:EntIndex())
end

function ENT:PrintDebugLine()
	if not self.DebugEnabled or CurTime() < self.NextDebugPrint then return end
	self.NextDebugPrint = CurTime() + DEBUG_INTERVAL

	local pos = self:GetPos()
	local now = CurTime()
	local lastPos = self.DebugLastPos or pos
	local lastTime = self.DebugLastTime or now
	local dt = math.max(now - lastTime, 0.001)
	local manualSpeed = (Vector(pos.x, pos.y, 0) - Vector(lastPos.x, lastPos.y, 0)):Length() / dt
	local moveVel = self.loco and self.loco:GetVelocity() or vector_origin
	local moveSpeed = moveVel:Length2D()
	local fwd = self:GetForward()
	local forwardSpeed = moveVel.x * fwd.x + moveVel.y * fwd.y
	local idealSpeed = self.DebugIdealSpeed or (self.loco and self.loco:GetDesiredSpeed() or -1)
	self.DebugLastPos = pos
	self.DebugLastTime = now
	self:SetNWFloat("CityV3ServerOriginZ", pos.z)
	self:SetNWFloat("CityV3MoveSpeed", moveSpeed)
	self:SetNWFloat("CityV3ManualSpeed", manualSpeed)
	self:SetNWFloat("CityV3ForwardSpeed", forwardSpeed)
	self:SetNWFloat("CityV3DesiredSpeed", idealSpeed)

	local target = self:GetNWVector("CityV3MoveTarget", vector_origin)
	local targetDist = (target ~= vector_origin) and pos:Distance(target) or -1
	local seq = self:GetSequence()
	local seqName = self:GetSequenceName(seq) or "?"
	local act = self.GetActivity and self:GetActivity() or "?"
	local cycle = self:GetCycle()
	local playbackRate = self.GetPlaybackRate and self:GetPlaybackRate() or -1
	local seqGroundSpeed = self.GetSequenceGroundSpeed and self:GetSequenceGroundSpeed(seq) or -1
	local seqMoveDist = self.GetSequenceMoveDist and self:GetSequenceMoveDist(seq) or -1
	local seqDeltaXY = 0
	local seqDeltaZ = 0
	if self.GetSequenceMovement then
		local lastSeq = self.DebugLastSeq or seq
		local lastCycle = self.DebugLastCycle or cycle
		local startCycle = (lastSeq == seq) and lastCycle or cycle
		local endCycle = cycle
		if lastSeq == seq and cycle < startCycle then
			endCycle = cycle + 1
		end
		local ok, delta = self:GetSequenceMovement(seq, startCycle, endCycle)
		if ok and isvector(delta) then
			seqDeltaXY = delta:Length2D()
			seqDeltaZ = delta.z
		end
	end
	self.DebugLastSeq = seq
	self.DebugLastCycle = cycle

	local commander = self.Commander
	local cmdValid = IsValid(commander)
	local cmdDist = cmdValid and pos:Distance(commander:GetPos()) or -1
	local stateKey = string.format("%s:%d:%s:%d", tostring(cmdValid), seq, seqName, math.floor(pos.z + 0.5))
	if suppressStillDebug(self, "_CityV3ServerDebug", moveSpeed > DEBUG_STILL_SPEED or manualSpeed > DEBUG_STILL_SPEED, stateKey) then return end

	print(string.format(
		"[V3DBG #%d] ts=%s speed=%.1f fwd=%.1f actual=%.1f desired=%.1f anim=%.1f follow=%s stock=false cmdDist=%.1f fDist=%.1f tgtDist=%.1f originZ=%.1f mvVel=%.1f spd=%.1f ideal=%.1f tgtZ=%.1f seq=%d:%s act=%s mvAct=%s mvSeq=%s cycle=%.3f pb=%.2f gspd=%.1f mdist=%.1f seqDxy=%.2f seqDz=%.2f mint=%.3f nav=%s schedIdle=%s isnpc=%s stairFac=%.2f climb=%.1f stockInt=%.1f cmdSpd=%.1f",
		self:EntIndex(), debugTimestamp(), moveSpeed, forwardSpeed, manualSpeed, idealSpeed, seqGroundSpeed, tostring(cmdValid), cmdDist, self:GetNWFloat("CityV3FollowDist", -1), targetDist,
		pos.z, moveSpeed, manualSpeed, idealSpeed, target.z, seq, seqName, tostring(act), "-1", "-1", cycle,
		playbackRate, seqGroundSpeed, seqMoveDist, seqDeltaXY, seqDeltaZ, -1, "nextbot", tostring(moveSpeed <= 1 and act == ACT_IDLE), tostring(self:IsNPC()),
		self._StairSpeedFactor or 1, self._StairClimbRate or 0, self._StockIntervalSpeed or idealSpeed, self._StairCommandSpeed or idealSpeed
	))
end

function ENT:BodyUpdate()
	local act = self:GetActivity()
	local vel = self.loco:GetVelocity()
	local speed = vel:Length2D()
	local fwd = self:GetForward()
	local forwardSpeed = vel.x * fwd.x + vel.y * fwd.y
	self:SetNWFloat("CityV3ServerOriginZ", self:GetPos().z)
	self:SetNWFloat("CityV3MoveSpeed", speed)
	self:SetNWFloat("CityV3ForwardSpeed", forwardSpeed)
	self:SetNWFloat("CityV3DesiredSpeed", self.DebugIdealSpeed or self.loco:GetDesiredSpeed())
	local wantMove = speed > 20

	if wantMove then
		local seqIdx = self:LookupSequence("walk_all")
		if seqIdx and seqIdx >= 0 then
			if self:GetSequence() ~= seqIdx then
				self:SetSequence(seqIdx)
			end
			self._UsingPlazaWalk = true
		elseif act ~= ACT_WALK then
			self._UsingPlazaWalk = nil
			self:StartActivity(ACT_WALK)
		end
	elseif self._UsingPlazaWalk or act ~= ACT_IDLE then
		self._UsingPlazaWalk = nil
		self:ClearWalkIdleOverlay()
		self:StartActivity(ACT_IDLE)
	end

	self:BodyMoveXY()
	self:UpdateWalkIdleOverlay(wantMove and self._InStairOverlay)
	self:PrintDebugLine()
end

function ENT:ClearWalkIdleOverlay()
	local layerId = self._WalkIdleLayer
	self._WalkIdleLayer = nil
	if layerId and self.IsValidLayer and self:IsValidLayer(layerId) and self.RemoveLayer then
		self:RemoveLayer(layerId)
	end
end

function ENT:UpdateWalkIdleOverlay(wantMove)
	if not wantMove then
		self:ClearWalkIdleOverlay()
		return
	end

	local seqIdx = self:LookupSequence("idle_subtle")
	if not seqIdx or seqIdx < 0 then return end

	local layerId = self._WalkIdleLayer
	local validLayer = layerId and self.IsValidLayer and self:IsValidLayer(layerId)
	if validLayer and self.GetLayerSequence and self:GetLayerSequence(layerId) ~= seqIdx then
		self:ClearWalkIdleOverlay()
		validLayer = false
	end

	if not validLayer then
		layerId = self:AddGestureSequence(seqIdx, false)
		if not layerId or layerId < 0 then return end
		self._WalkIdleLayer = layerId
	end

	if self.SetLayerPriority then self:SetLayerPriority(layerId, 1) end
	if self.SetLayerCycle then self:SetLayerCycle(layerId, WALK_IDLE_OVERLAY_CYCLE) end
	if self.SetLayerWeight then self:SetLayerWeight(layerId, WALK_IDLE_OVERLAY_WEIGHT) end
	if self.SetLayerPlaybackRate then self:SetLayerPlaybackRate(layerId, 1) end
end

function ENT:AcceptInput(name, activator)
	if name ~= "Use" then return end
	if not IsValid(activator) or not activator:IsPlayer() or not activator:Alive() then return end

	self.Commander = (self.Commander == activator) and nil or activator
	self:SetNWBool("CityV3Following", IsValid(self.Commander))
	if not IsValid(self.Commander) then
		self:SetNWFloat("CityV3FollowDist", -1)
		self:SetNWVector("CityV3MoveTarget", vector_origin)
	end
	if IsValid(self.Commander) and not self.DebugEnabled then
		self:SetDebugEnabled(activator, true)
	end
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

function ENT:IsMovingUphill(moveTarget)
	local zDelta = moveTarget.z - self:GetPos().z
	return zDelta > 8
end

function ENT:GetStairProjectedSpeed(baseSpeed)
	if not self._InStairOverlay then
		self._StairClimbRate = 0
		self._StairSpeedFactor = 1
		self._StockIntervalSpeed = baseSpeed
		self._StairCommandSpeed = baseSpeed
		return baseSpeed
	end

	local now = CurTime()
	local posZ = self:GetPos().z
	local lastZ = self._StairSpeedLastZ or self._LastFollowZ or posZ
	local lastTime = self._StairSpeedLastTime or now
	local dt = math.max(now - lastTime, 0.001)
	local climbRate = math.max(0, posZ - lastZ) / dt
	self._StairSpeedLastZ = posZ
	self._StairSpeedLastTime = now

	local oldRate = self._StairClimbRate or climbRate
	local smooth = (climbRate > oldRate) and STAIR_CLIMB_RISE_SMOOTH or STAIR_CLIMB_FALL_SMOOTH
	local smoothedRate = Lerp(smooth, oldRate, climbRate)
	self._StairClimbRate = smoothedRate

	local factor = baseSpeed / math.sqrt(baseSpeed * baseSpeed + smoothedRate * smoothedRate)
	factor = math.Clamp(factor, STAIR_SPEED_MIN_FACTOR, 1)
	self._StairSpeedFactor = factor

	-- Stock NPCs budget movement by CAI_Motor::CalcIntervalMove:
	-- 0.5 * (currentSpeed + idealSpeed) * interval, then MoveGroundStep resolves geometry.
	local currentSpeed = self.loco and self.loco:GetVelocity():Length2D() or 0
	local intervalSpeed = 0.5 * (currentSpeed + baseSpeed)
	self._StockIntervalSpeed = intervalSpeed
	local commandSpeed = math.min(intervalSpeed, baseSpeed * factor, STAIR_SPEED_MAX)
	self._StairCommandSpeed = commandSpeed
	return commandSpeed
end

function ENT:RunBehaviour()
	while self:IsValid() and self:Health() > 0 do
		
		if self.Commander and IsValid(self.Commander) and self.Commander:Alive() then
			local cmdPos = self.Commander:GetPos()
			local dist = self:GetPos():Distance(cmdPos)
			self:SetNWBool("CityV3Following", true)
			self:SetNWFloat("CityV3FollowDist", dist)
			self:SetNWVector("CityV3MoveTarget", cmdPos)

			if dist > FOLLOW_LOST_DIST then
				self._MovingUphill = false
				self._MovingOnStairs = false
				self._InStairOverlay = false
				self._StairClimbRate = 0
				self._StairSpeedFactor = 1
				self._StairSpeedLastZ = nil
				self._StairSpeedLastTime = nil
				self._LastFollowZ = nil
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
				self.DebugIdealSpeed = FOLLOW_SPEED_WALK
				self.loco:SetDesiredSpeed(FOLLOW_SPEED_WALK)
				self:SetNWFloat("CityV3DesiredSpeed", self.DebugIdealSpeed)
				local path = Path("Chase")
				path:SetMinLookAheadDistance(300)
				path:SetGoalTolerance(FOLLOW_STOP_DIST)
				local nextRepath = 0

				local stuckPos = self:GetPos()
				local stuckTime = 0

				while self.Commander and IsValid(self.Commander) and self.Commander:Alive() do
					cmdPos = self.Commander:GetPos()
					dist = self:GetPos():Distance(cmdPos)
					self:SetNWFloat("CityV3FollowDist", dist)
					self:SetNWVector("CityV3MoveTarget", cmdPos)

					if dist > FOLLOW_LOST_DIST then
						self._MovingUphill = false
						self._MovingOnStairs = false
						self._InStairOverlay = false
						self._StairClimbRate = 0
						self._StairSpeedFactor = 1
						self._StairSpeedLastZ = nil
						self._StairSpeedLastTime = nil
						self._LastFollowZ = nil
						break
					end
					if dist <= FOLLOW_STOP_DIST then
						self._MovingUphill = false
						self._MovingOnStairs = false
						self._InStairOverlay = false
						self._StairClimbRate = 0
						self._StairSpeedFactor = 1
						self._StairSpeedLastZ = nil
						self._StairSpeedLastTime = nil
						self._LastFollowZ = nil
						break
					end

					local uphill = self:IsMovingUphill(cmdPos)
					self._MovingUphill = uphill
					local posZ = self:GetPos().z
					self._MovingOnStairs = uphill and self._LastFollowZ and posZ - self._LastFollowZ > 1
					if self._MovingOnStairs then
						self._InStairOverlay = true
					elseif not uphill then
						self._InStairOverlay = false
					end
					self._LastFollowZ = posZ
					self.DebugIdealSpeed = FOLLOW_SPEED_WALK
					self.loco:SetDesiredSpeed(self:GetStairProjectedSpeed(FOLLOW_SPEED_RUN))
					self:SetNWFloat("CityV3DesiredSpeed", self.DebugIdealSpeed)

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
					if CurTime() >= nextRepath then
						path:Chase(self, self.Commander)
						nextRepath = CurTime() + FOLLOW_REPATH_INTERVAL
					end
					if path:IsValid() then
						path:Update(self)
					else
						self.loco:Approach(cmdPos, 1)
					end
					if self.loco:IsStuck() then
						self:HandleStuck()
						break
					end

					local yawDelta = (math.deg(math.atan2(cmdPos.y - self:GetPos().y, cmdPos.x - self:GetPos().x)) - self:GetAngles().y) % 360
					if yawDelta > 180 then yawDelta = yawDelta - 360 end
					self:AddTurnGesture(yawDelta)

					coroutine.yield()
				end
			else
				self._MovingUphill = false
				self._MovingOnStairs = false
				self._InStairOverlay = false
				self._StairClimbRate = 0
				self._StairSpeedFactor = 1
				self._StairSpeedLastZ = nil
				self._StairSpeedLastTime = nil
				self._LastFollowZ = nil
				coroutine.wait(1)
			end
		else
			self.Commander = nil
			self._MovingUphill = false
			self._MovingOnStairs = false
			self._InStairOverlay = false
			self._StairClimbRate = 0
			self._StairSpeedFactor = 1
			self._StairSpeedLastZ = nil
			self._StairSpeedLastTime = nil
			self._LastFollowZ = nil
			self:SetNWBool("CityV3Following", false)
			self:SetNWFloat("CityV3FollowDist", -1)
			self:SetNWVector("CityV3MoveTarget", vector_origin)
			coroutine.wait(1)
		end
	end
end

concommand.Remove("citynpc_v3_debug")
concommand.Add("citynpc_v3_debug", function(ply)
	if not IsValid(ply) then return end

	local ent = ply:GetEyeTrace().Entity
	if not IsValid(ent) or ent:GetClass() ~= "city_anim_final_npc_test3" then
		ply:PrintMessage(HUD_PRINTTALK, "[v3-nextbot] Look at v3 first")
		return
	end

	ent:SetDebugEnabled(ply, not ent.DebugEnabled)
end)

end

if CLIENT then

local CLIENT_DEBUG_INTERVAL = 0.05

local function fmt(v)
	return v and string.format("%.1f", v) or "?"
end

local function getFootInfo(ent, boneName)
	local bone = ent:LookupBone(boneName)
	if not bone or bone < 0 then return nil, nil end

	local mat = ent:GetBoneMatrix(bone)
	if not mat then return nil, nil end

	local world = mat:GetTranslation()
	return ent:WorldToLocal(world).z, world.z
end

local function getBoneWorldPos(ent, boneName)
	local bone = ent:LookupBone(boneName)
	if not bone or bone < 0 then return nil end

	local mat = ent:GetBoneMatrix(bone)
	return mat and mat:GetTranslation() or nil
end

local function getLegAngles(ent, side)
	local prefix = "ValveBiped.Bip01_" .. side .. "_"
	local hip = getBoneWorldPos(ent, prefix .. "Thigh")
	local knee = getBoneWorldPos(ent, prefix .. "Calf")
	local ankle = getBoneWorldPos(ent, prefix .. "Foot")
	if not hip or not knee or not ankle then return nil, nil, nil end

	local upper = hip - knee
	local lower = ankle - knee
	local upperLen = upper:Length()
	local lowerLen = lower:Length()
	local kneeAngle
	if upperLen > 0.001 and lowerLen > 0.001 then
		local dot = math.Clamp(upper:Dot(lower) / (upperLen * lowerLen), -1, 1)
		kneeAngle = math.deg(math.acos(dot))
	end

	local function pitch(a, b)
		local delta = b - a
		local horiz = math.sqrt(delta.x * delta.x + delta.y * delta.y)
		if horiz <= 0.001 then return nil end
		return math.deg(math.atan(delta.z / horiz))
	end

	return kneeAngle, pitch(hip, knee), pitch(knee, ankle)
end

local function getOverlayInfo(ent)
	if not ent.IsValidLayer or not ent.GetLayerSequence then return "unsupported" end

	local parts = {}
	for slot = 0, 15 do
		local okValid, valid = pcall(ent.IsValidLayer, ent, slot)
		if okValid and valid then
			local _, seq = pcall(ent.GetLayerSequence, ent, slot)
			local _, weight = pcall(ent.GetLayerWeight, ent, slot)
			local _, cycle = pcall(ent.GetLayerCycle, ent, slot)
			local _, rate = pcall(ent.GetLayerPlaybackRate, ent, slot)

			seq = tonumber(seq) or -1
			weight = tonumber(weight) or 0
			cycle = tonumber(cycle) or 0
			rate = tonumber(rate) or 0

			if seq >= 0 or weight > 0 then
				parts[#parts + 1] = string.format("%d:%d:%s c%.2f w%.2f r%.2f", slot, seq, ent:GetSequenceName(seq) or "?", cycle, weight, rate)
			end
		end
	end

	return (#parts > 0) and table.concat(parts, "|") or "none"
end

local function getSequenceDebug(ent, seq, cycle)
	local playbackRate = ent.GetPlaybackRate and ent:GetPlaybackRate() or -1
	local groundSpeed = ent.GetSequenceGroundSpeed and ent:GetSequenceGroundSpeed(seq) or -1
	local moveDist = ent.GetSequenceMoveDist and ent:GetSequenceMoveDist(seq) or -1
	local deltaXY = 0
	local deltaZ = 0

	if ent.GetSequenceMovement then
		local lastSeq = ent._CityV3LastSeq or seq
		local lastCycle = ent._CityV3LastCycle or cycle
		local startCycle = (lastSeq == seq) and lastCycle or cycle
		local endCycle = cycle
		if lastSeq == seq and cycle < startCycle then
			endCycle = cycle + 1
		end
		local ok, delta = ent:GetSequenceMovement(seq, startCycle, endCycle)
		if ok and isvector(delta) then
			deltaXY = delta:Length2D()
			deltaZ = delta.z
		end
	end

	ent._CityV3LastSeq = seq
	ent._CityV3LastCycle = cycle

	return playbackRate, groundSpeed, moveDist, deltaXY, deltaZ
end

function ENT:CityDebugLabel()
	return "v3-nextbot"
end

function ENT:Think()
	if not self:GetNWBool("CityV3Debug", false) then return end
	if self.NextClientDebugPrint and CurTime() < self.NextClientDebugPrint then return end
	self.NextClientDebugPrint = CurTime() + CLIENT_DEBUG_INTERVAL

	self:SetupBones()

	local hullZ = self:GetPos().z
	local ik = self._CityV3IkDebug or {}
	local originZ = ik.renderZ or hullZ
	local serverOriginZ = self:GetNWFloat("CityV3ServerOriginZ", originZ)
	local manualSpeed = self:GetNWFloat("CityV3ManualSpeed", 0)
	local moveSpeed = self:GetNWFloat("CityV3MoveSpeed", 0)
	local forwardSpeed = self:GetNWFloat("CityV3ForwardSpeed", 0)
	local lLocalZ, lWorldZ = getFootInfo(self, "ValveBiped.Bip01_L_Foot")
	local rLocalZ, rWorldZ = getFootInfo(self, "ValveBiped.Bip01_R_Foot")
	local lKnee, lThighPitch, lShinPitch = getLegAngles(self, "L")
	local rKnee, rThighPitch, rShinPitch = getLegAngles(self, "R")
	local renderOffset = originZ - hullZ
	lWorldZ = lWorldZ and (lWorldZ + renderOffset) or nil
	rWorldZ = rWorldZ and (rWorldZ + renderOffset) or nil
	local seq = self:GetSequence()
	local seqName = self:GetSequenceName(seq) or "?"
	local act = self.GetActivity and self:GetActivity() or "?"
	local cycle = self:GetCycle()
	local playbackRate, seqGroundSpeed, seqMoveDist, seqDeltaXY, seqDeltaZ = getSequenceDebug(self, seq, cycle)
	local overlays = getOverlayInfo(self)
	local hullGap = ik.estIkFloor and (hullZ - ik.estIkFloor) or nil
	local renderDelta = ik.renderZ and (ik.renderZ - hullZ) or nil
	local stepSpan = (ik.minGroundZ and ik.maxGroundZ) and (ik.maxGroundZ - ik.minGroundZ) or nil
	local moving = moveSpeed > DEBUG_STILL_SPEED or manualSpeed > DEBUG_STILL_SPEED
	local stateKey = string.format("%d:%s:%s:%d:%d", seq, seqName, overlays, math.floor(originZ + 0.5), math.floor(serverOriginZ + 0.5))
	if suppressStillDebug(self, "_CityV3ClientDebug", moving, stateKey) then return end
	local ikExtra = " active=" .. tostring(ik.active or "?") ..
		" hullZ=" .. fmt(hullZ) ..
		" planted=" .. tostring(ik.planted) ..
		" activeLoc=" .. fmt(ik.activeLocalZ) ..
		" activeHit=" .. fmt(ik.activeHit) ..
		" Lwgt=" .. fmt(ik.leftWeight) ..
		" Rwgt=" .. fmt(ik.rightWeight) ..
		" gZ=" .. fmt(ik.groundZ) ..
		" minZ=" .. fmt(ik.minGroundZ) ..
		" maxZ=" .. fmt(ik.maxGroundZ) ..
		" span=" .. fmt(stepSpan) ..
		" estZ=" .. fmt(ik.estIkFloor) ..
		" rZ=" .. fmt(ik.renderZ) ..
		" hullGap=" .. fmt(hullGap) ..
		" rDelta=" .. fmt(renderDelta) ..
		" Lhit=" .. fmt(ik.leftHit) ..
		" Rhit=" .. fmt(ik.rightHit) ..
		" Lknee=" .. fmt(lKnee) ..
		" Rknee=" .. fmt(rKnee) ..
		" Lthigh=" .. fmt(lThighPitch) ..
		" Rthigh=" .. fmt(rThighPitch) ..
		" Lshin=" .. fmt(lShinPitch) ..
		" Rshin=" .. fmt(rShinPitch)

	print(string.format(
		"[V3CDBG #%d] ts=%s speed=%.1f fwd=%.1f actual=%.1f anim=%.1f originZ=%s srvZ=%s zDelta=%s mvVel=%.1f spd=%.1f Lloc=%s Lw=%s Rloc=%s Rw=%s seq=%d:%s act=%s cycle=%.3f pb=%.2f gspd=%.1f mdist=%.1f seqDxy=%.2f seqDz=%.2f overlays=%s%s",
		self:EntIndex(), debugTimestamp(), moveSpeed, forwardSpeed, manualSpeed, seqGroundSpeed, fmt(originZ), fmt(serverOriginZ), fmt(originZ - serverOriginZ), moveSpeed, manualSpeed,
		fmt(lLocalZ), fmt(lWorldZ), fmt(rLocalZ), fmt(rWorldZ),
		seq, seqName, tostring(act), cycle, playbackRate, seqGroundSpeed, seqMoveDist, seqDeltaXY, seqDeltaZ, overlays, ikExtra
	))
end

function ENT:Draw()
	self:SetIK(true)
	self:SetupBones()

	local lFootBone = self:LookupBone("ValveBiped.Bip01_L_Foot")
	local rFootBone = self:LookupBone("ValveBiped.Bip01_R_Foot")

	local STEP_HEIGHT = 18
	local HULL_R = 2.5
	local PLANTED_FOOT_Z = 5.5
	local GROUND_Z_DEADZONE = 0.5
	local RENDER_Z_RISE_SPEED = 40
	local RENDER_Z_FALL_SPEED = 96
	local hullPos = self:GetPos()
	local hullZ = hullPos.z
	if self._VisualZ and math.abs(self._VisualZ - hullZ) > STEP_HEIGHT * 2 then
		self._VisualZ = nil
		self._VisualRenderZ = nil
		self._LastGroundZ = nil
		self._EstIkFloor = nil
	end
	local traceZ = self._VisualZ or self._LastGroundZ or hullZ

	local seqName = self:GetSequenceName(self:GetSequence()) or ""
	local isMovingSeq = seqName:lower():find("walk") or seqName:lower():find("run")
	local cycle = self:GetCycle()
	local activeFoot = getEventContactFoot(self) or "left"
	local leftWeight, rightWeight = getEventFootWeights(self)
	local fwd = self:GetForward()
	local footForward = isMovingSeq and (Vector(fwd.x, fwd.y, 0):GetNormalized() * 4) or vector_origin
	local function footLocalZ(bone)
		if not bone then return nil end
		local m = self:GetBoneMatrix(bone)
		if not m then return nil end
		return self:WorldToLocal(m:GetTranslation()).z
	end
	local leftLocalZ = footLocalZ(lFootBone)
	local rightLocalZ = footLocalZ(rFootBone)
	local leftPlanted = leftLocalZ and leftLocalZ < PLANTED_FOOT_Z
	local rightPlanted = rightLocalZ and rightLocalZ < PLANTED_FOOT_Z

	-- Trace from foot XY with the historical small forward probe, centered around
	-- the current visual ground estimate so stair edges are sampled ahead of the foot.
	local function doTrace(bone, planted)
		if not bone then return nil end
		local mat = self:GetBoneMatrix(bone)
		if not mat then return nil end
		local footPos = mat:GetTranslation() + (planted and vector_origin or footForward)
		local tr = util.TraceHull({
			start = Vector(footPos.x, footPos.y, traceZ + STEP_HEIGHT + 2),
			endpos = Vector(footPos.x, footPos.y, traceZ - STEP_HEIGHT - 2),
			mins = Vector(-HULL_R, -HULL_R, 0),
			maxs = Vector(HULL_R, HULL_R, 1),
			filter = self,
			mask = MASK_SOLID
		})
		if not tr.Hit or tr.HitPos.z > hullZ + 2 then return nil end
		return tr.HitPos.z
	end

	local leftHit = doTrace(lFootBone, leftPlanted)
	local rightHit = doTrace(rFootBone, rightPlanted)
	if not leftHit and not rightHit then
		self._CityV3IkDebug = nil
		self:DrawModel()
		return
	end

	-- Keep active-foot state in debug so contact selection can be compared to SDK output.
	local activeLocalZ = (activeFoot == "left") and leftLocalZ or rightLocalZ
	local activePlanted = activeLocalZ and activeLocalZ < PLANTED_FOOT_Z
	local activeHit = (activeFoot == "left") and leftHit or rightHit

	-- Foot events weight the two traces so render height follows the walk cycle
	-- instead of the larger NextBot hull, which rises before the feet arrive.
	local groundZ
	local minGroundZ = leftHit and rightHit and math.min(leftHit, rightHit) or leftHit or rightHit
	local maxGroundZ = leftHit and rightHit and math.max(leftHit, rightHit) or leftHit or rightHit
	local totalWeight = 0
	local weightedGroundZ = 0
	if leftHit then
		weightedGroundZ = weightedGroundZ + leftHit * leftWeight
		totalWeight = totalWeight + leftWeight
	end
	if rightHit then
		weightedGroundZ = weightedGroundZ + rightHit * rightWeight
		totalWeight = totalWeight + rightWeight
	end
	groundZ = (totalWeight > 0.01) and (weightedGroundZ / totalWeight) or activeHit or self._LastGroundZ or minGroundZ

	if groundZ then
		groundZ = math.Clamp(groundZ, traceZ - STEP_HEIGHT, traceZ + STEP_HEIGHT)
		if self._LastGroundZ and math.abs(groundZ - self._LastGroundZ) < GROUND_Z_DEADZONE then
			groundZ = self._LastGroundZ
		end

		self._EstIkFloor = self._EstIkFloor and (self._EstIkFloor * 0.2 + groundZ * 0.8) or groundZ
		local contactSpan = maxGroundZ and minGroundZ and (maxGroundZ - minGroundZ) or 0
		local bias = math.Clamp(contactSpan - STEP_HEIGHT, 0, STEP_HEIGHT)
		local renderOffset = math.Clamp(self._EstIkFloor - hullZ, -STEP_HEIGHT + bias, 0)
		local serverZ = self:GetNWFloat("CityV3ServerOriginZ", hullZ)
		local targetRenderZ = math.min(hullZ + renderOffset, serverZ)
		local renderZ = self._VisualRenderZ or targetRenderZ
		if math.abs(renderZ - targetRenderZ) > STEP_HEIGHT * 2 then
			renderZ = targetRenderZ
		else
			local smoothSpeed = (targetRenderZ > renderZ) and RENDER_Z_RISE_SPEED or RENDER_Z_FALL_SPEED
			renderZ = math.Approach(renderZ, targetRenderZ, FrameTime() * smoothSpeed)
		end

		self._CityV3IkDebug = {
			active = activeFoot,
			planted = activePlanted,
			activeLocalZ = activeLocalZ,
			activeHit = activeHit,
			leftWeight = leftWeight,
			rightWeight = rightWeight,
			groundZ = groundZ,
			minGroundZ = minGroundZ,
			maxGroundZ = maxGroundZ,
			estIkFloor = self._EstIkFloor,
			renderZ = renderZ,
			leftHit = leftHit,
			rightHit = rightHit
		}

		self._LastGroundZ = groundZ
		self._VisualZ = groundZ
		self._VisualRenderZ = renderZ
		local newPos = Vector(hullPos.x, hullPos.y, renderZ)

		self:SetRenderOrigin(newPos)
		self:SetupBones()
		self:DrawModel()
		self:SetRenderOrigin(nil)
	else
		self:DrawModel()
	end
end

end
