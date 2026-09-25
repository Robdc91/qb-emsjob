# Changelog

Notable changes to qb-emsjob. Versions follow semantic versioning.

## [1.4.7] - 2026-09-25

### Changed
- The duty menu card itself now uses a vertical dark-green -> light-green
  gradient (`#0b3d24` through `#26a65b` to `#a3e4c1`). Header, section titles,
  labels and separators switched to light-on-green styling; roster rows,
  inputs and buttons stay light cards so text contrast holds everywhere.

## [1.4.6] - 2026-09-25

### Changed
- Duty menu backdrop is a two-stop dark-green -> lighter-green gradient
  (`#0b3d24` to `#4ade80`) replacing the dark-green/green/white sweep; the
  light container and green accents are unchanged.

## [1.4.5] - 2026-09-25

### Changed
- Duty menu backdrop is now an asymmetric dark-green -> green -> white sweep
  (deep green on the left, brightening to white on the right) instead of the
  symmetric green-white-green; container and accents unchanged.

## [1.4.4] - 2026-09-25

### Changed
- Duty menu rethemed from dark purple to a light green-white-green gradient:
  green glowing edges on a white container, light panels, and dark-green
  accents; status hues keep their meaning on the light background (green =
  10-8, amber = 10-7, gray = 10-23, red = off duty). Dev harness chrome and
  toasts follow the same palette.

## [1.4.3] - 2026-09-25

### Changed
- 10-8 (available) status is green everywhere: the roster status chip and the
  selected 10-8 button use the same green as ox_lib success notifications
  (`--green` / `--green-bright`), so at-a-glance status reads green = available,
  amber = busy, red = out of service, gray = out of service chip in the roster,
  and the dim red chip means off duty.
- Default EMS salary ladder in both install recipes lowered to 50 / 75 / 100 /
  150 per paycheck (recruit, paramedic, senior, chief); re-running
  `install/ems_job.sql` updates existing rows via ON DUPLICATE KEY.

## [1.4.2] - 2026-09-25

### Changed
- New shared `bridge.lua` centralizes optional-resource detection
  (`Bridge.IsStarted`) and ox_lib resolution (`Bridge.GetOxLib`, cached,
  global-or-require fallback) for both VMs; target_bridge, items.lua,
  billing.lua and the garage picker all use it instead of repeating
  GetResourceState checks.

## [1.4.1] - 2026-09-25

### Fixed
- Qbox: invoices now actually reach qbx_phone - it has no
  `qb-phone:server:sendInvoice` event (the event silently did nothing), so
  the invoice row is inserted directly into `phone_invoices` using the same
  schema qbx_phone's /bill writes and its invoice app reads. Classic qb-phone
  keeps using the event with no duplicate row.

### Changed
- Society credits on instant billing pick the running money system at
  runtime: qbx_management -> Renewed-Banking -> legacy qb-management event.
- Garage vehicle picker uses ox_lib's inputDialog when qb-input is absent
  (Qbox), keeping qb-input preferred on QBCore. The ox_lib module is resolved
  via require when the `lib` global is absent, and results are read
  positionally as ox_lib returns them.

## [1.4.0] - 2026-09-25

### Added
- Qbox (qbx_core) support alongside classic QBCore: a client target bridge
  routes interaction points to qb-target or ox_target (whichever is started,
  qb-target preferred), item existence checks prefer ox_inventory when it is
  running, and the cosmetic `inventory:client:ItemBox` call is guarded for
  stacks where QBCore.Shared.Items does not hold the item. qb-target/PolyZone
  are no longer hard manifest dependencies. Qbox job setup is documented in
  `install/qbox_jobs.lua` (qbx_core defines jobs in Lua, not SQL).

## [1.3.4] - 2026-09-25

### Changed
- Duty menu rethemed to a purple accent palette with a purple-black-purple
  gradient backdrop, gradient container/header/footer, and purple glow
  highlights; status chips keep their distinct hues (purple/amber/gray/red).

## [1.3.3] - 2026-09-25

### Changed
- Duty menu NUI polish: roster shows more rows before scrolling, hover and
  pressed states on buttons/roster rows, call-sign focus ring, and responsive
  rules so the menu adapts to narrow or short windowed resolutions.

## [1.3.2] - 2026-09-25

### Added
- Duty menu status and call-sign now persist via client resource KVPs, so
  they survive a full client restart (statebags only survive resource
  restarts; the statebag still wins when both exist). Includes a browser
  dev harness (`html/dev-harness.html`) for the duty menu NUI with an
  on-duty/off-duty scenario switch.

## [1.3.1] - 2026-09-25

### Fixed
- Duty menu no longer flashes "No colleagues on duty." when opened: the client
  caches the latest roster (from `qb-emsjob:client:RosterUpdated` broadcasts and
  `GetDutyRoster` callback results, even while the menu is closed) and embeds it
  in the `open` NUI message. The authoritative roster refresh still follows.

## [1.3.0] - 2026-09-25

### Added
- Initial release: revive/heal with laststand bleed-out, hospital respawn with
  billing, ambulance garage + helicopter, NUI duty menu (status presets,
  call-sign, live roster), qb-phone invoice billing with insurance, EMS alert
  relay, useable first-aid items, and a Lua unit-test suite run in CI.
