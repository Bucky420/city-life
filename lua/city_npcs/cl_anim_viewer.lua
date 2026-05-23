CityNPCs = CityNPCs or {}

local ANIM_ENT_CLASS = "city_anim_viewer_ent"
do
    local existing = scripted_ents and scripted_ents.Get(ANIM_ENT_CLASS)
    if not existing then
        local TAB = {
            Type = "anim",
            Base = "base_gmodentity",
            PrintName = "City Anim Viewer",
            Spawnable = false,
            AdminOnly = false,
        }
        function TAB:Initialize()
        end
        function TAB:Draw()
            self:DrawModel()
        end
        scripted_ents.Register(TAB, ANIM_ENT_CLASS)
    end
end

local function OpenAnimViewer()
    local frame = vgui.Create("DFrame")
    frame:SetSize(900, 600)
    frame:SetTitle("Animation Viewer")
    frame:Center()
    frame:MakePopup()
    frame:SetSizable(true)
    frame:SetMinWidth(700)
    frame:SetMinHeight(450)

    local PAD = 6
    local TITLE_H = 25
    local SIDE_W = 300

    local ent = nil
    local useGestures = false

    local function CleanupEntity()
        if IsValid(ent) then
            ent:Remove()
            ent = nil
        end
    end
    frame:SetDeleteOnClose(false)
    frame.OnClose = function()
        CleanupEntity()
        frame:Remove()
    end

    local mdl = vgui.Create("DModelPanel", frame)
    mdl.Entity = nil

    local modelLabel = vgui.Create("DLabel", frame)
    modelLabel:SetText("Model:")
    modelLabel:SetContentAlignment(3)

    local modelInput = vgui.Create("DTextEntry", frame)
    modelInput:SetText("models/Humans/Group03/male_01.mdl")

    local loadBtn = vgui.Create("DButton", frame)
    loadBtn:SetText("Load")

    local speedSlider = vgui.Create("DNumSlider", frame)
    speedSlider:SetMin(0)
    speedSlider:SetMax(10)
    speedSlider:SetDecimals(2)
    speedSlider:SetValue(1)
    speedSlider:SetText("Speed")

    local dirSlider = vgui.Create("DNumSlider", frame)
    dirSlider:SetMin(-180)
    dirSlider:SetMax(180)
    dirSlider:SetDecimals(1)
    dirSlider:SetValue(0)
    dirSlider:SetText("Dir")

    local baseSelector = vgui.Create("DComboBox", frame)
    baseSelector:SetText("Base Animation")

    local infoLabel = vgui.Create("DLabel", frame)
    infoLabel:SetText("Select a sequence")
    infoLabel:SetTextColor(Color(180, 220, 255))

    local copyBtn = vgui.Create("DButton", frame)
    copyBtn:SetText("Copy")
    copyBtn:SetToolTip("Copy selected sequence name to clipboard")

    local pausedLabel = vgui.Create("DLabel", frame)
    pausedLabel:SetText("GAME PAUSED")
    pausedLabel:SetTextColor(Color(255, 0, 0))
    pausedLabel:SetContentAlignment(5)
    pausedLabel:SetFont("DermaDefaultBold")
    pausedLabel:SetVisible(false)

    local searchBar = vgui.Create("DTextEntry", frame)
    searchBar:SetPlaceholderText("Search sequences...")

    local seqList = vgui.Create("DListView", frame)
    seqList:SetMultiSelect(false)
    seqList:AddColumn("Animation")

    local seqData = {}
    local lastSearch = ""
    local baseIdx = {}
    local currentBase = -1
    local lastSelectedName = ""

    local function RefreshList(filter)
        seqList:Clear()
        filter = filter and filter:lower() or ""
        for _, d in ipairs(seqData) do
            if filter == "" or d.name:lower():find(filter, 1, true) or d.actStr:lower():find(filter, 1, true) then
                seqList:AddLine(d.label).SeqIndex = d.idx
            end
        end
    end

    local function PopulateSeqs()
        seqData = {}
        seqList:Clear()
        if not IsValid(ent) then return end
        baseIdx = {}
        baseSelector:Clear()
        local count = ent:GetSequenceCount()
        for i = 0, count - 1 do
            local name = ent:GetSequenceName(i) or "unknown"

            local act = ent:GetSequenceActivity(i)
            if act == ACT_IDLE then baseIdx.idle = i end
            if act == ACT_WALK then baseIdx.walk = i end
            table.insert(seqData, {idx = i, name = name, actStr = tostring(act), label = name .. " (" .. act .. ")"})
        end
        if baseIdx.idle then baseSelector:AddChoice("Idle", "idle") end
        if baseIdx.walk then baseSelector:AddChoice("Walk", "walk") end
        RefreshList(searchBar:GetText())
        if count > 0 then
            local first = baseIdx.idle or 0
            currentBase = first
            ent:ResetSequence(first)
            ent:SetCycle(0)
            ent:FrameAdvance(0)
            local mode = useGestures and " [gestures]" or ""
            infoLabel:SetText("Seq: " .. (ent:GetSequenceName(first) or "?") .. " (" .. count .. " total)" .. mode)
        else
            infoLabel:SetText("No sequences found for this model")
        end
    end

    local function SetupCamera()
        if not IsValid(ent) then return end
        local mins, maxs = ent:GetRenderBounds()
        local center = (mins + maxs) / 2
        local radius = (maxs - mins):Length()
        if radius > 0 then
            mdl:SetFOV(30)
            mdl:SetLookAt(center)
            mdl:SetCamPos(center + Vector(radius * 1.5, radius * 1.5, radius * 0.5))
        end
    end

    local function SetupEntity(path)
        CleanupEntity()
        mdl.Entity = nil
        useGestures = false

        local e

        if ents and ents.CreateClientside then
            local ok, result = pcall(ents.CreateClientside, ANIM_ENT_CLASS)
            if ok and IsValid(result) then
                e = result
                e:SetModel(path)
                e:Spawn()
                useGestures = e.GetAnimOverlay ~= nil
            end
        end

        if not IsValid(e) then
            local ok, result = pcall(ClientsideModel, path)
            if ok and IsValid(result) then
                e = result
            end
        end

        if IsValid(e) then
            useGestures = useGestures or e.GetAnimOverlay ~= nil or e.AnimRestartGesture ~= nil or e.AddGesture ~= nil or e.AddGestureSequence ~= nil
        end

        if not IsValid(e) then
            infoLabel:SetText("Cannot create entity for: " .. path)
            return
        end

        e:SetNoDraw(true)
        e:DrawShadow(false)
        local ok1 = pcall(function() e:SetSolid(SOLID_NONE) end)
        local ok2 = pcall(function() e:SetMoveType(MOVETYPE_NONE) end)
        local ok3 = pcall(function() e:SetPlaybackRate(1) end)
        e:SetAngles(Angle(0, 180, 0))
        ent = e
        mdl.Entity = e
        if not useGestures then
            infoLabel:SetText("Basic model mode (no gesture layering)")
        end
    end

    local function LoadModel(path)
        if not path or path == "" then return end
        SetupEntity(path)
        if not IsValid(ent) then
            infoLabel:SetText("Failed to load model: " .. path)
            return
        end
        baseSelector:SetText("Base Animation")
        currentBase = -1
        timer.Simple(0, function()
            if IsValid(ent) then
                PopulateSeqs()
                SetupCamera()
            end
        end)
    end

    local baseThink = frame.Think
    frame.Think = function(self)
        if baseThink then baseThink(self) end
        local searchText = searchBar:GetText()
        if searchText ~= lastSearch then
            lastSearch = searchText
            RefreshList(searchText)
        end
        if IsValid(ent) then
            local dt = FrameTime()
            pausedLabel:SetVisible(dt == 0)
            local speed = speedSlider:GetValue() or 1
            local ok = pcall(function() ent:SetPlaybackRate(1) end)
            ent:FrameAdvance(dt * speed)
            ent:SetAngles(Angle(0, (dirSlider:GetValue() or 0) + 180, 0))
        end
    end

    frame.PerformLayout = function(self)
        DFrame.PerformLayout(self)
        local w, h = self:GetWide(), self:GetTall()
        local top = TITLE_H + PAD

        local mw = w - SIDE_W - PAD * 3
        mw = math.max(200, mw)
        mdl:SetPos(SIDE_W + PAD * 2, top)
        mdl:SetSize(mw, h - top - PAD)
        pausedLabel:SetPos(SIDE_W + PAD * 2, top)
        pausedLabel:SetSize(mw, h - top - PAD)

        local x = PAD
        local y = top

        modelLabel:SetPos(x, y + 2)
        modelLabel:SetSize(40, 18)
        modelInput:SetPos(x + 42, y)
        modelInput:SetSize(SIDE_W - 42 - 60 - PAD, 22)
        loadBtn:SetPos(x + SIDE_W - 60 - PAD, y)
        loadBtn:SetSize(60, 22)

        y = y + 28
        speedSlider:SetPos(x, y)
        speedSlider:SetSize(SIDE_W, 20)

        y = y + 24
        dirSlider:SetPos(x, y)
        dirSlider:SetSize(SIDE_W, 20)

        y = y + 24
        baseSelector:SetPos(x, y)
        baseSelector:SetSize(SIDE_W, 24)

        y = y + 26
        infoLabel:SetPos(x, y + 2)
        infoLabel:SetSize(SIDE_W - 50, 18)
        copyBtn:SetPos(x + SIDE_W - 46, y)
        copyBtn:SetSize(46, 20)

        y = y + 22
        searchBar:SetPos(x, y)
        searchBar:SetSize(SIDE_W, 22)

        y = y + 24
        seqList:SetPos(x, y)
        seqList:SetSize(SIDE_W, math.max(50, h - y - PAD))
    end

    modelInput.OnEnter = function()
        LoadModel(modelInput:GetValue())
    end

    loadBtn.DoClick = function()
        LoadModel(modelInput:GetValue())
    end

    baseSelector.OnSelect = function(_, _, _, data)
        local idx = baseIdx[data]
        if idx and IsValid(ent) then
            currentBase = idx
            ent:ResetSequence(idx)
            ent:SetCycle(0)
            ent:FrameAdvance(0)
            infoLabel:SetText("Base: " .. (ent:GetSequenceName(idx) or "?"))
        end
    end

    function seqList:OnRowSelected(id, line)
        if IsValid(ent) and line and line.SeqIndex then
            local name = ent:GetSequenceName(line.SeqIndex) or "?"
            lastSelectedName = name
            SetClipboardText(name)
            if useGestures and ent.AddGestureSequence then
                ent:AddGestureSequence(line.SeqIndex)
                infoLabel:SetText("Gesture: " .. name .. " [copied]")
            elseif useGestures and ent.GetAnimOverlay then
                local gn = 1
                local seqIdx = line.SeqIndex
                for slot = gn, gn + 2 do
                    local ov = ent:GetAnimOverlay(slot)
                    if ov and ov:GetSequence() < 0 then
                        ov:SetSequence(seqIdx)
                        ov:SetCycle(0)
                        ov:SetPlaybackRate(1)
                        ov:SetWeight(1)
                        seqIdx = -1
                        break
                    end
                end
                if seqIdx >= 0 then
                    local ov = ent:GetAnimOverlay(gn)
                    if ov then
                        ov:SetSequence(line.SeqIndex)
                        ov:SetCycle(0)
                        ov:SetPlaybackRate(1)
                        ov:SetWeight(1)
                    end
                end
                infoLabel:SetText("Gesture overlay: " .. name .. " [copied]")
            else
                ent:ResetSequence(line.SeqIndex)
                ent:SetCycle(0)
                ent:FrameAdvance(0)
                infoLabel:SetText("Seq: " .. name .. " [copied]")
            end
        end
    end

    copyBtn.DoClick = function()
        if lastSelectedName ~= "" then
            SetClipboardText(lastSelectedName)
            infoLabel:SetText("Copied: " .. lastSelectedName)
        end
    end

    LoadModel(modelInput:GetValue())
end

concommand.Add("citynpc_anim_viewer", function()
    OpenAnimViewer()
end)
