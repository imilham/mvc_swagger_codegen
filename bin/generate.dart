// ignore_for_file: avoid_print, cascade_invocations
/// Swagger → Clean Architecture Code Generator
///
/// Usage:
///   dart run tools/swagger_codegen.dart <swagger.json> [--dry-run]
///
/// Generates:
///   - Models              → lib/data/models/
///   - Datasource Ifaces   → lib/data/datasources/
///   - Datasource Impls    → lib/data/datasources/
///   - Repo Interfaces     → lib/domain/<group>/repos/
///   - Repo Impls          → lib/data/repositories/ (delegation)
///   - Entity Barrels      → lib/domain/<group>/entities/
///   - Usecases (stubs)    → lib/domain/<group>/usecases/
///   - Endpoints           → lib/utils/network/endpoints.dart
///   - Barrel exports      → lib/data/data.dart & lib/domain/domain.dart
///   - DI registration     → lib/core/di/injection_container.dart
library;

import 'dart:convert';
import 'dart:io';

// ─── Configuration ────────────────────────────────────────────────────────────

/// Swagger definition names that should be renamed in Dart to avoid conflicts.
const Map<String, String> definitionRenames = {
  'File': 'MediaFile',
  'Duration': 'GameDuration',
  'ApiError': 'ApiErrorEntity',
  'RegisterRequest': 'RegisterApiRequest',
  'LoginRequest': 'LoginApiRequest',
  'AuthPostRegisterRequest': 'AuthPostRegisterApiRequest',
  'AuthPostLoginRequest': 'AuthPostLoginApiRequest',
};

/// Specific method name overrides. key: "path:method" or "operationId".
const Map<String, String> methodRenames = {
  '/profile:get': 'myProfile',
  '/profile:post': 'updateProfile',
  '/delete-profile:post': 'deleteUserAccount',
  '/profile/deactivate:post': 'deactivateUserProfile',
};

/// Maps a Swagger tag to one or more group names.
/// Tag lookup is case-insensitive — only one casing needed per tag.
const Map<String, List<String>> tagGroupsMapping = {
  'Profile': ['profile', 'user'],
  'Delete and deactivate account': ['profile', 'user'],
  'OAuth Authentication': ['auth'],
  'ForgotPassword': ['auth'],
  'SettingsAPI': ['settings'],
};

/// Maps the first path segment (e.g. 'profile' from '/profile/xyz') to a group.
/// This acts as an override if tags are inconsistent or missing.
const Map<String, List<String>> pathSegmentGroupsMapping = {
  'profile': ['profile', 'user'],
  'delete-profile': ['profile', 'user'],
  'delete-user': ['profile', 'user'],
};

/// Additional methods to add to repository interfaces (not in Swagger).
const Map<String, List<String>> manualRepositoryMethods = {};

/// Custom import paths for definitions that are manually excluded or reside elsewhere.
/// If a definition is listed here, this exact import string will be used.
/// Use '{pkg}' as a placeholder for the package name (read from pubspec.yaml).
const Map<String, String> customImportPaths = {
  'Paginator': 'package:{pkg}/utils/utils.dart',
};

/// Groups to SKIP generation for (already implemented manually).
const Set<String> skipGroups = {};

/// Models to SKIP generation for (already implemented manually).
const Set<String> skipDefinitions = {'Paginator'};

/// Maps Swagger definition names to a specific group, overriding dynamic discovery.
/// This is crucial for models like `User` that belong to `profile` but are referenced everywhere.
const Map<String, String> definitionToGroup = {
  'User': 'profile',
  'Device': 'auth',
};

/// Maps model names to a map of field names and their alternative JSON keys.
/// This is used to handle "flattened" API responses where a field might be
/// returned at the top level instead of inside a nested object.
const Map<String, Map<String, List<String>>> flattenedFields = {
  'Product': {
    'id': ['product_id'],
    'name': ['product_name'],
    'price': ['product_price'],
    'image': ['product_image'],
  },
};

/// Dependencies for repository implementations.
/// Group name (PascalCase) -> List of dependencies {type, name, required}
const Map<String, List<Map<String, String>>> repoDependencies = {
  'Auth': [
    {
      'type': 'IAuthLocalDataSource',
      'name': 'localDataSource',
      'required': 'true',
    },
  ],
};

/// Primitive type names that Swagger may reference via `$ref`.
/// When seen as a `$ref`, these are treated as plain Dart types, not models.
const Set<String> _primitiveRefs = {
  'string',
  'String',
  'integer',
  'Integer',
  'int',
  'number',
  'Number',
  'double',
  'boolean',
  'Boolean',
  'bool',
  'object',
  'Object',
};

// ─── Main ─────────────────────────────────────────────────────────────────────

void main(List<String> args) async {
  final swaggerPath = args.isNotEmpty && !args[0].startsWith('-')
      ? args[0]
      : 'tools/swagger.json';
  final dryRun = args.contains('--dry-run');

  Map<String, dynamic> json;

  if (swaggerPath.startsWith('http://') || swaggerPath.startsWith('https://')) {
    print('🌐 Fetching Swagger spec from URL: $swaggerPath');
    try {
      final content = await _fetchSwaggerSpec(swaggerPath);
      json = jsonDecode(content) as Map<String, dynamic>;
      // Cache it locally even if it's from URL
      if (!dryRun) {
        File('tools/swagger.json').writeAsStringSync(content);
        print('💾 Spec cached to tools/swagger.json');
      }
    } catch (e) {
      print('❌ Error fetching Swagger spec: $e');
      exit(1);
    }
  } else {
    final file = File(swaggerPath);
    if (!file.existsSync()) {
      print('❌ Error: File not found: $swaggerPath');
      exit(1);
    }
    json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  // Version Detection
  final openApiVersion = json['openapi']?.toString();

  if (openApiVersion != null && openApiVersion.startsWith('3.')) {
    print(
      '\n⚠️  WARNING: OpenAPI 3.x spec detected (version $openApiVersion).',
    );
    print('   This generator is currently optimized for Swagger 2.0.');
    print(
      '   Some complex schemas (allOf/oneOf) may not generate correctly.\n',
    );
  }

  final swagger = SwaggerSpec.fromJson(json);
  final packageName = _readPackageName();

  print('═══════════════════════════════════════════════════════════');
  print(' Swagger → Clean Architecture Code Generator');
  print(' Title:   ${swagger.title}');
  print(' Version: ${swagger.version}');
  print(' Base:    ${swagger.basePath}');
  print(' Package: $packageName');
  if (dryRun) print(' Mode:    DRY RUN (no files will be written)');
  print('═══════════════════════════════════════════════════════════\n');

  if (!dryRun) {
    _ensureRxDartDependency();
  }

  final generator = CodeGenerator(
    swagger: swagger,
    dryRun: dryRun,
    packageName: packageName,
  );
  generator.run();
}

/// Ensures `rxdart` is added as a dependency in `pubspec.yaml`
void _ensureRxDartDependency() {
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) return;

  final content = pubspecFile.readAsStringSync();
  if (!content.contains('rxdart:')) {
    print('📦 rxdart dependency not found. Adding rxdart...');
    final result = Process.runSync('flutter', ['pub', 'add', 'rxdart']);
    if (result.exitCode != 0) {
      print('⚠️ Failed to add rxdart: ${result.stderr}');
    } else {
      print('✅ rxdart added successfully.');
    }
  }
}

/// Reads the `name` field from pubspec.yaml to use as the package name in imports.
String _readPackageName() {
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    print('⚠️  pubspec.yaml not found, defaulting package name to "app"');
    return 'app';
  }
  final content = pubspecFile.readAsStringSync();
  final match = RegExp(r'^name:\s*(.+)$', multiLine: true).firstMatch(content);
  if (match == null) {
    print('⚠️  Could not read "name" from pubspec.yaml, defaulting to "app"');
    return 'app';
  }
  return match.group(1)!.trim();
}

/// Fetches spec from URL using HttpClient (no external dependencies required)
Future<String> _fetchSwaggerSpec(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to fetch spec (Status: ${response.statusCode})',
      );
    }
    final content = await response.transform(utf8.decoder).join();
    return content;
  } finally {
    client.close();
  }
}

// ─── Swagger Parsing ──────────────────────────────────────────────────────────

class SwaggerSpec {
  SwaggerSpec({
    required this.title,
    required this.version,
    required this.basePath,
    required this.paths,
    required this.definitions,
  });

  factory SwaggerSpec.fromJson(Map<String, dynamic> json) {
    final info = json['info'] as Map<String, dynamic>? ?? {};
    final paths = <String, Map<String, SwaggerOperation>>{};
    final pathsJson = json['paths'] as Map<String, dynamic>? ?? {};

    for (final entry in pathsJson.entries) {
      final methodMap = <String, SwaggerOperation>{};
      final methods = entry.value as Map<String, dynamic>;
      for (final methodEntry in methods.entries) {
        methodMap[methodEntry.key] = SwaggerOperation.fromJson(
          methodEntry.value as Map<String, dynamic>,
          path: entry.key,
          method: methodEntry.key,
        );
      }
      paths[entry.key] = methodMap;
    }

    final definitions = <String, SwaggerDefinition>{};
    // Support both Swagger 2.0 'definitions' and OpenAPI 3.x 'components/schemas'
    final defsJson =
        json['definitions'] as Map<String, dynamic>? ??
        (json['components'] as Map<String, dynamic>?)?['schemas']
            as Map<String, dynamic>? ??
        {};
    for (final entry in defsJson.entries) {
      // Sanitize definition names: strip &, commas, etc.
      final sanitizedName = entry.key.replaceAll(RegExp('[^a-zA-Z0-9_]'), '');
      definitions[sanitizedName] = SwaggerDefinition.fromJson(
        sanitizedName,
        entry.value as Map<String, dynamic>,
      );
    }

    return SwaggerSpec(
      title: info['title'] as String? ?? '',
      version: info['version'] as String? ?? '',
      basePath: json['basePath'] as String? ?? '',
      paths: paths,
      definitions: definitions,
    );
  }

  final String title;
  final String version;
  final String basePath;
  final Map<String, Map<String, SwaggerOperation>> paths;
  final Map<String, SwaggerDefinition> definitions;
}

class SwaggerOperation {
  SwaggerOperation({
    required this.path,
    required this.method,
    required this.tags,
    required this.summary,
    required this.operationId,
    required this.description,
    required this.parameters,
    required this.responses,
    required this.consumes,
    required this.security,
  });

  factory SwaggerOperation.fromJson(
    Map<String, dynamic> json, {
    required String path,
    required String method,
  }) {
    final params = <SwaggerParameter>[];
    final paramsJson = json['parameters'] as List<dynamic>? ?? [];
    for (final p in paramsJson) {
      params.add(SwaggerParameter.fromJson(p as Map<String, dynamic>));
    }

    final responses = <String, SwaggerResponse>{};
    final responsesJson = json['responses'] as Map<String, dynamic>? ?? {};
    for (final entry in responsesJson.entries) {
      responses[entry.key] = SwaggerResponse.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }

    final security = <Map<String, List<String>>>[];
    final securityJson = json['security'] as List<dynamic>? ?? [];
    for (final s in securityJson) {
      final secMap = <String, List<String>>{};
      for (final entry in (s as Map<String, dynamic>).entries) {
        secMap[entry.key] = (entry.value as List<dynamic>).cast<String>();
      }
      security.add(secMap);
    }

    return SwaggerOperation(
      path: path,
      method: method,
      tags:
          (json['tags'] as List<dynamic>?)
              ?.map((t) => _sanitizeForIdentifier(t as String))
              .toList() ??
          [],
      summary: json['summary'] as String? ?? '',
      operationId: (json['operationId'] as String? ?? '').replaceAll(
        RegExp('[^a-zA-Z0-9_]'),
        '',
      ), // strip &, commas, etc.
      description: json['description'] as String? ?? '',
      parameters: params,
      responses: responses,
      consumes: (json['consumes'] as List<dynamic>?)?.cast<String>() ?? [],
      security: security,
    );
  }

  final String path;
  final String method;
  final List<String> tags;
  final String summary;
  final String operationId;
  final String description;
  final List<SwaggerParameter> parameters;
  final Map<String, SwaggerResponse> responses;
  final List<String> consumes;
  final List<Map<String, List<String>>> security;

  bool get requiresAuth => security.any((s) => s.containsKey('accessToken'));

  List<SwaggerParameter> get queryParams =>
      parameters.where((p) => p.location == 'query').toList();

  List<SwaggerParameter> get formParams =>
      parameters.where((p) => p.location == 'formData').toList();

  List<SwaggerParameter> get pathParams =>
      parameters.where((p) => p.location == 'path').toList();

  String? get successResponseRef {
    final r = responses['200'] ?? responses['201'] ?? responses['204'];
    return r?.schemaRef;
  }
}

class SwaggerParameter {
  SwaggerParameter({
    required this.name,
    required this.location,
    required this.required_,
    required this.description,
    required this.type,
    this.collectionFormat,
    this.itemsType,
    this.schemaRef,
    this.schema,
  });

  factory SwaggerParameter.fromJson(Map<String, dynamic> json) {
    String? itemsType;
    if (json['items'] != null) {
      itemsType = (json['items'] as Map<String, dynamic>)['type'] as String?;
    }
    String? schemaRef;
    if (json['schema'] != null) {
      schemaRef = (json['schema'] as Map<String, dynamic>)[r'$ref'] as String?;
      if (schemaRef != null) {
        schemaRef = schemaRef
            .split('/')
            .last
            .replaceAll(RegExp('[^a-zA-Z0-9_]'), '');
      }
    }
    return SwaggerParameter(
      name: json['name'] as String? ?? '',
      location: json['in'] as String? ?? '',
      required_: json['required'] as bool? ?? false,
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? 'string',
      collectionFormat: json['collectionFormat'] as String?,
      itemsType: itemsType,
      schemaRef: schemaRef,
      schema: json['schema'] as Map<String, dynamic>?,
    );
  }

  final String name;
  final String location;
  final bool required_;
  final String description;
  final String type;
  final String? collectionFormat;
  final String? itemsType;
  final String? schemaRef;
  final Map<String, dynamic>? schema;

  String get dartType {
    if (type == 'array') return 'List<String>';
    if (type == 'integer' || type == 'int') return 'int';
    if (type == 'number' || type == 'double') return 'double';
    if (type == 'boolean' || type == 'bool') return 'bool';
    if (type == 'file') return 'File';
    return 'String';
  }

  String get dartName => _safeDartName(name);
}

class SwaggerResponse {
  SwaggerResponse({this.schemaRef, this.description});

  factory SwaggerResponse.fromJson(Map<String, dynamic> json) {
    String? ref;
    if (json['schema'] != null) {
      final schema = json['schema'] as Map<String, dynamic>;
      ref = schema[r'$ref'] as String?;
      if (ref != null) {
        ref = ref.split('/').last.replaceAll(RegExp('[^a-zA-Z0-9_]'), '');
      }
    }
    return SwaggerResponse(
      schemaRef: ref,
      description: json['description'] as String?,
    );
  }

  final String? schemaRef;
  final String? description;
}

class SwaggerDefinition {
  SwaggerDefinition({required this.name, required this.properties});

  factory SwaggerDefinition.fromJson(String name, Map<String, dynamic> json) {
    final props = <String, SwaggerProperty>{};
    final propsJson = json['properties'] as Map<String, dynamic>? ?? {};
    for (final entry in propsJson.entries) {
      props[entry.key] = SwaggerProperty.fromJson(
        entry.key,
        entry.value as Map<String, dynamic>,
      );
    }
    return SwaggerDefinition(name: name, properties: props);
  }

  final String name;
  final Map<String, SwaggerProperty> properties;

  /// Determines if this definition is just a generic API response wrapper
  /// (e.g. contains only result, message, data/payload, paginator)
  /// and should NOT be generated as a domain model.
  bool get isResponseWrapper {
    if (properties.isEmpty) return false;

    final hasResult = properties.containsKey('result');
    final hasToken = properties.containsKey('token');
    final hasData = properties.containsKey('data');
    final hasPayload = properties.containsKey('payload');

    // If it's the schema for a 200/201 response and only has wrapper-like fields
    final allowedFields = {
      'result',
      'message',
      'data',
      'payload',
      'paginator',
      'errors',
      'status_code',
      'token',
      'success',
    };
    for (final propName in properties.keys) {
      if (!allowedFields.contains(propName)) {
        return false;
      }
    }

    return hasData || hasPayload || hasToken || hasResult;
  }
}

class SwaggerProperty {
  SwaggerProperty({
    required this.name,
    required this.type,
    this.ref,
    this.defaultValue,
    this.itemsRef,
    this.itemsType,
    this.properties = const {},
  });

  factory SwaggerProperty.fromJson(String name, Map<String, dynamic> json) {
    var ref = json[r'$ref'] as String?;
    if (ref != null) {
      ref = ref.split('/').last.replaceAll(RegExp('[^a-zA-Z0-9_]'), '');
    }
    // Treat primitive $refs (e.g. "string") as plain types, not nested objects
    if (ref != null && _primitiveRefs.contains(ref)) ref = null;

    String? itemsRef;
    String? itemsType;
    if (json['items'] != null) {
      final items = json['items'] as Map<String, dynamic>;
      itemsRef = items[r'$ref'] as String?;
      if (itemsRef != null) {
        itemsRef = itemsRef
            .split('/')
            .last
            .replaceAll(RegExp('[^a-zA-Z0-9_]'), '');
      }
      // Treat primitive $refs in array items as plain types
      if (itemsRef != null && _primitiveRefs.contains(itemsRef)) {
        itemsType = itemsRef.toLowerCase();
        itemsRef = null;
      }
      itemsType ??= items['type'] as String?;
    }

    final props = <String, SwaggerProperty>{};
    if (json['properties'] != null) {
      final propsJson = json['properties'] as Map<String, dynamic>;
      for (final entry in propsJson.entries) {
        props[entry.key] = SwaggerProperty.fromJson(
          entry.key,
          entry.value as Map<String, dynamic>,
        );
      }
    }

    return SwaggerProperty(
      name: name,
      type: json['type'] as String? ?? (ref != null ? 'object' : 'string'),
      ref: ref,
      defaultValue: json['default'],
      itemsRef: itemsRef,
      itemsType: itemsType,
      properties: props,
    );
  }

  final String name;
  final String type;
  final String? ref;
  final dynamic defaultValue;
  final String? itemsRef;
  final String? itemsType;
  final Map<String, SwaggerProperty> properties;

  String get dartName {
    final override = _methodRenameOverride();
    if (override != null) return override;
    return _safeDartName(name);
  }

  String? _methodRenameOverride() {
    return null;
  }

  String get dartType {
    if (ref != null) return definitionRenames[ref!] ?? ref!;
    if (type == 'array') {
      if (itemsRef != null) {
        return 'List<${definitionRenames[itemsRef!] ?? itemsRef!}>';
      }
      if (itemsType == 'integer' || itemsType == 'int') return 'List<int>';
      if (itemsType == 'number' || itemsType == 'double') return 'List<double>';
      if (itemsType == 'boolean' || itemsType == 'bool') return 'List<bool>';
      if (itemsType == 'string') return 'List<String>';
      return 'List<dynamic>';
    }
    if (type == 'integer' || type == 'int') return 'int';
    if (type == 'number' || type == 'double') return 'double';
    if (type == 'boolean' || type == 'bool') return 'bool';
    if (properties.isNotEmpty) return 'Map<String, dynamic>';
    return 'String';
  }

  bool get isNestedObject => ref != null || properties.isNotEmpty;
  bool get isNestedList =>
      type == 'array' && (itemsRef != null || itemsType == 'object');
}

// ─── Code Generator ────────────────────────────────────────────────────────────

class CodeGenerator {
  CodeGenerator({
    required this.swagger,
    required this.dryRun,
    required this.packageName,
  });

  final SwaggerSpec swagger;
  final bool dryRun;
  final String packageName;
  final String libDir = 'lib';

  /// Convenience getter for the package import prefix (e.g. 'package:starter')
  String get _pkg => 'package:$packageName';

  /// Maps a definition name to its relative import path within api/*/models/
  final Map<String, String> _modelImportPaths = {};

  /// Dynamically computed: maps a Swagger definition name → group name
  late final Map<String, String> _definitionToGroup;

  /// Tracks all files written during this run to allow cleaning up stale ones
  final Set<String> _writtenFiles = {};

  /// Dynamically discovered manually created models to skip generating
  final Set<String> _dynamicSkipDefinitions = {};

  /// Custom import paths for dynamically discovered manual models
  final Map<String, String> _dynamicCustomImports = {};

  void run() {
    _discoverManualModels();

    // 1. Group operations by group (derived dynamically from tags, with path overrides)
    final groupOps = <String, List<SwaggerOperation>>{};
    for (final pathEntry in swagger.paths.entries) {
      final path = pathEntry.key;
      for (final methodEntry in pathEntry.value.entries) {
        final op = methodEntry.value;
        final firstSegment = path
            .split('/')
            .where((s) => s.isNotEmpty)
            .firstOrNull;

        final assignedGroups = <String>{};

        // Determine whether to override group based on the first path segment
        if (firstSegment != null &&
            pathSegmentGroupsMapping.containsKey(firstSegment)) {
          assignedGroups.addAll(pathSegmentGroupsMapping[firstSegment]!);
        } else if (op.tags.isNotEmpty) {
          // Group by tags (case-insensitive lookup into tagGroupsMapping)
          for (final tag in op.tags) {
            final tagLower = tag.toLowerCase();
            final matchingKey = tagGroupsMapping.keys
                .cast<String?>()
                .firstWhere(
                  (k) => k!.toLowerCase() == tagLower,
                  orElse: () => null,
                );
            if (matchingKey != null) {
              assignedGroups.addAll(tagGroupsMapping[matchingKey]!);
            } else {
              assignedGroups.add(_tagToGroupName(tag));
            }
          }
        } else {
          // Fallback to the first path segment if neither override nor tags exist
          assignedGroups.add(
            firstSegment != null ? _camelToSnake(firstSegment) : 'default',
          );
        }

        for (final group in assignedGroups) {
          groupOps.putIfAbsent(group, () => []).add(op);
        }
      }
    }

    // 2. Separate model defs from response wrapper defs
    final modelDefs = <String, SwaggerDefinition>{};
    final responseDefs = <String, SwaggerDefinition>{};
    for (final entry in swagger.definitions.entries) {
      final name = entry.key;
      final def = entry.value;

      final nameLower = name.trim().toLowerCase();
      if (def.isResponseWrapper ||
          nameLower.contains('apierror') ||
          nameLower.endsWith('successresponse') ||
          nameLower == 'paginator') {
        responseDefs[name] = def;
      } else {
        modelDefs[name] = def;
      }
    }

    // 3. Compute definition→group mapping dynamically
    _definitionToGroup = _computeDefinitionGroups(
      modelDefs,
      responseDefs,
      groupOps,
    );

    // 3.5. Validate swagger spec for potential codegen issues
    _validateSpec(modelDefs, responseDefs, groupOps);

    // 4. Generate models (centralized in lib/data/models/)
    print('\n── 📦 Models ──────────────────────────────────────────────');
    _generateAllModels(modelDefs, groupOps, responseDefs);

    // 5. Generate per group: datasources, repos, entity barrels, usecases
    for (final entry in groupOps.entries) {
      final group = entry.key;
      final ops = entry.value;

      if (skipGroups.contains(group)) {
        print('\n⏭ Skipping group "$group" (already implemented)');
        continue;
      }

      print('\n── 📦 Group: $group (${ops.length} operations) ──');

      // Generate repository in api/<group>/controller/
      _generateRepository(group, ops, responseDefs);

      // Generate service state class in api/<group>/controller/
      _generateServiceState(group);

      // Generate service stubs in api/<group>/controller/
      _generateService(group, ops, responseDefs);

      final hasPagination = _generatePaginationControllers(
        group,
        ops,
        responseDefs,
      );

      // Generate controller barrel file
      _generateControllerBarrel(group, hasPagination);
    }

    // 6. Generate endpoints file (preserves existing handwritten classes)
    _generateEndpointsFile(groupOps);

    // 6.5. Cleanup stale files inside `lib/api/`
    _cleanupStaleGeneratedFiles();

    // 7. Generate models barrel exports inside `lib/api/<module>/models/`
    // Include 'shared' since models can be placed there when referenced by multiple groups
    _generateBarrelExports(groupOps.keys, groupOps);

    // 7.5. Generate README files per group
    _generateGroupReadmes(groupOps);

    // 8. Inject dependencies in bootstrap.dart
    _injectDependenciesInBootstrap(groupOps.keys);

    print('\n═══════════════════════════════════════════════════════════');
    print(' ✅ Code generation complete!');
    if (dryRun) print('    (Dry run — no files were written)');
    print('═══════════════════════════════════════════════════════════');

    if (!dryRun) {
      // 9. Auto-fix, format, and analyze generated code
      _runPostGenCommands();
    }

    print('\n📋 Review the generated files in lib/api/');
  }

  // ── Post-Generation Commands ───────────────────────────────────────────────

  void _runPostGenCommands() {
    const commands = [
      ['dart', 'format', 'lib/'],
      ['dart', 'fix', '--apply', 'lib/'],
    ];

    for (final cmd in commands) {
      final label = cmd.join(' ');
      print('\n── 🔧 Running: $label ──');
      final result = Process.runSync(cmd.first, cmd.sublist(1));
      if (result.stdout.toString().trim().isNotEmpty) {
        print(result.stdout);
      }
      if (result.stderr.toString().trim().isNotEmpty) {
        print(result.stderr);
      }
      if (result.exitCode != 0) {
        print('   ⚠️  $label exited with code ${result.exitCode}');
      }
    }
  }

  // ── Generated File Header ──────────────────────────────────────────────────

  String _fileHeader(String description) {
    return '// Generated by swagger_codegen.dart\n// $description\n// DO NOT EDIT BY HAND — re-run the generator to update.\n';
  }

  // ── Dynamic Group Computation ──────────────────────────────────────────────

  /// Converts a Swagger tag (e.g. "Educational Resource") to a snake_case group name.
  /// Strips special chars like &, commas, etc. before conversion.
  String _tagToGroupName(String tag) {
    // Sanitize: "Delete & Deactive account" → "Delete Deactive account"
    final sanitized = _sanitizeForIdentifier(tag);
    // Remove spaces and convert PascalCase/camelCase to snake_case
    return _camelToSnake(sanitized.replaceAll(RegExp(r'\s+'), ''));
  }

  /// Compute which group each definition belongs to by tracing response refs.
  Map<String, String> _computeDefinitionGroups(
    Map<String, SwaggerDefinition> modelDefs,
    Map<String, SwaggerDefinition> responseDefs,
    Map<String, List<SwaggerOperation>> groupOps,
  ) {
    final defGroupRefs = <String, Set<String>>{};

    void addRef(String defName, String group, Set<String> visited) {
      if (visited.contains(defName)) return;
      visited.add(defName);
      if (_primitiveRefs.contains(defName)) return;

      defGroupRefs.putIfAbsent(defName, () => {}).add(group);

      final def = modelDefs[defName] ?? responseDefs[defName];
      if (def != null) {
        for (final prop in def.properties.values) {
          if (prop.ref != null) addRef(prop.ref!, group, visited);
          if (prop.itemsRef != null) addRef(prop.itemsRef!, group, visited);
        }
      }
    }

    for (final entry in groupOps.entries) {
      final group = entry.key;
      for (final op in entry.value) {
        if (op.successResponseRef != null) {
          addRef(op.successResponseRef!, group, {});
        }
        for (final p in op.parameters) {
          if (p.schemaRef != null) addRef(p.schemaRef!, group, {});
        }
      }
    }

    final result = <String, String>{...definitionToGroup};
    for (final defName in modelDefs.keys) {
      if (result.containsKey(defName)) continue; // Already pinned

      final groups = defGroupRefs[defName];
      if (groups == null || groups.isEmpty) {
        // Skip models not referenced by any group
        continue;
      } else if (groups.length == 1) {
        result[defName] = groups.first;
      } else {
        // Referenced by multiple groups → assign to first group
        result[defName] = groups.first;
      }
    }
    return result;
  }

  // ── Manual Model Discovery ────────────────────────────────────────────────
  void _discoverManualModels() {
    // Discover manual models in api/*/models/
    final apiDir = Directory('$libDir/api');
    if (apiDir.existsSync()) {
      for (final groupDir in apiDir.listSync()) {
        if (groupDir is Directory) {
          final modelsDir = Directory('${groupDir.path}/models');
          if (modelsDir.existsSync()) {
            for (final modelFile in modelsDir.listSync()) {
              if (modelFile is File &&
                  modelFile.path.endsWith('.dart') &&
                  !modelFile.path.endsWith('models.dart')) {
                final content = modelFile.readAsStringSync();
                // Skip files that were generated by this tool
                if (content.contains('// Generated by swagger_codegen.dart')) {
                  continue;
                }

                final relativePath = modelFile.path
                    .replaceFirst('$libDir/api/', '')
                    .replaceAll(r'\\', '/');
                final importPath = '$_pkg/api/$relativePath';

                // Find all class definitions in the file
                final classMatches = RegExp(
                  r'^class\s+([A-Z][a-zA-Z0-9_]*)',
                  multiLine: true,
                ).allMatches(content);
                for (final match in classMatches) {
                  final className = match.group(1)!;
                  _dynamicSkipDefinitions.add(className);
                  _dynamicCustomImports[className] = importPath;
                }
              }
            }
          }
        }
      }
    }

    if (_dynamicSkipDefinitions.isNotEmpty) {
      print('\n── 🔍 Discovered Manual Models ─────────────────────────────');
      for (final model in _dynamicSkipDefinitions) {
        print('   ✅ $model -> ${_dynamicCustomImports[model]}');
      }
    }
  }

  // ── Validation ────────────────────────────────────────────────────────────
  void _validateSpec(
    Map<String, SwaggerDefinition> modelDefs,
    Map<String, SwaggerDefinition> responseDefs,
    Map<String, List<SwaggerOperation>> groupOps,
  ) {
    final warnings = <String>[];
    final allDefs = {...modelDefs, ...responseDefs};

    // Check for definition name collisions after sanitization
    final sanitizedNames = <String, List<String>>{};
    for (final name in allDefs.keys) {
      final sanitized = name.replaceAll(RegExp('[^a-zA-Z0-9_]'), '');
      sanitizedNames.putIfAbsent(sanitized, () => []).add(name);
    }
    for (final entry in sanitizedNames.entries) {
      if (entry.value.length > 1) {
        warnings.add(
          'Definition name collision: ${entry.value.join(", ")} all sanitize to "${entry.key}"',
        );
      }
    }

    // Check for $ref values pointing to non-existent definitions
    for (final def in allDefs.values) {
      for (final prop in def.properties.values) {
        if (prop.ref != null && !allDefs.containsKey(prop.ref)) {
          warnings.add(
            'Property "${prop.name}" in "${def.name}" references missing definition "${prop.ref}"',
          );
        }
        if (prop.itemsRef != null && !allDefs.containsKey(prop.itemsRef)) {
          warnings.add(
            'Property "${prop.name}" in "${def.name}" has items referencing missing definition "${prop.itemsRef}"',
          );
        }
      }
    }

    // Check for reserved keyword field names and bracket params (informational)
    for (final def in allDefs.values) {
      for (final prop in def.properties.values) {
        if (_dartReservedKeywords.contains(prop.name)) {
          warnings.add(
            'Definition "${def.name}" has field "${prop.name}" which is a Dart reserved keyword → renamed to "${prop.dartName}"',
          );
        }
      }
    }
    for (final ops in groupOps.values) {
      for (final op in ops) {
        for (final p in op.formParams) {
          if (RegExp(r'\[\d+\]').hasMatch(p.name)) {
            warnings.add(
              'Endpoint "${op.operationId.isEmpty ? op.path : op.operationId}" has bracket-indexed param "${p.name}" → renamed to "${p.dartName}"',
            );
          }
          if (_dartReservedKeywords.contains(p.name)) {
            warnings.add(
              'Endpoint "${op.operationId.isEmpty ? op.path : op.operationId}" has param "${p.name}" which is a Dart reserved keyword → renamed to "${p.dartName}"',
            );
          }
        }
      }
    }

    if (warnings.isNotEmpty) {
      print('\n── ⚠️  Validation Warnings ──────────────────────────────');
      for (final w in warnings) {
        print('   ⚠️  $w');
      }
      print('');
    }
  }

  // ── Models ────────────────────────────────────────────────────────────────
  void _generateAllModels(
    Map<String, SwaggerDefinition> modelDefs,
    Map<String, List<SwaggerOperation>> groupOps,
    Map<String, SwaggerDefinition> responseDefs,
  ) {
    // STEP 0: Pre-calculate all import paths to avoid ordering issues
    final allDefs = {...modelDefs, ...responseDefs};
    for (final entry in allDefs.entries) {
      final name = entry.key;
      final dartName = definitionRenames[name] ?? name;
      final group = _definitionToGroup[name];
      if (group == null) continue; // Skip models not assigned to any group
      final fileName = _camelToSnake(dartName);

      final modelPath = '$_pkg/api/$group/models/${fileName}_model.dart';
      _modelImportPaths[name] = modelPath;
      _modelImportPaths[dartName] = modelPath;
    }

    // STEP 1: Generate model classes directly (without entities)
    for (final entry in allDefs.entries) {
      final name = entry.key;
      final dartName = definitionRenames[name] ?? name;
      final def = entry.value;
      final group = _definitionToGroup[name];
      if (group == null) continue; // Skip models not assigned to any group
      final modelName = '${dartName}Model';

      if (skipDefinitions.contains(name) ||
          _dynamicSkipDefinitions.contains(dartName) ||
          _dynamicSkipDefinitions.contains(modelName)) {
        print('   ⏭ Skipping model: $modelName (already implemented manually)');
        final modelFileName = '${_camelToSnake(dartName)}_model';
        final existingPath = '$libDir/api/$group/models/$modelFileName.dart';
        if (File(existingPath).existsSync()) {
          _writtenFiles.add(existingPath.replaceAll(r'\', '/'));
        }
        continue;
      }

      // Skip models from skipped groups
      if (skipGroups.contains(group)) {
        if (!_isModelReferencedByNonSkippedGroup(
          name,
          groupOps,
          responseDefs,
        )) {
          print('   ⏭ Skipping model: $modelName (in skipped group "$group")');
          continue;
        }
      }

      if (def.properties.isEmpty) {
        print(
          '   ⚠️  Model "$modelName" has no properties (empty definition), but generating it anyway.',
        );
      }

      final modelBuffer = StringBuffer();
      modelBuffer.writeln(_fileHeader('Model: $modelName'));
      modelBuffer.writeln("import 'package:meta/meta.dart';");
      modelBuffer.writeln("import '$_pkg/utils/utils.dart';");

      // Check if any property uses the dart:io File type
      final needsDartIo = def.properties.values.any(
        (p) => p.dartType == 'File',
      );
      if (needsDartIo) {
        modelBuffer.writeln("import 'dart:io';");
      }

      // Collect model imports
      final modelImports = <String>{};
      for (final prop in def.properties.values) {
        if (prop.ref != null) _addModelImportForRef(modelImports, prop.ref!);
        if (prop.itemsRef != null) {
          _addModelImportForRef(modelImports, prop.itemsRef!);
        }
      }

      final sortedModelImports = modelImports.toList()..sort();
      for (final imp in sortedModelImports) {
        modelBuffer.writeln("import '$imp';");
      }
      modelBuffer.writeln();
      _writeModelClassDirect(modelBuffer, dartName, def);

      final modelFileName = '${_camelToSnake(dartName)}_model';
      final modelPath = '$libDir/api/$group/models/$modelFileName.dart';
      _writeFile(modelPath, modelBuffer.toString());
      print('   📄 Model: $modelName → $modelPath');
    }

    // STEP 2: Generate request models from operations
    final writtenRequestModels = <String>{};
    for (final entry in groupOps.entries) {
      final group = entry.key;
      final ops = entry.value;

      if (skipGroups.contains(group)) continue;

      for (final op in ops) {
        if (op.formParams.isNotEmpty ||
            op.pathParams.isNotEmpty ||
            op.parameters.any((p) => p.location == 'body')) {
          final name = _operationToRequestModelName(op);
          final modelName = '${name}Model';
          if (writtenRequestModels.contains(modelName)) continue;
          writtenRequestModels.add(modelName);

          if (skipDefinitions.contains(name) ||
              _dynamicSkipDefinitions.contains(modelName)) {
            print(
              '   ⏭ Skipping request model: $modelName (already implemented manually)',
            );
            continue;
          }

          final fileName = _camelToSnake(name);
          final modelPath = '$libDir/api/$group/models/${fileName}_model.dart';

          final modelBuffer = StringBuffer();
          modelBuffer.writeln(_fileHeader('Request Model: $modelName'));
          modelBuffer.writeln("import 'package:meta/meta.dart';");

          final isMultipart = op.consumes.contains('multipart/form-data');
          if (isMultipart || op.formParams.isNotEmpty) {
            modelBuffer.writeln(
              "import 'package:dio/dio.dart'; // For FormData",
            );
          }

          // Check if any property uses File type (needs dart:io)
          final requestProps = _extractRequestProperties(op);
          final needsDartIo = requestProps.any((p) => p.dartType == 'File');
          if (needsDartIo) {
            modelBuffer.writeln("import 'dart:io';");
          }
          modelBuffer.writeln();

          _writeRequestModelClassDirect(modelBuffer, modelName, op);

          _writeFile(modelPath, modelBuffer.toString());
          _modelImportPaths[name] =
              '$_pkg/api/$group/models/${fileName}_model.dart';
          print('   📄 Request Model: $modelName → $modelPath');
        }
      }
    }
  }

  /// Writes a full data class Model without depending on an Entity.
  void _writeModelClassDirect(
    StringBuffer buffer,
    String dartName,
    SwaggerDefinition def,
  ) {
    final props = def.properties.values.toList();
    final modelName = '${dartName}Model';

    // Build deduplicated field names
    final fieldNames = <SwaggerProperty, String>{};
    final seen = <String, int>{};
    for (final prop in props) {
      var name = prop.dartName;
      if (seen.containsKey(name)) {
        seen[name] = seen[name]! + 1;
        name = '$name${seen[name]}';
      } else {
        seen[name] = 1;
      }
      fieldNames[prop] = name;
    }
    String fn(SwaggerProperty p) => fieldNames[p]!;

    buffer.writeln('@immutable');
    buffer.writeln('class $modelName {');
    buffer.writeln('  const $modelName({');
    for (final prop in props) {
      final isNullable = !_isRequired(prop);
      if (isNullable) {
        buffer.writeln('    this.${fn(prop)},');
      } else {
        buffer.writeln('    required this.${fn(prop)},');
      }
    }
    buffer.writeln('  });');
    buffer.writeln();

    // Fields
    for (final prop in props) {
      final isNullable = !_isRequired(prop);
      final type = _dartFieldTypeForModel(prop);
      buffer.writeln('  final $type${isNullable ? '?' : ''} ${fn(prop)};');
    }
    buffer.writeln();

    // fromJson
    buffer.writeln(
      '  factory $modelName.fromJson(Map<String, dynamic> json) {',
    );
    buffer.writeln('    return $modelName(');
    for (final prop in props) {
      buffer.writeln(
        '      ${fn(prop)}: ${_fromJsonExpressionForModel(prop, dartName)},',
      );
    }
    buffer.writeln('    );');
    buffer.writeln('  }');
    buffer.writeln();

    // toJson
    buffer.writeln('  Map<String, dynamic> toJson() {');
    buffer.writeln('    return <String, dynamic>{');
    for (final prop in props) {
      buffer.writeln("      '${prop.name}': ${_toJsonExpression(prop)},");
    }
    buffer.writeln('    };');
    buffer.writeln('  }');
    buffer.writeln();

    // copyWith
    buffer.writeln('  $modelName copyWith({');
    for (final prop in props) {
      final type = _dartFieldTypeForModel(prop);
      buffer.writeln('    $type? ${fn(prop)},');
    }
    buffer.writeln('  }) {');
    buffer.writeln('    return $modelName(');
    for (final prop in props) {
      buffer.writeln('      ${fn(prop)}: ${fn(prop)} ?? this.${fn(prop)},');
    }
    buffer.writeln('    );');
    buffer.writeln('  }');
    buffer.writeln();

    // toString
    buffer.writeln('  @override');
    buffer.write("  String toString() => '$modelName(");
    final toStringParts = props.map((p) => '${fn(p)}: \$${fn(p)}');
    buffer.write(toStringParts.join(', '));
    buffer.writeln(")';");

    buffer.writeln('}');
  }

  /// Writes a request model that does not depend on an entity.
  void _writeRequestModelClassDirect(
    StringBuffer buffer,
    String modelName,
    SwaggerOperation op,
  ) {
    final props = _extractRequestProperties(op);
    final isMultipart = op.consumes.contains('multipart/form-data');

    buffer.writeln('@immutable');
    buffer.writeln('class $modelName {');
    buffer.writeln('  const $modelName({');
    for (final prop in props) {
      if (prop.isRequired) {
        buffer.writeln('    required this.${prop.dartName},');
      } else {
        buffer.writeln('    this.${prop.dartName},');
      }
    }
    buffer.writeln('  });');
    buffer.writeln();

    for (final prop in props) {
      final nullable = prop.isRequired ? '' : '?';
      buffer.writeln('  final ${prop.dartType}$nullable ${prop.dartName};');
    }
    buffer.writeln();

    buffer.writeln('  Map<String, dynamic> toJson() => {');
    for (final prop in props) {
      buffer.writeln("    '${prop.name}': ${prop.dartName},");
    }
    buffer.writeln('  };');
    buffer.writeln();

    if (isMultipart || op.formParams.isNotEmpty) {
      buffer.writeln('  FormData toFormData() {');
      buffer.writeln(
        '    return FormData.fromMap(toJson()..removeWhere((key, value) => value == null));',
      );
      buffer.writeln('  }');
      buffer.writeln();
    }

    buffer.writeln('  @override');
    buffer.write("  String toString() => '$modelName(");
    final toStringParts = props.map((p) => '${p.dartName}: \$${p.dartName}');
    buffer.write(toStringParts.join(', '));
    buffer.writeln(")';");

    buffer.writeln('}');
  }

  List<_RequestProp> _extractRequestProperties(SwaggerOperation op) {
    final results = <_RequestProp>[];
    final params = [...op.formParams, ...op.pathParams];

    for (final p in params) {
      String? ref;
      String? itemsRef;

      if (p.schema != null) {
        final schema = p.schema!;
        if (schema.containsKey('$ref')) {
          ref = (schema['$ref'] as String).split('/').last;
        } else if (schema['items'] != null &&
            (schema['items'] as Map).containsKey('$ref')) {
          itemsRef = (schema['items'] as Map)['$ref']
              .toString()
              .split('/')
              .last;
        }
      }

      results.add(
        _RequestProp(
          name: p.name,
          dartName: p.dartName,
          dartType: p.dartType,
          isRequired: p.required_,
          ref: ref,
          itemsRef: itemsRef,
        ),
      );
    }

    // Body flattening
    final bodyParams = op.parameters
        .where((p) => p.location == 'body')
        .toList();
    if (bodyParams.isNotEmpty) {
      final bodyParam = bodyParams.first;
      if (bodyParam.schema != null && bodyParam.schema!['properties'] != null) {
        final props = bodyParam.schema!['properties'] as Map<String, dynamic>;
        for (final entry in props.entries) {
          final propName = entry.key;
          final propData = entry.value as Map<String, dynamic>;
          final type = propData['type'] as String? ?? 'string';
          final dartType = type == 'integer'
              ? 'int'
              : (type == 'number'
                    ? 'double'
                    : (type == 'boolean' ? 'bool' : 'String'));

          String? ref;
          String? itemsRef;
          if (propData.containsKey('$ref')) {
            ref = (propData['$ref'] as String).split('/').last;
          } else if (propData['items'] != null &&
              (propData['items'] as Map).containsKey('$ref')) {
            itemsRef = (propData['items'] as Map)['$ref']
                .toString()
                .split('/')
                .last;
          }

          results.add(
            _RequestProp(
              name: propName,
              dartName: _safeDartName(propName),
              dartType: dartType,
              isRequired: true,
              ref: ref,
              itemsRef: itemsRef,
            ),
          );
        }
      }
    }
    // Deduplicate dartNames — append numeric suffix on collision
    final seen = <String, int>{};
    for (var i = 0; i < results.length; i++) {
      final name = results[i].dartName;
      if (seen.containsKey(name)) {
        seen[name] = seen[name]! + 1;
        final uniqueName = '$name${seen[name]}';
        results[i] = _RequestProp(
          name: results[i].name,
          dartName: uniqueName,
          dartType: results[i].dartType,
          isRequired: results[i].isRequired,
          ref: results[i].ref,
          itemsRef: results[i].itemsRef,
        );
      } else {
        seen[name] = 1;
      }
    }
    return results;
  }

  // ── Repository Implementation ──────────────────────────────────────────────
  void _generateRepository(
    String group,
    List<SwaggerOperation> ops,
    Map<String, SwaggerDefinition> responseDefs,
  ) {
    final buffer = StringBuffer();
    final className = '${_pascalCase(group)}Repository';
    final endpointClass = '${_pascalCase(group)}Endpoints';
    final requiresAuth = ops.any((op) => op.requiresAuth);

    buffer.writeln(_fileHeader('Repository: $className'));
    buffer.writeln('///');
    buffer.writeln('/// ## 📋 Import Adjustments When Copying');
    buffer.writeln('///');
    buffer.writeln(
      '/// If you copy this file to `lib/$group/controller/`, update imports:',
    );
    buffer.writeln(
      '/// - Models: Keep api imports or update to relative paths',
    );
    buffer.writeln('/// - Utils: `$_pkg/utils/utils.dart` (unchanged)');
    buffer.writeln(
      '/// - Auth: `$_pkg/auth/controller/interceptor.dart` (unchanged)',
    );
    buffer.writeln('/// - Endpoints: Available via `$_pkg/utils/utils.dart`');
    buffer.writeln('///');
    buffer.writeln("import '$_pkg/api/api.dart'; // ignore: unused_import");
    // Endpoints come via utils.dart
    buffer.writeln(
      "import '$_pkg/auth/controller/interceptor.dart'; // ignore: unused_import",
    );
    buffer.writeln("import '$_pkg/utils/utils.dart'; // ignore: unused_import");
    buffer.writeln();
    buffer.writeln(
      '/// Concrete repository for ${_humanize(group)} operations.',
    );
    buffer.writeln('///');
    buffer.writeln('/// Makes real API calls via [ApiClient].');
    buffer.writeln('class $className extends ApiClient {');
    buffer.writeln();

    if (requiresAuth) {
      buffer.writeln(
        "  $className() : super(interceptors: [AuthInterceptor(rejectIfNoSession: true)], name: '$className');",
      );
    } else {
      buffer.writeln("  $className() : super(name: '$className');");
    }
    buffer.writeln();

    for (final op in ops) {
      _writeDataSourceImplMethod(buffer, op, endpointClass, responseDefs);
    }

    buffer.writeln('}');

    final filePath = '$libDir/api/$group/controller/repository.dart';
    _writeFile(filePath, buffer.toString());
    print('   📄 Repository: $className → $filePath');
  }

  // ── Service State Class Generation (Inheritance Pattern) ───────────────────
  void _generateServiceState(String group) {
    final pascal = _pascalCase(group);
    final stateClassName = '${pascal}State';
    final filePath = '$libDir/api/$group/controller/states.dart';

    final buffer = StringBuffer();
    buffer.writeln(_fileHeader('States: $stateClassName'));
    buffer.writeln();
    buffer.writeln('/// Base state class for $pascal operations');
    buffer.writeln('abstract class $stateClassName {');
    buffer.writeln('  const $stateClassName();');
    buffer.writeln('}');
    buffer.writeln();
    buffer.writeln('/// Initial state');
    buffer.writeln('class ${pascal}Initial extends $stateClassName {}');
    buffer.writeln();
    buffer.writeln('/// Loading state');
    buffer.writeln('class ${pascal}Loading extends $stateClassName {}');
    buffer.writeln();
    buffer.writeln('/// Success state with typed data');
    buffer.writeln('class ${pascal}Success<T> extends $stateClassName {');
    buffer.writeln('  const ${pascal}Success(this.data);');
    buffer.writeln('  final T data;');
    buffer.writeln('}');
    buffer.writeln();
    buffer.writeln('/// Error state with message');
    buffer.writeln('class ${pascal}Error extends $stateClassName {');
    buffer.writeln('  const ${pascal}Error(this.message);');
    buffer.writeln('  final String message;');
    buffer.writeln('}');

    _writeFile(filePath, buffer.toString());
    print('   📄 State Classes: $stateClassName → $filePath');
  }

  // ── Service Stub Implementation ─────────────────────────────────────────────
  void _generateService(
    String group,
    List<SwaggerOperation> ops,
    Map<String, SwaggerDefinition> responseDefs,
  ) {
    final pascal = _pascalCase(group);
    final repoName = '${pascal}Repository';
    final className = '${pascal}Service';
    final stateClassName = '${pascal}State';

    final filePath = '$libDir/api/$group/controller/service.dart';

    final buffer = StringBuffer();
    buffer.writeln(_fileHeader('Service: $className'));
    buffer.writeln("import 'dart:async';");
    buffer.writeln();
    buffer.writeln("import 'package:flutter/foundation.dart';");
    buffer.writeln("import 'package:rxdart/rxdart.dart';");
    buffer.writeln("import '$_pkg/api/api.dart';");
    buffer.writeln("import '$_pkg/utils/utils.dart'; // ignore: unused_import");
    buffer.writeln();
    buffer.writeln('/// Service class for ${_humanize(group)} operations.');
    buffer.writeln('/// Extends [$repoName] to inherit API calls.');
    buffer.writeln('///');
    buffer.writeln(
      '/// Provides a [BehaviorSubject] with typed [$stateClassName] events.',
    );
    buffer.writeln(
      '/// Listen to [onStateChanges] to react to loading / success / error states.',
    );
    buffer.writeln('class $className extends $repoName with ChangeNotifier {');
    buffer.writeln('  $className();');
    buffer.writeln();
    buffer.writeln('  // ── State Stream ──');
    buffer.writeln(
      '  final _stateController = BehaviorSubject<$stateClassName>();',
    );
    buffer.writeln(
      '  Stream<$stateClassName> get onStateChanges => _stateController.stream;',
    );
    buffer.writeln();
    buffer.writeln('  @override');
    buffer.writeln('  void dispose() {');
    buffer.writeln('    _stateController.close();');
    buffer.writeln('    super.dispose();');
    buffer.writeln('  }');
    buffer.writeln();

    // Generate a wrapped method for each operation
    for (final op in ops) {
      final methodName = _sanitizeMethodName(_operationToMethodName(op));
      final returnType = _determineReturnType(op, responseDefs, forModel: true);
      final params = _buildMethodParams(op);

      // State variable
      final stateVarName = '_${methodName}Data';
      if (returnType != 'void' && returnType != 'dynamic') {
        buffer.writeln('  $returnType? $stateVarName;');
        buffer.writeln(
          '  $returnType? get ${methodName}Data => $stateVarName;',
        );
        buffer.writeln();
      }

      // Build the call args to forward to super
      final callArgs = <String>[];
      if ((op.formParams.isNotEmpty ||
              op.parameters.any((p) => p.location == 'body')) &&
          (op.method == 'post' ||
              op.method == 'put' ||
              op.method == 'patch' ||
              op.method == 'delete')) {
        callArgs.add('request: request');
      }
      for (final param in op.queryParams) {
        callArgs.add('${param.dartName}: ${param.dartName}');
      }
      for (final param in op.pathParams) {
        callArgs.add('${param.dartName}: ${param.dartName}');
      }

      buffer.writeln('  /// ${op.summary}');
      buffer.write('  Future<$returnType> ${methodName}Service(');
      if (params.isNotEmpty) {
        buffer.write('{${params.join(', ')}}');
      }
      buffer.writeln(') async {');
      buffer.writeln('    _stateController.add(${pascal}Loading());');
      buffer.writeln('    try {');

      buffer.writeln(
        '      final result = await super.${methodName}Repo(${callArgs.isNotEmpty ? callArgs.join(', ') : ''});',
      );
      if (returnType != 'void' && returnType != 'dynamic') {
        buffer.writeln('      $stateVarName = result;');
        buffer.writeln('      notifyListeners();');
      }
      buffer.writeln('      _stateController.add(${pascal}Success(result));');
      buffer.writeln('      return result;');

      buffer.writeln('    } catch (e) {');
      buffer.writeln(
        '      _stateController.add(${pascal}Error(e.toString()));',
      );
      buffer.writeln('      rethrow;');
      buffer.writeln('    }');
      buffer.writeln('  }');
      buffer.writeln();
    }

    buffer.writeln(
      '  // Add custom business logic, state management, or method overrides here',
    );
    buffer.writeln('}');

    _writeFile(filePath, buffer.toString());
    print('   📄 Service: $className → $filePath');
  }

  bool _generatePaginationControllers(
    String group,
    List<SwaggerOperation> ops,
    Map<String, SwaggerDefinition> responseDefs,
  ) {
    final paginatedOps = ops
        .where((op) => _isPaginatedResponse(op, responseDefs))
        .toList();
    if (paginatedOps.isEmpty) return false;

    final pascal = _pascalCase(group);
    final filePath = '$libDir/api/$group/controller/pagination.dart';
    final buffer = StringBuffer();

    buffer.writeln(_fileHeader('Pagination Controllers'));
    buffer.writeln("import 'dart:async'; // ignore: unused_import");
    buffer.writeln("import 'package:flutter/foundation.dart';");
    buffer.writeln("import '$_pkg/utils/utils.dart';");
    buffer.writeln("import '$_pkg/api/api.dart'; // ignore: unused_import");
    buffer.writeln();

    for (final op in paginatedOps) {
      final methodName = _sanitizeMethodName(_operationToMethodName(op));
      final pascalMethodName = _pascalCase(methodName);
      final returnType = _determineReturnType(op, responseDefs, forModel: true);

      final match = RegExp(r'List<(\w+)>').firstMatch(returnType);
      final itemType = match?.group(1) ?? 'dynamic';

      buffer.writeln(
        '/// Auto-generated Pagination Controller for [$methodName]',
      );
      buffer.writeln(
        'class ${pascalMethodName}Pagination extends BasePaginationController<$itemType> {',
      );
      buffer.writeln('  ${pascalMethodName}Pagination(this.service);');
      buffer.writeln();
      buffer.writeln('  final ${pascal}Service service;');
      buffer.writeln();

      final allFields = <String, String>{};
      final callArgs = <String>[];

      if ((op.formParams.isNotEmpty ||
              op.parameters.any((p) => p.location == 'body')) &&
          (op.method == 'post' ||
              op.method == 'put' ||
              op.method == 'patch' ||
              op.method == 'delete')) {
        final requestModelName = _operationToRequestModelName(op);
        allFields['request'] = '${requestModelName}Model';
        callArgs.add('request: request!');
      }

      for (final param in op.pathParams) {
        allFields[param.dartName] = param.dartType;
        callArgs.add('${param.dartName}: ${param.dartName}!');
      }

      for (final param in op.queryParams) {
        if (param.name == 'page' ||
            param.dartName == 'page' ||
            param.name == 'pageKey') {
          final val = param.dartType == 'String'
              ? 'pageKey.toString()'
              : 'pageKey';
          callArgs.add('${param.dartName}: $val');
        } else {
          allFields[param.dartName] = param.dartType;
          if (param.required_) {
            String fallback = '';
            if (param.dartType == 'String') {
              fallback = " ?? ''";
            } else if (param.dartType == 'int') {
              fallback = " ?? 0";
            } else if (param.dartType == 'double') {
              fallback = " ?? 0.0";
            } else if (param.dartType == 'bool') {
              fallback = " ?? false";
            } else {
              fallback = "!";
            }
            callArgs.add('${param.dartName}: ${param.dartName}$fallback');
          } else {
            callArgs.add('${param.dartName}: ${param.dartName}');
          }
        }
      }

      if (allFields.isNotEmpty) {
        buffer.writeln('  // Endpoint Parameters');
        for (final entry in allFields.entries) {
          buffer.writeln('  ${entry.value}? ${entry.key};');
        }
        buffer.writeln();
      }

      buffer.writeln('  @override');
      buffer.writeln(
        '  Future<({List<$itemType> items, Paginator paginator})> fetchApi(int pageKey) {',
      );
      buffer.write('    return service.${methodName}Service(');
      if (callArgs.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('      ${callArgs.join(',\n      ')},');
        buffer.write('    ');
      }
      buffer.writeln(');');
      buffer.writeln('  }');
      buffer.writeln();

      if (allFields.isNotEmpty) {
        buffer.writeln(
          '  /// Helper to smoothly merge state and trigger debounce refreshes',
        );
        buffer.write('  void updateFilters({');
        buffer.write(
          allFields.entries.map((e) => '${e.value}? ${e.key}').join(', '),
        );
        buffer.writeln('}) {');
        buffer.writeln('    debounceRefresh(() {');
        for (final entry in allFields.entries) {
          buffer.writeln(
            '      if (${entry.key} != null) this.${entry.key} = ${entry.key};',
          );
        }
        buffer.writeln('    });');
        buffer.writeln('  }');
      }

      buffer.writeln('}');
      buffer.writeln();
    }

    _writeFile(filePath, buffer.toString());
    print('   📄 Pagination: $filePath');
    return true;
  }

  // ── Controller Barrel File Generation ──────────────────────────────────────
  void _generateControllerBarrel(String group, bool hasPagination) {
    final filePath = '$libDir/api/$group/controller/controller.dart';
    final buffer = StringBuffer();
    buffer.writeln(_fileHeader('Controller Barrel'));
    buffer.writeln();
    buffer.writeln("export 'repository.dart';");
    buffer.writeln("export 'service.dart';");
    buffer.writeln("export 'states.dart';");
    if (hasPagination) {
      buffer.writeln("export 'pagination.dart';");
    }

    _writeFile(filePath, buffer.toString());
  }

  /// Sanitize a method name to be a valid Dart identifier
  String _sanitizeMethodName(String name) {
    var result = name.replaceAll(RegExp('[^a-zA-Z0-9_]'), '');
    if (result.isEmpty) result = 'operation';
    if (RegExp(r'^[0-9]').hasMatch(result)) result = 'op$result';
    if (_dartReservedKeywords.contains(result)) result = '${result}Method';
    return result;
  }

  void _writeDataSourceImplMethod(
    StringBuffer buffer,
    SwaggerOperation op,
    String endpointClass,
    Map<String, SwaggerDefinition> responseDefs,
  ) {
    final methodName = _sanitizeMethodName(_operationToMethodName(op));
    final endpointConst =
        '$endpointClass.${_sanitizeMethodName(_endpointConstName(op))}';
    final returnType = _determineReturnType(op, responseDefs, forModel: true);
    final isPaginated = _isPaginatedResponse(op, responseDefs);

    buffer.writeln('  /// ${op.summary}');
    buffer.write('  Future<$returnType> ${methodName}Repo(');

    final params = _buildMethodParams(op);
    if (params.isNotEmpty) {
      buffer.write('{${params.join(', ')}}');
    }

    buffer.writeln(') async {');
    buffer.writeln('    try {');

    final httpMethod = op.method;

    // Path expression
    String pathExpr;
    if (op.pathParams.isNotEmpty) {
      pathExpr = endpointConst;
      final replaces = <String>[];
      for (final param in op.pathParams) {
        final toStr = param.dartType == 'String' ? '' : '.toString()';
        replaces.add(".replaceAll('{${param.name}}', ${param.dartName}$toStr)");
      }
      pathExpr = '$endpointConst${replaces.join()}';
    } else {
      pathExpr = endpointConst;
    }

    if (op.queryParams.isNotEmpty) {
      buffer.writeln('      final queryParams = <String, dynamic>{');
      for (final param in op.queryParams) {
        if (param.required_) {
          buffer.writeln("        '${param.name}': ${param.dartName},");
        } else {
          buffer.writeln(
            "        if (${param.dartName} != null) '${param.name}': ${param.dartName},",
          );
        }
      }
      buffer.writeln('      };');
      buffer.writeln();
    }

    if (httpMethod == 'get') {
      buffer.writeln('      final response = await $httpMethod(');
      buffer.writeln(
        '        ${op.pathParams.isNotEmpty ? pathExpr : endpointConst},',
      );
      if (op.queryParams.isNotEmpty) {
        buffer.writeln('        queryParameters: queryParams,');
      }
      buffer.writeln('      );');
    } else {
      buffer.writeln('      final response = await $httpMethod(');
      buffer.writeln(
        '        ${op.pathParams.isNotEmpty ? pathExpr : endpointConst},',
      );

      final isMultipart = op.consumes.contains('multipart/form-data');
      final hasFormParams = op.formParams.isNotEmpty;
      if (isMultipart || hasFormParams) {
        buffer.writeln('        data: request.toFormData(),');
      } else if (op.parameters.any((p) => p.location == 'body')) {
        buffer.writeln('        data: request.toJson(),');
      }

      if (op.queryParams.isNotEmpty) {
        buffer.writeln('        queryParameters: queryParams,');
      }
      buffer.writeln('      );');
    }

    buffer.writeln();
    buffer.writeln(
      '      final apiResponse = ApiResponse.fromJson(response.data as Map<String, dynamic>);',
    );
    buffer.writeln('      if (apiResponse is ApiFailureResponse) {');
    buffer.writeln('        throw Exception(apiResponse.message);');
    buffer.writeln('      }');

    _writeResponseParsing(buffer, op, responseDefs, isPaginated, returnType);

    buffer.writeln('    } on Exception catch (e) {');
    buffer.writeln('      return onError(e);');
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.writeln();
  }

  void _writeResponseParsing(
    StringBuffer buffer,
    SwaggerOperation op,
    Map<String, SwaggerDefinition> responseDefs,
    bool isPaginated,
    String returnType,
  ) {
    final successRef = op.successResponseRef;
    if (successRef == null || successRef == 'SuccessResponse') {
      if (returnType == 'bool') {
        buffer.writeln('      return true;');
      } else {
        buffer.writeln('      return apiResponse.data;');
      }
      return;
    }

    final responseDef = responseDefs[successRef];
    final payloadProp =
        responseDef?.properties['payload'] ?? responseDef?.properties['data'];

    if (responseDef == null || payloadProp == null) {
      if (returnType == 'bool') {
        buffer.writeln('      return true;');
      } else if (returnType.endsWith('Model')) {
        buffer.writeln(
          '      final data = apiResponse.data as Map<String, dynamic>;',
        );
        buffer.writeln('      return $returnType.fromJson(data);');
      } else {
        buffer.writeln('      return apiResponse.data;');
      }
      return;
    }

    // Handle based on payload type
    if (payloadProp.type == 'array' && payloadProp.itemsRef != null) {
      // Extract the item type from returnType (e.g., List<UserModel> -> UserModel)
      String itemType;
      if (isPaginated) {
        // Extract from record type: ({List<UserModel> items, ...}) -> UserModel
        final match = RegExp(r'List<(\w+)>').firstMatch(returnType);
        itemType = match?.group(1) ?? 'dynamic';
      } else {
        // Extract from List<Type>
        final match = RegExp(r'List<(\w+)>').firstMatch(returnType);
        itemType = match?.group(1) ?? 'dynamic';
      }

      if (isPaginated) {
        buffer.writeln(
          '      final items = (apiResponse.data as List<dynamic>)',
        );
        buffer.writeln(
          '          .map((e) => $itemType.fromJson(e as Map<String, dynamic>))',
        );
        buffer.writeln('          .toList();');
        buffer.writeln(
          '      return (items: items, paginator: apiResponse.paginator!);',
        );
      } else {
        buffer.writeln('      return (apiResponse.data as List<dynamic>)');
        buffer.writeln(
          '          .map((e) => $itemType.fromJson(e as Map<String, dynamic>))',
        );
        buffer.writeln('          .toList();');
      }
    } else if (payloadProp.isNestedObject) {
      // Use returnType directly instead of resolving from refs
      String? modelName;
      if (returnType != 'dynamic' &&
          !returnType.startsWith('List<') &&
          !returnType.startsWith('(')) {
        modelName = returnType;
      }

      if (modelName != null) {
        if (payloadProp.name != 'data' && payloadProp.name != 'payload') {
          buffer.writeln(
            '      final data = apiResponse.data as Map<String, dynamic>;',
          );
          buffer.writeln(
            "      return $modelName.fromJson(data['${payloadProp.name}'] as Map<String, dynamic>);",
          );
        } else {
          buffer.writeln(
            '      final data = apiResponse.data as Map<String, dynamic>;',
          );
          buffer.writeln('      return $modelName.fromJson(data);');
        }
      } else {
        buffer.writeln('      return apiResponse.data;');
      }
    } else {
      // Fallback: try parsing if returnType is a model class
      if (returnType == 'bool') {
        buffer.writeln('      return true;');
      } else if (returnType != 'dynamic' &&
          !returnType.startsWith('List<') &&
          !returnType.startsWith('(') &&
          returnType.endsWith('Model')) {
        buffer.writeln(
          '      final data = apiResponse.data as Map<String, dynamic>;',
        );
        buffer.writeln('      return $returnType.fromJson(data);');
      } else {
        buffer.writeln('      return apiResponse.data;');
      }
    }
  }

  // ── Endpoints ─────────────────────────────────────────────────────────────

  void _generateEndpointsFile(Map<String, List<SwaggerOperation>> groupOps) {
    final endpointsPath = '$libDir/utils/network/endpoints.dart';
    final endpointsFile = File(endpointsPath);

    // Read existing file to preserve handwritten endpoint classes
    final existingClasses = <String, String>{};
    if (endpointsFile.existsSync()) {
      final existingContent = endpointsFile.readAsStringSync();
      // Parse existing class blocks: class XxxEndpoints { ... }
      final classPattern = RegExp(
        r'(\/\/\/[^\n]*\n)?class\s+(\w+Endpoints)\s*\{[\s\S]*?\n\}',
        multiLine: true,
      );
      for (final match in classPattern.allMatches(existingContent)) {
        final className = match.group(2)!;
        existingClasses[className] = match.group(0)!;
      }
    }

    final buffer = StringBuffer();
    buffer.writeln(_fileHeader('API Endpoints'));
    buffer.writeln(
      '/// All endpoints are relative to the base URL defined in environment variables.',
    );
    buffer.writeln('library;');
    buffer.writeln();

    // Keep track of which classes we've written
    final written = <String>{};

    // First, write endpoint classes for skipped groups from existing file
    for (final group in skipGroups) {
      final className = '${_pascalCase(group)}Endpoints';
      if (existingClasses.containsKey(className)) {
        buffer.writeln(existingClasses[className]);
        buffer.writeln();
        written.add(className);
      }
    }

    // Generate new endpoint classes for non-skipped groups
    for (final entry in groupOps.entries) {
      final group = entry.key;
      final ops = entry.value;
      if (skipGroups.contains(group)) continue;

      final className = '${_pascalCase(group)}Endpoints';
      if (written.contains(className)) continue;
      written.add(className);

      buffer.writeln('/// ${_humanize(group)} related endpoints');
      buffer.writeln('class $className {');
      buffer.writeln('  const $className._();');
      buffer.writeln();

      final seen = <String>{};
      for (final op in ops) {
        final constName = _endpointConstName(op);
        if (seen.contains(constName)) continue;
        seen.add(constName);
        final cleanPath = op.path
            .replaceAll(r'\n', '')
            .replaceAll(r'\r', '')
            .trim();
        buffer.writeln("  static const String $constName = '$cleanPath';");
      }

      buffer.writeln('}');
      buffer.writeln();
    }

    // Also preserve any other existing classes not yet written (e.g. manually added ones)
    for (final entry in existingClasses.entries) {
      if (!written.contains(entry.key)) {
        buffer.writeln(entry.value);
        buffer.writeln();
        written.add(entry.key);
      }
    }

    _writeFile(endpointsPath, buffer.toString());
    print('\n   📄 Endpoints → lib/utils/network/endpoints.dart');
  }

  // ── Barrel Exports ──────────────────────────────────────────────────────

  void _generateBarrelExports(
    Iterable<String> groups,
    Map<String, List<SwaggerOperation>> groupOps,
  ) {
    final allExports = <String>[];
    final groupedExports = <String, List<String>>{};

    for (final group in groups) {
      final groupExports = <String>[];

      // 1. Generate models barrel (granular)
      final modelsPath = '$libDir/api/$group/models';
      final modelsDir = Directory(modelsPath);
      if (modelsDir.existsSync()) {
        final exports = <String>[];
        for (final entity in modelsDir.listSync()) {
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              !entity.path.endsWith('models.dart')) {
            final fileName = entity.path.split('/').last.split(r'\').last;
            exports.add("export '$fileName';");
          }
        }
        if (exports.isNotEmpty) {
          exports.sort();
          final buffer = StringBuffer();
          buffer.writeln(_fileHeader('Models Barrel: $group'));
          for (final e in exports) {
            buffer.writeln(e);
          }
          _writeFile('$modelsPath/models.dart', buffer.toString());
          print('   📄 Models Barrel: api/$group/models/models.dart');
          groupExports.add('models/models.dart');
        }
      }

      // 2. Add controller barrel to group exports (only if group has operations)
      final groupHasOps =
          groupOps.containsKey(group) && groupOps[group]!.isNotEmpty;
      if (groupHasOps && !skipGroups.contains(group)) {
        groupExports.add('controller/controller.dart');
      }

      // 3. Generate comprehensive group-level barrel file
      if (groupExports.isNotEmpty) {
        _generateGroupBarrelFile(group, groupExports);
        groupedExports[group] = groupExports;
      }

      // 4. Collect for global api barrel
      for (final export in groupExports) {
        allExports.add("export '$group/$export';");
      }
    }

    // 5. Generate enhanced root api.dart barrel
    if (allExports.isNotEmpty) {
      _generateRootApiBarrel(groupedExports);
      print('   📄 Global Barrel: lib/api/api.dart');
    }
  }

  // ── Group-Level Barrel File ───────────────────────────────────────────────

  /// Generates a comprehensive barrel file for a specific group.
  /// This allows developers to import the entire feature with one line.
  void _generateGroupBarrelFile(String group, List<String> exports) {
    final pascal = _pascalCase(group);
    final buffer = StringBuffer();

    buffer.writeln(_fileHeader('Feature Barrel: $pascal'));
    buffer.writeln('/// Complete export for ${_humanize(group)} feature.');
    buffer.writeln('///');
    buffer.writeln(
      '/// This barrel file exports all components for the $group feature:',
    );
    buffer.writeln('/// - Models/DTOs');
    buffer.writeln('/// - Repository (API layer)');
    buffer.writeln('/// - Service (business logic layer)');
    buffer.writeln('/// - Service state classes');
    buffer.writeln('///');
    buffer.writeln('/// ## Usage in your feature module');
    buffer.writeln('///');
    buffer.writeln(
      '/// Copy this entire folder to `lib/$group/controller/` and import:',
    );
    buffer.writeln('/// ```dart');
    buffer.writeln("/// import '$_pkg/api/$group/$group.dart';");
    buffer.writeln('/// ```');
    buffer.writeln('///');
    buffer.writeln('/// Or after copying, adjust imports to:');
    buffer.writeln('/// ```dart');
    buffer.writeln("/// import '$_pkg/$group/controller/repository.dart';");
    buffer.writeln("/// import '$_pkg/$group/controller/service.dart';");
    buffer.writeln('/// ```');
    buffer.writeln('library;');
    buffer.writeln();

    // Organize exports by category
    final modelExports = exports.where((e) => e.startsWith('models/')).toList();
    final controllerExports = exports
        .where((e) => e.startsWith('controller/'))
        .toList();

    if (modelExports.isNotEmpty) {
      buffer.writeln(
        '// ── Models ──────────────────────────────────────────────────────────────',
      );
      for (final e in modelExports) {
        buffer.writeln("export '$e';");
      }
      buffer.writeln();
    }

    if (controllerExports.isNotEmpty) {
      buffer.writeln(
        '// ── Controller ──────────────────────────────────────────────────────────',
      );
      for (final e in controllerExports) {
        buffer.writeln("export '$e';");
      }
    }

    final filePath = '$libDir/api/$group/$group.dart';
    _writeFile(filePath, buffer.toString());
    print('   📄 Group Barrel: api/$group/$group.dart');
  }

  // ── Enhanced Root API Barrel ──────────────────────────────────────────────

  /// Generates the root api.dart with clear organization and documentation.
  void _generateRootApiBarrel(Map<String, List<String>> groupedExports) {
    final buffer = StringBuffer();
    buffer.writeln(_fileHeader('Root API Barrel'));
    buffer.writeln('/// Central export point for all generated API code.');
    buffer.writeln('///');
    buffer.writeln('/// ## Available Features');
    buffer.writeln('///');

    final sortedGroups = groupedExports.keys.toList()..sort();
    for (final group in sortedGroups) {
      final pascal = _pascalCase(group);
      buffer.writeln(
        '/// - **$pascal**: ${groupedExports[group]!.length} exports',
      );
    }
    buffer.writeln('///');
    buffer.writeln('/// ## Quick Import');
    buffer.writeln('///');
    buffer.writeln('/// Import a specific feature:');
    buffer.writeln('/// ```dart');
    if (sortedGroups.isNotEmpty) {
      buffer.writeln(
        "/// import '$_pkg/api/${sortedGroups.first}/${sortedGroups.first}.dart';",
      );
    }
    buffer.writeln('/// ```');
    buffer.writeln('///');
    buffer.writeln('/// Or import everything:');
    buffer.writeln('/// ```dart');
    buffer.writeln("/// import '$_pkg/api/api.dart';");
    buffer.writeln('/// ```');
    buffer.writeln('library;');
    buffer.writeln();

    for (final group in sortedGroups) {
      for (final export in groupedExports[group]!) {
        buffer.writeln("export '$group/$export';");
      }
    }

    _writeFile('$libDir/api/api.dart', buffer.toString());
  }

  // ── Group README Generation ───────────────────────────────────────────────

  /// Generates a README.md file for each group with usage instructions,
  /// endpoint documentation, and copy-paste guidance.
  void _generateGroupReadmes(Map<String, List<SwaggerOperation>> groupOps) {
    print('\n── 📝 README Files ────────────────────────────────────────');

    for (final entry in groupOps.entries) {
      final group = entry.key;
      final ops = entry.value;

      if (skipGroups.contains(group)) continue;

      final pascal = _pascalCase(group);
      final repoClass = '${pascal}Repository';
      final serviceClass = '${pascal}Service';

      final buffer = StringBuffer();

      // Header
      buffer.writeln('# $pascal API');
      buffer.writeln();
      buffer.writeln('Generated API layer for ${_humanize(group)} operations.');
      buffer.writeln();

      // Structure
      buffer.writeln('## 📁 Structure');
      buffer.writeln();
      buffer.writeln('```');
      buffer.writeln('$group/');
      buffer.writeln('├── $group.dart              # Complete barrel export');
      buffer.writeln('├── models/');
      buffer.writeln('│   └── models.dart          # Models barrel');
      buffer.writeln('├── repositories/');
      buffer.writeln('│   └── ${_camelToSnake(group)}_repository.dart');
      buffer.writeln('└── services/');
      buffer.writeln('    ├── ${_camelToSnake(group)}_service_state.dart');
      buffer.writeln('    └── ${_camelToSnake(group)}_service.dart');
      buffer.writeln('```');
      buffer.writeln();

      // Available Operations
      buffer.writeln('## 🎯 Available Operations');
      buffer.writeln();
      buffer.writeln(
        'This feature provides ${ops.length} API operation${ops.length != 1 ? 's' : ''}:',
      );
      buffer.writeln();

      final sortedOps = ops.toList()..sort((a, b) => a.path.compareTo(b.path));
      for (final op in sortedOps) {
        final methodName = _sanitizeMethodName(_operationToMethodName(op));
        final method = op.method.toUpperCase();
        buffer.writeln('- **`$methodName()`** - $method `${op.path}`');
        if (op.summary.isNotEmpty) {
          buffer.writeln('  - ${op.summary}');
        }
      }
      buffer.writeln();

      // Quick Start
      buffer.writeln('## 🚀 Quick Start');
      buffer.writeln();
      buffer.writeln('### Option 1: Use directly from api folder');
      buffer.writeln();
      buffer.writeln('```dart');
      buffer.write('import ');
      buffer.write("'");
      buffer.write('$_pkg/api/$group/$group.dart');
      buffer.writeln("';");
      buffer.writeln();
      buffer.writeln('// In your code');
      buffer.writeln('final service = $serviceClass();');
      buffer.writeln('final result = await service.someMethod();');
      buffer.writeln('```');
      buffer.writeln();

      buffer.writeln('### Option 2: Copy to feature module');
      buffer.writeln();
      buffer.writeln('1. **Copy this folder** to `lib/$group/controller/`');
      buffer.writeln('2. **Update imports** in the copied files:');
      buffer.writeln('   ```dart');
      buffer.write('   // Change from: import ');
      buffer.writeln("'$_pkg/api/...'");
      buffer.write('   // To: import ');
      buffer.writeln("'$_pkg/$group/controller/...'");
      buffer.writeln('   ```');
      buffer.writeln(
        '3. **Register service** in `lib/core/di/injection_container.dart`:',
      );
      buffer.writeln('   ```dart');
      buffer.writeln('   getIt.registerLazySingleton($serviceClass.new);');
      buffer.writeln('   ```');
      buffer.writeln();

      // Repository Usage
      buffer.writeln('## 🔧 Repository Usage');
      buffer.writeln();
      buffer.writeln(
        'The `$repoClass` extends `ApiClient` and provides direct API access:',
      );
      buffer.writeln();
      buffer.writeln('```dart');
      buffer.writeln('final repository = $repoClass();');
      if (ops.isNotEmpty) {
        final firstOp = ops.first;
        final methodName = _sanitizeMethodName(_operationToMethodName(firstOp));
        buffer.writeln('final data = await repository.$methodName();');
      }
      buffer.writeln('```');
      buffer.writeln();

      // Service Usage
      buffer.writeln('## 📡 Service Usage (with State Management)');
      buffer.writeln();
      buffer.writeln(
        'The `$serviceClass` extends the repository and adds reactive state:',
      );
      buffer.writeln();
      buffer.writeln('```dart');
      buffer.writeln('final service = $serviceClass();');
      buffer.writeln();
      buffer.writeln('// Listen to state changes');
      buffer.writeln('service.onStateChanges.listen((state) {');
      buffer.writeln('  if (state.isLoading) {');
      buffer.writeln('    // Show loading indicator');
      buffer.writeln('  } else if (state.isSuccess) {');
      buffer.writeln('    // Handle success: state.data');
      buffer.writeln('  } else if (state.isError) {');
      buffer.writeln('    // Handle error: state.error');
      buffer.writeln('  }');
      buffer.writeln('});');
      buffer.writeln();
      if (ops.isNotEmpty) {
        final firstOp = ops.first;
        final methodName = _sanitizeMethodName(_operationToMethodName(firstOp));
        buffer.writeln('// Call API methods (emits state changes)');
        buffer.writeln(
          'await service.stream${methodName[0].toUpperCase()}${methodName.substring(1)}();',
        );
      }
      buffer.writeln();
      buffer.writeln('service.dispose();');
      buffer.writeln('```');
      buffer.writeln();

      // Customization
      buffer.writeln('## ✏️ Customization');
      buffer.writeln();
      buffer.writeln(
        'The service file is generated as a **stub** and preserved on subsequent generations.',
      );
      buffer.writeln('Feel free to add:');
      buffer.writeln();
      buffer.writeln('- Custom business logic');
      buffer.writeln('- Data transformation');
      buffer.writeln('- Caching strategies');
      buffer.writeln('- Additional state management (e.g., ChangeNotifier)');
      buffer.writeln('- Error handling logic');
      buffer.writeln();

      // Dependencies
      buffer.writeln('## 📦 Dependencies');
      buffer.writeln();
      buffer.writeln(
        '- `ApiClient` - Base HTTP client (from `utils/network/client.dart`)',
      );
      buffer.writeln(
        '- `ApiResponse` - Response wrapper (from `utils/network/model.dart`)',
      );
      final requiresAuth = ops.any((op) => op.requiresAuth);
      if (requiresAuth) {
        buffer.writeln(
          '- `AuthInterceptor` - Token injection (from `auth/controller/interceptor.dart`)',
        );
      }
      buffer.writeln();

      // Notes
      buffer.writeln('## 📌 Notes');
      buffer.writeln();
      buffer.writeln(
        '- **Repository**: Contains actual HTTP call implementations',
      );
      buffer.writeln('- **Service**: Wraps repository with state management');
      buffer.writeln(
        '- **State**: Typed state class with loading/success/error variants',
      );
      buffer.writeln('- **Models**: Auto-generated from Swagger definitions');
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
      buffer.writeln(
        '*Generated by `swagger_codegen.dart` - DO NOT EDIT THIS FILE*',
      );

      final readmePath = '$libDir/api/$group/README.md';
      _writeFile(readmePath, buffer.toString());
      print('   📝 README: api/$group/README.md');
    }
  }

  // ── Dependency Injection ──────────────────────────────────────────────────

  void _injectDependenciesInBootstrap(Iterable<String> groups) {
    if (dryRun) return;
    final diFile = File('$libDir/core/di/injection_container.dart');
    if (!diFile.existsSync()) return;

    var content = diFile.readAsStringSync();

    // Ensure required barrel imports exist
    final requiredImports = [
      "import '$_pkg/api/api.dart';",
      "import '$_pkg/utils/utils.dart';",
    ];
    for (final imp in requiredImports) {
      final packageName = imp.split("'")[1];
      if (!content.contains(packageName)) {
        final lastImportIdx = content.lastIndexOf(
          RegExp(r'^import .*;\n', multiLine: true),
        );
        if (lastImportIdx != -1) {
          final endOfLastImport = content.indexOf('\n', lastImportIdx) + 1;
          content =
              '${content.substring(0, endOfLastImport)}$imp\n${content.substring(endOfLastImport)}';
          print('   📦 Added import: $imp');
        }
      }
    }

    // ── Build the generated registration lines ──────────────────────────
    const marker = '// -- Generated Services (from swagger_codegen) --';

    final generatedLines = <String>[];
    for (final group in groups) {
      if (skipGroups.contains(group)) continue;

      final pascal = _pascalCase(group);
      final serviceClass = '${pascal}Service';

      // Check if already manually registered (outside the generated section)
      final contentWithoutGenerated = _stripGeneratedBlock(content, marker);
      if (RegExp(
        'register\\w*<$serviceClass>',
      ).hasMatch(contentWithoutGenerated)) {
        continue; // Already manually registered
      }

      generatedLines.add('    ..registerLazySingleton($serviceClass.new)');
      print('   💉 Injecting: $serviceClass');
    }

    // ── Replace/insert the generated block ──────────────────────────────
    if (content.contains(marker)) {
      final markerIdx = content.indexOf(marker);
      final afterMarker = markerIdx + marker.length;
      final nextSectionMatch = RegExp(
        r'\n\s+// [A-Z]',
      ).firstMatch(content.substring(afterMarker));
      final endIdx = nextSectionMatch != null
          ? afterMarker + nextSectionMatch.start
          : afterMarker;
      final replacement = generatedLines.isNotEmpty
          ? '\n${generatedLines.join('\n')}\n'
          : '\n';
      content =
          '${content.substring(0, afterMarker)}$replacement${content.substring(endIdx)}';
    } else {
      final servicesMatch = RegExp(
        r'(\n\s+// Services & Controllers)',
      ).firstMatch(content);
      if (servicesMatch != null) {
        final block = generatedLines.isNotEmpty
            ? '\n    $marker\n${generatedLines.join('\n')}\n'
            : '\n    $marker\n';
        content =
            '${content.substring(0, servicesMatch.start)}$block${content.substring(servicesMatch.start)}';
      }
    }

    // Remove old generated blocks
    const oldMarker =
        '// -- Generated Remote DataSources & Repositories (from swagger_codegen) --';
    if (content.contains(oldMarker)) {
      final markerIdx = content.indexOf(oldMarker);
      final afterMarker = markerIdx + oldMarker.length;
      final nextSectionMatch = RegExp(
        r'\n\s+// [A-Z]',
      ).firstMatch(content.substring(afterMarker));
      final endIdx = nextSectionMatch != null
          ? afterMarker + nextSectionMatch.start
          : afterMarker;
      content =
          '${content.substring(0, markerIdx)}${content.substring(endIdx)}';
    }

    final stalePattern = RegExp(
      r'^\s+\.\.register\w+<I\w+(?:RemoteDataSource|Repository)>\([^)]*\)\n',
      multiLine: true,
    );
    content = content.replaceAll(stalePattern, '');

    diFile.writeAsStringSync(content);
    print('   📄 Updated lib/core/di/injection_container.dart');
  }

  /// Strip the generated block between marker and next section for duplicate-checking
  String _stripGeneratedBlock(String content, String marker) {
    if (!content.contains(marker)) return content;
    final markerIdx = content.indexOf(marker);
    final afterMarker = markerIdx + marker.length;
    final nextSection = RegExp(
      r'\n\s+// [A-Z]',
    ).firstMatch(content.substring(afterMarker));
    final endIdx = nextSection != null
        ? afterMarker + nextSection.start
        : afterMarker;
    return '${content.substring(0, markerIdx)}${content.substring(endIdx)}';
  }

  // ── Import Helpers ──────────────────────────────────────────────────────

  /// Check if a model from a skipped group is referenced by any non-skipped operation
  bool _isModelReferencedByNonSkippedGroup(
    String modelName,
    Map<String, List<SwaggerOperation>> groupOps,
    Map<String, SwaggerDefinition> responseDefs,
  ) {
    for (final entry in groupOps.entries) {
      if (skipGroups.contains(entry.key)) continue;
      for (final op in entry.value) {
        final returnType = _determineReturnType(op, responseDefs);
        if (returnType.contains(modelName)) return true;
      }
    }
    return false;
  }

  // ── File I/O ────────────────────────────────────────────────────────────

  void _writeFile(String path, String content) {
    final normalizedPath = path.replaceAll(r'\', '/');
    _writtenFiles.add(normalizedPath);

    if (dryRun) {
      print('   [DRY RUN] Would write: $path');
      return;
    }
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  // ── Cleanup Stale Files ──────────────────────────────────────────────────

  void _cleanupStaleGeneratedFiles() {
    print('\n── 🧹 Cleaning Up Stale Files ────────────────────────────────');
    final apiDir = Directory('$libDir/api');

    var deletedCount = 0;
    if (apiDir.existsSync()) {
      for (final entity in apiDir.listSync(recursive: true)) {
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.endsWith('_test.dart')) {
          final normalizedPath = entity.path.replaceAll(r'\', '/');

          if (!_writtenFiles.contains(normalizedPath)) {
            // Check if it's actually an auto-generated file
            final content = entity.readAsStringSync();
            if (content.contains('// Generated by swagger_codegen.dart')) {
              if (!dryRun) entity.deleteSync();
              print('   🗑 Deleted stale: $normalizedPath');
              deletedCount++;
            }
          }
        }
      }

      // Remove empty directories
      for (final entity
          in apiDir
              .listSync(recursive: true)
              .whereType<Directory>()
              .toList()
              .reversed) {
        if (entity.listSync().isEmpty) {
          if (!dryRun) entity.deleteSync();
          print('   🗑 Deleted empty dir: ${entity.path}');
        }
      }
    }

    if (deletedCount == 0) {
      print('   ✅ No stale files found');
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  List<String> _buildMethodParams(SwaggerOperation op) {
    final params = <String>[];

    if ((op.formParams.isNotEmpty ||
            op.parameters.any((p) => p.location == 'body')) &&
        (op.method == 'post' ||
            op.method == 'put' ||
            op.method == 'patch' ||
            op.method == 'delete')) {
      final requestModelName = _operationToRequestModelName(op);
      params.add('required ${requestModelName}Model request');
    }

    for (final param in op.queryParams) {
      final required = param.required_ ? 'required ' : '';
      final nullable = param.required_ ? '' : '?';
      params.add('$required${param.dartType}$nullable ${param.dartName}');
    }

    for (final param in op.pathParams) {
      params.add('required ${param.dartType} ${param.dartName}');
    }

    return params;
  }

  String _determineReturnType(
    SwaggerOperation op,
    Map<String, SwaggerDefinition> responseDefs, {
    bool forModel = false,
  }) {
    final successRef = op.successResponseRef;
    if (successRef == null || successRef == 'SuccessResponse') return 'bool';

    if (successRef.contains('Login') ||
        successRef.contains('Register') ||
        successRef.contains('Verify')) {
      return forModel ? 'UserModel' : 'User';
    }

    final responseDef = responseDefs[successRef];
    if (responseDef == null) return 'dynamic';

    final payloadProp =
        responseDef.properties['payload'] ?? responseDef.properties['data'];
    if (payloadProp == null) return 'dynamic';

    if (payloadProp.type == 'array' && payloadProp.itemsRef != null) {
      final itemType =
          definitionRenames[payloadProp.itemsRef!] ?? payloadProp.itemsRef!;
      final typeToUse = forModel ? '${itemType}Model' : itemType;
      if (responseDef.properties.containsKey('paginator')) {
        return '({List<$typeToUse> items, Paginator paginator})';
      }
      return 'List<$typeToUse>';
    }
    if (payloadProp.ref != null) {
      final typeName = definitionRenames[payloadProp.ref!] ?? payloadProp.ref!;
      return forModel ? '${typeName}Model' : typeName;
    }
    return 'dynamic';
  }

  bool _isPaginatedResponse(
    SwaggerOperation op,
    Map<String, SwaggerDefinition> responseDefs,
  ) {
    final successRef = op.successResponseRef;
    if (successRef == null) return false;
    return responseDefs[successRef]?.properties.containsKey('paginator') ??
        false;
  }

  String _operationToMethodName(SwaggerOperation op) {
    // Check overrides
    if (methodRenames.containsKey(op.operationId)) {
      return methodRenames[op.operationId]!;
    }
    final pathKey = '${op.path}:${op.method}';
    if (methodRenames.containsKey(pathKey)) return methodRenames[pathKey]!;

    // Handle empty or missing operationId by generating from path + method
    if (op.operationId.isEmpty) {
      final pathParts = op.path
          .split('/')
          .where((s) => s.isNotEmpty && !s.startsWith('{'))
          .toList();
      if (pathParts.isEmpty) return '${op.method}Root';
      return _snakeToCamel('${op.method}_${pathParts.join('_')}');
    }

    final parts = op.operationId.split('_');
    String name;
    if (parts.length >= 3) {
      final meaningful = parts.sublist(2).where((s) => s.isNotEmpty).toList();
      if (meaningful.isEmpty) {
        name = _snakeToCamel(op.operationId);
      } else {
        name =
            meaningful.first +
            meaningful
                .sublist(1)
                .map(
                  (s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1),
                )
                .join();
      }
    } else {
      name = _snakeToCamel(op.operationId);
    }

    // Guard against empty name
    if (name.isEmpty) {
      final pathParts = op.path
          .split('/')
          .where((s) => s.isNotEmpty && !s.startsWith('{'))
          .toList();
      name = _snakeToCamel('${op.method}_${pathParts.join('_')}');
    }

    // Prevent methods from being named exactly like common HTTP methods
    // because repository implementations extend ApiClient which already has these.
    const forbiddenNames = {
      'get',
      'post',
      'put',
      'delete',
      'patch',
      'update',
      'remove',
    };
    if (forbiddenNames.contains(name)) {
      var prefix = parts.isNotEmpty ? parts[0] : '';

      // Simple singularization for common resource names
      if (prefix.endsWith('ies')) {
        prefix = '${prefix.substring(0, prefix.length - 3)}y';
      } else if (prefix.endsWith('s') &&
          !prefix.endsWith('ss') &&
          !prefix.endsWith('us')) {
        prefix = prefix.substring(0, prefix.length - 1);
      }

      if (prefix.isNotEmpty) {
        final featureCamel = _snakeToCamel(prefix);
        name = featureCamel + name[0].toUpperCase() + name.substring(1);
      }
    }

    return name;
  }

  String _operationToRequestModelName(SwaggerOperation op) {
    final method = _operationToMethodName(op);
    if (method.isEmpty) return 'UnknownRequest';
    final name = '${method[0].toUpperCase()}${method.substring(1)}Request';
    return definitionRenames[name] ?? name;
  }

  String _endpointConstName(SwaggerOperation op) =>
      _sanitizeMethodName(_operationToMethodName(op));

  /// Helper to check if a definition should NOT get Model suffix
  bool _shouldSkipModelSuffix(String refName) {
    final dartRef = definitionRenames[refName] ?? refName;
    return skipDefinitions.contains(refName) ||
        skipDefinitions.contains(dartRef) ||
        _dynamicSkipDefinitions.contains(dartRef) ||
        _dynamicSkipDefinitions.contains('${dartRef}Model');
  }

  /// Returns field type for model classes (uses *Model type names for nested objects)
  String _dartFieldTypeForModel(SwaggerProperty prop) {
    if (prop.isNestedObject) {
      if (prop.ref != null) {
        final dartRef = definitionRenames[prop.ref!] ?? prop.ref!;
        return _shouldSkipModelSuffix(prop.ref!) ? dartRef : '${dartRef}Model';
      }
      return 'Map<String, dynamic>';
    }
    if (prop.isNestedList) {
      if (prop.itemsRef != null) {
        final dartRef = definitionRenames[prop.itemsRef!] ?? prop.itemsRef!;
        final modelRef = _shouldSkipModelSuffix(prop.itemsRef!)
            ? dartRef
            : '${dartRef}Model';
        return 'List<$modelRef>';
      }
      return 'List<Map<String, dynamic>>';
    }
    switch (prop.type) {
      case 'integer':
      case 'int':
        return 'int';
      case 'number':
      case 'double':
        return 'double';
      case 'boolean':
      case 'bool':
        return 'bool';
      case 'array':
        if (prop.itemsType == 'integer' || prop.itemsType == 'int') {
          return 'List<int>';
        }
        if (prop.itemsType == 'number' || prop.itemsType == 'double') {
          return 'List<double>';
        }
        if (prop.itemsType == 'boolean' || prop.itemsType == 'bool') {
          return 'List<bool>';
        }
        return 'List<String>';
      default:
        return 'String';
    }
  }

  /// Same as _fromJsonExpression but uses *Model type names for nested refs
  String _fromJsonExpressionForModel(
    SwaggerProperty prop, [
    String? modelName,
  ]) {
    final jsonKey = prop.name;
    var expression = "json['$jsonKey']";

    // Handle flattened fields if configured
    if (modelName != null && flattenedFields.containsKey(modelName)) {
      final alternatives = flattenedFields[modelName]![prop.name];
      if (alternatives != null && alternatives.isNotEmpty) {
        final fallbackKeys = alternatives.map((k) => "json['$k']").join(' ?? ');
        expression = "($expression ?? $fallbackKeys)";
      }
    }

    if (prop.isNestedObject) {
      if (prop.ref != null) {
        final dartRef = definitionRenames[prop.ref!] ?? prop.ref!;
        final isSkipped = _shouldSkipModelSuffix(prop.ref!);
        final modelRef = isSkipped ? dartRef : '${dartRef}Model';

        // Product video and other fields might be returned as a String URL or a Map
        return "($expression is Map) ? $modelRef.fromJson($expression as Map<String, dynamic>) : ($expression is String ? $modelRef.fromJson({'fileUrl': $expression, 'url': $expression, 'path': $expression, 'id': $expression, 'name': $expression}) : $modelRef.fromJson({}))";
      } else {
        return "$expression is Map ? $expression as Map<String, dynamic> : {}";
      }
    }

    if (prop.isNestedList) {
      if (prop.itemsRef != null) {
        final dartRef = definitionRenames[prop.itemsRef!] ?? prop.itemsRef!;
        final isSkipped = _shouldSkipModelSuffix(prop.itemsRef!);
        final modelRef = isSkipped ? dartRef : '${dartRef}Model';
        return "($expression as List<dynamic>?)?.whereType<Map<String, dynamic>>().map((e) => $modelRef.fromJson(e)).toList() ?? []";
      } else {
        return "($expression as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList() ?? []";
      }
    }

    if (prop.type == 'array') {
      if (prop.itemsType == 'integer' || prop.itemsType == 'int') {
        return "($expression as List<dynamic>?)?.map((e) => tryParseInt(e) ?? 0).toList() ?? []";
      }
      if (prop.itemsType == 'number' || prop.itemsType == 'double') {
        return "($expression as List<dynamic>?)?.map((e) => tryParseDouble(e) ?? 0.0).toList() ?? []";
      }
      return "($expression as List<dynamic>?)?.map((e) => e.toString()).toList() ?? []";
    }

    switch (prop.type) {
      case 'integer':
      case 'int':
        return "tryParseInt($expression)";
      case 'number':
      case 'double':
        return "tryParseDouble($expression)";
      case 'boolean':
      case 'bool':
        return "tryParseBool($expression)";
      default:
        return "tryParseString($expression)";
    }
  }

  String _toJsonExpression(SwaggerProperty prop) {
    if (prop.isNestedObject) {
      if (prop.ref == null) return prop.dartName;
      return '${prop.dartName}?.toJson()';
    }
    if (prop.isNestedList) {
      if (prop.itemsRef == null) return '${prop.dartName}?.toList()';
      return '${prop.dartName}?.map((e) => e.toJson()).toList()';
    }
    return prop.dartName;
  }

  // (Removed entity methods)

  void _addModelImportForRef(Set<String> modelImports, String refName) {
    final refDartName = definitionRenames[refName] ?? refName;

    if (customImportPaths.containsKey(refName)) {
      modelImports.add(
        customImportPaths[refName]!.replaceAll('{pkg}', packageName),
      );
      return;
    }

    if (_dynamicCustomImports.containsKey(refDartName)) {
      modelImports.add(_dynamicCustomImports[refDartName]!);
      return;
    }

    final existingPath = _modelImportPaths[refName];
    if (existingPath != null) {
      modelImports.add(existingPath);
    } else {
      final refGroup = _definitionToGroup[refName];
      if (refGroup != null) {
        modelImports.add(
          '$_pkg/api/$refGroup/models/${_camelToSnake(refDartName)}_model.dart',
        );
      }
    }
  }

  bool _isRequired(SwaggerProperty prop) {
    if (prop.name == 'id') return true;
    if (prop.isNestedObject || prop.isNestedList) return false;
    if (prop.type == 'array') return true;
    return true;
  }
}

class _RequestProp {
  _RequestProp({
    required this.name,
    required this.dartName,
    required this.dartType,
    required this.isRequired,
    this.ref,
    this.itemsRef,
  });

  final String name;
  final String dartName;
  final String dartType;
  final bool isRequired;
  final String? ref;
  final String? itemsRef;
}

// ─── String Utilities ──────────────────────────────────────────────────────

/// Dart reserved words, built-in identifiers, and contextual keywords.
const _dartReservedKeywords = <String>{
  // Reserved words
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue',
  'default', 'do', 'else', 'enum', 'extends', 'false', 'final', 'finally',
  'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super',
  'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with',
  // Built-in identifiers
  'abstract', 'as', 'covariant', 'deferred', 'dynamic', 'export',
  'extension', 'external', 'factory', 'Function', 'get', 'implements',
  'import', 'interface', 'late', 'library', 'mixin', 'operator', 'part',
  'required', 'set', 'static', 'typedef',
  // Contextual keywords
  'async', 'await', 'hide', 'of', 'on', 'show', 'sync', 'yield',
};

/// Method names generated on every model class — field names must not collide.
const _reservedMethodNames = <String>{
  'toJson',
  'fromJson',
  'copyWith',
  'toString',
  'hashCode',
  'noSuchMethod',
  'runtimeType',
};

String _snakeToCamel(String input) {
  final parts = input.split(RegExp(r'[_\-.]'));
  if (parts.isEmpty) return input;
  return parts.first +
      parts
          .sublist(1)
          .map((s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1))
          .join();
}

/// Produce a valid, collision-free Dart field name from any Swagger name.
///
/// Handles: bracket-indexed params, reserved keywords, digit-prefixed names,
/// empty names, and method-name collisions.
String _safeDartName(String raw) {
  // 1. For bracket-indexed params like `children_list[0][first_name]`,
  //    extract prefix and inner field names to build a composite name.
  final bracketIndexed = RegExp(r'^([^\[]+)\[\d+\]\[([^\]]+)\]$');
  final match = bracketIndexed.firstMatch(raw);
  String cleaned;
  if (match != null) {
    // e.g. children_list[0][first_name] → children_list_first_name
    cleaned = '${match.group(1)}_${match.group(2)}';
  } else {
    // Strip any remaining bracket content (e.g. items[] → items)
    cleaned = raw.replaceAll(RegExp(r'\[.*?\]'), '');
  }

  // 2. Convert to camelCase
  var result = _snakeToCamel(cleaned);

  // 3. If empty, provide a fallback
  if (result.isEmpty) result = 'field';

  // 4. If starts with digit, prepend 'field'
  if (result.isNotEmpty && RegExp(r'^[0-9]').hasMatch(result)) {
    result = 'field${result[0].toUpperCase()}${result.substring(1)}';
  }

  // 5. If Dart reserved keyword, append 'Field'
  if (_dartReservedKeywords.contains(result)) {
    result = '${result}Field';
  }

  // 6. If collides with a generated method name, append 'Value'
  if (_reservedMethodNames.contains(result)) {
    result = '${result}Value';
  }

  return result;
}

/// Strip characters that are invalid in Dart identifiers.
/// Replaces special chars with spaces, then collapses whitespace.
String _sanitizeForIdentifier(String input) {
  return input
      .replaceAll(RegExp(r'[^a-zA-Z0-9_\s\-]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _camelToSnake(String input) {
  // Strip any remaining special chars first
  final cleaned = input.replaceAll(RegExp('[^a-zA-Z0-9_]'), '');
  return cleaned
      .replaceAllMapped(
        RegExp('([A-Z])'),
        (m) => '_${m.group(1)!.toLowerCase()}',
      )
      .replaceAll(RegExp('^_'), '');
}

String _pascalCase(String input) {
  // Split on underscores, hyphens, spaces, and any non-alphanumeric chars
  final parts = input.split(RegExp(r'[_\-\s&,/|+]+'));
  return parts.map((s) {
    if (s.isEmpty) return '';
    // Strip any remaining special chars
    final cleaned = s.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
    if (cleaned.isEmpty) return '';
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }).join();
}

String _humanize(String input) {
  return input
      .split('_')
      .map((s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1))
      .join(' ');
}

// _dartFieldTypeForModel has been moved into CodeGenerator class
// to support proper Model suffix logic with skip checks.
