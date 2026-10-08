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
NEXT_STAGE_SIGNATURE=evidence-s03.zip.sig
NEXT_STAGE_PUBLIC_KEY=s03-signing-public.pem
EOF

        # ------------------------------------------------------
        # Phase 8 — Final S03 forensic evidence
        #
        # These files are generated outside Jenkins by:
        #
        #   ./scripts/generate-s03-evidence.sh
        #
        # and mounted read-only into the Jenkins container.
        # ------------------------------------------------------

        S03_DIST="/opt/poisoned-pipeline/s03/dist"
        S03_KEYS="/opt/poisoned-pipeline/s03/keys"

        # ------------------------------------------------------
        # Validate Phase 8 evidence inputs
        # ------------------------------------------------------

        for FILE in \
            "$S03_DIST/evidence-s03.zip" \
            "$S03_DIST/evidence-s03.zip.sig" \
            "$S03_KEYS/s03-signing-public.pem"
        do
            if [[ ! -r "$FILE" ]]; then
                echo "[ERROR] Missing Phase 8 evidence input."
                echo "[ERROR] Required file is not readable:"
                echo "        $FILE"
                exit 1
            fi
        done

        # ------------------------------------------------------
        # Archive final S03 evidence
        # ------------------------------------------------------

        cp \
            "$S03_DIST/evidence-s03.zip" \
            "$OUT/evidence-s03.zip"

        cp \
            "$S03_DIST/evidence-s03.zip.sig" \
            "$OUT/evidence-s03.zip.sig"

        cp \
            "$S03_KEYS/s03-signing-public.pem" \
            "$OUT/s03-signing-public.pem"

        echo "[+] Final S03 forensic evidence archived."
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