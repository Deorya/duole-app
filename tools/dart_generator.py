"""Generate dependency-free Dart consumer models from the canonical contract."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
from typing import Any, Mapping


def generate_dart_models(openapi_path: str | Path, output_path: str | Path) -> None:
    """Render and write the Dart consumer represented by ``openapi_path``."""

    source_path = Path(openapi_path)
    raw_contract = source_path.read_bytes()
    document = json.loads(raw_contract)
    rendered = render_dart_models(
        document,
        contract_sha256=hashlib.sha256(raw_contract).hexdigest(),
    )
    destination = Path(output_path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(rendered, encoding="utf-8")


def render_dart_models(
    document: Mapping[str, Any],
    *,
    contract_sha256: str,
) -> str:
    """Return deterministic Dart source for the supported OpenAPI schemas."""

    if document.get("openapi") != "3.1.0":
        raise ValueError("Dart models require the DUOLE OpenAPI 3.1.0 contract")
    schemas = document.get("components", {}).get("schemas", {})
    if not isinstance(schemas, Mapping):
        raise ValueError("OpenAPI components.schemas must be an object")

    enum_names = {
        name
        for name, schema in schemas.items()
        if isinstance(schema, Mapping) and "enum" in schema
    }
    sections = [
        "// GENERATED CODE - DO NOT MODIFY BY HAND.",
        f"// contract-sha256: {contract_sha256}",
        "",
        _helpers(),
        _render_contract_policy(document),
        _render_request_policy(document),
    ]
    for name, schema in schemas.items():
        if not isinstance(schema, Mapping):
            raise ValueError(f"schema {name} must be an object")
        if "enum" in schema:
            sections.append(_render_enum(str(name), schema))
        elif _has_schema_type(schema, "object"):
            sections.append(
                _render_object(str(name), schema, enum_names, schemas)
            )
    return "\n\n".join(section.rstrip() for section in sections if section) + "\n"


def _render_contract_policy(document: Mapping[str, Any]) -> str:
    version = str(document.get("info", {}).get("version", ""))
    policy = document.get("x-duole-contract", {}).get("compatibility", {})
    if not version or not isinstance(policy, Mapping):
        raise ValueError("contract version and compatibility policy are required")
    if policy.get("write_requires_same_api_major") is not True:
        raise ValueError("contract must fail closed on API major mismatch")
    diagnostics_allowed = (
        "true" if policy.get("diagnostics_allowed_on_major_mismatch") is True else "false"
    )
    error_code = _dart_enum_case(str(policy.get("error_code", "")))
    return f"""const String appContractVersion = {_dart_literal(version)};

class ApiCompatibilityDecision {{
  final bool writeAllowed;
  final bool diagnosticsAllowed;
  final ErrorCode? errorCode;

  const ApiCompatibilityDecision({{
    required this.writeAllowed,
    required this.diagnosticsAllowed,
    required this.errorCode,
  }});
}}

ApiCompatibilityDecision evaluateApiCompatibility(
  String serverApiVersion, {{
  String clientApiVersion = appContractVersion,
}}) {{
  final clientMajor = _apiMajor(clientApiVersion);
  final serverMajor = _apiMajor(serverApiVersion);
  if (clientMajor != null && serverMajor != null && clientMajor == serverMajor) {{
    return const ApiCompatibilityDecision(
      writeAllowed: true,
      diagnosticsAllowed: true,
      errorCode: null,
    );
  }}
  return const ApiCompatibilityDecision(
    writeAllowed: false,
    diagnosticsAllowed: {diagnostics_allowed},
    errorCode: ErrorCode.{error_code},
  );
}}

int? _apiMajor(String version) {{
  final match = RegExp(r'^(0|[1-9]\\d*)\\.').firstMatch(version);
  return match == null ? null : int.tryParse(match.group(1)!);
}}"""


def _render_request_policy(document: Mapping[str, Any]) -> str:
    policy = document.get("x-duole-contract", {}).get("request_metadata", {})
    if not isinstance(policy, Mapping):
        raise ValueError("request metadata policy is required")
    kinds = tuple(str(kind) for kind in policy.get("kinds", ()))
    header_policies = policy.get("headers", {})
    if not kinds or not isinstance(header_policies, Mapping):
        raise ValueError("request metadata kinds and headers are required")

    kind_members = ", ".join(_dart_enum_case(kind) for kind in kinds)
    policies: list[str] = []
    for key, raw_spec in header_policies.items():
        if not isinstance(raw_spec, Mapping):
            raise ValueError(f"request header policy {key} must be an object")
        required = ", ".join(
            f"RequestMetadataKind.{_dart_enum_case(str(kind))}"
            for kind in raw_spec.get("required_for", ())
        )
        args = [
            f"    {_dart_literal(str(raw_spec.get('wire_name', '')))},",
            f"    requiredFor: {{{required}}},",
        ]
        if raw_spec.get("pattern") is not None:
            args.append(
                f"    pattern: {_dart_raw_literal(str(raw_spec['pattern']))},"
            )
        if raw_spec.get("format") is not None:
            args.append(f"    format: {_dart_literal(str(raw_spec['format']))},")
        if raw_spec.get("type") is not None:
            args.append(f"    type: {_dart_literal(str(raw_spec['type']))},")
        if raw_spec.get("minimum") is not None:
            args.append(f"    minimum: {int(raw_spec['minimum'])},")
        if raw_spec.get("maximum") is not None:
            args.append(f"    maximum: {int(raw_spec['maximum'])},")
        policies.append(
            "  _RequestHeaderPolicy(\n" + "\n".join(args) + "\n  ),"
        )

    expiry = policy.get("expiry", {})
    if not isinstance(expiry, Mapping):
        raise ValueError("request expiry policy must be an object")
    sent_spec = header_policies.get(expiry.get("sent_at"), {})
    ttl_spec = header_policies.get(expiry.get("ttl_ms"), {})
    if not isinstance(sent_spec, Mapping) or not isinstance(ttl_spec, Mapping):
        raise ValueError("request expiry headers are invalid")
    sent_wire = _dart_literal(str(sent_spec.get("wire_name", "")))
    ttl_wire = _dart_literal(str(ttl_spec.get("wire_name", "")))
    future_skew = int(expiry.get("max_future_skew_ms", 0))
    policy_block = "\n".join(policies)
    return f"""enum RequestMetadataKind {{ {kind_members} }}

class ContractViolation {{
  final String path;
  final String message;

  const ContractViolation(this.path, this.message);
}}

class _RequestHeaderPolicy {{
  final String wireName;
  final Set<RequestMetadataKind> requiredFor;
  final String? pattern;
  final String? format;
  final String? type;
  final int? minimum;
  final int? maximum;

  const _RequestHeaderPolicy(
    this.wireName, {{
    required this.requiredFor,
    this.pattern,
    this.format,
    this.type,
    this.minimum,
    this.maximum,
  }});
}}

const _requestHeaderPolicies = <_RequestHeaderPolicy>[
{policy_block}
];

List<ContractViolation> validateRequestMetadata(
  RequestMetadataKind kind,
  Map<String, String> headers, {{
  required DateTime now,
}}) {{
  final normalized = {{
    for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
  }};
  final violations = <ContractViolation>[];
  for (final policy in _requestHeaderPolicies) {{
    final value = normalized[policy.wireName.toLowerCase()];
    final path = r'$.headers.' + policy.wireName;
    if (value == null) {{
      if (policy.requiredFor.contains(kind)) {{
        violations.add(
          ContractViolation(path, '${{policy.wireName}} is required for $kind'),
        );
      }}
      continue;
    }}
    if (policy.pattern != null && !RegExp(policy.pattern!).hasMatch(value)) {{
      violations.add(ContractViolation(path, 'header value has an invalid format'));
    }}
    if (policy.format == 'date-time' && !_isAwareDateTime(value)) {{
      violations.add(
        ContractViolation(path, 'expected RFC 3339 date-time with timezone'),
      );
    }}
    if (policy.type == 'integer') {{
      final number = int.tryParse(value);
      if (number == null) {{
        violations.add(ContractViolation(path, 'header value must be an integer'));
      }} else if (policy.minimum != null && number < policy.minimum!) {{
        violations.add(
          ContractViolation(path, 'header value is below ${{policy.minimum}}'),
        );
      }} else if (policy.maximum != null && number > policy.maximum!) {{
        violations.add(
          ContractViolation(path, 'header value is above ${{policy.maximum}}'),
        );
      }}
    }}
  }}

  final sentAtRaw = normalized[{sent_wire}.toLowerCase()];
  final ttlRaw = normalized[{ttl_wire}.toLowerCase()];
  final sentAt = sentAtRaw == null ? null : DateTime.tryParse(sentAtRaw);
  final ttlMs = ttlRaw == null ? null : int.tryParse(ttlRaw);
  if (sentAt != null && ttlMs != null) {{
    if (sentAt.isAfter(now.add(const Duration(milliseconds: {future_skew})))) {{
      violations.add(
        const ContractViolation(
          r'$.headers.{str(sent_spec.get("wire_name", ""))}',
          'request timestamp exceeds allowed future clock skew',
        ),
      );
    }} else if (now.isAfter(sentAt.add(Duration(milliseconds: ttlMs)))) {{
      violations.add(
        const ContractViolation(
          r'$.headers.{str(ttl_spec.get("wire_name", ""))}',
          'request has expired according to X-Sent-At and TTL',
        ),
      );
    }}
  }}
  return List.unmodifiable(violations);
}}

bool _isAwareDateTime(String value) {{
  return DateTime.tryParse(value) != null &&
      RegExp(r'(Z|[+-]\\d\\d:\\d\\d)$').hasMatch(value);
}}"""


def _render_enum(name: str, schema: Mapping[str, Any]) -> str:
    values = tuple(str(value) for value in schema["enum"])
    fallback = schema.get("x-duole-consumer-fallback")
    consumer_values = values + (
        (str(fallback),) if fallback is not None and fallback not in values else ()
    )
    members = ", ".join(_dart_enum_case(value) for value in consumer_values)
    cases = "\n".join(
        f"      {value!r} => {name}.{_dart_enum_case(value)}," for value in values
    )
    default = (
        f"      _ => {name}.{_dart_enum_case(str(fallback))},"
        if fallback is not None
        else f"      _ => throw FormatException('unknown {name}: $value'),"
    )
    enum_source = f"""enum {name} {{ {members} }}

{name} _decode{name}(Object? value, String path) {{
  if (value is! String) {{
    throw FormatException('$path must be a string');
  }}
  return switch (value) {{
{cases}
{default}
  }};
}}"""
    predicate = schema.get("x-duole-safety-predicate")
    if predicate is None:
        return enum_source
    if not isinstance(predicate, Mapping):
        raise ValueError(f"enum {name} safety predicate must be an object")
    predicate_name = str(predicate.get("name", ""))
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*", predicate_name):
        raise ValueError(f"enum {name} safety predicate name is invalid")
    allowed = tuple(str(value) for value in predicate.get("allowed", ()))
    if any(value not in values for value in allowed):
        raise ValueError(f"enum {name} safety predicate contains unknown value")
    allowed_cases = "\n".join(
        f"      {name}.{_dart_enum_case(value)} => true," for value in allowed
    )
    return f"""{enum_source}

extension {name}Safety on {name} {{
  bool get {predicate_name} => switch (this) {{
{allowed_cases}
      _ => false,
  }};
}}"""


def _render_object(
    name: str,
    schema: Mapping[str, Any],
    enum_names: set[str],
    schemas: Mapping[str, Any],
) -> str:
    properties = schema.get("properties", {})
    if not isinstance(properties, Mapping):
        raise ValueError(f"schema {name} properties must be an object")
    required = set(schema.get("required", ()))

    fields: list[str] = []
    constructor: list[str] = []
    decoders: list[str] = []
    constraint_checks: list[str] = []
    for wire_name, raw_property in properties.items():
        if not isinstance(raw_property, Mapping):
            raise ValueError(f"schema {name}.{wire_name} must be an object")
        field_name = _lower_camel(str(wire_name))
        dart_type = _dart_type(raw_property, schemas)
        if wire_name not in required and not dart_type.endswith("?"):
            dart_type += "?"
        fields.append(f"  final {dart_type} {field_name};")
        constructor.append(f"    required this.{field_name},")
        expression = _decode_expression(
            raw_property,
            f"_required(json, {str(wire_name)!r}, path)",
            f"'$path.{wire_name}'",
            enum_names,
            schemas,
        )
        if wire_name not in required:
            expression = (
                f"json.containsKey({str(wire_name)!r}) ? {expression} : null"
            )
        decoders.append(f"      {field_name}: {expression},")
        constraint_checks.extend(
            _render_property_constraints(
                field_name,
                str(wire_name),
                raw_property,
                dart_type,
            )
        )

    allowed = ", ".join(repr(str(key)) for key in properties)
    reject_unknown = ""
    if schema.get("additionalProperties") is False:
        reject_unknown = f"    _rejectUnknownKeys(json, const {{{allowed}}}, path);\n"
    one_of_check = _render_one_of_required_check(name, schema, properties)
    field_block = "\n".join(fields)
    constructor_block = "\n".join(constructor)
    decoder_block = "\n".join(decoders)
    check_block = "\n".join(constraint_checks)
    if check_block:
        check_block += "\n"
    return f"""class {name} {{
{field_block}

  const {name}({{
{constructor_block}
  }});

  factory {name}.fromJson(Map<String, Object?> json, {{String path = r'$'}}) {{
{reject_unknown}{one_of_check}    final result = {name}(
{decoder_block}
    );
{check_block}    return result;
  }}
}}"""


def _render_one_of_required_check(
    name: str,
    schema: Mapping[str, Any],
    properties: Mapping[str, Any],
) -> str:
    raw_alternatives = schema.get("oneOf")
    if raw_alternatives is None:
        return ""
    if not isinstance(raw_alternatives, list) or not raw_alternatives:
        raise ValueError(f"schema {name} oneOf must be a non-empty array")
    conditions: list[str] = []
    for raw_alternative in raw_alternatives:
        if not isinstance(raw_alternative, Mapping) or set(raw_alternative) != {
            "required"
        }:
            raise ValueError(
                f"schema {name} supports only required-field oneOf alternatives"
            )
        required_fields = raw_alternative.get("required")
        if not isinstance(required_fields, list) or not required_fields:
            raise ValueError(f"schema {name} oneOf required set is invalid")
        names = tuple(str(value) for value in required_fields)
        if len(set(names)) != len(names) or any(
            value not in properties for value in names
        ):
            raise ValueError(f"schema {name} oneOf required field is invalid")
        conditions.append(
            " && ".join(f"json.containsKey({value!r})" for value in names)
        )
    match_count = " + ".join(f"(({condition}) ? 1 : 0)" for condition in conditions)
    return (
        f"    if ({match_count} != 1) {{\n"
        "      throw FormatException(\n"
        "        '$path must match exactly one allowed field combination',\n"
        "      );\n"
        "    }\n"
    )


def _render_property_constraints(
    field_name: str,
    wire_name: str,
    schema: Mapping[str, Any],
    dart_type: str,
) -> list[str]:
    if "$ref" in schema:
        return []
    checks: list[str] = []
    field = f"result.{field_name}"
    nullable = dart_type.endswith("?")
    value = f"{field}!" if nullable else field

    def add(condition: str, message: str) -> None:
        guarded = f"{field} != null && ({condition})" if nullable else condition
        checks.append(
            f"    if ({guarded}) {{\n"
            f"      throw FormatException('$path.{wire_name} {message}');\n"
            "    }"
        )

    if "const" in schema:
        constant = _dart_literal(schema["const"])
        add(f"{value} != {constant}", f"must equal {constant}")
    if "enum" in schema:
        allowed_values = tuple(
            item for item in schema["enum"] if item is not None
        )
        allowed = ", ".join(_dart_literal(item) for item in allowed_values)
        add(
            f"!const <Object?>[{allowed}].contains({value})",
            "contains an unknown enum value",
        )
    if schema.get("minLength") is not None:
        minimum = int(schema["minLength"])
        add(f"{value}.length < {minimum}", f"must contain at least {minimum} characters")
    if schema.get("maxLength") is not None:
        maximum = int(schema["maxLength"])
        add(f"{value}.length > {maximum}", f"must contain at most {maximum} characters")
    if schema.get("pattern") is not None:
        pattern = _dart_raw_literal(str(schema["pattern"]))
        add(f"!RegExp({pattern}).hasMatch({value})", "has an invalid format")
    if schema.get("minimum") is not None:
        minimum = schema["minimum"]
        add(f"{value} < {minimum}", f"must be at least {minimum}")
    if schema.get("maximum") is not None:
        maximum = schema["maximum"]
        add(f"{value} > {maximum}", f"must be at most {maximum}")
    return checks


def _dart_type(
    schema: Mapping[str, Any],
    schemas: Mapping[str, Any],
) -> str:
    reference = schema.get("$ref")
    if reference is not None:
        target = str(reference).rsplit("/", 1)[-1]
        target_schema = schemas.get(target)
        nullable = (
            isinstance(target_schema, Mapping)
            and _has_schema_type(target_schema, "null")
        )
        return f"{target}?" if nullable else target
    raw_type = schema.get("type")
    nullable = isinstance(raw_type, list) and "null" in raw_type
    selected = next(
        (candidate for candidate in raw_type if candidate != "null"), None
    ) if isinstance(raw_type, list) else raw_type
    if selected == "string":
        result = "DateTime" if schema.get("format") == "date-time" else "String"
    elif selected == "integer":
        result = "int"
    elif selected == "number":
        result = "double"
    elif selected == "boolean":
        result = "bool"
    elif selected == "array":
        result = f"List<{_dart_type(schema['items'], schemas)}>"
    elif selected == "object":
        result = "Map<String, Object?>"
    else:
        raise ValueError(f"unsupported Dart schema type: {raw_type!r}")
    return f"{result}?" if nullable else result


def _decode_expression(
    schema: Mapping[str, Any],
    value: str,
    path: str,
    enum_names: set[str],
    schemas: Mapping[str, Any],
) -> str:
    reference = schema.get("$ref")
    if reference is not None:
        target = str(reference).rsplit("/", 1)[-1]
        if target in enum_names:
            return f"_decode{target}({value}, {path})"
        expression = f"{target}.fromJson(_asMap({value}, {path}), path: {path})"
        target_schema = schemas.get(target)
        if isinstance(target_schema, Mapping) and _has_schema_type(
            target_schema,
            "null",
        ):
            return f"{value} == null ? null : {expression}"
        return expression

    raw_type = schema.get("type")
    nullable = isinstance(raw_type, list) and "null" in raw_type
    selected = next(
        (candidate for candidate in raw_type if candidate != "null"), None
    ) if isinstance(raw_type, list) else raw_type
    if selected == "string":
        parser = "_asDateTime" if schema.get("format") == "date-time" else "_asString"
        expression = f"{parser}({value}, {path})"
    elif selected == "integer":
        expression = f"_asInt({value}, {path})"
    elif selected == "number":
        expression = f"_asDouble({value}, {path})"
    elif selected == "boolean":
        expression = f"_asBool({value}, {path})"
    elif selected == "array":
        item = _decode_expression(
            schema["items"],
            "item",
            "itemPath",
            enum_names,
            schemas,
        )
        expression = f"_asList({value}, {path}).asMap().entries.map((entry) {{\n"
        expression += f"        final item = entry.value;\n"
        expression += f"        final itemPath = {path} + '[${{entry.key}}]';\n"
        expression += f"        return {item};\n"
        expression += "      }).toList(growable: false)"
    elif selected == "object":
        expression = f"_asMap({value}, {path})"
    else:
        raise ValueError(f"unsupported Dart decoder type: {raw_type!r}")
    if nullable:
        return f"{value} == null ? null : {expression}"
    return expression


def _has_schema_type(schema: Mapping[str, Any], expected: str) -> bool:
    raw_type = schema.get("type")
    return raw_type == expected or (
        isinstance(raw_type, list) and expected in raw_type
    )


def _helpers() -> str:
    return r"""Object? _required(Map<String, Object?> json, String key, String path) {
  if (!json.containsKey(key)) {
    throw FormatException('$path.$key is required');
  }
  return json[key];
}

void _rejectUnknownKeys(
  Map<String, Object?> json,
  Set<String> allowed,
  String path,
) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$path.$key is not allowed');
    }
  }
}

Map<String, Object?> _asMap(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

List<Object?> _asList(Object? value, String path) {
  if (value is! List<Object?>) {
    throw FormatException('$path must be an array');
  }
  return value;
}

String _asString(Object? value, String path) {
  if (value is! String) throw FormatException('$path must be a string');
  return value;
}

int _asInt(Object? value, String path) {
  if (value is! int) throw FormatException('$path must be an integer');
  return value;
}

// ignore: unused_element
double _asDouble(Object? value, String path) {
  if (value is! num) throw FormatException('$path must be a number');
  return value.toDouble();
}

bool _asBool(Object? value, String path) {
  if (value is! bool) throw FormatException('$path must be a boolean');
  return value;
}

DateTime _asDateTime(Object? value, String path) {
  final raw = _asString(value, path);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || !raw.contains(RegExp(r'(Z|[+-]\d\d:\d\d)$'))) {
    throw FormatException('$path must be an RFC 3339 date-time with timezone');
  }
  return parsed;
}"""


def _lower_camel(value: str) -> str:
    words = [word for word in re.split(r"[^A-Za-z0-9]+", value) if word]
    if not words:
        raise ValueError(f"cannot turn {value!r} into a Dart identifier")
    return words[0].lower() + "".join(word.capitalize() for word in words[1:])


def _dart_enum_case(value: str) -> str:
    result = _lower_camel(value)
    return f"value{result}" if result[0].isdigit() else result


def _dart_literal(value: object) -> str:
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if value is True:
        return "true"
    if value is False:
        return "false"
    if value is None:
        return "null"
    return str(value)


def _dart_raw_literal(value: str) -> str:
    if "'" in value:
        raise ValueError("Dart raw single-quoted literal cannot contain an apostrophe")
    return f"r'{value}'"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("openapi", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args(argv)
    generate_dart_models(args.openapi, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
