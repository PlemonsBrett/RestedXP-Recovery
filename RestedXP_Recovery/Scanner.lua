local _, addon = ...

local function questIds(element)
    if type(element) ~= "table" then
        return {}
    end

    if type(element.ids) == "table" and #element.ids > 0 then
        local result = {}
        for _, id in ipairs(element.ids) do
            id = tonumber(id)
            if id and id > 0 then
                result[#result + 1] = id
            end
        end
        return result
    end

    local id = tonumber(element.questId)
    if id and id > 0 then
        return { id }
    end
    return {}
end

local function isDependencyUse(element)
    local tag = element and element.tag
    if not tag then
        return false
    end

    return tag == "complete"
        or tag == "turnin"
        or tag == "dailyturnin"
        or tag == "abandon"
end

local function isAccept(element)
    local tag = element and element.tag
    return tag == "accept" or tag == "daily"
end

function addon:CollectTargets()
    local rxp = self:GetRXP()
    local guide = rxp and rxp.currentGuide
    if not guide or type(guide.steps) ~= "table" then
        return nil, "No active RestedXP guide was found."
    end

    local currentStep = math.max(1, self:GetGuideProgress(guide))
    local firstAccept = {}

    for stepIndex, step in ipairs(guide.steps) do
        for _, element in ipairs(step.elements or {}) do
            if isAccept(element) then
                for _, id in ipairs(questIds(element)) do
                    if not firstAccept[id] then
                        firstAccept[id] = stepIndex
                    end
                end
            end
        end
    end

    local targets, seen = {}, {}

    local function addTarget(id, mode, stepIndex, tag)
        local key = tostring(mode) .. ":" .. tostring(id)
        if seen[key] or self:IsQuestTurnedIn(id) then
            return
        end
        seen[key] = true
        targets[#targets + 1] = {
            id = id,
            mode = mode,
            sourceStep = stepIndex,
            sourceTag = tag,
        }
    end

    for stepIndex = currentStep, #guide.steps do
        local step = guide.steps[stepIndex]
        for _, element in ipairs(step.elements or {}) do
            if isAccept(element) then
                for _, id in ipairs(questIds(element)) do
                    addTarget(id, "accept", stepIndex, element.tag)
                end
            elseif isDependencyUse(element) and not element.skipIfMissing then
                for _, id in ipairs(questIds(element)) do
                    if not self:IsOnQuest(id) and not self:IsQuestTurnedIn(id) then
                        local acceptAt = firstAccept[id]

                        -- If the guide will still introduce this quest before the
                        -- dependent step, it is not a carry-over problem.
                        local introducedLater = acceptAt
                            and acceptAt >= currentStep
                            and acceptAt < stepIndex

                        if not introducedLater then
                            addTarget(id, "carryover", stepIndex, element.tag)
                        end
                    end
                end
            end
        end
    end

    table.sort(targets, function(a, b)
        if a.sourceStep == b.sourceStep then
            return a.id < b.id
        end
        return a.sourceStep < b.sourceStep
    end)

    return {
        guide = guide,
        currentStep = currentStep,
        targets = targets,
    }
end

function addon:Scan()
    local context, err = self:CollectTargets()
    if not context then
        return nil, err
    end

    local questDB = self:GetQuestDB()
    if not questDB then
        return nil,
            "Quest prerequisite data is unavailable. Enable Questie, then /reload. "
            .. "RestedXP itself uses Questie's database for prerequisite checks."
    end

    local plan = self.Planner.Resolve(context.targets, {
        completed = function(id)
            return self:IsQuestTurnedIn(id)
        end,
        onQuest = function(id)
            return self:IsOnQuest(id)
        end,
        getQuest = function(id)
            return self:GetQuestRecord(id)
        end,
        getName = function(id)
            return self:GetQuestName(id)
        end,
    })

    plan.guide = context.guide
    plan.currentStep = context.currentStep
    plan.targets = context.targets

    for _, step in ipairs(plan.steps) do
        step.references = self:GetGuideReferences(step.id)
    end

    self.lastPlan = plan
    return plan
end
