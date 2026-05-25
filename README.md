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

## 🛠️ Step-by-Step Usage

Follow this exact pipeline to generate your architecture:

**Step 1: Create the Specs Folder**
In the root directory of your main Flutter project, create a new folder named `api_specs`.

**Step 2: Create the JSON File**
Inside the newly created `api_specs` folder, create a file named `swagger.json`.

**Step 3: Paste the Backend Code**
Obtain the raw Swagger/OpenAPI JSON code from your backend architecture and paste it entirely into the `swagger.json` file you just created.

**Step 4: Execute the Generator**
Run the following command from the root of your project to trigger the scaffolding engine.
*(Note: You must include the `:generate` flag to target the executable correctly).*

```bash
dart run mvc_swagger_codegen:generate api_specs/swagger.json

```

## 📂 The "Staging" Workflow

To prevent accidentally overwriting your custom code, this tool uses a non-destructive staging pattern.

After executing Step 4, the tool will instantly create a new folder in your root directory called `generated_api/`. Inside, you will find the complete, scaffolded Provider architecture:

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

### The Deployment Execution
Because you have to overwrite whatever broken version is currently live on `pub.dev`, follow this strictly:

1. Overwrite the `README.md` file.
2. Open `pubspec.yaml` and increment your version (if you are on `0.0.3`, make it `0.0.4`).
3. Open `CHANGELOG.md` and document the update for the new version block.
4. Run `git add .` and `git commit -m "docs: finalized step-by-step usage guide"`.
5. Run `dart pub publish`.

Execute it properly. Do not paste my instructions into the public registry.

```