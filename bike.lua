-- Begin of globals

barrier_whitelist = { [""] = true, ["bollard"] = true, ["entrance"] = true, ["cattle_grid"] = true, ["border_control"] = true, ["toll_booth"] = true, ["no"] = true, ["sally_port"] = true, ["gate"] = true}
access_tag_whitelist = { ["yes"] = true, ["permissive"] = true, ["designated"] = true	}
access_tag_blacklist = { ["no"] = true, ["private"] = true, ["agricultural"] = true, ["forestery"] = true }
access_tag_restricted = { ["destination"] = true, ["delivery"] = true }
access_tags_hierachy = { "bicycle", "vehicle", "access" }
service_tag_restricted = { ["parking_aisle"] = true }
ignore_in_grid = { ["ferry"] = true }
surface_speeds = { ["paved"] = 0, ["gravel"] = -2, ["asphalt"] = 0, ["ground"] = -1, ["unpaved"] = -2, ["grass"] = -5, ["dirt"] = -5, ["concrete"] = 0, ["cobblestone"] = -5, ["pebblestone"] = -1, ["paving_stones"] = 0, ["compacted"] = -1, ["wood"] = -1, ["grit"] = -4, ["sand"] = -6 }
-- just note the unpaved ones
default_surface = { ["track"] = "compacted", ["path"] = "unpaved" } 

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
	["default"] = 18
}

route_profile = {
	["ferry"] = 5
}

man_made_profile = {
	["pier"] = 5
}

obey_bollards 			= false
ignore_areas 			= true -- future feature
traffic_signal_penalty 	= 2
u_turn_penalty 			= 20

-- End of globals

--find first tag in access hierachy which is set
function find_access_tag(source)
	for i,v in ipairs(access_tags_hierachy) do 
		local tag = source.tags:Find(v)
		if tag ~= '' then --and tag ~= "" then
			return tag
		end
	end
	return nil
end

function node_function (node)
	local barrier = node.tags:Find ("barrier")
	local access = find_access_tag(node)
	local traffic_signal = node.tags:Find("highway")
	
	-- flag node if it carries a traffic light	
	if traffic_signal == "traffic_signals" then
		node.traffic_light = true
	end
	
	-- parse access and barrier tags
	if access  and access ~= "" then
		if access_tag_blacklist[access] then
			node.bollard = true
		else
			node.bollard = false
		end
	elseif barrier and barrier ~= "" then
		if barrier_whitelist[barrier] then
			node.bollard = false
		else
			node.bollard = true
		end
	end
	
	return 1
end

function way_function (way, numberOfNodesInWay)
	-- A way must have two nodes or more
	if(numberOfNodesInWay < 2) then
		return 0;
	end

 	-- Check if we are allowed to access the way
	local access = find_access_tag(way)
    local specaccess = way.tags:Find("bicycle")
    if access_tag_blacklist[access] then
		return 0
    end

	
	-- First, get the properties of each way that we come across
	local highway = way.tags:Find("highway")
	local junction = way.tags:Find("junction")
	local route = way.tags:Find("route")
	local man_made = way.tags:Find("man_made")
	local barrier = way.tags:Find("barrier")
	local duration	= way.tags:Find("duration")
	local service	= way.tags:Find("service")
	local area = way.tags:Find("area")

    -- Set the name that will be used for instructions	
	local name = way.tags:Find("name")
	local ref = way.tags:Find("ref")
	if "" ~= ref then
		way.name = ref
	elseif "" ~= name then
		way.name = name
	else
		way.name = highway		-- if no name exists, use way type
	end

		-- Handling ferries and piers
    if (route_profile[route] ~= nil and route_profile[route] > 0) or
       (man_made_profile[man_made] ~= nil and man_made_profile[man_made] > 0) 
    then
      if durationIsValid(duration) then
	    way.speed = math.max( duration / math.max(1, numberOfNodesInWay-1) );
        way.is_duration_set = true
      end
      way.direction = Way.bidirectional;
      if not way.is_duration_set then
        if route_profile[route] ~= nil then
           way.speed = route_profile[route]
        elseif man_made_profile[man_made] ~= nil then
           way.speed = man_made_profile[man_made]
        end
      end
      way.type = 1
      return 1
    end

    -- no biking above grade3
    local trackgrade = way.tags:Find("tracktype")
    if (trackgrade == "grade4" or trackgrade == "grade5") then
      return 0
    end
    -- no biking on sac_scale
    local sac_scale = way.tags:Find("sac_scale")
    if highway == 'path' and sac_scale ~= "" then
      return 0
    end


    -- designated bike ways get maxspeed, everything else according to profile
    if (specaccess == 'designated') then
      way.speed = speed_profile["default"]
    else
      -- Set the avg speed on the way if it is accessible by road class
        if (speed_profile[highway] ~= nil and way.speed == -1 ) then 
          way.speed = speed_profile[highway]
        -- Set the avg speed on ways that are marked accessible
        elseif access_tag_whitelist[specaccess] then
            way.speed = speed_profile["default"]
        else
          return 0
        end
    end

    -- surface speeds
    local surface = way.tags:Find("surface")

    if "" == surface then
      if trackgrade == "grade1" then
        surface = "paved"
      elseif trackgrade == "grade2" then
        surface = "compacted"
      elseif trackgrade == "grade3" then
        surface = "gravel"
      else
        surface = default_surface[highway]
      end
    end
    if (surface_speeds[surface] ~= nil and way.speed > surface_speeds[surface]) then
      way.speed = way.speed - surface_speeds[surface]
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
  
	way.type = 1
	return 1
end
