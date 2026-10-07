local _, addon = ...

local function printReferences(step)
    if not step.references or #step.references == 0 then
        addon:Print("      No loaded RestedXP guide reference found for this quest.")
        return
    end

    local shown = 0
    for _, ref in ipairs(step.references) do
        addon:Print("      RXP: " .. tostring(ref.group) .. " > " .. tostring(ref.name)
            .. (ref.step and (" (step " .. ref.step .. ")") or ""))
        shown = shown + 1
        if shown >= 3 then
            break
        end
    end
end

function addon:PrintPlan(plan)
    if not plan then
        return
    end

    local guideName = plan.guide and plan.guide.name or "unknown guide"
    self:Print("Scanning |cffffffff" .. tostring(guideName) .. "|r from step "
        .. tostring(plan.currentStep) .. ".")

    if #plan.steps == 0 then
        self:Print("No missing prerequisite/carry-over quest chain was detected.")
        if #plan.targets > 0 then
            self:Print("Checked " .. #plan.targets .. " upcoming quest dependencies.")
        end
        return
    end

    self:Print("Recovery plan: |cffffd166" .. #plan.steps .. " quest(s)|r")
    for index, step in ipairs(plan.steps) do
        local status = step.status == "in-log" and " |cff80ff80[already in log]|r" or ""
        local reason = step.requiredBy and (" -> needed for "
            .. (step.requiredBy == "xp" and "XP recovery" or ("#" .. tostring(step.requiredBy)))) or ""
        self:Print(string.format("  %d. %s |cff999999(#%d)|r%s%s",
            index, step.name or ("Quest #" .. step.id), step.id, status, reason))
        printReferences(step)
    end

    if #plan.warnings > 0 then
        self:Print("Warnings:")
        for _, warning in ipairs(plan.warnings) do
            self:Print("  - " .. warning)
        end
    end

    self:Print("Run |cffffffff/rxpr recover|r to load these steps as an opt-in temporary guide.")
end

function addon:PrintXPPlan(plan)
    if not plan then
        return
    end
    if not plan.gate then
        self:Print("No upcoming XP gate or late-guide level deficit was detected.")
        return
    end
    self:Print("XP recovery target: level " .. plan.gate.level
        .. (plan.gate.kind == "explicit" and (" at guide step " .. plan.gate.step)
            or " by the end of this guide") .. ".")
    if plan.gate.estimatedDeficit and plan.gate.estimatedDeficit > 0 then
        self:Print("Estimated deficit: " .. plan.gate.estimatedDeficit .. " XP.")
    end
    if #plan.candidates == 0 then
        self:Print("No suitable unfinished quests with loaded RestedXP steps were found.")
        return
    end
    self:Print("Recommended optional quests:")
    for index, quest in ipairs(plan.candidates) do
        local xp = quest.xp > 0 and (", about " .. quest.xp .. " XP") or ""
        self:Print(string.format("  %d. %s (#%d, level %d%s)",
            index, quest.name, quest.id, quest.level, xp))
        printReferences(quest)
    end
    self:Print("Run |cffffffff/rxpr xprecover|r to load these quest segments.")
end

local function help()
    addon:Print("Commands:")
    addon:Print("  /rxpr scan  - analyze the active RXP guide for missing prerequisites")
    addon:Print("  /rxpr info  - show detected guide/client/database state")
    addon:Print("  /rxpr last  - print the most recent recovery plan again")
    addon:Print("  /rxpr recover  - scan and load an opt-in prerequisite recovery route")
    addon:Print("  /rxpr resume  - cancel recovery and return to the original guide")
    addon:Print("  /rxpr xp  - report an upcoming XP deficit and optional quests")
    addon:Print("  /rxpr xprecover  - load the recommended optional quest route")
    addon:Print("  /rxpr autoprompt on|off  - toggle guide-load recovery prompts")
end

local function info()
    local rxp = addon:GetRXP()
    if not rxp then
        addon:Print("RestedXP: not detected")
        return
    end

    local guide = rxp.currentGuide
    addon:Print("Version: " .. addon.version)
    addon:Print("RestedXP game mode: " .. tostring(rxp.game))
    addon:Print("Active guide: " .. tostring(guide and guide.name or "none"))
    addon:Print("Quest database: " .. (addon:GetQuestDB() and "available" or "unavailable (enable Questie)"))
    addon:Print("Automatic recovery prompt: " .. (addon.db.autoPrompt and "on" or "off"))
    addon:Print("Recovery route: " .. (addon.activeRecovery and "active" or "inactive"))
end

SLASH_RXPRECOVERY1 = "/rxpr"
SLASH_RXPRECOVERY2 = "/rxprecovery"
SlashCmdList.RXPRECOVERY = function(message)
    local command = string.lower((message or ""):match("^%s*(%S*)") or "")

    if command == "scan" or command == "" then
        local plan, err = addon:Scan()
        if not plan then
            addon:Print(err or "Scan failed.")
            return
        end
        addon:PrintPlan(plan)
    elseif command == "info" then
        info()
    elseif command == "last" then
        if addon.lastPlan then
            addon:PrintPlan(addon.lastPlan)
        else
            addon:Print("No previous scan. Run /rxpr scan first.")
        end
    elseif command == "recover" then
        local plan, err = addon:Scan()
        if not plan then
            addon:Print(err or "Scan failed.")
        elseif #plan.steps == 0 then
            addon:Print("No missing prerequisites require a recovery route.")
        else
            local route, routeErr = addon:StartRecovery(plan)
            if not route then
                addon:Print(routeErr or "Recovery could not be started.")
            end
        end
    elseif command == "resume" or command == "cancel" then
        local ok, err = addon:CancelRecovery()
        if not ok then
            addon:Print(err)
        end
    elseif command == "xp" then
        local plan, err = addon:GetXPRecoveryPlan()
        if plan then
            addon.lastXPPlan = plan
            addon:PrintXPPlan(plan)
        else
            addon:Print(err)
        end
    elseif command == "xprecover" then
        local plan, err = addon:GetXPRecoveryPlan()
        if not plan then
            addon:Print(err)
        else
            local route, routeErr = addon:StartXPRecovery(plan)
            if not route then
                addon:Print(routeErr)
            end
        end
    elseif command == "autoprompt" then
        local value = string.lower((message or ""):match("^%s*%S+%s+(%S+)") or "")
        if value == "on" then
            addon.db.autoPrompt = true
        elseif value == "off" then
            addon.db.autoPrompt = false
        else
            addon:Print("Usage: /rxpr autoprompt on|off")
            return
        end
        addon:Print("Automatic recovery prompt: " .. value)
    else
        help()
    end
end
