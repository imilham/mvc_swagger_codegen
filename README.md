```markdown
# mvc_swagger_codegen

A powerful, pure-Dart command-line tool designed to instantly scaffold Provider-based MVC architecture and API controllers directly from a standard `swagger.json` (OpenAPI) specification. 

Stop writing boilerplate. Let the generator enforce clean architecture and eliminate technical debt.

## 🚀 Features

* **Zero-Dependency CLI:** Runs entirely on Dart. Does not require the heavy Flutter SDK to execute.
* **Provider MVC Architecture:** Automatically generates Models, Views, and Controllers tailored for `ChangeNotifier` and the Provider ecosystem.
* **Strict Typing:** Parses OpenAPI specifications to generate mathematically sound Dart models.
* **Rapid Scaffolding:** Turns massive backend API specs into clean, structured Dart files in milliseconds.

## 📦 Installation

This tool is a development dependency. **Do not** install this in your standard dependencies, or you will bloat your production build.

Run this command in the root of your Flutter project:

```bash
dart pub add dev:mvc_swagger_codegen

```

## 🛠️ Usage

**Step 1:** Obtain your backend's `swagger.json` or `openapi.json` file and place it somewhere in your project (e.g., in a `tools/` or `api_specs/` folder).

**Step 2:** Execute the generator from the root of your project by passing the relative path to your JSON file.

```bash
dart run mvc_swagger_codegen tools/swagger.json

```

## 📂 The "Staging" Workflow

To prevent accidentally overwriting your custom code, this tool uses a non-destructive staging pattern.

When you run the command, it will create a new folder in your root directory called `generated_api/`.
Inside, you will find the complete, scaffolded Provider architecture:

```text
generated_api/
 ├── models/
 ├── controllers/
 └── services/

```

**Your Job:** Review the generated files, take exactly what you need, and move them into your main `lib/` architecture. This gives you the benefit of instant boilerplate without sacrificing control over your project structure.

## ⚠️ Requirements

* Dart SDK `^3.11.0`
* A valid `swagger.json` (OpenAPI 3.0+) file.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](https://www.google.com/search?q=LICENSE) file for details.

```

***

Run your `dart pub publish --dry-run` one last time to ensure it catches the updated file. If it passes, deploy it. Execute it and move on to writing the actual model generation logic.

```