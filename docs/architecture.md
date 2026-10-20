# Architecture

How the Petzy app for iOS is put together.

The app is a SwiftUI client for one backend, the same one the web app uses.
It holds no database of its own: what it knows is a copy of what it has
already seen, in one file, so that a person without a network still sees the
last week of the diary.

The code is in layers. The layers below the views know nothing about
SwiftUI, and the views know nothing about HTTP.

## The shape

| Module | What it is responsible for |
| --- | --- |
| `Petzy/App/PetzyApp.swift` | The entry point. It sets the locale to `ru_RU` and starts the app. |
| `Petzy/App/RootView.swift` | The first decision the interface makes: restoring, signed out, signed in, or a link from an e-mail. |
| `Petzy/App/AppModel.swift` and its extensions | The state of the app: the session, the list of pets, the selected pet, the feed, the history and the form defaults. It is an `@Observable` class, one per app. |
| `Petzy/App/AppConfig.swift` | The address of the API and the one `URLSession` of the app, with a 15 second timeout. |
| `Petzy/App/Accent.swift` | The accent colour, in a light and a dark value. |
| `Petzy/App/Offline/` | The copy and the queue: what the device has already seen, and the writes that have not gone out yet. |
| `Petzy/API/HTTP.swift` | Builds a request to `/api/...` and reads the error body. It is the only place that knows about headers. |
| `Petzy/API/APIClient.swift` | Adds the token, refreshes it after a 401 and repeats the request once. |
| `Petzy/API/*API.swift` | The routes, one file per group of endpoints. |
| `Petzy/API/Models.swift` and the other model files | The payloads, decoded with hand-written `CodingKeys`. |
| `Petzy/Auth/AuthSession.swift` | Signing in, refreshing and signing out. It is an actor, because the tokens are shared. |
| `Petzy/Auth/TokenStorage.swift`, `KeychainTokenStorage.swift` | Where the tokens live: a protocol, and the Keychain behind it. |
| The screen directories under `Petzy/` | One per screen, named after it: `Auth`, `Documents`, `Feed`, `History`, `Login`, `MedicalCard`, `Medications`, `Pets`, `Settings` and `Shell`. Each holds a model and a view, and the model talks to `APIClient` and never to the network. |
| `Petzy/Resources/` | The asset catalogue, with the app icon. |
| `PetzyTests/`, `PetzyUITests/` | The unit tests and the UI tests. |

The screens are: Auth, Documents, Feed, History, Login, MedicalCard,
Medications, Pets, Settings and Shell.

## The data flow

```
a tap on a screen
 → the model of that screen
 → APIClient
 → HTTP
 → the Petzy API
 → the model decodes the answer
 → the view redraws
```

With no network, the path forks at the model:

```
a write with no connection
 → kept as the request itself: path, method, body
 → LocalStore, in offline.json
 → the queue is flushed when the network is back
```

A read with no connection takes the other fork: the answer is taken from
the copy in `offline.json`, and the section says on the screen that it is
showing saved data.

## Decisions worth knowing about

### The request never carries an Origin header

The backend treats a request without that header as a native client and
answers with the tokens in the body, while a browser gets httpOnly cookies.
A test asserts the header is absent.

### The copy is stored as the bytes the server sent

The sections that come back as a blob are kept as `Data` in the snapshot and
parsed by the same code that parses the network answer. A second parser in
the copy would drift from the first one at the first change of the
contract.

### The write queue holds requests, not records

A write made without a network is kept as the path, the method and the body,
because the queue is one queue for the whole app and every section would
otherwise need its own way of describing a pending write. The name the
device gave the record is the `local_id` of the contract, so a queue that
sends twice does not write twice.

### A client retries once after a 401

`APIClient` refreshes the token and repeats the request a single time. A
second 401 becomes `.unauthorized`, and there is no loop.

### The models decode with hand-written CodingKeys

`JSONDecoder.convertFromSnakeCase` turns the pet id `_id` into `Id`, and
that typo does not surface as a build error. Every model spells out its
keys.

### The feed is read with a cursor

A hundred records to a page, and the next page is asked for when the person
reaches the end of the list. The days are grouped from the records for
display, because a page that arrives later has to join the days that are
already on screen.

### Deleted records are not asked for

The feed is read without the tombstones. The server does not return them
anyway, and asking for them only cost page slots: a page of a hundred held
fewer live records, and a feed of a pet whose records were deleted often
looked empty.

### The section models belong to a pet

The shell builds one model per section and per pet, and rebuilds them when
the selected pet changes. A section that was made for another pet would
send the pet's id in its requests and answer for the wrong animal.

### The project file is a build artefact

`Petzy.xcodeproj` is a build artefact and is not in git. `project.yml` is
the source, XcodeGen builds the project from it, and a file added under
`Petzy/` needs no project change.

## Boundaries

- A model under a screen directory talks to `APIClient` and never to
  `URLSession`. The network is reached through the client.
- `Petzy/API/` knows nothing about SwiftUI and nothing about the app's
  state. It answers with decoded payloads or throws.
- `Petzy/Auth/` owns the tokens. Nothing else reads the Keychain, and
  nothing else refreshes a token.
- `Petzy/App/Offline/` is the only place that reads and writes
  `offline.json`.
- The views hold no business rule. A view draws what its model holds and
  sends an action back to it.
- `Petzy/App/` holds the state that outlives a screen: the session, the
  pets and the selected pet.
