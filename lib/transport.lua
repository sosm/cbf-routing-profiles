local durationIsValid = durationIsValid;
--
-- Function for public transport use in routes
--


module("transport")

-- check for ferries and set the parameters accordingly
function is_ferry(way, default_speed)
    local route = way.tags:Find("route")

    if route == "ferry" then
        local duration = way.tags:Find("duration")
        if durationIsValid(duration) then
            way.speed = math.max( duration / math.max(1, numberOfNodesInWay-1) );
            way.is_duration_set = true
        else
            way.speed = default_speed
        end
        way.type = 1
        return true
    end
    return false
end
