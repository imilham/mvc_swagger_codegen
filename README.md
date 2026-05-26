# mvc_swagger_codegen

`mvc_swagger_codegen` is a pure-Dart command-line tool that scaffolds Provider-friendly MVC code from a Swagger/OpenAPI JSON document.

It is designed to reduce repetitive boilerplate while keeping the generated output easy to review, copy, and adapt inside your app.

## Features

- Pure Dart CLI with no Flutter SDK required to run the generator.
- Generates repositories, services, models, and controller-friendly state helpers.
- Supports typed model generation from OpenAPI schemas.
- Produces organized output that can be moved into an existing app structure.
- Keeps generated service state streams disposable and lifecycle-safe.

## Installation

Add the package as a development dependency in the project that will run the generator:

```bash
dart pub add dev:mvc_swagger_codegen
```

You can also add it manually to `dev_dependencies` in `pubspec.yaml`.

## Usage

1. Place your Swagger/OpenAPI JSON file in your project, for example at `api_specs/swagger.json`.
2. Run the generator from the root of the project that contains the spec file:

```bash
dart run mvc_swagger_codegen:generate api_specs/swagger.json
```

The generator reads the specification and writes the scaffolded output into the generated API folder used by the tool.

## Generated Output

The generated code is organized to separate responsibilities clearly:

- `models/` for data classes
- `controllers/` for UI-facing state and actions
- `services/` for repository and API access logic

The service layer includes a state stream and a `dispose()` method so stream resources are closed cleanly when the service is no longer needed.

## Example Workflow

```text
your_project/
├── api_specs/
│   └── swagger.json
└── generated_api/
	├── models/
	├── controllers/
	└── services/
```

Review the generated files, move the pieces you want into your app, and keep the parts that fit your architecture.

## Requirements

- Dart SDK `^3.11.0`
- A valid OpenAPI 3.0+ `swagger.json` file

## Versioning

This package follows standard semantic versioning. Check the [CHANGELOG.md](CHANGELOG.md) for release notes.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.