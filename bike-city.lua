require("tags")
require("barrier")
require("highway")
require("transport")
--
-- Global variables required by extractor
--
ignore_areas 			= true -- future feature
traffic_signal_penalty 	= 2
u_turn_penalty 			= 20
use_turn_restrictions   = true

--
-- Globals for profile definition
--

local access_list = { "bicycle", "vehicle", "access" }


---------------------------------------------------------------------------
--
-- TURN RESTRICTION EXCEPTIONS

function get_exceptions(vector)
	for i,v in ipairs(access_list) do 
		vector:Add(v)
	end
end


---------------------------------------------------------------------------
--
-- NODE FUNCTION
--
-- Node    in: lat,lon,id,tags
-- result out: bollard,traffic_light

-- default is forbidden, so add allowed ones only
local barrier_access = {
    ["kerb"] = true,
    ["block"] = true,
    ["bollard"] = true,
    ["border_control"] = true,
    ["cattle_grid"] = true,
    ["entrance"] = true,
    ["sally_port"] = true,
    ["toll_both"] = true
}

function node_function (node, result)
    barrier.set_bollard(node, result, access_list, barrier_access)

    -- flag delays
    if result.bollard or node:get_value_by_key("highway") == "traffic_signals" then
        result.traffic_light = true
    end

    return 1
end


---------------------------------------------------------------------------
--
-- WAY FUNCTION
--
-- Way     in: tags
-- result out: String name,
--             double forward_speed,
--             double backward_speed,
--             short type,
--             bool access,
--             bool roundabout,
--             bool is_duration_set,
--             bool is_access_restricted,
--             bool ignore_in_grid,
--             forward_mode { 0, 1, 2 }
--             backward_mode { 0, 1, 2 }
	
--
-- Begin of globals

local default_speed = 16
local designated_speed = 18
local speed_highway = { 
	["cycleway"] = 18,
	["primary"] = 15,
	["primary_link"] = 15,
	["secondary"] = 16,
	["secondary_link"] = 16,
	["tertiary"] = 17,
	["tertiary_link"] = 17,
	["residential"] = 18,
	["unclassified"] = 18,
	["living_street"] = 18,
	["road"] = 17,
	["service"] = 17,
	["path"] = 6,
	["footway"] = 5,
	["pedestrian"] = 5,
	["steps"] = 1,
}

local speed_track = { 18, 16, 12 }

local speed_path = {
    sac_scale = nil,
    foot = { designated = 0.5,
             yes = 0.9 },
    bicycle = { yes = 3 },
    ["mtb:scale"] = nil
}

local surface_penalties = { 
    ["gravel"] = 0.8,
    ["ground"] = 0.6,
    ["unpaved"] = 0.8,
    ["grass"] = 0.4,
    ["dirt"] = 0.4,
    ["cobblestone"] = 0.5, 
    ["pebblestone"] = 0.9, 
    ["compacted"] = 0.9, 
    ["wood"] = 0.95,
    ["grit"] = 0.5,
    ["sand"] = 0.4
}

local name_list = { "ref", "name" }

function way_function (way, result)
 	-- Check if we are allowed to access the way
    if tags.get_access_grade(way, access_list) < -1 then
		return 0
    end

    -- ferries
    if transport.is_ferry(way, result, 5) then
        return 1
    end

    -- is it a valid highway?
    if not highway.set_base_speed(way, result, speed_highway, speed_track) then
        -- check for designated access
        if tags.as_access_grade(way:get_value_by_key('bicycle')) > 0 then
            result.forward_speed = default_speed
            result.backward_speed = default_speed
        else
            return 0
        end
    end

    if not highway.adjust_speed_for_path(way, result, speed_path) then
        return 0
    end
    if not highway.adjust_speed_by_surface(way, result, surface_penalties, 1.0) then
        return 0
    end

    local cycleway = way:get_value_by_key('cycleway')
    if (cycleway == 'lane' or cycleway == 'track') and
         (highway == 'primary' or highway == 'secondary') then
        result.forward_speed = result.forward_speed + 1
        result.backward_speed = result.backward_speed + 1
    end

    -- finally: restrict to maxspeed
    highway.restrict_to_maxspeed(way, result, 1.0)

    -- Set direction according to tags on way
    highway.set_cycleway_directions(way, result, result)
  
    result.name = tags.get_name(way, name_list)
    result.type = 1
    return 1
end
