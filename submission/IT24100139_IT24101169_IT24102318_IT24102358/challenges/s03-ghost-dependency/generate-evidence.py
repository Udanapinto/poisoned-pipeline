#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
import shutil
import shlex
import zipfile
from pathlib import Path


CHALLENGE_DIR = Path(__file__).resolve().parent
ROOT_DIR = CHALLENGE_DIR.parents[1]

DIST_DIR = CHALLENGE_DIR / "dist"
WORK_DIR = CHALLENGE_DIR / "work"
PRIVATE_DIR = ROOT_DIR / "private" / "s03"

ZIP_PATH = DIST_DIR / "evidence-s03.zip"
ANSWER_FILE = PRIVATE_DIR / "answer-manifest.env"

APP_VERSION = "nexora-platform-2026.09.03"

TARGET_HOST = "nexora-app"
DIAGNOSTICS_CLUE = "/api/diagnostics/run"


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def package_purl(name: str, version: str) -> str:
    return f"pkg:pypi/{name}@{version}"


def approved_digest(slot: str, name: str, version: str) -> str:
    synthetic_payload = (
        f"NEXORA-APPROVED|{slot}|{name}|{version}|release"
    )
    return sha256_text(synthetic_payload)


def observed_digest(
    slot: str,
    name: str,
    version: str,
    variant: str = "release",
) -> str:
    payload = (
        f"NEXORA-OBSERVED|{slot}|{name}|{version}|{variant}"
    )
    return sha256_text(payload)


# ---------------------------------------------------------
# Approved component baseline
# ---------------------------------------------------------

approved = [
    {
        "slot": "auth-core",
        "name": "nexora-auth",
        "version": "3.1.4",
        "source": "internal-approved-index",
    },
    {
        "slot": "telemetry-core",
        "name": "nexora-telemetry",
        "version": "1.8.0",
        "source": "internal-approved-index",
    },
    {
        "slot": "render-core",
        "name": "nexora-render",
        "version": "4.0.2",
        "source": "internal-approved-index",
    },
    {
        "slot": "parser-core",
        "name": "nexora-parser",
        "version": "5.2.0",
        "source": "internal-approved-index",
    },
    {
        "slot": "utility-core",
        "name": "nexora-utils",
        "version": "2.4.1",
        "source": "internal-approved-index",
    },
]

for component in approved:
    component["purl"] = package_purl(
        component["name"],
        component["version"],
    )

    component["expected_sha256"] = approved_digest(
        component["slot"],
        component["name"],
        component["version"],
    )


approved_by_slot = {
    component["slot"]: component
    for component in approved
}


# ---------------------------------------------------------
# Observed compromised release
#
# The records deliberately contain multiple decoys:
#
# telemetry-core -> source anomaly only
# render-core    -> version/checksum anomaly
# parser-core    -> checksum anomaly
# utility-core   -> all four required indicators
#
# The script never labels the answer in player evidence.
# ---------------------------------------------------------

observed = []

# Completely normal component
a = approved_by_slot["auth-core"]
observed.append(
    {
        "slot": a["slot"],
        "name": a["name"],
        "version": a["version"],
        "source": a["source"],
        "purl": a["purl"],
        "sha256": a["expected_sha256"],
    }
)

# Source anomaly only
a = approved_by_slot["telemetry-core"]
observed.append(
    {
        "slot": a["slot"],
        "name": a["name"],
        "version": a["version"],
        "source": "staging-proxy",
        "purl": a["purl"],
        "sha256": a["expected_sha256"],
    }
)

# Version drift + checksum difference
a = approved_by_slot["render-core"]
render_version = "4.0.3"
observed.append(
    {
        "slot": a["slot"],
        "name": a["name"],
        "version": render_version,
        "source": a["source"],
        "purl": package_purl(
            a["name"],
            render_version,
        ),
        "sha256": observed_digest(
            a["slot"],
            a["name"],
            render_version,
        ),
    }
)

# Checksum anomaly only
a = approved_by_slot["parser-core"]
observed.append(
    {
        "slot": a["slot"],
        "name": a["name"],
        "version": a["version"],
        "source": a["source"],
        "purl": a["purl"],
        "sha256": observed_digest(
            a["slot"],
            a["name"],
            a["version"],
            "repacked",
        ),
    }
)

# Substituted dependency
#
# Do not describe this as "malicious" in the generated evidence.
a = approved_by_slot["utility-core"]

sub_name = "nexorra-utils"
sub_version = "2.4.9"

observed.append(
    {
        "slot": a["slot"],
        "name": sub_name,
        "version": sub_version,
        "source": "community-mirror",
        "purl": package_purl(
            sub_name,
            sub_version,
        ),
        "sha256": observed_digest(
            a["slot"],
            sub_name,
            sub_version,
            "diagnostics-enabled",
        ),
    }
)


# ---------------------------------------------------------
# Identify expected answer privately
# ---------------------------------------------------------

matches = []

for component in observed:
    baseline = approved_by_slot[component["slot"]]

    indicators = {
        "name": component["name"] != baseline["name"],
        "version": component["version"] != baseline["version"],
        "source": component["source"] != baseline["source"],
        "checksum": (
            component["sha256"]
            != baseline["expected_sha256"]
        ),
    }

    if all(indicators.values()):
        matches.append(component)


if len(matches) != 1:
    raise SystemExit(
        f"Expected exactly one four-indicator component; "
        f"found {len(matches)}"
    )


answer = matches[0]

canonical_purl = answer["purl"]

token = hashlib.sha256(
    canonical_purl.encode("utf-8")
).hexdigest()[:32]

flag = f"IE3132{{PP_S03_{token}}}"


# ---------------------------------------------------------
# Prepare deterministic work area
# ---------------------------------------------------------

if WORK_DIR.exists():
    shutil.rmtree(WORK_DIR)

WORK_DIR.mkdir(parents=True)
DIST_DIR.mkdir(parents=True, exist_ok=True)
PRIVATE_DIR.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------
# CycloneDX 1.7 SBOM
# ---------------------------------------------------------

sbom_components = []

for component in observed:
    sbom_components.append(
        {
            "type": "library",
            "name": component["name"],
            "version": component["version"],
            "purl": component["purl"],
            "hashes": [
                {
                    "alg": "SHA-256",
                    "content": component["sha256"],
                }
            ],
            "properties": [
                {
                    "name": "nexora:slot",
                    "value": component["slot"],
                },
                {
                    "name": "nexora:source",
                    "value": component["source"],
                },
            ],
        }
    )


sbom = {
    "bomFormat": "CycloneDX",
    "specVersion": "1.7",
    "serialNumber": (
        "urn:uuid:"
        "1d363087-736d-43d9-9a91-0a963ac10303"
    ),
    "version": 1,
    "metadata": {
        "component": {
            "type": "application",
            "name": "nexora-platform",
            "version": APP_VERSION,
        }
    },
    "components": sbom_components,
}


(WORK_DIR / "sbom.json").write_text(
    json.dumps(
        sbom,
        indent=2,
        sort_keys=True,
    )
    + "\n",
    encoding="utf-8",
)


# ---------------------------------------------------------
# Approved component baseline
# ---------------------------------------------------------

approved_document = {
    "application": APP_VERSION,
    "policy": "Nexora Approved Component Baseline",
    "approved": approved,
}

(WORK_DIR / "approved-components.json").write_text(
    json.dumps(
        approved_document,
        indent=2,
        sort_keys=True,
    )
    + "\n",
    encoding="utf-8",
)


# ---------------------------------------------------------
# Package source / Package URL evidence
# ---------------------------------------------------------

source_lines = [
    "# slot|name|version|source|purl"
]

for component in observed:
    source_lines.append(
        "|".join(
            [
                component["slot"],
                component["name"],
                component["version"],
                component["source"],
                component["purl"],
            ]
        )
    )

(WORK_DIR / "package-sources.txt").write_text(
    "\n".join(source_lines) + "\n",
    encoding="utf-8",
)


# ---------------------------------------------------------
# Build log
# ---------------------------------------------------------

log_lines = [
    "Nexora Technologies Release Builder",
    f"release={APP_VERSION}",
    "build=103",
    "resolver_mode=locked-with-fallback",
    "",
]

for component in observed:
    log_lines.append(
        " ".join(
            [
                "RESOLVED",
                f"slot={component['slot']}",
                f"name={component['name']}",
                f"version={component['version']}",
                f"source={component['source']}",
            ]
        )
    )

log_lines += [
    "",
    "INFO dependency inventory exported to CycloneDX",
    "INFO package-origin records preserved",
    "INFO component digests recorded",
    "WARN release requires forensic review",
]

(WORK_DIR / "build.log").write_text(
    "\n".join(log_lines) + "\n",
    encoding="utf-8",
)


# ---------------------------------------------------------
# Evidence file integrity manifest
# ---------------------------------------------------------

evidence_files = [
    "approved-components.json",
    "build.log",
    "package-sources.txt",
    "sbom.json",
]

manifest_lines = []

for filename in evidence_files:
    path = WORK_DIR / filename

    digest = hashlib.sha256(
        path.read_bytes()
    ).hexdigest()

    manifest_lines.append(
        f"{digest}  {filename}"
    )


(WORK_DIR / "SHA256SUMS").write_text(
    "\n".join(manifest_lines) + "\n",
    encoding="utf-8",
)


# ---------------------------------------------------------
# Deterministic ZIP
# ---------------------------------------------------------

if ZIP_PATH.exists():
    ZIP_PATH.unlink()


archive_files = evidence_files + ["SHA256SUMS"]

with zipfile.ZipFile(
    ZIP_PATH,
    mode="w",
    compression=zipfile.ZIP_DEFLATED,
    compresslevel=9,
) as archive:

    for filename in sorted(archive_files):

        data = (WORK_DIR / filename).read_bytes()

        info = zipfile.ZipInfo(
            filename=filename,
            date_time=(2026, 1, 1, 0, 0, 0),
        )

        info.compress_type = zipfile.ZIP_DEFLATED
        info.create_system = 3
        info.external_attr = 0o100644 << 16

        archive.writestr(info, data)


# ---------------------------------------------------------
# Private answer manifest
# ---------------------------------------------------------

values = {
    "S03_COMPONENT_SLOT": answer["slot"],
    "S03_COMPONENT_NAME": answer["name"],
    "S03_COMPONENT_VERSION": answer["version"],
    "S03_COMPONENT_SOURCE": answer["source"],
    "S03_CANONICAL_PURL": canonical_purl,
    "S03_TOKEN": token,
    "S03_FLAG": flag,
    "S03_AFFECTED_APP_VERSION": APP_VERSION,
    "S03_TARGET_HOST": TARGET_HOST,
    "S03_DIAGNOSTICS_CLUE": DIAGNOSTICS_CLUE,
}

answer_lines = [
    "# S03 private instructor answer manifest",
    "# DO NOT COMMIT",
]

for key, value in values.items():
    answer_lines.append(
        f"{key}={shlex.quote(str(value))}"
    )


ANSWER_FILE.write_text(
    "\n".join(answer_lines) + "\n",
    encoding="utf-8",
)

os.chmod(ANSWER_FILE, 0o600)


print("[+] S03 evidence generated.")
print("[+] Exactly one four-indicator chain verified.")
print("[+] Player evidence contains no S03 flag.")
print("[+] Private answer manifest updated.")