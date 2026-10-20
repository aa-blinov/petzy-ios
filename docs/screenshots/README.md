# Screenshots

The folder holds no picture of the interface, and that is a deliberate
state rather than an oversight.

The repository carries one image, the app icon, and it sits one folder up
in `docs/app-icon.svg` because the README shows it there. Nothing shows
what the screens look like. The reason is in the tooling rather than in
the app: a simulator screenshot taken on the wrong display comes out solid
black, and the display has to be named with `--display=1` or the picture
says nothing about the app.

## Taking one

```bash
make run            # build, install and launch on the simulator
make shot           # a screenshot of the current screen
```

The simulator window is `DeviceHub.app` inside the Xcode bundle, and it
has to be started with the device UDID, otherwise the screen is black.
There are two displays, `LCD` is the real one and `LCD-1` stays black.

A screenshot of a screen with real data is the bar for calling a screen
done, next to the unit tests and a green `make ci`.

## Where one goes

When a picture is taken, it goes in this folder and the README points at it
by a relative path:

```markdown
![The feed](docs/screenshots/feed.png)
```

A relative path resolves both on GitHub and in a local checkout, and the
house-style checker verifies that every image reference points at a file
that exists, so a renamed picture cannot quietly break the README.
