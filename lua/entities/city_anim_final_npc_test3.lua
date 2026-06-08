AddCSLuaFile()
AddCSLuaFile("entities/modules/npc_debug.lua")
include("entities/modules/npc_debug.lua")

local NPCDebug = CityNPCs.Modules.npc_debug

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
local SDK_PREDICTIVE_LOOKAHEAD = 96
local SDK_LOCAL_STEP_SIZE = 16
local SDK_MOVE_HEIGHT_EPSILON = 0.0625
local FOLLOW_REPATH_INTERVAL = 0.25
local WALK_IDLE_OVERLAY_CYCLE = 0.20
local WALK_IDLE_OVERLAY_MAX_WEIGHT = 0.97
local WALK_IDLE_OVERLAY_FADE_RATE = 4.0
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

local function getFootContactAge(ent, side)
	local cache = getModelFootCycles(ent:GetModel())
	local footCycle = cache and cache[ent:GetSequenceName(ent:GetSequence())]
	if not footCycle or not footCycle[side] then return nil end

	local age = ent:GetCycle() - footCycle[side]
	if age < 0 then age = age + 1 end
	return age
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
	self.DebugMoveTarget = vector_origin

	NPCDebug.PrintSpawnHull(self, "v3-nextbot")
end

function ENT:SetDebugEnabled(ply, enabled)
	NPCDebug.SetServerEnabled(self, ply, enabled, "v3-nextbot")
end

function ENT:PrintDebugLine()
	NPCDebug.PrintServerLine(self)
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
		self:StartActivity(ACT_IDLE)
	end

	self._WalkIdleOverlayWanted = wantMove and self._InStairOverlay
	self._WalkIdleOverlayMoveSpeed = speed
	self:BodyMoveXY()
	self:PrintDebugLine()
end

function ENT:BehaveUpdate(interval)
	if self.BehaveThread then
		coroutine.resume(self.BehaveThread)
	end

	self:UpdateWalkIdleOverlay(self._WalkIdleOverlayWanted, self._WalkIdleOverlayMoveSpeed, interval)
end

function ENT:ClearWalkIdleOverlay()
	local layerId = self._WalkIdleLayer
	self._WalkIdleLayer = nil
	if layerId and self.IsValidLayer and self:IsValidLayer(layerId) and self.RemoveLayer then
		if self.SetLayerBlendIn then self:SetLayerBlendIn(layerId, 0) end
		if self.SetLayerBlendOut then self:SetLayerBlendOut(layerId, 0) end
		self:RemoveLayer(layerId)
	end
end

function ENT:UpdateWalkIdleOverlay(wantMove, moveSpeed, interval)
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
		if self.SetLayerLooping then self:SetLayerLooping(layerId, true) end
		if self.SetLayerAutokill then self:SetLayerAutokill(layerId, false) end
		if self.SetLayerBlendIn then self:SetLayerBlendIn(layerId, 0) end
		if self.SetLayerBlendOut then self:SetLayerBlendOut(layerId, 0) end
	end

	local targetWeight = math.Clamp(1 - ((moveSpeed or 0) / FOLLOW_SPEED_WALK), 0, WALK_IDLE_OVERLAY_MAX_WEIGHT)
	self._WalkIdleOverlayRawWeight = targetWeight
	self._WalkIdleOverlayTargetWeight = targetWeight
	local dt = interval or (FrameTime and FrameTime() or 0.015)
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
		self:ClearFollowMoveState(true)
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

function ENT:ClearSdkSpeedAdjust()
	self._SdkReactiveSpeedAdjust = nil
	self._SdkPredictiveSpeedAdjust = nil
	self._SdkSpeedPrevOrigin1 = nil
	self._SdkSpeedPrevOrigin2 = nil
	self._SdkProbeFoundHeightChange = nil
	self._FollowPath = nil
	self.DebugSdkSpeedAdjust = nil
	self.DebugSdkReactiveSpeedAdjust = nil
	self.DebugSdkPredictiveSpeedAdjust = nil
end

function ENT:ClearFollowMoveState(clearTarget)
	self._InStairOverlay = false
	self._LastFollowZ = nil
	self.DebugIdealSpeed = nil
	self:ClearSdkSpeedAdjust()
	if clearTarget then
		self.DebugMoveTarget = vector_origin
	end
end

function ENT:GetSdkHeightAdjustBetween(fromPos, toPos)
	if not isvector(fromPos) or not isvector(toPos) then return 1 end

	local dist = (Vector(toPos.x, toPos.y, 0) - Vector(fromPos.x, fromPos.y, 0)):Length()
	local height = toPos.z - fromPos.z
	if dist <= 0.001 then return 1 end

	local adjust = 1.1 - math.abs(height / dist)
	return math.Clamp(adjust, (height > 0) and SDK_HEIGHT_ADJUST_UP_MIN or SDK_HEIGHT_ADJUST_DOWN_MIN, 1)
end

function ENT:GetSdkTraceHullBounds()
	local mins, maxs = self:GetCollisionBounds()
	if not isvector(mins) or not isvector(maxs) then
		mins, maxs = self:OBBMins(), self:OBBMaxs()
	end
	mins = Vector(mins.x, mins.y, 0)
	return mins, maxs
end

function ENT:TraceSdkMoveHull(startPos, endPos)
	local mins, maxs = self:GetSdkTraceHullBounds()
	return util.TraceHull({
		start = startPos,
		endpos = endPos,
		mins = mins,
		maxs = maxs,
		filter = self,
		mask = MASK_NPCSOLID or MASK_SOLID,
		collisiongroup = COLLISION_GROUP_NPC
	})
end

function ENT:CheckSdkGroundStep(startPos, moveDir, stepSize)
	local stepHeight = (self.loco and self.loco.GetStepHeight) and self.loco:GetStepHeight() or 18
	local start = Vector(startPos.x, startPos.y, startPos.z + SDK_MOVE_HEIGHT_EPSILON)
	local forwardEnd = start + moveDir * stepSize
	local forwardTrace = self:TraceSdkMoveHull(start, forwardEnd)
	local moveStart = start
	local moveTrace = forwardTrace

	if forwardTrace.StartSolid or forwardTrace.Fraction < 1 then
		moveStart = forwardTrace.StartSolid and start or forwardTrace.HitPos
		local upTrace = self:TraceSdkMoveHull(moveStart, moveStart + Vector(0, 0, stepHeight))
		moveStart = upTrace.HitPos
		moveTrace = self:TraceSdkMoveHull(moveStart, Vector(forwardEnd.x, forwardEnd.y, moveStart.z))
		if moveTrace.StartSolid or moveTrace.Fraction <= 0.01 then
			return startPos, true
		end
	end

	local downStart = moveTrace.HitPos
	local downEnd = Vector(downStart.x, downStart.y, startPos.z - stepHeight - SDK_MOVE_HEIGHT_EPSILON)
	local downTrace = self:TraceSdkMoveHull(downStart, downEnd)
	if downTrace.Fraction == 1 then
		return startPos, true
	end

	local endPoint = downTrace.HitPos
	endPoint.z = endPoint.z + SDK_MOVE_HEIGHT_EPSILON
	return endPoint, false
end

function ENT:GetSdkGroundProbeAdjust(pos, desiredEnd)
	if not isvector(pos) or not isvector(desiredEnd) then return 1, false end

	local flatDelta = Vector(desiredEnd.x - pos.x, desiredEnd.y - pos.y, 0)
	local totalDist = flatDelta:Length()
	if totalDist <= 0.001 then return 1, false end

	local moveDir = flatDelta / totalDist
	local remaining = math.min(totalDist, SDK_PREDICTIVE_LOOKAHEAD)
	local probePos = pos
	local adjust = 1
	local foundHeightChange = false

	while remaining > 0.001 do
		local stepSize = math.min(SDK_LOCAL_STEP_SIZE, remaining)
		local nextPos, blocked = self:CheckSdkGroundStep(probePos, moveDir, stepSize)
		local stepAdjust = self:GetSdkHeightAdjustBetween(probePos, nextPos)
		adjust = math.min(adjust, stepAdjust)
		if math.abs(nextPos.z - probePos.z) > 0.5 then
			foundHeightChange = true
		end
		probePos = nextPos
		if blocked then break end
		remaining = remaining - stepSize
	end

	return adjust, foundHeightChange
end

function ENT:GetSdkPredictiveSpeedAdjust(pos)
	local target = self.DebugMoveTarget
	local bestAdjust = 1
	local foundHeightChange = false

	local path = self._FollowPath
	if path and path.IsValid and path:IsValid() then
		local goal = path.GetCurrentGoal and path:GetCurrentGoal() or nil
		local goalPos = istable(goal) and goal.pos or nil
		if isvector(goalPos) then
			bestAdjust = math.min(bestAdjust, self:GetSdkHeightAdjustBetween(pos, goalPos))
			local probeAdjust, probeHeightChange = self:GetSdkGroundProbeAdjust(pos, goalPos)
			bestAdjust = math.min(bestAdjust, probeAdjust)
			foundHeightChange = foundHeightChange or probeHeightChange
		end

		local cursor = path.GetCursorPosition and path:GetCursorPosition() or nil
		local length = path.GetLength and path:GetLength() or nil
		if isnumber(cursor) and isnumber(length) and path.GetPositionOnPath then
			local lookaheadPos = path:GetPositionOnPath(math.min(cursor + SDK_PREDICTIVE_LOOKAHEAD, length))
			if isvector(lookaheadPos) then
				bestAdjust = math.min(bestAdjust, self:GetSdkHeightAdjustBetween(pos, lookaheadPos))
				local probeAdjust, probeHeightChange = self:GetSdkGroundProbeAdjust(pos, lookaheadPos)
				bestAdjust = math.min(bestAdjust, probeAdjust)
				foundHeightChange = foundHeightChange or probeHeightChange
			end
		end
	end

	if isvector(target) then
		bestAdjust = math.min(bestAdjust, self:GetSdkHeightAdjustBetween(pos, target))
		local probeAdjust, probeHeightChange = self:GetSdkGroundProbeAdjust(pos, target)
		bestAdjust = math.min(bestAdjust, probeAdjust)
		foundHeightChange = foundHeightChange or probeHeightChange
	end

	self._SdkProbeFoundHeightChange = foundHeightChange
	return bestAdjust
end

function ENT:GetSdkHeightAdjustedSpeed(baseSpeed)
	local pos = self:GetPos()
	local prev = self._SdkSpeedPrevOrigin2 or self._SdkSpeedPrevOrigin1 or pos
	local reactiveAdjust = self:GetSdkHeightAdjustBetween(prev, pos)
	local predictiveAdjust = self:GetSdkPredictiveSpeedAdjust(pos)

	if reactiveAdjust < (self._SdkReactiveSpeedAdjust or 1) then
		self._SdkReactiveSpeedAdjust = (self._SdkReactiveSpeedAdjust or 1) * 0.2 + reactiveAdjust * 0.8
	else
		self._SdkReactiveSpeedAdjust = (self._SdkReactiveSpeedAdjust or 1) * 0.5 + reactiveAdjust * 0.5
	end
	self._SdkPredictiveSpeedAdjust = predictiveAdjust

	local finalAdjust = math.min(self._SdkReactiveSpeedAdjust, self._SdkPredictiveSpeedAdjust)
	self.DebugSdkSpeedAdjust = finalAdjust
	self.DebugSdkReactiveSpeedAdjust = self._SdkReactiveSpeedAdjust
	self.DebugSdkPredictiveSpeedAdjust = self._SdkPredictiveSpeedAdjust
	self._SdkSpeedPrevOrigin2 = self._SdkSpeedPrevOrigin1 or pos
	self._SdkSpeedPrevOrigin1 = pos
	return baseSpeed * finalAdjust
end

function ENT:RunBehaviour()
	while self:IsValid() and self:Health() > 0 do
		if self.Commander and IsValid(self.Commander) and self.Commander:Alive() then
			local cmdPos = self.Commander:GetPos()
			local dist = self:GetPos():Distance(cmdPos)
			self.DebugMoveTarget = cmdPos

			if dist > FOLLOW_LOST_DIST then
				self:ClearFollowMoveState(false)
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
					NPCDebug.PrintEntityStatus(self, "moving to " .. self.Commander:Nick())
				end
				self.DebugIdealSpeed = FOLLOW_SPEED_WALK
				self.loco:SetAcceleration(FOLLOW_ACCEL)
				self.loco:SetDeceleration(FOLLOW_DECEL)
				self.loco:SetDesiredSpeed(FOLLOW_SPEED_WALK)
				local path = Path("Chase")
				path:SetMinLookAheadDistance(300)
				path:SetGoalTolerance(FOLLOW_STOP_DIST)
				self._FollowPath = path
				local nextRepath = 0

				local stuckPos = self:GetPos()
				local stuckTime = 0

				while self.Commander and IsValid(self.Commander) and self.Commander:Alive() do
					cmdPos = self.Commander:GetPos()
					dist = self:GetPos():Distance(cmdPos)
					self.DebugMoveTarget = cmdPos

					if dist > FOLLOW_LOST_DIST then
						self:ClearFollowMoveState(false)
						break
					end
					if dist <= FOLLOW_STOP_DIST then
						self:ClearFollowMoveState(false)
						break
					end

					self.loco:FaceTowards(cmdPos)
					if CurTime() >= nextRepath then
						path:Chase(self, self.Commander)
						nextRepath = CurTime() + FOLLOW_REPATH_INTERVAL
					end

					local targetFollowSpeed = self:GetSdkHeightAdjustedSpeed(FOLLOW_SPEED_RUN)
					local uphill = self:IsMovingUphill(cmdPos)
					local posZ = self:GetPos().z
					local movingOnStairs = (uphill and self._LastFollowZ and posZ - self._LastFollowZ > 1) or self._SdkProbeFoundHeightChange
					if movingOnStairs then
						self._InStairOverlay = true
					elseif not uphill then
						self._InStairOverlay = false
					end
					self._LastFollowZ = posZ

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
						NPCDebug.PrintEntityStatus(self, "is stuck, retrying...")
						break
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
				self:ClearFollowMoveState(false)
				coroutine.wait(1)
			end
		else
			self.Commander = nil
			self:ClearFollowMoveState(true)
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
	local CONTACT_RELEASE_CYCLE = 0.48
	local STEP_ORIGIN_INTERP_SPEED = 12
	local hullPos = self:GetPos()
	local hullZ = hullPos.z
	if self._VisualRenderZ and math.abs(self._VisualRenderZ - hullZ) > STEP_HEIGHT * 4 then
		self._VisualRenderZ = nil
		self._LastGroundZ = nil
		self._VisualEstIkFloor = nil
		self._VisualIkOffset = nil
	end
	local traceZ = hullZ

	local seqName = self:GetSequenceName(self:GetSequence()) or ""
	local isMovingSeq = seqName:lower():find("walk") or seqName:lower():find("run")

	local activeFoot = isMovingSeq and (getEventContactFoot(self) or "left") or nil
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
	local footDistXY, footDist3D, footDeltaZ
	if leftWorldZ and rightWorldZ then
		local leftMat = self:GetBoneMatrix(lFootBone)
		local rightMat = self:GetBoneMatrix(rFootBone)
		if leftMat and rightMat then
			local leftWorld = leftMat:GetTranslation()
			local rightWorld = rightMat:GetTranslation()
			local footDelta = leftWorld - rightWorld
			footDistXY = Vector(footDelta.x, footDelta.y, 0):Length()
			footDist3D = footDelta:Length()
			footDeltaZ = footDelta.z
		end
	end
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
	if not leftHit and not rightHit then
		NPCDebug.PrintVisualZ(self, "V3ZDBG", {
			activeFoot = activeFoot,
			leftLocalZ = leftLocalZ,
			leftWorldZ = leftWorldZ,
			footDistXY = footDistXY,
			footDist3D = footDist3D,
			footDeltaZ = footDeltaZ,
			rightLocalZ = rightLocalZ,
			rightWorldZ = rightWorldZ
		})
		self:DrawModel()
		return
	end

	if not activeFoot then
		if leftHit and rightHit then
			activeFoot = (leftHit <= rightHit) and "left" or "right"
		elseif leftHit then
			activeFoot = "left"
		elseif rightHit then
			activeFoot = "right"
		else
			activeFoot = "left"
		end
	end

	-- SDK-style visual step origin: only committed animation contact feet feed the
	-- height adjust. Raw swing-foot traces are validation/probes, not render-origin
	-- targets, otherwise stair edges snap the whole model.
	local committedHeights = {}
	local activeAge = activeFoot and getFootContactAge(self, activeFoot) or nil
	local activeHit = (activeFoot == "left") and leftHit or rightHit
	if activeHit and activeAge and activeAge <= CONTACT_RELEASE_CYCLE then
		committedHeights[#committedHeights + 1] = activeHit
	else
		if leftHit and leftPlanted then committedHeights[#committedHeights + 1] = leftHit end
		if rightHit and rightPlanted then committedHeights[#committedHeights + 1] = rightHit end
	end

	local minGroundZ
	local maxGroundZ
	for _, height in ipairs(committedHeights) do
		minGroundZ = minGroundZ and math.min(minGroundZ, height) or height
		maxGroundZ = maxGroundZ and math.max(maxGroundZ, height) or height
	end
	minGroundZ = minGroundZ or self._LastGroundZ
	maxGroundZ = maxGroundZ or minGroundZ

	if minGroundZ and maxGroundZ then
		minGroundZ = math.Clamp(minGroundZ, traceZ - STEP_HEIGHT, traceZ + STEP_HEIGHT)
		maxGroundZ = math.Clamp(maxGroundZ, traceZ - STEP_HEIGHT, traceZ + STEP_HEIGHT)
		self._VisualEstIkFloor = (self._VisualEstIkFloor or minGroundZ) * 0.2 + minGroundZ * 0.8

		local bias = math.Clamp((maxGroundZ - minGroundZ) - STEP_HEIGHT, 0, STEP_HEIGHT)
		local targetOffset = math.Clamp(self._VisualEstIkFloor - hullZ, -STEP_HEIGHT + bias, 0)
		local targetRenderZ = hullZ + targetOffset
		local renderZ = self._VisualRenderZ or targetRenderZ
		local blend = math.Clamp(FrameTime() * STEP_ORIGIN_INTERP_SPEED, 0, 1)
		renderZ = Lerp(blend, renderZ, targetRenderZ)
		self._VisualIkOffset = targetOffset
		self._LastGroundZ = minGroundZ
		self._VisualRenderZ = renderZ
		local newPos = Vector(hullPos.x, hullPos.y, renderZ)
		NPCDebug.PrintVisualZ(self, "V3ZDBG", {
			activeFoot = activeFoot,
			leftLocalZ = leftLocalZ,
			leftWorldZ = leftWorldZ,
			leftHit = leftHit,
			footDistXY = footDistXY,
			footDist3D = footDist3D,
			footDeltaZ = footDeltaZ,
			rightLocalZ = rightLocalZ,
			rightWorldZ = rightWorldZ,
			rightHit = rightHit,
			groundZ = minGroundZ,
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
