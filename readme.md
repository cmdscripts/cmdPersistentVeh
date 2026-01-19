🚗 Persistent Vehicles (FiveM)

A modern, server-side vehicle persistence system for FiveM.
Vehicles remain exactly where players leave them — even after server or resource restarts.

Built for performance, modders, and clean integrations.

✨ Features

Vehicles are saved automatically when a player exits

Vehicles persist across server & resource restarts

Adopt-or-Spawn logic (no duplicates on script restart)

Fully server-side database logic

Uses Statebags (pvId, pvPlate)

Cleanup system (despawn vehicles not moved for X days)

Configurable debug output

Rich exports for integration with other scripts

Works with ox_lib and oxmysql

📦 Requirements

FiveM (latest recommended)

ox_lib

oxmysql

🗄️ Database Setup
CREATE TABLE IF NOT EXISTS persistent_vehicles (
  id INT NOT NULL AUTO_INCREMENT,
  model VARCHAR(64) NOT NULL,
  plate VARCHAR(12) NOT NULL,
  x DOUBLE NOT NULL,
  y DOUBLE NOT NULL,
  z DOUBLE NOT NULL,
  heading DOUBLE NOT NULL,
  props LONGTEXT,
  last_moved BIGINT NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_plate (plate)
);

⚙️ Configuration (config.lua)
Config = {}

Config.Debug = true                 -- Enable debug prints
Config.SaveIntervalMs = 60000       -- Periodic save interval
Config.DespawnAfterDays = 7         -- Remove vehicles not moved for X days
Config.CleanupIntervalMs = 3600000  -- Cleanup check interval

🔁 How It Works

A player enters a vehicle as driver

When the player exits the vehicle, it is saved:

position

heading

plate

vehicle properties

last moved timestamp

On restart:

existing vehicles are adopted by plate

missing vehicles are spawned from database

Vehicles not moved for X days are automatically despawned & deleted

🧠 Statebags

Each persistent vehicle gets:

Entity(vehicle).state.pvId     -- Database ID
Entity(vehicle).state.pvPlate  -- Vehicle plate


These are synced and usable in all scripts.

🔌 Exports (Server-side)
Check if entity is persistent
exports.perstistent:IsPersistent(entity)

Get persistent ID from entity
exports.perstistent:GetPersistentId(entity)

Get vehicle by plate
exports.perstistent:GetByPlate('ABC123')

Save a vehicle manually
exports.perstistent:SaveEntity(entity, props)

Insert / update a vehicle manually
exports.perstistent:Upsert({
  model = model,
  plate = 'ABC123',
  x = x, y = y, z = z,
  heading = heading,
  props = props
})

Spawn a vehicle by plate
exports.perstistent:SpawnByPlate('ABC123', true)

Remove vehicle by plate
exports.perstistent:RemoveByPlate('ABC123')

Remove vehicle by database ID
exports.perstistent:RemoveById(12)

List all persistent vehicles
exports.perstistent:List()

Force save all vehicles
exports.perstistent:ForceSaveAll()

Force cleanup (despawn old vehicles)
exports.perstistent:ForceCleanup()

🧹 Cleanup System

Vehicles are removed if:

last_moved exceeds Config.DespawnAfterDays

Vehicle is despawned and deleted from database

Runs automatically at Config.CleanupIntervalMs.

🧪 Debugging

Enable debug prints:

Config.Debug = true


All logs are prefixed with:

[pv]

📌 Notes

No commands required

No client-side database logic

Safe for large servers

Designed for job vehicles, owned vehicles, admin spawns, etc.

🚗 Persistente Fahrzeuge (Deutsch)

Ein modernes, serverseitiges Vehicle-Persistenz-System für FiveM.
Fahrzeuge bleiben genau dort stehen, wo Spieler sie verlassen – auch nach Server- oder Script-Restarts.

Optimiert, sauber und perfekt für Modder.

✨ Features

Fahrzeuge werden automatisch beim Aussteigen gespeichert

Fahrzeuge bleiben nach Server- & Resource-Restart

Adopt-or-Spawn (keine Duplikate)

Komplette Server-Side Datenbanklogik

Nutzung von Statebags

Cleanup-System (alte Fahrzeuge werden entfernt)

Debug-Modus

Umfangreiche Exports

Unterstützt ox_lib & oxmysql

📦 Voraussetzungen

FiveM

ox_lib

oxmysql

🗄️ Datenbank

Siehe SQL oben (identisch).

⚙️ Konfiguration
Config.Debug = true                 -- Debug-Ausgaben
Config.SaveIntervalMs = 60000       -- Regelmäßiges Speichern
Config.DespawnAfterDays = 7         -- Fahrzeuge löschen nach X Tagen
Config.CleanupIntervalMs = 3600000  -- Cleanup-Intervall

🔁 Funktionsweise

Spieler fährt ein Fahrzeug

Beim Aussteigen wird es gespeichert

Beim Restart:

vorhandene Fahrzeuge werden übernommen

fehlende Fahrzeuge werden gespawnt

Fahrzeuge ohne Bewegung über X Tage werden automatisch entfernt

🧠 Statebags
pvId     -- Datenbank-ID
pvPlate  -- Kennzeichen

🔌 Exports (Server)

Alle Exports sind serverseitig und sofort nutzbar:

exports.perstistent:IsPersistent(entity)
exports.perstistent:GetPersistentId(entity)
exports.perstistent:GetByPlate('ABC123')
exports.perstistent:SaveEntity(entity, props)
exports.perstistent:SpawnByPlate('ABC123', true)
exports.perstistent:RemoveByPlate('ABC123')
exports.perstistent:List()
exports.perstistent:ForceSaveAll()
exports.perstistent:ForceCleanup()

🧹 Cleanup

Fahrzeuge ohne Bewegung → werden despawnt

DB bleibt sauber

Vollautomatisch

🧪 Debug
Config.Debug = true


Logs erscheinen als:

[pv]

📌 Hinweise

Keine Commands nötig

Kein Client-DB-Zugriff

Performance-freundlich

Ideal für Jobs, Besitzfahrzeuge, Admin-Spawns