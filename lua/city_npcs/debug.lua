CityNPCDebug = CityNPCDebug or {}

function CityNPCDebug.Timestamp()
	local frac = RealTime and (RealTime() % 1) or 0
	return os.date("%H:%M:%S") .. string.format(".%03d", math.floor(frac * 1000))
end

function CityNPCDebug.FormatVector(v)
	if not isvector(v) then return tostring(v) end
	return string.format("(%.1f,%.1f,%.1f)", v.x, v.y, v.z)
end

function CityNPCDebug.PrintSpawnHull(ent, label)
	if not IsValid(ent) then return end

	local colMins, colMaxs = ent:GetCollisionBounds()
	local pos = ent:GetPos()
	local phys = ent:GetPhysicsObject()
	print(string.format(
		"[%s HULL #%d] model=%s solid=%s move=%s obbMin=%s obbMax=%s colMin=%s colMax=%s hullWorldMin=%s hullWorldMax=%s hullOrigin=%s physValid=%s physMove=%s physMotion=%s",
		label, ent:EntIndex(), tostring(ent:GetModel()), tostring(ent:GetSolid()), tostring(ent:GetMoveType()),
		CityNPCDebug.FormatVector(ent:OBBMins()), CityNPCDebug.FormatVector(ent:OBBMaxs()), CityNPCDebug.FormatVector(colMins), CityNPCDebug.FormatVector(colMaxs),
		CityNPCDebug.FormatVector(pos + colMins), CityNPCDebug.FormatVector(pos + colMaxs), CityNPCDebug.FormatVector(pos),
		tostring(IsValid(phys)), IsValid(phys) and tostring(phys:IsMoveable()) or "?", IsValid(phys) and tostring(phys:IsMotionEnabled()) or "?"
	))
end

function CityNPCDebug.GetLayerInfo(ent, layerId, fallbackWeight, fallbackTargetWeight, fallbackRawWeight)
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

function CityNPCDebug.ScanLayers(ent, maxLayers)
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

function CityNPCDebug.GetAnimSegment(ent)
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
			seq, seqName, tostring(act), cycle, playbackRate, seqGroundSpeed, seqMoveDist, seqDeltaXY, seqDeltaZ, CityNPCDebug.ScanLayers(ent)
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
