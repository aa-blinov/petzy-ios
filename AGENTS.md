# Working in this repo

Petzy for iOS: a native SwiftUI client for the same API the pet health diary web
app uses. The backend lives in a separate repository (`petzy`, Flask + MongoDB);
this repo holds only the app. The interface is Russian.

**This project is developed with TDD.** See "TDD" below, it is not optional.

## Git

The rules from the `petzy` repo apply here too:

- Work in `master`: no feature branches, no pull requests. Commit locally as each
  piece is done.
- Push only when the owner says so.
- **Never add an AI attribution trailer** (`Co-Authored-By: Claude`, mentions of
  Claude or Anthropic) to commits or pull request descriptions. History is
  attributed to the human author only.
- Never `--no-verify`: fix the cause.

## Build

The Xcode project is generated from `project.yml` and is **not** in git.
`.pbxproj` is a build artifact: never edit it, never commit it. Change
`project.yml` and run `make generate`. Adding a file under `Petzy/` needs no
project change, XcodeGen globs the directory.

- Project: `Petzy.xcodeproj` (run `make generate` first)
- Scheme: `Petzy`
- Destination: `platform=iOS Simulator,name=iPhone 18 Pro`
- Bundle id: `ru.petzy.app`
- Derived data: `.build` (in the repo, gitignored)
- iOS 26.0 minimum, Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY=complete`
- `.xcode-version` pins the local Xcode (27.1); `.swift-version` pins the language

**Go through `make`, not through `xcodebuild` by hand.** The Makefile owns the
destination, the derived data path and the scheme, and it is the one place where a
change of simulator or of scheme lands. Hand-written `xcodebuild` calls drift out
of sync with CI and are the usual source of "works here, fails in CI". The one
exception is debugging a single failing test, where reading the full
`xcodebuild` output beats `tail`.

```bash
make setup     # brew install xcodegen swiftlint, then generate
make build     # generate + build for the simulator
make test      # unit tests, fast, no server
make test-ui   # UI tests against the live local stack (needs make backend)
make run       # build, install and launch on the simulator
make shot      # screenshot of the current screen
make lint      # swiftlint
make lint-strict  # same, warnings count as errors (what CI runs)
make format    # rewrite the code per .swiftformat
make format-check  # check the shape without changing anything
make ci        # lint-strict + format-check + build + test, all of CI in one run
make hooks     # point git at .githooks, once per clone
```

`make ci` is the pre-push check in full. Before handing a change over, run it
rather than a piece of it, unless nothing Swift changed, in which case
`make lint-strict format-check` is enough.

**A recipe that ends in `| tail` returns tail's code, not xcodebuild's.** That
made `make ci` exit 0 on failing tests until every such recipe started with
`set -o pipefail;`. macOS make is 3.81 and does not know `.SHELLFLAGS`, so the
flag goes into the recipe. Any new `xcodebuild … | tail` needs the same prefix,
or a red run looks green.

The working simulator is `iPhone 18 Pro` on iOS 27.0, set in the `Makefile` as
`SIM ?= iPhone 18 Pro`. Override with `make run SIM="..."`. `iPhone Duo` (iOS
27.1) is still around as a spare.

The runtime for the modern devices is **older than the Xcode runtime**: Xcode
27.1 with iOS 27.1 cannot create an iPhone 18 Pro at all, `simctl create`
answers `Incompatible device`. `xcodebuild -downloadPlatform iOS` pulls iOS
27.0 and installs a set of devices with it, which is what made the switch
possible. When a device type is rejected the same way, check
`xcrun simctl list runtimes` before assuming the type is the problem.

**`iPhone Duo` is not a normal phone.** Its screen is 466×678 pt and the system
puts the `TabView` bar in a **vertical rail on the right edge**, not along the
bottom. Two consequences that cost real time:

- A `TabView` filled with bare views renders its buttons with **empty labels**,
  and they collapse into a nameless strip. The label belongs in `Tab("Лента",
  systemImage: "list.bullet") { ... }`, not in the content view.
- In XCUITest there is **no `app.tabBars` element at all** on this device; the
  tabs are `AXRadioButton` with the `AXTabButton` subtype. Select them as
  `app.buttons["Лента"]`, which also works on a bottom tab bar.

`make test-ui` swallows its own output through `tail -40`, so a run in progress
looks frozen. When you need to watch it, run `xcodebuild` from the Makefile's
line directly into a file.

## Style and hooks

- SwiftLint, 120 columns, same as the backend's ruff. `make lint-strict` is what
  CI runs.
- SwiftFormat, 0.64, config in `.swiftformat`. `make format` before committing;
  `make format-check` is the read-only version.
- The two disagree in one known place: swiftformat moves the brace of a
  multi-line `if let` onto its own line, SwiftLint's `opening_brace` forbids it.
  Write such conditions on one line instead of adding a suppression.
- Git hooks live in `.githooks/`, not `.git/hooks/`. `make hooks` points git at
  them once per clone. `pre-commit` checks formatting and style of staged Swift
  files, `pre-push` runs the strict lint and the unit tests. Never `--no-verify`.

## CI

`.github/workflows/ci.yml` runs on every push to `master`: install the tools,
`xcodegen generate`, `swiftlint lint --strict`, build, unit tests. UI tests are
not in CI, they need a running Petzy stand.

The runner is `macos-26` with `latest-stable` Xcode. That works because the
minimum is iOS 26: under an iOS 27 minimum the image's Xcode 26.6 had no
simulator destination at all and the unit tests could not run. If the minimum
goes back up to 27, the Xcode version has to be pinned to one that ships the
iOS 27 SDK.

## Agents

`.mcp.json` registers two MCP servers: `xcodebuild` (XcodeBuildMCP, owned by
Sentry) for build, test and scheme discovery, and `ios-simulator` for
screenshots and taps. Both are also registered in the local runtime; they start
on the next turn after being added.

A third, `xcode-bridge` (`xcrun mcpbridge`), is registered in the local runtime
but not in `.mcp.json`: it needs a running Xcode with the project open, so it
answers in a headless session. It gives `DocumentationSearch` and
`RenderPreview`. Do not build a task around it; use `make` instead.

`.xcodebuildmcp/config.yaml` holds the session defaults, so MCP calls need no
arguments:

```json
build_sim({})
test_sim({})
```

Keep `simulatorName` there and not `simulatorId`: the name is portable between
machines and the server resolves the UDID itself. `projectPath` is absolute and
belongs to this machine; on another one, fix that line or drop it and pass the
path per call. The config points at `Petzy.xcodeproj`, which is generated, so
run `make generate` first if the file is missing.

## TDD

Every piece of behaviour is written test first. The order is not negotiable:

1. Write a test that fails, and check that it fails **for the reason you think**.
   A test that fails on a typo or on a missing symbol proves nothing: it would
   have "caught" the bug while testing nothing. Read the failure message.
2. Make it pass with the least code that works.
3. Refactor with the test green, run again.

Rules that follow from that:

- No production code without a test that failed before it existed. If a change is
  too small to test, say so out loud rather than skipping silently.
- Network in unit tests is never real. `StubURLProtocol` answers with canned
  responses in order.
- UI tests are for wiring: does the screen reach the server and show what came
  back. They are not for logic; logic belongs in unit tests where it runs in
  milliseconds.
- Assert **which requests happened and in what order**, not only what came back.
  `StubURLProtocol.requestedPaths` is what catches a retry that fired twice.
- A test that cannot fail is worse than no test. Delete it.
- Commit on green. A red test in history is fine and useful; a red test that gets
  papered over is not.

**Do not leave known gaps.** If you notice that something is unfinished, broken
or unverified — while writing it, while testing it, or while looking at the
screen — finish it in the same pass and say in the report what it was and how
it was checked. A list of "what I did not check" at the end of a message is a
to-do list in disguise. If a gap genuinely cannot be closed now, it goes into
`docs/PORT-PLAN.md` as an open item with the reason, not into the prose.

**Tests passing is not the same as working.** Unit tests check logic, and they
passed on a shell whose tabs were invisible. Always run the change on the
simulator and look at it before calling anything done:

```bash
make run        # build, install, launch
make shot       # screenshot, with the right display this time
```

Screenshots go through `read`, which shows the image: a claim like «экран
открывается» is not evidence until a picture backs it. `make run` alone proves
only that the app starts. For flows that need a signed-in session, launch with
`PETZY_TEST_LOGIN` and `PETZY_TEST_PASSWORD` and tap the button through the
`ios-simulator` MCP (see "The simulator on this machine").

The bar for "done" on a screen: unit tests green, `make ci` green, and a
screenshot of the real screen with real data.

## The simulator on this machine

Xcode 27.1 behaves differently from older versions, and the defaults here cost
real time to rediscover. All of this was verified in practice.

**There is no `Simulator.app`.** In Xcode 27 the simulator window is
`DeviceHub.app`, inside the Xcode bundle:

```bash
$(xcode-select -p)/../Applications/DeviceHub.app
```

Launch it **with the device UDID**, or the display never attaches:

```bash
UDID=$(xcrun simctl list devices available | grep -m1 "iPhone 18 Pro" \
  | sed -E 's/.*\(([-0-9A-F]+)\).*/\1/')
open -a "$(xcode-select -p)/../Applications/DeviceHub.app" --args -CurrentDeviceUDID "$UDID"
```

Without the UDID the app runs fine but every screenshot is **solid black**, and
so is the home screen. A black screenshot says nothing about the app. Check the
home screen before blaming the code.

**There are two displays.** `LCD` is the real one, `LCD-1` stays black. Name the
display explicitly:

```bash
xcrun simctl io "$UDID" screenshot --display=1 out.png
```

**`idb` is installed by hand, not by Homebrew.** `brew install idb-companion`
does not work: the formula and the cask are both gone from Homebrew, and the
cask named `companion` is an unrelated Stream Deck app. The project itself is
alive (facebook/idb), so both halves were installed from release v1.7.6:

```bash
# CLI, Python: любой интерпретатор 3.8+
python3 -m venv ~/.local/share/idb/venv
~/.local/share/idb/venv/bin/pip install fb-idb

# companion: готовая сборка из релиза, 28 МБ
curl -sSL -o /tmp/idb-companion.tar.gz \
  https://github.com/facebook/idb/releases/download/v1.7.6/idb-companion.macos-arm64.tar.gz
tar -xzf /tmp/idb-companion.tar.gz -C ~/.local/share/idb/companion
ln -sf ~/.local/share/idb/venv/bin/idb            ~/.local/bin/idb
ln -sf ~/.local/share/idb/companion/idb_companion ~/.local/bin/idb_companion
```

Both need `~/.local/bin` on PATH, which it already is here. Without the
companion the CLI installs fine and still cannot see any simulator: every
`ios-simulator` MCP call that touches the UI fails with `spawn idb ENOENT`.

**Do not move a Python venv after creating it.** Its scripts carry an absolute
shebang to the interpreter; after a `mv` every entry point dies with
`bad interpreter: No such file or directory`.

**A `Task` that was stopped may still have left `xcodebuild` running.**
Cancelling a background command kills the shell wrapper, not the build. Two
`xcodebuild` runs on the same `-derivedDataPath` block each other and the next
run appears to hang with no output. Check before blaming the build:

```bash
pgrep -fl "Xcode.app/Contents/Developer/usr/bin/xcodebuild"
```

And when watching a long run, redirect to a file (`> /tmp/log 2>&1`) instead of
piping into `grep`: a pipe buffers, so a running build and a build that failed
on line one look identical until it finishes.

**`simctl get_app_container` fails with `Unable to lookup in current state:
Shutdown`** when the device is off. Boot it first.

**`typeText` into a `SecureField` drops characters.** A 15 character password
arrived as its last six characters, digits and hyphens only. Chunked typing, the
hardware keyboard setting, `textContentType`, and the keyboard layout all made no
difference. The keyboard itself is **not** the cause: a screenshot of the search
field in the type catalog shows a full Russian layout, about thirty keys, so this
is specific to the secure field and not to typing in general. `idb`'s `ui_type`
also rejects non-ASCII outright (`text must match ^[\x20-\x7E]+$`), so Russian
text cannot be typed through MCP either.

So: **do not type into `SecureField` from a UI test**, and do not plan a UI test
around typing Russian text. Feed credentials through the environment instead (see
below). Read what the app actually received with `app.debugDescription` or a file
in its container; the accessibility value of a secure field does not give a usable
character count. Pick record types without fields, or already filled values, when
the test has to get past a form.

## The backend

The app talks to a Petzy API server over HTTP. The local one is Docker:

```bash
make backend            # docker compose up in ~/Documents/petzy, API on :5002
make backend-stop
```

`PETZY_API_BASE_URL` in `project.yml` is baked into `Info.plist`
(`http://localhost:5002`). To point a run somewhere else without touching the
file, pass a launch argument:

```bash
xcrun simctl launch "$UDID" ru.petzy.app -petzyBaseURL https://petzy.duckdns.org
```

The simulator reaches the Mac on `localhost`. A **physical device** cannot: give
it the Mac's LAN address and give `NSAllowsLocalNetworking` an exception domain
for that host. Not wired up, because there is no signing identity.

Demo login for the local stack: `demo`, password from `DEMO_PASSWORD` in
`scripts/seed_demo.py` of the backend repo. Five login attempts a minute from one
address, and ten wrong ones lock that login for fifteen minutes including the
right password. The `petzy` e2e suite (`e2e/run.py`) logs into the same stand and
shares that budget, so UI tests can fail from rate limiting that has nothing to
do with them.

The API reference is at `/api/docs`, the machine-readable spec at
`/api/openapi.json`. Read it before guessing a field.

**The backend already supports offline writing.** Do not assume it does not, and
do not file tickets for it without checking `web/events.py` first. As of the
commits that sit on `master` locally but not on `origin`:

- `local_id` on `POST /api/events`, plus `PUT`/`DELETE /api/events/local/{local_id}`
  to edit and delete before the answer comes back. Repeating a `POST` with the
  same `local_id` does not create a second record.
- `updated_at`, set by the server in UTC with milliseconds, compare as text.
  There is no `?since=` filter on purpose: read the whole feed.
- **`date_time` comes back in two formats, and which one depends on whether
  the record carries a `tz`.** A record written by the app sends `tz` and comes
  back as ISO with an offset, `2026-10-18T14:13:00+05:00`; an older one is
  `2026-10-04 11:00`. Parsing only the second one showed `Сегодня` as
  `18T13:01:00+05:00.10.2026` and broke three UI tests at once. Both go through
  `MomentText`, which also keeps the offset out of the shown time: the person
  entered it on their own clock.
- Cursor paging: `before` carries the previous `next_cursor`, and new records
  never shift a page. `page`/`page_size` is the web app's own path.
- Soft delete: `with_deleted=1` returns tombstones with `is_deleted` and
  `deleted_at`, kept for 30 days.
- **The app reads the feed without `with_deleted=1`, and that is deliberate.**
  A deleted record is not in the normal response anyway, and the app replaces
  its own copy wholesale after a full read, so it has nothing to purge. Asking
  for tombstones only cost page slots: a page of a hundred held fewer live
  records, and on a pet whose records were deleted many times the feed looked
  empty. Tombstones matter for a client that syncs by `since`.

Own event types (`/api/event-types`, key `custom_…`, `category: null`):
- The **key** is the server's to assign; `icon` and `color` are not — without
  either of them `POST` answers 422 `validation_error` with
  `{"field": "icon"|"color", "type": "missing"}`. The app sends both from the
  person's choice of icon and colour.
- `DELETE …?preview=true` returns `events_count`, and the type is **not**
  deletable while it has records: the real `DELETE` answers 422
  `event_type_has_events`. Ask for the count first and say plainly that only an
  empty type can go; do not promise records will disappear with it.
- Field names must match `^[a-z][a-z0-9_]{0,49}$` and `pet_id, date, time,
  comment, type, fields` are reserved. A field the person added but left blank
  must not be sent at all, or the server refuses the whole type.

All of it is written out in the «Синхронизация с нативным приложением» section
of `web/openapi_doc.py`. Read that section before designing offline work.

The admin section (`/api/users*`) answers only the administrator; everyone else
gets `forbidden_admin_only`.

- Who is the administrator is decided by `GET /api/auth/session`
  (`{"is_admin": true, "username": …}`), and that same name is a single
  `ADMIN_USERNAME` in the server config. There is no list of roles.
- **`is_admin` in the user list is not a field of every user**: it is present
  only in the admin's own record. A non-optional decode of it breaks the whole
  list, and the screen stays empty with a decoding error.
- `DELETE /api/users/<login>` is a soft disable: the person stops signing in,
  their records stay. There is no hard delete, so a probe account stays in the
  database forever, just disabled.
- The local stand serves the admin only with the extra compose file
  `docker-compose.demo-admin.yml` (it restarts `web` with
  `ADMIN_USERNAME=demo_admin`); the demo password is the public one.

## Layout

```
Petzy/App/         @main, AppConfig (base URL), AppModel (session state), RootView
Petzy/API/         HTTP (one request builder), APIClient (authed routes), models
Petzy/Auth/        AuthSession (login, refresh), TokenStorage, KeychainTokenStorage
Petzy/Features/    one directory per screen: Login, Pets
Petzy/Resources/   Assets.xcassets with the app icon
PetzyTests/        Swift Testing suites, StubURLProtocol for the fake network
PetzyUITests/      XCUITest flows against the live local stack
docs/PORT-PLAN.md  what is being ported from the web app, in which order
```

## Porting from the web app

`docs/PORT-PLAN.md` holds the inventory of all 48 web routes and the 11 stages
they are ported in. Read it before adding a screen, and keep it current: a stage
that is done is marked as done there rather than in a commit message.

Two directions are worth knowing, because the web app is the source of truth for
behaviour and for Russian wording. The route map is
`frontend/src/App.tsx` in the `petzy` repo, the design system is its `DESIGN.md`
and `frontend/src/styles/globals.css`, and the API truth is `/api/openapi.json`
of a running stand.

The settings screen follows the web's grouping (`frontend/src/pages/
Settings.tsx`): «Питомцы», «Записи», «Новые записи», «Аккаунт»,
«О приложении», «Администрирование» (у админа) и «Выход». A flat list mixed
them up: «Справка» stood between the pet and the account, and it was not clear
that these were different things at all.

## Auth

The backend is already prepared for a native client: **a request without an
`Origin` header is treated as native and gets `access_token` and `refresh_token`
in the response body** (a browser gets httpOnly cookies instead). `HTTP.send`
deliberately never sets `Origin`; a test asserts it.

Rules the backend enforces and the app must respect:

- `access_token` lives 15 minutes, `refresh_token` 7 days.
- `POST /api/auth/refresh` returns a **new** `refresh_token` that replaces the
  old one. The old one still works for 30 seconds; presented later it counts as
  stolen and ends that sign-in. Always store the new pair.
- The refresh token goes in the Keychain, never in `UserDefaults`.
- `APIClient` retries once after a 401 and the refresh. A second 401 becomes
  `.unauthorized`; there is no loop.
- Never `try?` a Keychain read. A swallowed failure looks exactly like "the person
  never signed in" and makes them type their password on every launch. `restore()`
  logs what it found.

**Sign-out is local only.** `AuthSession.signOut()` deletes the tokens from the
device and does not call `POST /api/auth/logout`, because that endpoint ends the
user's sessions on *every* device at once. Signing out on the phone should not log
the person out of their tablet. A separate "sign out everywhere" button is the
place for that endpoint, when it is wanted.

### Test hooks

Three launch-time hooks exist only for tests, and all of them default to doing
nothing:

- `-uiTestSignedOut` makes `AppModel.start()` wipe the tokens before restoring,
  so a UI test always starts on the login screen. It does **not** skip the
  Keychain, which is the thing being tested.
- `-uiTestOnboarding` shows the first-run screen even when the onboarding flag
  is already set. It is checked **after** `-uiTestSignedOut`, which skips the
  onboarding, so the two together give a signed-out app on the first screen.
- `PETZY_TEST_LOGIN` and `PETZY_TEST_PASSWORD` prefill the login form. Needed
  because of the broken software keyboard above. The real button press still
  happens, so login, response parsing, the Keychain and the pets request are all
  genuinely exercised.

When checking session restore, clear `launchArguments` before the relaunch. Left
set, `-uiTestSignedOut` wipes the tokens itself and the test silently checks a
cold start instead.

### A UI test inherits the pet the previous test picked

The selected pet lives in `UserDefaults`, so it survives a relaunch and the
next UI test starts on the same pet. A check that holds for one pet but not for
another then passes in one order and fails in another: the medical card test
looked for the field «Что беспокоит» by its hint, and the complaint from the
note «К приёму» is put into that field beforehand, so the hint is gone.

Two rules follow:

- A UI test must not depend on the data of a particular pet. Look for what
  every pet has (a section header, a button), not for a hint or a value.
- The pet comes from the stand, and the stand's data changes under the tests:
  `TestLaunch.petWithCourse`, `petWithPhoto` and `petWithNextFeedPage` ask the
  server which pet fits the check.

### A flag in `UserDefaults` does not redraw the screen

State read from `UserDefaults` inside a computed property is invisible to
SwiftUI: writing the default changes the value, but nothing tells the view to
redraw, and the screen keeps showing what it showed. The onboarding screen
stayed on top of the login form until the app was restarted.

Such state belongs in the model as a stored, observable property, set in `init`
from the default and updated in the same place that writes the default:

```swift
internal(set) var needsOnboarding: Bool   // set in init, changed in skipOnboarding()
```

`internal(set)` rather than `private(set)`: the setter lives in another file of
the same module, and `private(set)` forbids exactly that.

A unit test cannot catch this one — the value was right, only the observation
was missing. It takes a UI test (`testOnboardingLeadsToLoginForm`) to see it.

## Interface text

The rules come from the web app (`AGENTS.md` in the backend repo):

- Russian, calm and direct.
- No « · » or any glyph joining two facts. Side by side with a comma.
- No « — » or « – » outside number ranges.
- A single UI line (toast, hint, note, empty state) ends without a full stop;
  sentences inside it keep theirs.
- Touch targets at least 44 pt.

## Interface decisions

Settled with the owner and verified against Apple's own guidance. They are
decisions, not preferences: do not re-litigate them screen by screen. The
reasoning and the sources are in `docs/PORT-PLAN.md`.

- **Create is a system button in the toolbar**, `ToolbarItem(placement:
  .topBarTrailing)` with a `plus` label. No hand-drawn circular button. Apple
  gives the leading edge to back and title, common actions to the trailing one
  ([HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)),
  and in iOS 26 the button gets Liquid Glass on its own.
- **A sign shows the thing, and a failure looks like a failure.** The pet
  switcher shows the species sign (`PetSpecies.icon`), so a dog is a dog and not
  a paw; the medical card's failure shows the warning triangle, like the feed
  and the history. One meaning has one sign: `plus` for creating,
  `square.and.arrow.up` for sharing, `arrow.down.doc` for export, `clock` for
  «waits to be sent».
- **The app icon is the petzy brand icon.** It comes from the web app
  (`frontend/public/icon.svg`, a copy in `docs/app-icon.svg`) and is rendered to
  a 1024×1024 PNG without transparency and without rounded corners: iOS cuts
  the shape itself. Re-render it when the brand changes:

  ```bash
  sed 's/width="512" height="512"/width="1024" height="1024"/' docs/app-icon.svg > /tmp/icon.svg
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu \
    --hide-scrollbars --window-size=1024,1024 \
    --screenshot=Petzy/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png \
    "file:///tmp/icon.svg"
  ```
- **Row actions are `swipeActions`**, not web-style swipe-left-to-delete, and the delete
  goes through a confirm dialog. One exception, made because the list crashed:
  «Свои типы записей» has a red trash button in the row instead, as the web does.
  Destructive
  button uses `Button(role: .destructive)`, the delete goes through a
  `confirmationDialog`, and the full swipe is switched off through the
  **parameter of `swipeActions`**, not as a modifier on the button:
  `.swipeActions(edge: .trailing, allowsFullSwipe: false)`. Written as a modifier
  on the button it does not compile, and the compiler reports it as «unable to
  type-check this expression», not as a missing member.
- **In iOS 26 a `swipeActions` button is painted from the tint, and
  `role: .destructive` alone leaves it the accent colour.** Verified on the
  simulator: «Удалить» and «Изменить» came out the same brown, and only
  `.tint(.red)` on the destructive button turned it red. The same button inside
  a `confirmationDialog` *is* red with the role alone. So the destructive action
  in a row needs both: the role and the tint. A server-side delete is hard and
  unrecoverable, and silently losing a medication dose is worse than one extra
  tap. This is the exact pattern in
  [What's new in SwiftUI, WWDC26](https://developer.apple.com/videos/play/wwdc2026/269/).
- **Pets carry a photo and a name.** No photo frames, no coloured card background,
  no handwritten font. Those were web decoration.
- **The pet's card is the first row of the feed.** Photo (or the species icon when
  there is no photo), name, and the line «age, breed, gender», all in one line
  through a comma. The photo comes from the pet list itself (`photo_url` in
  `/api/pets`), so no extra request is needed; the address is signed and opens
  without a token. The card is a link to «О питомце», where all of this is
  edited. The web's «Добавить возраст и породу» button is not repeated: the
  link leads to the same form.
- **Native components, no glass of our own.** Use the system control, strip its
  background and shadow, keep the accent (`#C46A3F` light, `#E8946A` dark).

### A `task(id:)` keyed on the pet shows the previous pet's model

Sections with their own model (`Лекарства`, `Медкарта`, `Документы`) get it
recreated by `AppShellView` per pet, and that recreation happens **after**
`selectedPetID` changes. So `.task(id: app.selectedPetID)` restarts while the
screen still holds the *old* model: `load()` fills the model nobody renders,
the new empty one appears instead, and nothing loads it again. The screen then
says «Лекарств нет» at a pet with courses, and only an app restart fixes it.
The key is the model itself, `.task(id: ObjectIdentifier(model))`, which
changes exactly when the rendered model does.

Two things made this expensive. Switching pets *before* opening the section
loads the right model on the first try, so a UI test written that order passes
on the broken build; the defect needs the section already on screen. And the
screen looks plausible, so a screenshot of the list taken after the switch
proves nothing either way — the answer was in the backend access log, where the
response size for the two pets alternated one step behind the selection.

### Four traps of `List` on iOS 26, each found by crashing or by looking

- **`swipeActions` + removal of that same row crashes the list.** The signature is
  `UICollectionView Invalid Number Of Items In Section` inside
  `UICollectionViewListCoordinatorBase.performUpdates`. The crash comes before the
  delete request reaches the server, so the API is not involved. What does *not*
  help: making the row a `Button`, `.listStyle(.plain)`,
  `.animation(nil, value:)`, delaying the confirm dialog, or swapping
  `confirmationDialog` for `alert` — all four were tried on the simulator and the
  crash stayed. What does help: **no swipe at all**. The row carries a red trash
  `Button`, exactly as `frontend/src/pages/EventTypesSettings.tsx` does in the
  web app. Five removals in a row then ran clean. The feed, documents and
  medications also use `swipeActions` and delete rows there without falling over,
  so this is not a blanket ban on swipe: if a list starts crashing on removal,
  take the swipe off that list first.
- **In a `confirmationDialog` a `role: .cancel` button is not drawn.** It is
  hoisted out of the popover and never appears, so a dialog offering only a
  cancel action shows text and no way out. Use a plain `Button("Отмена")`.
  In an `.alert` the same button renders normally, so there `role: .cancel` is
  fine and is the better choice.
- **The dialog closes before its own action runs.** A handler that reads state
  the dialog was showing finds it already nil: `isPresented` is set to `false`
  first, and a custom setter wired to `cancelDelete()` wipes it. The native way
  out is `presenting:` — the system hands the item to the action, and the
  action never reads the state the dialog was showing:

  ```swift
  .confirmationDialog("Удалить запись?", isPresented: showing, presenting: pendingDelete) { event in
      Button("Удалить", role: .destructive) { Task { await model.deleteEvent(id: event.id) } }
      Button("Отмена") { pendingDelete = nil }
  } message: { _ in
      Text("Запись пропадёт из дневника")
  }
  ```

  Two details cost time: the `message:` closure takes the item too, so it is
  `{ _ in … }` and not `{ … }`; and there is no overload with `presenting:` and
  a message that takes no argument. `CustomTypesView` keeps the key in the
  model instead, because its alert has to show the record count.
- **Several `NavigationLink`s in one row break the navigation.** A row of a
  `List` that holds a link becomes a link itself, and with a grid of four links
  in one row the row took the transition over: a tap on «Прививки» opened
  «Операции и процедуры», and the back button walked through the sections
  instead of returning to the card. One link per row is fine — that is what the
  settings screen does. When one row holds several, the transition goes by
  path: `NavigationStack(path:)`, a `Button` that appends to it, and
  `.navigationDestination(for:)`. `CustomTypesView` and `UsersView` already do
  it that way for the same family of reasons. The link's own chevron disappears
  with it, so the row draws its own.

## SwiftUI practices

Checked against Apple's own guidance (HIG, WWDC26) and what the SDK actually
offers. The app was already native in most of it: system controls everywhere,
`.searchable` instead of a hand-drawn search field, `ContentUnavailableView`
for empty states, value-based navigation where a row holds several links.

Three things were not, and are now rules:

- **The layout has to survive the accessibility text sizes.** A two-column grid
  of tiles breaks at the largest size: the titles wrap by letters and the
  chevron lands on the text. `MedicalCardView.columns(for:)` switches to one
  column when `dynamicTypeSize.isAccessibilitySize`, and the tile puts the
  icon above the title so the title gets the whole width. The weekdays of the
  medication course are the same story: seven chips in a row leave 40 pt each
  and «Пн» breaks by letters, so `WeekdaysPicker` puts them in a grid of four.
  Check it with:

  ```bash
  xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large
  ```

  and look at the screen, not at the code: a `List` scales on its own, a grid
  does not.
- **Return has to go somewhere.** A field with `.submitLabel(.next)` and no
  `@FocusState` promises a transition and does nothing. Forms with more than
  one field take a `@FocusState` with an enum of the fields and move the focus
  in `.onSubmit`: login, registration, pet card, document, medication course,
  medical record, event.
- **The keyboard hides itself on its own.** A `Form` and a `List` dismiss the
  keyboard when the content scrolls, so `.scrollDismissesKeyboard` is not
  needed. Only a number pad has no way out, and that is what the keyboard
  toolbar is for.

Four more, found by going screen by screen:

- **A tappable row is a `Button`, not `onTapGesture`.** A gesture leaves the
  row invisible to VoiceOver: the person hears the text and cannot open the
  record, and on iPad or Mac the row cannot be reached with the keyboard. The
  feed, the history and «Свои типы записей» were the last three places with a
  gesture; documents, users and the rest were already buttons.
- **A number pad needs a «Готово» above it.** The numeric keyboard has no
  Return key, so it cannot be dismissed, and it covers the form. The button
  lives in `ToolbarItemGroup(placement: .keyboard)` and the shared modifier is
  `View.keyboardDone` (`Petzy/App/KeyboardDone.swift`). The focus state has to
  cover **all** the fields of the form, not only the numeric ones: otherwise
  the button is on the screen and does nothing.
- **A sheet needs a way out.** A sheet without a close button closes only by
  a swipe down, and on a device with a vertical tab rail the gesture is not
  obvious. The close button goes on the sheet that is actually on screen, not
  on the view inside it: the policy is opened both from the login screen and
  from the settings, and a close button in `PrivacyView` would be wrong in one
  of them.
- **A sheet presented from under another sheet opens behind it.** The
  registration form is a sheet, and the policy opened by the login screen
  appeared *behind* it, so «Прочитать политику» looked dead. The sheet has to
  be attached to the view that is on screen.
- **A long list loads the next page by itself.** «Загрузить ещё» was a web
  pattern: in iOS the list grows when the person reaches the end, and the app
  asks for the next page on its own, the way Mail and Photos do. The trigger is
  a row at the end of the list with `onAppear`, and the request is guarded by
  `isLoadingMore`, so two appearances cannot read the same page twice.

## Swift conventions

- Swift 6, strict concurrency on. Anything crossing an actor boundary or escaping
  into a task is `Sendable`; make it compile before moving on.
- Models decode with hand-written `CodingKeys`, not
  `JSONDecoder.convertFromSnakeCase`. The pet id is `_id`, which the automatic
  conversion turns into `Id`, and that typo does not surface as a build error.
- **A struct with its own `init` loses the memberwise one.** Adding the second
  initializer to `EventDraft` silently removed the synthesised `init(type:…)` that
  the tests and the form were calling, and the errors pointed at every call site
  instead of at the struct. When a struct grows a convenience initializer, write
  the plain one out by hand. The same trap is built into the language: a `let`
  with a default value (`let batch: String? = nil`) is dropped from the memberwise
  initializer too, so adding "just a default" makes every call site stop
  compiling with «extra arguments at positions …».
- «the compiler is unable to type-check this expression in reasonable time» is
  almost never a slow type checker. It is a modifier or argument the API does not
  have, and the real diagnostic («no member `allowsFullSwipe`») shows up only
  after the expression is broken up into smaller ones.
- `Pet` carries only the fields the app uses today. `/api/pets` returns more; add
  a field when a screen needs it rather than importing everything.
- API errors carry the server's own Russian text. «Неверный логин или пароль» and
  «сессия закончилась» are different problems for the person in front of the
  screen.
- SwiftLint and SwiftFormat, 120 columns, same as the backend's ruff. See
  "Style and hooks" above.
- Swift Testing, not XCTest, for unit tests. XCTest only where the framework
  requires it, which today means XCUITest.

Three things that cost real time and are now fixed:

- **`simctl install` does not restart the app.** It swaps the bundle, and a
  running process keeps serving the old code, so a fix looks like it «did
  nothing». Always `simctl terminate` between install and launch when checking
  a change on the simulator.
- **`idb`'s tap does not choose an item in a SwiftUI `Picker` popup.** The menu
  opens, the tap closes it, and the value silently stays as it was. A `List`
  with rows is fine, a `Picker` menu is not. Verify anything that goes through
  a `Picker` with a UI test, and look it up with
  `app.descendants(matching: .any).matching(identifier: label)`:
  `app.buttons[label]` does not find it.
- **A tap on a `StaticText` inside a `Button` with `.plain` does nothing.**
  The text has no hit area of its own. Use
  `app.buttons.containing(.staticText, identifier: title).firstMatch`.
- **A swipe can step over a day header.** A UI test that samples the visible
  headers while scrolling misses the ones that passed between two samples: the
  test looked for a day in the middle of the feed, never saw it, and the app
  had long since loaded the page. Look for the day at the very bottom of the
  feed, which is on screen at the end, and take one more sample after the last
  swipe.