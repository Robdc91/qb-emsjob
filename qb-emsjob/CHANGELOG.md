# Changelog

Notable changes to qb-emsjob. Versions follow semantic versioning.

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
