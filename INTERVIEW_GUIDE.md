# CoolBeans: Interview Guide

Everything you need to explain this project from the first sentence to the hardest follow-up. Read parts 1 to 3 first, then use the Q&A in part 9 to practice out loud.

---

## 1. The 60-second pitch

> CoolBeans is an iOS app I built in SwiftUI for logging coffee drinks. The menu is not hardcoded: it is fetched from a REST API with URLSession and async/await and decoded into Codable models. Users search a grid of drinks, open a customize form (size, extra shots, decaf, milk, syrup) and see caffeine and calorie estimates update live. When they tap Save, the serving is stored locally and synced to the backend with a POST. The home screen shows today's totals, a weekly chart and a list grouped by day, with swipe actions to repeat or delete. Everything is cached as JSON in the Documents directory, so the app works offline, and changes made offline are queued and sent later.

Short version (20 seconds): "A SwiftUI coffee tracker with an API-driven menu, live estimates, local caching for offline use, and a retrying sync queue to the backend."

---

## 2. The problem and the design goals

- **Problem:** people want to know how much caffeine and how many calories they have had today, with custom drinks (size, shots, milk, syrup), not just a fixed list.
- **Goals:**
  1. Data-driven: the menu comes from a server so it can change without an app update.
  2. Fast and responsive: estimates update instantly as options change.
  3. Reliable: no lost drinks when the network fails.
  4. Simple code: minimal files, no third-party libraries, easy to read.

---

## 3. Architecture at a glance

```
                 ┌──────────────┐
                 │ CoolBeansApp │  creates Menu + History once,
                 └──────┬───────┘  injects them into the view tree
                        │ environmentObject
        ┌───────────────┼────────────────┐
        ▼                                ▼
   ┌─────────┐                     ┌───────────┐
   │  Menu   │                     │  History  │
   │ (menu   │                     │ (servings,│
   │  data)  │                     │ favorites,│
   └────┬────┘                     │ sync queue)│
        │                          └─────┬─────┘
        │ uses                           │ uses
        ▼                                ▼
   ┌─────────┐   ┌─────────┐        ┌─────────┐
   │   API   │   │  Store  │◄───────┤  Store  │
   │(network)│   │ (disk)  │        │ (disk)  │
   └─────────┘   └─────────┘        └─────────┘

Views: HomeView → MenuView → CustomizeView
```

It is a light MVVM style:

- **Model:** `Drink`, `Option`, `MenuData`, `Size`, `Serving` (all `Codable`).
- **View models (state holders):** `Menu` and `History`, both `ObservableObject`.
- **Views:** `HomeView`, `MenuView`, `CustomizeView`.
- **Services:** `API` (network) and `Store` (disk). They are plain enums with static functions, because they hold no state.

### File map

| File | Responsibility |
|------|----------------|
| `CoolBeansApp.swift` | App entry. Creates `Menu` and `History`, loads the menu, syncs when the app becomes active. |
| `Models.swift` | Data types. |
| `API.swift` | All network calls. |
| `Store.swift` | Read/write JSON files in Documents. |
| `Menu.swift` | Loads the menu, caches it, holds loading/error state. |
| `History.swift` | Servings, favorites, offline sync queue. |
| `HomeView.swift` | Totals, chart, day sections, swipe actions, edit sheet, reminder toggle. |
| `MenuView.swift` | Search grid, loading and retry UI. |
| `CustomizeView.swift` | Option form, live estimates, save and edit. |
| `Reminder.swift` | Daily local notification. |
| `mock_server.py` | Fake backend for development. |
| `project.yml` | XcodeGen config that generates the `.xcodeproj`. |

---

## 4. End-to-end flow (say it in this order)

1. **Launch:** `CoolBeansApp` creates `Menu` and `History` with `@StateObject`. `Menu` starts with the cached menu from disk (if any). `History` starts with servings, favorites and the pending queue from disk.
2. **Menu load:** `.task { await menu.load() }` runs. It calls `API.menu()`, which fetches `/drinks`, `/milks` and `/syrups` concurrently. On success the data is shown and cached. On failure, if there is no cache, the user sees an error and a Retry button. If a cache exists, the app stays quiet and uses it.
3. **Pick a drink:** `MenuView` shows a searchable `LazyVGrid`. Favorites are listed first.
4. **Customize:** `CustomizeView` holds the options in `@State`. A computed property `serving` recalculates caffeine and calories from the current options. Because SwiftUI re-renders when `@State` changes, the estimate is live with no extra code.
5. **Save:** `history.add(serving)` inserts the serving at the top of the list, adds it to the pending queue, writes both to disk, and calls `sync()`.
6. **Sync:** `sync()` sends queued POSTs and DELETEs. On success each item is removed from the queue.
7. **Home screen updates:** `History` is `@Published`, so `HomeView` re-renders. Totals, chart and day sections recalculate.

---

## 5. Concept-by-concept deep dive

### 5.1 SwiftUI state management

| Wrapper | Where | Why |
|---------|-------|-----|
| `@State` | `CustomizeView` (size, shots, decaf, milk, syrup), `HomeView` (`showMenu`, `editing`), `MenuView` (`search`) | Local, view-owned value. Changing it re-renders the view. |
| `@StateObject` | `CoolBeansApp` (`Menu`, `History`) | The view creates and owns a reference-type object. It survives re-renders, so it is created once. |
| `@EnvironmentObject` | `HomeView`, `MenuView`, `CustomizeView` | Reads a shared object injected higher up. No need to pass it through every initializer. |
| `@Published` | inside `Menu` and `History` | Any change notifies views observing the object. |
| `@AppStorage` | `HomeView` (`reminder`) | A bool saved in `UserDefaults`, bound to the UI. Good for a simple preference. |
| `@Environment(\.scenePhase)` | `CoolBeansApp` | Detects foreground/background to trigger a sync. |

Key idea: **single source of truth.** There is one `History` and one `Menu`. Views never copy this data; they read it and call methods on it.

`@StateObject` vs `@ObservedObject`: `@StateObject` owns the object's lifetime, `@ObservedObject` only observes an object owned elsewhere. Using `@ObservedObject` for an object you create inside the view would recreate it on every re-render and lose state.

### 5.2 Networking with URLSession and async/await

```swift
static func get<T: Decodable>(_ path: String) async throws -> T {
    let (data, response) = try await URLSession.shared.data(from: base.appending(path: path))
    try check(response)
    return try JSONDecoder().decode(T.self, from: data)
}
```

- `async throws`: the function can suspend while waiting for the network and can throw errors. The caller uses `try await`.
- **Generic:** one `get<T: Decodable>` serves drinks, milks and syrups. The return type decides what gets decoded.
- **Status check:** `URLSession` does not throw on HTTP 404 or 500. It only throws on transport errors. So `check` throws `URLError(.badServerResponse)` when the status code is 300 or higher.
- **Concurrency with `async let`:**

```swift
async let drinks: [Drink] = get("drinks")
async let milks: [Option] = get("milks")
async let syrups: [Option] = get("syrups")
return try await MenuData(drinks: drinks, milks: milks, syrups: syrups)
```

  All three requests start at the same time. The total time is about the slowest one, not the sum of the three. If one fails, the whole call throws.
- **Why async/await instead of completion handlers:** linear, readable code, normal `try/catch` error handling, no callback nesting, and structured concurrency (child tasks are cancelled with the parent).
- **POST and DELETE:** build a `URLRequest`, set `httpMethod`, set `Content-Type: application/json`, encode the body with `JSONEncoder`.

### 5.3 Codable and JSON

- `Drink`, `Option`, `MenuData`, `Serving` conform to `Codable` (= `Encodable` + `Decodable`). Swift generates the encode/decode code automatically when property names match JSON keys.
- `Serving` has default values (`id = UUID()`, `date = Date()`), so it can be created without them and still encode them.
- `Size` is a `String` enum with `Codable`, so it is stored as `"small"`, `"medium"` or `"large"`.
- `Date` uses the default encoding (a number of seconds). Simple, but the server must understand it. In production you would set an explicit strategy such as `.iso8601`.

### 5.4 Swift protocols used

| Protocol | Where | Why |
|----------|-------|-----|
| `Identifiable` | `Drink`, `Option`, `Serving` | `ForEach` and `sheet(item:)` need a stable `id`. |
| `Hashable` | `Drink`, `Option` | Needed as `Picker` tags and selection values. |
| `Equatable` | `Serving` | Lets the sync queue find and remove the exact serving that was sent (`firstIndex(of:)`). |
| `Codable` | all models | JSON and disk storage. |
| `ObservableObject` | `Menu`, `History` | Publishing changes to SwiftUI. |

### 5.5 Local persistence (offline support)

`Store` is two functions: `load<T: Decodable>` and `save<T: Encodable>`. Each key is one JSON file in the Documents directory (`URL.documentsDirectory`).

| File | Contents |
|------|----------|
| `menu.json` | Last fetched menu |
| `servings.json` | All logged servings |
| `favorites.json` | Set of favorite drink names |
| `pending.json` | Unsent POSTs and DELETEs |

- **Offline-first:** the app reads from disk first, then refreshes from the network. The UI never waits on the network to show something.
- **Why JSON files and not Core Data or SwiftData:** the data is small, flat and always loaded whole. Files are about 10 lines of code. Core Data/SwiftData would make sense with large data, relationships, queries or migrations.
- **Why Documents:** it is backed up and persists across launches. (Caches directory can be purged by the OS.)
- **Limitation:** writes are synchronous on the main thread and rewrite the whole file. Fine for hundreds of items; at thousands you would move to a database or background writes.

### 5.6 The sync queue (most important design topic)

Problem: if the POST fails because the user is offline, a naive version loses the drink on the server.

Solution (`History.swift`):

```swift
struct Pending: Codable { var posts: [Serving]; var deletes: [UUID] }
```

- Every `add` / `update` appends to `pending.posts`. Every `delete` appends to `pending.deletes`.
- The queue is saved to disk, so it survives app restarts.
- `sync()` sends items one by one. An item is removed only after the server accepts it.
- `sync()` runs on: every change, app launch, and returning to the foreground (`scenePhase == .active`).
- A `syncing` flag stops two syncs from running at once (no duplicate sends).

Details worth mentioning:

- **Optimistic UI:** the local list updates immediately; the network catches up later. The user never waits on the server.
- **Delete before send:** if you add a drink and delete it before it was ever sent, `delete` just removes it from `pending.posts`. No DELETE call is queued (`neverSent` check), because the server never heard of it.
- **Edit = upsert:** an edit re-queues the serving with the same `id`. The server is expected to overwrite by `id`. This is why the POST is called idempotent: sending it twice gives the same result.
- **`Equatable` use:** after a successful POST, the code removes that exact serving value from the queue. If the user edited the same serving during the request, the newer version stays queued.
- **Known weakness:** the loop stops at the first failure. If the server permanently rejects one item, it blocks everything behind it. Fix: skip items after N failures, or use exponential backoff and a dead-letter list.

### 5.7 Concurrency and the main actor

- `Menu` and `History` are marked `@MainActor`. All their state is touched only on the main thread, which is required for `@Published` properties that drive UI. It also avoids data races without locks.
- `Task { ... }` inside a main-actor method inherits the main actor. The `await` points suspend without blocking the UI.
- `.task { await menu.load() }` is a view modifier that starts async work when the view appears and cancels it when the view goes away. Prefer it over `onAppear` + `Task`.

### 5.8 Error and loading states

`Menu` exposes `data`, `loading` and `error`. `MenuView` decides what to show:

1. `data != nil` → show the grid (cached or fresh).
2. else `error != nil` → show the message and a Retry button (`Task { await menu.load() }`).
3. else → `ProgressView()`.

The cache rule: if a refresh fails but old data exists, the error is hidden. The user is not blocked by a flaky network.

### 5.9 Live estimates

In `CustomizeView`, `serving` is a computed property:

```
caffeine = (drink.caffeine × size.scale + shots × 75) × (decaf ? 0.03 : 1)
calories = drink.calories × size.scale + shots × 5 + milk.calories + syrup.calories
```

- Not stored: it is derived from state every time the body renders. This is the SwiftUI way (state in, view out).
- The saved `Serving` stores the computed `caffeine` and `calories`. Trade-off: history keeps the numbers that were true at the time (good if formulas change later), but it cannot be recalculated automatically.
- The numbers are rough estimates, not nutrition-label values.

### 5.10 Forms and pickers

- `Picker(selection: $milk)` with `milk: Option?`. For optional selection, each row needs a matching optional tag: `.tag(Optional($0))`, and "None" uses `.tag(Option?.none)`. A tag with the wrong type means the selection silently does nothing.
- `Stepper` with `in: 0...4` limits shots (input validation).
- `Toggle` for decaf. `Picker` with `.segmented` style for size.

### 5.11 Navigation and presentation

- `NavigationStack` (iOS 16+) replaces the old `NavigationView`.
- `NavigationLink` pushes `CustomizeView` from the grid.
- `.sheet(isPresented:)` shows the menu flow from Home. `.sheet(item:)` shows the edit form for a specific `Serving` (item must be `Identifiable`).
- A `done` closure is passed down so `CustomizeView` can close the whole sheet after saving. `@Environment(\.dismiss)` would only pop one level.

### 5.12 Lists, grid, search, swipe

- `LazyVGrid` with `GridItem(.adaptive(minimum: 140))` creates as many columns as fit, and loads cells lazily.
- `.searchable(text:)` adds the search bar; filtering is a plain `filter` with `localizedCaseInsensitiveContains`.
- `.swipeActions(edge: .leading)` = Repeat, `.trailing` = Delete (with `role: .destructive`).
- Days are grouped with `Set` of `startOfDay` dates, sorted descending; each day is a `Section`.

### 5.13 Swift Charts

`Chart { ForEach(week) { BarMark(...) }; RuleMark(y: limit) }` draws 7 bars (last 7 days) and a red line at the 400 mg limit. `unit: .day` makes the x-axis day-based. Charts is built into the SDK; no dependency.

### 5.14 Notifications

`UNUserNotificationCenter` with a `UNCalendarNotificationTrigger` (hour 14, repeats daily). Permission is requested only when the user turns the toggle on (good UX: ask in context). Turning it off removes the pending request by identifier.

### 5.15 App Transport Security (ATS)

iOS blocks plain `http` by default. The mock server uses `http://localhost:8000`, so `project.yml` sets `NSAllowsLocalNetworking = true`. This allows local networking only. A production API must use `https`.

### 5.16 Project tooling

- **XcodeGen:** `project.yml` describes the project; `xcodegen` generates `CoolBeans.xcodeproj`. Benefits: tiny, readable config, no merge conflicts in `project.pbxproj`, easy to recreate.
- **Mock server:** `mock_server.py` uses only Python's standard library (`http.server`). It implements the same endpoints as the real API so the app can be developed and demoed without a backend.

---

## 6. Data models

```swift
struct Drink:  Codable, Identifiable, Hashable { id, name, caffeine, calories }   // medium size
struct Option: Codable, Identifiable, Hashable { id, name, calories }             // milk and syrup
struct MenuData: Codable { drinks, milks, syrups }
enum   Size: String, Codable, CaseIterable { small, medium, large }               // scale 0.75 / 1 / 1.25
struct Serving: Codable, Identifiable, Equatable {
    id: UUID, date: Date, drink: String, size, shots, decaf, milk: String, syrup: String, caffeine, calories
}
```

Design choices to defend:

- **One `Option` type for milk and syrup:** they have the same shape. Two types would be duplicate code.
- **`Serving` stores names, not IDs or `Drink` objects:** a saved serving stays readable even if the menu changes. Downside: if a drink is renamed or removed it cannot be edited (the app checks this).
- **`id` is a client-generated `UUID`:** it lets the app create the record offline and lets the server upsert safely.

---

## 7. API contract

| Method | Path | Body | Response |
|--------|------|------|----------|
| GET | `/drinks` | none | `[Drink]` |
| GET | `/milks` | none | `[Option]` |
| GET | `/syrups` | none | `[Option]` |
| POST | `/servings` | `Serving` JSON | 2xx |
| DELETE | `/servings/{uuid}` | none | 2xx |

Requirement on the backend: POST must upsert by `id` (edit and retry depend on it).

---

## 8. Design decisions and trade-offs

| Decision | Why | Trade-off / alternative |
|----------|-----|-------------------------|
| JSON files for storage | Tiny, no setup | Not for large data. Use SwiftData/Core Data if it grows. |
| Two `ObservableObject`s | Clear split: menu data vs user data | Could use the new `@Observable` macro (iOS 17) for less boilerplate. |
| Services as static enums | No state, nothing to mock in a tiny app | Harder to unit test. Use a protocol and inject it for tests. |
| Optimistic local-first | Instant UI, works offline | Needs a sync queue and conflict thinking. |
| Last-write-wins sync | Simple | No conflict resolution across multiple devices. |
| Stop-on-first-failure queue | Preserves order, simple | One bad item blocks the rest. |
| Stored estimates | Historical numbers stay stable | Cannot recompute if formulas change. |
| No third-party libraries | Nothing to maintain or audit | You write small helpers yourself. |
| Local notification, not push | No server needed | Cannot react to server events. |

---

## 9. Interview Q&A

### Basics

**Q: Walk me through the project.**
Use the 60-second pitch in part 1, then offer to go deeper on networking, offline sync or state management.

**Q: Why SwiftUI instead of UIKit?**
Less code for forms, lists and live-updating UI. State drives the view automatically, which fits the live estimate feature. UIKit would give finer control but needs much more boilerplate for the same screens.

**Q: What is the minimum iOS version and why?**
iOS 17. I use `NavigationStack`, Swift Charts, `URL.documentsDirectory` and the two-parameter `onChange`, which are all available there.

**Q: Which architecture did you use?**
A light MVVM: models, `ObservableObject` state holders (`Menu`, `History`), and views. API and Store are separate service layers.

### State and SwiftUI

**Q: Difference between `@State`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject`?**
`@State`: simple value owned by one view. `@StateObject`: reference object created and owned by a view. `@ObservedObject`: reference object owned elsewhere and passed in. `@EnvironmentObject`: object injected at the top and read anywhere below without passing it through initializers.

**Q: Why is `History` created in the App struct?**
It must be one shared instance for all screens, and it must live as long as the app. `@StateObject` at the root guarantees it is created once.

**Q: How does the live estimate work?**
`serving` is a computed property based on `@State` values. When the user changes an option, the state changes, SwiftUI re-runs `body`, and the computed values update.

**Q: How does the home screen update after Save?**
`History.servings` is `@Published`. `add` modifies it, so every view observing `History` re-renders.

**Q: Why does `Picker` need `.tag(Optional($0))`?**
The selection is `Option?`. The tag type must match the selection type exactly. A non-optional tag would never match, so selection would not work.

**Q: How do you edit an existing serving with the same form?**
`CustomizeView` takes an optional `editing: Serving?`. Its `init` seeds the `@State` values from it. On save it keeps the original `id` and `date` and calls `history.update` instead of `add`.

**Q: What does `.task` do compared to `.onAppear`?**
`.task` runs async code and automatically cancels it when the view disappears. `.onAppear` needs a manual `Task` and no cancellation.

### Networking

**Q: How do you fetch data?**
`URLSession.shared.data(from:)` with `async/await`, then `JSONDecoder` into `Codable` models.

**Q: Why check the HTTP status yourself?**
`URLSession` only throws for transport failures. A 404 or 500 returns normally, so without a check the decoder would try to parse an error body.

**Q: What does `async let` do?**
Starts child tasks concurrently and waits for them together. The three menu requests run in parallel.

**Q: What happens if one of the three requests fails?**
The whole `API.menu()` throws. The app falls back to the cached menu if it exists; otherwise it shows the error with Retry. Improvement: fetch the three endpoints independently or use one `/menu` endpoint.

**Q: How would you add authentication?**
Add an `Authorization: Bearer <token>` header in one place (a shared request builder), store the token in the Keychain (never UserDefaults), and handle 401 by refreshing the token or logging out.

**Q: How would you handle timeouts and retries?**
Set `timeoutInterval` on the request (or a custom `URLSessionConfiguration`), and use exponential backoff for retries. Retry only idempotent requests (GET, upsert POST, DELETE).

**Q: How would you test networking?**
Put `API` behind a protocol or use a custom `URLProtocol` stub to return canned responses. Test success, a 500, bad JSON and offline.

### Offline and sync

**Q: How does the app work offline?**
It reads the menu and servings from JSON files on disk first. Writes go to disk immediately and into a pending queue that is saved to disk. The queue is sent when the network is back.

**Q: What happens if the app is killed while offline with unsynced drinks?**
`pending.json` is on disk. On next launch (and whenever the app becomes active) `sync()` sends it. Nothing is lost.

**Q: How do you avoid sending the same item twice?**
A `syncing` flag allows one sync at a time, and each item is removed from the queue only after success. If a request succeeds but the response is lost, the item is sent again, which is safe because the POST upserts by `id`.

**Q: What is idempotency and why does it matter here?**
An operation is idempotent if repeating it gives the same result. POST with a client-generated `id` that the server upserts is idempotent, so retries never create duplicates.

**Q: What conflicts can happen?**
If the same account is used on two devices, last write wins. A real fix needs versioning or timestamps (for example an `updatedAt` field and server-side merge).

**Q: Why not use Core Data or SwiftData?**
The data is small and always read whole. JSON files are far simpler. I would switch for large data sets, queries, relationships or migrations.

**Q: What are the weak points of your sync?**
It stops at the first failed item, so one permanently rejected item blocks the rest. There is no backoff, no user-visible sync status, and no conflict handling. Next step: attempt counters, backoff, a status indicator.

**Q: Why is deleting an unsent serving handled specially?**
The server never saw it, so sending DELETE would return 404 and could block the queue. The code just removes it from the pending posts.

### Data and design

**Q: Why UUIDs created on the client?**
Records can be created offline without asking the server for an id, and the same id is used for upserts and deletes.

**Q: Why does `Serving` store `caffeine` and `calories` instead of recomputing?**
So history stays stable if formulas or the menu change later. The cost is that old records do not update automatically.

**Q: Why does `Serving` store drink name as a string?**
It is self-contained and still readable if the menu changes. The downside is that renamed or removed drinks cannot be edited, so the edit action checks the drink still exists.

**Q: How are estimates calculated?**
Size scales base values (0.75, 1, 1.25). Each extra shot adds 75 mg caffeine and 5 kcal. Decaf keeps 3% of the caffeine. Milk and syrup add their calories. These are approximations.

**Q: How did you handle input validation?**
Shots are limited to 0 to 4 by the stepper range. Size, milk and syrup come from fixed lists, so free text never reaches the data. The decoder rejects malformed JSON from the server.

### Features

**Q: How does the daily limit work?**
Today's caffeine is compared to a constant (400 mg). If it is higher, the text turns red and the chart shows a red rule line.

**Q: How are servings grouped by day?**
Take the set of `startOfDay` dates from all servings, sort them newest first, and make a section per day filtered with `Calendar.isDate(_:inSameDayAs:)`. Dates use the user's current calendar and time zone.

**Q: How does the reminder work?**
A repeating local notification at 14:00 using `UNCalendarNotificationTrigger`. Permission is requested when the user turns the toggle on.

**Q: How do favorites work?**
A `Set<String>` of drink names saved to `favorites.json`. The menu puts favorites first and prefixes them with ★. It is stored on device only, not synced.

### Quality and improvement

**Q: Did you write tests?**
No tests yet. I would add unit tests for the estimate formula and for `History` (add, update, delete, queue behavior), plus a stubbed `URLProtocol` for `API`. The estimate logic is the first candidate because it is pure.

**Q: What would you improve with more time?**
1. Sync: backoff, attempt limits, status UI.
2. Move the estimate into a pure function with unit tests.
3. Use the `@Observable` macro and protocol-based services for testability.
4. Explicit date encoding (ISO 8601) and an `updatedAt` field for conflicts.
5. Accessibility labels, Dynamic Type checks, dark mode review.
6. Better error messages and a visible sync indicator.
7. Auth and HTTPS for production.

**Q: How would you scale this to thousands of servings?**
Move storage to SwiftData, paginate or window the list, aggregate daily totals in a query rather than recomputing in the view, and sync incrementally using a `since` timestamp.

**Q: How would you support multiple devices?**
A server as the source of truth, `GET /servings?since=` for pulling, `updatedAt` for merging, and tombstones for deletes.

**Q: What about accessibility?**
Standard controls (`Picker`, `Toggle`, `Stepper`, `List`) come with VoiceOver and Dynamic Type support. Remaining work: explicit accessibility labels for the chart and swipe actions, and a non-swipe way to delete or repeat.

**Q: What would you do about security and privacy?**
HTTPS only (ATS), tokens in the Keychain, no sensitive data in logs, and be clear about what health-related data is stored. Caffeine intake is personal health-adjacent data.

### Tooling

**Q: Why XcodeGen?**
It generates the Xcode project from a small YAML file, which avoids `project.pbxproj` merge conflicts and makes the project reproducible.

**Q: How did you develop without a backend?**
A small Python mock server with the same endpoints, using only the standard library. The app just points `API.base` at it.

**Q: Why did you need `NSAllowsLocalNetworking`?**
ATS blocks plain http. This key allows it for local network addresses only, which is enough for the mock server and does not weaken production traffic.

---

## 10. Tricky "gotcha" questions

- **"Your sync loop could run twice, how do you prevent that?"** The `syncing` boolean guard. Both calls happen on the main actor, so there is no race on the flag.
- **"What if a POST succeeds but the response never arrives?"** The item stays in the queue and is resent. Safe because the server upserts by `id`.
- **"What if the user edits a serving while it is being sent?"** `update` re-queues the new version. After the old request finishes, only that exact old value is removed (via `Equatable`), so the new version is still sent.
- **"Why is `History` marked `@MainActor`?"** It publishes UI state and mutates arrays. Keeping it on the main actor avoids data races without locks.
- **"Why not `@ObservedObject` in the App struct?"** The App must own the object's lifetime, which is `@StateObject`.
- **"Is the cache ever invalidated?"** The menu cache is replaced on every successful fetch. There is no expiry, so an offline user sees the last known menu indefinitely.
- **"What if the drink was removed from the menu?"** Existing servings remain (they store names). Editing is disabled for them.
- **"What does the decaf 3% mean?"** Decaf coffee still has a small amount of caffeine. 3% is an approximation, not an exact value.

---

## 11. Vocabulary cheat sheet

- **Optimistic update:** update the UI first, confirm with the server later.
- **Offline-first:** local storage is the primary source; the network is a sync layer.
- **Idempotent:** repeating the operation has the same effect as doing it once.
- **Upsert:** update if it exists, otherwise insert.
- **Single source of truth:** one owner of each piece of data.
- **Structured concurrency:** child tasks are tied to a parent scope and cancelled with it.
- **Main actor:** the actor that runs on the main thread; all UI work belongs there.
- **ATS:** App Transport Security, iOS's rule that network traffic should use HTTPS.
- **Computed property:** a value derived on demand rather than stored.
- **Tombstone:** a marker meaning "this item was deleted", used to sync deletions.

---

## 12. Demo script (2 minutes)

1. Open the app. Point out totals at 0 and the empty list.
2. Tap **+**. Menu loads (mention: API call, cached afterwards). Search "lat".
3. Open **Latte**. Change size, add a shot, toggle decaf. Show the estimate changing live.
4. Tap the star (favorite). Tap **Save**.
5. Home screen: totals and chart updated. Show the server log line `logged ...`.
6. Swipe right to repeat, swipe left to delete.
7. Tap a serving to edit it.
8. Stop the mock server, add a drink (it still saves). Restart the server and bring the app to the foreground. The queued drink syncs.
9. Mention the 400 mg limit turning the total red, and the 2 PM reminder.

---

## 13. How to run (for the demo)

1. `python3 mock_server.py`
2. Open `CoolBeans.xcodeproj` in Xcode, choose a simulator, press Cmd + R.
3. Regenerate the project after adding files: `xcodegen`.
