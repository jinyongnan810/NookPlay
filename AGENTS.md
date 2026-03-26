# AGENTS.md

## Purpose
This repository contains a SwiftUI application.  
When making changes, prioritize readability, maintainability, and safety over cleverness or unnecessary abstraction.

## General coding rules
- Write clear, simple, and production-friendly Swift code.
- Prefer straightforward solutions over overly abstract designs.
- Keep files and types focused on a single responsibility.
- Avoid introducing new dependencies unless clearly justified.
- Preserve existing architecture unless there is a strong reason to improve it.
- Do not make broad refactors unless they are required for the task.

## Readability and comments
- Always leave detailed comments for reading.
- Write comments with the assumption that another developer will read this code later without prior context.
- Explain:
  - why the code exists
  - the intent of non-obvious logic
  - important state transitions
  - edge cases and assumptions
  - framework or platform quirks
- Do not add useless comments that only restate the code literally.
- Prefer meaningful documentation comments (`///`) for public types, properties, and functions.
- For complex internal logic, add regular inline comments that explain the reasoning.

## SwiftUI guidelines
- Prefer small, composable views over very large view files.
- Extract repeated UI into reusable views or modifiers when it improves clarity.
- Keep `body` implementations readable and not overly nested.
- When a view becomes hard to scan, split parts into clearly named private computed properties or subviews.
- Use SwiftUI-native patterns first before falling back to UIKit.
- Avoid putting too much business logic directly inside SwiftUI views.
- Move non-UI logic into view models, helpers, or services when appropriate.

## Architecture preferences
- Favor simple MVVM-style separation when suitable for the feature.
- Views should focus on presentation and user interaction.
- View models should manage UI state and orchestrate calls to services.
- Services should handle data access, persistence, networking, or system APIs.
- Keep boundaries clear between UI code and business logic.
- Use dependency injection where practical, especially for testability.

## Naming
- Use descriptive names.
- Prefer full words over unclear abbreviations.
- Name views with nouns that describe what they render.
- Name actions and methods with verbs that describe what they do.
- Name booleans so they read clearly at call sites, such as `isLoading`, `hasPermission`, or `canSubmit`.

## Error handling
- Handle errors explicitly where possible.
- Avoid silent failures unless there is a good UX reason.
- When swallowing an error intentionally, leave a comment explaining why.
- Surface user-facing errors in a clear and non-technical way.
- Log useful debugging context when appropriate.

## Async and concurrency
- Prefer Swift concurrency (`async/await`) over older callback-based approaches when possible.
- Keep async flows readable and well-structured.
- Be explicit about main-thread UI updates.
- Avoid starting unnecessary tasks in views.
- Document concurrency assumptions when they are not obvious.

## State management
- Keep state as local as possible.
- Avoid duplicating derived state.
- Prefer a single source of truth for important UI state.
- Document tricky synchronization or lifecycle behavior.

## File organization
- Keep related code grouped logically.
- Use `// MARK:` sections to improve navigation.
- Suggested section order for Swift types when applicable:
  1. public API
  2. stored properties
  3. initialization
  4. body
  5. helpers
  6. private subviews
- Do not let files grow without reason. Split them when doing so improves readability.

## Previews
- Add or update SwiftUI previews when it meaningfully helps understand the view.
- Keep previews simple and useful.
- Include multiple states when helpful, such as loading, error, empty, and populated.

## Testing
- Prefer code that is easy to test.
- Add or update tests for non-trivial logic when appropriate.
- For bug fixes, consider adding a test that covers the regression.
- Do not add fragile tests with little long-term value.

## Editing existing code
- Match the style of the existing codebase unless it is clearly harmful.
- Preserve behavior unless the task explicitly requires changing it.
- When changing a non-obvious implementation, update comments to reflect the new behavior.
- Do not remove useful comments unless replacing them with better ones.

## Output expectations
When making changes in this repository:
- Leave detailed comments wherever the intent may not be obvious to a future reader.
- explain non-obvious choices
- avoid unnecessary complexity
- preserve maintainability for future readers
