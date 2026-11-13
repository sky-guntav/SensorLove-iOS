# Contributing

Thank you for wanting to make SensorLove better. Everyone here follows the [code of conduct](CODE_OF_CONDUCT.md).

## Start with an issue

Open an issue for a bug or an idea before writing code, so we can agree on it first. Keep each pull request small and about one thing.

## Working on it

- **The interface** is one page, `WebUI/home.html`. It also runs in a browser, without a phone: open it there to change it.
- **The app** is Swift, in `App/`. The Xcode project is not kept in the repo: make it from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`xcodegen generate`), then build it with Xcode 26 or later.
- **The website** is `site/`. `python site/build.py --serve` builds and serves it. The build also writes `docs/sensors.md` from the app's address table: when you change a sensor or its card, run it and commit that file with your change.
- Write code like the code around it: its naming, its comments, its idiom. Run the self-checks: the page's `console.assert`s show in the browser's console, and the Swift tests are in `Tests/`.

## Your contribution and its licence

By sending a contribution (a pull request or a patch), you confirm that:

1. It is your own work, or you have the right to give it.
2. It is licensed under the GNU GPL v3 with the [additional terms](ADDITIONAL-TERMS.md), like the rest of SensorLove.
3. You also give Göktuğ Güntav a permanent, worldwide, free and non-exclusive licence to use, change and publish it under other terms too. This lets SensorLove stay on the App Store, whose terms the GPL does not fit, and lets its licence change later. Your contribution stays yours, and everyone else still gets it under the GPL.
