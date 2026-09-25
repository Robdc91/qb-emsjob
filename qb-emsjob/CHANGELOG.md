# Changelog

Notable changes to qb-emsjob. Versions follow semantic versioning.

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
