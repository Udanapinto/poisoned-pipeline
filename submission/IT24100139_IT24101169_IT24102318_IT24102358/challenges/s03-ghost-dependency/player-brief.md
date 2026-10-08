# S03 — The Ghost Dependency

A compromised Nexora release contains one dependency that does not
match the internally approved component inventory.

Use all available evidence:

- CycloneDX SBOM
- build log
- approved component baseline
- package source records
- checksum evidence

Exactly one component is inconsistent across all required indicators.

## Token calculation

After identifying the substituted component:

1. Take the exact Package URL (PURL) associated with the component.
2. Do not add spaces or a newline.
3. Calculate SHA-256 over that exact UTF-8 string.
4. Take the first 32 lowercase hexadecimal characters.
5. Submit:

IE3132{PP_S03_<32-hex-token>}

Example calculation structure:

    printf '%s' "$CANONICAL_PURL" | sha256sum

Do not hash the package name alone.
Do not hash the filename.
Do not include a newline.



