require("access")
require("surface")
require("transport")
--
-- Global variables required by extractor
--
ignore_areas 			= true -- future feature
traffic_signal_penalty 	= 2
u_turn_penalty 			= 20
use_restrictions        = false

--
-- Globals for profile definition
--

access_tags_hierachy = { "foot", "access" }


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
    ["toll_both"] = true,
    ["cycle_barrier"] = true,
    ["stile"] = true,
    ["block"] = true,
    ["kissing_gate"] = true,
    ["turnstile"] = true,
    ["hampshire_gate"] = true
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

default_speed = 4.0
designated_speed = 4.2
speed_profile = {
    ["footway"] = 4.2,
	["cycleway"] = 4.0,
	["primary"] = 3.5,
	["primary_link"] = 3.5,
	["secondary"] = 3.7,
	["secondary_link"] = 3.7,
	["tertiary"] = 3.9,
	["tertiary_link"] = 3.9,
	["residential"] = 4.1,
	["unclassified"] = 4.0,
	["living_street"] = 4.1,
	["road"] = 3.9,
	["service"] = 4.1,
	["track"] = 4.1,
	["path"] = 4.2,
	["pedestrian"] = 4.2,
	["steps"] = 4.1,
}

surface_penalties = { 
    ["paved"] = 0, 
    ["gravel"] = 0, 
    ["asphalt"] = 0, 
    ["ground"] = 0, 
    ["unpaved"] = 0, 
    ["grass"] = 0,
    ["dirt"] = 0, 
    ["concrete"] = 0, 
    ["cobblestone"] = 0, 
    ["pebblestone"] = 0, 
    ["paving_stones"] = 0, 
    ["compacted"] = 0, 
    ["wood"] = 0, 
    ["grit"] = 0, 
    ["sand"] = -0.1
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
    -- no sac_scale higher 2
    local sac_scale = way.tags:Find("sac_scale")
    if sac_scale ~= nil and sac_scale ~= "" and
        not (sac_scale == "hiking" or sac_scale == "mountain_hiking")  then
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
    if transport.is_ferry(way, 5) then
        return 1
    end

    -- designated bike ways get maxspeed, everything else according to profile
    local footaccess = access.value_to_grade(way.tags:Find('foot'))
    local highway = way.tags:Find("highway")
    if footaccess > 1 then
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

    -- if shared with bikes, reduce speed
    if way.tags:Find('bicycle') == "designated" then
        way.speed = way.speed * 0.8
    end

    -- if there is a sidewalk, the better
    local sidewalk = way.tags:Find('sidewalk')
    if sidewalk == 'both' or sidewalk == 'left' or sidewalk == 'right' then
        way.speed = way.speed + 0.1
    end

    if junction == "roundabout" then
        way.roundabout = true
    end
  
	way.type = 1
	return 1
end
