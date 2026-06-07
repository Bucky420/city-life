AddCSLuaFile()
AddCSLuaFile("city_npcs/debug.lua")
include("city_npcs/debug.lua")

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
local FOLLOW_ACCEL = 200
local FOLLOW_DECEL = 200
local SDK_HEIGHT_ADJUST_UP_MIN = 0.5
local SDK_HEIGHT_ADJUST_DOWN_MIN = 0.8
local FOLLOW_REPATH_INTERVAL = 0.25
local WALK_IDLE_OVERLAY_CYCLE = 0.20
local WALK_IDLE_OVERLAY_MAX_WEIGHT = 0.97
local WALK_IDLE_OVERLAY_FADE_RATE = 4.0
local DEBUG_INTERVAL = 0.05
local DEBUG_STILL_SPEED = 1
local DEBUG_STILL_MAX_SAMPLES = 6
local WALK_TO_IDLE_DELAY = 0.15

local TURN_GESTURE_COOLDOWN = 0.5
local TURN_GESTURE_MIN_DELTA = 15

-- Citizen footstep events mark which foot should be treated as the current
-- contact foot for stair/IK checks. Source defines regular footsteps as
-- 6004/6005 and material-based footsteps as 6006/6007.
local FOOTSTEP_EVENT_LEFT = 6004
local FOOTSTEP_EVENT_RIGHT = 6005
local FOOTSTEP_EVENT_MAT_LEFT = 6006
local FOOTSTEP_EVENT_MAT_RIGHT = 6007
local modelFootCycleCache = {}

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
					if ev.Event == FOOTSTEP_EVENT_LEFT or ev.Event == FOOTSTEP_EVENT_MAT_LEFT then leftCycle = ev.Cycle end
					if ev.Event == FOOTSTEP_EVENT_RIGHT or ev.Event == FOOTSTEP_EVENT_MAT_RIGHT then rightCycle = ev.Cycle end
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
	local function cycleSince(eventCycle)
		local d = cycle - eventCycle
		if d < 0 then d = d + 1 end
		return d
	end

	return (cycleSince(footCycle.left) < cycleSince(footCycle.right)) and "left" or "right"
end

local function getEventFootWeights(ent)
	local cache = getModelFootCycles(ent:GetModel())
	local footCycle = cache and cache[ent:GetSequenceName(ent:GetSequence())]
	if not footCycle then return 1, 0 end

	local cycle = ent:GetCycle()
	local function cycleSince(eventCycle)
		local d = cycle - eventCycle
		if d < 0 then d = d + 1 end
		return d
	end

	return (cycleSince(footCycle.left) < cycleSince(footCycle.right)) and 1 or 0, (cycleSince(footCycle.right) < cycleSince(footCycle.left)) and 1 or 0
end

local function getFootSwingProbeScale(ent, side)
	local cache = getModelFootCycles(ent:GetModel())
	local footCycle = cache and cache[ent:GetSequenceName(ent:GetSequence())]
	if not footCycle then return 0 end

	local ownCycle = footCycle[side]
	local otherCycle = (side == "left") and footCycle.right or footCycle.left
	if not ownCycle or not otherCycle then return 0 end

	local cycle = ent:GetCycle()
	local span = ownCycle - otherCycle
	if span <= 0 then span = span + 1 end
	if span <= 0.001 then return 0 end

	local sinceOther = cycle - otherCycle
	if sinceOther < 0 then sinceOther = sinceOther + 1 end
	if sinceOther > span then return 0 end

	return math.sin(math.Clamp(sinceOther / span, 0, 1) * math.pi)
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
	self.loco:SetAcceleration(FOLLOW_ACCEL)
	self.loco:SetDeceleration(FOLLOW_DECEL)
	self.loco:SetStepHeight(18)
	self.loco:SetMaxYawRate(180)

	self:StartActivity(ACT_IDLE)

	self.Commander = nil
	self.NextTurnTime = 0
	self.DebugEnabled = false
	self.NextDebugPrint = 0
	self.DebugLastPos = self:GetPos()
	self.DebugLastTime = CurTime()
	self.DebugFollowDist = -1
	self.DebugMoveTarget = vector_origin

	CityNPCDebug.PrintSpawnHull(self, "v3-nextbot")
end

function ENT:SetDebugEnabled(ply, enabled)
	self.DebugEnabled = enabled
	self.DebugOwner = enabled and ply or nil
	self.NextDebugPrint = 0
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
	local posDelta = pos - lastPos
	local manualSpeed = Vector(posDelta.x, posDelta.y, 0):Length() / dt
	local zSpeed = posDelta.z / dt
	local moveVel = self.loco and self.loco:GetVelocity() or vector_origin
	local moveSpeed = moveVel:Length2D()
	local entVel = self.GetVelocity and self:GetVelocity() or vector_origin
	local entSpeed = entVel:Length2D()
	local groundNormal = (self.loco and self.loco.GetGroundNormal) and self.loco:GetGroundNormal() or vector_origin
	local groundMotion = (self.loco and self.loco.GetGroundMotionVector) and self.loco:GetGroundMotionVector() or vector_origin
	local locoOnGround = (self.loco and self.loco.IsOnGround) and self.loco:IsOnGround() or false
	local locoAttempt = (self.loco and self.loco.IsAttemptingToMove) and self.loco:IsAttemptingToMove() or false
	local locoClimbJump = (self.loco and self.loco.IsClimbingOrJumping) and self.loco:IsClimbingOrJumping() or false
	local stepHeight = (self.loco and self.loco.GetStepHeight) and self.loco:GetStepHeight() or -1
	local groundEnt = self.GetGroundEntity and self:GetGroundEntity() or NULL
	local groundSpeedVel = self.GetGroundSpeedVelocity and self:GetGroundSpeedVelocity() or vector_origin
	local fwd = self:GetForward()
	local forwardSpeed = moveVel.x * fwd.x + moveVel.y * fwd.y
	local idealSpeed = self.DebugIdealSpeed or (self.loco and self.loco:GetDesiredSpeed() or -1)
	local desiredSpeed = (self.loco and self.loco.GetDesiredSpeed) and self.loco:GetDesiredSpeed() or idealSpeed
	local sdkAdjust = self.DebugSdkSpeedAdjust or -1
	self.DebugLastPos = pos
	self.DebugLastTime = now
	local target = self.DebugMoveTarget or vector_origin
	local targetDist = (target ~= vector_origin) and pos:Distance(target) or -1
	local anim = CityNPCDebug.GetAnimSegment(self)
	local layerInfo = CityNPCDebug.GetLayerInfo(self, self._WalkIdleLayer, self._WalkIdleOverlayWeight, self._WalkIdleOverlayTargetWeight, self._WalkIdleOverlayRawWeight)

	local commander = self.Commander
	local cmdValid = IsValid(commander)
	local cmdDist = cmdValid and pos:Distance(commander:GetPos()) or -1
	local stateKey = string.format("%s:%d:%s:%d", tostring(cmdValid), anim.seq, anim.seqName, math.floor(pos.z + 0.5))
	if suppressStillDebug(self, "_CityV3ServerDebug", moveSpeed > DEBUG_STILL_SPEED or manualSpeed > DEBUG_STILL_SPEED, stateKey) then return end

	print(string.format(
		"[V3DBG #%d] ts=%s locoVel=%.1f entVel=%.1f actualVel=%.1f fwdVel=%.1f zVel=%.1f desired=%.1f ideal=%.1f sdkAdj=%.2f anim=%.1f follow=%s stock=false cmdDist=%.1f tgtDist=%.1f originZ=%.1f tgtZ=%.1f %s layer=%s layerSeq=%d:%s layerW=%.2f layerTarget=%.2f layerRaw=%.2f layerCycle=%.3f layerPb=%.2f nav=%s schedIdle=%s isnpc=%s locoGround=%s locoAttempt=%s locoClimbJump=%s stepH=%.1f gNorm=(%.2f,%.2f,%.2f) gMotion=(%.2f,%.2f,%.2f) gEnt=%s gSpdVel=%.1f",
		self:EntIndex(), CityNPCDebug.Timestamp(), moveSpeed, entSpeed, manualSpeed, forwardSpeed, zSpeed, desiredSpeed, idealSpeed, sdkAdjust, anim.seqGroundSpeed, tostring(cmdValid), cmdDist, targetDist,
		pos.z, target.z, anim.text, tostring(layerInfo.valid), layerInfo.seq, layerInfo.name, layerInfo.weight, layerInfo.targetWeight, layerInfo.rawWeight, layerInfo.cycle, layerInfo.playbackRate,
		"nextbot", tostring(moveSpeed <= 1 and anim.act == ACT_IDLE), tostring(self:IsNPC()),
		tostring(locoOnGround), tostring(locoAttempt), tostring(locoClimbJump), stepHeight,
		groundNormal.x, groundNormal.y, groundNormal.z, groundMotion.x, groundMotion.y, groundMotion.z,
		IsValid(groundEnt) and (groundEnt:GetClass() .. "#" .. groundEnt:EntIndex()) or "none", groundSpeedVel:Length2D()
	))
end

function ENT:BodyUpdate()
	local act = self:GetActivity()
	local vel = self.loco:GetVelocity()
	local speed = vel:Length2D()
	local pos = self:GetPos()
	local now = CurTime()
	local lastPos = self._BodyUpdateLastPos or pos
	local lastTime = self._BodyUpdateLastTime or now
	local dt = math.max(now - lastTime, 0.001)
	local actualSpeed = (Vector(pos.x, pos.y, 0) - Vector(lastPos.x, lastPos.y, 0)):Length() / dt
	self._BodyUpdateLastPos = pos
	self._BodyUpdateLastTime = now
	local fwd = self:GetForward()
	local forwardSpeed = vel.x * fwd.x + vel.y * fwd.y
	self.DebugMoveSpeed = speed
	self.DebugForwardSpeed = forwardSpeed
	self.DebugDesiredSpeed = self.DebugIdealSpeed or self.loco:GetDesiredSpeed()
	local movingNow = math.max(speed, actualSpeed) > 20
	if movingNow then self._LastBodyMoveTime = now end
	local wantMove = movingNow or ((now - (self._LastBodyMoveTime or 0)) < WALK_TO_IDLE_DELAY)

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
	self:UpdateWalkIdleOverlay(wantMove and self._InStairOverlay, speed)
	self:PrintDebugLine()
end

function ENT:ClearWalkIdleOverlay()
	local layerId = self._WalkIdleLayer
	self._WalkIdleLayer = nil
	if layerId and self.IsValidLayer and self:IsValidLayer(layerId) and self.RemoveLayer then
		self:RemoveLayer(layerId)
	end
end

function ENT:UpdateWalkIdleOverlay(wantMove, moveSpeed)
	if not wantMove then
		self._WalkIdleOverlayWeight = 0
		self._WalkIdleOverlayTargetWeight = 0
		self._WalkIdleOverlayRawWeight = 0
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
		layerId = self.AddLayeredSequence and self:AddLayeredSequence(seqIdx, 0) or self:AddGestureSequence(seqIdx, false)
		if not layerId or layerId < 0 then return end
		self._WalkIdleLayer = layerId
		if self.SetLayerCycle then self:SetLayerCycle(layerId, WALK_IDLE_OVERLAY_CYCLE) end
	end

	local targetWeight = math.Clamp(1 - ((moveSpeed or 0) / FOLLOW_SPEED_WALK), 0, WALK_IDLE_OVERLAY_MAX_WEIGHT)
	self._WalkIdleOverlayRawWeight = targetWeight
	self._WalkIdleOverlayTargetWeight = targetWeight
	local dt = FrameTime and FrameTime() or 0.015
	self._WalkIdleOverlayWeight = math.Approach(self._WalkIdleOverlayWeight or 0, targetWeight, WALK_IDLE_OVERLAY_FADE_RATE * dt)

	if self.SetLayerPriority then self:SetLayerPriority(layerId, 1) end
	if self.SetLayerWeight then self:SetLayerWeight(layerId, self._WalkIdleOverlayWeight) end
	if self.SetLayerPlaybackRate then self:SetLayerPlaybackRate(layerId, 1) end
end

function ENT:AcceptInput(name, activator)
	if name ~= "Use" then return end
	if not IsValid(activator) or not activator:IsPlayer() or not activator:Alive() then return end

	self.Commander = (self.Commander == activator) and nil or activator
	if not IsValid(self.Commander) then
		self.DebugFollowDist = -1
		self.DebugMoveTarget = vector_origin
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

function ENT:GetSdkHeightAdjustedSpeed(baseSpeed)
	local pos = self:GetPos()
	local prev = self._SdkSpeedPrevOrigin2 or self._SdkSpeedPrevOrigin1 or pos
	local dist = (Vector(pos.x, pos.y, 0) - Vector(prev.x, prev.y, 0)):Length()
	local height = pos.z - prev.z
	local adjust = 1
	if dist > 0.001 then
		adjust = 1.1 - math.abs(height / dist)
		adjust = math.Clamp(adjust, (height > 0) and SDK_HEIGHT_ADJUST_UP_MIN or SDK_HEIGHT_ADJUST_DOWN_MIN, 1)
	end

	if adjust < (self._SdkReactiveSpeedAdjust or 1) then
		self._SdkReactiveSpeedAdjust = (self._SdkReactiveSpeedAdjust or 1) * 0.2 + adjust * 0.8
	else
		self._SdkReactiveSpeedAdjust = (self._SdkReactiveSpeedAdjust or 1) * 0.5 + adjust * 0.5
	end

	self.DebugSdkSpeedAdjust = self._SdkReactiveSpeedAdjust
	self._SdkSpeedPrevOrigin2 = self._SdkSpeedPrevOrigin1 or pos
	self._SdkSpeedPrevOrigin1 = pos
	return baseSpeed * self._SdkReactiveSpeedAdjust
end

function ENT:RunBehaviour()
	while self:IsValid() and self:Health() > 0 do
		
		if self.Commander and IsValid(self.Commander) and self.Commander:Alive() then
			local cmdPos = self.Commander:GetPos()
			local dist = self:GetPos():Distance(cmdPos)
			self.DebugFollowDist = dist
			self.DebugMoveTarget = cmdPos

			if dist > FOLLOW_LOST_DIST then
				self._MovingUphill = false
				self._MovingOnStairs = false
				self._InStairOverlay = false
				self._SdkReactiveSpeedAdjust = nil
				self._SdkSpeedPrevOrigin1 = nil
				self._SdkSpeedPrevOrigin2 = nil
				self.DebugSdkSpeedAdjust = nil
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
				self.loco:SetAcceleration(FOLLOW_ACCEL)
				self.loco:SetDeceleration(FOLLOW_DECEL)
				self.loco:SetDesiredSpeed(FOLLOW_SPEED_WALK)
				local path = Path("Chase")
				path:SetMinLookAheadDistance(300)
				path:SetGoalTolerance(FOLLOW_STOP_DIST)
				local nextRepath = 0

				local stuckPos = self:GetPos()
				local stuckTime = 0

				while self.Commander and IsValid(self.Commander) and self.Commander:Alive() do
					cmdPos = self.Commander:GetPos()
					dist = self:GetPos():Distance(cmdPos)
					self.DebugFollowDist = dist
					self.DebugMoveTarget = cmdPos

					if dist > FOLLOW_LOST_DIST then
						self._MovingUphill = false
						self._MovingOnStairs = false
						self._InStairOverlay = false
						self._SdkReactiveSpeedAdjust = nil
						self._SdkSpeedPrevOrigin1 = nil
						self._SdkSpeedPrevOrigin2 = nil
						self.DebugSdkSpeedAdjust = nil
						self._LastFollowZ = nil
						break
					end
					if dist <= FOLLOW_STOP_DIST then
						self._MovingUphill = false
						self._MovingOnStairs = false
						self._InStairOverlay = false
						self._SdkReactiveSpeedAdjust = nil
						self._SdkSpeedPrevOrigin1 = nil
						self._SdkSpeedPrevOrigin2 = nil
						self.DebugSdkSpeedAdjust = nil
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
					local targetFollowSpeed = self:GetSdkHeightAdjustedSpeed(FOLLOW_SPEED_RUN)
					self.loco:SetAcceleration(FOLLOW_ACCEL)
					self.loco:SetDeceleration(FOLLOW_DECEL)
					self.DebugIdealSpeed = targetFollowSpeed
					self.loco:SetDesiredSpeed(targetFollowSpeed)

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
				self._SdkReactiveSpeedAdjust = nil
				self._SdkSpeedPrevOrigin1 = nil
				self._SdkSpeedPrevOrigin2 = nil
				self.DebugSdkSpeedAdjust = nil
				self._LastFollowZ = nil
				coroutine.wait(1)
			end
		else
			self.Commander = nil
			self._MovingUphill = false
			self._MovingOnStairs = false
			self._InStairOverlay = false
			self._SdkReactiveSpeedAdjust = nil
			self._SdkSpeedPrevOrigin1 = nil
			self._SdkSpeedPrevOrigin2 = nil
			self.DebugSdkSpeedAdjust = nil
			self._LastFollowZ = nil
			self.DebugFollowDist = -1
			self.DebugMoveTarget = vector_origin
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

local CLIENT_VIS_DEBUG_INTERVAL = 0.05

local function fmt(v)
	return v and string.format("%.1f", v) or "?"
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

local function printVisualDebug(ent, data)
	if ent._CityV3NextVisualDebug and CurTime() < ent._CityV3NextVisualDebug then return end
	ent._CityV3NextVisualDebug = CurTime() + CLIENT_VIS_DEBUG_INTERVAL

	local hullZ = ent:GetPos().z
	local seq = ent:GetSequence()
	local seqName = ent:GetSequenceName(seq) or "?"
	local cycle = ent:GetCycle()
	local lKnee, lThighPitch, lShinPitch = getLegAngles(ent, "L")
	local rKnee, rThighPitch, rShinPitch = getLegAngles(ent, "R")

	print(string.format(
		"[V3ZDBG #%d] seq=%d:%s cycle=%.3f hullZ=%s renderZ=%s rDelta=%s active=%s groundZ=%s estZ=%s minZ=%s maxZ=%s Lloc=%s Lw=%s Lhit=%s Rloc=%s Rw=%s Rhit=%s Lknee=%s Rknee=%s Lthigh=%s Rthigh=%s Lshin=%s Rshin=%s",
		ent:EntIndex(), seq, seqName, cycle, fmt(hullZ), fmt(data.renderZ), fmt(data.renderZ and (data.renderZ - hullZ)), tostring(data.activeFoot or "?"),
		fmt(data.groundZ), fmt(data.estZ), fmt(data.minGroundZ), fmt(data.maxGroundZ),
		fmt(data.leftLocalZ), fmt(data.leftWorldZ), fmt(data.leftHit), fmt(data.rightLocalZ), fmt(data.rightWorldZ), fmt(data.rightHit),
		fmt(lKnee), fmt(rKnee), fmt(lThighPitch), fmt(rThighPitch), fmt(lShinPitch), fmt(rShinPitch)
	))
end

function ENT:CityDebugLabel()
	return "v3-nextbot"
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
	local RENDER_Z_RISE_SPEED = 96
	local RENDER_Z_FALL_SPEED = 96
	local hullPos = self:GetPos()
	local hullZ = hullPos.z
	if self._VisualRenderZ and math.abs(self._VisualRenderZ - hullZ) > STEP_HEIGHT * 4 then
		self._VisualZ = nil
		self._VisualRenderZ = nil
		self._LastGroundZ = nil
		self._EstIkFloor = nil
	end
	local traceZ = hullZ

	local seqName = self:GetSequenceName(self:GetSequence()) or ""
	local isMovingSeq = seqName:lower():find("walk") or seqName:lower():find("run")
	if not isMovingSeq then
		self._VisualZ = nil
		self._VisualRenderZ = nil
		self._LastGroundZ = nil
		self._EstIkFloor = nil
		self:DrawModel()
		return
	end

	local activeFoot = getEventContactFoot(self) or "left"
	local leftWeight, rightWeight = getEventFootWeights(self)
	local fwd = self:GetForward()
	local flatForward = Vector(fwd.x, fwd.y, 0):GetNormalized()
	local function footInfo(bone)
		if not bone then return nil end
		local m = self:GetBoneMatrix(bone)
		if not m then return nil end
		local world = m:GetTranslation()
		return self:WorldToLocal(world).z, world.z
	end
	local leftLocalZ, leftWorldZ = footInfo(lFootBone)
	local rightLocalZ, rightWorldZ = footInfo(rFootBone)
	local leftPlanted = leftLocalZ and leftLocalZ < PLANTED_FOOT_Z
	local rightPlanted = rightLocalZ and rightLocalZ < PLANTED_FOOT_Z

	-- Trace from foot XY. Swinging feet get a small event-shaped forward probe so
	-- stair-edge sampling follows footstep timing instead of snapping on plant state.
	local function doTrace(bone, side, planted)
		if not bone then return nil end
		local mat = self:GetBoneMatrix(bone)
		if not mat then return nil end
		local probeScale = (isMovingSeq and not planted) and getFootSwingProbeScale(self, side) or 0
		local footPos = mat:GetTranslation() + flatForward * (probeScale * 4)
		local tr = util.TraceHull({
			start = Vector(footPos.x, footPos.y, traceZ + STEP_HEIGHT + 2),
			endpos = Vector(footPos.x, footPos.y, traceZ - STEP_HEIGHT - 2),
			mins = Vector(-HULL_R, -HULL_R, 0),
			maxs = Vector(HULL_R, HULL_R, 1),
			filter = self,
			mask = MASK_SOLID
		})
		if not tr.Hit or tr.HitPos.z > traceZ + STEP_HEIGHT then return nil end
		return tr.HitPos.z
	end

	local leftHit = doTrace(lFootBone, "left", leftPlanted)
	local rightHit = doTrace(rFootBone, "right", rightPlanted)
	if leftHit and rightHit and math.abs(leftHit - hullZ) < 0.75 and math.abs(rightHit - hullZ) < 0.75 then
		if leftLocalZ then self._FlatFootLocalZLeft = self._FlatFootLocalZLeft and (self._FlatFootLocalZLeft * 0.9 + leftLocalZ * 0.1) or leftLocalZ end
		if rightLocalZ then self._FlatFootLocalZRight = self._FlatFootLocalZRight and (self._FlatFootLocalZRight * 0.9 + rightLocalZ * 0.1) or rightLocalZ end
	end
	if not leftHit and not rightHit then
		printVisualDebug(self, {
			activeFoot = activeFoot,
			leftLocalZ = leftLocalZ,
			leftWorldZ = leftWorldZ,
			rightLocalZ = rightLocalZ,
			rightWorldZ = rightWorldZ
		})
		self:DrawModel()
		return
	end

	local activeHit = (activeFoot == "left") and leftHit or rightHit

	-- Build an independent visual height from model contact data. The collision
	-- hull stair-steps, so do not use hull/local entity Z as the visual reference.
	local contactGroundZ
	local contactLocalZ
	local minGroundZ = leftHit and rightHit and math.min(leftHit, rightHit) or leftHit or rightHit
	local maxGroundZ = leftHit and rightHit and math.max(leftHit, rightHit) or leftHit or rightHit
	local totalWeight = 0
	local weightedGroundZ = 0
	local weightedLocalZ = 0
	if leftHit and leftPlanted then
		weightedGroundZ = weightedGroundZ + leftHit * leftWeight
		weightedLocalZ = weightedLocalZ + (leftLocalZ or 0) * leftWeight
		totalWeight = totalWeight + leftWeight
	end
	if rightHit and rightPlanted then
		weightedGroundZ = weightedGroundZ + rightHit * rightWeight
		weightedLocalZ = weightedLocalZ + (rightLocalZ or 0) * rightWeight
		totalWeight = totalWeight + rightWeight
	end
	local activeLocalZ = (activeFoot == "left") and leftLocalZ or rightLocalZ
	local activePlanted = (activeFoot == "left") and leftPlanted or rightPlanted
	if activeHit and activeLocalZ and activePlanted then
		contactGroundZ = activeHit
		contactLocalZ = activeLocalZ
	elseif totalWeight > 0.01 then
		contactGroundZ = weightedGroundZ / totalWeight
		contactLocalZ = weightedLocalZ / totalWeight
	elseif leftHit and leftPlanted and leftLocalZ then
		contactGroundZ = leftHit
		contactLocalZ = leftLocalZ
	elseif rightHit and rightPlanted and rightLocalZ then
		contactGroundZ = rightHit
		contactLocalZ = rightLocalZ
	else
		contactGroundZ = minGroundZ or self._LastGroundZ
		contactLocalZ = math.min(leftLocalZ or PLANTED_FOOT_Z, rightLocalZ or PLANTED_FOOT_Z, PLANTED_FOOT_Z)
	end

	if contactGroundZ and contactLocalZ then
		contactGroundZ = math.Clamp(contactGroundZ, traceZ - STEP_HEIGHT, traceZ + STEP_HEIGHT)
		contactLocalZ = math.Clamp(contactLocalZ, -STEP_HEIGHT, PLANTED_FOOT_Z)
		if self._LastGroundZ and math.abs(contactGroundZ - self._LastGroundZ) < GROUND_Z_DEADZONE then
			contactGroundZ = self._LastGroundZ
		end

		local contactFoot = activeHit and activeLocalZ and activePlanted and activeFoot or nil
		if not contactFoot then
			if leftHit and leftPlanted and leftLocalZ then contactFoot = "left" end
			if not contactFoot and rightHit and rightPlanted and rightLocalZ then contactFoot = "right" end
		end
		local footBaseline = (contactFoot == "left") and self._FlatFootLocalZLeft or self._FlatFootLocalZRight
		footBaseline = footBaseline or math.Clamp(contactLocalZ, 0, PLANTED_FOOT_Z)
		local footTargetZ = contactGroundZ - (contactLocalZ - footBaseline)
		local targetRenderZ = math.Clamp(footTargetZ, hullZ - STEP_HEIGHT, hullZ)
		local renderZ = self._VisualRenderZ or targetRenderZ
		if math.abs(renderZ - targetRenderZ) > STEP_HEIGHT * 2 then
			renderZ = targetRenderZ
		else
			local smoothSpeed = (targetRenderZ > renderZ) and RENDER_Z_RISE_SPEED or RENDER_Z_FALL_SPEED
			renderZ = math.Approach(renderZ, targetRenderZ, FrameTime() * smoothSpeed)
		end

		self._LastGroundZ = contactGroundZ
		self._VisualZ = contactGroundZ
		self._VisualRenderZ = renderZ
		local newPos = Vector(hullPos.x, hullPos.y, renderZ)
		printVisualDebug(self, {
			activeFoot = activeFoot,
			leftLocalZ = leftLocalZ,
			leftWorldZ = leftWorldZ,
			leftHit = leftHit,
			rightLocalZ = rightLocalZ,
			rightWorldZ = rightWorldZ,
			rightHit = rightHit,
			groundZ = contactGroundZ,
			estZ = targetRenderZ,
			minGroundZ = minGroundZ,
			maxGroundZ = maxGroundZ,
			renderZ = renderZ
		})

		self:SetRenderOrigin(newPos)
		self:SetupBones()
		self:DrawModel()
		self:SetRenderOrigin(nil)
	else
		self:DrawModel()
	end
end

end
