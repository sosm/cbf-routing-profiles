require("access")
require("surface")
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

access_tags_hierachy = { "bicycle", "vehicle", "access" }


---------------------------------------------------------------------------
--
-- NODE FUNCTION
--
-- Node-> in: lat,lon,id,tags
--       out: bollard,traffic_light

-- default is forbidden, so add allowed ones only
barrier_access = {
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
	local acgrade = access.find_access_grade(node, access_tags_hierachy)
    local barrier = node.tags:Find ("barrier")
	local traffic_signal = node.tags:Find("highway")

    if acgrade == 0 then
        if barrier and barrier ~= "" then
            node.bollard = not barrier_access[barrier]
        end
    else
        node.bollard = (acgrade < 0)
    end

	-- flag delays	
	if traffic_signal == "traffic_signals"
        or (barrier and barrier ~= "") then
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

default_speed = 16
designated_speed = 18
speed_profile = { 
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
	["track"] = 16,
	["path"] = 16,
	["footway"] = 5,
	["pedestrian"] = 5,
	["steps"] = 1,
}

surface_penalties = { 
    ["paved"] = 0, 
    ["gravel"] = -2, 
    ["asphalt"] = 0, 
    ["ground"] = -1, 
    ["unpaved"] = -2, 
    ["grass"] = -5, 
    ["dirt"] = -5, 
    ["concrete"] = 0, 
    ["cobblestone"] = -5, 
    ["pebblestone"] = -1, 
    ["paving_stones"] = 0, 
    ["compacted"] = -1, 
    ["wood"] = -1, 
    ["grit"] = -4, 
    ["sand"] = -6 
}


function way_function (way, numberOfNodesInWay)
	-- A way must have two nodes or more
	if(numberOfNodesInWay < 2) then
		return 0;
	end

 	-- Check if we are allowed to access the way
	local acgrade = access.find_access_grade(way, access_tags_hierachy)
    if acgrade < -1 then
		return 0
    end
    -- no biking above grade3
    local highway = way.tags:Find("highway")
    local trackgrade = way.tags:Find("tracktype")
    if (trackgrade == "grade4" or trackgrade == "grade5") then
      return 0
    end
    -- no biking on sac_scale
    local sac_scale = way.tags:Find("sac_scale")
    if highway == 'path' and sac_scale ~= "" then
      return 0
    end

    -- Set the name that will be used for instructions	
	local name = way.tags:Find("name")
	local ref = way.tags:Find("ref")
	if "" ~= ref then
		way.name = ref
	elseif "" ~= name then
		way.name = name
	end

    -- ferries
    if transport.is_ferry(way, 5, numberOfNodesInWay) then
        return 1
    end

    -- designated bike ways get maxspeed, everything else according to profile
    local bikeaccess = access.value_to_grade(way.tags:Find('bicycle'))
    if bikeaccess > 1 then
      way.speed = designated_speed
    else
        -- Set the avg speed on the way if it is accessible by road class
        if speed_profile[highway] ~= nil then 
          way.speed = speed_profile[highway]
        -- Set the avg speed on ways that are marked accessible
        elseif acgrade > 0 then
            way.speed = default_speed
        else
          return 0
        end
    end

    -- surface speeds
    local surfacepenalty = surface_penalties[surface.get_surface(way.tags)]

    if (surfacepenalty ~= nil and way.speed > surfacepenalty) then
      way.speed = way.speed - surfacepenalty
    end

    local cycleway = way.tags:Find('cycleway')
    if (cycleway == 'lane' or cycleway == 'track') and
         (highway == 'primary' or highway == 'secondary' or highway == 'tertiary') then
        way.speed = way.speed + 2
    end

    -- finally: restrict to maxspeed
	local maxspeed = parseMaxspeed(way.tags:Find ( "maxspeed") )
    if (maxspeed > 0 and maxspeed < way.speed) then
      way.speed = maxspeed
    end
	
	-- Set direction according to tags on way
	local oneway = way.tags:Find("oneway")
	local onewayClass = way.tags:Find("oneway:bicycle")
	local cycleway = way.tags:Find("cycleway")
    if onewayClass == "yes" or onewayClass == "1" or onewayClass == "true" then
        way.direction = Way.oneway
    elseif onewayClass == "no" or onewayClass == "0" or onewayClass == "false" then
        way.direction = Way.bidirectional
    elseif onewayClass == "-1" then
        way.direction = Way.opposite
    elseif oneway == "no" or oneway == "0" or oneway == "false" then
        way.direction = Way.bidirectional
    elseif cycleway == "opposite" or cycleway == "opposite_track" or cycleway == "opposite_lane" then
        way.direction = Way.bidirectional
    elseif oneway == "-1" then
        way.direction = Way.opposite
    elseif oneway == "yes" or oneway == "1" or oneway == "true" or junction == "roundabout" then
        way.direction = Way.oneway
    else
        way.direction = Way.bidirectional
    end
  
    if junction == "roundabout" then
        way.roundabout = true
    end
  
	way.type = 1
	return 1
end
