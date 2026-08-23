#!/usr/bin/env python3
"""Validate the shipped JSON fixtures against the published JSON Schemas.

Vee publishes a schema for each structured payload a plugin can print — the
widget card and the JSON menu output. Those schemas are documentation, and they
are what a plugin author's editor validates against, so they have to stay true
to what the Swift parsers actually accept.

The SDKs already commit golden fixtures that all three SDKs produce
byte-identically and that the Swift parsers round-trip. Validating the schemas
against those fixtures means the schema is checked against payloads three
implementations already agree on, rather than against hand-written samples.

    python3 docs/scripts/check_schemas.py

Fixtures are discovered by glob: drop a new JSON fixture in and it is checked,
with no list to update here.

Implements only the JSON Schema subset these schemas use (type, const, enum,
required, properties, items, minimum, maximum, oneOf, $ref/$defs) — the same
"support what we actually use" rule as the other guard scripts, rather than
taking on a third-party dependency for a validator.
"""
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SCHEMAS = os.path.join(ROOT, "docs/schemas")
FIXTURES = os.path.join(ROOT, "plugins/fixtures")

# Which schema a fixture is checked against, chosen by a marker key in the
# payload itself rather than by filename — a fixture declares what it is.
MARKERS = [("vee_widget", "widget-card.schema.json"), ("vee", "json-output.schema.json")]

TYPES = {
    "object": dict, "array": list, "string": str, "boolean": bool,
    "number": (int, float), "integer": int, "null": type(None),
}


def resolve(schema, root):
    while "$ref" in schema:
        ref = schema["$ref"]
        if not ref.startswith("#/"):
            raise ValueError("only local $ref is supported: %s" % ref)
        node = root
        for part in ref[2:].split("/"):
            node = node[part]
        schema = node
    return schema


def check(value, schema, root, path, errors):
    schema = resolve(schema, root)

    if "const" in schema and value != schema["const"]:
        errors.append("%s: expected %r, got %r" % (path, schema["const"], value))
        return

    if "enum" in schema and value not in schema["enum"]:
        errors.append("%s: %r is not one of %s" % (path, value, schema["enum"]))
        return

    if "oneOf" in schema:
        for sub in schema["oneOf"]:
            trial = []
            check(value, sub, root, path, trial)
            if not trial:
                break
        else:
            errors.append("%s: %r matches none of the allowed forms" % (path, value))
        return

    declared = schema.get("type")
    if declared is not None:
        allowed = declared if isinstance(declared, list) else [declared]
        # bool is a subclass of int in Python; JSON treats them as distinct
        ok = any(
            isinstance(value, TYPES[t]) and not (t in ("number", "integer") and isinstance(value, bool))
            for t in allowed
        )
        if not ok:
            errors.append("%s: expected type %s, got %s" % (path, declared, type(value).__name__))
            return

    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append("%s: %r is below minimum %r" % (path, value, schema["minimum"]))
        if "maximum" in schema and value > schema["maximum"]:
            errors.append("%s: %r is above maximum %r" % (path, value, schema["maximum"]))

    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append("%s: missing required key %r" % (path, key))
        props = schema.get("properties", {})
        for key, sub in value.items():
            if key in props:
                check(sub, props[key], root, "%s.%s" % (path, key), errors)
            elif schema.get("additionalProperties") is False:
                errors.append("%s: unexpected key %r" % (path, key))

    if isinstance(value, list) and "items" in schema:
        for i, entry in enumerate(value):
            check(entry, schema["items"], root, "%s[%d]" % (path, i), errors)


def main():
    schemas = {}
    for name in os.listdir(SCHEMAS):
        if name.endswith(".schema.json"):
            schemas[name] = json.load(open(os.path.join(SCHEMAS, name)))
    if not schemas:
        print("no schemas found in docs/schemas")
        return 1

    checked, failures = 0, 0
    for path in sorted(glob.glob(os.path.join(FIXTURES, "*.txt"))):
        raw = open(path).read().strip()
        if not raw.startswith("{"):
            continue  # a text-protocol fixture, not a structured payload
        name = os.path.basename(path)
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError as e:
            print("FAIL %s: not valid JSON (%s)" % (name, e))
            failures += 1
            continue

        schema_name = next((s for marker, s in MARKERS if marker in payload), None)
        if schema_name is None:
            print("FAIL %s: no version marker (%s) — cannot tell which schema applies"
                  % (name, " / ".join(m for m, _ in MARKERS)))
            failures += 1
            continue

        schema = schemas[schema_name]
        errors = []
        check(payload, schema, schema, name, errors)
        checked += 1
        if errors:
            failures += 1
            print("FAIL %s against %s:" % (name, schema_name))
            for e in errors:
                print("    " + e)
        else:
            print("ok   %s against %s" % (name, schema_name))

    if failures:
        print("\n%d fixture(s) do not match their schema. Either the payload is wrong,"
              "\nor docs/schemas is out of date with what the parser accepts." % failures)
        return 1
    print("\nok: %d structured fixtures validate against their published schemas" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
