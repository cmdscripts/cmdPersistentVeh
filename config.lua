-- config.lua
Config = {}

Config.Debug = true

Config.SaveIntervalMs = 60000
Config.DespawnAfterDays = 7
Config.CleanupIntervalMs = 3600000

Config.PersistLockState = true
Config.DefaultLockStatus = 0

Config.PersistExtra = true

Config.PersistStatebags = true
Config.StatebagKeys = { 'vehicleLock', 'keysOwner', 'myCustomState' }

Config.LegacyFuelEvent = true
Config.LegacyFuelResource = 'LegacyFuel'

Config.BootDelayMs = 5000
Config.SpawnRetries = 8
Config.SpawnRetryDelayMs = 750
Config.SpawnZMin = -100.0
Config.SpawnZMax = 2000.0

Config.ServerSetterType = 'automobile'