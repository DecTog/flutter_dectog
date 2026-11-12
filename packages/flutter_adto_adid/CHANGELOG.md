# Changelog

## [1.0.0] - 2026-11-12

First release, for flutter_adto 1.0.0. `AdtoAdId.provider` for
`AdtoConfig.advertisingIdProvider` (the IDFA once App Tracking
Transparency is authorized, the GAID unless the user opted out),
`AdtoAdId.trackingStatus()` and `AdtoAdId.requestTracking()` for the ATT
prompt, and a privacy manifest declaring the IDFA.
