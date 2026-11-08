# FaceUpAgents Mobile

Native Android AI assistant (Flutter) built to match the supplied design mockups.
Package: `com.satira.faceup_agents` · Version: `0.0.1+1` (beta) · License: MIT

## Features

- **Chat** with real providers: OpenAI (Responses API), Anthropic (Messages API),
  Google (Gemini generateContent / interactions), Polza.ai (chat + media).
- **Media generation tools**: the text model can call `generate_image` /
  `generate_video`; results are saved locally, shown in chat and survive restarts.
- **Image resolution** selector (1K / 2K / 4K) for the Image-Generation category.
- **One-tap API refresh**: re-fetches model catalogs for all connected categories
  using the stored keys.
- **Stop button**: cancels a running generation, keeps already generated media,
  and blocks late provider results from overwriting the stopped message.
- Web search (incl. deep search with citations), reasoning levels, reasoning and
  source disclosures in messages.
- Chat persistence in SQLite, API keys in secure storage, partial media saved
  while a generation is still running, interrupted-generation recovery.
- EN / RU / ES localization, light / dark / system theme, Inter font.

## Project layout

```
lib/
  core/         models, localization strings, theme
  data/         SQLite chat store, settings store
  services/     providers (openai, anthropic, google, polza), chat service,
                media store, http utils
  state/        app-level state: generation jobs, cancellation, API refresh
  ui/           screens (api, chats, settings, chat) and widgets
test/           unit tests (providers, generation jobs, persistence, l10n)
```

## Build

```
flutter pub get
flutter test
flutter build apk --release
```

The release APK is not committed to keep the repository lean — grab the latest
artifact from GitHub Releases.

## Notes

- API keys are stored per provider on the device (flutter_secure_storage) and
  are never included in the repository.
- `заготовки/` and `design_ref/` are local design references and are ignored.
