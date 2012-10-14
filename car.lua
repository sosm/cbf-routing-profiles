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

access_tags_hierachy = { "motorcar", "motor_vehicle", "vehicle", "access" }


---------------------------------------------------------------------------
--
-- NODE FUNCTION
--
-- Node-> in: lat,lon,id,tags
--       out: bollard,traffic_light

-- default is forbidden, so add allowed ones only
barrier_access = {
    ["kerb"] = true,
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

default_speed = 50
designated_speed = 80
speed_profile = { 
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
	["service"] = 20,
    ["track"] = 20   -- only track grade 1
}

surface_penalties = { 
    ["paved"] = 0,
    ["gravel"] = 20, 
    ["asphalt"] = 0, 
    ["ground"] = 25, 
    ["unpaved"] = 15, 
    ["grass"] = 100, 
    ["dirt"] = 100, 
    ["concrete"] = 0, 
    ["cobblestone"] = 5, 
    ["pebblestone"] = 0, 
    ["paving_stones"] = 0, 
    ["compacted"] = 5, 
    ["wood"] = 5, 
    ["grit"] = 100, 
    ["sand"] = 100 
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
    local highway = way.tags:Find("highway")
    local trackgrade = way.tags:Find("tracktype")
    local caraccess = access.value_to_grade(way.tags:Find('motorcar'))
    if caraccess > 1 then
      way.speed = designated_speed
    else
        -- Set the avg speed on the way if it is accessible by road class
        if highway == "track" then
            if tracktype == "grade1" then
                way.speed = speed_profile["track"]
            else
                return 0
            end
        elseif speed_profile[highway] ~= nil then 
          way.speed = speed_profile[highway]
        else
          return 0
        end
    end

    -- surface speeds
    local surfacepenalty = surface_penalties[surface.get_surface(way.tags)]

    if surfacepenalty ~= nil then
        if surfacepenalty >= 100 then
            return 0
        end
        if way.speed > surfacepenalty then
            way.speed = way.speed - surfacepenalty
        end
    end

    local lanes = way.tags:Find("lanes")
    if lanes == "1" then
        way.speed = math.floor(way.speed*0.8)
    end

    -- finally: restrict to maxspeed
	local maxspeed = parseMaxspeed(way.tags:Find ( "maxspeed") )
    if (maxspeed > 0 and maxspeed < way.speed) then
      way.speed = math.floor(maxspeed*0.95)
    end
	
	-- Set direction according to tags on way
    local oneway = way.tags:Find("oneway")
    local junction = way.tags:Find("junction")
    if oneway == "no" or oneway == "0" or oneway == "false" then
        way.direction = Way.bidirectional
    elseif oneway == "-1" then
        way.direction = Way.opposite
    elseif oneway == "yes" or oneway == "1" or oneway == "true" or junction == "roundabout" or highway == "motorway_link" or highway == "motorway" then
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
