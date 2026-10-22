# Changelog

All notable changes to petzy-ios. Versions are ordered newest first.

<!--
  The format is Keep a Changelog. Each entry says what changed and why it
  was worth changing.

  The traps do not go here. They go in AGENTS.md, because the changelog is
  read by the people who use the software and the traps are read by whoever
  works on the code next.
-->

## 1.0.1 — 2026-10-22

Nothing changes in how the app works. This release is the codebase catching up
with itself: dead code removed, and the quality of the code measured from now
on instead of judged by eye.

### Removed

- Fourteen declarations nothing reached any more, found by Periphery rather
  than by reading: an unused clinic body, a duplicated `isSignedIn`, two
  offline getters, an unused initialiser of the record form and of the visit
  note, a duplicated weight line, an unused readiness check, two route
  properties, a leftover notification counter and a pet birthday formatter.

### Changed

- `make metrics` now reports the cyclomatic complexity of every function and
  closure (315 of them: mean 1.93, median 1, maximum 7), the longest functions,
  types and files, and the parameter counts. `make analyze` looks for unused
  imports and declarations, and `make dead-code` runs Periphery.
- `.swiftlint.yml` spells out the thresholds instead of relying on the
  defaults: complexity 8 warns and 12 fails, a function of 50 lines warns, a
  file of 400 warns.

## 1.0.0 — 2026-10-22

The first release. A native client for the Petzy pet health diary, on the same
API the web app uses: the first version that covers the web's main paths
without a browser.

### Added

- **A diary that reads like a history.** Records are grouped by day, the next
  page loads by itself when the list ends, the type filter narrows the list,
  and a record opens for editing and deletes with a swipe. The «+» button
  offers the pet's own set of types, in the order the owner put them.
- **A medical card for a visit to the vet.** The pet's profile, vaccinations,
  treatments and procedures, visits, documents and weight, the readiness to be
  seen, and the card as a PDF or as a link for the doctor.
- **Medications.** The schedule of a course, the stock left, marking a dose,
  and the last intakes, where a dose can be moved to another time or cancelled
  with the stock coming back.
- **Reminders about doses**, as local notifications: they work without a
  network, and the settings say when the next one is.
- **Documents** in any format the web accepts, uploaded from the file picker or
  shot with the camera, a scan through the server, and every file opens on tap.
- **Sharing a pet.** Inviting a person, the rights of the one invited, taking
  the access back, and the page of the person on the other side.
- **Export of the records** as a table, default values for new records, custom
  record types, and access tokens for assistants.
- **Offline.** The last copy seen is readable without a network, and a write
  made without one waits in a queue that sends it when the network is back.
- The version of the app in the settings: the number people are asked for when
  they ask for help.
- Signing in, the onboarding, the link from an e-mail, and the privacy policy.

### Changed

- The separate history screen is gone: the feed is the history now, as in the
  web app, and the records are exported from the settings.
