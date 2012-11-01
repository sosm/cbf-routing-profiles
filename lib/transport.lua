local durationIsValid = durationIsValid
local parseDuration = parseDuration
local math = math
local tags = require('tags')
--
-- Function for public transport use in routes
--


module("transport")

local ferry_name_tags = { 'name' }

-- check for ferries and set the parameters accordingly
function is_ferry(way, default_speed, numberOfNodesInWay)
    local route = way.tags:Find("route")

    if route == "ferry" then
        local duration = way.tags:Find("duration")
        if durationIsValid(duration) then
            way.speed = math.max( parseDuration(duration) / math.max(1, numberOfNodesInWay-1) );
            way.is_duration_set = true
        else
            way.speed = default_speed
        end
        way.name = tags.get_name(way.tags, ferry_name_tags)
        way.type = 1
        return true
    end
    return false
end
