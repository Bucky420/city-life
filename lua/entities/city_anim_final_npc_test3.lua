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
ENT.Category = "Citizens"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Author = "City NPCs"
ENT.Editable = true

ENT.Purpose = "Minimal follow NPC with SetIK(true)"
ENT.Instructions = "Press +USE to recruit. Follows commander."

ENT.FollowStopDist = 48
ENT.FollowLostDist = 30000

ENT.FollowSpeedWalk = 80
ENT.FollowSpeedRun = 80
ENT.FollowAccel = 200
ENT.FollowDecel = 200
ENT.SdkHeightAdjustUpMin = 0.5
ENT.SdkHeightAdjustDownMin = 0.8
ENT.SdkPredictiveLookahead = 96
ENT.SdkLocalStepSize = 16
ENT.SdkMoveHeightEpsilon = 0.0625
ENT.SdkReactiveDownBlend = 0.8
ENT.SdkReactiveUpBlend = 0.5
ENT.WalkIdleOverlayCycle = 0.20
ENT.WalkIdleOverlayMinWeight = 0.25
ENT.WalkIdleOverlayMaxWeight = 0.97
ENT.WalkIdleOverlayFadeRate = 4.0
ENT.FootTraceCenterForwardOffset = 3
ENT.FootIkReleaseFraction = 0.1
ENT.WalkToIdleDelay = 0.15
ENT.StairZDeltaThreshold = 1
ENT.VisualStepOriginInterpSpeed = 10.5
ENT.VisualIkFloorBlend = 0.8
ENT.VisualStepOriginMaxDown = 18
ENT.VisualStepHeight = 18
ENT.VisualTraceHullRadius = 2.5
ENT.VisualTraceExtraHeight = 2
ENT.VisualTraceRadiusShrink = 1
ENT.VisualTraceMinRadius = 1
ENT.VisualRenderResetStepMultiplier = 4
ENT.VisualHullRiseEpsilon = 0.1
ENT.VisualHigherTreadMinDelta = 1
ENT.VisualHigherTreadHullTolerance = 1
ENT.VisualPushHeightFraction = 0.1
ENT.VisualStaleOffsetDecay = 0.5
ENT.VisualOffsetDeadzone = 0.01

ENT.EnableSdkSpeedAdjust = true
ENT.EnablePredictiveStepProbe = true
ENT.EnableWalkIdleOverlay = true
ENT.EnableTurnGestures = true
ENT.EnableVisualStepOrigin = true
ENT.EnableFootIkRules = true
ENT.EnableFootTraceCenterOffset = true
ENT.EnableClientDeveloperDebug = true

ENT.TurnGestureCooldown = 0.5
ENT.TurnGestureMinDelta = 15

ENT.MaleSharedAnimModel = "models/humans/male_shared.mdl"
ENT.MaleEventAnimModel = "models/humans/group03/male_01.mdl"

ENT.EditableFloatTunables = {
	{ field = "FollowStopDist", key = "follow_stop_dist", min = 0, max = 512, category = "Follow", networkType = "Int" },
	{ field = "FollowLostDist", key = "follow_lost_dist", min = 0, max = 50000, category = "Follow", networkType = "Int" },
	{ field = "FollowSpeedWalk", key = "follow_speed_walk", min = 0, max = 300, category = "Movement", networkType = "Int" },
	{ field = "FollowSpeedRun", key = "follow_speed_run", min = 0, max = 300, category = "Movement", networkType = "Int" },
	{ field = "FollowAccel", key = "follow_accel", min = 0, max = 1000, category = "Movement", networkType = "Int" },
	{ field = "FollowDecel", key = "follow_decel", min = 0, max = 1000, category = "Movement", networkType = "Int" },
	{ field = "SdkHeightAdjustUpMin", key = "sdk_height_adjust_up_min", min = 0, max = 1, category = "SDK Speed" },
	{ field = "SdkHeightAdjustDownMin", key = "sdk_height_adjust_down_min", min = 0, max = 1, category = "SDK Speed" },
	{ field = "SdkPredictiveLookahead", key = "sdk_predictive_lookahead", min = 0, max = 512, category = "SDK Probe", networkType = "Int" },
	{ field = "SdkLocalStepSize", key = "sdk_local_step_size", min = 1, max = 64, category = "SDK Probe", networkType = "Int" },
	{ field = "SdkMoveHeightEpsilon", key = "sdk_move_height_epsilon", min = 0, max = 1, category = "SDK Probe" },
	{ field = "SdkReactiveDownBlend", key = "sdk_reactive_down_blend", min = 0, max = 1, category = "SDK Speed" },
	{ field = "SdkReactiveUpBlend", key = "sdk_reactive_up_blend", min = 0, max = 1, category = "SDK Speed" },
	{ field = "WalkIdleOverlayCycle", key = "walk_idle_overlay_cycle", min = 0, max = 1, category = "Overlay" },
	{ field = "WalkIdleOverlayMinWeight", key = "walk_idle_overlay_min_weight", min = 0, max = 1, category = "Overlay" },
	{ field = "WalkIdleOverlayMaxWeight", key = "walk_idle_overlay_max_weight", min = 0, max = 1, category = "Overlay" },
	{ field = "WalkIdleOverlayFadeRate", key = "walk_idle_overlay_fade_rate", min = 0, max = 20, category = "Overlay" },
	{ field = "FootTraceCenterForwardOffset", key = "foot_trace_center_forward_offset", min = -16, max = 16, category = "Foot IK" },
	{ field = "FootIkReleaseFraction", key = "foot_ik_release_fraction", min = 0, max = 1, category = "Foot IK" },
	{ field = "WalkToIdleDelay", key = "walk_to_idle_delay", min = 0, max = 2, category = "Movement" },
	{ field = "StairZDeltaThreshold", key = "stair_z_delta_threshold", min = 0, max = 12, category = "Visual Z" },
	{ field = "VisualStepOriginInterpSpeed", key = "visual_step_origin_interp_speed", min = 0, max = 60, category = "Visual Z" },
	{ field = "VisualIkFloorBlend", key = "visual_ik_floor_blend", min = 0, max = 1, category = "Visual Z" },
	{ field = "VisualStepOriginMaxDown", key = "visual_step_origin_max_down", min = 0, max = 72, category = "Visual Z", networkType = "Int" },
	{ field = "VisualStepHeight", key = "visual_step_height", min = 1, max = 72, category = "Visual Z", networkType = "Int" },
	{ field = "VisualTraceHullRadius", key = "visual_trace_hull_radius", min = 0.1, max = 16, category = "Visual Z" },
	{ field = "VisualTraceExtraHeight", key = "visual_trace_extra_height", min = 0, max = 32, category = "Visual Z" },
	{ field = "VisualTraceRadiusShrink", key = "visual_trace_radius_shrink", min = 0, max = 8, category = "Visual Z" },
	{ field = "VisualTraceMinRadius", key = "visual_trace_min_radius", min = 0.1, max = 8, category = "Visual Z" },
	{ field = "VisualRenderResetStepMultiplier", key = "visual_render_reset_step_multiplier", min = 1, max = 16, category = "Visual Z" },
	{ field = "VisualHullRiseEpsilon", key = "visual_hull_rise_epsilon", min = 0, max = 4, category = "Visual Z" },
	{ field = "VisualHigherTreadMinDelta", key = "visual_higher_tread_min_delta", min = 0, max = 16, category = "Visual Z" },
	{ field = "VisualHigherTreadHullTolerance", key = "visual_higher_tread_hull_tolerance", min = 0, max = 16, category = "Visual Z" },
	{ field = "VisualPushHeightFraction", key = "visual_push_height_fraction", min = 0, max = 1, category = "Visual Z" },
	{ field = "VisualStaleOffsetDecay", key = "visual_stale_offset_decay", min = 0, max = 1, category = "Visual Z" },
	{ field = "VisualOffsetDeadzone", key = "visual_offset_deadzone", min = 0, max = 4, category = "Visual Z" },
	{ field = "TurnGestureCooldown", key = "turn_gesture_cooldown", min = 0, max = 5, category = "Gestures" },
	{ field = "TurnGestureMinDelta", key = "turn_gesture_min_delta", min = 0, max = 180, category = "Gestures", networkType = "Int" }
}

ENT.EditableBoolTunables = {
	{ field = "EnableSdkSpeedAdjust", key = "enable_sdk_speed_adjust", category = "SDK Speed" },
	{ field = "EnablePredictiveStepProbe", key = "enable_predictive_step_probe", category = "SDK Probe" },
	{ field = "EnableWalkIdleOverlay", key = "enable_walk_idle_overlay", category = "Overlay" },
	{ field = "EnableTurnGestures", key = "enable_turn_gestures", category = "Gestures" },
	{ field = "EnableVisualStepOrigin", key = "enable_visual_step_origin", category = "Visual Z" },
	{ field = "EnableFootIkRules", key = "enable_foot_ik_rules", category = "Foot IK" },
	{ field = "EnableFootTraceCenterOffset", key = "enable_foot_trace_center_offset", category = "Foot IK" },
	{ field = "EnableClientDeveloperDebug", key = "enable_client_developer_debug", category = "Debug" }
}

ENT.EditableDefaultValues = {}
for _, data in ipairs(ENT.EditableFloatTunables) do
	ENT.EditableDefaultValues[data.field] = ENT[data.field]
end
for _, data in ipairs(ENT.EditableBoolTunables) do
	ENT.EditableDefaultValues[data.field] = ENT[data.field]
end

function ENT:SetupDataTables()
	local slots = { Float = 0, Int = 0 }
	for slot, data in ipairs(self.EditableFloatTunables) do
		local field = data.field
		local networkType = data.networkType or "Float"
		local editType = networkType == "Int" and "Int" or "Float"
		local networkSlot = slots[networkType] or 0
		slots[networkType] = networkSlot + 1
		self:NetworkVar(networkType, networkSlot, field .. "Edit", {
			KeyName = data.key,
			Edit = { type = editType, min = data.min, max = data.max, order = slot, category = data.category }
		})
		self:NetworkVarNotify(field .. "Edit", function(ent, _, _, newValue)
			local value = tonumber(newValue)
			ent[field] = networkType == "Int" and math.floor(value or ent[field] or 0) or (value or ent[field])
			ent:ApplyEditableRuntimeTunables()
		end)
	end

	for slot, data in ipairs(self.EditableBoolTunables) do
		local field = data.field
		self:NetworkVar("Bool", slot - 1, field .. "Edit", {
			KeyName = data.key,
			Edit = { type = "Boolean", order = 100 + slot, category = data.category }
		})
		self:NetworkVarNotify(field .. "Edit", function(ent, _, _, newValue)
			ent[field] = tobool(newValue)
			ent:ApplyEditableRuntimeTunables()
		end)
	end

	local resetSlot = #self.EditableBoolTunables
	self:NetworkVar("Bool", resetSlot, "ResetEditableDefaults", {
		KeyName = "reset_editable_defaults",
		Edit = { type = "Boolean", title = "Reset To Defaults", order = 1000, category = "Reset" }
	})
	self:NetworkVarNotify("ResetEditableDefaults", function(ent, _, _, newValue)
		if not newValue then return end
		ent:ResetEditableTunables()
		if SERVER then ent:SetResetEditableDefaults(false) end
	end)
end

function ENT:ApplyEditableRuntimeTunables()
	if self.loco then
		self.loco:SetDesiredSpeed(self.FollowSpeedWalk or 80)
		self.loco:SetAcceleration(self.FollowAccel or 200)
		self.loco:SetDeceleration(self.FollowDecel or 200)
	end

	if not self.EnableWalkIdleOverlay then
		self._WalkIdleOverlayWanted = false
		if self.ClearWalkIdleOverlay then self:ClearWalkIdleOverlay() end
	end
end

function ENT:ApplyEditableDefaults()
	for _, data in ipairs(self.EditableFloatTunables) do
		local setter = self["Set" .. data.field .. "Edit"]
		if setter then setter(self, self.EditableDefaultValues[data.field]) end
	end

	for _, data in ipairs(self.EditableBoolTunables) do
		local setter = self["Set" .. data.field .. "Edit"]
		if setter then setter(self, self.EditableDefaultValues[data.field]) end
	end

	self:ApplyEditableRuntimeTunables()
end

function ENT:ResetEditableTunables()
	self:ApplyEditableDefaults()
	if self.SetResetEditableDefaults then self:SetResetEditableDefaults(false) end
	self:ClearSdkSpeedAdjust()
	self._CityFootIK = nil
	self._VisualRenderZ = nil
	self._LastGroundZ = nil
	self._VisualEstIkFloor = nil
	self._VisualIkOffset = nil
	self._LastVisualHullZ = nil
end

local function angleFromStudioQuaternion(q)
	if not q then return nil end
	local x = q.x or 0
	local y = q.y or 0
	local z = q.z or 0
	local w = q.w or 1
	local len = math.sqrt(x * x + y * y + z * z + w * w)
	if len <= 0 then return angle_zero end
	x, y, z, w = x / len, y / len, z / len, w / len

	local sinrCosp = 2 * (w * x + y * z)
	local cosrCosp = 1 - 2 * (x * x + y * y)
	local roll = math.deg(math.atan2(sinrCosp, cosrCosp))

	local sinp = 2 * (w * y - z * x)
	local pitch
	if math.abs(sinp) >= 1 then
		pitch = math.deg((sinp >= 0) and (math.pi * 0.5) or (-math.pi * 0.5))
	else
		pitch = math.deg(math.asin(sinp))
	end

	local sinyCosp = 2 * (w * z + x * y)
	local cosyCosp = 1 - 2 * (y * y + z * z)
	local yaw = math.deg(math.atan2(sinyCosp, cosyCosp))

	return Angle(pitch, yaw, roll)
end

local function getIkRuleTargetPosition(boneMatrix, rule)
	if not boneMatrix or not rule or not isvector(rule.pos) then
		return boneMatrix and boneMatrix:GetTranslation() or nil
	end

	local localOffset = Matrix()
	localOffset:SetTranslation(rule.pos)
	local offsetAngle = angleFromStudioQuaternion(rule.q)
	if offsetAngle then
		localOffset:SetAngles(offsetAngle)
	end

	local inverseOffset = localOffset:GetInverseTR()
	local targetMatrix = Matrix(boneMatrix)
	targetMatrix:Mul(inverseOffset)
	return targetMatrix:GetTranslation()
end

local function offsetFootTraceCenter(ent, matrix, pos)
	local offset = ent.FootTraceCenterForwardOffset or 0
	if not ent.EnableFootTraceCenterOffset or not matrix or not isvector(pos) or offset == 0 then return pos end

	local forward = matrix.GetForward and matrix:GetForward() or nil
	if not isvector(forward) or forward:IsZero() then return pos end

	forward:Normalize()
	return pos + forward * offset
end

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
	local sharedModel = ent.MaleSharedAnimModel or "models/humans/male_shared.mdl"
	local rules = getSequenceGroundRules(sharedModel, seqName) or getSequenceGroundRules(ent:GetModel(), seqName)
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
	local rule, dist = StudioIK.GetBlendedGroundRule(sharedModel, seqName, contactCycle, poseValues)
	if rule then return rule, dist end
	return StudioIK.GetBlendedGroundRule(ent:GetModel(), seqName, contactCycle, poseValues)
end

local function getRuleActiveFoot(ent, leftRule, rightRule)
	local cycle = ent:GetCycle()
	local releaseFraction = ent.FootIkReleaseFraction
	local leftActive = FootIK.IsCycleInRelease(leftRule, cycle, releaseFraction)
	local rightActive = FootIK.IsCycleInRelease(rightRule, cycle, releaseFraction)
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
	model = (model and model ~= "") and model or ENT.MaleSharedAnimModel
	seqName = (seqName and seqName ~= "") and seqName or "walk_all"
	prefix = prefix or "V3TIMING"

	print(string.format("[%s] model=%s seq=%s", prefix, tostring(model), tostring(seqName)))

	local models = {}
	local seenModels = {}
	addUniqueModel(models, seenModels, model)
	addUniqueModel(models, seenModels, ENT.MaleEventAnimModel)
	addUniqueModel(models, seenModels, ENT.MaleSharedAnimModel)

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
	local sharedModel = ent.MaleSharedAnimModel or "models/humans/male_shared.mdl"
	local seq = StudioIK.GetSequence(sharedModel, seqName) or StudioIK.GetSequence(ent:GetModel(), seqName)
	if not seq or not seq.paramIndex then return nil end

	local values = {}
	local data = StudioIK.LoadModel(sharedModel) or StudioIK.LoadModel(ent:GetModel())
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

	self.loco:SetDesiredSpeed(self.FollowSpeedWalk)
	self.loco:SetAcceleration(self.FollowAccel)
	self.loco:SetDeceleration(self.FollowDecel)
	self.loco:SetStepHeight(18)
	self.loco:SetMaxYawRate(180)

	self:StartActivity(ACT_IDLE)

	self.Commander = nil
	self.NextUseTime = 0
	self.NextTurnTime = 0
	self.DebugEnabled = false
	self.NextDebugPrint = 0
	self.NextPoseDebugPrint = 0
	self.DebugLastPos = self:GetPos()
	self.DebugLastTime = CurTime()
	self.DebugMoveTarget = vector_origin
	self:ApplyEditableDefaults()

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
	local walkSpeed = self.FollowSpeedWalk or 80
	local groundSpeed = self.GetSequenceGroundSpeed and self:GetSequenceGroundSpeed(self:GetSequence()) or walkSpeed
	local playbackRate = walkSpeed / math.max(groundSpeed, 1)

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
	local wantMove = movingNow or ((now - (self._LastBodyMoveTime or 0)) < (self.WalkToIdleDelay or 0.15))

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

	self._WalkIdleOverlayWanted = self.EnableWalkIdleOverlay and wantMove and self._InStairOverlay
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
		if self.SetLayerCycle then self:SetLayerCycle(layerId, self.WalkIdleOverlayCycle or 0.20) end
		if self.SetLayerLooping then self:SetLayerLooping(layerId, true) end
		if self.SetLayerAutokill then self:SetLayerAutokill(layerId, false) end
		if self.SetLayerBlendIn then self:SetLayerBlendIn(layerId, 0) end
		if self.SetLayerBlendOut then self:SetLayerBlendOut(layerId, 0) end
	end

	local walkSpeed = math.max(self.FollowSpeedWalk or 80, 1)
	local targetWeight = math.Clamp(1 - ((moveSpeed or 0) / walkSpeed), self.WalkIdleOverlayMinWeight or 0.25, self.WalkIdleOverlayMaxWeight or 0.97)
	self._WalkIdleOverlayRawWeight = targetWeight
	self._WalkIdleOverlayTargetWeight = targetWeight
	local dt = interval or (FrameTime and FrameTime() or 0.015)
	self._WalkIdleOverlayWeight = math.Approach(self._WalkIdleOverlayWeight or 0, targetWeight, (self.WalkIdleOverlayFadeRate or 4.0) * dt)

	if self.SetLayerPriority then self:SetLayerPriority(layerId, 1) end
	if self.SetLayerWeight then self:SetLayerWeight(layerId, self._WalkIdleOverlayWeight) end
	if self.SetLayerPlaybackRate then self:SetLayerPlaybackRate(layerId, 1) end
end

function ENT:ToggleCommander(activator)
	if not IsValid(activator) or not activator:IsPlayer() or not activator:Alive() then return end
	if CurTime() < (self.NextUseTime or 0) then return end
	self.NextUseTime = CurTime() + 0.2

	if self.DebugEnabled then
		self.Commander = nil
		self:ClearFollowMoveState(true)
		self:SetDebugEnabled(activator, false)
		return true
	end

	self.Commander = (self.Commander == activator) and nil or activator
	if not IsValid(self.Commander) then
		self:ClearFollowMoveState(true)
		if self.DebugEnabled then
			self:SetDebugEnabled(activator, false)
		end
	end
	if IsValid(self.Commander) and not self.DebugEnabled then
		self:SetDebugEnabled(activator, true)
	end
	return true
end

function ENT:Use(activator)
	return self:ToggleCommander(activator)
end

function ENT:AcceptInput(name, activator)
	if name ~= "Use" then return end
	return self:ToggleCommander(activator)
end

function ENT:AddTurnGesture(yawDeltaDeg)
	if not self.EnableTurnGestures then return end
	if CurTime() < self.NextTurnTime then return end
	self.NextTurnTime = CurTime() + (self.TurnGestureCooldown or 0.5)

	local absDelta = math.abs(yawDeltaDeg)
	if absDelta < (self.TurnGestureMinDelta or 15) then return end

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
	return math.Clamp(adjust, (height > 0) and (self.SdkHeightAdjustUpMin or 0.5) or (self.SdkHeightAdjustDownMin or 0.8), 1)
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
	local moveHeightEpsilon = self.SdkMoveHeightEpsilon or 0.0625
	local start = Vector(startPos.x, startPos.y, startPos.z + moveHeightEpsilon)
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
	local downEnd = Vector(downStart.x, downStart.y, startPos.z - stepHeight - moveHeightEpsilon)
	local downTrace = self:TraceSdkMoveHull(downStart, downEnd)
	if downTrace.Fraction == 1 then
		return startPos, true
	end

	local endPoint = downTrace.HitPos
	endPoint.z = endPoint.z + moveHeightEpsilon
	return endPoint, false
end

function ENT:GetSdkGroundProbeAdjust(pos, desiredEnd)
	if not self.EnablePredictiveStepProbe then return 1, false end
	if not isvector(pos) or not isvector(desiredEnd) then return 1, false end

	local flatDelta = Vector(desiredEnd.x - pos.x, desiredEnd.y - pos.y, 0)
	local totalDist = flatDelta:Length()
	if totalDist <= 0.001 then return 1, false end

	local moveDir = flatDelta / totalDist
	local remaining = math.min(totalDist, self.SdkPredictiveLookahead or 96)
	local probePos = pos
	local adjust = 1
	local foundHeightChange = false

	while remaining > 0.001 do
		local stepSize = math.min(self.SdkLocalStepSize or 16, remaining)
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
			local lookaheadPos = path:GetPositionOnPath(math.min(cursor + (self.SdkPredictiveLookahead or 96), length))
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
	if not self.EnableSdkSpeedAdjust then
		self.DebugSdkSpeedAdjust = 1
		self.DebugSdkReactiveSpeedAdjust = 1
		self.DebugSdkPredictiveSpeedAdjust = 1
		return baseSpeed
	end

	local pos = self:GetPos()
	local prev = self._SdkSpeedPrevOrigin2 or self._SdkSpeedPrevOrigin1 or pos
	local reactiveAdjust = self:GetSdkHeightAdjustBetween(prev, pos)
	local predictiveAdjust = self:GetSdkPredictiveSpeedAdjust(pos)

	if reactiveAdjust < (self._SdkReactiveSpeedAdjust or 1) then
		local blend = math.Clamp(self.SdkReactiveDownBlend or 0.8, 0, 1)
		self._SdkReactiveSpeedAdjust = (self._SdkReactiveSpeedAdjust or 1) * (1 - blend) + reactiveAdjust * blend
	else
		local blend = math.Clamp(self.SdkReactiveUpBlend or 0.5, 0, 1)
		self._SdkReactiveSpeedAdjust = (self._SdkReactiveSpeedAdjust or 1) * (1 - blend) + reactiveAdjust * blend
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

			if dist > self.FollowLostDist then
				self:ClearFollowMoveState(false)
				coroutine.wait(1)
				continue
			end

			if dist > self.FollowStopDist then
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
				self.DebugIdealSpeed = self.FollowSpeedWalk
				self.loco:SetAcceleration(self.FollowAccel)
				self.loco:SetDeceleration(self.FollowDecel)
				self.loco:SetDesiredSpeed(self.FollowSpeedWalk)
				self._FollowPath = nil

				local stuckPos = self:GetPos()
				local stuckTime = 0

				while self.Commander and IsValid(self.Commander) and self.Commander:Alive() do
					cmdPos = self.Commander:GetPos()
					dist = self:GetPos():Distance(cmdPos)
					self.DebugMoveTarget = cmdPos

					if dist > self.FollowLostDist then
						self:ClearFollowMoveState(false)
						break
					end
					if dist <= self.FollowStopDist then
						self:ClearFollowMoveState(false)
						break
					end

					self.loco:FaceTowards(cmdPos)

					local targetFollowSpeed = self:GetSdkHeightAdjustedSpeed(self.FollowSpeedRun or self.FollowSpeedWalk)
					local uphill = self:IsMovingUphill(cmdPos)
					local posZ = self:GetPos().z
					local movingOnStairs = (uphill and self._LastFollowZ and posZ - self._LastFollowZ > (self.StairZDeltaThreshold or 1)) or self._SdkProbeFoundHeightChange
					if movingOnStairs then
						self._InStairOverlay = true
					elseif not uphill then
						self._InStairOverlay = false
					end
					self._LastFollowZ = posZ

					self.loco:SetAcceleration(self.FollowAccel)
					self.loco:SetDeceleration(self.FollowDecel)
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
		model = ENT.MaleSharedAnimModel
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
		model = ENT.MaleSharedAnimModel
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
		model = ENT.MaleSharedAnimModel
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
		model = ENT.MaleSharedAnimModel
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

local function drawTraceSquare(x, y, z, r, color)
	render.DrawLine(Vector(x - r, y - r, z), Vector(x + r, y - r, z), color, false)
	render.DrawLine(Vector(x + r, y - r, z), Vector(x + r, y + r, z), color, false)
	render.DrawLine(Vector(x + r, y + r, z), Vector(x - r, y + r, z), color, false)
	render.DrawLine(Vector(x - r, y + r, z), Vector(x - r, y - r, z), color, false)
end

local function shouldDrawDeveloperDebug(ent)
	if not ent.EnableClientDeveloperDebug then return false end
	local developer = GetConVar("developer")
	return ent:GetNWBool("CityNPCDebugEnabled", false) and developer and developer:GetBool()
end

local function drawBoxLines(pos, mins, maxs, color)
	local x1, y1, z1 = pos.x + mins.x, pos.y + mins.y, pos.z + mins.z
	local x2, y2, z2 = pos.x + maxs.x, pos.y + maxs.y, pos.z + maxs.z
	local bottom = {
		Vector(x1, y1, z1), Vector(x2, y1, z1), Vector(x2, y2, z1), Vector(x1, y2, z1)
	}
	local top = {
		Vector(x1, y1, z2), Vector(x2, y1, z2), Vector(x2, y2, z2), Vector(x1, y2, z2)
	}
	for i = 1, 4 do
		local nextIndex = (i % 4) + 1
		render.DrawLine(bottom[i], bottom[nextIndex], color, false)
		render.DrawLine(top[i], top[nextIndex], color, false)
		render.DrawLine(bottom[i], top[i], color, false)
	end
end

local function drawRuleStateMarker(info, rule, activeFoot, side, hullZ)
	if not info or not info.traceX or not info.traceY then return end

	local ent = info.ent
	local cycle = 0
	if IsValid(ent) and ent.GetCycle then
		cycle = ent:GetCycle()
	end

	local active = activeFoot == side
	local inRule = FootIK.IsCycleInRelease(rule, cycle)
	local push = getRulePushFraction(rule, cycle)
	local hitZ = info.traceZ
	local falling = not hitZ or (hullZ and hitZ and hullZ - hitZ > 18.5)
	local baseZ = (hitZ or info.floor or hullZ or 0) + 2
	local color = Color(120, 120, 120, 220)
	if falling then
		color = Color(255, 60, 60, 255)
	elseif push > 0.05 then
		color = Color(255, 220, 60, 255)
	elseif inRule or active then
		color = Color(80, 255, 100, 255)
	end

	local height = 6 + push * 12
	local p1 = Vector(info.traceX, info.traceY, baseZ)
	local p2 = Vector(info.traceX, info.traceY, baseZ + height)
	render.DrawLine(p1, p2, color, false)
	drawTraceSquare(info.traceX, info.traceY, baseZ + height, 2, color)
end

local function drawFootContactIndicator(footPos, hitZ, radius)
	if not isvector(footPos) then return end

	local r = math.max(radius or 1.5, 1.5)
	local contactZ = isnumber(hitZ) and hitZ or (footPos.z - 8)
	local gap = footPos.z - contactZ
	local color = (not isnumber(hitZ) or gap > 1.5) and Color(255, 40, 40, 255) or Color(60, 255, 80, 255)
	local groundPos = Vector(footPos.x, footPos.y, contactZ + 0.4)

	render.DrawLine(groundPos, footPos, color, false)
	drawTraceSquare(footPos.x, footPos.y, groundPos.z, r * 1.25, color)
	drawTraceSquare(footPos.x, footPos.y, footPos.z, r, color)
end

local function drawTraceHullLines(info, color)
	if not info or not info.traceX or not info.traceY or not info.floor or not info.height or not info.radius then return end

	local x = info.traceX
	local y = info.traceY
	local r = info.radius
	local startZ = info.floor + info.height
	local endZ = info.floor - info.height

	-- The trace sweeps far above/below the foot; draw that as a center guide only.
	render.DrawLine(Vector(x, y, startZ), Vector(x, y, endZ), Color(180, 180, 180, 160), false)
	drawTraceSquare(x, y, info.floor, r, Color(180, 180, 255, 220))
	if info.rawTraceX and info.rawTraceY and info.rawTraceZ then
		local rawZ = info.rawTraceZ + 0.4
		render.DrawLine(Vector(info.rawTraceX, info.rawTraceY, rawZ), Vector(x, y, rawZ), Color(255, 255, 255, 220), false)
		drawTraceSquare(info.rawTraceX, info.rawTraceY, rawZ, 0.8, Color(255, 255, 255, 220))
	end

	if info.traceZ then
		local z = info.traceZ + 0.2
		drawTraceSquare(x, y, z, r, color)
		render.DrawLine(Vector(x - r * 1.5, y, z), Vector(x + r * 1.5, y, z), Color(255, 255, 80, 255), false)
		render.DrawLine(Vector(x, y - r * 1.5, z), Vector(x, y + r * 1.5, z), Color(255, 255, 80, 255), false)
	end
end

local function drawFootTraceHulls(leftTrace, rightTrace, leftRule, rightRule, activeFoot, hullZ, ent, leftFootPos, rightFootPos)
	if leftTrace then leftTrace.ent = ent end
	if rightTrace then rightTrace.ent = ent end
	drawTraceHullLines(leftTrace, Color(80, 170, 255, 255))
	drawTraceHullLines(rightTrace, Color(255, 120, 80, 255))
	drawRuleStateMarker(leftTrace, leftRule, activeFoot, "left", hullZ)
	drawRuleStateMarker(rightTrace, rightRule, activeFoot, "right", hullZ)
	drawFootContactIndicator(leftFootPos, leftTrace and leftTrace.traceZ, leftTrace and leftTrace.radius)
	drawFootContactIndicator(rightFootPos, rightTrace and rightTrace.traceZ, rightTrace and rightTrace.radius)
end

local function getClientMoveDirection(ent)
	local pos = ent:GetPos()
	local lastPos = ent._CityForwardProbeLastPos
	ent._CityForwardProbeLastPos = pos

	if isvector(lastPos) then
		local delta = Vector(pos.x - lastPos.x, pos.y - lastPos.y, 0)
		local dist = delta:Length()
		if dist > 0.05 then
			ent._CityForwardProbeDir = delta / dist
		end
	end

	if isvector(ent._CityForwardProbeDir) then
		return ent._CityForwardProbeDir
	end

	local forward = ent:GetForward()
	forward.z = 0
	local len = forward:Length()
	if len <= 0.001 then return nil end
	return forward / len
end

local function getClientSdkTraceHullBounds(ent)
	local mins, maxs = ent:GetCollisionBounds()
	if not isvector(mins) or not isvector(maxs) then
		mins, maxs = ent:OBBMins(), ent:OBBMaxs()
	end
	mins = Vector(mins.x, mins.y, 0)
	return mins, maxs
end

local function traceClientSdkMoveHull(ent, startPos, endPos, mins, maxs)
	return util.TraceHull({
		start = startPos,
		endpos = endPos,
		mins = mins,
		maxs = maxs,
		filter = ent,
		mask = MASK_NPCSOLID or MASK_SOLID,
		collisiongroup = COLLISION_GROUP_NPC
	})
end

local function drawForwardStepProbe(ent)
	if not ent.EnableClientDeveloperDebug or not ent.EnablePredictiveStepProbe then return end
	local pos = ent:GetPos()
	local moveDir = getClientMoveDirection(ent)
	if not isvector(moveDir) then return end

	local remaining = ent.SdkPredictiveLookahead or 96
	local probePos = pos
	local mins, maxs = getClientSdkTraceHullBounds(ent)
	local stepHeight = (ent.loco and ent.loco.GetStepHeight) and ent.loco:GetStepHeight() or 18
	local moveHeightEpsilon = ent.SdkMoveHeightEpsilon or 0.0625

	while remaining > 0.001 do
		local stepSize = math.min(ent.SdkLocalStepSize or 16, remaining)
		local start = Vector(probePos.x, probePos.y, probePos.z + moveHeightEpsilon)
		local forwardEnd = start + moveDir * stepSize
		local forwardTrace = traceClientSdkMoveHull(ent, start, forwardEnd, mins, maxs)

		drawBoxLines(start, mins, maxs, Color(80, 220, 255, 180))
		render.DrawLine(start, forwardEnd, Color(80, 220, 255, 255), false)

		local moveStart = start
		local moveTrace = forwardTrace
		local blocked = false
		if forwardTrace.StartSolid or forwardTrace.Fraction < 1 then
			moveStart = forwardTrace.StartSolid and start or forwardTrace.HitPos
			local upEnd = moveStart + Vector(0, 0, stepHeight)
			local upTrace = traceClientSdkMoveHull(ent, moveStart, upEnd, mins, maxs)
			render.DrawLine(moveStart, upEnd, Color(200, 120, 255, 255), false)
			drawBoxLines(upTrace.HitPos, mins, maxs, Color(200, 120, 255, 180))

			moveStart = upTrace.HitPos
			moveTrace = traceClientSdkMoveHull(ent, moveStart, Vector(forwardEnd.x, forwardEnd.y, moveStart.z), mins, maxs)
			render.DrawLine(moveStart, Vector(forwardEnd.x, forwardEnd.y, moveStart.z), Color(80, 220, 255, 255), false)
			if moveTrace.StartSolid or moveTrace.Fraction <= 0.01 then
				blocked = true
			end
		end

		if blocked then
			drawBoxLines(moveTrace.HitPos or moveStart, mins, maxs, Color(255, 60, 60, 220))
			break
		end

		local downStart = moveTrace.HitPos
		local downEnd = Vector(downStart.x, downStart.y, probePos.z - stepHeight - moveHeightEpsilon)
		local downTrace = traceClientSdkMoveHull(ent, downStart, downEnd, mins, maxs)
		render.DrawLine(downStart, downEnd, Color(255, 220, 80, 255), false)
		if downTrace.Fraction == 1 then
			drawBoxLines(downEnd, mins, maxs, Color(255, 60, 60, 220))
			break
		end

		local nextPos = downTrace.HitPos
		nextPos.z = nextPos.z + moveHeightEpsilon
		drawBoxLines(nextPos, mins, maxs, Color(80, 255, 100, 200))
		probePos = nextPos
		remaining = remaining - stepSize
	end
end

function ENT:Draw()
	self:SetIK(false)
	self:SetupBones()

	local lFootBone = self:LookupBone("ValveBiped.Bip01_L_Foot")
	local rFootBone = self:LookupBone("ValveBiped.Bip01_R_Foot")
	local traceBoneMatrices = {}
	for _, bone in ipairs({ lFootBone, rFootBone }) do
		if bone then
			local mat = self:GetBoneMatrix(bone)
			if mat then
				traceBoneMatrices[bone] = Matrix(mat)
			end
		end
	end

	self:SetIK(true)
	self:SetupBones()
	if not self.EnableVisualStepOrigin then
		self._VisualRenderZ = nil
		self._VisualIkOffset = nil
		self:DrawModel()
		return
	end

	local STEP_HEIGHT = self.VisualStepHeight or 18
	local HULL_R = self.VisualTraceHullRadius or 2.5
	local STEP_ORIGIN_INTERP_SPEED = self.VisualStepOriginInterpSpeed or 10.5
	local IK_FLOOR_BLEND = self.VisualIkFloorBlend or 0.8
	local hullPos = self:GetPos()
	local hullZ = hullPos.z
	local prevHullZ = self._LastVisualHullZ or hullZ
	local hullRising = hullZ > prevHullZ + (self.VisualHullRiseEpsilon or 0.1)
	self._LastVisualHullZ = hullZ
	if self._VisualRenderZ and math.abs(self._VisualRenderZ - hullZ) > STEP_HEIGHT * (self.VisualRenderResetStepMultiplier or 4) then
		self._VisualRenderZ = nil
		self._LastGroundZ = nil
		self._VisualEstIkFloor = nil
		self._VisualIkOffset = nil
	end
	local traceZ = hullZ

	local seqName = self:GetSequenceName(self:GetSequence()) or ""
	local isMovingSeq = seqName:lower():find("walk") or seqName:lower():find("run")

	local leftRule = self.EnableFootIkRules and getFootIkRule(self, "left") or nil
	local rightRule = self.EnableFootIkRules and getFootIkRule(self, "right") or nil
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
	local leftFootMat = lFootBone and self:GetBoneMatrix(lFootBone) or nil
	local rightFootMat = rFootBone and self:GetBoneMatrix(rFootBone) or nil
	local leftFootPos = leftFootMat and leftFootMat:GetTranslation() or nil
	local rightFootPos = rightFootMat and rightFootMat:GetTranslation() or nil
	local footDistXY, footDist3D, footDeltaZ
	if leftWorldZ and rightWorldZ then
		local leftMat = leftFootMat
		local rightMat = rightFootMat
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
		local mat = traceBoneMatrices[bone] or self:GetBoneMatrix(bone)
		if not mat then return nil end
		local footPos = mat:GetTranslation()
		local tracePos = footPos
		local radius = HULL_R
		local height = STEP_HEIGHT + (self.VisualTraceExtraHeight or 2)
		local floorZ = traceZ
		if rule then
			radius = math.max(rule.radius or radius, 1)
			height = math.max(rule.height or height, 1)
			floorZ = hullZ + (rule.floor or 0)
			tracePos = getIkRuleTargetPosition(mat, rule) or footPos
		end
		local rawTracePos = tracePos
		tracePos = offsetFootTraceCenter(self, mat, tracePos)
		radius = math.max(radius - (self.VisualTraceRadiusShrink or 1), self.VisualTraceMinRadius or 1)
		local tr = util.TraceHull({
			start = Vector(tracePos.x, tracePos.y, floorZ + height),
			endpos = Vector(tracePos.x, tracePos.y, floorZ - height),
			mins = Vector(-radius, -radius, 0),
			maxs = Vector(radius, radius, radius * 2),
			filter = self,
			mask = MASK_SOLID
		})
		local info = {
			hit = tr.Hit and tr.HitPos.z <= traceZ + STEP_HEIGHT and tr.HitPos.z or nil,
			fraction = tr.Fraction,
			normalZ = tr.HitNormal and tr.HitNormal.z,
			startSolid = tr.StartSolid,
			hitWorld = tr.HitWorld,
			traceX = tracePos.x,
			traceY = tracePos.y,
			traceZ = tr.HitPos and tr.HitPos.z,
			rawTraceX = rawTracePos.x,
			rawTraceY = rawTracePos.y,
			rawTraceZ = rawTracePos.z,
			radius = radius,
			height = height,
			floor = floorZ
		}
		return info.hit, info
		end

	local leftHit, leftTrace = doTrace(lFootBone, leftRule)
	local rightHit, rightTrace = doTrace(rFootBone, rightRule)
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
			leftFraction = leftTrace and leftTrace.fraction,
			leftNormalZ = leftTrace and leftTrace.normalZ,
			leftStartSolid = leftTrace and leftTrace.startSolid,
			leftHitWorld = leftTrace and leftTrace.hitWorld,
			footDistXY = footDistXY,
			footDist3D = footDist3D,
			footDeltaZ = footDeltaZ,
			rightLocalZ = rightLocalZ,
			rightWorldZ = rightWorldZ,
			rightFraction = rightTrace and rightTrace.fraction,
			rightNormalZ = rightTrace and rightTrace.normalZ,
			rightStartSolid = rightTrace and rightTrace.startSolid,
			rightHitWorld = rightTrace and rightTrace.hitWorld
		})
		self:DrawModel()
		if shouldDrawDeveloperDebug(self) then
			drawFootTraceHulls(leftTrace, rightTrace, leftRule, rightRule, activeFoot, hullZ, self, leftFootPos, rightFootPos)
			drawForwardStepProbe(self)
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
	if minGroundZ and currentMaxHit and hullRising and hullZ - minGroundZ > STEP_HEIGHT * (self.VisualPushHeightFraction or 0.1) and currentMaxHit > minGroundZ + (self.VisualHigherTreadMinDelta or 1) and currentMaxHit <= hullZ + (self.VisualHigherTreadHullTolerance or 1) then
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
		local targetOffset = math.Clamp(self._VisualEstIkFloor - hullZ, -(self.VisualStepOriginMaxDown or 18) + bias, 0)
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
			leftFraction = leftTrace and leftTrace.fraction,
			leftNormalZ = leftTrace and leftTrace.normalZ,
			leftStartSolid = leftTrace and leftTrace.startSolid,
			leftHitWorld = leftTrace and leftTrace.hitWorld,
			footDistXY = footDistXY,
			footDist3D = footDist3D,
			footDeltaZ = footDeltaZ,
			rightLocalZ = rightLocalZ,
			rightWorldZ = rightWorldZ,
			rightHit = rightHit,
			rightFraction = rightTrace and rightTrace.fraction,
			rightNormalZ = rightTrace and rightTrace.normalZ,
			rightStartSolid = rightTrace and rightTrace.startSolid,
			rightHitWorld = rightTrace and rightTrace.hitWorld,
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
		if shouldDrawDeveloperDebug(self) then
			drawFootTraceHulls(leftTrace, rightTrace, leftRule, rightRule, activeFoot, hullZ, self, leftFootPos, rightFootPos)
			drawForwardStepProbe(self)
		end
	else
		-- SDK UpdateStepOrigin decays the previous IK offset when contact is stale
		-- instead of snapping the render origin straight back to the hull.
		self._VisualIkOffset = (self._VisualIkOffset or 0) * (self.VisualStaleOffsetDecay or 0.5)
		self._VisualEstIkFloor = hullZ
		local renderZ = hullZ + self._VisualIkOffset
		self._VisualRenderZ = renderZ
		if math.abs(self._VisualIkOffset) > (self.VisualOffsetDeadzone or 0.01) then
			self:SetRenderOrigin(Vector(hullPos.x, hullPos.y, renderZ))
			self:SetupBones()
			self:DrawModel()
			self:SetRenderOrigin(nil)
		else
			self:DrawModel()
		end
		if shouldDrawDeveloperDebug(self) then
			drawFootTraceHulls(leftTrace, rightTrace, leftRule, rightRule, activeFoot, hullZ, self, leftFootPos, rightFootPos)
			drawForwardStepProbe(self)
		end
	end
end

end
