# CoolBeans

An iOS app for logging coffee drinks. Browse a menu loaded from a REST API, customize a drink, and track caffeine and calories. Works offline.

Built with SwiftUI, `URLSession` async/await and `Codable`. No third-party dependencies. Requires iOS 17+ and Xcode.

## Features

- **Menu from an API:** drinks, milk options and syrup options are fetched at launch. Shows a loading spinner, and an error with a Retry button if the first load fails.
- **Search grid:** searchable grid of drinks. Favorites (marked with ★) are listed first.
- **Customize form:** size, extra shots (0 to 4), decaf toggle, milk and syrup. Caffeine and calorie estimates update live.
- **Home screen:** today's caffeine and calories, a 7-day caffeine chart, and servings grouped by day.
- **Swipe actions:** swipe right to repeat a serving, left to delete it.
- **Edit:** tap a serving to reopen the customize form with its values.
- **Daily limit:** today's caffeine turns red above 400 mg (`limit` in `HomeView.swift`).
- **Reminder:** optional daily 2 PM "caffeine cutoff" notification.
- **Offline:** the menu, servings and favorites are cached as JSON in the Documents directory. Changes made offline are queued and sent when the server is reachable.

## How it works

1. The app opens and `Menu` shows the cached menu, then refreshes it from the API.
2. The user picks a drink, customizes it and taps Save.
3. `History` stores the serving locally and queues a `POST /servings`.
4. The queue is sent right away, and again on app launch and whenever the app returns to the foreground.
5. The home screen and totals update from `History`.

## Project layout

```
CoolBeans/
  CoolBeansApp.swift   App entry. Creates Menu and History, triggers sync.
  Models.swift         Drink, Option (milk/syrup), MenuData, Size, Serving.
  API.swift            URLSession calls. Base URL is set here.
  Store.swift          Load/save JSON files in Documents.
  Menu.swift           Menu loading, caching, loading/error state.
  History.swift        Servings, favorites, sync queue.
  HomeView.swift       Totals, chart, day sections, swipe actions, edit.
  MenuView.swift       Search grid, loading and retry UI.
  CustomizeView.swift  Option form, live estimates, save/edit, favorite.
  Reminder.swift       Daily notification.
mock_server.py         Local mock of the API for development.
project.yml            XcodeGen spec. Generates CoolBeans.xcodeproj.
```

## API

The base URL is `API.base` in `API.swift` (currently `http://localhost:8000`).

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/drinks` | `[{id, name, caffeine, calories}]` (medium size values) |
| GET | `/milks` | `[{id, name, calories}]` |
| GET | `/syrups` | `[{id, name, calories}]` |
| POST | `/servings` | Log or update a serving (JSON body, upsert by `id`) |
| DELETE | `/servings/{id}` | Remove a serving |

A serving is `{id, date, drink, size, shots, decaf, milk, syrup, caffeine, calories}`.

## Run it

1. Install Xcode, including an iOS simulator runtime (Xcode > Settings > Components).
2. Start the mock server: `python3 mock_server.py` (port 8000, data kept in memory).
3. Open `CoolBeans.xcodeproj`, pick a simulator and press Cmd + R.

To use a real backend, change `API.base`. Plain `http` is only allowed for local networking (`NSAllowsLocalNetworking` in `project.yml`), so use `https` in production.

After adding or removing Swift files, regenerate the project with `xcodegen` (`brew install xcodegen`).

## Estimate formulas

These are rough estimates, set in `CustomizeView.swift`:

- Size scale: small 0.75, medium 1, large 1.25.
- Each extra shot adds 75 mg caffeine and 5 kcal.
- Decaf keeps about 3% of the caffeine.
- Calories add the chosen milk and syrup calories.

## Known limits

- **Sync queue:** it stops at the first failure. One item the API permanently rejects blocks the items behind it. Add skip or backoff logic if your API can reject items.
- **Edit:** only drinks still on the menu can be edited.
- **Mock server:** it keeps data in memory only, and the repeat/edit flows rely on its upsert-by-id behavior.
- **No tests.**
