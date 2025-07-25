local function chunk_key(pos)
  return pos.x .. "," .. pos.y
end

local function get_chunk_positions_around(cx, cy, radius)
  local positions = {}
  for dx = -radius, radius do
    for dy = -radius, radius do
      table.insert(positions, {x = cx + dx, y = cy + dy})
    end
  end
  return positions
end

local function is_chunk_active(surface, chunk)
  local area = {
    {chunk.x * 32, chunk.y * 32},
    {(chunk.x + 1) * 32, (chunk.y + 1) * 32}
  }

  -- Check for player entities (e.g. assemblers, belts, etc.)
  local entities = surface.find_entities_filtered{
    area = area,
    force = "player"
  }

  for _, entity in ipairs(entities) do
    if not (
      entity.name == "fulgoran-ruin-attractor" or
      entity.name:find("^space%-") or
      entity.name == "electric-energy-interface"
    ) then
      return true -- count only real "active" player-built entities
    end
  end

  -- Check for players inside chunk
  for _, player in pairs(game.connected_players) do
    if player.surface == surface then
      local pos = player.position
      if math.floor(pos.x / 32) == chunk.x and math.floor(pos.y / 32) == chunk.y then
        return true
      end
    end
  end

  -- Check pollution
  local pollution = surface.get_pollution{
    x = chunk.x * 32 + 16,
    y = chunk.y * 32 + 16
  }
  if pollution and pollution > 0 then return true end

  -- Check for radar or roboport coverage
  local radars = surface.find_entities_filtered{
    area = area,
    name = {"roboport", "radar"},
    force = "player"
  }
  if #radars > 0 then return true end

  return false
end

-- keep chunks surrounded on 4 cardinal sides
local function expand_preserve_for_surrounded_chunks(preserve_chunks)
  local expanded = {}
  for key, _ in pairs(preserve_chunks) do
    expanded[key] = true
  end

  for key, _ in pairs(preserve_chunks) do
    local x, y = key:match("(-?%d+),(-?%d+)")
    x = tonumber(x)
    y = tonumber(y)

    -- Check neighbor positions
    local neighbors = {
      {x = x, y = y - 1},
      {x = x, y = y + 1},
      {x = x - 1, y = y},
      {x = x + 1, y = y}
    }

    for _, n in ipairs(neighbors) do
      local nk = chunk_key(n)
      -- Only consider adding chunk if it's not already preserved and all 4 neighbors are preserved
      if not expanded[nk] then
        local north = chunk_key({x = n.x, y = n.y - 1})
        local south = chunk_key({x = n.x, y = n.y + 1})
        local west  = chunk_key({x = n.x - 1, y = n.y})
        local east  = chunk_key({x = n.x + 1, y = n.y})

        if preserve_chunks[north] and preserve_chunks[south] and preserve_chunks[east] and preserve_chunks[west] then
          expanded[nk] = true
        end
      end
    end
  end

  return expanded
end

local function cleanup_chunks(surface)
  local active_chunks = {}
  local preserve_chunks = {}

  for chunk in surface.get_chunks() do
    local cx, cy = chunk.x, chunk.y
    local is_active = is_chunk_active(surface, chunk)
    local key = chunk_key(chunk)
    if is_active then
      active_chunks[key] = true
      -- Add surrounding 5x5 area
      for dx = -2, 2 do
        for dy = -2, 2 do
          local nx, ny = cx + dx, cy + dy
          preserve_chunks[chunk_key({x = nx, y = ny})] = true
        end
      end
    end
  end

  preserve_chunks = expand_preserve_for_surrounded_chunks(preserve_chunks)

  local deleted_count = 0
  for chunk in surface.get_chunks() do
    local key = chunk_key(chunk)
    if not preserve_chunks[key] then
      local success = surface.delete_chunk({x = chunk.x, y = chunk.y})
      if success then
        deleted_count = deleted_count + 1
      end
    end
  end

  return deleted_count
end

commands.add_command("cleanup_chunks", "Clean unused chunks from a surface. Usage: /cleanup_chunks <surface>",
  function(cmd)
    local surface_name = cmd.parameter
    if not surface_name then
      if cmd.player_index then
        game.players[cmd.player_index].print("Please provide a surface name. Example: /cleanup_chunks nauvis")
      else
        log("Please provide a surface name. Example: /cleanup_chunks nauvis")
      end
      return
    end

    local surface = game.surfaces[surface_name]
    if not surface then
      if cmd.player_index then
        game.players[cmd.player_index].print("Surface '" .. surface_name .. "' not found.")
      else
        log("Surface '" .. surface_name .. "' not found.")
      end
      return
    end

    local deleted = cleanup_chunks(surface)
    local msg = "Deleted unused chunks from surface '" .. surface_name .. "'."
    if cmd.player_index then
      game.players[cmd.player_index].print(msg)
    else
      log(msg)
    end
  end
)