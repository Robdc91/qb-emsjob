# qb-emsjob

A complete, self-contained **EMS / Paramedic job** for **QBCore and Qbox** on FiveM.

## Features

- 🚑 **Multi-hospital coverage** — Central Los Santos, Sandy Shores and Paleto Bay, all configurable
- 🚁 **EMS helicopters** — helipads with `policemav` / `annihilator2` (EMS-only blips, any count of vehicles per pad)
- 🚑 **Per-location garages** — each hospital has its own duty point, garage, and vehicle list
- 🩺 **Revive downed players** — grade-locked, consumes an `ifaks` item, billed to the patient
- 💉 **Heal players** — consumes a `bandage`, per-patient cooldown, billed to the patient
- 🫀 **Last stand / bleed-out** — downed timer (default 300s), hold **E** to self-respawn at the hospital
- 🩺 **NUI duty menu** — status presets (10-8 / 10-7 / 10-23), call-sign field, live on-duty roster
- 🏥 **Nearest-hospital respawn** — bleeding out sends you to the closest configured hospital
- 🩺 **Checkup shows insurance** — EMS see whether the patient is insured during a vitals check
- 🚨 **EMS alerts** — on-duty EMS get a notification + flashing GPS blip when someone goes down
- 🧾 **Contestable billing** — qb-phone invoices patients can pay or contest, or legacy instant charges (`Config.BillingMode`)
- 🪪 **Optional insurance** — insured patients get a discount or full coverage (`player_insurance` table)
- 🌍 **Locales** — English & Spanish (`set qb_locale es`)
- 🔒 **Server-side validation** — job/grade/distance/item checks on every action
- ✅ Works with or without `qb-target` / `ox_target` (set `Config.UseTarget = false` for 3D text)
- 📦 **Runs on QBCore and Qbox** — auto-detects qb-target vs ox_target and ox_inventory at runtime

## Testing

[![CI](https://github.com/Robdc91/qb-emsjob/actions/workflows/ci.yml/badge.svg)](https://github.com/Robdc91/qb-emsjob/actions/workflows/ci.yml)

The server-side validation and billing logic ships with a unit-test harness that runs under **plain Lua 5.4** — no FiveM server required:

```bash
lua tests/run_tests.lua
```

`tests/fivem_stubs.lua` stubs the FiveM environment (event registry with the magic `source`, QBCore player objects, oxmysql backed by an in-memory DB, vector3 arithmetic, ped coords/health natives), then the runner loads the **real** `config.lua`, `locale.lua`, `server/main.lua`, `server/billing.lua` and `server/revive.lua` and exercises them:

- job / duty / grade validation (`IsOnDutyEMS`)
- distance anti-cheat (near/far/self revives, item consumption, malformed-target guards)
- instant vs invoice billing, bank/cash drain behavior, society-credit failure handling
- insurance: expiry, 50% discount, full coverage
- respawn fee billing: charged, skipped when the fee is 0, insurance-covered announcement
- heal cooldown, garage callback, duty toggle, invoice-contest hook
- **EMS alert relay** — on-duty-only fan-out, victim excluded, garbage-coordinate rejection, config kill-switch
- **duty roster sync** — call-sign validation/truncation/uppercase, invalid status rejection, non-EMS rejection, disconnect cleanup
- **useable items** — registration only for existing shared items, event fires only when the player holds the item
- **duty menu controller (client)** — NUI open/close gating, statebag + resource-KVP persistence of status + call-sign (KVPs survive full client restarts; statebag wins after resource restarts), save validation (unknown statuses, illegal call-signs, uppercase/truncation), live roster pushes, cached roster embedded in the open message (no empty-roster flash), duty-state sync and resource-stop cleanup (via the statebag + NUI stubs)
- **garage controller (client)** — garage/helipad zone registration, ambulance & helicopter take-out (spawn, heading/plate/engine/fuel/livery, keys, warp), blocked-spawn refusal, store/delete validation (EMS vs civilian vs on-foot) and zone cleanup (via qb-target + vehicle stubs)
- **revive / laststand controller (client)** — laststand entry (countdown replication, EMS alert, downed blip), fake-time bleed-out drain to full death, revive via `NetworkResurrectLocalPlayer`, hold-E hospital respawn + respawn billing, hold cancel, dynamic target options on nearby downed players, revive/heal progress-bar flows through to server events, and bandage self-heal with cooldown (coroutine threads + controllable clock)

Tests exit non-zero on failure, so they drop straight into CI.

### NUI dev harness

Open `html/dev-harness.html` in a browser to click through the duty menu outside the game. It loads the real `style.css` + `script.js`, drives them with mock `open` / `roster` / `state` messages from a side panel (including the empty-roster flash that 1.3.1 fixed and an on-duty/off-duty switch that re-renders the duty button, self roster chip and on-duty count), and logs the NUI callbacks the UI posts back (`close`, `toggleDuty`, `save`). The harness is not listed in `fxmanifest.lua`'s `files {}`, so FiveM never ships or loads it.

## Dependencies

| Resource | Required |
|---|---|
| [qb-core](https://github.com/qbcore-framework/qb-core) *or* [qbx_core](https://github.com/Qbox-project/qbx_core) (via its QB bridge) | ✅ |
| [oxmysql](https://github.com/overextended/oxmysql) | ✅ |
| [qb-target](https://github.com/qbcore-framework/qb-target) *or* [ox_target](https://github.com/overextended/ox_target) | optional (when `Config.UseTarget = true`); auto-detected |
| [ox_inventory](https://github.com/overextended/ox_inventory) | optional; item lookups prefer it when started (Qbox) |
| [PolyZone](https://github.com/qbcore-framework/PolyZone) | optional qb-target companion (never required directly) |

## Installation

1. Drop the `qb-emsjob` folder into your `resources/[qb]` directory.
2. Run `install/ems_job.sql` on your database (adds the `ambulance` job + grades). For invoice billing + insurance, also run `install/ems_billing.sql`.
3. (Optional insurance) give players insurance rows in `player_insurance`, e.g. via the example in `install/ems_billing.sql`.
4. Make sure you have `bandage` and `ifaks` items in `qb-core/shared/items.lua` (QBCore) or in ox_inventory (Qbox; items added to `qbx_core/shared/items.lua` are auto-synced to ox_inventory).
5. Add to your `server.cfg`:

   ```cfg
   ensure qb-emsjob
   ```

6. Optional: set the language with `set qb_locale en` (or `es`).

> **Invoice mode:** set `Config.BillingMode = 'invoices'` (default) to send qb-phone invoices patients can pay or contest, or `'instant'` for legacy immediate charges. Insurance rules live under `Config.Insurance`.
>
> **Qbox:** no extra setup — with the QB bridge enabled (default), the resource uses qbx_core's `qb-core` compatibility layer, routes interaction points to ox_target, and looks items up in ox_inventory. Job grades in `install/ems_job.sql` use QBCore's string form; Qbox needs numeric grade names, so adjust `qbx_core/shared/jobs.lua` instead of running that SQL.

## Usage

- **Duty:** go to the front-desk point at any hospital (Central, Sandy Shores, Paleto Bay) and use **Open Duty Menu** — pick a status (10-8/10-7/10-23), set your call-sign, then **Save & Apply**. Toggle duty from the same menu.
- **Garage:** grab an ambulance at any hospital bay, or a helicopter from an enabled helipad; park it back and use **Store Ambulance**.
- **Revive/Heal:** walk up to a player (downed for revive, injured for heal) and use the qb-target options.
- **Items:** use `bandage` / `ifaks` from your inventory for a small self-heal.
- **Death:** after bleeding out or holding **E** for 3s, you respawn at the hospital.

## Configuration

Everything lives in `config.lua` — job name, grade requirements, prices, cooldowns, items, blips, last-stand timings, and the `Config.Hospitals` table. Each hospital entry defines its `duty` point, `garage` (interact spot, spawn, vehicle list), optional `helipad` (set `enabled = true/false`), and `respawn`/`beds` coordinates. Add or remove hospital entries to shape coverage; garages and helipads follow automatically.

## Events (for other resources)

```lua
-- Client exports
exports['qb-emsjob']:IsEMS()      -- bool: is the player EMS?
exports['qb-emsjob']:IsOnDuty()   -- bool: is EMS on duty?

-- Force-revive a player from another script (e.g. admin menu)
TriggerClientEvent('qb-emsjob:client:Revived', targetSrc, 0)
```
