# Repository Guidelines

## Project Structure & Module Organization

The repository is beginning a Flutter cross-platform audiobook application. Product decisions and constraints are recorded in `docs/PRODUCT_DECISIONS.md`; the planned architecture and layout are in `docs/ARCHITECTURE.md`. Flutter production code should live under `lib/`, platform integrations under `android/` and `linux/`, tests under `test/`, and static files under `assets/`. Group Dart modules by feature rather than by file type when that makes dependencies easier to follow.

## Build, Test, and Development Commands

Cloud builds and checks are intended to run in GitHub Actions. Once the project is scaffolded, the workflow should run `flutter pub get`, `flutter analyze`, and `flutter test`, then build with `flutter build appbundle` and `flutter build linux --release`. Local `flutter run -d linux` and wireless ADB remain useful for development and real-device validation. New contributors should run the checks locally when the SDK is available and rely on required CI checks before opening a pull request.

## Coding Style & Naming Conventions

Follow the formatter and linter selected by the project once they are introduced; avoid hand-formatting exceptions unless a rule is intentionally configured. Use four spaces for indentation unless the language ecosystem requires another standard. Prefer descriptive, feature-oriented names: `PascalCase` for types/components, `camelCase` for functions and variables, and `kebab-case` for directories or command names. Keep modules focused and avoid unrelated refactors.

## Testing Guidelines

No test framework or coverage threshold is configured yet. Add tests with each behavior change, naming them after the behavior they verify (for example, `parser_handles_empty_input`). Keep unit tests deterministic and place integration tests in a clearly marked suite. Update this section when the framework and required coverage target are chosen.

## Commit & Pull Request Guidelines

Git history is not available in the current scaffold, so no existing commit convention can be inferred. Use concise imperative subjects, ideally following Conventional Commits (for example, `feat: add book parser` or `fix: handle empty metadata`). Pull requests should explain the change, identify relevant tests or validation, link an issue when applicable, and include screenshots or sample output for user-facing changes.

## Configuration & Security

Do not commit credentials, private keys, or local environment files. Keep secrets in environment variables or an approved secret store, and provide a safe example configuration such as `.env.example` when configuration is introduced. Review generated files and dependency changes before committing.
