-- Noch ein Tipp: OSRM 5.7.0 feature: `force_split_edges` flag to the global properties which 
-- when set to true guarantees that the segment function will be called for all segments, 
-- but also doubles memory consumption in the worst case.

api_version = 4

Set = require('lib/set')
Sequence = require('lib/sequence')
Handlers = require("lib/way_handlers")
find_access_tag = require("lib/access").find_access_tag

-- Setup function to load the raster file (shadow data) and initialize the walking profile
function setup()
  local raster_path = os.getenv('OSRM_PROFILE_PATH') ..  "/vampire/shadows_zurich_city.asc"

  -- Update these values as per your .asc file header:
  -- This is an example. Ensure these match the actual ASC file's metadata.
  local lon_min = 8.811776471450    -- xllcorner
  local ncols = 509
  local nrows = 347
  local cellsize = 0.000026370000
  
  local lon_max = lon_min + (ncols * cellsize)
  local lat_min = 47.221587715161   -- yllcorner
  local lat_max = lat_min + (nrows * cellsize)

  local raster_source = raster:load(
    raster_path,
    lon_min, lon_max,
    lat_min, lat_max,
    nrows,
    ncols
  )

  local walking_speed = 5

  return {
    properties = {
      weight_name = 'duration',
      max_speed_for_map_matching = 40/3.6, -- km/h to m/s
      call_tagless_node_function = false,
      traffic_light_penalty = 2,
      u_turn_penalty = 2,
      continue_straight_at_waypoint = false,
      use_turn_restrictions = false,
      force_split_edges = true, -- Ensures segment processing is always called
    },

    raster_source = raster_source,
    default_mode = mode.walking,
    default_speed = walking_speed,
    oneway_handling = 'specific',
    barrier_whitelist = Set { 'cycle_barrier', 'bollard', 'entrance' },
    access_tag_whitelist = Set { 'yes', 'foot', 'permissive', 'designated' },
    access_tag_blacklist = Set { 'no', 'agricultural', 'forestry', 'private', 'delivery' },
    restricted_highway_whitelist = Set { },
    access_tags_hierarchy = Sequence { 'foot', 'access' },
    restricted_access_tag_list = Set { },
    service_access_tag_blacklist = Set { },
    restrictions = Sequence { 'foot' },
    suffix_list = Set { 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'North', 'South', 'West', 'East' },
    avoid = Set { 'impassable' },

    speeds = Sequence {
      highway = {
        primary = walking_speed,
        primary_link = walking_speed,
        secondary = walking_speed,
        secondary_link = walking_speed,
        tertiary = walking_speed,
        tertiary_link = walking_speed,
        unclassified = walking_speed,
        residential = walking_speed,
        road = walking_speed,
        living_street = walking_speed,
        service = walking_speed,
        track = walking_speed,
        path = walking_speed,
        steps = walking_speed,
        pedestrian = walking_speed,
        footway = walking_speed,
        pier = walking_speed,
      },
      railway = { platform = walking_speed },
      amenity = { parking = walking_speed, parking_entrance = walking_speed },
      man_made = { pier = walking_speed },
      leisure = { track = walking_speed },
    },

    route_speeds = { ferry = 5 },
    bridge_speeds = { },
    surface_speeds = {
      fine_gravel = walking_speed * 0.75,
      gravel = walking_speed * 0.75,
      pebblestone = walking_speed * 0.75,
      mud = walking_speed * 0.5,
      sand = walking_speed * 0.5,
    },
    tracktype_speeds = { },
    smoothness_speeds = { }
  }
end

function log_result(result)
  print("Inspecting result object:")
  print("Forward Rate:", result.forward_rate)
  print("Backward Rate:", result.backward_rate)
  print("Forward Speed:", result.forward_speed)
  print("Backward Speed:", result.backward_speed)
  print("Weight:", result.weight)
end


-- Calculate rate based on shadow_value:
-- - -9999 (nodata): return 0, no adjustment
-- - 0 (black/shadow): very high preference
-- - Increasing values: decreasing preference
function calculate_rate(shadow_value)
  if shadow_value == -9999 then
    return 0
  end

  if shadow_value < 0 then
    return 0
  end

  -- Exponential decay approach:
  -- rate = large_factor * exp(-shadow_value * scale)
  -- For shadow_value = 0, rate = large_factor * exp(0) = large_factor (maximum preference)
  -- For larger shadow_value, rate decreases exponentially.
  -- Adjust 'scale' to control how fast the preference drops off.
  
  local large_factor = 1000000
  local scale = 0.5  -- Increase this value to make the penalty grow faster for large shadow values

  local rate = large_factor * math.exp(-shadow_value * scale)
  return rate
end



function process_node(profile, node, result)
  local access = find_access_tag(node, profile.access_tags_hierarchy)
  if access then
    if profile.access_tag_blacklist[access] then
      result.barrier = true
    end
  else
    local barrier = node:get_value_by_key("barrier")
    if barrier then
      local bollard = node:get_value_by_key("bollard")
      local rising_bollard = bollard and "rising" == bollard
      if not profile.barrier_whitelist[barrier] and not rising_bollard then
        result.barrier = true
      end
    end
  end

  local tag = node:get_value_by_key("highway")
  if "traffic_signals" == tag then
    result.traffic_lights = true
  end
end

function process_way(profile, way, result)
  local data = {
    highway = way:get_value_by_key('highway'),
    tunnel = way:get_value_by_key('tunnel'),
    public_transport = way:get_value_by_key('public_transport'),
    shelter = way:get_value_by_key('shelter')

  }

  if next(data) == nil then
    return
  end

  -- log_result(result)

  local handlers = Sequence {
    WayHandlers.default_mode,
    WayHandlers.access,
    WayHandlers.speed,
    WayHandlers.surface
  }

  WayHandlers.run(profile, way, result, data, handlers)

  if (data.tunnel == "yes" or data.tunnel == "building_passage") or
     (data.public_transport == "platform") or
     (data.public_transport == "shelter" and data.shelter == "yes") then
    -- Add a custom "priority" class
    result.forward_classes = result.forward_classes or {}
    result.forward_classes["priority"] = true
  end
end

function process_segment(profile, segment)
  -- Query raster data for source location
  local sourceData = raster:query(profile.raster_source, segment.source.lon, segment.source.lat)
  -- Query raster data for target location
  local targetData = raster:query(profile.raster_source, segment.target.lon, segment.target.lat)

  -- Calculate rates for source and target
  local sourceRate = calculate_rate(sourceData.datum)
  local targetRate = calculate_rate(targetData.datum)

  -- Average the rates; if both are 0 (nodata), no adjustment
  local average_rate = 0
  if sourceRate > 0 or targetRate > 0 then
    average_rate = (sourceRate + targetRate) / 2
  end

  -- If we have a positive average_rate, adjust the segment weight
  -- Since lower shadow_value = higher rate = more preferred,
  -- we divide the segment weight by average_rate to reduce cost in those areas
  if average_rate > 0 then
    segment.weight = segment.weight / average_rate
  end

  -- Adjust weight based on custom "priority" class
  if segment.forward_classes and segment.forward_classes["priority"] then
    -- Further reduce weight for preferred routing
    segment.weight = segment.weight * 0.5
  end
end

function process_turn(profile, turn)
  turn.duration = 0.

  if turn.is_u_turn then
    turn.duration = turn.duration + profile.properties.u_turn_penalty
  end

  if turn.has_traffic_light then
    turn.duration = profile.properties.traffic_light_penalty
  end

  if profile.properties.weight_name == 'routability' then
    if not turn.source_restricted and turn.target_restricted then
      turn.weight = turn.weight + 3000
    end
  end
end

return {
  setup = setup,
  process_way = process_way,
  process_node = process_node,
  process_segment = process_segment,
}
