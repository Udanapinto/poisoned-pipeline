#!/usr/bin/env bash
# S03 - The Ghost Dependency
# Reference solver for the intended solution path.
# Authorized use only inside the isolated Operation Poisoned Pipeline lab.

set -euo pipefail

EVIDENCE_ZIP="${1:-/tmp/s02-solve/evidence-s03.zip}"
WORK_DIR="${2:-/tmp/s03-solve}"

if [[ ! -f "${EVIDENCE_ZIP}" ]]; then
    echo "[ERROR] Evidence ZIP not found: ${EVIDENCE_ZIP}"
    exit 1
fi

echo "======================================================"
echo " S03 - The Ghost Dependency Solver"
echo "======================================================"
echo

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

echo "[1] Extracting evidence bundle..."
unzip -q "${EVIDENCE_ZIP}" -d "${WORK_DIR}/evidence"
cd "${WORK_DIR}/evidence"

echo "[2] Validating evidence integrity..."
sha256sum -c SHA256SUMS

echo
echo "[3] CycloneDX specification version:"
jq -r '.specVersion' sbom.json

echo
echo "[4] Correlating SBOM, approved baseline, package sources, and checksums..."

python3 - <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(".")

approved_doc = json.loads((root / "approved-components.json").read_text())
sbom = json.loads((root / "sbom.json").read_text())
build_log = (root / "build.log").read_text()

sources = {}
for line in (root / "package-sources.txt").read_text().splitlines():
    if not line or line.startswith("#"):
        continue
    slot, name, version, source, purl = line.split("|")
    sources[slot] = {
        "name": name,
        "version": version,
        "source": source,
        "purl": purl,
    }

approved = {item["slot"]: item for item in approved_doc["approved"]}

candidates = []
for component in sbom["components"]:
    props = {item["name"]: item["value"] for item in component.get("properties", [])}
    slot = props["nexora:slot"]
    baseline = approved[slot]
    source_record = sources[slot]
    observed_hash = next(
        item["content"]
        for item in component["hashes"]
        if item["alg"] == "SHA-256"
    )

    mismatches = [
        component["name"] != baseline["name"],
        component["version"] != baseline["version"],
        source_record["source"] != baseline["source"],
        observed_hash != baseline["expected_sha256"],
    ]

    if slot not in build_log:
        raise SystemExit(f"build.log missing slot {slot}")

    if all(mismatches):
        candidates.append(component)

if len(candidates) != 1:
    print(f"ERROR: expected exactly 1 candidate, found {len(candidates)}")
    sys.exit(1)

candidate = candidates[0]
purl = candidate["purl"]
token = hashlib.sha256(purl.encode("utf-8")).hexdigest()[:32]

print()
print("=" * 60)
print(" SUBSTITUTED COMPONENT IDENTIFIED")
print("=" * 60)
print(f"  Name:     {candidate['name']}")
print(f"  Version:  {candidate['version']}")
print(f"  PURL:     {purl}")
print()
print(f"  S03 token: {token}")
print(f"  S03 flag:  IE3132{{PP_S03_{token}}}")
print("=" * 60)
PY

echo
echo "======================================================"
echo " S03 solve complete."
echo " Submit the S03 token to CTFd."
echo " The affected application version and target host feed into S04."
echo "======================================================"
