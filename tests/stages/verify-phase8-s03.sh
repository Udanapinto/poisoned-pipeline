#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ZIP="$ROOT_DIR/challenges/s03-ghost-dependency/dist/evidence-s03.zip"
SIG="$ROOT_DIR/challenges/s03-ghost-dependency/dist/evidence-s03.zip.sig"
PUB="$ROOT_DIR/challenges/s03-ghost-dependency/keys/s03-signing-public.pem"

BASELINE="$ROOT_DIR/private/s03/baseline.env"
ANSWER="$ROOT_DIR/private/s03/answer-manifest.env"

source "$ROOT_DIR/private/s01/s01.env"
source "$ROOT_DIR/private/s02/s02.env"
source "$BASELINE"
source "$ANSWER"

BASE_URL="https://10.13.10.20/jenkins"
AUTH="$S01_JENKINS_USER:$S01_JENKINS_PASSWORD"

PASS=0
FAIL=0

pass() {
    echo "[PASS] $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "[FAIL] $1"
    FAIL=$((FAIL + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "======================================================"
echo " Phase 8 — S03 Ghost Dependency Verification"
echo "======================================================"
echo

# --------------------------------------------------
# Required files
# --------------------------------------------------

for FILE in "$ZIP" "$SIG" "$PUB"
do
    if [[ -f "$FILE" ]]; then
        pass "Required S03 file exists"
    else
        fail "Required S03 file exists"
    fi
done

# --------------------------------------------------
# Bundle baseline
# --------------------------------------------------

ACTUAL_ZIP_SHA="$(sha256sum "$ZIP" | awk '{print $1}')"

if [[ "$ACTUAL_ZIP_SHA" == "$S03_EVIDENCE_SHA256" ]]; then
    pass "Evidence bundle matches private baseline"
else
    fail "Evidence bundle matches private baseline"
fi

# --------------------------------------------------
# Signature
# --------------------------------------------------

if openssl dgst \
    -sha256 \
    -verify "$PUB" \
    -signature "$SIG" \
    "$ZIP" \
    >/dev/null 2>&1
then
    pass "Detached signature verifies"
else
    fail "Detached signature verifies"
fi

# --------------------------------------------------
# No literal flag
# --------------------------------------------------

if zipgrep -q 'IE3132{' "$ZIP"
then
    fail "Player evidence contains no literal flag"
else
    pass "Player evidence contains no literal flag"
fi

# --------------------------------------------------
# Extract and verify inner manifest
# --------------------------------------------------

mkdir -p "$TMP/evidence"

unzip -q \
    "$ZIP" \
    -d "$TMP/evidence"

if (
    cd "$TMP/evidence"
    sha256sum -c SHA256SUMS >/dev/null
)
then
    pass "Evidence SHA256SUMS validates"
else
    fail "Evidence SHA256SUMS validates"
fi

# --------------------------------------------------
# CycloneDX version
# --------------------------------------------------

SPEC="$(
    jq -r '.specVersion' \
    "$TMP/evidence/sbom.json"
)"

if [[ "$SPEC" == "1.7" ]]; then
    pass "CycloneDX specification is 1.7"
else
    fail "CycloneDX specification is 1.7"
fi

# --------------------------------------------------
# Independent evidence correlation
# --------------------------------------------------

RESULT="$(
python3 - "$TMP/evidence" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])

approved_doc = json.loads(
    (root / "approved-components.json").read_text()
)

sbom = json.loads(
    (root / "sbom.json").read_text()
)

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

approved = {
    item["slot"]: item
    for item in approved_doc["approved"]
}

candidates = []

for component in sbom["components"]:

    props = {
        item["name"]: item["value"]
        for item in component.get("properties", [])
    }

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

    # Ensure build.log also contains the component.
    if slot not in build_log:
        raise SystemExit(
            f"build.log missing slot {slot}"
        )

    if all(mismatches):
        candidates.append(component)

if len(candidates) != 1:
    print(f"ERROR|{len(candidates)}")
    raise SystemExit(0)

candidate = candidates[0]

token = hashlib.sha256(
    candidate["purl"].encode()
).hexdigest()[:32]

print(
    "OK"
    + "|"
    + candidate["purl"]
    + "|"
    + token
)
PY
)"

STATUS="$(cut -d'|' -f1 <<< "$RESULT")"

if [[ "$STATUS" == "OK" ]]; then
    pass "Exactly one component satisfies all four indicators"
else
    fail "Exactly one component satisfies all four indicators"
fi

FOUND_PURL="$(cut -d'|' -f2 <<< "$RESULT")"
FOUND_TOKEN="$(cut -d'|' -f3 <<< "$RESULT")"

if [[ "$FOUND_PURL" == "$S03_CANONICAL_PURL" ]]; then
    pass "Independent analysis finds expected canonical PURL"
else
    fail "Independent analysis finds expected canonical PURL"
fi

if [[ "$FOUND_TOKEN" == "$S03_TOKEN" ]]; then
    pass "Independent token derivation matches answer manifest"
else
    fail "Independent token derivation matches answer manifest"
fi

if [[ "$S03_TOKEN" =~ ^[0-9a-f]{32}$ ]]; then
    pass "S03 token is 32 lowercase hex characters"
else
    fail "S03 token is 32 lowercase hex characters"
fi

# --------------------------------------------------
# Jenkins player handoff
# --------------------------------------------------

curl -ksS \
    -u "$AUTH" \
    "$BASE_URL/job/$S01_JOB_NAME/103/artifact/artifact-output/evidence-s03.zip" \
    -o "$TMP/jenkins-evidence.zip"

if cmp -s \
    "$ZIP" \
    "$TMP/jenkins-evidence.zip"
then
    pass "Jenkins #103 exposes exact canonical S03 bundle"
else
    fail "Jenkins #103 exposes exact canonical S03 bundle"
fi

# --------------------------------------------------
# Other builds must not contain S03 bundle
# --------------------------------------------------

for BUILD in 101 102 104
do
    CODE="$(
        curl -k -s \
          -u "$AUTH" \
          -o /dev/null \
          -w '%{http_code}' \
          "$BASE_URL/job/$S01_JOB_NAME/$BUILD/artifact/artifact-output/evidence-s03.zip"
    )"

    if [[ "$CODE" != "200" ]]; then
        pass "Build $BUILD does not expose S03 bundle"
    else
        fail "Build $BUILD does not expose S03 bundle"
    fi
done

# --------------------------------------------------
# Next-stage handoff exists privately
# --------------------------------------------------

if [[ -n "$S03_AFFECTED_APP_VERSION" \
   && -n "$S03_TARGET_HOST" \
   && -n "$S03_DIAGNOSTICS_CLUE" ]]
then
    pass "S03 -> S04 handoff values exist"
else
    fail "S03 -> S04 handoff values exist"
fi

echo
echo "======================================================"
echo " RESULTS"
echo "======================================================"
echo
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo

if [[ "$FAIL" -eq 0 ]]; then
    echo "PHASE 8 S03: PASSED"
    exit 0
else
    echo "PHASE 8 S03: FAILED"
    exit 1
fi