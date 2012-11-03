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
use_restrictions        = true

--
-- Globals for profile definition
--

local access_list = { "bicycle", "vehicle", "access" }


---------------------------------------------------------------------------
--
-- NODE FUNCTION
--
-- Node-> in: lat,lon,id,tags
--       out: bollard,traffic_light

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
	["path"] = 16,
	["footway"] = 5,
	["pedestrian"] = 5,
	["steps"] = 1,
}

local speed_track = { 18, 16, 16, 10, 5 }

local speed_path = {
    sac_scale = nil,
    foot = { designated = 0.5,
             yes = 0.9 },
    ["mtb:scale"] = { ["0"] = 0.9, ["1"] = 0, ["2"] = 0, ["3"] = 0, ["4"] = 0, ["5"] = 0 }
}

local surface_penalties = { 
    ["gravel"] = 0.8,
    ["ground"] = 0.8,
    ["unpaved"] = 0.9,
    ["grass"] = 0.5,
    ["dirt"] = 0.5,
    ["cobblestone"] = 0.5, 
    ["pebblestone"] = 0.9, 
    ["compacted"] = 0.9, 
    ["wood"] = 0.95,
    ["grit"] = 0.6,
    ["sand"] = 0.4
}

local name_list = { "ref", "name" }

function way_function (way, numberOfNodesInWay)
	-- A way must have two nodes or more
	if(numberOfNodesInWay < 2) then
		return 0;
	end

 	-- Check if we are allowed to access the way
    if tags.get_access_grade(way.tags, access_list) < -1 then
		return 0
    end

    -- ferries
    if transport.is_ferry(way, 5, numberOfNodesInWay) then
        return 1
    end

    -- is it a valid highway?
    if not highway.set_base_speed(way, speed_highway, speed_track) then
        -- check for designated access
        if tags.as_access_grade(way.tags:Find('bicycle')) > 0 then
            way.speed = default_speed
        else
            return 0
        end
    end

    if not highway.adjust_speed_for_path(way, speed_path) then
        return 0
    end
    if not highway.adjust_speed_by_surface(way, surface_penalties, 1.0) then
        return 0
    end

    local cycleway = way.tags:Find('cycleway')
    if (cycleway == 'lane' or cycleway == 'track') and
         (highway == 'primary' or highway == 'secondary') then
        way.speed = way.speed + 1
    end

    -- finally: restrict to maxspeed
    highway.restrict_to_maxspeed(way, 1.0)

    -- Set direction according to tags on way
    highway.set_directions(way, "bicycle")
	if tags.as_oneway(way.tags:Find("cycleway")) == Way.opposite then
        way.direction = Way.bidirectional
    end
  
    way.name = tags.get_name(way.tags, name_list)
	way.type = 1
	return 1
end
