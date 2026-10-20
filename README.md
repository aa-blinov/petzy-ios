# Petzy for iOS

Petzy for iOS is a native SwiftUI client for the Petzy pet health diary: a
feed of daily records, medication courses, a medical card and documents for
every pet of the account. It talks to the same backend as the Petzy web app,
so a login, a pet and its records are the same on both. The interface is
Russian.

![The Petzy app icon](docs/app-icon.svg)

[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![CI](https://github.com/aa-blinov/petzy-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/aa-blinov/petzy-ios/actions/workflows/ci.yml)

---

## Quick start

```bash
make setup     # install xcodegen and swiftlint, generate Petzy.xcodeproj
make backend   # raise the local petzy stack in Docker, the API on :5002
make run       # build, install and launch on the simulator
```

Xcode and Homebrew are needed. XcodeGen builds `Petzy.xcodeproj` from
`project.yml`, and the project file is not in git, so `make setup` comes
first and `make generate` after every change to `project.yml`.

The local stack answers on `http://localhost:5002`. Its demo account is
`demo`, with the password `petzy-demo-2026`.

| Where | How | What it takes |
| --- | --- | --- |
| Simulator | `make run` | Xcode, a simulator device, the local stack |
| Another server | `xcrun simctl launch booted ru.petzy.app -petzyBaseURL https://petzy.duckdns.org` | the address of the API |
| A physical phone | not wired up | a signing identity, which the repository does not have |

The simulator reaches the Mac on `localhost`. A phone on the same network
cannot: it needs the address of the Mac on the LAN and an exception in
`Info.plist` for that host. Neither is in place, because without a signature
there is nothing to build onto a device.

`make run SIM="iPhone Duo"` picks another simulator. The default is
`iPhone 18 Pro`.

## What it does

- **A feed of daily records.** Food and water, excretion, health, care,
  activity and the conditions the pet lives in. The catalogue of types comes
  from the server, the form is drawn from the description of the type, and
  the required fields, the ranges and the numbers are checked before the
  request goes out.
- **Editing and deleting.** A tap on a record opens it with its values, a
  swipe gives "Change" and "Delete", and the delete asks for confirmation.
  The full swipe is off: a record on the server does not come back.
- **History and a chart.** Everything for all time, unlike the feed. The type
  filter is sent to the server, and only the types the pet has records of are
  listed. A type with a value draws a line, a counted type draws bars, and
  under the chart it says in words what the chart shows.
- **Export.** The records of a pet as a table, in CSV, TSV, HTML or Markdown,
  handed to the system share sheet.
- **Medications.** Courses with the schedule in words, the dose, the
  remaining amount and the number of days it lasts, the last dose, and the
  "Archive" and "Starts" marks. "Gave now" marks a dose, and the sheet takes
  another time, another dose or "Skip the dose". The tab counts the overdue
  doses.
- **The medical card.** The card of the selected pet: breed, age, last weight,
  four tiles with the number of records and the overdue ones, a "For the
  visit" block and a "For the doctor" PDF. The sections are vaccinations,
  parasite treatment, doctor's visits and procedures. The profile for the
  doctor and the notes for the next appointment are edited there, and a share
  link opens the card to a vet.
- **Documents.** The files of the pet in six categories: vaccinations, tests,
  results, images, insurance and other. Each has an expiry date, and the tab
  counts the ones whose date has passed.
- **Several pets, one account.** The card of a pet holds the photo, the name,
  the species, the breed, the birth date, the sex, the neutering and the
  health notes. The same form adds a pet and changes one, and the deletion
  asks first what goes away with it.
- **The account.** The login, the name, the address for the password, the
  change of the address, the change of the password, and the deletion of the
  account with a preview of what disappears.
- **Assistant access.** Personal tokens for a person or a script that works
  for you without the password. The secret is shown once.
- **Your own record types.** A type with its own name and its own fields. The
  server assigns the key, the icon and the colour are yours to choose. Only
  an empty type can be deleted, and the app says so before the tap.
- **Working without a network.** What the phone has already seen is stored on
  the device, and the sections say so: "No connection, showing saved data". A
  record made in the basement waits in one queue and goes out by itself when
  the network is back.
- **Administration.** For the administrator only: the list of people, create,
  change, disable and reset the password.

## How it works

```
PetzyApp -> RootView -> AppShellView (five tabs)
                            |
                            +-> AppModel: the session, the pets, the feed, the history
                            +-> one model per section and per pet
                            +-> APIClient -> HTTP -> the Petzy API
                            +-> OfflineState -> LocalStore -> offline.json
```

`Petzy/App/` holds the entry point, the configuration, the app model and the
root view. The app model owns the session, the list of pets and the selected
pet; the shell builds one model per section and per pet, so a section always
works with the pet it was made for.

`Petzy/API/` holds the network. `HTTP` builds the request and reads the
error text the server sent. `APIClient` adds the token, refreshes it after a
401 and repeats the request once; the other files are the routes and the
models.

`Petzy/Auth/` holds the session: `AuthSession` signs in, refreshes and signs
out, and the tokens live in the Keychain.

Every screen has its own directory under `Petzy/`, named after the screen,
with a model and a view. The model talks to `APIClient` and never to the
network directly.

`Petzy/App/Offline/` holds the copy and the queue. A write made without a
network is kept as the request itself: the path, the method and the body. The
record carries the name the device gave it, and the server treats a repeated
request with that name as the same record, so a queue that sends twice does
not write twice.

Two decisions are worth naming. A request never carries an `Origin` header,
and that is how the backend tells a native client from a browser and hands
the tokens out in the body rather than in an httpOnly cookie. The copy of a
section is stored as the bytes the server sent and is parsed by the same code
that parses the network answer, because a second parser would drift at the
first change of the contract.

The feed is read with a cursor, 100 records to a page, and the next page is
asked for when the person reaches the end of the list. Deleted records are
not asked for: the server does not return them, and the tombstones would
take the place of live records in the page.

## Configuration

The address of the API and the knobs of the build:

| Knob | Where | Default |
| --- | --- | --- |
| `PETZY_API_BASE_URL` | `project.yml`, baked into `Info.plist` | `http://localhost:5002` |
| `-petzyBaseURL <url>` | launch argument, wins over the value above | none |
| `SIM` | `Makefile` | `iPhone 18 Pro` |
| `BUNDLE_ID` | `Makefile` | `ru.petzy.app` |
| `PETZY_DIR` | `Makefile` | `~/Documents/petzy` |
| `DERIVED` | `Makefile` | `.build` |
| Request timeout | `Petzy/App/AppConfig.swift` | 15 s |

The launch arguments and the environment of a test run:

| Knob | Effect |
| --- | --- |
| `-uiTestSignedOut` | Wipes the tokens before the restore, so a run starts on the login screen. |
| `-uiTestOnboarding` | Shows the first-run screen even when the flag is already set. |
| `PETZY_TEST_LOGIN`, `PETZY_TEST_PASSWORD` | Fill the login form, because the software keyboard of the simulator cannot type into a secure field. |

The session itself is short-lived: the access token lives 15 minutes, the
refresh token 7 days. The backend lets five sign-in attempts a minute from one
address, and ten wrong ones lock that login for fifteen minutes, the right
password included.

## Development

```bash
make setup         # brew install xcodegen swiftlint, then generate the project
make generate      # rebuild Petzy.xcodeproj from project.yml
make build         # build for the simulator
make test          # unit tests, fast, no server
make test-ui       # UI tests against the live local stack, needs make backend
make run           # build, install and launch on the simulator
make shot          # screenshot of the current screen
make lint-strict   # swiftlint, warnings count as errors, what CI runs
make format-check  # check the shape of the code without changing anything
make ci            # lint-strict, format-check, build and test in one run
make hooks         # point git at .githooks, once per clone
make backend       # raise the local petzy stack in Docker
```

`make test` runs 58 files of Swift Testing over `PetzyTests`. The network in
those tests is never real: `StubURLProtocol` answers with canned responses in
order, the last answer is not repeated, and an extra request gets a 500 that
the test sees.

`make test-ui` runs 12 files of XCUITest over `PetzyUITests` against the
live stack. CI runs the unit tests only: the UI tests need a running Petzy.

| Path | What it holds |
| --- | --- |
| `Petzy/App/` | The entry point, the configuration, the app model, the root view, the offline layer. |
| `Petzy/API/` | The HTTP layer, the routes, the models. |
| `Petzy/Auth/` | The session, the token storage, the Keychain. |
| `Petzy/Resources/` | The asset catalogue with the app icon. |
| `PetzyTests/` | The unit tests. |
| `PetzyUITests/` | The UI tests. |
| `docs/PORT-PLAN.md` | The inventory of the web screens and the order they were ported in. |
| `docs/USER-CASES.md` | What a person can do in the app, and what has to happen. |
| `project.yml` | The source of the Xcode project. |
| `Makefile` | Every command, and the destination and the scheme. |

The project has no package manager and no third-party dependency: the system
frameworks are all it uses.

## License

MIT, © Alexander Blinov. See [LICENSE](LICENSE).
