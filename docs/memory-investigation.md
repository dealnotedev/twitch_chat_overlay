# Windows memory investigation — 2026-09-18

The reported near-1-GiB process was the Debug executable launched from the IDE.
Measurements on the user's Windows machine isolated the larger contribution
to the default Impeller graphics backend on its integrated AMD GPU.

| Configuration | Working set (MiB) | Private bytes (MiB) | Shared GPU allocation (MiB) | Dedicated GPU allocation (MiB) |
| --- | ---: | ---: | ---: | ---: |
| Original running Debug, default renderer | 1033 | 996 | 578 | not sampled |
| Fresh Release, default renderer | 829.2 | 845.7 | 586.1 | 80.2 |
| Fresh Release, Skia | 210.2 | 221.9 | 105.0 | 10.3 |

The Debug figures were sampled at different points during diagnosis, not in
one atomic snapshot. The desktop/window was 1646 × 1029. Release comparisons
used the same settings and application code except for the renderer switch.
Chat history can differ after reconnecting; this was a short startup comparison,
not a long-running workload benchmark. GPU allocation counters and process RAM
counters overlap and must not be added together.

## Evidence

- `Get-Process`: working set and private bytes.
- Windows `GPU Process Memory` counters: shared and dedicated GPU allocations.
- Dart VM Service `getMemoryUsage`, `getAllocationProfile`, and
  `getProcessMemoryUsage` on the original Debug process: main isolate heap about
  117 MiB, six `ChatUserMessage` objects, no `ChatGifProvider` or
  `_ChatPlaybackImageState` instances. A full GC did not materially lower RAM.
- Debug additionally mapped an approximately 83-MiB `kernel_blob.bin`; its VM
  report included roughly 164 MiB of VM heaps and diagnostic structures.

These measurements rule out accumulated messages or GIFs as the explanation
for this particular near-1-GiB observation. They do not establish an internal
Impeller/driver allocation cause or prove there are no separate long-session
retention issues.

## Fix and verification

`windows/runner/main.cpp` selects
`flutter::ImpellerSwitch::Disabled`, using Flutter's supported Windows Skia
fallback. See the [Flutter renderer documentation](https://docs.flutter.dev/perf/impeller#windows).
This preserves hardware acceleration and the existing chat functionality.

- `flutter build windows --release --no-pub`: passed.
- `flutter analyze lib test --no-pub`: passed.
- Restarted the application into the fixed Release and sampled its RAM/GPU
  counters: working set approximately 75% lower than the default Release.
- Whole-repository `flutter analyze --no-pub` was blocked by unresolved
  dependencies in the separate, uninitialized `updater` package. That package
  was not changed. During 1.3.3 release preparation, running `flutter pub get`
  in `updater` resolved this setup issue; whole-repository analysis then passed.

The session timeline remains intentionally unlimited. Finite GIF playback also
keeps offscreen rows alive to preserve playback progress. These are separate
long-session memory risks; neither was responsible for the measured incident.
