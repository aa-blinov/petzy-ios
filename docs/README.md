# Documentation

The documents in this folder describe the Petzy app for iOS. There are four
of them, and none of them repeats the README.

| Document | What it covers |
| --- | --- |
| [architecture.md](architecture.md) | The layers of the app, the path a request takes through them, the decisions that are not obvious and the boundaries between them. |
| [screenshots/README.md](screenshots/README.md) | Why the folder holds no picture of the interface, and how to take one. |
| [PORT-PLAN.md](PORT-PLAN.md) | The inventory of the 48 web routes and the 11 stages they were ported in. |
| [USER-CASES.md](USER-CASES.md) | What a person can do in the app, and the test that covers each case. |
| [../README.md](../README.md) | The front door: what the app does and how to run it. |
| [../PRODUCT.md](../PRODUCT.md) | The product record: the users, the purpose and the principles the port is held to. |

## Reading order

New here: [../README.md](../README.md), then
[architecture.md](architecture.md). The README gives you the commands and
the capabilities, the architecture gives you the layers behind them.

Changing the code: [architecture.md](architecture.md), then
[../AGENTS.md](../AGENTS.md) for the traps. The traps in this project are
mostly SwiftUI behaviours that cost a rebuild to learn, and several of them
are the reason a screen looks the way it does.
