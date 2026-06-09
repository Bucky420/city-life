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
local WALK_IDLE_OVERLAY_MIN_WEIGHT = 0.25
local WALK_IDLE_OVERLAY_MAX_WEIGHT = 0.97
local WALK_IDLE_OVERLAY_FADE_RATE = 4.0
local WALK_TO_IDLE_DELAY = 0.15
local VISUAL_STEP_ORIGIN_INTERP_SPEED = 10.5
local VISUAL_IK_FLOOR_BLEND = 0.8
local VISUAL_STEP_ORIGIN_MAX_DOWN = 18

local TURN_GESTURE_COOLDOWN = 0.5
local TURN_GESTURE_MIN_DELTA = 15

local MALE_SHARED_ANIM_MODEL = "models/humans/male_shared.mdl"
local MALE_EVENT_ANIM_MODEL = "models/humans/group03/male_01.mdl"

local function cycleDistance(a, b)
	a = a and (a % 1) or 0
	b = b and (b % 1) or 0
	local d = math.abs(a - b)
	return math.min(d, 1 - d)
end

local function getSequenceGroundRules(model, seqName)
	local seq = StudioIK.GetSequence(model, seqName)
	if not seq then return nil end
	local rules = {}
	local seen = {}
	for _, rule in ipairs(seq.rules or {}) do
		local key = tostring(rule.chain) .. ":" .. tostring(rule.slot)
		if not seen[key] then
			seen[key] = true
			rules[#rules + 1] = rule
		end
	end
	table.sort(rules, function(a, b)
		if a.chain ~= b.chain then return (a.chain or 0) < (b.chain or 0) end
		return (a.contact or a.peak or 0) < (b.contact or b.peak or 0)
	end)
	return rules
end

local function getFootIkRule(ent, side)
	local seqName = ent:GetSequenceName(ent:GetSequence())
	local rules = getSequenceGroundRules(MALE_SHARED_ANIM_MODEL, seqName) or getSequenceGroundRules(ent:GetModel(), seqName)
	if not rules or #rules == 0 then return nil end

	local wantedChain = (side == "left") and 3 or 2
	local baseRule
	for _, rule in ipairs(rules) do
		if rule.chain == wantedChain then
			baseRule = rule
			break
		end
	end
	if not baseRule then
		local index = (side == "right" and #rules >= 2) and 2 or 1
		baseRule = rules[index]
	end
	if not baseRule then return nil end

	local poseValues = ent._VisualPoseValues
	local contactCycle = baseRule.contact or baseRule.peak or baseRule.start or 0
	local rule, dist = StudioIK.GetBlendedGroundRule(MALE_SHARED_ANIM_MODEL, seqName, contactCycle, poseValues)
	if rule then return rule, dist end
	return StudioIK.GetBlendedGroundRule(ent:GetModel(), seqName, contactCycle, poseValues)
end

local function getRuleActiveFoot(ent, leftRule, rightRule)
	local cycle = ent:GetCycle()
	local leftActive = FootIK.IsCycleInRelease(leftRule, cycle)
	local rightActive = FootIK.IsCycleInRelease(rightRule, cycle)
	if leftActive and not rightActive then return "left" end
	if rightActive and not leftActive then return "right" end

	local leftContact = leftRule and (leftRule.contact or leftRule.peak or leftRule.start)
	local rightContact = rightRule and (rightRule.contact or rightRule.peak or rightRule.start)
	if leftContact and rightContact then
		return cycleDistance(cycle, leftContact) <= cycleDistance(cycle, rightContact) and "left" or "right"
	end
	return leftRule and "left" or (rightRule and "right" or nil)
end

local function getRulePushFraction(rule, cycle)
	if not rule then return 0 end

	local peak = rule.peak or rule.start or 0
	local tail = rule.tail or peak
	if tail < peak then tail = tail + 1 end
	if cycle < peak then cycle = cycle + 1 end
	if cycle <= peak then return 0 end
	if cycle >= tail then return 1 end

	local t = math.Clamp((cycle - peak) / math.max(tail - peak, 0.001), 0, 1)
	-- Leg push should start subtle, then accelerate as the support leg straightens.
	return t * t * (3 - 2 * t)
end

local function normalizedCycle(value)
	if not isnumber(value) then return nil end
	return value % 1
end

local function fmtCycle(value)
	if not isnumber(value) then return "?" end
	return string.format("%.3f", normalizedCycle(value))
end

local function fmtRaw(value)
	return isnumber(value) and string.format("%.3f", value) or tostring(value)
end

local function footSideFromIkChain(chain)
	if chain == 3 then return "left" end
	if chain == 2 then return "right" end
	return "?"
end

local function addUniqueModel(list, seen, model)
	if not model or model == "" or seen[model] then return end
	seen[model] = true
	list[#list + 1] = model
end

local function printWalkTimingDebug(prefix, model, seqName)
	model = (model and model ~= "") and model or MALE_SHARED_ANIM_MODEL
	seqName = (seqName and seqName ~= "") and seqName or "walk_all"
	prefix = prefix or "V3TIMING"

	print(string.format("[%s] model=%s seq=%s", prefix, tostring(model), tostring(seqName)))

	local models = {}
	local seenModels = {}
	addUniqueModel(models, seenModels, model)
	addUniqueModel(models, seenModels, MALE_EVENT_ANIM_MODEL)
	addUniqueModel(models, seenModels, MALE_SHARED_ANIM_MODEL)

	local function printEventsForModel(checkModel, modelInfo)
		local printed = false
		if modelInfo and modelInfo.Sequences then
			for _, seq in ipairs(modelInfo.Sequences) do
				if seq.Name == seqName then
					for _, ev in ipairs(seq.Events or {}) do
					local side = ({ [6004] = "left", [6005] = "right", [6006] = "left", [6007] = "right" })[ev.Event] or "?"
					local name = ({ [6004] = "step", [6005] = "step", [6006] = "mat", [6007] = "mat" })[ev.Event] or "event"
					print(string.format("[%s] event id=%s side=%s name=%s cycle=%s raw=%s options=%s", prefix, tostring(ev.Event), side, name, fmtCycle(ev.Cycle), tostring(ev.Cycle), tostring(ev.Options or "")))
						printed = true
					end
					break
				end
			end
		end
		return printed
	end

	for _, sourceModel in ipairs(models) do
		print(string.format("[%s] source model=%s", prefix, sourceModel))

		local foundEvents = printEventsForModel(sourceModel, util.GetModelInfo(sourceModel))
		if not foundEvents then
			print(string.format("[%s] event none model=%s", prefix, sourceModel))
		end

		local seq = StudioIK.GetSequence(sourceModel, seqName)
		if not seq or not seq.rules or #seq.rules == 0 then
			print(string.format("[%s] ik none model=%s", prefix, sourceModel))
		else
			for i, rule in ipairs(seq.rules or {}) do
				print(string.format(
					"[%s] ik[%d] model=%s side=%s chain=%s slot=%s contact=%s start=%s peak=%s tail=%s end=%s rawContact=%s rawStart=%s rawPeak=%s rawTail=%s rawEnd=%s floor=%s height=%s radius=%s",
					prefix, i, sourceModel, footSideFromIkChain(rule.chain), tostring(rule.chain), tostring(rule.slot), fmtCycle(rule.contact), fmtCycle(rule.start), fmtCycle(rule.peak), fmtCycle(rule.tail), fmtCycle(rule.finish),
					fmtRaw(rule.contact), fmtRaw(rule.start), fmtRaw(rule.peak), fmtRaw(rule.tail), fmtRaw(rule.finish), tostring(rule.floor), tostring(rule.height), tostring(rule.radius)
				))
			end
		end
	end
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

local function normalizeMoveYaw(yaw)
	yaw = (yaw + 180) % 360 - 180
	return yaw
end

local function getSequenceMoveYaw(ent)
	if not ent.GetSequenceMoveYaw then return 0 end

	local yaw = ent:GetSequenceMoveYaw(ent:GetSequence())
	if not isnumber(yaw) or math.abs(yaw) > 360 then return 0 end
	return normalizeMoveYaw(yaw)
end

function ENT:_MoveYaw(moveYaw, playbackRate)
	moveYaw = normalizeMoveYaw(tonumber(moveYaw) or 0)
	playbackRate = math.max(tonumber(playbackRate) or 1, 0)

	if self.SetPoseParameter then
		self:SetPoseParameter("move_yaw", moveYaw)
		if self.InvalidateBoneCache then self:InvalidateBoneCache() end
	end

	self:SetPlaybackRate(playbackRate)
	self:FrameAdvance()

	if self.DebugEnabled and CurTime() >= (self.NextPoseDebugPrint or 0) then
		self.NextPoseDebugPrint = CurTime() + 0.25
		print(string.format(
			"[V3POSESV #%d] seq=%d:%s inYaw=%.3f pb=%.2f getYaw=%s rangeYaw=%s seqMoveYaw=%s",
			self:EntIndex(), self:GetSequence(), tostring(self:GetSequenceName(self:GetSequence())), moveYaw, playbackRate,
			tostring(self:GetPoseParameter("move_yaw")),
			getPoseRangeDebug(self, "move_yaw"), tostring(getSequenceMoveYaw(self))
		))
	end
end

function ENT:RunMoveYawClone(wantMove, speed, moveVel)
	if not wantMove then
		self:_MoveYaw(0, 1)
		return
	end

	local vel = isvector(moveVel) and moveVel or self.loco:GetVelocity()
	local moveSpeed = math.max(speed or 0, 0)
	local moveYaw = 0
	if moveSpeed > 1 and vel:LengthSqr() > 0.001 then
		moveYaw = normalizeMoveYaw((vel:Angle().y - self:GetAngles().y) - getSequenceMoveYaw(self))
	end
	local groundSpeed = self.GetSequenceGroundSpeed and self:GetSequenceGroundSpeed(self:GetSequence()) or FOLLOW_SPEED_WALK
	local playbackRate = FOLLOW_SPEED_WALK / math.max(groundSpeed, 1)

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
	local actualVel = Vector((pos.x - lastPos.x) / dt, (pos.y - lastPos.y) / dt, 0)
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
	local moveAnimSpeed = actualSpeed > 0.1 and actualSpeed or speed
	local moveAnimVel = actualSpeed > 0.1 and actualVel or vel
	self._WalkIdleOverlayMoveSpeed = moveAnimSpeed
	self:RunMoveYawClone(wantMove, moveAnimSpeed, moveAnimVel)
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

	local targetWeight = math.Clamp(1 - ((moveSpeed or 0) / FOLLOW_SPEED_WALK), WALK_IDLE_OVERLAY_MIN_WEIGHT, WALK_IDLE_OVERLAY_MAX_WEIGHT)
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

					self.loco:Approach(cmdPos, 1)
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

concommand.Remove("citynpc_v3_walk_timing")
concommand.Add("citynpc_v3_walk_timing", function(ply, _, args)
	if not IsValid(ply) then return end

	local model = args and args[1]
	local seqName = args and args[2]
	local ent = ply:GetEyeTrace().Entity
	if (not model or model == "") and IsValid(ent) and ent:GetClass() == "city_anim_final_npc_test3" then
		model = ent:GetModel()
	end
	printWalkTimingDebug("V3TIMING", model, seqName or "walk_all")
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

concommand.Remove("citynpc_v3_walk_timing_client")
concommand.Add("citynpc_v3_walk_timing_client", function(_, _, args)
	local model = args and args[1]
	local seqName = args and args[2]
	local ent = LocalPlayer and IsValid(LocalPlayer()) and LocalPlayer():GetEyeTrace().Entity or nil
	if (not model or model == "") and IsValid(ent) and ent:GetClass() == "city_anim_final_npc_test3" then
		model = ent:GetModel()
	end
	printWalkTimingDebug("V3TIMING CLIENT", model, seqName or "walk_all")
end)

function ENT:Draw()
	self:SetIK(true)
	self:SetupBones()

	local lFootBone = self:LookupBone("ValveBiped.Bip01_L_Foot")
	local rFootBone = self:LookupBone("ValveBiped.Bip01_R_Foot")

	local STEP_HEIGHT = 18
	local HULL_R = 2.5
	local STEP_ORIGIN_INTERP_SPEED = VISUAL_STEP_ORIGIN_INTERP_SPEED
	local IK_FLOOR_BLEND = VISUAL_IK_FLOOR_BLEND
	local hullPos = self:GetPos()
	local hullZ = hullPos.z
	local prevHullZ = self._LastVisualHullZ or hullZ
	local hullRising = hullZ > prevHullZ + 0.1
	self._LastVisualHullZ = hullZ
	if self._VisualRenderZ and math.abs(self._VisualRenderZ - hullZ) > STEP_HEIGHT * 4 then
		self._VisualRenderZ = nil
		self._LastGroundZ = nil
		self._VisualEstIkFloor = nil
		self._VisualIkOffset = nil
	end
	local traceZ = hullZ

	local seqName = self:GetSequenceName(self:GetSequence()) or ""
	local isMovingSeq = seqName:lower():find("walk") or seqName:lower():find("run")

	local leftRule = getFootIkRule(self, "left")
	local rightRule = getFootIkRule(self, "right")
	local activeFoot = isMovingSeq and getRuleActiveFoot(self, leftRule, rightRule) or nil
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
	-- Trace from the IK rule ground target, using the rule floor/height/radius
	-- parsed from the studio model.
	local function doTrace(bone, rule)
		if not bone then return nil end
		local mat = self:GetBoneMatrix(bone)
		if not mat then return nil end
		local footPos = mat:GetTranslation()
		local radius = HULL_R
		local height = STEP_HEIGHT + 2
		local floorZ = traceZ
		if rule then
			radius = math.max(rule.radius or radius, 1)
			height = math.max(rule.height or height, 1)
			floorZ = hullZ + (rule.floor or 0)
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

	local leftHit = doTrace(lFootBone, leftRule)
	local rightHit = doTrace(rFootBone, rightRule)
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

	-- SDK-style visual step origin: parsed rules drive a small per-foot latch
	-- state, while traces only provide ground heights for active contact windows.
	local activeRule = (activeFoot == "left") and leftRule or rightRule
	local committedHeights = FootIK.GetCommittedHeights(self, {
		activeFoot = activeFoot,
		cycle = self:GetCycle(),
		leftHit = leftHit,
		rightHit = rightHit,
		leftRule = leftRule,
		rightRule = rightRule
	})
	local minGroundZ, maxGroundZ = FootIK.MinMax(committedHeights)
	maxGroundZ = maxGroundZ or minGroundZ
	if currentMaxHit then
		maxGroundZ = maxGroundZ and math.max(maxGroundZ, currentMaxHit) or currentMaxHit
	end
	if minGroundZ and currentMaxHit and hullRising and hullZ - minGroundZ > STEP_HEIGHT * 0.1 and currentMaxHit > minGroundZ + 1 and currentMaxHit <= hullZ + 1 then
		-- GLua NextBot hulls step up before the IK rule switches feet. Shape the
		-- higher-tread takeover by IK rule phase so the visual body follows the
		-- support-leg push: slow at first, then fast as the leg straightens.
		local push = getRulePushFraction(activeRule, self:GetCycle())
		if push > 0 then
			minGroundZ = Lerp(push, minGroundZ, currentMaxHit)
		end
	end

	if minGroundZ and maxGroundZ then
		minGroundZ = math.Clamp(minGroundZ, traceZ - STEP_HEIGHT, traceZ + STEP_HEIGHT)
		maxGroundZ = math.Clamp(maxGroundZ, traceZ - STEP_HEIGHT, traceZ + STEP_HEIGHT)
		self._VisualEstIkFloor = (self._VisualEstIkFloor or minGroundZ) * (1 - IK_FLOOR_BLEND) + minGroundZ * IK_FLOOR_BLEND

		local bias = math.Clamp((maxGroundZ - minGroundZ) - STEP_HEIGHT, 0, STEP_HEIGHT)
		local targetOffset = math.Clamp(self._VisualEstIkFloor - hullZ, -VISUAL_STEP_ORIGIN_MAX_DOWN + bias, 0)
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
			ikRuleStart = activeRule and activeRule.start,
			ikRulePeak = activeRule and activeRule.peak,
			ikRuleTail = activeRule and activeRule.tail,
			ikRuleEnd = activeRule and activeRule.finish,
			ikRuleBlend = activeRule and activeRule.blendSource,
			ikRuleWeight = activeRule and activeRule.blendWeight,
			renderZ = renderZ
		})

		self:SetRenderOrigin(newPos)
		self:SetupBones()
		self:DrawModel()
		self:SetRenderOrigin(nil)
	else
		-- SDK UpdateStepOrigin decays the previous IK offset when contact is stale
		-- instead of snapping the render origin straight back to the hull.
		self._VisualIkOffset = (self._VisualIkOffset or 0) * 0.5
		self._VisualEstIkFloor = hullZ
		local renderZ = hullZ + self._VisualIkOffset
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
