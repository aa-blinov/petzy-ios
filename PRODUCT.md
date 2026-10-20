# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

The application is a native iOS client: Swift 6 with strict concurrency on,
a minimum of iOS 26.0, one app target and two test bundles beside it. The
interface is SwiftUI throughout, with the system controls, and the project
has no third-party package.

It runs on iPhone and on iPad, `TARGETED_DEVICE_FAMILY` is `1,2`, and the
orientation is portrait. The backend is a separate repository (`petzy`, Flask
and MongoDB). The client speaks to it over HTTP with JSON bodies; the only
multipart body is the one that carries a file, a pet's photo or a document.

## Users

The person who keeps a pet and wants the record of its health in one place:
what it ate, what happened in the litter box, when the tablet was given, what
the vet said, when the next vaccination is due. The pet is the subject of
the record. The person writing it down is on the way somewhere, often with
one hand and often without a network.

The second audience is the vet. The medical card carries a PDF "for the
doctor", a profile for the doctor, notes for the next appointment and a share
link that opens the card to somebody else.

The third is a helper: the app issues personal access tokens, so a family
member or a script can work for the account without the password.

The repository is public and new. It was created in October 2026 and has no
stars, no forks and no releases, so there is no reach to report.

## Product Purpose

Keep the health record of a pet on the phone, in the same account as the web
app.

The unit of work is one entry: the type, the date and the time, a comment and
the fields of that type. The rest of the app exists so that writing one entry
and reading it back later take as few steps as possible, and so that the
record can be handed to somebody else when it has to be.

Success for the person: the entry is in the diary in two taps, and it is
still there when the phone is out of the network. Success for the product:
the diary lives in one place, the phone and the browser show the same
records, and the person can hand the doctor a summary of a year of entries
without typing it out.

## Positioning

A neighbouring app would start from nowhere. This one starts from a backend
that already holds the data: the same account, the same pets and the same
records as the web app, and the same contract, `local_id` included, so a
record written on the phone and a record written in the browser are one
record.

Three things the code does that a fresh app would have to invent:

- **The write queue.** A record made without a network is kept as the
  request itself, with the path, the method and the body, and goes out by
  itself. The name the device gave the record is the `local_id` of the
  contract, so a queue that fires twice does not write twice.
- **The copy.** The phone keeps what it has already seen and says so on the
  screen. A person in a clinic with no connection sees the last week rather
  than an empty list.
- **The native surface.** System controls, the accessibility text sizes, a
  tappable row that VoiceOver can activate and a keyboard can reach. The
  gestures of the web app do not travel, and the port did not try to carry
  them over.

## Operating Context

The phone is in a pocket. The app is opened several times a day for a
second: the cat did not eat, the dog needs the tablet, the vaccination is
due. The entry is written where the event happens, so the input has to be
short and forgiving, and the screen has to hold together at the largest
accessibility text sizes.

The network is often missing: a basement, a clinic with a bad connection, a
lift. The person writes the entry anyway, and the phone holds it until the
network is back.

The appointment is the moment the record is read by somebody else. The
medical card, the PDF and the share link are built for that moment.

The work happens against a local stack of the backend in Docker on port 5002,
and the UI tests run against that stack. The same backend serves the
production instance at `petzy.duckdns.org`.

## Capabilities and Constraints

Confirmed by the code:

- Five tabs: the feed, the medications, the medical card, the documents and
  the settings.
- The feed is read with a cursor, 100 records to a page, and the next page
  is asked for when the person reaches the end of the list. The days are
  grouped under "Сегодня", "Вчера" or a date.
- The catalogue of record types comes from the server and the form is drawn
  from the description of the type. There is no list of types in the code.
- Six categories of document, each with an expiry date: vaccinations, tests,
  results, images, insurance and other.
- Four sections of the medical card: vaccinations, parasite treatment,
  doctor's visits and procedures, each with the number of records and the
  overdue ones.
- Export in four formats: CSV, TSV, HTML and Markdown, handed to the system
  share sheet.
- Thirteen species, from the cat to the tortoise, each with its own sign, its
  own wording for the breed field and, where it makes sense, the question
  about neutering.
- The access token lives 15 minutes, the refresh token 7 days. The client
  refreshes once and repeats the request once; a second 401 ends the
  session.
- The session is restored from the Keychain at launch, and signing out
  deletes the tokens from this device only.
- What the phone has already seen is kept in one file, `offline.json` in
  Application Support, written atomically.

Deliberately not true, and worth knowing before a change:

- The app is unsigned. There is no build for a physical device, and the
  `petzy://` links in an e-mail lead to the web version. The scheme is
  registered in advance and the screens for it are ready.
- The UI tests are not in CI. They need a running Petzy.
- `GET /api/sync` is not used. Every section is read in full when it is
  opened.
- A document cannot be written without a network, because the upload needs a
  file.
- A record made with a date in the past does not rise to the top of the
  feed. The app says which day it went to.
- The filter of the history cannot be shared as a link: the state lives in
  the model, and a `petzy://` link opens only on a phone that has the app.
- There is no screen for the history of the doses of a course and no screen
  for the weight inside the medical card. The route is wrapped, the screen is
  not drawn.

## Brand Commitments

**Name:** Petzy. **Tone:** calm and direct, in Russian. The interface states
the outcome in words: a refused write, an expired document and a delete that
has to be confirmed each say so on the screen, and not only in a colour.

**The accent.** A warm brown-orange, `UIColor(red: 0.77, green: 0.42, blue:
0.25)` in light mode and `(0.91, 0.58, 0.42)` in dark mode, applied to the
whole app.

**The icon.** The petzy brand icon, the same "P" on a cream square
(`#FAF6EF`) that the web app uses. It comes from `docs/app-icon.svg` and is
rendered to a 1024x1024 PNG without transparency and without rounded corners,
because iOS cuts the shape itself.

**The wording.** The Russian of the web app carries over to the app, down to
the error messages: the text of the server is shown to the person as it
arrived, because "Неверный логин или пароль" and "сессия закончилась" are
different problems.

## Evidence on Hand

- The code: 98 Swift files and 14,690 lines in `Petzy/`, 58 unit test files
  and 8,578 lines in `PetzyTests/`, 12 UI test files and 1,060 lines in
  `PetzyUITests/`.
- The two documents in `docs/`: `PORT-PLAN.md` holds the inventory of the 48
  web routes and the 11 stages they were ported in, `USER-CASES.md` holds
  the user cases and the test that covers each of them.
- The contract of the backend: `/api/openapi.json` of a running stand, and
  the "Синхронизация с нативным приложением" section of
  `web/openapi_doc.py` in the `petzy` repository.
- The icon: `docs/app-icon.svg` and
  `Petzy/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.
- The live stand: the local petzy stack in Docker on port 5002, with the
  demo account `demo`.

Absent, and not to be invented: no screenshot of the interface is in the
repository, only the icon. There are no download counts, no usage numbers, no
testimonials and no comparison with other pet diary apps. The repository was
created in October 2026, has no stars, no forks and no releases, and there is
nowhere to count them.

## Product Principles

1. **One diary, one account.** The phone and the browser are two clients of
   one backend. A record written on one is on the other, and the copy on the
   phone is a copy of that record, not a second diary.
2. **Write it in the moment, and keep it.** The entry is written where the
   event happens, and it stays on the device until the network takes it. Any
   feature that adds a step between the event and the entry has to earn its
   place.
3. **The system control, not a drawn one.** The interface uses the system
   controls and the system signs, and one meaning has one sign. A screen
   that looks like the web app and behaves like a drawing is a defect.
4. **A failure is visible in words.** A refused write, an expired document, a
   record somebody else changed and a section shown from the copy each say
   so on the screen, in the person's own words, and not only in a log.
5. **The web app decides the behaviour and the wording.** The behaviour and
   the Russian wording come from the web app, and the port is tracked in
   `docs/PORT-PLAN.md`. A stage that is done is marked there and not in a
   commit message.

## Accessibility & Inclusion

- **Touch targets are at least 44 pt**, and a tappable row is a `Button`,
  not a gesture. A gesture leaves the row invisible to VoiceOver, and on
  iPad or on Mac the row cannot be reached with the keyboard.
- **The layout holds at the accessibility text sizes.** The tiles of the
  medical card switch to one column there, and the weekdays of a medication
  course go into a grid of four, because seven chips in a row leave 40 pt
  each and the label breaks by letters.
- **The keyboard has a way out.** A number pad has no Return key, so a
  "Готово" button sits above it, and the focus state has to cover every
  field of the form, not only the numeric ones.
- **The interface is Russian only.** The locale is pinned to `ru_RU` and
  there is no language switch, so a screen reader reads the Russian labels
  and nothing else.
- **A standard for contrast has not been set.** The accent comes from the
  brand and the rest of the interface follows the system theme.
