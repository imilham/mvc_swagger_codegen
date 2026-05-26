## 0.0.4

- Generated service classes now include `dispose()` to close the state stream controller.
- Added cleanup guidance to the generated service usage example.

## 0.0.3

- Added stronger static analysis compatibility by aligning lint setup for a pure Dart package.
- Improved generator warning output for endpoint names and renamed parameters.
- Fixed null-aware dead code warnings in the code generator internals.
- Applied code style updates for if-statements to satisfy brace enforcement rules.

## 0.0.2

- Improved generated API/model import handling for cleaner output structure.
- Added better handling for primitive schema refs in properties and array items.
- Refined operation method naming behavior and fallback logic.

## 0.0.1

- Initial release of mvc_swagger_codegen CLI.
- Generates MVC-style structure, models, and API controllers from Swagger/OpenAPI specs.
