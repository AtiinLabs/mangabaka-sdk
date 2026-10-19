#!/usr/bin/env python3
"""Download MangaBaka's OpenAPI document, apply the compatibility patches the
Swift OpenAPI Generator needs, and regenerate the client. Review the diff of
OpenAPI/openapi.json on its own before touching hand-written code.

Source: https://mangabaka.org/api.json (the document the API Explorer at
https://mangabaka.org/data/api/explorer loads).
"""
import hashlib
import json
import os
import subprocess
import urllib.request

SOURCE = "https://mangabaka.org/api.json"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "OpenAPI", "openapi.json")


def loosen(node):
    """Removes the `enum` keyword and `additionalProperties: false` in place, keeping each
    schema's type. Properties named `enum` are kept: only list values are enum keywords."""
    if isinstance(node, dict):
        if isinstance(node.get("enum"), list):
            del node["enum"]
        if node.get("additionalProperties") is False:
            del node["additionalProperties"]
        for value in node.values():
            loosen(value)
    elif isinstance(node, list):
        for value in node:
            loosen(value)


def operations(spec):
    for path_item in spec["paths"].values():
        for operation in path_item.values():
            if isinstance(operation, dict):
                yield operation


def patch(spec):
    """Each patch fixes a construct the generator rejects or decodes too strictly."""
    schemas = spec["components"]["schemas"]

    # 1. `type: "integer[]"` is not a JSON Schema type. Express it as an array of integers.
    param = spec["paths"]["/v1/my/library/batch"]["get"]["parameters"][0]
    if param["schema"].get("type") == "integer[]":
        param["schema"] = {"type": "array", "items": {"type": "integer"}}

    # 2. Responses must keep decoding when MangaBaka adds an enum value or a field. Generated
    #    enums reject unlisted values and `additionalProperties: false` rejects unlisted keys, so
    #    both are removed. The SDK exposes enumerations as open string-backed types and passes
    #    them through unchanged in requests, so request enums are removed too; the server
    #    still validates every request.
    loosen(spec["paths"])
    loosen(schemas)

    # 3. Source lookups (`/v1/source/{source}/{id}`) embed the deprecated v1 series schema. The
    #    SDK only reads each matched series' id and state, so only those fields are declared;
    #    other fields are ignored when decoding.
    for path in ("/v1/source/anilist/{id}", "/v1/source/my-anime-list/{id}"):
        data = spec["paths"][path]["get"]["responses"]["200"]["content"]["application/json"]
        data = data["schema"]["properties"]["data"]
        data["properties"]["series"]["items"] = {
            "type": "object",
            "properties": {"id": {"type": "number"}, "state": {"type": "string"}},
            "required": ["id", "state"],
        }

    # 4. `SeriesV2Any` is `anyOf: [SeriesV2Full, SeriesV2]`. SeriesV2Full has the same required
    #    fields as SeriesV2 and only adds optional ones, so it describes both payloads; use it
    #    directly instead of generating two parallel series types.
    schemas["SeriesV2Any"] = {"$ref": "#/components/schemas/SeriesV2Full"}

    # 5. Repeatable query filters (`type`, `status`, `tag`, …) are declared as untyped
    #    "one value or an array" unions, which the generator skips. Declare them as arrays of
    #    strings; they are sent as repeated parameters (`type=manga&type=manhwa`), which the
    #    API accepts.
    for operation in operations(spec):
        for parameter in operation.get("parameters", []):
            variants = parameter.get("schema", {}).get("anyOf", [])
            if parameter.get("in") == "query" and any(v.get("type") == "array" for v in variants):
                parameter["schema"] = {"type": "array", "items": {"type": "string"}}

    # 6. IDs, pages and limits are declared as `number`, which is encoded with a decimal point
    #    (`/v2/series/1995.0`). Declare them as integers. (`random_seed` is a fraction in [0, 1).)
    integer_query_parameters = {"page", "limit"}
    for operation in operations(spec):
        for parameter in operation.get("parameters", []):
            schema = parameter.get("schema", {})
            is_integer = parameter.get("in") == "path" or parameter.get("name") in integer_query_parameters
            if not is_integer:
                continue
            if schema.get("type") == "number":
                schema["type"] = "integer"
            elif isinstance(schema.get("type"), list):
                schema["type"] = ["integer" if t == "number" else t for t in schema["type"]]

    # 7. Library entry writes report success through the status code; the body is
    #    `{status, data: boolean}` and carries nothing the SDK uses. Its schema is removed so a
    #    change to that body cannot turn a write that was applied into a decoding error.
    for method in ("post", "patch", "delete"):
        responses = spec["paths"]["/v1/my/library/{series_id}"][method]["responses"]
        for status, response in responses.items():
            if status.startswith("2"):
                response.pop("content", None)
    return spec


def main():
    request = urllib.request.Request(SOURCE, headers={"User-Agent": "mangabaka-sdk-update"})
    with urllib.request.urlopen(request, timeout=30) as response:
        raw = response.read()
    spec = json.loads(raw)
    with open(OUTPUT, "w", encoding="utf-8") as file:
        # The generator parses JSON with a YAML parser that rejects escaped surrogate pairs (emoji),
        # so non-ASCII text is written as UTF-8.
        json.dump(patch(spec), file, indent=1, sort_keys=True, ensure_ascii=False)
        file.write("\n")
    print(f"Wrote {OUTPUT} ({len(spec['paths'])} paths)")
    print(f"Upstream {spec['info']['title']} {spec['info']['version']}, SHA-256 {hashlib.sha256(raw).hexdigest()}")
    subprocess.run([os.path.join(ROOT, "Scripts", "generate.sh")], check=True)


if __name__ == "__main__":
    main()
