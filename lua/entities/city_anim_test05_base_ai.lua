AddCSLuaFile()

ENT.Type = "ai"
ENT.Base = "base_ai"

DEFINE_BASECLASS("base_ai")

ENT.PrintName = "Test v5 (base_ai)"
ENT.Category = "Citizens"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Author = "City NPCs"

ENT.Purpose = "base_ai scripted NPC for stair/IK comparison with entity-local debug hooks."
ENT.Instructions = "Use citynpc_debug_entity while looking at it."

ENT.AutomaticFrameAdvance = true
ENT.RenderGroup = RENDERGROUP_OPAQUE

local MODEL = "models/Humans/Group03/male_01.mdl"
local STEP_HEIGHT = 18
local MOVE_REFRESH_INTERVAL = 0.25

local FOLLOW_STOP_DIST = 48
local FOLLOW_LOST_DIST = 30000
local FOLLOW_TARGET_OFFSET = 32
local DEBUG_INTERVAL = 0.05

local function debugTimestamp()
	local frac = RealTime and (RealTime() % 1) or 0
	return os.date("%H:%M:%S") .. string.format(".%03d", math.floor(frac * 1000))
end

local function fmtVec(v)
	if not isvector(v) then return tostring(v) end
	return string.format("(%.1f,%.1f,%.1f)", v.x, v.y, v.z)
end

local function printSpawnHull(ent, label)
	if not IsValid(ent) then return end

	local colMins, colMaxs = ent:GetCollisionBounds()
	local pos = ent:GetPos()
	local phys = ent:GetPhysicsObject()
	print(string.format(
		"[%s HULL #%d] model=%s solid=%s move=%s obbMin=%s obbMax=%s colMin=%s colMax=%s hullWorldMin=%s hullWorldMax=%s hullOrigin=%s physValid=%s physMove=%s physMotion=%s",
		label, ent:EntIndex(), tostring(ent:GetModel()), tostring(ent:GetSolid()), tostring(ent:GetMoveType()),
		fmtVec(ent:OBBMins()), fmtVec(ent:OBBMaxs()), fmtVec(colMins), fmtVec(colMaxs),
		fmtVec(pos + colMins), fmtVec(pos + colMaxs), fmtVec(pos),
		tostring(IsValid(phys)), IsValid(phys) and tostring(phys:IsMoveable()) or "?", IsValid(phys) and tostring(phys:IsMotionEnabled()) or "?"
	))
end

if SERVER then

local selectedByPlayer = {}

function ENT:Initialize()
	if BaseClass.Initialize then
		BaseClass.Initialize(self)
	end

	self:SetModel(MODEL)
	self:SetIK(true)
	self:SetUseType(SIMPLE_USE)

	self.Commander = nil
	self.StockMoveActive = false
	self.DefaultIdleApplied = false
	self.NextMoveRefresh = 0
	self.NextUseTime = 0
	self.NextDebugPrint = 0
	self.DebugOwner = nil
	self.DebugEnabled = false
	self.DebugLastPos = self:GetPos()
	self.DebugLastTime = CurTime()
	self.DebugFollowDist = -1
	self.DebugMoveTarget = vector_origin

	printSpawnHull(self, "v5-base_ai")
end

function ENT:SetDebugEnabled(ply, enabled)
	self.DebugEnabled = enabled
	self.DebugOwner = enabled and ply or nil
	self.NextDebugPrint = 0
	print("[v5-base_ai] Debug " .. (enabled and "ON" or "OFF") .. " for #" .. self:EntIndex())
end

function ENT:MoveToPosition(pos, run)
	if not isvector(pos) then return end

	self.DefaultIdleApplied = false
	self:SetSaveValue("m_vecLastPosition", pos)
	self:SetSchedule(run and SCHED_FORCED_GO_RUN or SCHED_FORCED_GO)
	self.StockMoveActive = true
	self.DebugMoveTarget = pos
end

function ENT:ClearCommander()
	self.Commander = nil
	self.DebugFollowDist = -1
end

function ENT:ForceDefaultIdle()
	self:ClearCommander()
	self:ClearEnemyMemory()
	self:SetEnemy(NULL)
	self:StopMoving(true)
	self:SetSchedule(SCHED_IDLE_STAND)
end

function ENT:GetCommanderMoveTarget(commander)
	local npcPos = self:GetPos()
	local cmdPos = commander:GetPos()
	local away = npcPos - cmdPos
	away.z = 0

	if away:LengthSqr() < 1 then
		away = -commander:GetForward()
	else
		away:Normalize()
	end

	return cmdPos + away * FOLLOW_TARGET_OFFSET
end

function ENT:ToggleCommander(activator)
	if not IsValid(activator) or not activator:IsPlayer() then return end
	if CurTime() < self.NextUseTime then return end
	self.NextUseTime = CurTime() + 0.2

	if self.Commander == activator then
		self:ClearCommander()
		self.StockMoveActive = false
		self.DefaultIdleApplied = false
		activator:PrintMessage(HUD_PRINTTALK, "[v5-base_ai] Follow disabled")
		return
	end

	self.Commander = activator
	self.StockMoveActive = false
	self.DefaultIdleApplied = false
	self.NextMoveRefresh = 0
	if not self.DebugEnabled then
		self:SetDebugEnabled(activator, true)
	end

	activator:PrintMessage(HUD_PRINTTALK, "[v5-base_ai] Follow enabled. Press E again to stop")
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
	local moveVel = self.GetMoveVelocity and self:GetMoveVelocity() or vector_origin
	local moveSpeed = moveVel:Length2D()
	local groundEnt = self.GetGroundEntity and self:GetGroundEntity() or NULL
	local groundSpeedVel = self.GetGroundSpeedVelocity and self:GetGroundSpeedVelocity() or vector_origin
	local stepHeight = self.GetStepHeight and self:GetStepHeight() or -1
	local npcMoving = self.IsMoving and self:IsMoving() or false
	local hasObstacles = self.HasObstacles and self:HasObstacles() or false
	local curWaypoint = self.GetCurWaypointPos and self:GetCurWaypointPos() or nil
	local nextWaypoint = self.GetNextWaypointPos and self:GetNextWaypointPos() or nil
	local goalPos = self.GetGoalPos and self:GetGoalPos() or nil
	local pathDist = self.GetPathDistanceToGoal and self:GetPathDistanceToGoal() or -1
	local fwd = self:GetForward()
	local forwardSpeed = moveVel.x * fwd.x + moveVel.y * fwd.y
	local idealSpeed = self.GetIdealMoveSpeed and self:GetIdealMoveSpeed() or -1
	local moveAct = self.GetMovementActivity and self:GetMovementActivity() or "?"
	local moveSeq = self.GetMovementSequence and self:GetMovementSequence() or -1
	self.DebugLastPos = pos
	self.DebugLastTime = now
	local target = self.DebugMoveTarget or vector_origin
	local targetDist = (target ~= vector_origin) and self:GetPos():Distance(target) or -1
	local seq = self:GetSequence()
	local seqName = self:GetSequenceName(self:GetSequence()) or "?"
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
	local moveInterval = self.GetMoveInterval and self:GetMoveInterval() or -1
	local navType = self.GetNavType and self:GetNavType() or -1
	local commander = self.Commander
	local cmdValid = IsValid(commander)
	local cmdDist = cmdValid and self:GetPos():Distance(commander:GetPos()) or -1

	print(string.format(
		"[V5DBG #%d] ts=%s speed=%.1f fwd=%.1f actual=%.1f desired=%.1f anim=%.1f follow=%s stock=%s cmdDist=%.1f tgtDist=%.1f originZ=%.1f mvVel=%.1f spd=%.1f ideal=%.1f tgtZ=%.1f seq=%d:%s act=%s mvAct=%s mvSeq=%s cycle=%.3f pb=%.2f gspd=%.1f mdist=%.1f seqDxy=%.2f seqDz=%.2f mint=%.3f nav=%s schedIdle=%s isnpc=%s npcMoving=%s hasObs=%s stepH=%.1f gEnt=%s gSpdVel=%.1f curWpZ=%s nextWpZ=%s goalZ=%s pathDist=%.1f",
		self:EntIndex(), debugTimestamp(), moveSpeed, forwardSpeed, manualSpeed, idealSpeed, seqGroundSpeed, tostring(cmdValid), tostring(self.StockMoveActive), cmdDist, targetDist,
		pos.z, moveSpeed, manualSpeed, idealSpeed, target.z, seq, seqName, tostring(act), tostring(moveAct), tostring(moveSeq), cycle,
		playbackRate, seqGroundSpeed, seqMoveDist, seqDeltaXY, seqDeltaZ, moveInterval, tostring(navType),
		tostring(self:IsCurrentSchedule(SCHED_IDLE_STAND)), tostring(self:IsNPC()),
		tostring(npcMoving), tostring(hasObstacles), stepHeight,
		IsValid(groundEnt) and (groundEnt:GetClass() .. "#" .. groundEnt:EntIndex()) or "none", groundSpeedVel:Length2D(),
		curWaypoint and string.format("%.1f", curWaypoint.z) or "?",
		nextWaypoint and string.format("%.1f", nextWaypoint.z) or "?",
		goalPos and string.format("%.1f", goalPos.z) or "?", pathDist
	))
end

function ENT:Use(activator)
	self:ToggleCommander(activator)
end

function ENT:AcceptInput(name, activator)
	if name ~= "Use" then
		if BaseClass.AcceptInput then
			return BaseClass.AcceptInput(self, name, activator)
		end

		return
	end

	self:ToggleCommander(activator)
	return true
end

function ENT:RunV5Think()
	if self.Commander ~= nil and not IsValid(self.Commander) then
		self:ClearCommander()
	end

	if IsValid(self.Commander) then
		local commander = self.Commander
		local dist = self:GetPos():Distance(commander:GetPos())
		self.DebugFollowDist = dist

		if dist > FOLLOW_LOST_DIST then
			self:ClearCommander()
			self:StopMoving(true)
			self.DefaultIdleApplied = false
		elseif dist <= FOLLOW_STOP_DIST then
			self:StopMoving(false)
			self.DebugMoveTarget = vector_origin
		else
			if CurTime() >= self.NextMoveRefresh then
				local target = self:GetCommanderMoveTarget(commander)
				self:SetSaveValue("m_vecLastPosition", target)
				self:SetSchedule(SCHED_FORCED_GO)
				self.DebugMoveTarget = target
				self.NextMoveRefresh = CurTime() + MOVE_REFRESH_INTERVAL
			end
		end
	elseif self.StockMoveActive then
		local target = self.DebugMoveTarget or vector_origin
		local targetDist = (target ~= vector_origin) and self:GetPos():Distance(target) or math.huge
		local moveVel = self.GetMoveVelocity and self:GetMoveVelocity() or vector_origin
		if targetDist <= 25 and moveVel:Length2D() < 5 then
			self.StockMoveActive = false
			self.DefaultIdleApplied = false
		end
	elseif not self.DefaultIdleApplied then
		self:ForceDefaultIdle()
		self.DefaultIdleApplied = true
	end

	self:PrintDebugLine()
end

function ENT:Think()
	if BaseClass.Think then
		BaseClass.Think(self)
	end

	self:RunV5Think()
end

concommand.Remove("citynpc_v5_debug")
concommand.Add("citynpc_v5_debug", function(ply)
	if not IsValid(ply) then return end

	local ent = ply:GetEyeTrace().Entity
	if not IsValid(ent) or ent:GetClass() ~= "city_anim_test05_base_ai" then
		ply:PrintMessage(HUD_PRINTTALK, "[v5-base_ai] Look at v5 first")
		return
	end

	ent:SetDebugEnabled(ply, not ent.DebugEnabled)
end)

concommand.Remove("citynpc_v5_move")
concommand.Add("citynpc_v5_move", function(ply, _, args)
	if not IsValid(ply) then return end

	local tr = ply:GetEyeTrace()
	local ent = tr.Entity
	if IsValid(ent) and ent:GetClass() == "city_anim_test05_base_ai" then
		selectedByPlayer[ply] = ent
		ent:SetDebugEnabled(ply, true)
		ply:PrintMessage(HUD_PRINTTALK, "[v5-base_ai] Selected for stock move. Look at destination and run citynpc_v5_move")
		return
	end

	local selected = selectedByPlayer[ply]
	if not IsValid(selected) then
		ply:PrintMessage(HUD_PRINTTALK, "[v5-base_ai] Look at v5 and run citynpc_v5_move first")
		return
	end

	if not tr.Hit then return end

	selected:ClearCommander()
	selected:MoveToPosition(tr.HitPos, args[1] == "run")
	ply:PrintMessage(HUD_PRINTTALK, "[v5-base_ai] Stock move order sent")
end)

end

if CLIENT then

function ENT:Initialize()
	if BaseClass.Initialize then
		BaseClass.Initialize(self)
	end

	self:SetModel(MODEL)
	self:SetIK(true)
end

function ENT:Draw()
	self:SetIK(true)
	self:SetupBones()
	self:DrawModel()
end

function ENT:CityDebugLabel()
	return "v5-base_ai"
end

end
