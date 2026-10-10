# Shared Mac source

`Models.swift` contains the platform-neutral station model and search helpers.
Personal station JSON decoding, URL de-duplication, encoding and HTTPS import
live in `PersonalCatalog.swift`; local storage and the one-time preferences
backup live in `PersonalStationRepository.swift`.

The app target must include these Swift files, but must not include a bundled
station directory or historic station-translation JSON. Personal station data
is stored under the user's Application Support `Wavelet/PersonalStations.json`.
Tests use synthetic JSON fixtures and temporary storage directories.

The Mac app does not include iOS-only motivational quotes. Keep font assets and
their license files in the app target.
