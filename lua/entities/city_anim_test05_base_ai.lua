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

	NPCDebug.PrintSpawnHull(self, "v5-base_ai")
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
