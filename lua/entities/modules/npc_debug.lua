CityNPCs = CityNPCs or {}
CityNPCs.Modules = CityNPCs.Modules or {}

local Mod = CityNPCs.Modules.npc_debug or {}
CityNPCs.Modules.npc_debug = Mod
Mod.PrintSpawnHullEnabled = Mod.PrintSpawnHullEnabled or false

local SERVER_DEBUG_INTERVAL = 0.05
local SERVER_DEBUG_STILL_SPEED = 1
local SERVER_DEBUG_STILL_MAX_SAMPLES = 6

local V5_INTERNAL_PROBE_NAMES = {
	"m_flEstIkOffset",
	"m_flEstIkFloor",
	"m_flIKGroundMinHeight",
	"m_flIKGroundMaxHeight",
	"m_flIKGroundContactTime",
	"m_iIKCounter",
	"m_vecAbsOrigin",
	"m_vecOrigin",
	"m_vecLastPosition",
	"m_flStepSize",
	"m_nStepside",
	"m_hBigStepGroundEnt",
	"m_RenderOrigin"
}

function Mod.Timestamp()
	local now = CurTime and CurTime() or os.clock()
	return string.format("%.3f", now)
end

function Mod.FormatVector(v)
	if not isvector(v) then return tostring(v) end
	return string.format("(%.1f,%.1f,%.1f)", v.x, v.y, v.z)
end

function Mod.FormatNumber(v)
	return v and string.format("%.1f", v) or "?"
end

function Mod.GetEntityLabel(ent)
	if not IsValid(ent) then return "invalid" end
	if ent.CityDebugLabel then return ent:CityDebugLabel() end
	return string.format("%s:%s", tostring(ent.Type or "entity"), tostring(ent:GetClass()))
end

function Mod.PrintSpawnHull(ent, label)
	if not IsValid(ent) then return end
	if not Mod.PrintSpawnHullEnabled and not ent.DebugPrintSpawnHull then return end

	local colMins, colMaxs = ent:GetCollisionBounds()
	local pos = ent:GetPos()
	local phys = ent:GetPhysicsObject()
	print(string.format(
		"[%s HULL #%d] model=%s solid=%s move=%s obbMin=%s obbMax=%s colMin=%s colMax=%s hullWorldMin=%s hullWorldMax=%s hullOrigin=%s physValid=%s physMove=%s physMotion=%s",
		label, ent:EntIndex(), tostring(ent:GetModel()), tostring(ent:GetSolid()), tostring(ent:GetMoveType()),
		Mod.FormatVector(ent:OBBMins()), Mod.FormatVector(ent:OBBMaxs()), Mod.FormatVector(colMins), Mod.FormatVector(colMaxs),
		Mod.FormatVector(pos + colMins), Mod.FormatVector(pos + colMaxs), Mod.FormatVector(pos),
		tostring(IsValid(phys)), IsValid(phys) and tostring(phys:IsMoveable()) or "?", IsValid(phys) and tostring(phys:IsMotionEnabled()) or "?"
	))
end

function Mod.SuppressStill(ent, keyPrefix, moving, stateKey, maxSamples)
	local lastStateKey = keyPrefix .. "LastState"
	local sampleKey = keyPrefix .. "StillSamples"
	if moving or ent[lastStateKey] ~= stateKey then
		ent[lastStateKey] = stateKey
		ent[sampleKey] = 0
		return false
	end

	local stillSamples = (ent[sampleKey] or 0) + 1
	ent[sampleKey] = stillSamples
	return stillSamples >= (maxSamples or 0)
end

function Mod.SetServerEnabled(ent, ply, enabled, label)
	ent.DebugEnabled = enabled
	ent.DebugOwner = enabled and ply or nil
	ent.NextDebugPrint = 0
	ent.DebugSaveProbePrinted = false
	print("[" .. tostring(label or Mod.GetEntityLabel(ent)) .. "] Debug " .. (enabled and "ON" or "OFF") .. " for #" .. ent:EntIndex())
end

function Mod.PrintEntityStatus(ent, message)
	if not IsValid(ent) then return end
	print(ent:GetClass() .. " [" .. ent:EntIndex() .. "] " .. tostring(message))
end

local function getEntitySpeedSinceLastDebug(ent, pos, now)
	local lastPos = ent.DebugLastPos or pos
	local lastTime = ent.DebugLastTime or now
	local dt = math.max(now - lastTime, 0.001)
	local posDelta = pos - lastPos
	ent.DebugLastPos = pos
	ent.DebugLastTime = now
	return Vector(posDelta.x, posDelta.y, 0):Length() / dt, posDelta.z / dt
end

local function formatGroundEntity(ent)
	return IsValid(ent) and (ent:GetClass() .. "#" .. ent:EntIndex()) or "none"
end

local function fmtProbeValue(v)
	if isvector(v) then return Mod.FormatVector(v) end
	if isentity(v) and IsValid(v) then return v:GetClass() .. "#" .. v:EntIndex() end
	if v == NULL then return "NULL" end
	return tostring(v)
end

local function getV5InternalProbeString(ent)
	if not ent.GetInternalVariable then return "noapi" end

	local parts = {}
	for _, name in ipairs(V5_INTERNAL_PROBE_NAMES) do
		local ok, value = pcall(ent.GetInternalVariable, ent, name)
		if ok and value ~= nil then
			parts[#parts + 1] = name .. "=" .. fmtProbeValue(value)
		end
	end

	return (#parts > 0) and table.concat(parts, ";") or "none"
end

local function printV5SaveProbeKeys(ent)
	if not ent.GetSaveTable then return end

	local ok, saveTable = pcall(ent.GetSaveTable, ent, true)
	if not ok or not istable(saveTable) then
		print(string.format("[V5SAVE #%d] unavailable=%s", ent:EntIndex(), tostring(saveTable)))
		return
	end

	local keys = {}
	for key in pairs(saveTable) do
		local lower = string.lower(tostring(key))
		if string.find(lower, "ik", 1, true)
			or string.find(lower, "step", 1, true)
			or string.find(lower, "origin", 1, true)
			or string.find(lower, "floor", 1, true)
			or string.find(lower, "ground", 1, true)
			or string.find(lower, "render", 1, true)
			or string.find(lower, "lastposition", 1, true) then
			keys[#keys + 1] = tostring(key)
		end
	end

	table.sort(keys)
	print(string.format("[V5SAVE #%d] keys=%s", ent:EntIndex(), (#keys > 0) and table.concat(keys, ",") or "none"))
end

local function printV3ServerLine(ent)
	local pos = ent:GetPos()
	local now = CurTime()
	local manualSpeed, zSpeed = getEntitySpeedSinceLastDebug(ent, pos, now)
	local moveVel = ent.loco and ent.loco:GetVelocity() or vector_origin
	local moveSpeed = moveVel:Length2D()
	local groundNormal = (ent.loco and ent.loco.GetGroundNormal) and ent.loco:GetGroundNormal() or vector_origin
	local groundMotion = (ent.loco and ent.loco.GetGroundMotionVector) and ent.loco:GetGroundMotionVector() or vector_origin
	local locoOnGround = (ent.loco and ent.loco.IsOnGround) and ent.loco:IsOnGround() or false
	local locoAttempt = (ent.loco and ent.loco.IsAttemptingToMove) and ent.loco:IsAttemptingToMove() or false
	local locoClimbJump = (ent.loco and ent.loco.IsClimbingOrJumping) and ent.loco:IsClimbingOrJumping() or false
	local stepHeight = (ent.loco and ent.loco.GetStepHeight) and ent.loco:GetStepHeight() or -1
	local groundEnt = ent.GetGroundEntity and ent:GetGroundEntity() or NULL
	local groundSpeedVel = ent.GetGroundSpeedVelocity and ent:GetGroundSpeedVelocity() or vector_origin
	local fwd = ent:GetForward()
	local forwardSpeed = moveVel.x * fwd.x + moveVel.y * fwd.y
	local idealSpeed = ent.DebugIdealSpeed or (ent.loco and ent.loco:GetDesiredSpeed() or -1)
	local desiredSpeed = (ent.loco and ent.loco.GetDesiredSpeed) and ent.loco:GetDesiredSpeed() or idealSpeed
	local sdkAdjust = ent.DebugSdkSpeedAdjust or -1
	local sdkReactiveAdjust = ent.DebugSdkReactiveSpeedAdjust or -1
	local sdkPredictiveAdjust = ent.DebugSdkPredictiveSpeedAdjust or -1
	local sdkProbe = ent._SdkProbeFoundHeightChange or false
	local target = ent.DebugMoveTarget or vector_origin
	local targetDist = (target ~= vector_origin) and pos:Distance(target) or -1
	local anim = Mod.GetAnimSegment(ent)
	local layerInfo = Mod.GetLayerInfo(ent, ent._WalkIdleLayer, ent._WalkIdleOverlayWeight, ent._WalkIdleOverlayTargetWeight, ent._WalkIdleOverlayRawWeight)
	local commander = ent.Commander
	local cmdValid = IsValid(commander)
	local cmdDist = cmdValid and pos:Distance(commander:GetPos()) or -1
	local stateKey = string.format("%s:%d:%s:%d", tostring(cmdValid), anim.seq, anim.seqName, math.floor(pos.z + 0.5))
	if Mod.SuppressStill(ent, "_CityV3ServerDebug", moveSpeed > SERVER_DEBUG_STILL_SPEED or manualSpeed > SERVER_DEBUG_STILL_SPEED, stateKey, SERVER_DEBUG_STILL_MAX_SAMPLES) then return end

	print(string.format(
		"[V3DBG #%d] ts=%s locoVel=%.1f actualVel=%.1f fwdVel=%.1f zVel=%.1f desired=%.1f ideal=%.1f sdkAdj=%.2f sdkReact=%.2f sdkPred=%.2f sdkProbe=%s anim=%.1f follow=%s stock=false cmdDist=%.1f tgtDist=%.1f originZ=%.1f tgtZ=%.1f %s layer=%s layerSeq=%d:%s layerW=%.2f layerTarget=%.2f layerRaw=%.2f layerCycle=%.3f layerPb=%.2f nav=%s schedIdle=%s isnpc=%s locoGround=%s locoAttempt=%s locoClimbJump=%s stepH=%.1f gNorm=(%.2f,%.2f,%.2f) gMotion=(%.2f,%.2f,%.2f) gEnt=%s gSpdVel=%.1f",
		ent:EntIndex(), Mod.Timestamp(), moveSpeed, manualSpeed, forwardSpeed, zSpeed, desiredSpeed, idealSpeed, sdkAdjust, sdkReactiveAdjust, sdkPredictiveAdjust, tostring(sdkProbe), anim.seqGroundSpeed, tostring(cmdValid), cmdDist, targetDist,
		pos.z, target.z, anim.text, tostring(layerInfo.valid), layerInfo.seq, layerInfo.name, layerInfo.weight, layerInfo.targetWeight, layerInfo.rawWeight, layerInfo.cycle, layerInfo.playbackRate,
		"nextbot", tostring(moveSpeed <= 1 and anim.act == ACT_IDLE), tostring(ent:IsNPC()),
		tostring(locoOnGround), tostring(locoAttempt), tostring(locoClimbJump), stepHeight,
		groundNormal.x, groundNormal.y, groundNormal.z, groundMotion.x, groundMotion.y, groundMotion.z,
		formatGroundEntity(groundEnt), groundSpeedVel:Length2D()
	))
end

local function printV5ServerLine(ent)
	if not ent.DebugSaveProbePrinted then
		ent.DebugSaveProbePrinted = true
		printV5SaveProbeKeys(ent)
	end

	local pos = ent:GetPos()
	local now = CurTime()
	local manualSpeed = getEntitySpeedSinceLastDebug(ent, pos, now)
	local moveVel = ent.GetMoveVelocity and ent:GetMoveVelocity() or vector_origin
	local moveSpeed = moveVel:Length2D()
	local groundEnt = ent.GetGroundEntity and ent:GetGroundEntity() or NULL
	local groundSpeedVel = ent.GetGroundSpeedVelocity and ent:GetGroundSpeedVelocity() or vector_origin
	local stepHeight = ent.GetStepHeight and ent:GetStepHeight() or -1
	local npcMoving = ent.IsMoving and ent:IsMoving() or false
	local hasObstacles = ent.HasObstacles and ent:HasObstacles() or false
	local curWaypoint = ent.GetCurWaypointPos and ent:GetCurWaypointPos() or nil
	local nextWaypoint = ent.GetNextWaypointPos and ent:GetNextWaypointPos() or nil
	local goalPos = ent.GetGoalPos and ent:GetGoalPos() or nil
	local pathDist = ent.GetPathDistanceToGoal and ent:GetPathDistanceToGoal() or -1
	local fwd = ent:GetForward()
	local forwardSpeed = moveVel.x * fwd.x + moveVel.y * fwd.y
	local idealSpeed = ent.GetIdealMoveSpeed and ent:GetIdealMoveSpeed() or -1
	local moveAct = ent.GetMovementActivity and ent:GetMovementActivity() or "?"
	local moveSeq = ent.GetMovementSequence and ent:GetMovementSequence() or -1
	local target = ent.DebugMoveTarget or vector_origin
	local targetDist = (target ~= vector_origin) and pos:Distance(target) or -1
	local anim = Mod.GetAnimSegment(ent)
	local moveInterval = ent.GetMoveInterval and ent:GetMoveInterval() or -1
	local navType = ent.GetNavType and ent:GetNavType() or -1
	local commander = ent.Commander
	local cmdValid = IsValid(commander)
	local cmdDist = cmdValid and pos:Distance(commander:GetPos()) or -1
	local internalProbe = getV5InternalProbeString(ent)
	local stateKey = string.format("%s:%s:%s:%d:%s:%s", tostring(cmdValid), tostring(ent.StockMoveActive), tostring(npcMoving), math.floor(pos.z + 0.5), tostring(moveAct), anim.seqName)
	if Mod.SuppressStill(ent, "_CityV5ServerDebug", moveSpeed > SERVER_DEBUG_STILL_SPEED or manualSpeed > SERVER_DEBUG_STILL_SPEED, stateKey, SERVER_DEBUG_STILL_MAX_SAMPLES) then return end

	print(string.format(
		"[V5DBG #%d] ts=%s speed=%.1f fwd=%.1f actual=%.1f desired=%.1f anim=%.1f follow=%s stock=%s cmdDist=%.1f tgtDist=%.1f originZ=%.1f mvVel=%.1f spd=%.1f ideal=%.1f tgtZ=%.1f %s mvAct=%s mvSeq=%s mint=%.3f nav=%s schedIdle=%s isnpc=%s npcMoving=%s hasObs=%s stepH=%.1f gEnt=%s gSpdVel=%.1f curWpZ=%s nextWpZ=%s goalZ=%s pathDist=%.1f internal=%s",
		ent:EntIndex(), Mod.Timestamp(), moveSpeed, forwardSpeed, manualSpeed, idealSpeed, anim.seqGroundSpeed, tostring(cmdValid), tostring(ent.StockMoveActive), cmdDist, targetDist,
		pos.z, moveSpeed, manualSpeed, idealSpeed, target.z, anim.text, tostring(moveAct), tostring(moveSeq), moveInterval, tostring(navType),
		tostring(ent:IsCurrentSchedule(SCHED_IDLE_STAND)), tostring(ent:IsNPC()),
		tostring(npcMoving), tostring(hasObstacles), stepHeight,
		formatGroundEntity(groundEnt), groundSpeedVel:Length2D(),
		curWaypoint and string.format("%.1f", curWaypoint.z) or "?",
		nextWaypoint and string.format("%.1f", nextWaypoint.z) or "?",
		goalPos and string.format("%.1f", goalPos.z) or "?", pathDist, internalProbe
	))
end

function Mod.PrintServerLine(ent)
	if not ent.DebugEnabled or CurTime() < (ent.NextDebugPrint or 0) then return end
	ent.NextDebugPrint = CurTime() + SERVER_DEBUG_INTERVAL

	if ent.Type == "nextbot" or ent.Base == "base_nextbot" then
		printV3ServerLine(ent)
		return
	end

	if ent.Type == "ai" or ent.Base == "base_ai" then
		printV5ServerLine(ent)
	end
end

function Mod.GetLayerInfo(ent, layerId, fallbackWeight, fallbackTargetWeight, fallbackRawWeight)
	local valid = layerId and ent.IsValidLayer and ent:IsValidLayer(layerId) or false
	local seq = -1
	local name = "none"
	local weight = fallbackWeight or 0
	local targetWeight = fallbackTargetWeight or 0
	local rawWeight = fallbackRawWeight or 0
	local cycle = -1
	local playbackRate = -1

	if valid then
		seq = ent.GetLayerSequence and ent:GetLayerSequence(layerId) or -1
		name = (seq and seq >= 0 and ent:GetSequenceName(seq)) or "?"
		weight = ent.GetLayerWeight and ent:GetLayerWeight(layerId) or weight
		cycle = ent.GetLayerCycle and ent:GetLayerCycle(layerId) or -1
		playbackRate = ent.GetLayerPlaybackRate and ent:GetLayerPlaybackRate(layerId) or -1
	end

	return {
		valid = valid,
		seq = seq,
		name = name,
		weight = weight,
		targetWeight = targetWeight,
		rawWeight = rawWeight,
		cycle = cycle,
		playbackRate = playbackRate
	}
end

function Mod.ScanLayers(ent, maxLayers)
	if not ent.IsValidLayer then return "noapi" end

	local parts = {}
	for layerId = 0, (maxLayers or 15) do
		if ent:IsValidLayer(layerId) then
			local seq = ent.GetLayerSequence and ent:GetLayerSequence(layerId) or -1
			local name = (seq and seq >= 0 and ent:GetSequenceName(seq)) or "?"
			local weight = ent.GetLayerWeight and ent:GetLayerWeight(layerId) or -1
			local cycle = ent.GetLayerCycle and ent:GetLayerCycle(layerId) or -1
			local playbackRate = ent.GetLayerPlaybackRate and ent:GetLayerPlaybackRate(layerId) or -1
			parts[#parts + 1] = string.format("%d:%d:%s:w=%.2f:cy=%.3f:pb=%.2f", layerId, seq, name, weight, cycle, playbackRate)
		end
	end

	return (#parts > 0) and table.concat(parts, ";") or "none"
end

function Mod.GetAnimSegment(ent)
	local seq = ent:GetSequence()
	local seqName = ent:GetSequenceName(seq) or "?"
	local act = ent.GetActivity and ent:GetActivity() or "?"
	local cycle = ent:GetCycle()
	local playbackRate = ent.GetPlaybackRate and ent:GetPlaybackRate() or -1
	local seqGroundSpeed = ent.GetSequenceGroundSpeed and ent:GetSequenceGroundSpeed(seq) or -1
	local seqMoveDist = ent.GetSequenceMoveDist and ent:GetSequenceMoveDist(seq) or -1
	local seqDeltaXY = 0
	local seqDeltaZ = 0

	if ent.GetSequenceMovement then
		local lastSeq = ent.DebugLastSeq or seq
		local lastCycle = ent.DebugLastCycle or cycle
		local startCycle = (lastSeq == seq) and lastCycle or cycle
		local endCycle = cycle
		if lastSeq == seq and cycle < startCycle then
			endCycle = cycle + 1
		end

		local ok, delta = ent:GetSequenceMovement(seq, startCycle, endCycle)
		if ok and isvector(delta) then
			seqDeltaXY = delta:Length2D()
			seqDeltaZ = delta.z
		end
	end

	ent.DebugLastSeq = seq
	ent.DebugLastCycle = cycle

	return {
		text = string.format(
			"seq=%d:%s act=%s cycle=%.3f pb=%.2f gspd=%.1f mdist=%.1f seqDxy=%.2f seqDz=%.2f layers=%s",
			seq, seqName, tostring(act), cycle, playbackRate, seqGroundSpeed, seqMoveDist, seqDeltaXY, seqDeltaZ, Mod.ScanLayers(ent)
		),
		seq = seq,
		seqName = seqName,
		act = act,
		cycle = cycle,
		playbackRate = playbackRate,
		seqGroundSpeed = seqGroundSpeed,
		seqMoveDist = seqMoveDist,
		seqDeltaXY = seqDeltaXY,
		seqDeltaZ = seqDeltaZ
	}
end

if CLIENT then

local DEFAULT_VISUAL_DEBUG_INTERVAL = 0.05
local VISUAL_DEBUG_STILL_MAX_SAMPLES = 6
local VISUAL_DEBUG_NO_FOLLOW_MAX_SAMPLES = 6

local function getBoneWorldPos(ent, boneName)
	local bone = ent:LookupBone(boneName)
	if not bone or bone < 0 then return nil end

	local mat = ent:GetBoneMatrix(bone)
	return mat and mat:GetTranslation() or nil
end

function Mod.GetLegAngles(ent, side)
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

function Mod.PrintVisualZ(ent, tag, data, interval)
	if not IsValid(ent) then return end

	local label = tostring(tag or Mod.GetEntityLabel(ent))
	local key = "_CityVisualDebugNext" .. label
	if ent[key] and CurTime() < ent[key] then return end
	ent[key] = CurTime() + (interval or DEFAULT_VISUAL_DEBUG_INTERVAL)

	data = data or {}
	local fmt = Mod.FormatNumber
	local hullZ = ent:GetPos().z
	local now = CurTime()
	local lastPos = ent._CityVisualDebugLastPos or ent:GetPos()
	local lastTime = ent._CityVisualDebugLastTime or now
	local posDelta = ent:GetPos() - lastPos
	local visualSpeed = Vector(posDelta.x, posDelta.y, 0):Length() / math.max(now - lastTime, 0.001)
	ent._CityVisualDebugLastPos = ent:GetPos()
	ent._CityVisualDebugLastTime = now
	local seq = ent:GetSequence()
	local seqName = ent:GetSequenceName(seq) or "?"
	local cycle = ent:GetCycle()
	local movingSeq = string.find(string.lower(seqName), "walk", 1, true) or string.find(string.lower(seqName), "run", 1, true)
	local noFollowKey = "_CityVisualDebugNoFollowSamples" .. label
	if visualSpeed <= SERVER_DEBUG_STILL_SPEED and not movingSeq then
		local noFollowSamples = (ent[noFollowKey] or 0) + 1
		ent[noFollowKey] = noFollowSamples
		if noFollowSamples > VISUAL_DEBUG_NO_FOLLOW_MAX_SAMPLES then return end
	else
		ent[noFollowKey] = 0
	end
	local lKnee, lThighPitch, lShinPitch = Mod.GetLegAngles(ent, "L")
	local rKnee, rThighPitch, rShinPitch = Mod.GetLegAngles(ent, "R")
	local stateKey = string.format(
		"%s:%d:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s",
		label,
		seq,
		tostring(data.activeFoot or "?"),
		fmt(hullZ),
		fmt(data.renderZ),
		fmt(data.groundZ),
		fmt(data.estZ),
		fmt(data.minGroundZ),
		fmt(data.maxGroundZ),
		fmt(data.leftHit),
		fmt(data.rightHit),
		fmt(data.renderZ and (data.renderZ - hullZ)),
		fmt(data.ikRuleStart),
		fmt(data.ikRulePeak),
		fmt(data.ikRuleTail),
		fmt(data.ikRuleEnd),
		tostring(data.ikRuleBlend or "?"),
		fmt(data.ikRuleWeight),
		tostring(data.poseDebug or "?")
	)
	if Mod.SuppressStill(ent, "_CityVisualDebug" .. label, false, stateKey, VISUAL_DEBUG_STILL_MAX_SAMPLES) then return end

	print(string.format(
		"[%s #%d] seq=%d:%s cycle=%.3f hullZ=%s renderZ=%s rDelta=%s active=%s groundZ=%s estZ=%s minZ=%s maxZ=%s ikStart=%s ikPeak=%s ikTail=%s ikEnd=%s ikBlend=%s ikWeight=%s poseNorm=%s Lloc=%s Lw=%s Lhit=%s Rloc=%s Rw=%s Rhit=%s footXY=%s foot3D=%s footDz=%s Lknee=%s Rknee=%s Lthigh=%s Rthigh=%s Lshin=%s Rshin=%s",
		label, ent:EntIndex(), seq, seqName, cycle, fmt(hullZ), fmt(data.renderZ), fmt(data.renderZ and (data.renderZ - hullZ)), tostring(data.activeFoot or "?"),
		fmt(data.groundZ), fmt(data.estZ), fmt(data.minGroundZ), fmt(data.maxGroundZ),
		fmt(data.ikRuleStart), fmt(data.ikRulePeak), fmt(data.ikRuleTail), fmt(data.ikRuleEnd), tostring(data.ikRuleBlend or "?"), fmt(data.ikRuleWeight), tostring(data.poseDebug or "?"),
		fmt(data.leftLocalZ), fmt(data.leftWorldZ), fmt(data.leftHit), fmt(data.rightLocalZ), fmt(data.rightWorldZ), fmt(data.rightHit),
		fmt(data.footDistXY), fmt(data.footDist3D), fmt(data.footDeltaZ),
		fmt(lKnee), fmt(rKnee), fmt(lThighPitch), fmt(rThighPitch), fmt(lShinPitch), fmt(rShinPitch)
	))
end

end
