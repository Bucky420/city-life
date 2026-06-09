AddCSLuaFile()
AddCSLuaFile("entities/modules/npc_debug.lua")
include("entities/modules/npc_debug.lua")

local NPCDebug = CityNPCs.Modules.npc_debug

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
	self.DebugSaveProbePrinted = false
	self.DebugKeyValues = {}

	NPCDebug.PrintSpawnHull(self, "v5-base_ai")
end

function ENT:KeyValue(key, value)
	self.DebugKeyValues = self.DebugKeyValues or {}
	self.DebugKeyValues[tostring(key)] = tostring(value)
end

function ENT:SetDebugEnabled(ply, enabled)
	NPCDebug.SetServerEnabled(self, ply, enabled, "v5-base_ai")
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
	NPCDebug.PrintServerLine(self)
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

local FOOT_TRACE_RADIUS = 2.5
local FOOT_TRACE_HEIGHT = 20

local function getFootData(ent, side)
	local bone = ent:LookupBone("ValveBiped.Bip01_" .. side .. "_Foot")
	if not bone or bone < 0 then return nil end

	local mat = ent:GetBoneMatrix(bone)
	if not mat then return nil end

	local footPos = mat:GetTranslation()
	local tr = util.TraceHull({
		start = footPos + Vector(0, 0, FOOT_TRACE_HEIGHT),
		endpos = footPos - Vector(0, 0, FOOT_TRACE_HEIGHT),
		mins = Vector(-FOOT_TRACE_RADIUS, -FOOT_TRACE_RADIUS, 0),
		maxs = Vector(FOOT_TRACE_RADIUS, FOOT_TRACE_RADIUS, FOOT_TRACE_RADIUS * 2),
		filter = ent,
		mask = MASK_SOLID
	})

	return {
		worldPos = footPos,
		localZ = ent:WorldToLocal(footPos).z,
		worldZ = footPos.z,
		hitZ = tr.Hit and tr.HitPos.z or nil,
		fraction = tr.Fraction,
		normalZ = tr.HitNormal and tr.HitNormal.z or nil,
		startSolid = tr.StartSolid,
		allSolid = tr.AllSolid,
		hitWorld = tr.HitWorld,
		hitNonWorld = tr.HitNonWorld,
		hitEntity = IsValid(tr.Entity) and (tr.Entity:GetClass() .. "#" .. tr.Entity:EntIndex()) or (tr.HitWorld and "world" or "none")
	}
end

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

	if self:GetNWBool("CityNPCDebugEnabled", false) then
		local leftFoot = getFootData(self, "L")
		local rightFoot = getFootData(self, "R")
		local renderOrigin = self.GetRenderOrigin and self:GetRenderOrigin() or nil
		local renderZ = isvector(renderOrigin) and renderOrigin.z or nil
		local networkOrigin = self.GetNetworkOrigin and self:GetNetworkOrigin() or nil
		local leftHit = leftFoot and leftFoot.hitZ
		local rightHit = rightFoot and rightFoot.hitZ
		local minHit = leftHit and rightHit and math.min(leftHit, rightHit) or (leftHit or rightHit)
		local maxHit = leftHit and rightHit and math.max(leftHit, rightHit) or (leftHit or rightHit)
		local onGround
		if self.IsOnGround then
			onGround = self:IsOnGround()
		end
		local hasBoneManipulations
		if self.HasBoneManipulations then
			hasBoneManipulations = self:HasBoneManipulations()
		end
		local footDistXY, footDist3D, footDeltaZ
		if leftFoot and rightFoot then
			local footDelta = leftFoot.worldPos - rightFoot.worldPos
			footDistXY = Vector(footDelta.x, footDelta.y, 0):Length()
			footDist3D = footDelta:Length()
			footDeltaZ = leftFoot.worldZ - rightFoot.worldZ
		end
		NPCDebug.PrintVisualZ(self, "V5ZDBG", {
			renderZ = renderZ,
			networkZ = isvector(networkOrigin) and networkOrigin.z or nil,
			onGround = onGround,
			sequenceCount = self.GetSequenceCount and self:GetSequenceCount() or nil,
			hasBoneManipulations = hasBoneManipulations,
			groundZ = minHit,
			minGroundZ = minHit,
			maxGroundZ = maxHit,
			leftLocalZ = leftFoot and leftFoot.localZ,
			leftWorldZ = leftFoot and leftFoot.worldZ,
			leftHit = leftHit,
			leftFraction = leftFoot and leftFoot.fraction,
			leftNormalZ = leftFoot and leftFoot.normalZ,
			leftStartSolid = leftFoot and leftFoot.startSolid,
			leftHitWorld = leftFoot and leftFoot.hitWorld,
			rightLocalZ = rightFoot and rightFoot.localZ,
			rightWorldZ = rightFoot and rightFoot.worldZ,
			rightHit = rightHit,
			rightFraction = rightFoot and rightFoot.fraction,
			rightNormalZ = rightFoot and rightFoot.normalZ,
			rightStartSolid = rightFoot and rightFoot.startSolid,
			rightHitWorld = rightFoot and rightFoot.hitWorld,
			footDistXY = footDistXY,
			footDist3D = footDist3D,
			footDeltaZ = footDeltaZ
		})
	end

	self:DrawModel()
end

function ENT:CityDebugLabel()
	return "v5-base_ai"
end

end
