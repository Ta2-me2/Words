# Validation and performance — 2.2

All 27 tests passed. They cover both fixed directions and mixed mode, mixed-mode validation on both sides, direction stability on retries, per-Deck scopes, lifetime accuracy calculations, pause/resume identity, durable progress, failed writes and retries, deduplication, terrain contact and scene reuse.

Rendering retains the optimized 428-entity scene: static batching, 24 recycled terrain tiles, 128 pooled particles, and no geometry generation during answer crossings. The menu and statistics share that scene. Deck changes at the same level reuse geometry. No FPS overlay is included.

The deterministic level-9 Debug scenario advances 3,000 steps and crosses 19 questions. The latest measured CPU callback p95 was 0.560 ms and maximum answer-frame callback 1.975 ms. This excludes GPU work, UI composition and host callbacks, so it is not an FPS guarantee.

Manual Release checks: empty Deck selection disables Start; the host shell imports an explicitly selected Deck JSON; only its supplied folder appears in the selector; Mixed directions is selectable; gear opens both settings; Escape opens the main menu with Continue game; resume preserves the question and lives. Gameplay controls are ordered Pause, Volume, Menu. The integration sample and storage schema are documented in README and Integration.md.

```sh
swift test
./Scripts/build-app.sh release
./Scripts/package-sdk.sh
```

The archive contains source, documentation, an explicitly loadable sample JSON and the demo app, but no learner progress. Host persistence must stay asynchronous; callbacks execute on MainActor.

## 2.2.1 host appearance regression

An NSHostingView/NSWindow regression checks the library inside a light host and standalone gameplay inside a dark host, including navigation back to a host-only screen. A positive control confirms that window-level appearance preferences are observable by the test. Both game views now scope their appearance locally. The supplied icon is packaged into standard ICNS sizes without altering the source artwork.
