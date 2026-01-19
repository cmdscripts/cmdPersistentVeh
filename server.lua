-- server.lua
local ESX = exports['es_extended']:getSharedObject()

local function dbg(...)
  if not Config or not Config.Debug then return end
  print(('[pv] %s'):format(table.concat({ ... }, ' ')))
end

local spawned = {}
local saving = false

local function nowMs()
  return os.time() * 1000
end

local function enc(v)
  if v == nil then return nil end
  return json.encode(v)
end

local function dec(v)
  if not v or v == '' then return nil end
  return json.decode(v)
end

local function anyPlayer()
  local players = GetPlayers()
  local p = players and players[1]
  if not p then return nil end
  return tonumber(p)
end

local function getIdentifier(source)
  local xPlayer = ESX.GetPlayerFromId(source)
  return xPlayer and xPlayer.identifier or nil
end

local function isPlateOwnedBy(source, plate)
  local identifier = getIdentifier(source)
  if not identifier or not plate or plate == '' then return false end
  local row = MySQL.single.await('SELECT 1 FROM owned_vehicles WHERE owner = ? AND plate = ? LIMIT 1', { identifier, plate })
  return row ~= nil
end

local function ensureRowIdByPlate(plate)
  local row = MySQL.single.await('SELECT id FROM persistent_vehicles WHERE plate = ? LIMIT 1', { plate })
  return row and row.id or nil
end

local function toU32(n)
  n = tonumber(n) or 0
  if n < 0 then return n + 4294967296 end
  return n
end

local function parseModel(raw)
  if raw == nil then return 0 end
  local n = tonumber(raw)
  if n and n ~= 0 then return toU32(n) end
  if type(raw) == 'string' and raw ~= '' then return toU32(joaat(raw)) end
  return 0
end

local function upsertVehicle(data)
  MySQL.insert.await([[
    INSERT INTO persistent_vehicles (model, plate, x, y, z, heading, props, extra, last_moved, lock_status)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      model = VALUES(model),
      x = VALUES(x),
      y = VALUES(y),
      z = VALUES(z),
      heading = VALUES(heading),
      props = VALUES(props),
      extra = VALUES(extra),
      last_moved = VALUES(last_moved),
      lock_status = VALUES(lock_status)
  ]], {
    data.model,
    data.plate,
    data.x, data.y, data.z,
    data.heading,
    enc(data.props),
    enc(data.extra),
    data.last_moved or 0,
    data.lock_status or (Config.DefaultLockStatus or 0)
  })
end

local function setState(veh, rowId, plate, lockStatus)
  local st = Entity(veh).state
  st.pvId = rowId
  st.pvPlate = plate
  if Config.PersistLockState then
    st.pvLockStatus = lockStatus or (Config.DefaultLockStatus or 0)
  end
end

local function applyLockServer(veh, lockStatus)
  if not Config.PersistLockState then return end
  local ls = tonumber(lockStatus) or (Config.DefaultLockStatus or 0)
  SetVehicleDoorsLocked(veh, ls)
end

local function validateCoords(row)
  if type(row.x) ~= 'number' or type(row.y) ~= 'number' or type(row.z) ~= 'number' then
    dbg('spawn skip bad coords type', tostring(row.id), tostring(row.plate))
    return false
  end
  local zmin = Config.SpawnZMin or -100.0
  local zmax = Config.SpawnZMax or 2000.0
  if row.z < zmin or row.z > zmax then
    dbg('spawn skip z out', tostring(row.id), tostring(row.plate), 'z', tostring(row.z))
    return false
  end
  return true
end

local function createVeh(model, x, y, z, heading)
  local veh = 0

  if CreateVehicleServerSetter then
    local ok, r = pcall(CreateVehicleServerSetter, model, (Config.ServerSetterType or 'automobile'), x, y, z, heading)
    if ok then veh = r or 0 end
  end

  if veh == 0 then
    veh = CreateVehicle(model, x, y, z, heading, true, true) or 0
  end

  return veh
end

lib.callback.register('pv:saveOnExit', function(source, netId, props, coords, heading, extra)
  local veh = NetworkGetEntityFromNetworkId(netId)
  if not veh or veh == 0 or not DoesEntityExist(veh) then
    dbg('saveOnExit fail entity', 'netId', tostring(netId))
    return false
  end

  local plate = GetVehicleNumberPlateText(veh)

  if not isPlateOwnedBy(source, plate) then
    dbg('saveOnExit denied not owner', tostring(source), plate)
    return false
  end

  local model = GetEntityModel(veh)

  local pos = coords
  if type(pos) ~= 'vector3' then
    local c = GetEntityCoords(veh)
    pos = vector3(c.x, c.y, c.z)
  end

  local hd = heading
  if type(hd) ~= 'number' then
    hd = GetEntityHeading(veh)
  end

  local ls = Config.DefaultLockStatus or 0
  if Config.PersistLockState then
    if type(extra) == 'table' and type(extra.lockStatus) == 'number' then
      ls = extra.lockStatus
    else
      local st = Entity(veh).state
      ls = (st and st.pvLockStatus) or ls
    end
  end

  upsertVehicle({
    model = tostring(model),
    plate = plate,
    x = pos.x, y = pos.y, z = pos.z,
    heading = hd,
    props = props,
    extra = (Config.PersistExtra and extra) or nil,
    last_moved = nowMs(),
    lock_status = (Config.PersistLockState and ls) or (Config.DefaultLockStatus or 0)
  })

  local id = Entity(veh).state.pvId
  if not id then
    id = ensureRowIdByPlate(plate)
    if id then setState(veh, id, plate, ls) end
  else
    setState(veh, id, plate, ls)
  end

  if id then spawned[id] = veh end

  applyLockServer(veh, ls)

  dbg('saveOnExit ok', 'id', tostring(id), 'plate', plate, 'model', tostring(model), 'ls', tostring(ls))
  return true
end)

lib.callback.register('pv:getMyVehicles', function(source)
  local identifier = getIdentifier(source)
  if not identifier then return {} end

  local rows = MySQL.query.await([[
    SELECT pv.plate, pv.model, pv.x, pv.y, pv.z, pv.last_moved
    FROM persistent_vehicles pv
    INNER JOIN owned_vehicles ov ON ov.plate = pv.plate
    WHERE ov.owner = ?
    ORDER BY pv.last_moved DESC
  ]], { identifier })

  if not rows then return {} end

  local out = {}
  for i = 1, #rows do
    local r = rows[i]
    out[#out + 1] = {
      plate = r.plate,
      model = r.model,
      coords = { x = r.x, y = r.y, z = r.z },
      lastMoved = r.last_moved or 0
    }
  end
  return out
end)

lib.callback.register('pv:locateByPlate', function(source, plate)
  if not plate or plate == '' then return nil end
  if not isPlateOwnedBy(source, plate) then
    dbg('locate denied not owner', tostring(source), plate)
    return nil
  end

  local vehicles = GetAllVehicles()
  for i = 1, #vehicles do
    local v = vehicles[i]
    if DoesEntityExist(v) and GetVehicleNumberPlateText(v) == plate then
      local c = GetEntityCoords(v)
      return { found = true, coords = { x = c.x, y = c.y, z = c.z } }
    end
  end

  local row = MySQL.single.await('SELECT x,y,z FROM persistent_vehicles WHERE plate = ? LIMIT 1', { plate })
  if not row then return nil end
  return { found = false, coords = { x = row.x, y = row.y, z = row.z } }
end)

local function adoptOrSpawn(row)
  local plate = row.plate
  if not plate or plate == '' then
    dbg('row skip empty plate', tostring(row.id))
    return
  end

  local cutoffDays = (Config.DespawnAfterDays or 0)
  if cutoffDays > 0 then
    local lm = tonumber(row.last_moved or 0) or 0
    if lm > 0 and (nowMs() - lm) >= (cutoffDays * 86400000) then
      dbg('skip spawn old', tostring(row.id), plate, 'last_moved', tostring(lm))
      return
    end
  end

  if not validateCoords(row) then return end

  local lockStatus = tonumber(row.lock_status or (Config.DefaultLockStatus or 0)) or (Config.DefaultLockStatus or 0)
  local props = dec(row.props)
  local extra = dec(row.extra)

  local vehicles = GetAllVehicles()
  for i = 1, #vehicles do
    local v = vehicles[i]
    if DoesEntityExist(v) and GetVehicleNumberPlateText(v) == plate then
      setState(v, row.id, plate, lockStatus)
      spawned[row.id] = v

      applyLockServer(v, lockStatus)

      local netId = NetworkGetNetworkIdFromEntity(v)
      if props then TriggerClientEvent('pv:applyProps', -1, netId, props) end
      if extra and Config.PersistExtra then TriggerClientEvent('pv:applyExtra', -1, netId, extra) end

      dbg('adopted', tostring(row.id), plate)
      return
    end
  end

  local modelRaw = row.model
  local model = parseModel(modelRaw)
  if model == 0 then
    dbg('spawn skip model parse=0', tostring(row.id), plate, 'raw', tostring(modelRaw))
    return
  end

  dbg('spawn attempt', tostring(row.id), plate, 'model_raw', tostring(modelRaw), 'model_u32', tostring(model))

  local retries = Config.SpawnRetries or 8
  local delay = Config.SpawnRetryDelayMs or 750

  local veh = 0
  local t = 0
  ::spawntry::
  veh = createVeh(model, row.x, row.y, row.z, row.heading)
  if veh ~= 0 then goto spawned_ok end

  t += 1
  if t >= retries then
    dbg('spawn failed', tostring(row.id), plate, 'model_u32', tostring(model), 'setter', tostring(CreateVehicleServerSetter ~= nil))
    return
  end

  Wait(delay)
  goto spawntry

  ::spawned_ok::
  SetVehicleNumberPlateText(veh, plate)

  setState(veh, row.id, plate, lockStatus)
  spawned[row.id] = veh

  applyLockServer(veh, lockStatus)

  local netId = NetworkGetNetworkIdFromEntity(veh)
  if props then TriggerClientEvent('pv:applyProps', -1, netId, props) end
  if extra and Config.PersistExtra then TriggerClientEvent('pv:applyExtra', -1, netId, extra) end

  dbg('spawned', tostring(row.id), plate, 'net', tostring(netId))
end

local function despawnRowId(rowId)
  local veh = spawned[rowId]
  if veh and DoesEntityExist(veh) then
    DeleteEntity(veh)
  end
  spawned[rowId] = nil
end

local function saveAll()
  if saving then return end
  saving = true

  local src = anyPlayer()
  if not src then dbg('saveAll no players -> props/extra skipped') end

  for id, veh in pairs(spawned) do
    if DoesEntityExist(veh) then
      local plate = GetVehicleNumberPlateText(veh)
      local model = GetEntityModel(veh)
      local c = GetEntityCoords(veh)
      local h = GetEntityHeading(veh)

      local ls = Config.DefaultLockStatus or 0
      if Config.PersistLockState then
        local st = Entity(veh).state
        ls = (st and st.pvLockStatus) or ls
      end

      local props, extra = nil, nil
      if src then
        if isPlateOwnedBy(src, plate) then
          local netId = NetworkGetNetworkIdFromEntity(veh)
          props = lib.callback.await('pv:getProps', src, netId)
          extra = lib.callback.await('pv:getExtra', src, netId)
        end
      end

      upsertVehicle({
        model = tostring(model),
        plate = plate,
        x = c.x, y = c.y, z = c.z,
        heading = h,
        props = props,
        extra = (Config.PersistExtra and extra) or nil,
        last_moved = nowMs(),
        lock_status = (Config.PersistLockState and ls) or (Config.DefaultLockStatus or 0)
      })
    else
      spawned[id] = nil
    end
  end

  saving = false
end

local function cleanupOld()
  local days = Config.DespawnAfterDays or 0
  if days <= 0 then return end

  local cutoff = nowMs() - (days * 86400000)
  local rows = MySQL.query.await('SELECT id FROM persistent_vehicles WHERE last_moved > 0 AND last_moved < ?', { cutoff })
  if not rows or #rows == 0 then return end

  for i = 1, #rows do
    despawnRowId(rows[i].id)
    MySQL.update.await('DELETE FROM persistent_vehicles WHERE id = ?', { rows[i].id })
  end

  dbg('cleanup removed', tostring(#rows))
end

CreateThread(function()
  dbg('onesync', GetConvar('onesync', 'off'), 'sv_enforceGameBuild', GetConvar('sv_enforceGameBuild', ''))
  Wait(Config.BootDelayMs or 5000)

  local rows = MySQL.query.await('SELECT * FROM persistent_vehicles')
  if not rows or #rows == 0 then
    dbg('boot spawn 0')
    return
  end

  dbg('boot spawn', tostring(#rows))

  for i = 1, #rows do
    adoptOrSpawn(rows[i])
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  dbg('resource stop saveAll')
  saveAll()
end)

CreateThread(function()
  while true do
    Wait(Config.SaveIntervalMs or 60000)
    saveAll()
  end
end)

CreateThread(function()
  while true do
    Wait(Config.CleanupIntervalMs or 3600000)
    cleanupOld()
  end
end)

exports('SetLockStatusByPlate', function(plate, lockStatus)
  if not Config.PersistLockState then return false end
  if not plate or plate == '' then return false end

  local ls = tonumber(lockStatus) or (Config.DefaultLockStatus or 0)
  MySQL.update.await('UPDATE persistent_vehicles SET lock_status = ?, last_moved = ? WHERE plate = ?', { ls, nowMs(), plate })

  local vehicles = GetAllVehicles()
  for i = 1, #vehicles do
    local v = vehicles[i]
    if DoesEntityExist(v) and GetVehicleNumberPlateText(v) == plate then
      local st = Entity(v).state
      if st then st.pvLockStatus = ls end
      applyLockServer(v, ls)
      break
    end
  end

  dbg('SetLockStatusByPlate', plate, tostring(ls))
  return true
end)
