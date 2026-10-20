# AGENTS.md — agent context for `petzy-ios`

A native SwiftUI client for the Petzy pet health diary, on the same API the
web app uses. The backend lives in the `petzy` repository (Flask and MongoDB);
this one holds the app. The interface is Russian, and the documents here are
in English.

This file is what you need to work on the project without reading all of it.
The porting decisions and the reasons behind them are in
`docs/PORT-PLAN.md`, and the list of what a person can do in the app is in
`docs/USER-CASES.md`.

## Run / build / test

```bash
make setup         # brew install xcodegen swiftlint, then generate the project
make build         # generate and build for the simulator
make test          # unit tests, fast, no server
make test-ui       # UI tests against the live local stack, needs make backend
make run           # build, install and launch on the simulator
make shot          # screenshot of the current screen
make lint-strict   # swiftlint, warnings count as errors, what CI runs
make format        # rewrite the code per .swiftformat
make format-check  # check the shape without changing anything
make ci            # lint-strict, format-check, build and test, all of CI
make hooks         # point git at .githooks, once per clone
```

Xcode 27.1 and Swift 6.4.0 are pinned in `.xcode-version` and `.swift-version`.
The app targets iOS 26.0 and above, the language mode is Swift 6, and the
strict concurrency is complete. The bundle id is `ru.petzy.app`, the scheme is
`Petzy`, and the derived data lands in `.build`.

Go through `make`, not through a hand-written `xcodebuild`. The Makefile owns
the destination, the derived data path and the scheme, and it is the one
place where a change of simulator lands. Hand-written calls drift out of sync
with CI, and that is the usual source of "works here, fails in CI".

## Where things live

| Path | What it holds |
| --- | --- |
| `project.yml` | The source of the Xcode project. XcodeGen builds `Petzy.xcodeproj` from it, and the project file is not in git. |
| `Makefile` | Every command, plus the simulator, the bundle id and the derived data path. |
| `Petzy/App/` | The entry point, `AppConfig`, `AppModel`, `RootView`, the shell, the offline layer. |
| `Petzy/API/` | `HTTP` builds a request, `APIClient` signs it and refreshes the token, the rest are routes and models. |
| `Petzy/Auth/` | `AuthSession`, the token storage, the Keychain. |
| `Petzy/Resources/` | The asset catalogue with the app icon. |
| The screen directories under `Petzy/` | One per screen, named after it: `Auth`, `Documents`, `Feed`, `History`, `Login`, `MedicalCard`, `Medications`, `Pets`, `Settings`, `Shell`. |
| `PetzyTests/` | The unit tests, Swift Testing, and `StubURLProtocol` for the fake network. |
| `PetzyUITests/` | The UI tests, XCUITest, against the live local stack. |
| `docs/PORT-PLAN.md` | The inventory of the 48 web routes and the 11 stages they were ported in. |
| `docs/USER-CASES.md` | The user cases, with the test that covers each of them. |
| `.githooks/` | The pre-commit and the pre-push hook. |

## Traps

- **The Xcode project is generated.** `Petzy.xcodeproj` is a build artefact:
  never edit it, never commit it. Change `project.yml` and run
  `make generate`. A file added under `Petzy/` needs no project change,
  XcodeGen globs the directory.
- **A recipe that ends in `| tail` returns tail's code.** macOS make 3.81
  does not know `.SHELLFLAGS`, so the flag goes into the recipe:
  `set -o pipefail; xcodebuild ... | tail -20`. Without it `make ci` exits 0
  on failing tests and a red run looks green. Any new recipe that pipes needs
  the same prefix.
- **Xcode 27 has no `Simulator.app`.** The simulator window is
  `DeviceHub.app` inside the Xcode bundle, and it has to be started with the
  device UDID:
  `open -a "$(xcode-select -p)/../Applications/DeviceHub.app" --args -CurrentDeviceUDID "$UDID"`.
  Without the UDID the app runs, but every screenshot is solid black, and the
  home screen is black too. A black screenshot says nothing about the app.
- **There are two displays.** `LCD` is the real one, `LCD-1` stays black.
  Name the display: `xcrun simctl io "$UDID" screenshot --display=1 out.png`.
- **The device runtime is older than the Xcode runtime.** Xcode 27.1 with
  iOS 27.1 cannot create an iPhone 18 Pro at all, `simctl create` answers
  "Incompatible device". `xcodebuild -downloadPlatform iOS` pulls iOS 27.0
  and a set of devices with it. When a device type is rejected the same way,
  check `xcrun simctl list runtimes` before blaming the type.
- **`iPhone Duo` is not a normal phone.** Its screen is 466x678 pt and the
  system puts the `TabView` bar in a vertical rail on the right edge. A
  `TabView` filled with bare views renders its buttons with empty labels, so
  the label belongs in `Tab("Лента", systemImage: "list.bullet") { ... }`. In
  XCUITest there is no `app.tabBars` element on this device at all: the tabs
  are `AXRadioButton` with the `AXTabButton` subtype, and
  `app.buttons["Лента"]` finds them on either layout.
- **Do not type into a `SecureField` from a UI test.** The software keyboard
  of the simulator in this environment draws three keys instead of thirty and
  drops characters from a secure field: a 15 character password arrived as
  its last six. `idb`'s `ui_type` rejects non-ASCII outright, so Russian text
  cannot be typed either. Feed the credentials through `PETZY_TEST_LOGIN` and
  `PETZY_TEST_PASSWORD` instead. The button press stays real, so the login,
  the parsing, the Keychain and the pets request are all exercised.
- **`simctl install` does not restart the app.** It swaps the bundle, and a
  running process keeps serving the old code, so a fix looks like it did
  nothing. Terminate between install and launch.
- **A stopped task may have left `xcodebuild` running.** Cancelling a
  background command kills the shell wrapper, not the build. Two
  `xcodebuild` runs on the same `-derivedDataPath` block each other and the
  next run appears to hang with no output. Check with
  `pgrep -fl "Xcode.app/Contents/Developer/usr/bin/xcodebuild"`. When
  watching a long run, redirect to a file instead of piping into `grep`: a
  pipe buffers, so a running build and a build that failed on line one look
  the same until it finishes.
- **A `task(id:)` keyed on the pet shows the previous pet's model.** The
  section models are recreated after `selectedPetID` changes, so
  `.task(id: app.selectedPetID)` restarts while the screen still holds the
  old model: the load fills a model nobody renders, and the new empty one
  appears instead. The key is the model, `.task(id: ObjectIdentifier(model))`.
- **`swipeActions` plus the removal of that same row crashes the list.** The
  signature is `UICollectionView Invalid Number Of Items In Section`, before
  the delete request reaches the server. Making the row a button,
  `.listStyle(.plain)`, `.animation(nil, value:)`, delaying the dialog and
  swapping `confirmationDialog` for `alert` do not help; all four were tried.
  What helps is no swipe: the row carries a red trash button. The feed, the
  documents and the medications delete rows with a swipe without falling
  over, so this is not a ban on swipe. If a list starts crashing on removal,
  take the swipe off that list first.
- **In a `confirmationDialog` a `role: .cancel` button is not drawn.** It is
  hoisted out of the popover, so a dialog with a cancel action and nothing
  else shows text and no way out. Use a plain `Button("Отмена")`. In an `.alert`
  the same button renders normally, and there the role is the better choice.
- **The dialog closes before its own action runs.** A handler that reads the
  state the dialog was showing finds it already nil. Let the system pass the
  item to the action with `presenting:`:
  ```swift
  .confirmationDialog("Удалить запись?", isPresented: showing, presenting: pendingDelete) { event in
      Button("Удалить", role: .destructive) { Task { await model.deleteEvent(id: event.id) } }
      Button("Отмена") { pendingDelete = nil }
  } message: { _ in
      Text("Запись пропадёт из дневника")
  }
  ```
  The `message:` closure takes the item too, so it is `{ _ in ... }` and not
  `{ ... }`.
- **Several `NavigationLink`s in one row break the navigation.** The row
  becomes a link itself and takes the transition over, so a tap on
  "Прививки" opens "Операции и процедуры" and the back button walks through
  the sections. One link per row is fine. When a row holds several, the
  transition goes by path: `NavigationStack(path:)`, a `Button` that appends
  to it and `.navigationDestination(for:)`.
- **A flag in `UserDefaults` does not redraw the screen.** State read from
  `UserDefaults` inside a computed property is invisible to SwiftUI: writing
  the default changes the value and nothing tells the view to redraw, so the
  onboarding screen stayed on top of the login form until a restart. Such
  state belongs in the model as a stored, observable property, set in `init`
  from the default and updated where the default is written. Use
  `internal(set)` rather than `private(set)`, because the setter lives in
  another file of the same module.
- **Sign-out is local only.** `AuthSession.signOut()` deletes the tokens from
  the device and does not call `POST /api/auth/logout`, because that endpoint
  ends the sessions on every device at once. A separate "sign out
  everywhere" button is the place for it, when it is wanted.
- **The refresh token comes back new, and the old one turns into a theft.**
  `POST /api/auth/refresh` returns a new `refresh_token` that replaces the
  old one. The old one still works for 30 seconds and, presented later, ends
  that sign-in. Always store the new pair.
- **Never swallow a Keychain read.** A `try?` on the read looks exactly like
  "the person never signed in" and makes them type their password on every
  launch. `restore()` logs what it found.
- **`HTTP.send` deliberately never sets `Origin`.** The backend treats a
  request without that header as a native client and returns the tokens in
  the body, while a browser gets httpOnly cookies. A test asserts the header
  is absent.
- **The client retries once after a 401 and the refresh.** A second 401
  becomes `.unauthorized`; there is no loop.
- **A session dies only when the server says so.** The refresh token lives a
  week, so a network blip must not wipe it: the person in the subway would be
  thrown out of the app and would have to type their password again.
  `AuthSession.RefreshOutcome` tells the three cases apart: `.refreshed`,
  `.offline` (the network is gone, the session is alive, the request failed
  as a transport error and the app shows the saved copy) and `.expired` (the
  server refused, the tokens are gone, the person goes back to the login
  screen).
- **Any 401 means the session is over, on every route.** `APIClient.failure`
  turns it into `.unauthorized` so that `isAuthProblem` is true and the app
  shows the login. A route that does not parse the response (delete, raw
  send, download, the raw copy of a section) must not return the server's
  401 as an ordinary error: the person would stay inside the app with
  "Session expired" and think the action failed. The same goes for `getRaw`:
  the body of an error must not reach the offline copy, or its parsing fails
  later with a service message instead of "session expired".
- **Models decode with hand-written `CodingKeys`.**
  `JSONDecoder.convertFromSnakeCase` turns the pet id `_id` into `Id`, and
  that typo does not surface as a build error.
- **A struct with its own `init` loses the memberwise one.** Adding a second
  initializer to a draft silently removed the synthesized `init(type: ...)`
  that the tests and the form were calling, and the errors pointed at every
  call site instead of at the struct. A `let` with a default value is dropped
  from the memberwise initializer too, so adding "just a default" makes
  every call site stop compiling.
- **`date_time` comes back in two formats.** A record written by the app
  carries `tz` and comes back as ISO with an offset,
  `2026-10-18T14:13:00+05:00`; an older one comes back as
  `2026-10-04 11:00`. Both go through `MomentText`, which also keeps the
  offset out of the shown time, because the person entered it on their own
  clock. Parsing only the second one shows "Сегодня" as
  `18T13:01:00+05:00.10.2026` and breaks three UI tests at once.
- **The feed is read without `with_deleted=1`, and that is deliberate.** A
  deleted record is not in the normal answer anyway, and the app replaces
  its own copy wholesale after a full read. Asking for the tombstones only
  cost page slots: a page of a hundred held fewer live records, and on a pet
  whose records were deleted many times the feed looked empty.
- **`is_admin` is optional in the user DTO, and that is deliberate.** The
  server sends the flag only in the admin's own record, so `UserDTO.isAdmin`
  is `Bool?` and a missing key becomes `false`. Make the field required and
  the whole user list fails to decode, and the screen stays empty with a
  decoding error.
- **The offline copy belongs to the person who put it there.** The snapshot
  keeps the login of its owner, and the copy is shown only to him: on a
  shared device the next person to sign in must not see someone else's
  diary. Signing out takes the copy with it, but a session that died on its
  own does not: the person did not choose that, and his records must still
  be there next time. The login is known without the network (the login form
  gives it), and it is remembered in `UserDefaults` -- it is not a secret, and
  without it the app could not tell whose copy it is showing.
- **The offline queue is one queue of raw requests.** A write made without a
  network is kept as the path, the method and the body, and the name the
  device gave the record is the `local_id` of the contract, so a repeated
  `POST` with it is the same record and not a second one. A copy of a section
  is stored as the bytes the server sent and is parsed by the same code that
  parses the network answer.
- **`idb`'s tap does not choose an item in a SwiftUI `Picker` popup.** The
  menu opens, the tap closes it and the value stays as it was. A `List` with
  rows is fine, a `Picker` menu is not. Look a picker value up with
  `app.descendants(matching: .any).matching(identifier: label)`:
  `app.buttons[label]` does not find it.
- **A tap on a `StaticText` inside a `Button` with `.plain` does nothing.**
  The text has no hit area of its own. Use
  `app.buttons.containing(.staticText, identifier: title).firstMatch`.
- **A swipe can step over a day header.** A UI test that samples the visible
  headers while scrolling misses the ones that passed between two samples:
  the test looked for a day in the middle of the feed, never saw it, and the
  app had long since loaded the page. Look for the day at the very bottom of
  the feed, which is on screen at the end, and take one more sample after
  the last swipe.

## Style / safety rails

- **The interface is Russian.** Calm and direct. No middle dot between two
  facts: side by side with a comma. No em dash or en dash outside number
  ranges. A single UI line (a toast, a hint, a note, an empty state) ends
  without a full stop; the sentences inside it keep theirs. Touch targets are
  at least 44 pt.
- **The locale is pinned to `ru_RU`.** The interface has no language switch,
  so on an English device a date field would show "18 Oct 2026" and the
  numbers would be formatted as money.
- **TDD is not optional.** Every piece of behaviour is written test first,
  and the test has to fail for the reason you think: a test that fails on a
  typo or on a missing symbol proves nothing, because it would have caught
  the bug while testing nothing. The network in unit tests is never real. UI
  tests are for wiring, not for logic. Assert which requests happened and in
  what order, not only what came back: `StubURLProtocol.requestedPaths` is
  what catches a retry that fired twice. A test that cannot fail is worse
  than no test. Commit on green.
- **Do not leave known gaps.** If something is unfinished, broken or
  unverified, finish it in the same pass and say in the report what it was
  and how it was checked. A gap that cannot be closed now goes into
  `docs/PORT-PLAN.md` as an open item with the reason, not into the prose.
- **Tests passing is not the same as working.** Run the change on the
  simulator and look at it: `make run` and `make shot`. The bar for "done"
  on a screen is unit tests green, `make ci` green, and a screenshot of the
  real screen with real data.
- **Comments explain why, never what.** The comments in this codebase are
  unusually good on this point. Keep them that way.
- **SwiftLint and SwiftFormat, 120 columns.** They disagree in one known
  place: swiftformat moves the brace of a multi-line `if let` onto its own
  line and SwiftLint's `opening_brace` forbids it. Write such conditions on
  one line rather than adding a suppression.
- **CI checks the style of everything.** SwiftLint covers `Petzy`,
  `PetzyTests` and `PetzyUITests`, and the workflow also runs
  `swiftformat --lint`: a hook can be bypassed, CI cannot.
- **No dependency without a reason written down next to it.** The project
  has no package manager and no third-party package; the system frameworks
  are all it uses.
- **System controls, not drawn ones.** Use the system control, strip its
  background and shadow, keep the accent. One meaning has one sign: `plus`
  for creating, `square.and.arrow.up` for sharing, `arrow.down.doc` for
  export, `clock` for "waits to be sent".
- **A destructive action in a row needs both the role and the tint.** In
  iOS 26 a `swipeActions` button is painted from the tint, and
  `role: .destructive` alone leaves it the accent colour. The role and
  `.tint(.red)` are both needed. The same button inside a `confirmationDialog`
  is red with the role alone.
- **The full swipe is a parameter of `swipeActions`, not a modifier on the
  button.** Write `.swipeActions(edge: .trailing, allowsFullSwipe: false)`.
  As a modifier on the button it does not compile, and the compiler reports
  it as "unable to type-check this expression" rather than as a missing
  member.
- **The app icon comes from the web app.** `docs/app-icon.svg`, rendered to a
  1024x1024 PNG without transparency and without rounded corners: iOS cuts
  the shape itself.
- **The web app decides the behaviour and the Russian wording.** The route
  map is `frontend/src/App.tsx` in the `petzy` repository, the API truth is
  `/api/openapi.json` of a running stand, and the sync contract is written
  out in the "Синхронизация с нативным приложением" section of
  `web/openapi_doc.py`.
- **Git.** Work in `master`: no feature branches, no pull requests. Commit
  locally as each piece is done, and push only when the owner says so. Never
  `--no-verify`: fix the cause. Never add an AI attribution trailer to a
  commit or a pull request description.

## Where the product truth lives

`PRODUCT.md` holds it. Read it before changing the behaviour of the app, and
write the change there when the behaviour changes.
