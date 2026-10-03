dele# quick_brew

QuickBrew — a Flutter ordering app for two coffee shops, with an admin side for
whoever runs them.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Before you deploy: push the Firestore rules

```
firebase deploy --only firestore:rules
```

**The test suite cannot tell you whether you have done this.** Every test runs
against `fake_cloud_firestore`, which does not evaluate `firestore.rules` at
all — it answers every read and write as though the rules admitted it. So the
suite passes identically whether the deployed rules are current, stale, or the
default deny-everything a fresh project starts with. There is no red test
anywhere for the failures below; the app simply behaves differently on a device
than it does in CI.

Three of the rules exist because the feature above them broke without one. Each
fails in a way that does not look like a permissions problem, which is what
makes this checklist worth reading rather than assuming:

| Block in `firestore.rules` | What it lets happen | What a stale deploy looks like |
|---|---|---|
| `orders/{order}` — `allow create` | Placing an order from the last step of the wizard | Every confirmed order comes back "could not place that order". `write: if false` was correct while nothing called it, so a rules file predating the wizard silently breaks all ordering. |
| `shops/{shop}/addons/{addOn}` — `allow read` | The wizard's customise step showing what a shop adds to a drink | The step draws **no add-ons at all**, for either shop, and says nothing. `BrewCounter.addOns` logs and swallows a refused read, so it is indistinguishable from a shop that genuinely sells no extras. |
| `drafts/{uid}` | Save for later, and the Saved order card on Home | Save for later reports a failure, and no saved card ever appears. |

After deploying, the fastest way to confirm all three on a real build: place one
order end to end (that covers `orders` and `addons` — the customise step is on
the way), then save a second order and check the card is on Home.

### Why there are no automated rules tests

Testing these properly needs `@firebase/rules-unit-testing` against the Firestore
emulator: a Node toolchain and a `package.json` in what is otherwise a pure-Dart
project, plus a JDK for the emulator itself, plus a second test command for
anyone running the suite to know about. That was judged not worth it here.

The narrower reason is that it would not catch the failure this checklist is
actually about. An emulator test reads `firestore.rules` from the working tree,
so it verifies the file — and the file has never been the problem. The problem is
the file being right in the repo and never pushed to the project, which is a
deploy step, and no test of any kind sees it.
