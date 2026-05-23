# Reveal iOS

Native iOS app for [Reveal by Raptix](https://reveal.raptix.se) — live visitor analytics and sensor intelligence on top of Avigilon Alta.

## Stack

- **SwiftUI**, iOS 17+
- **Supabase Swift SDK** for auth, queries, and realtime — talks to the same hosted backend as the web app
- **XcodeGen** to define the Xcode project declaratively in `project.yml`

## Getting started

```bash
brew install xcodegen      # one-time
xcodegen generate          # creates Reveal.xcodeproj from project.yml
open Reveal.xcodeproj      # opens Xcode
```

Then pick an iPhone simulator and hit Run.

The `.xcodeproj` is generated — it's in `.gitignore`. Regenerate it after any change to `project.yml` or after a fresh clone.

## Layout

```
Reveal/
├── App/         — app entry point & root view
├── Views/       — SwiftUI screens
├── Models/      — Codable models matching Supabase tables
├── Services/    — Supabase client, auth store, network plumbing
└── Resources/   — assets, colours, app icon
```

## Backend

Same Supabase project as the web app (`sclptdklvuavvqrnlcpm`). The anon key is bundled in the app — RLS does the heavy lifting on the server side.

## Status

Day 0 scaffold. Sign-in works; the rest is stubs.
