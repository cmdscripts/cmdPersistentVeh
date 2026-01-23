local function dbg(...)
  if not Config or not Config.Debug then return end
  print(('[pv] %s'):format(table.concat({ ... }, ' ')))
end

local function getStatebags(veh)
  if not Config.PersistStatebags or not Config.StatebagKeys then return nil end
  local out = {}
  local st = Entity(veh).state
  for i = 1, #Config.StatebagKeys do
    local k = Config.StatebagKeys[i]
    local v = st[k]
    if v ~= nil then out[k] = v end
  end
  return next(out) and out or nil
end

local function applyStatebags(veh, bags)
  if not bags then return end
  local st = Entity(veh).state
  for k, v in pairs(bags) do
    st:set(k, v, true)
  end
end

local function getExtra(veh)
  if not Config.PersistExtra then return nil end
  local extra = {}

  extra.entityHealth = GetEntityHealth(veh)
  extra.bodyHealth = GetVehicleBodyHealth(veh)
  extra.engineHealth = GetVehicleEngineHealth(veh)
  extra.tankHealth = GetVehiclePetrolTankHealth(veh)

  extra.dirtLevel = GetVehicleDirtLevel(veh)
  extra.fuelLevel = GetVehicleFuelLevel(veh)

  extra.lockStatus = GetVehicleDoorLockStatus(veh)
  extra.engineOn = GetIsVehicleEngineRunning(veh)

  if GetVehicleClass(veh) == 14 then
    extra.boatAnchor = IsBoatAnchoredAndFrozen(veh)
  end

  extra.landingGear = GetLandingGearState(veh)

  if IsThisModelAPlane(GetEntityModel(veh)) or IsThisModelAHeli(GetEntityModel(veh)) then
    extra.vtol = GetVehicleFlightNozzlePosition(veh)
  end

  extra.roofState = GetConvertibleRoofState(veh)

  local tyres = {}
  for i = 0, 7 do
    tyres[i] = IsVehicleTyreBurst(veh, i, false)
  end
  extra.tyres = tyres

  local doors = {}
  for i = 0, 7 do
    doors[i] = IsVehicleDoorDamaged(veh, i)
  end
  extra.doors = doors

  local windows = {}
  for i = 0, 7 do
    windows[i] = not IsVehicleWindowIntact(veh, i)
  end
  extra.windows = windows

  extra.statebags = getStatebags(veh)

  return extra
end

local function applyExtra(veh, extra)
  if not extra then return end

  if type(extra.lockStatus) == 'number' then
    SetVehicleDoorsLocked(veh, extra.lockStatus)
  end

  if type(extra.fuelLevel) == 'number' then
    SetVehicleFuelLevel(veh, extra.fuelLevel + 0.0)
    if Config.LegacyFuelEvent and Config.LegacyFuelResource and GetResourceState(Config.LegacyFuelResource) == 'started' then
      TriggerEvent('LegacyFuel:SetFuel', veh, extra.fuelLevel + 0.0)
    end
  end

  if type(extra.dirtLevel) == 'number' then
    SetVehicleDirtLevel(veh, extra.dirtLevel + 0.0)
  end

  if type(extra.entityHealth) == 'number' then
    SetEntityHealth(veh, extra.entityHealth)
  end
  if type(extra.bodyHealth) == 'number' then
    SetVehicleBodyHealth(veh, extra.bodyHealth + 0.0)
  end
  if type(extra.engineHealth) == 'number' then
    SetVehicleEngineHealth(veh, extra.engineHealth + 0.0)
  end
  if type(extra.tankHealth) == 'number' then
    SetVehiclePetrolTankHealth(veh, extra.tankHealth + 0.0)
  end

  if type(extra.engineOn) == 'boolean' then
    SetVehicleEngineOn(veh, extra.engineOn, true, true)
  end

  if type(extra.landingGear) == 'number' then
    SetVehicleLandingGear(veh, extra.landingGear)
  end

  if type(extra.vtol) == 'number' then
    SetVehicleFlightNozzlePosition(veh, extra.vtol + 0.0)
  end

  if type(extra.boatAnchor) == 'boolean' then
    SetBoatAnchor(veh, extra.boatAnchor)
    SetBoatFrozenWhenAnchored(veh, extra.boatAnchor)
  end

  if type(extra.roofState) == 'number' then
    if extra.roofState == 0 then
      RaiseConvertibleRoof(veh, false)
    elseif extra.roofState == 2 then
      LowerConvertibleRoof(veh, false)
    end
  end

  if type(extra.tyres) == 'table' then
    for i = 0, 7 do
      if extra.tyres[i] == true then
        SetVehicleTyreBurst(veh, i, true, 1000.0)
      end
    end
  end

  if type(extra.doors) == 'table' then
    for i = 0, 7 do
      if extra.doors[i] == true then
        SetVehicleDoorBroken(veh, i, true)
      end
    end
  end

  if type(extra.windows) == 'table' then
    for i = 0, 7 do
      if extra.windows[i] == true then
        SmashVehicleWindow(veh, i)
      end
    end
  end

  applyStatebags(veh, extra.statebags)
end

lib.callback.register('pv:getProps', function(netId)
  local veh = NetToVeh(netId)
  if veh == 0 or not DoesEntityExist(veh) then return nil end
  return lib.getVehicleProperties(veh)
end)

lib.callback.register('pv:getExtra', function(netId)
  local veh = NetToVeh(netId)
  if veh == 0 or not DoesEntityExist(veh) then return nil end
  return getExtra(veh)
end)

RegisterNetEvent('pv:applyProps', function(netId, props)
  if not props then return end

  local tries = 0
  ::continue::
  local veh = NetToVeh(netId)
  if veh ~= 0 and DoesEntityExist(veh) then
    lib.setVehicleProperties(veh, props)
    dbg('applyProps', tostring(netId))
    return
  end
  tries += 1
  if tries >= 50 then return end
  Wait(100)
  goto continue
end)

RegisterNetEvent('pv:applyExtra', function(netId, extra)
  if not extra then return end

  local tries = 0
  ::continue::
  local veh = NetToVeh(netId)
  if veh ~= 0 and DoesEntityExist(veh) then
    applyExtra(veh, extra)
    dbg('applyExtra', tostring(netId))
    return
  end
  tries += 1
  if tries >= 50 then return end
  Wait(100)
  goto continue
end)

local function ensureNetId(veh)
  if veh == 0 or not DoesEntityExist(veh) then return 0 end

  local netId = VehToNet(veh)
  if netId ~= 0 then return netId end

  local tries = 0
  ::continue::

  if not DoesEntityExist(veh) then return 0 end

  if not NetworkHasControlOfEntity(veh) then
    NetworkRequestControlOfEntity(veh)
  end

  NetworkRegisterEntityAsNetworked(veh)

  netId = VehToNet(veh)
  if netId ~= 0 then return netId end

  tries += 1
  if tries >= 50 then return 0 end
  Wait(25)
  goto continue
end

local saving = {}
local lastDriverVeh = 0

local function saveVehicle(veh)
  if veh == 0 or not DoesEntityExist(veh) then return end

  local netId = ensureNetId(veh)
  if netId == 0 then return end
  if saving[netId] then return end
  saving[netId] = true

  CreateThread(function()
    local props = lib.getVehicleProperties(veh)
    local coords = GetEntityCoords(veh)
    local heading = GetEntityHeading(veh)
    local extra = getExtra(veh)

    dbg('exit save', tostring(netId))
    lib.callback.await('pv:saveOnExit', false, netId, props, coords, heading, extra)

    saving[netId] = nil
  end)
end

lib.onCache('seat', function(value)
  if value == -1 and cache.vehicle and cache.vehicle ~= 0 then
    lastDriverVeh = cache.vehicle
  end
end)

lib.onCache('vehicle', function(value, oldValue)
  if value then return end
  if not oldValue or oldValue == 0 then return end
  if oldValue ~= lastDriverVeh then return end

  lastDriverVeh = 0
  saveVehicle(oldValue)
end)

local function setWaypoint(coords)
  SetNewWaypoint(coords.x + 0.0, coords.y + 0.0)
end

local function openTrackMenu()
  local list = lib.callback.await('pv:getMyVehicles', false)
  if not list or #list == 0 then
    lib.notify({ title = 'Fahrzeuge', description = 'Keine Fahrzeuge gefunden', type = 'error' })
    return
  end

  local opts = {}

  for i = 1, #list do
    local v = list[i]
    opts[#opts + 1] = {
      title = v.plate,
      description = ('Model: %s'):format(tostring(v.model)),
      icon = 'car',
      onSelect = function()
        local res = lib.callback.await('pv:locateByPlate', false, v.plate)
        if not res or not res.coords then
          lib.notify({ title = 'Tracking', description = 'Position nicht gefunden', type = 'error' })
          return
        end
        setWaypoint(res.coords)
        lib.notify({ title = 'Tracking', description = ('Waypoint gesetzt: %s'):format(v.plate), type = 'success' })
      end
    }
  end

  opts[#opts + 1] = {
    title = 'Waypoint entfernen',
    icon = 'ban',
    onSelect = function()
      SetWaypointOff()
      lib.notify({ title = 'Tracking', description = 'Waypoint entfernt', type = 'inform' })
    end
  }

  lib.registerContext({
    id = 'pv_track_menu',
    title = 'Meine Fahrzeuge',
    options = opts
  })

  lib.showContext('pv_track_menu')
end

RegisterCommand('pvtrack', function()
  openTrackMenu()
end, false)
