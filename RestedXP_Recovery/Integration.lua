local _, addon = ...

local RECOVERY_GROUP = "*RestedXP Recovery"
local RESTORE_ATTEMPTS = 8

local function rxpCall(method, ...)
    local rxp = addon:GetRXP()
    local fn = rxp and rxp[method]
    if type(fn) ~= "function" then
        return false, "RestedXP does not expose " .. tostring(method) .. "."
    end
    local ok, result = pcall(fn, rxp, ...)
    if not ok then
        return false, result
    end
    return true, result
end

local function planForStorage(plan)
    local stored = { steps = {}, targets = {} }
    for _, step in ipairs(plan.steps or {}) do
        stored.steps[#stored.steps + 1] = {
            id = step.id,
            name = step.name,
            status = step.status,
            requiredBy = step.requiredBy,
        }
    end
    for _, target in ipairs(plan.targets or {}) do
        stored.targets[#stored.targets + 1] = {
            id = target.id,
            mode = target.mode,
            sourceStep = target.sourceStep,
            sourceTag = target.sourceTag,
        }
    end
    return stored
end

local function hydratePlan(stored)
    local plan = {
        steps = {},
        targets = stored.targets or {},
        warnings = {},
    }
    for _, step in ipairs(stored.steps or {}) do
        plan.steps[#plan.steps + 1] = {
            id = step.id,
            name = step.name or addon:GetQuestName(step.id),
            status = step.status,
            requiredBy = step.requiredBy,
            references = addon:GetGuideReferences(step.id),
        }
    end
    return plan
end

local function recoveryKey(original, plan)
    local ids = {}
    for _, step in ipairs(plan.steps or {}) do
        ids[#ids + 1] = tostring(step.id)
    end
    return "rxpr:" .. tostring(original.key or original.group or "guide")
        .. ":" .. table.concat(ids, ",")
end

local function buildGuide(plan, original)
    local route = addon.RouteBuilder.Build(plan, {
        currentGroup = original.group,
    })
    if #route.steps == 0 then
        return nil, route
    end

    local guide = {
        name = "Recovery - " .. tostring(original.name or "Guide"),
        title = "RestedXP Recovery",
        group = RECOVERY_GROUP,
        groupdisplayname = "RestedXP Recovery",
        key = recoveryKey(original, plan),
        version = 1,
        classic = true,
        standalone = true,
        steps = route.steps,
        rxprRecovery = true,
    }
    return guide, route
end

local function originalState(guide)
    local rxp = addon:GetRXP()
    local step, stepId = 1, nil
    if rxp and type(rxp.GetGuideProgress) == "function" then
        local ok, savedStep, savedId = pcall(rxp.GetGuideProgress, guide)
        if ok then
            step, stepId = tonumber(savedStep) or 1, savedId
        end
    end
    return {
        group = guide.group,
        name = guide.name,
        key = guide.key,
        step = step,
        stepId = stepId,
    }
end

function addon:StartRecovery(plan, savedOriginal, restoring)
    local rxp = self:GetRXP()
    local original = savedOriginal or (plan and plan.guide)
        or (rxp and rxp.currentGuide)
    if not original or original.rxprRecovery then
        return nil, "No original RestedXP guide is available to resume."
    end

    for _, step in ipairs(plan.steps or {}) do
        step.references = step.references or self:GetGuideReferences(step.id)
    end

    local guide, route = buildGuide(plan, original)
    if not guide then
        return nil, "No recovery steps could be extracted from loaded RestedXP guides.", route
    end

    local resume = savedOriginal and {
        group = savedOriginal.group,
        name = savedOriginal.name,
        key = savedOriginal.key,
        step = savedOriginal.step,
        stepId = savedOriginal.stepId,
    } or originalState(original)

    local storedPlan = planForStorage(plan)
    self.db.activeRecovery = {
        version = 1,
        original = resume,
        plan = storedPlan,
    }
    self.activeRecovery = {
        guide = guide,
        route = route,
        plan = plan,
        original = resume,
    }

    if not restoring and type(rxp.SaveGuideProgress) == "function" then
        local firstStep = guide.steps[1]
        pcall(rxp.SaveGuideProgress, guide, 1, firstStep and firstStep.stepId)
    end

    local ok, err = rxpCall("LoadGuide", guide)
    if not ok or not (rxp.currentGuide and rxp.currentGuide.rxprRecovery) then
        self.activeRecovery = nil
        if not restoring then
            self.db.activeRecovery = nil
        end
        return nil, "RestedXP rejected the generated recovery guide: "
            .. tostring(err or "the recovery guide did not become active"), route
    end

    self:Print("Started an opt-in recovery route with " .. #guide.steps
        .. " step(s) from " .. #route.sources .. " quest segment(s).")
    for _, warning in ipairs(route.warnings) do
        self:Print("Warning: " .. warning)
    end
    return route
end

local function findOriginalGuide(state)
    local rxp = addon:GetRXP()
    if not rxp or type(rxp.GetGuideTable) ~= "function" then
        return nil
    end
    local ok, guide = pcall(rxp.GetGuideTable, state.group, state.name)
    if ok and guide then
        return guide
    end
    ok, guide = pcall(rxp.GetGuideTable, rxp, state.group, state.name)
    return ok and guide or nil
end

function addon:ResumeOriginalGuide(reason)
    local runtime = self.activeRecovery
    local stored = self.db.activeRecovery
    local active = runtime or stored
    local state = active and active.original
    if not state then
        return nil, "No recovery route is active."
    end
    local guide = findOriginalGuide(state)
    if not guide then
        return nil, "The original RestedXP guide is not currently loaded."
    end

    local rxp = self:GetRXP()
    if type(rxp.SaveGuideProgress) == "function" then
        pcall(rxp.SaveGuideProgress, guide, state.step, state.stepId)
    end

    self.db.activeRecovery = nil
    self.activeRecovery = nil
    local ok, err = rxpCall("LoadGuide", guide)
    if not ok then
        self.db.activeRecovery = stored
        self.activeRecovery = runtime
        return nil, tostring(err)
    end
    self:Print("Resumed " .. tostring(state.name)
        .. (reason and (" (" .. reason .. ").") or "."))
    return true
end

function addon:IsRecoverySatisfied()
    local active = self.activeRecovery
    if not active then
        return false
    end
    for _, step in ipairs(active.plan.steps or {}) do
        if step.requiredBy then
            if not self:IsQuestTurnedIn(step.id) then
                return false
            end
        elseif not self:IsQuestTurnedIn(step.id) and not self:IsOnQuest(step.id) then
            return false
        end
    end
    return true
end

function addon:CheckRecoveryStatus()
    if self.activeRecovery and self:IsRecoverySatisfied() then
        self:ResumeOriginalGuide("recovery requirements satisfied")
    end
end

function addon:CancelRecovery()
    local active = self.activeRecovery or self.db.activeRecovery
    local original = active and active.original
    if original then
        self.db.ignoredPrompt = tostring(original.key) .. ":" .. tostring(original.step)
    end
    return self:ResumeOriginalGuide("recovery cancelled")
end

function addon:RestoreRecovery(attempt)
    local stored = self.db.activeRecovery
    if not stored then
        return
    end
    attempt = attempt or 1
    local original = findOriginalGuide(stored.original)
    if not original then
        if attempt < RESTORE_ATTEMPTS and C_Timer and C_Timer.After then
            C_Timer.After(1, function()
                addon:RestoreRecovery(attempt + 1)
            end)
        elseif attempt >= RESTORE_ATTEMPTS then
            self:Print("Could not restore the saved recovery route because the original guide is unavailable.")
        end
        return
    end

    local plan = hydratePlan(stored.plan or {})
    plan.guide = original
    local route, err = self:StartRecovery(plan, stored.original, true)
    if not route then
        self:Print("Could not restore recovery: " .. tostring(err))
    end
end

function addon:GetXPRecoveryPlan()
    local rxp = self:GetRXP()
    local guide = rxp and rxp.currentGuide
    if not guide or guide.rxprRecovery then
        return nil, "No normal RestedXP guide is active."
    end
    local currentStep = self:GetGuideProgress(guide)
    local player = self:GetPlayerXPState()
    local gate = self.XPPlanner.FindGate(guide, currentStep, player)
    if not gate then
        return {
            guide = guide,
            currentStep = currentStep,
            player = player,
            candidates = {},
        }
    end

    local candidateIds = {}
    for id in pairs(rxp.pickUpList or {}) do
        candidateIds[#candidateIds + 1] = id
    end
    local neededXP
    if gate.level == player.level then
        neededXP = math.max(0, (gate.xp or 0) - player.xp)
    elseif gate.level == player.level + 1 then
        neededXP = math.max(0, player.xpMax - player.xp) + (gate.xp or 0)
    end
    gate.estimatedDeficit = neededXP

    local candidates = self.XPPlanner.SelectCandidates(candidateIds, {
        playerLevel = player.level,
        neededXP = neededXP,
        completed = function(id) return self:IsQuestTurnedIn(id) end,
        onQuest = function(id) return self:IsOnQuest(id) end,
        getQuest = function(id) return self:GetQuestRecord(id) end,
        getName = function(id) return self:GetQuestName(id) end,
        getXP = function(id) return self:GetQuestXP(id) end,
        isDoable = function(id)
            local value = self:IsQuestDoable(id)
            return value == nil or value
        end,
        hasReference = function(id)
            return #self:GetGuideReferences(id) > 0
        end,
        getReferences = function(id) return self:GetGuideReferences(id) end,
    }, 8)

    return {
        guide = guide,
        currentStep = currentStep,
        player = player,
        gate = gate,
        candidates = candidates,
    }
end

function addon:StartXPRecovery(xpPlan)
    xpPlan = xpPlan or self:GetXPRecoveryPlan()
    if not xpPlan or not xpPlan.gate or #xpPlan.candidates == 0 then
        return nil, "No XP recovery route is currently available."
    end
    local plan = {
        guide = xpPlan.guide,
        targets = {},
        warnings = {},
        steps = {},
    }
    for _, candidate in ipairs(xpPlan.candidates) do
        plan.steps[#plan.steps + 1] = {
            id = candidate.id,
            name = candidate.name,
            status = "missing",
            requiredBy = "xp",
            references = candidate.references,
        }
    end
    return self:StartRecovery(plan)
end

function addon:PromptForRecovery(plan)
    if not self.db.autoPrompt or not plan or #plan.steps == 0
        or self.activeRecovery then
        return
    end
    local guide = plan.guide
    local signature = tostring(guide and guide.key) .. ":" .. tostring(plan.currentStep)
    if self.db.ignoredPrompt == signature then
        return
    end
    self.pendingPlan = plan
    self.pendingSignature = signature
    if StaticPopup_Show then
        StaticPopup_Show("RXP_RECOVERY_AVAILABLE", #plan.steps)
    end
end

if StaticPopupDialogs then
    StaticPopupDialogs.RXP_RECOVERY_AVAILABLE = {
        text = "This guide assumes %d missing quest(s). Add a temporary recovery route?",
        button1 = "Add Recovery",
        button2 = "Continue Normally",
        OnAccept = function()
            local plan = addon.pendingPlan
            addon.pendingPlan = nil
            if plan then
                local route, err = addon:StartRecovery(plan)
                if not route then
                    addon:Print(err or "Recovery could not be started.")
                end
            end
        end,
        OnCancel = function()
            addon.db.ignoredPrompt = addon.pendingSignature
            addon.pendingPlan = nil
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local function delayedGuideScan(_, guide)
    if not guide or guide.rxprRecovery or addon.activeRecovery then
        return
    end
    local function scan()
        local plan = addon:Scan()
        if plan then
            addon:PromptForRecovery(plan)
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.25, scan)
    else
        scan()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local rxp = addon:GetRXP()
        if rxp and type(rxp.RegisterMessage) == "function" then
            rxp:RegisterMessage("RXP_GUIDE_LOADED", delayedGuideScan)
            rxp:RegisterMessage("RXP_STEP_COMPLETE", function()
                addon:CheckRecoveryStatus()
            end)
        end
        if addon.db.activeRecovery then
            if C_Timer and C_Timer.After then
                C_Timer.After(1, function() addon:RestoreRecovery() end)
            else
                addon:RestoreRecovery()
            end
        end
    elseif addon.activeRecovery then
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, function() addon:CheckRecoveryStatus() end)
        else
            addon:CheckRecoveryStatus()
        end
    end
end)
