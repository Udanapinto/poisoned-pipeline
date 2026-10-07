#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# This script documents the intended CTFd challenge configuration.
# It does not automatically configure CTFd via API; use the CTFd admin UI
# or extend this script with API calls if you prefer automation.

echo "=========================================="
echo " Operation Poisoned Pipeline"
echo " CTFd Challenge Configuration Reference"
echo "=========================================="
echo
echo "The following six challenges must exist in CTFd:"
echo

cat <<'EOF'
--------------------------------------------------------------------
S01 - The Git Leak
  Category: OSINT / Reconnaissance
  Value: 100
  Flag format: IE3132{PP_S01_<32 hex>}
  Hints:
    H1 (5 pts):  The latest tree may not contain the full story.
    H2 (10 pts): Inspect earlier commits and file history.
    H3 (15 pts): Compare versions of the deployment configuration.
--------------------------------------------------------------------
S02 - Pipeline Breach
  Category: Web Technologies / Web Security
  Value: 100
  Flag format: IE3132{PP_S02_<32 hex>}
  Hints:
    H1 (5 pts):  Old integration accounts are often overlooked during migration.
    H2 (10 pts): Inspect historical builds and artefacts.
    H3 (15 pts): The compromised release manifest links the token and evidence bundle.
--------------------------------------------------------------------
S03 - The Ghost Dependency
  Category: Digital Forensics
  Value: 150
  Flag format: IE3132{PP_S03_<32 hex>}
  Hints:
    H1 (8 pts):  Package source is mismatching with approved packages.
    H2 (15 pts): Find two package names, versions and PURLs and compare character by character.
    H3 (23 pts): Use the checksum evidence to select from the near matches.
--------------------------------------------------------------------
S04 - Poisoned Runtime
  Category: Linux and System Security
  Value: 200
  Flag format: IE3132{PP_S04_<32 hex>}
  Hints:
    H1 (10 pts): The substituted component added an undocumented diagnostics capability.
    H2 (20 pts): Compare the endpoint input with the server-side action it triggers.
    H3 (30 pts): Automate one crafted request and verify the executing account.
--------------------------------------------------------------------
S05 - Broken Trust
  Category: Linux and System Security
  Value: 200
  Flag format: IE3132{PP_S05_<32 hex>}
  Hints:
    H1 (10 pts): The intended flaw is local configuration, not a public kernel CVE.
    H2 (20 pts): Compare what sudo -l permits with the files that utility trusts.
    H3 (30 pts): One trusted hook reference is writable by the service account group.
--------------------------------------------------------------------
S06 - Behind the Firewall
  Category: Networking
  Value: 250
  Flag format: IE3132{PP_S06_<32 hex>}
  Hints:
    H1 (13 pts): The attacked server has multiple network interfaces.
    H2 (25 pts): Use its SSH service as a controlled relay.
    H3 (38 pts): An application configuration that is only useful after tunnelling contains a database identity.
--------------------------------------------------------------------

Total: 1000 points
EOF

echo
echo "=========================================="
echo " To apply these challenges:"
echo " 1. Open https://10.13.10.20/ in a browser."
echo " 2. Log in as the CTFd administrator."
echo " 3. Create each challenge with the values above."
echo " 4. Add the real flag values from private/s0*/."
echo "=========================================="
