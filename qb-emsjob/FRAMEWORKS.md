# Framework integration reference

qb-emsjob runs on **classic QBCore** and **Qbox (qbx_core)** from one codebase.
All differences are resolved at runtime by `bridge.lua` (loaded into both VMs
via `shared_scripts`); there is no config switch and no fork.

## Detection order

| Integration point | Priority | Classic QBCore | Qbox | Neither |
|---|---|---|---|---|
| Core object | fixed | `qb-core` resource | qbx_core QB bridge answers `exports['qb-core']:GetCoreObject()` | n/a (hard dep) |
| Interaction targets | 1. qb-target 2. ox_target | qb-target (+PolyZone) | ox_target | warn once; interaction points disabled (`Config.UseTarget = false` = 3D text always works) |
| Item existence | 1. ox_inventory 2. QBCore.Shared.Items | shared items | ox_inventory | falls back to shared items |
| Invoices | 1. qb-phone event 2. direct DB row | `qb-phone:server:sendInvoice` event | INSERT into `phone_invoices` (qbx_phone has no such event) | direct DB row |
| Society credit (instant billing) | 1. qbx_management 2. Renewed-Banking 3. legacy event | `qb-management:server:addSocietyMoney` event | `qbx_management:AddMoney` (or Renewed-Banking) | credit skipped |
| Garage vehicle picker | 1. qb-input 2. ox_lib dialog 3. first vehicle | qb-input `ShowInput` | `lib.inputDialog` via `Bridge.GetOxLib()` | first configured vehicle |

Detection is cached per session (target backend) or per call (inventory,
phone, money); `GetResourceState` is the source of truth in every case.

## Shared surface (identical on both frameworks)

Qbox's QB bridge implements all of these; no bridging needed.

| API / event | Used for |
|---|---|
| `QBCore.Functions.GetPlayer / GetQBPlayers / Notify / TriggerCallback / CreateUseableItem / SpawnVehicle / GetPlate / SetJobDuty` | core player, notify, callback, garage |
| `QBCore:Client:OnPlayerLoaded / OnJobUpdate / SetDuty / OnPlayerUnload` | duty + job state sync |
| `QBCore:Notify` (client event) | server-initiated notifications |
| `qb-emsjob:server:ToggleDuty / SetDutyStatus / RevivePlayer / HealPlayer / CheckupPlayer / RespawnBilled / InvoiceContested` | resource events (unchanged) |
| `qb-emsjob:client:RosterUpdated / DownedAlert / UseBandage / UseIfaks` | resource events (unchanged) |
| `vehiclekeys:client:SetOwner` | giving keys after garage spawn |

## Qbox-specific notes

- **Jobs are Lua, not SQL.** Do not run `install/ems_job.sql`; see
  `install/qbox_jobs.lua`. The stock qbx_core `ambulance` job works as-is
  (grade *levels* are all qb-emsjob checks).
- **qb-phone invoices**: qbx_phone implements neither `sendInvoice` nor a
  reason column; the direct row uses qbx_phone's own `/bill` schema
  (`citizenid, amount, society, sender, sendercitizenid`), which its invoice
  app and `PayInvoice` flow read. `PayInvoice` credits `qbx_management`.
- **ox_lib** is not imported by this resource; `Bridge.GetOxLib()` resolves
  the module lazily (global first, then `require('@ox_lib/init.lua')`) so the
  garage dialog works without adding an ox_lib include to the manifest.
- **Manifest deps** are only `qb-core` (satisfied by the QB bridge) and
  `oxmysql`. qb-target/PolyZone/qb-input/qb-phone/management are all optional.

## Classic-QBCore notes

- Requires `qb-target` (with PolyZone) for target interaction; otherwise set
  `Config.UseTarget = false` for 3D text.
- Requires `qb-phone` for invoice mode (event path). Without any phone, the
  direct-row fallback needs the `phone_invoices` table to exist — create it
  via `install/ems_billing.sql` (kept for manual installs).
- Society credit uses the legacy event; ensure a management resource listens
  on it (qb-management does).

## Where the bridging lives

| File | Bridged concern |
|---|---|
| `bridge.lua` (shared) | `Bridge.IsStarted`, cached `Bridge.GetOxLib`, `Bridge.ResetCaches` |
| `client/target_bridge.lua` | qb-target ↔ ox_target zones/entities, option mapping (`job`→`groups`, `action`→`onSelect`) |
| `server/items.lua` | inventory layer choice |
| `server/billing.lua` | invoice route + society credit route |
| `client/garage.lua` | input dialog choice |
| `tests/fivem_stubs.lua` | `stub.started` registry powering all detection in tests |
