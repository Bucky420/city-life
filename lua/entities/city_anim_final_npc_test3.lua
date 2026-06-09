AddCSLuaFile()
AddCSLuaFile("entities/modules/npc_debug.lua")
AddCSLuaFile("entities/modules/studio_ik.lua")
AddCSLuaFile("entities/modules/foot_ik.lua")
include("entities/modules/npc_debug.lua")
include("entities/modules/studio_ik.lua")
include("entities/modules/foot_ik.lua")

local NPCDebug = CityNPCs.Modules.npc_debug
local StudioIK = CityNPCs.Modules.studio_ik
local FootIK = CityNPCs.Modules.foot_ik

ENT.Type = "nextbot"
ENT.Base = "base_nextbot"

ENT.PrintName = "Final Anim Test NPC v3"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Author = "City NPCs"
ENT.Editable = true

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
local WALK_IDLE_OVERLAY_CYCLE = 0.20
local WALK_TO_IDLE_DELAY = 0.15
local VISUAL_CONTACT_RELEASE_CYCLE = 0.48
local VISUAL_STEP_ORIGIN_INTERP_SPEED = 12
local VISUAL_SWING_PROBE_SCALE = 4
local VISUAL_IK_FLOOR_BLEND = 0.8
local VISUAL_IK_CONTACT_TIMEOUT = 0.2
local VISUAL_DOWN_STEP_MAX_SPEED = 72
local VISUAL_UP_STEP_MAX_SPEED = 240

local TURN_GESTURE_COOLDOWN = 0.5
local TURN_GESTURE_MIN_DELTA = 15

-- Citizen footstep events mark which foot should be treated as the current
-- contact foot for stair/IK checks. Source defines regular footsteps as
-- 6004/6005 and material-based footsteps as 6006/6007.
local FOOTSTEP_EVENT_LEFT = 6004
local FOOTSTEP_EVENT_RIGHT = 6005
local FOOTSTEP_EVENT_MAT_LEFT = 6006
local FOOTSTEP_EVENT_MAT_RIGHT = 6007
local MALE_SHARED_ANIM_MODEL = "models/humans/male_shared.mdl"
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

local function getFootIkRule(ent, side)
	local cache = getModelFootCycles(ent:GetModel())
	local seqName = ent:GetSequenceName(ent:GetSequence())
	local footCycle = cache and cache[seqName]
	if not footCycle or not footCycle[side] then return nil end
	local poseValues = ent._VisualPoseValues
	local rule, dist = StudioIK.GetBlendedGroundRule(MALE_SHARED_ANIM_MODEL, seqName, footCycle[side], poseValues)
	if rule then return rule, dist end
	return StudioIK.GetBlendedGroundRule(ent:GetModel(), seqName, footCycle[side], poseValues)
end

local function getTunableFloat(ent, getterName, default, minValue, maxValue)
	local getter = ent[getterName]
	local value = getter and getter(ent) or default
	if not isnumber(value) then value = default end
	if value <= 0 then value = default end
	return math.Clamp(value, minValue, maxValue)
end

local function getNormalizedPoseParameter(ent, name)
	local value = ent:GetPoseParameter(name)
	if not isnumber(value) then return nil end

	-- GetPoseParameter is already normalized on the client, but returns the
	-- actual pose range on the server. Studio_SeqAnims expects normalized input.
	if SERVER and ent.GetPoseParameterRange then
		local minValue, maxValue = ent:GetPoseParameterRange(name)
		if isnumber(minValue) and isnumber(maxValue) and math.abs(maxValue - minValue) > 0.0001 then
			value = (value - minValue) / (maxValue - minValue)
		end
	end

	return math.Clamp(value, 0, 1)
end

local function getPoseRangeDebug(ent, name)
	if not ent.GetPoseParameterRange then return "?:?" end
	local minValue, maxValue = ent:GetPoseParameterRange(name)
	return tostring(minValue) .. ":" .. tostring(maxValue)
end

local function angleDiff(destAngle, srcAngle)
	local delta = (destAngle - srcAngle) % 360
	if delta > 180 then delta = delta - 360 end
	return delta
end

local function refreshVisualPoseValues(ent)
	if not ent.GetPoseParameter then return nil end
	local seqName = ent:GetSequenceName(ent:GetSequence())
	local seq = StudioIK.GetSequence(MALE_SHARED_ANIM_MODEL, seqName) or StudioIK.GetSequence(ent:GetModel(), seqName)
	if not seq or not seq.paramIndex then return nil end

	local values = {}
	local data = StudioIK.LoadModel(MALE_SHARED_ANIM_MODEL) or StudioIK.LoadModel(ent:GetModel())
	for _, poseIndex in ipairs(seq.paramIndex) do
		local pose = data and data.poseParams and data.poseParams[poseIndex]
		if pose and pose.name and pose.name ~= "" then
			local value = getNormalizedPoseParameter(ent, pose.name)
			if isnumber(value) then
				values[pose.name] = value
				values[poseIndex] = value
			end
		end
	end
	ent._VisualPoseValues = values
	return values
end

function ENT:SetupDataTables()
	self:NetworkVar("Float", 0, "VisualContactReleaseCycle", {
		KeyName = "visual_contact_release_cycle",
		Edit = { type = "Float", min = 0.05, max = 1.0, order = 1, category = "Visual Step" }
	})
	self:NetworkVar("Float", 1, "VisualStepInterpSpeed", {
		KeyName = "visual_step_interp_speed",
		Edit = { type = "Float", min = 1, max = 30, order = 2, category = "Visual Step" }
	})
	self:NetworkVar("Float", 2, "VisualSwingProbeScale", {
		KeyName = "visual_swing_probe_scale",
		Edit = { type = "Float", min = 0.1, max = 12, order = 3, category = "Visual Step" }
	})
	self:NetworkVar("Float", 3, "VisualIkFloorBlend", {
		KeyName = "visual_ik_floor_blend",
		Edit = { type = "Float", min = 0.05, max = 1.0, order = 4, category = "Visual Step" }
	})
	self:NetworkVar("Float", 4, "VisualStepMaxSpeed", {
		KeyName = "visual_step_max_speed",
		Edit = { type = "Float", min = 1, max = 240, order = 5, category = "Visual Step" }
	})
end

function ENT:CanEditVariables(ply)
	return IsValid(ply) and ply:IsAdmin()
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
	self:SetVisualContactReleaseCycle(VISUAL_CONTACT_RELEASE_CYCLE)
	self:SetVisualStepInterpSpeed(VISUAL_STEP_ORIGIN_INTERP_SPEED)
	self:SetVisualSwingProbeScale(VISUAL_SWING_PROBE_SCALE)
	self:SetVisualIkFloorBlend(VISUAL_IK_FLOOR_BLEND)
	self:SetVisualStepMaxSpeed(VISUAL_DOWN_STEP_MAX_SPEED)

	self:StartActivity(ACT_IDLE)

	self.Commander = nil
	self.NextTurnTime = 0
	self.DebugEnabled = false
	self.NextDebugPrint = 0
	self.NextPoseDebugPrint = 0
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

function ENT:_MoveYaw(moveYaw, playbackRate)
	moveYaw = math.Clamp(tonumber(moveYaw) or 0, -180, 180)
	playbackRate = math.max(tonumber(playbackRate) or 1, 0)

	if self.SetPoseParameter then
		self:SetPoseParameter("move_yaw", moveYaw)
		if self.InvalidateBoneCache then self:InvalidateBoneCache() end
	end

	self:SetPlaybackRate(playbackRate)
	self:FrameAdvance()

	if self.DebugEnabled and CurTime() >= (self.NextPoseDebugPrint or 0) then
		local seq = self:GetSequence()
		local seqName = tostring(self:GetSequenceName(seq))
		local stillIdle = not self._UsingWalkActivity and math.abs(moveYaw) < 0.01 and math.abs(playbackRate - 1) < 0.01
		local state = string.format("%d:%s:%.2f:%.2f", seq, seqName, moveYaw, playbackRate)
		if stillIdle and self._LastPoseDebugState == state then return end

		self._LastPoseDebugState = state
		self.NextPoseDebugPrint = CurTime() + (stillIdle and 2 or 0.25)
		print(string.format(
			"[V3POSESV #%d] seq=%d:%s yawIn=%.2f pb=%.2f getYaw=%s rangeYaw=%s seqMoveYaw=%s",
			self:EntIndex(), seq, seqName, moveYaw, playbackRate,
			tostring(self:GetPoseParameter("move_yaw")), getPoseRangeDebug(self, "move_yaw"),
			tostring(self.GetSequenceMoveYaw and self:GetSequenceMoveYaw(seq) or nil)
		))
	end
end

function ENT:RunMoveYawClone(wantMove, speed)
	if not wantMove then
		self:_MoveYaw(0, 1)
		return
	end

	local vel = self.loco:GetVelocity()
	local moveSpeed = math.max(speed or 0, 0)
	local seq = self:GetSequence()
	local playbackRate = 1
	local moveYaw = 0

	if moveSpeed > 1 then
		local seqMoveYaw = self.GetSequenceMoveYaw and self:GetSequenceMoveYaw(seq) or 0
		if not isnumber(seqMoveYaw) or math.abs(seqMoveYaw) > 360 then seqMoveYaw = 0 end
		moveYaw = angleDiff(vel:Angle().y, self:GetAngles().y + seqMoveYaw)
	end

	self:_MoveYaw(moveYaw, playbackRate)
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
		if act ~= ACT_WALK then
			self:StartActivity(ACT_WALK)
		end
		self._UsingWalkActivity = true
	elseif self._UsingWalkActivity or act ~= ACT_IDLE then
		self._UsingWalkActivity = nil
		self:StartActivity(ACT_IDLE)
	end

	self._WalkIdleOverlayWanted = wantMove
	self._WalkIdleOverlayMoveSpeed = speed
	self:RunMoveYawClone(wantMove, speed)
	refreshVisualPoseValues(self)
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
	self._WalkIdleSequence = nil
	if layerId and self.IsValidLayer and self:IsValidLayer(layerId) and self.RemoveLayer then
		if self.SetLayerBlendIn then self:SetLayerBlendIn(layerId, 0) end
		if self.SetLayerBlendOut then self:SetLayerBlendOut(layerId, 0) end
		self:RemoveLayer(layerId)
	end
end

function ENT:FindWalkIdleOverlayLayer(seqIdx)
	if not self.IsValidLayer or not self.GetLayerSequence then return nil end

	local tracked = self._WalkIdleLayer
	local keepLayer = tracked and self:IsValidLayer(tracked) and self:GetLayerSequence(tracked) == seqIdx and tracked or nil

	for layerId = 0, 15 do
		if self:IsValidLayer(layerId) and self:GetLayerSequence(layerId) == seqIdx then
			if not keepLayer then
				keepLayer = layerId
			elseif layerId ~= keepLayer and self.RemoveLayer then
				if self.SetLayerBlendIn then self:SetLayerBlendIn(layerId, 0) end
				if self.SetLayerBlendOut then self:SetLayerBlendOut(layerId, 0) end
				if self.SetLayerWeight then self:SetLayerWeight(layerId, 0) end
				self:RemoveLayer(layerId)
			end
		end
	end

	self._WalkIdleLayer = keepLayer
	return keepLayer
end

function ENT:UpdateWalkIdleOverlay(wantMove, moveSpeed, interval)
	if not wantMove then
		self._WalkIdleOverlayWeight = 0
		self._WalkIdleOverlayTargetWeight = 0
		self._WalkIdleOverlayRawWeight = 0
		self:ClearWalkIdleOverlay()
		return
	end

	local seqIdx = self._WalkIdleSequence
	if not seqIdx or seqIdx < 0 or (self._WalkIdleOverlayWeight or 0) < 0.02 then
		seqIdx = self:LookupSequence("idle_subtle")
		if not seqIdx or seqIdx < 0 then
			seqIdx = self.SelectWeightedSequence and self:SelectWeightedSequence(ACT_IDLE) or -1
		end
		self._WalkIdleSequence = seqIdx
	end
	if not seqIdx or seqIdx < 0 then return end

	local layerId = self:FindWalkIdleOverlayLayer(seqIdx) or self._WalkIdleLayer
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

	local seq = self:GetSequence()
	local groundSpeed = self.GetSequenceGroundSpeed and self:GetSequenceGroundSpeed(seq) or FOLLOW_SPEED_WALK
	if not isnumber(groundSpeed) or groundSpeed < 0.001 then groundSpeed = FOLLOW_SPEED_WALK end
	local playbackRate = math.Clamp((moveSpeed or 0) / math.max(groundSpeed, 0.001), 0.01, 10)
	local targetWeight = math.Clamp(1 - playbackRate, 0, 1)
	self._WalkIdleOverlayRawWeight = targetWeight
	self._WalkIdleOverlayTargetWeight = targetWeight
	self._WalkIdleOverlayWeight = targetWeight

	if self.SetLayerPriority then self:SetLayerPriority(layerId, 1) end
	if self.SetLayerWeight then self:SetLayerWeight(layerId, self._WalkIdleOverlayWeight) end
	if self.SetLayerPlaybackRate then self:SetLayerPlaybackRate(layerId, 0) end
	if self.SetLayerCycle then self:SetLayerCycle(layerId, WALK_IDLE_OVERLAY_CYCLE) end
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
				self._FollowPath = nil

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

					local targetFollowSpeed = self:GetSdkHeightAdjustedSpeed(FOLLOW_SPEED_RUN)
					local posZ = self:GetPos().z
					local movingOnStairs = (self._LastFollowZ and math.abs(posZ - self._LastFollowZ) > 1) or self._SdkProbeFoundHeightChange
					if movingOnStairs then
						self._InStairOverlay = true
					else
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

					-- SDK NextBotGroundLocomotion::ApplyAccumulatedApproach flattens
					-- Approach goals to the current feet Z; ground constraints solve stairs.
					local approachPos = Vector(cmdPos.x, cmdPos.y, self:GetPos().z)
					self.loco:Approach(approachPos, 1)
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

concommand.Remove("citynpc_v3_ikdebug")
concommand.Add("citynpc_v3_ikdebug", function(ply, _, args)
	if not IsValid(ply) then return end

	local model = args and args[1]
	local seqName = args and args[2]
	local ent = ply:GetEyeTrace().Entity

	if not model or model == "" then
		model = MALE_SHARED_ANIM_MODEL
	end
	StudioIK.ClearCache(model)
	if (not seqName or seqName == "") and IsValid(ent) and ent:GetClass() == "city_anim_final_npc_test3" then
		seqName = ent:GetSequenceName(ent:GetSequence())
		print(string.format("[StudioIK] eyeTrace entity=%s seq=%d:%s entityModel=%s", ent:GetClass(), ent:GetSequence(), tostring(seqName), tostring(ent:GetModel())))
	end

	for _, line in ipairs(StudioIK.GetDebugLines(model, seqName)) do
		print(line)
	end
end)

concommand.Remove("citynpc_v3_ikdump")
concommand.Add("citynpc_v3_ikdump", function(ply, _, args)
	if not IsValid(ply) then return end

	local model = args and args[1]
	if not model or model == "" then
		model = MALE_SHARED_ANIM_MODEL
	end
	StudioIK.ClearCache(model)
	for _, line in ipairs(StudioIK.GetDumpLines(model)) do
		print(line)
	end
end)

end

if CLIENT then

function ENT:CityDebugLabel()
	return "v3-nextbot"
end

concommand.Remove("citynpc_v3_ikdebug_client")
concommand.Add("citynpc_v3_ikdebug_client", function(_, _, args)
	local model = args and args[1]
	local seqName = args and args[2]
	local ent = LocalPlayer and IsValid(LocalPlayer()) and LocalPlayer():GetEyeTrace().Entity or nil

	if not model or model == "" then
		model = MALE_SHARED_ANIM_MODEL
	end
	StudioIK.ClearCache(model)
	if (not seqName or seqName == "") and IsValid(ent) and ent:GetClass() == "city_anim_final_npc_test3" then
		seqName = ent:GetSequenceName(ent:GetSequence())
		print(string.format("[StudioIK CLIENT] eyeTrace entity=%s seq=%d:%s entityModel=%s", ent:GetClass(), ent:GetSequence(), tostring(seqName), tostring(ent:GetModel())))
	end

	for _, line in ipairs(StudioIK.GetDebugLines(model, seqName)) do
		print(line:gsub("%[StudioIK%]", "[StudioIK CLIENT]"))
	end
end)

concommand.Remove("citynpc_v3_ikdump_client")
concommand.Add("citynpc_v3_ikdump_client", function(_, _, args)
	local model = args and args[1]
	if not model or model == "" then
		model = MALE_SHARED_ANIM_MODEL
	end
	StudioIK.ClearCache(model)
	for _, line in ipairs(StudioIK.GetDumpLines(model)) do
		print(line:gsub("%[StudioIKDUMP%]", "[StudioIKDUMP CLIENT]"))
	end
end)

function ENT:Draw()
	self:SetIK(true)
	self:SetupBones()

	local lFootBone = self:LookupBone("ValveBiped.Bip01_L_Foot")
	local rFootBone = self:LookupBone("ValveBiped.Bip01_R_Foot")

	local STEP_HEIGHT = 18
	local HULL_R = 2.5
	local PLANTED_FOOT_Z = 5.5
	local CONTACT_RELEASE_CYCLE = getTunableFloat(self, "GetVisualContactReleaseCycle", VISUAL_CONTACT_RELEASE_CYCLE, 0.05, 1.0)
	local SWING_PROBE_SCALE = getTunableFloat(self, "GetVisualSwingProbeScale", VISUAL_SWING_PROBE_SCALE, 0.1, 12)
	local IK_FLOOR_BLEND = VISUAL_IK_FLOOR_BLEND
	local DOWN_STEP_MAX_SPEED = getTunableFloat(self, "GetVisualStepMaxSpeed", VISUAL_DOWN_STEP_MAX_SPEED, 1, 240)
	local hullPos = self:GetPos()
	local hullZ = hullPos.z
	self._LastVisualHullZ = hullZ
	if self._VisualRenderZ and math.abs(self._VisualRenderZ - hullZ) > STEP_HEIGHT * 4 then
		self._VisualRenderZ = nil
		self._LastGroundZ = nil
		self._LastGroundMaxZ = nil
		self._LastGroundTime = nil
		self._VisualEstIkFloor = nil
		self._VisualIkOffset = nil
	end
	local traceZ = hullZ

	local seqName = self:GetSequenceName(self:GetSequence()) or ""
	local isMovingSeq = seqName:lower():find("walk") or seqName:lower():find("run")

	local activeFoot = isMovingSeq and (getEventContactFoot(self) or "left") or nil
	local fwd = self:GetForward()
	local flatForward = Vector(fwd.x, fwd.y, 0):GetNormalized()
	local vel = self:GetVelocity()
	local flatVelocity = Vector(vel.x, vel.y, 0)
	local probeDir = flatVelocity:Length() > 5 and flatVelocity:GetNormalized() or flatForward
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
	local leftRule = getFootIkRule(self, "left")
	local rightRule = getFootIkRule(self, "right")

	-- SDK IK_GROUND traces from the animation target XY, anchored at abs origin
	-- plus the rule floor, with the rule's height/radius defining the sweep.
	local function doTrace(bone, side, planted, rule)
		if not bone then return nil end
		local mat = self:GetBoneMatrix(bone)
		if not mat then return nil end
		local footPos = mat:GetTranslation()
		local radius = HULL_R
		local height = STEP_HEIGHT + 2
		local floorZ = footPos.z

		if rule then
			radius = math.max(rule.radius or radius, 1)
			height = math.max(rule.height or height, 1)
			floorZ = hullZ + (rule.floor or 0)
		else
			local probeScale = (isMovingSeq and not planted) and getFootSwingProbeScale(self, side) or 0
			footPos = footPos + probeDir * (probeScale * SWING_PROBE_SCALE)
			floorZ = traceZ
		end

		local tr = util.TraceHull({
			start = Vector(footPos.x, footPos.y, floorZ + height),
			endpos = Vector(footPos.x, footPos.y, floorZ - height),
			mins = Vector(-radius, -radius, 0),
			maxs = Vector(radius, radius, radius * 2),
			filter = self,
			mask = MASK_SOLID
		})
		if not tr.Hit or tr.HitPos.z > traceZ + STEP_HEIGHT then return nil end
		return tr.HitPos.z
	end

	local leftHit = doTrace(lFootBone, "left", leftPlanted, leftRule)
	local rightHit = doTrace(rFootBone, "right", rightPlanted, rightRule)
	local currentMinHit
	local currentMaxHit
	if leftHit then
		currentMinHit = leftHit
		currentMaxHit = leftHit
	end
	if rightHit then
		currentMinHit = currentMinHit and math.min(currentMinHit, rightHit) or rightHit
		currentMaxHit = currentMaxHit and math.max(currentMaxHit, rightHit) or rightHit
	end
	if not leftHit and not rightHit then
		self._VisualIkOffset = (self._VisualIkOffset or 0) * 0.5
		self._VisualEstIkFloor = hullZ
		self._LastGroundZ = nil
		self._LastGroundMaxZ = nil
		self._LastGroundTime = nil
		local renderZ = hullZ + self._VisualIkOffset
		self._VisualRenderZ = renderZ
		NPCDebug.PrintVisualZ(self, "V3ZDBG", {
			activeFoot = activeFoot,
			leftLocalZ = leftLocalZ,
			leftWorldZ = leftWorldZ,
			footDistXY = footDistXY,
			footDist3D = footDist3D,
			footDeltaZ = footDeltaZ,
			rightLocalZ = rightLocalZ,
			rightWorldZ = rightWorldZ,
			renderZ = renderZ
		})
		if math.abs(self._VisualIkOffset) > 0.01 then
			self:SetRenderOrigin(Vector(hullPos.x, hullPos.y, renderZ))
			self:SetupBones()
			self:DrawModel()
			self:SetRenderOrigin(nil)
		else
			self:DrawModel()
		end
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
	local activeRule = (activeFoot == "left") and leftRule or rightRule

	-- SDK-style visual step origin: parsed rules drive a small per-foot latch
	-- state, while traces only provide ground heights for active contact windows.
	local ikTargets = FootIK.UpdateTargets(self, {
		activeFoot = activeFoot,
		cycle = self:GetCycle(),
		fallbackWindow = CONTACT_RELEASE_CYCLE,
		leftHit = leftHit,
		rightHit = rightHit,
		leftRule = leftRule,
		rightRule = rightRule,
		leftAge = getFootContactAge(self, "left"),
		rightAge = getFootContactAge(self, "right"),
		leftPlanted = leftPlanted,
		rightPlanted = rightPlanted
	})
	local minGroundZ, maxGroundZ = ikTargets.minZ, ikTargets.maxZ
	local leftTarget = ikTargets.left
	local rightTarget = ikTargets.right
	local activeTarget = ikTargets.active
	if not minGroundZ and self._LastGroundZ and self._LastGroundTime and CurTime() - self._LastGroundTime <= VISUAL_IK_CONTACT_TIMEOUT then
		minGroundZ = self._LastGroundZ
		maxGroundZ = self._LastGroundMaxZ or minGroundZ
	end
	maxGroundZ = maxGroundZ or minGroundZ
	if currentMinHit and minGroundZ and minGroundZ < currentMinHit - SDK_MOVE_HEIGHT_EPSILON then
		-- A foot latch should be stable, but not keep an old lower tread after
		-- both current IK ground traces have moved up to the next tread.
		minGroundZ = currentMinHit
		maxGroundZ = currentMaxHit or currentMinHit
	end

	if minGroundZ and maxGroundZ then
		minGroundZ = math.Clamp(minGroundZ, traceZ - STEP_HEIGHT, traceZ + STEP_HEIGHT)
		maxGroundZ = math.Clamp(maxGroundZ, traceZ - STEP_HEIGHT, traceZ + STEP_HEIGHT)
		local visualGroundZ = minGroundZ
		if not isMovingSeq then
			visualGroundZ = hullZ
		end
		-- SDK InitStepHeightAdjust seeds m_flEstIkFloor from the entity origin;
		-- do not seed from first foot contact or the debounce is bypassed.
		self._VisualEstIkFloor = (self._VisualEstIkFloor or hullZ) * (1 - IK_FLOOR_BLEND) + visualGroundZ * IK_FLOOR_BLEND

		local bias = math.Clamp((maxGroundZ - minGroundZ) - STEP_HEIGHT, 0, STEP_HEIGHT)
		local targetOffset = math.Clamp(self._VisualEstIkFloor - hullZ, -STEP_HEIGHT + bias, 0)
		local targetRenderZ = hullZ + targetOffset
		local prevRenderZ = self._VisualRenderZ or targetRenderZ
		local dt = FrameTime and FrameTime() or 0.015
		local renderZ
		if targetRenderZ < prevRenderZ then
			renderZ = math.max(targetRenderZ, prevRenderZ - DOWN_STEP_MAX_SPEED * dt)
		else
			renderZ = math.min(targetRenderZ, prevRenderZ + VISUAL_UP_STEP_MAX_SPEED * dt)
		end
		renderZ = math.Clamp(renderZ, hullZ - STEP_HEIGHT + bias, hullZ + STEP_HEIGHT)
		self._VisualIkOffset = targetOffset
		self._LastGroundZ = visualGroundZ
		self._LastGroundMaxZ = maxGroundZ
		self._LastGroundTime = CurTime()
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
			groundZ = visualGroundZ,
			estZ = targetRenderZ,
			minGroundZ = minGroundZ,
			maxGroundZ = maxGroundZ,
			ikRuleStart = activeRule and activeRule.start,
			ikRulePeak = activeRule and activeRule.peak,
			ikRuleTail = activeRule and activeRule.tail,
			ikRuleEnd = activeRule and activeRule.finish,
			ikRuleBlend = activeRule and activeRule.blendSource,
			ikRuleWeight = activeTarget and activeTarget.weight or (activeRule and activeRule.blendWeight),
			ikRelease = activeTarget and activeTarget.release,
			ikLatched = activeTarget and activeTarget.latchedAmount,
			leftIkWeight = leftTarget and leftTarget.weight,
			leftIkRelease = leftTarget and leftTarget.release,
			leftIkLatched = leftTarget and leftTarget.latchedAmount,
			leftIkSolved = leftTarget and leftTarget.solvedHeight,
			rightIkWeight = rightTarget and rightTarget.weight,
			rightIkRelease = rightTarget and rightTarget.release,
			rightIkLatched = rightTarget and rightTarget.latchedAmount,
			rightIkSolved = rightTarget and rightTarget.solvedHeight,
			renderZ = renderZ
		})

		self:SetRenderOrigin(newPos)
		self:SetupBones()
		self:DrawModel()
		self:SetRenderOrigin(nil)
	else
		self._VisualIkOffset = (self._VisualIkOffset or 0) * 0.5
		self._VisualEstIkFloor = hullZ
		self._LastGroundZ = nil
		self._LastGroundMaxZ = nil
		self._LastGroundTime = nil
		local targetRenderZ = hullZ + self._VisualIkOffset
		local prevRenderZ = self._VisualRenderZ or targetRenderZ
		local dt = FrameTime and FrameTime() or 0.015
		local renderZ = math.Approach(prevRenderZ, targetRenderZ, DOWN_STEP_MAX_SPEED * dt)
		self._VisualRenderZ = renderZ
		if math.abs(self._VisualIkOffset) > 0.01 then
			self:SetRenderOrigin(Vector(hullPos.x, hullPos.y, renderZ))
			self:SetupBones()
			self:DrawModel()
			self:SetRenderOrigin(nil)
		else
			self:DrawModel()
		end
	end
end

end
