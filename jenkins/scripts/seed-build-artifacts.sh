#!/usr/bin/env bash
set -euo pipefail

# Never xtrace this script because build 103 uses S02_FLAG.
set +x

: "${WORKSPACE:?WORKSPACE is required}"
: "${BUILD_NUMBER:?BUILD_NUMBER is required}"
: "${S02_FLAG:?S02_FLAG is required}"

OUT="$WORKSPACE/artifact-output"

rm -rf "$OUT"
mkdir -p "$OUT"

echo "=================================================="
echo " Nexora Release Verification"
echo " Build: $BUILD_NUMBER"
echo "=================================================="

case "$BUILD_NUMBER" in

    101)
        cat > "$OUT/release-summary.txt" <<EOF
release=nexora-platform-2026.09.01
build=101
status=approved
security_review=passed
EOF

        echo "[+] Release verification passed."
        ;;

    102)
        cat > "$OUT/release-summary.txt" <<EOF
release=nexora-platform-2026.09.02
build=102
status=approved
security_review=passed
EOF

        echo "[+] Release verification passed."
        ;;

    103)
        echo "[!] Release integrity anomaly detected."
        echo "[!] Preserving forensic evidence for investigation."

        cat > "$OUT/release-manifest.txt" <<EOF
NEXORA RELEASE MANIFEST
=======================

release=nexora-platform-2026.09.03
build=103
status=QUARANTINED
security_review=INVESTIGATION_REQUIRED

S02_TOKEN=${S02_FLAG}

NEXT_STAGE_EVIDENCE=evidence-s03.zip
EOF

        TMP="$(mktemp -d)"
        trap 'rm -rf "$TMP"' EXIT

        # ------------------------------------------------------
        # Temporary Phase 7 handoff structure.
        #
        # Phase 8 will replace the CONTENTS with the final
        # Ghost Dependency evidence while keeping the same
        # evidence-s03.zip handoff.
        # ------------------------------------------------------

        cat > "$TMP/sbom.json" <<'EOF'
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.7",
  "serialNumber": "urn:uuid:11111111-2222-3333-4444-555555555555",
  "version": 1,
  "metadata": {
    "component": {
      "type": "application",
      "name": "nexora-platform",
      "version": "2026.09.03"
    }
  },
  "components": [
    {
      "type": "library",
      "name": "nexora-utils",
      "version": "2.4.1",
      "purl": "pkg:pypi/nexora-utils@2.4.1"
    }
  ]
}
EOF

        cat > "$TMP/build.log" <<'EOF'
Nexora release build 103
Supply-chain evidence captured.
Full S03 evidence will be finalized during Phase 8.
EOF

        cat > "$TMP/approved-components.json" <<'EOF'
{
  "approved": [
    {
      "name": "nexora-utils",
      "version": "2.4.1"
    }
  ]
}
EOF

        cat > "$TMP/package-sources.txt" <<'EOF'
nexora-utils|2.4.1|internal-approved-index
EOF

        (
            cd "$TMP"

            sha256sum \
                sbom.json \
                build.log \
                approved-components.json \
                package-sources.txt \
                > SHA256SUMS

            # Fixed timestamps improve reproducibility.
            touch -t 202601010000 \
                sbom.json \
                build.log \
                approved-components.json \
                package-sources.txt \
                SHA256SUMS

            zip -X -q \
                "$OUT/evidence-s03.zip" \
                sbom.json \
                build.log \
                approved-components.json \
                package-sources.txt \
                SHA256SUMS
        )

        echo "[+] Investigation artifacts archived."
        ;;

    104)
        cat > "$OUT/release-summary.txt" <<EOF
release=nexora-platform-2026.09.04
build=104
status=approved
security_review=passed
EOF

        echo "[+] Release verification passed."
        ;;

    *)
        echo "[ERROR] Unexpected build number."
        exit 1
        ;;
esac

echo "[+] Build artifact generation complete."