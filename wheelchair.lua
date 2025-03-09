-- API Version
api_version = 4

-------------------------------------------------------------------
-- Configuration Block
-------------------------------------------------------------------
-- These settings are intended to be easily adjustable by the user.
local CONFIG = {
  -- Debug settings
  DEBUG = false,  -- Toggle debug logging (true/false)

  -- Raster source settings
  RASTER_SOURCE = os.getenv('OSRM_RASTER_SOURCE') or "Alti3D_Zurich_10000_Zentimeter.asc",
  RASTER_METADATA = {
    lon_min = 8.470792821210,   -- xllcorner
    lat_min = 47.340983157973,  -- yllcorner
    ncols = 23847,              -- number of columns
    nrows = 16196,              -- number of rows
    cellsize = 0.000005630727    -- cellsize in degrees
  },

  -- Default walking speed (in m/s)
  WALKING_SPEED = 5,

  -- Slope calculation and penalty constants
  METERS_PER_DEGREE = 111320,     -- Approximate conversion factor from degrees to meters
  MIN_SLOPE_ANGLE = 0,            -- Minimum slope angle for clamping (degrees)
  MAX_SLOPE_ANGLE = 30,           -- Maximum slope angle for clamping (degrees)
  LOWER_SLOPE_THRESHOLD = 5,      -- Slope threshold for first penalty phase (degrees)
  PENALTY_AT_THRESHOLD = 1.5,     -- Extra penalty factor at the threshold
  MAX_PENALTY = 3.5,              -- Extra penalty factor at maximum slope
  BASE_SCALE = 0.2                -- Scaling factor for the exponential base multiplier
}

-------------------------------------------------------------------
-- Required Libraries
-------------------------------------------------------------------
Set = require('lib/set')
Sequence = require('lib/sequence')
Handlers = require("lib/way_handlers")
find_access_tag = require("lib/access").find_access_tag

-------------------------------------------------------------------
-- Debug Logging Function
-------------------------------------------------------------------
local function debugLog(...)
  if CONFIG.DEBUG then
    print(...)
  end
end

-------------------------------------------------------------------
-- Configuration: OSM Keys and Wheelchair Rules
-------------------------------------------------------------------
local osm_keys = {
  { key = 'highway' },
  { key = 'tunnel' },
  { key = 'public_transport' },
  { key = 'shelter' },
  { key = 'foot' },
  { key = 'wheelchair' },
  { key = 'barrier' },
  { key = 'staircase' },
  { key = 'sidewalk' },
  { key = 'ramp' },
  { key = 'access' },
  { key = 'footway' },
  { key = 'entrance' },
  -- Additional parent keys for wheelchair rules:
  { key = 'trance' },
  { key = 'kerb' },
  { key = 'incline' },
  { key = 'surface' },
  { key = 'smoothness' },
}

local wheelchair_rules = {
  {
    key = 'wheelchair',
    type = "blacklist",
    values = { "no", "steps", "escalator", "elevator" }
  },
  {
    key = 'wheelchair',
    type = "priority",
    values = { "yes" }
  },
  {
    key = 'wheelchair',
    type = "priority",
    values = { "designated", "permissive", "limited" }
  },
  {
    key = 'barrier',
    type = "blacklist",
    values = { "kerb" }
  },
  {
    key = 'sidewalk:left:wheelchair',
    type = "priority",
    values = { "yes", "designated", "permissive", "limited" }
  },
  {
    key = 'sidewalk:right:wheelchair',
    type = "priority",
    values = { "yes", "designated", "permissive", "limited" }
  },
  {
    key = 'ramp',
    type = "priority",
    values = { "yes" }
  },
  {
    key = 'sidewalk:left:sloped_curb',
    type = "priority",
    values = { "yes", "reduced", "low" }
  },
  {
    key = 'sidewalk:right:sloped_curb',
    type = "priority",
    values = { "yes", "reduced", "low" }
  },
  {
    key = 'access',
    type = "blacklist",
    values = { "private", "no", "restricted" }
  },
  {
    key = 'footway',
    type = "priority",
    values = { "yes", "designated", "permissive" }
  },
  {
    key = 'trance',
    type = "priority",
    values = { "yes", "designated", "permissive" }
  },
  {
    key = 'kerb:mobility',
    type = "priority",
    values = { "lowered", "flush" }
  },
  {
    key = 'kerb:mobility',
    type = "blacklist",
    values = { "raised", "uneven" }
  },
  {
    key = 'incline',
    type = "blacklist",
    values = { "steep", "very_steep", "extreme" }
  },
  {
    key = 'surface',
    type = "priority",
    values = { "asphalt", "concrete", "paved" }
  },
  {
    key = 'surface',
    type = "blacklist",
    values = { "gravel", "dirt", "cobblestone" }
  },
  {
    key = 'sidewalk:wheelchair',
    type = "priority",
    values = { "yes", "designated" }
  },
  {
    key = 'smoothness',
    type = "priority",
    values = { "excellent", "good", "intermediate" }
  },
  {
    key = 'smoothness',
    type = "blacklist",
    values = { "bad", "very_bad", "horrible", "very_horrible" }
  }
}

-- Precompute a set of key prefixes for OSM keys
local function compute_osm_keys_set(osm_keys_list)
  local set = {}
  for _, keyEntry in ipairs(osm_keys_list) do
    local keyPrefix = keyEntry.key:match("^[^:]+")
    set[keyPrefix] = true
  end
  return set
end
local osm_keys_set = compute_osm_keys_set(osm_keys)

-------------------------------------------------------------------
-- Helper Functions
-------------------------------------------------------------------
-- Check if a value exists in a table.
local function contains(tbl, val)
  for _, v in ipairs(tbl) do
    if v == val then
      return true
    end
  end
  return false
end

-- Validate that every wheelchair rule uses a defined OSM key prefix.
local function validate_osm_keys_and_wheelchair_rules()
  for _, rule in ipairs(wheelchair_rules) do
    local rulePrefix = rule.key:match("^[^:]+")
    if not osm_keys_set[rulePrefix] then
      debugLog("Warning: wheelchair rule key '" .. rule.key .. "' is not defined in osm_keys.")
    end
  end
end

-- For nodes: Check wheelchair rules and return if it should be a barrier
local function apply_wheelchair_rules_to_node(node, rules)
  for _, rule in ipairs(rules) do
    local value = node:get_value_by_key(rule.key)
    if value and contains(rule.values, value) then
      if rule.type == "blacklist" then
        return true  -- Mark node as barrier immediately
      elseif rule.type == "priority" then
        -- Optional: handle priority nodes differently if needed
      end
    end
  end
  return false
end

-- For ways: Apply wheelchair rules to the result's forward_classes
local function apply_wheelchair_rules_to_way(data, result)
  -- Initialize forward_classes first (on the result table, not segment)
  result.forward_classes = result.forward_classes or {}
  
  for _, rule in ipairs(wheelchair_rules) do
    local value = data[rule.key]
    if value and contains(rule.values, value) then
      if rule.type == "blacklist" then
        result.forward_classes["blacklist"] = true
      elseif rule.type == "priority" then
        result.forward_classes["priority"] = true
      end
    end
  end
end

-- Calculate raster bounds from metadata.
local function calculate_raster_bounds(metadata)
  local lon_min = metadata.lon_min
  local lat_min = metadata.lat_min
  local ncols = metadata.ncols
  local nrows = metadata.nrows
  local cellsize = metadata.cellsize

  local lon_max = lon_min + (ncols * cellsize)
  local lat_max = lat_min + (nrows * cellsize)
  return lon_min, lon_max, lat_min, lat_max
end

-------------------------------------------------------------------
-- Setup Function
-------------------------------------------------------------------
-- Loads the raster file and initializes the walking profile.
function setup()
  local raster_metadata = CONFIG.RASTER_METADATA
  local lon_min, lon_max, lat_min, lat_max = calculate_raster_bounds(raster_metadata)

  local raster_source = raster:load(
    CONFIG.RASTER_SOURCE,
    lon_min, lon_max,
    lat_min, lat_max,
    raster_metadata.nrows,
    raster_metadata.ncols
  )
  if not raster_source then
    error("Failed to load raster from path: " .. CONFIG.RASTER_SOURCE)
  end

  return {
    properties = {
      weight_name = 'duration',
      max_speed_for_map_matching = 40 / 3.6,
      call_tagless_node_function = false,
      traffic_light_penalty = 2,
      u_turn_penalty = 2,
      continue_straight_at_waypoint = false,
      use_turn_restrictions = false,
      force_split_edges = true,
    },
    raster_source = raster_source,
    default_mode = mode.walking,
    default_speed = CONFIG.WALKING_SPEED,
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
        primary = CONFIG.WALKING_SPEED,
        primary_link = CONFIG.WALKING_SPEED,
        secondary = CONFIG.WALKING_SPEED,
        secondary_link = CONFIG.WALKING_SPEED,
        tertiary = CONFIG.WALKING_SPEED,
        tertiary_link = CONFIG.WALKING_SPEED,
        unclassified = CONFIG.WALKING_SPEED,
        residential = CONFIG.WALKING_SPEED,
        road = CONFIG.WALKING_SPEED,
        living_street = CONFIG.WALKING_SPEED,
        service = CONFIG.WALKING_SPEED,
        track = CONFIG.WALKING_SPEED,
        path = CONFIG.WALKING_SPEED,
        steps = CONFIG.WALKING_SPEED,
        pedestrian = CONFIG.WALKING_SPEED,
        footway = CONFIG.WALKING_SPEED,
        pier = CONFIG.WALKING_SPEED,
      },
      railway = { platform = CONFIG.WALKING_SPEED },
      amenity = { parking = CONFIG.WALKING_SPEED, parking_entrance = CONFIG.WALKING_SPEED },
      man_made = { pier = CONFIG.WALKING_SPEED },
      leisure = { track = CONFIG.WALKING_SPEED },
    },

    route_speeds = { ferry = 5 },
    bridge_speeds = { },
    surface_speeds = {
      fine_gravel = CONFIG.WALKING_SPEED * 0.75,
      gravel = CONFIG.WALKING_SPEED * 0.75,
      pebblestone = CONFIG.WALKING_SPEED * 0.75,
      mud = CONFIG.WALKING_SPEED * 0.5,
      sand = CONFIG.WALKING_SPEED * 0.5,
    },
    tracktype_speeds = { },
    smoothness_speeds = { }
  }
end

-------------------------------------------------------------------
-- Way and Node Processing Functions
-------------------------------------------------------------------
local function load_way_data(way, keys)
  local data = {}
  for _, k in ipairs(keys) do
    local keyName = type(k) == "table" and k.key or k
    data[keyName] = way:get_value_by_key(keyName)
  end
  return data
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
      local rising_bollard = bollard and (bollard == "rising")
      if not profile.barrier_whitelist[barrier] and not rising_bollard then
        result.barrier = true
      end
    end
  end

  if node:get_value_by_key("highway") == "traffic_signals" then
    result.traffic_lights = true
  end

  local node_data = {}
  for _, k in ipairs(osm_keys) do
    local keyName = type(k) == "table" and k.key or k
    node_data[keyName] = node:get_value_by_key(keyName)
  end
  
  -- Use the node-specific helper
  if apply_wheelchair_rules_to_node(node, wheelchair_rules) then
    result.barrier = true
  end
end

function process_way(profile, way, result)
  validate_osm_keys_and_wheelchair_rules()
  local data = load_way_data(way, osm_keys)
  if next(data) == nil then return end
  
  local handlers = Sequence {
    WayHandlers.default_mode,
    WayHandlers.access,
    WayHandlers.speed,
    WayHandlers.surface
  }
  WayHandlers.run(profile, way, result, data, handlers)
  
  -- Use the way-specific helper
  apply_wheelchair_rules_to_way(data, result)
end
-------------------------------------------------------------------
-- Slope Calculation and Segment Processing
-------------------------------------------------------------------
local function clamp(value, lower, upper)
  if value < lower then
    debugLog("Warning: value", value, "is below lower bound", lower, "- clamping to", lower)
    return lower
  elseif value > upper then
    debugLog("Warning: value", value, "is above upper bound", upper, "- clamping to", upper)
    return upper
  else
    return value
  end
end

local function calc_slope_angle(segment, sourceData, targetData)
  if not sourceData or not targetData then
    debugLog("Warning: Missing raster data for segment ID:", segment.id or "unknown")
    return 0
  end

  if sourceData.datum == targetData.datum then
    debugLog("Segment ID:", segment.id or "unknown", "- no altitude difference; slope = 0")
    return 0
  end

  local altitude_difference = math.abs(sourceData.datum - targetData.datum)
  local avg_lat = (segment.source.lat + segment.target.lat) / 2
  local avg_lat_rad = avg_lat * math.pi / 180

  local lat_distance = (segment.source.lat - segment.target.lat) * CONFIG.METERS_PER_DEGREE
  local lon_distance = (segment.source.lon - segment.target.lon) * CONFIG.METERS_PER_DEGREE * math.cos(avg_lat_rad)
  local horizontal_distance = math.sqrt(lat_distance^2 + lon_distance^2)

  if horizontal_distance > 0 then
    local slope_angle = math.deg(math.atan(altitude_difference / horizontal_distance))
    slope_angle = clamp(slope_angle, CONFIG.MIN_SLOPE_ANGLE, CONFIG.MAX_SLOPE_ANGLE)
    debugLog("Segment ID:", segment.id or "unknown", "slope angle (clamped):", slope_angle, "degrees")
    return slope_angle
  end

  return 0
end

function calculate_slope_multiplier(slope)
  if type(slope) ~= "number" or slope == 0 then
    return 1
  end

  local base_multiplier = math.exp(slope * CONFIG.BASE_SCALE)
  local extra_factor = 1

  if slope < CONFIG.LOWER_SLOPE_THRESHOLD then
    local ratio = slope / CONFIG.LOWER_SLOPE_THRESHOLD
    extra_factor = 1 + (CONFIG.PENALTY_AT_THRESHOLD - 1) * ratio
  else
    local ratio = math.min((slope - CONFIG.LOWER_SLOPE_THRESHOLD) / (CONFIG.MAX_SLOPE_ANGLE - CONFIG.LOWER_SLOPE_THRESHOLD), 1)
    extra_factor = CONFIG.PENALTY_AT_THRESHOLD + (CONFIG.MAX_PENALTY - CONFIG.PENALTY_AT_THRESHOLD) * ratio
  end

  local multiplier = base_multiplier * extra_factor
  debugLog("Slope:", slope, "degrees, base_multiplier:", base_multiplier, "extra_factor:", extra_factor, "total multiplier:", multiplier)
  return multiplier
end

-- Modify adjust_segment_weight to handle only slope adjustments
local function adjust_segment_weight(segment, slope_value)
  debugLog("Segment ID:", segment.id or "unknown", "original weight:", segment.weight)
  
  -- Only apply slope multiplier here - forward classes are already handled in process_way
  local slope_multiplier = calculate_slope_multiplier(slope_value)
  segment.weight = segment.weight * slope_multiplier
  
  debugLog("Segment ID:", segment.id or "unknown", "adjusted weight:", segment.weight)
end

function apply_forward_class_adjustments(segment)
  local priority_scale = 1
  local blocked_segment = 1e2

  if segment.forward_classes then
    -- If any blacklist marker is present, apply a heavy penalty.
    if segment.forward_classes["blacklist"] then
      if DEBUG then
        print("Segment ID:", segment.id or "unknown", "is blacklisted")
      end

      segment.weight = segment.weight * blocked_segment
    end
    -- If a priority marker exists, apply lower penalty.
    if segment.forward_classes["priority"] then
      if DEBUG then
        print("Segment ID:", segment.id or "unknown", "is prioritized")
      end

      segment.weight = segment.weight * priority_scale
    end
  end
end

local function query_raster_for_segment(segment, raster_source)
  local sourceData = raster:query(raster_source, segment.source.lon, segment.source.lat)
  local targetData = raster:query(raster_source, segment.target.lon, segment.target.lat)
  return sourceData, targetData
end

function process_segment(profile, segment)
  -- Query altitude data for source and target
  local sourceData, targetData = query_raster_for_segment(segment, profile.raster_source)

  local slope_angle = calc_slope_angle(segment, sourceData, targetData)
  
  adjust_segment_weight(segment, slope_angle)
end

-------------------------------------------------------------------
-- Turn Processing
-------------------------------------------------------------------
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

-------------------------------------------------------------------
-- Return Profile Functions
-------------------------------------------------------------------
return {
  setup = setup,
  process_way = process_way,
  process_node = process_node,
  process_segment = process_segment,
  process_turn = process_turn,
}
