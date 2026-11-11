# Changelog

## [1.0.0] - 2026-10-14

First release, for flutter_dectog 1.0.0. `DectogAdId.provider` for
`DectogConfig.advertisingIdProvider` (the IDFA once App Tracking
Transparency is authorized, the GAID unless the user opted out),
`DectogAdId.trackingStatus()` and `DectogAdId.requestTracking()` for the ATT
prompt, and a privacy manifest declaring the IDFA.
