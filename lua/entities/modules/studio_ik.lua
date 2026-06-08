CityNPCs = CityNPCs or {}
CityNPCs.Modules = CityNPCs.Modules or {}

local StudioIK = CityNPCs.Modules.studio_ik or {}
CityNPCs.Modules.studio_ik = StudioIK

local IK_GROUND = 3
local STUDIOHDR_NUMLOCALANIM = 180
local STUDIOHDR_LOCALANIMINDEX = 184
local STUDIOHDR_NUMLOCALSEQ = 188
local STUDIOHDR_LOCALSEQINDEX = 192
local STUDIOHDR_SZANIMBLOCKNAMEINDEX = 348
local STUDIOHDR_NUMANIMBLOCKS = 352
local STUDIOHDR_ANIMBLOCKINDEX = 356
local SEQDESC_SIZE = 212
local SEQDESC_LABELINDEX = 4
local SEQDESC_ANIMINDEXINDEX = 60
local SEQDESC_GROUPSIZE = 68
local SEQDESC_NUMIKLOCKS = 164
local SEQDESC_IKLOCKINDEX = 168
local ANIMDESC_SIZE = 100
local ANIMDESC_NAMEINDEX = 4
local ANIMDESC_FPS = 8
local ANIMDESC_FLAGS = 12
local ANIMDESC_NUMFRAMES = 16
local ANIMDESC_ANIMBLOCK = 52
local ANIMDESC_ANIMINDEX = 56
local ANIMDESC_NUMIKRULES = 60
local ANIMDESC_IKRULEINDEX = 64
local ANIMDESC_ANIMBLOCKIKRULEINDEX = 68
local IKRULE_SIZE = 152
local IKLOCK_SIZE = 32

StudioIK.Cache = StudioIK.Cache or {}
StudioIK.Errors = StudioIK.Errors or {}

function StudioIK.ClearCache(model)
	if model and model ~= "" then
		model = model:gsub("\\", "/")
		StudioIK.Cache[model] = nil
		StudioIK.Errors[model] = nil
		return
	end

	StudioIK.Cache = {}
	StudioIK.Errors = {}
end

local function readAt(f, pos, reader)
	f:Seek(pos)
	return reader(f)
end

local function readLongAt(f, pos)
	return readAt(f, pos, f.ReadLong)
end

local function readFloatAt(f, pos)
	return readAt(f, pos, f.ReadFloat)
end

local function readStringAt(f, pos, maxLen)
	f:Seek(pos)
	local s = f:Read(maxLen or 128) or ""
	local nul = s:find("\0", 1, true)
	if nul then s = s:sub(1, nul - 1) end
	return s
end

local function readShortAt(f, pos)
	return readAt(f, pos, f.ReadShort)
end

local function cycleDistance(a, b)
	local d = math.abs(a - b)
	return math.min(d, 1 - d)
end

local function parseGroundRule(f, base)
	local ruleType = readLongAt(f, base + 4)
	if ruleType ~= IK_GROUND then return nil end

	return {
		index = readLongAt(f, base),
		type = ruleType,
		chain = readLongAt(f, base + 8),
		bone = readLongAt(f, base + 12),
		slot = readLongAt(f, base + 16),
		height = readFloatAt(f, base + 20),
		radius = readFloatAt(f, base + 24),
		floor = readFloatAt(f, base + 28),
		start = readFloatAt(f, base + 76),
		peak = readFloatAt(f, base + 80),
		tail = readFloatAt(f, base + 84),
		finish = readFloatAt(f, base + 88),
		contact = readFloatAt(f, base + 96),
		drop = readFloatAt(f, base + 100),
		top = readFloatAt(f, base + 104)
	}
end

local function parseIkLock(f, base)
	return {
		chain = readLongAt(f, base),
		posWeight = readFloatAt(f, base + 4),
		localQWeight = readFloatAt(f, base + 8),
		flags = readLongAt(f, base + 12)
	}
end

local function defaultAnimBlockName(model)
	return model:gsub("%.mdl$", ".ani")
end

local function openAnimBlock(model, blockName)
	blockName = (blockName and blockName ~= "") and blockName or defaultAnimBlockName(model)
	return file.Open(blockName, "rb", "GAME"), blockName
end

function StudioIK.LoadModel(model)
	if not model or model == "" then return nil end
	model = model:gsub("\\", "/")
	local cached = StudioIK.Cache[model]
	if cached ~= nil then return cached or nil end

	local f = file.Open(model, "rb", "GAME")
	if not f then
		StudioIK.Cache[model] = false
		StudioIK.Errors[model] = "file.Open failed"
		return nil
	end

	local ok, data = pcall(function()
		local numAnim = readLongAt(f, STUDIOHDR_NUMLOCALANIM)
		local animIndex = readLongAt(f, STUDIOHDR_LOCALANIMINDEX)
		local numSeq = readLongAt(f, STUDIOHDR_NUMLOCALSEQ)
		local seqIndex = readLongAt(f, STUDIOHDR_LOCALSEQINDEX)
		local animBlockNameIndex = readLongAt(f, STUDIOHDR_SZANIMBLOCKNAMEINDEX)
		local animBlockName = animBlockNameIndex > 0 and readStringAt(f, animBlockNameIndex, 128) or defaultAnimBlockName(model)
		local numAnimBlocks = readLongAt(f, STUDIOHDR_NUMANIMBLOCKS)
		local animBlockIndex = readLongAt(f, STUDIOHDR_ANIMBLOCKINDEX)
		local animBlockFile, animBlockOpenName
		local parsed = {
			model = model,
			anims = {},
			animBlocks = {},
			sequences = {},
			byName = {},
			header = {
				numAnim = numAnim,
				animIndex = animIndex,
				numSeq = numSeq,
				seqIndex = seqIndex,
				animBlockName = animBlockName,
				numAnimBlocks = numAnimBlocks,
				animBlockIndex = animBlockIndex
			}
		}

		for block = 0, math.max(numAnimBlocks - 1, -1) do
			local blockBase = animBlockIndex + block * 8
			parsed.animBlocks[block] = {
				datastart = readLongAt(f, blockBase),
				dataend = readLongAt(f, blockBase + 4)
			}
		end

		for animId = 0, numAnim - 1 do
			local animBase = animIndex + animId * ANIMDESC_SIZE
			local nameIndex = readLongAt(f, animBase + ANIMDESC_NAMEINDEX)
			parsed.anims[animId] = {
				id = animId,
				name = nameIndex > 0 and readStringAt(f, animBase + nameIndex, 128) or "",
				fps = readFloatAt(f, animBase + ANIMDESC_FPS),
				flags = readLongAt(f, animBase + ANIMDESC_FLAGS),
				numframes = readLongAt(f, animBase + ANIMDESC_NUMFRAMES),
				animblock = readLongAt(f, animBase + ANIMDESC_ANIMBLOCK),
				animindex = readLongAt(f, animBase + ANIMDESC_ANIMINDEX),
				numikrules = readLongAt(f, animBase + ANIMDESC_NUMIKRULES),
				ikruleindex = readLongAt(f, animBase + ANIMDESC_IKRULEINDEX),
				animblockikruleindex = readLongAt(f, animBase + ANIMDESC_ANIMBLOCKIKRULEINDEX)
			}
		end

		for seqId = 0, numSeq - 1 do
			local seqBase = seqIndex + seqId * SEQDESC_SIZE
			local label = readStringAt(f, seqBase + readLongAt(f, seqBase + SEQDESC_LABELINDEX), 128)
			local groupsX = math.max(readLongAt(f, seqBase + SEQDESC_GROUPSIZE), 1)
			local groupsY = math.max(readLongAt(f, seqBase + SEQDESC_GROUPSIZE + 4), 1)
			local blendCount = groupsX * groupsY
			local animIndexIndex = readLongAt(f, seqBase + SEQDESC_ANIMINDEXINDEX)
			local animRefs = {}
			local rules = {}

			for blend = 0, blendCount - 1 do
				local animId = readShortAt(f, seqBase + animIndexIndex + blend * 2)
				animRefs[#animRefs + 1] = animId
				if animId >= 0 and animId < numAnim then
					local animBase = animIndex + animId * ANIMDESC_SIZE
					local animBlock = readLongAt(f, animBase + ANIMDESC_ANIMBLOCK)
					local numRules = readLongAt(f, animBase + ANIMDESC_NUMIKRULES)
					local ruleIndex = readLongAt(f, animBase + ANIMDESC_IKRULEINDEX)
					local animBlockRuleIndex = readLongAt(f, animBase + ANIMDESC_ANIMBLOCKIKRULEINDEX)
					local ruleFile = f
					local ruleBase = animBase
					if ruleIndex <= 0 and animBlock == 0 then
						ruleIndex = animBlockRuleIndex
					elseif ruleIndex <= 0 and animBlock > 0 and animBlockRuleIndex > 0 and animBlockIndex > 0 and animBlock < numAnimBlocks then
						if not animBlockFile then
							animBlockFile, animBlockOpenName = openAnimBlock(model, animBlockName)
							parsed.header.animBlockOpenName = animBlockOpenName
							parsed.header.animBlockOpened = animBlockFile ~= nil
						end
						if animBlockFile then
							local blockEntry = animBlockIndex + animBlock * 8
							ruleFile = animBlockFile
							ruleBase = readLongAt(f, blockEntry)
							ruleIndex = animBlockRuleIndex
						end
					end
					if numRules > 0 and ruleIndex > 0 then
						for i = 0, numRules - 1 do
							local rule = parseGroundRule(ruleFile, ruleBase + ruleIndex + i * IKRULE_SIZE)
							if rule then
								rule.anim = animId
								rule.animBlock = animBlock
								rules[#rules + 1] = rule
							end
						end
					end
				end
			end

			local locks = {}
			local numLocks = readLongAt(f, seqBase + SEQDESC_NUMIKLOCKS)
			local lockIndex = readLongAt(f, seqBase + SEQDESC_IKLOCKINDEX)
			if numLocks > 0 and lockIndex > 0 then
				for i = 0, numLocks - 1 do
					locks[#locks + 1] = parseIkLock(f, seqBase + lockIndex + i * IKLOCK_SIZE)
				end
			end

			local seq = { id = seqId, name = label, animRefs = animRefs, rules = rules, locks = locks }
			parsed.sequences[seqId] = seq
			parsed.byName[label] = seq
		end

		if animBlockFile then animBlockFile:Close() end

		return parsed
	end)

	f:Close()
	StudioIK.Cache[model] = ok and data or false
	StudioIK.Errors[model] = ok and nil or tostring(data)
	return ok and data or nil
end

function StudioIK.GetSequence(model, sequenceName)
	local data = StudioIK.LoadModel(model)
	return data and data.byName and data.byName[sequenceName] or nil
end

function StudioIK.GetClosestGroundRule(model, sequenceName, contactCycle)
	local seq = StudioIK.GetSequence(model, sequenceName)
	if not seq or not contactCycle then return nil end

	local bestRule
	local bestDist
	for _, rule in ipairs(seq.rules or {}) do
		local dist = cycleDistance(rule.contact or rule.peak or 0, contactCycle)
		if not bestDist or dist < bestDist then
			bestDist = dist
			bestRule = rule
		end
	end

	return bestRule, bestDist
end

local function fmt(v)
	return isnumber(v) and string.format("%.3f", v) or tostring(v)
end

function StudioIK.GetDebugLines(model, sequenceName)
	model = (model and model ~= "") and model:gsub("\\", "/") or "models/humans/male_shared.mdl"
	local data = StudioIK.LoadModel(model)
	local lines = {}
	lines[#lines + 1] = "[StudioIK] model=" .. model

	if not data then
		lines[#lines + 1] = "[StudioIK] load failed: " .. tostring(StudioIK.Errors[model] or "unknown")
		return lines
	end

	local header = data.header or {}
	lines[#lines + 1] = string.format(
		"[StudioIK] header numAnim=%s animIndex=%s numSeq=%s seqIndex=%s animBlockName=%s numAnimBlocks=%s animBlockIndex=%s animBlockOpened=%s animBlockOpenName=%s",
		tostring(header.numAnim), tostring(header.animIndex), tostring(header.numSeq), tostring(header.seqIndex), tostring(header.animBlockName),
		tostring(header.numAnimBlocks), tostring(header.animBlockIndex), tostring(header.animBlockOpened), tostring(header.animBlockOpenName)
	)

	local seq = sequenceName and data.byName and data.byName[sequenceName]
	if sequenceName and not seq then
		lines[#lines + 1] = "[StudioIK] sequence not found: " .. tostring(sequenceName)
	end

	if not seq then
		local matches = {}
		for _, candidate in pairs(data.sequences or {}) do
			local name = tostring(candidate.name or "")
			if name:lower():find("walk", 1, true) or name:lower():find("run", 1, true) then
				matches[#matches + 1] = string.format("%d:%s rules=%d locks=%d", candidate.id or -1, name, #(candidate.rules or {}), #(candidate.locks or {}))
			end
		end
		lines[#lines + 1] = "[StudioIK] walk/run sequences: " .. (#matches > 0 and table.concat(matches, "; ") or "none")
		return lines
	end

	lines[#lines + 1] = string.format("[StudioIK] sequence %d:%s rules=%d locks=%d", seq.id or -1, tostring(seq.name), #(seq.rules or {}), #(seq.locks or {}))
	for i, lock in ipairs(seq.locks or {}) do
		lines[#lines + 1] = string.format("[StudioIK] lock[%d] chain=%s posW=%s localQW=%s flags=%s", i, tostring(lock.chain), fmt(lock.posWeight), fmt(lock.localQWeight), tostring(lock.flags))
	end
	for i, rule in ipairs(seq.rules or {}) do
		lines[#lines + 1] = string.format("[StudioIK] groundRule[%d] anim=%s block=%s chain=%s slot=%s contact=%s start=%s peak=%s tail=%s end=%s floor=%s height=%s radius=%s drop=%s top=%s", i, tostring(rule.anim), tostring(rule.animBlock), tostring(rule.chain), tostring(rule.slot), fmt(rule.contact), fmt(rule.start), fmt(rule.peak), fmt(rule.tail), fmt(rule.finish), fmt(rule.floor), fmt(rule.height), fmt(rule.radius), fmt(rule.drop), fmt(rule.top))
	end
	return lines
end

function StudioIK.GetDumpLines(model)
	model = (model and model ~= "") and model:gsub("\\", "/") or "models/humans/male_shared.mdl"
	local data = StudioIK.LoadModel(model)
	local lines = {}
	lines[#lines + 1] = "[StudioIKDUMP] model=" .. model

	if not data then
		lines[#lines + 1] = "[StudioIKDUMP] load failed: " .. tostring(StudioIK.Errors[model] or "unknown")
		return lines
	end

	local header = data.header or {}
	lines[#lines + 1] = string.format(
		"[StudioIKDUMP] header numAnim=%s animIndex=%s numSeq=%s seqIndex=%s animBlockName=%s numAnimBlocks=%s animBlockIndex=%s animBlockOpened=%s animBlockOpenName=%s",
		tostring(header.numAnim), tostring(header.animIndex), tostring(header.numSeq), tostring(header.seqIndex), tostring(header.animBlockName),
		tostring(header.numAnimBlocks), tostring(header.animBlockIndex), tostring(header.animBlockOpened), tostring(header.animBlockOpenName)
	)

	for id = 0, #(data.animBlocks or {}) do
		local block = data.animBlocks[id]
		if block then
			lines[#lines + 1] = string.format("[StudioIKDUMP] animblock[%d] datastart=%s dataend=%s", id, tostring(block.datastart), tostring(block.dataend))
		end
	end

	for id = 0, (header.numAnim or 0) - 1 do
		local anim = data.anims and data.anims[id]
		if anim then
			lines[#lines + 1] = string.format(
				"[StudioIKDUMP] anim[%d] name=%s fps=%s frames=%s flags=%s animblock=%s animindex=%s numikrules=%s ikruleindex=%s animblockikruleindex=%s",
				id, tostring(anim.name), fmt(anim.fps), tostring(anim.numframes), tostring(anim.flags), tostring(anim.animblock), tostring(anim.animindex),
				tostring(anim.numikrules), tostring(anim.ikruleindex), tostring(anim.animblockikruleindex)
			)
		end
	end

	for id = 0, (header.numSeq or 0) - 1 do
		local seq = data.sequences and data.sequences[id]
		if seq then
			lines[#lines + 1] = string.format(
				"[StudioIKDUMP] seq[%d] name=%s animRefs=%s rules=%d locks=%d",
				id, tostring(seq.name), table.concat(seq.animRefs or {}, ","), #(seq.rules or {}), #(seq.locks or {})
			)
			for i, rule in ipairs(seq.rules or {}) do
				lines[#lines + 1] = string.format("[StudioIKDUMP] seq[%d].groundRule[%d] anim=%s block=%s chain=%s slot=%s contact=%s start=%s peak=%s tail=%s end=%s floor=%s height=%s radius=%s drop=%s top=%s", id, i, tostring(rule.anim), tostring(rule.animBlock), tostring(rule.chain), tostring(rule.slot), fmt(rule.contact), fmt(rule.start), fmt(rule.peak), fmt(rule.tail), fmt(rule.finish), fmt(rule.floor), fmt(rule.height), fmt(rule.radius), fmt(rule.drop), fmt(rule.top))
			end
			for i, lock in ipairs(seq.locks or {}) do
				lines[#lines + 1] = string.format("[StudioIKDUMP] seq[%d].lock[%d] chain=%s posW=%s localQW=%s flags=%s", id, i, tostring(lock.chain), fmt(lock.posWeight), fmt(lock.localQWeight), tostring(lock.flags))
			end
		end
	end

	return lines
end

return StudioIK
