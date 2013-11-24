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

local access_list = { "motorcar", "motor_vehicle", "vehicle", "access" }

function turn_function (angle)
   return highway.turn_function(angle, 10, 1.4)
end

---------------------------------------------------------------------------
--
-- NODE FUNCTION
--
-- Node-> in: lat,lon,id,tags
--       out: bollard,traffic_light

-- default is forbidden, so add allowed ones only
local barrier_access = {
    ["kerb"] = true,
    ["border_control"] = true,
    ["cattle_grid"] = true,
    ["entrance"] = true,
    ["sally_port"] = true,
    ["toll_both"] = true
}

function node_function (node)
    barrier.set_bollard(node, access_list, barrier_access)

	-- flag delays	
	if node.bollard or node.tags:Find("highway") == "traffic_signals" then
		node.traffic_light = true
	end

	return 1
end


---------------------------------------------------------------------------
--
-- WAY FUNCTION
--
-- Way-> in: tags
--       out: String name,
--            double speed,
--            short type,
--            bool access,
--            bool roundabout,
--            bool is_duration_set,
--            bool is_access_restricted,
--            bool ignore_in_grid,
--            direction { notSure, oneway, bidirectional, opposite }
	
--
-- Begin of globals

local default_speed = 30
local speed_highway = { 
    ["motorway"] = 95,
    ["motorway_link"] = 70,
    ["trunk"] = 80,
    ["trunk_link"] = 60,
	["primary"] = 65,
	["primary_link"] = 60,
	["secondary"] = 60,
	["secondary_link"] = 55,
	["tertiary"] = 45,
	["tertiary_link"] = 40,
	["unclassified"] = 40,
	["residential"] = 30,
	["living_street"] = 5,
	["road"] = 35,
	["service"] = 20
}
local speed_track = { 20 }

-- default is no penalty, so leave those out
-- a factor of 0 disables ways for routing
local surface_penalties = { 
    ["gravel"] = 0.5, 
    ["ground"] = 0.5, 
    ["unpaved"] = 0.8, 
    ["grass"] = 0, 
    ["dirt"] = 0, 
    ["cobblestone"] = 0.95, 
    ["compacted"] = 0.8, 
    ["wood"] = 0.9, 
    ["grit"] = 0, 
    ["sand"] = 0 
}

local name_list = { "ref", "name" }

function way_function (way, numberOfNodesInWay)
 	-- Check if we are allowed to access the way
    if tags.get_access_grade(way.tags, access_list) < -1 then
		return 0
    end

    -- ferries
    if transport.is_ferry(way, 5) then
        return 1
    end

    -- is it a valid highway?
    if not highway.set_base_speed(way, speed_highway, speed_track) then
        -- check for designated access
        if tags.as_access_grade(way.tags:Find('motorcar')) > 0 then
            way.speed = default_speed
        else
            return 0
        end
    end
    -- make speed adjustments
    if not highway.adjust_speed_by_surface(way, surface_penalties, 1.0) then
        return 0
    end
    if way.tags:Find("lanes") == "1" then
        way.speed = math.floor(way.speed*0.8)
    end
    highway.restrict_to_maxspeed(way, 0.95)

	-- Set direction according to tags on way
    highway.set_directions(way, nil)
  
    way.name = tags.get_name(way.tags, name_list)
	way.type = 1
	return 1
end
