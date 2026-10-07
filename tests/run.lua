local failures = 0

local function check(condition, message)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. message .. "\n")
    end
end

local function equal(actual, expected, message)
    check(actual == expected, message .. " (expected " .. tostring(expected)
        .. ", got " .. tostring(actual) .. ")")
end

local addon = {}
for _, path in ipairs({
    "../RestedXP_Recovery/Core.lua",
    "../RestedXP_Recovery/Scanner.lua",
    "../RestedXP_Recovery/Integration.lua",
    "../RestedXP_Recovery/UI.lua",
}) do
    assert(loadfile(path), "syntax check failed for " .. path)
end
assert(loadfile("../RestedXP_Recovery/Planner.lua"))("RestedXP_Recovery", addon)
assert(loadfile("../RestedXP_Recovery/RouteBuilder.lua"))("RestedXP_Recovery", addon)
assert(loadfile("../RestedXP_Recovery/XPPlanner.lua"))("RestedXP_Recovery", addon)

local function plannerAPI(quests, completed, active)
    completed = completed or {}
    active = active or {}
    return {
        completed = function(id) return completed[id] or false end,
        onQuest = function(id) return active[id] or false end,
        getQuest = function(id) return quests[id] end,
        getName = function(id) return "Quest " .. id end,
    }
end

local function stepIds(plan)
    local result = {}
    for _, step in ipairs(plan.steps) do
        result[#result + 1] = tostring(step.id)
    end
    return table.concat(result, ",")
end

do
    local quests = {
        [100] = { name = "One" },
        [200] = { name = "Two", preQuestGroup = {100} },
        [300] = { name = "Three", preQuestGroup = {200} },
    }
    local plan = addon.Planner.Resolve({{id = 300, mode = "carryover"}}, plannerAPI(quests))
    equal(stepIds(plan), "100,200,300", "linear prerequisite chain is topologically ordered")

    plan = addon.Planner.Resolve({{id = 300, mode = "carryover"}},
        plannerAPI(quests, {[200] = true}))
    equal(stepIds(plan), "300", "completed prerequisite is omitted")

    plan = addon.Planner.Resolve({{id = 300, mode = "accept"}}, plannerAPI(quests))
    equal(stepIds(plan), "100,200", "upcoming accept does not duplicate its target")
end

do
    local quests = {
        [100] = { name = "Short" },
        [150] = { name = "Long", preQuestGroup = {151} },
        [151] = { name = "Long prerequisite" },
        [300] = { name = "Target", preQuestSingle = {150, 100} },
    }
    local plan = addon.Planner.Resolve({{id = 300, mode = "accept"}}, plannerAPI(quests))
    equal(stepIds(plan), "100", "shortest OR prerequisite branch is selected")

    plan = addon.Planner.Resolve({{id = 300, mode = "accept"}},
        plannerAPI(quests, {}, {[150] = true}))
    equal(stepIds(plan), "150", "active OR prerequisite branch is preferred")
end

do
    local quests = {
        [1] = {name = "Cycle one", preQuestGroup = {2}},
        [2] = {name = "Cycle two", preQuestGroup = {1}},
    }
    local plan = addon.Planner.Resolve({{id = 1, mode = "carryover"}}, plannerAPI(quests))
    check(#plan.warnings > 0, "circular dependencies produce a warning")
end


local function element(tag, id, text)
    return {tag = tag, questId = id, text = text or tag}
end

do
    local guide = {key = "source", group = "A", name = "Guide", steps = {}}
    guide.steps[1] = {stepId = 1, elements = {{tag = "goto", text = "Travel"}}}
    guide.steps[2] = {stepId = 2, include = "Other Guide", elements = {
        element("accept", 100), {tag = "xp", level = 20, xp = 0},
    }}
    guide.steps[3] = {stepId = 3, elements = {
        element("complete", 100), element("accept", 999),
    }}
    guide.steps[4] = {stepId = 4, elements = {element("turnin", 100)}}
    local refs = {
        {action = "accept", group = "A", name = "Guide", guide = guide,
            sourceStep = guide.steps[2]},
        {action = "turnin", group = "A", name = "Guide", guide = guide,
            sourceStep = guide.steps[4]},
    }

    local route = addon.RouteBuilder.Build({steps = {{id = 100, requiredBy = 200,
        references = refs}}}, {currentGroup = "A"})
    equal(#route.steps, 3, "prerequisite route includes accept, complete, and turn-in")
    equal(#route.steps[2].elements, 1, "unrelated quest action is filtered")
    equal(route.steps[2].elements[1].questId, 100, "wanted quest action is retained")
    equal(#guide.steps[3].elements, 2, "source guide is not mutated")

    route = addon.RouteBuilder.Build({steps = {{id = 100, references = refs}}},
        {currentGroup = "A"})
    equal(#route.steps, 1, "carry-over target route stops after acceptance")
    equal(#route.steps[1].elements, 1, "XP control directive is removed from route")
    equal(route.steps[1].elements[1].tag, "accept", "carry-over route accepts target")
    check(route.steps[1].include == nil, "guide include directive is removed from route")
end

do
    local guide = {
        name = "18-22 Example",
        steps = {
            {elements = {}},
            {elements = {{tag = "xp", level = 20, xp = 500}}},
            {elements = {}},
        },
    }
    local gate = addon.XPPlanner.FindGate(guide, 1, {level = 19, xp = 100})
    equal(gate.level, 20, "explicit XP gate is detected")

    local quests = {
        [1] = {name = "Best", level = 19, requiredLevel = 18},
        [2] = {name = "Done", level = 19, requiredLevel = 18},
        [3] = {name = "Too high", level = 25, requiredLevel = 25},
        [4] = {name = "Second", level = 18, requiredLevel = 17},
    }
    local candidates = addon.XPPlanner.SelectCandidates({1, 2, 3, 4}, {
        playerLevel = 19,
        getQuest = function(id) return quests[id] end,
        completed = function(id) return id == 2 end,
        onQuest = function() return false end,
        isDoable = function() return true end,
        hasReference = function() return true end,
        getXP = function(id) return ({[1] = 2000, [4] = 1000})[id] or 0 end,
        neededXP = 1500,
    }, 8)
    equal(#candidates, 1, "known XP deficit limits the recommendation count")
    equal(candidates[1].id, 1, "XP candidates prefer higher reward")
end

if failures > 0 then
    io.stderr:write(tostring(failures) .. " test(s) failed\n")
    os.exit(1)
end

print("All planner, route-builder, and XP-planner tests passed")
