-- Functions to filter out ways and adjust speed/weight

local tags = require('tags')
local math = math
local Way = Way
local tonumber = tonumber
local string = string
local ipairs = ipairs
local print = print

module('highway')

local function parse_maxspeed(source)
	if source == nil then
		return 0
	end
	local n = tonumber(source:match("%d*"))
	if n == nil then
		n = 0
	end
	if string.match(source, "mph") or string.match(source, "mp/h") then
		n = (n*1609)/1000;
	end
	return math.abs(n)
end


-- Set basic speed for way
-- Returns false if no speed is defined.
function set_base_speed(source, highway_speed, track_speed)
    local highway = source.tags:Find('highway')

    if highway == 'track' then
        if track_speed ~= nil then
            local grade = tonumber(tags.get_trackgrade(source.tags))
            if track_speed[grade] ~= nil then
                source.forward_speed = track_speed[grade]
                source.backward_speed = track_speed[grade]
                return true
            end
        end
    else
        if highway_speed[highway] ~= nil then
            source.forward_speed = highway_speed[highway]
            source.backward_speed = highway_speed[highway]
            return true
        end
    end

    source.forward_speed = 0
    source.backward_speed = 0
    return false
end


function adjust_speed_by_surface(source, surfaces, default)
    local surface = tags.get_surface(source.tags)

    if surfaces[surface] ~= nil then
        source.forward_speed = math.floor(source.forward_speed * surfaces[surface])
        source.backward_speed = math.floor(source.backward_speed * surfaces[surface])
    else
        source.forward_speed = math.floor(source.forward_speed * default)
        source.backward_speed = math.floor(source.backward_speed * default)
    end

    return source.forward_speed > 0 or source.backward_speed > 0
end

function adjust_speed_for_path(source, speeds)
    if source.tags:Find("highway") == 'path' then
        for k,v in ipairs(speeds) do
            local tag = source.tags:Find(k)
            if tag ~= '' then
                if v == nil then
                    source.forward_speed = 0
                    source.backward_speed = 0
                    return false
                else
                    if v[tag] ~= nil then
                        source.forward_speed = math.floor(source.forward_speed * v[tag])
                        source.backward_speed = math.floor(source.backward_speed * v[tag])
                    end
                end
            end
        end
        return (source.forward_speed > 0 or source.backward_speed > 0)
    end

    return true
end

-- speedfac controls how well the speed limit should be kept
function restrict_to_maxspeed(source, speedfac)
	local maxspeed = math.floor(parse_maxspeed(source.tags:Find ("maxspeed"))*speedfac)
    if (maxspeed > 0 and maxspeed < source.forward_speed) then
      source.forward_speed = maxspeed
    end
    if (maxspeed > 0 and maxspeed < source.backward_speed) then
      source.backward_speed = maxspeed
    end
    -- check if an explicit speed for backward direction is set
    local maxspeed_forward = parse_maxspeed(source.tags:Find("maxspeed:forward"))
    local maxspeed_backward = parse_maxspeed(source.tags:Find("maxspeed:backward"))
    if maxspeed_forward > 0 then
        source.forward_speed = maxspeed_forward
    end
    if maxspeed_backward > 0 then
      source.backward_speed = maxspeed_backward
    end
end

function set_directions(source, mode)
    local junction = source.tags:Find("junction")
    if junction == "roundabout" then
        source.forward_mode = 1
        source.backward_mode = 0
        source.junction = true
    else
        source.junction = false
        if mode ~= nil then
            local onewaymode = source.tags:Find(string.format("oneway:%s", mode))
            if onewaymode ~= '' then
                tags.as_oneway(source, onewaymode)
                return true
            end
        end
        local oneway = source.tags:Find("oneway")
        if oneway ~= nil then
            tags.as_oneway(source, oneway)
            return true
        end
        local highway = source.tags:Find("highway")
        if highway == "motorway" or highway == "motorway_link" then
            source.forward_mode = 1
            source.backward_mode = 0
        end
    end
end

function set_cycleway_directions(way)
    set_directions(way, "bicycle")
	if (tags.oneway_value(way.tags:Find("cycleway")) == -1)
       or (tags.oneway_value(way.tags:Find("cycleway:right")) == -1)
       or (tags.oneway_value(way.tags:Find("cycleway:left")) == -1) then
         way.forward_mode = 1
         way.backward_mode = 0
    end
end


function turn_function (angle, turn_penalty, turn_bias)
    -- compute turn penalty as angle^2, with a left/right bias
    k = turn_penalty/(90.0*90.0)
	if angle>=0 then
	    return angle*angle*k/turn_bias
	else
	    return angle*angle*k*turn_bias
    end
end
