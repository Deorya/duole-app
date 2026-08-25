# DUOLE App contract consumer

`lib/app_contract.dart` is generated from the OpenAPI document released by the
DUOLE API provider. Do not edit it by hand.

Regenerate it from the repository root:

```bash
python3 tools/dart_generator.py \
  /path/to/duole-app-v1-openapi.json \
  dart/duole_app_contract/lib/app_contract.dart
```

The fixture entrypoints under `test/` accept provider-released JSON fixture
paths. Provider contract validation remains the API provider's responsibility;
this repository owns consumer decoding, Dart/Flutter analysis, and App tests.

Unknown wire enum values are deliberately decoded to a fail-closed consumer
fallback; unknown capability keys never alias a known capability. Provider
payloads containing those unknown wire values remain invalid against the frozen
v1 schema.
