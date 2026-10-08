# Operation Poisoned Pipeline - Submission Package

This package contains the complete CTF Play Box implementation for the
IE3132 Penetration Testing module.

## Contents

- `compose.yml`: Docker Compose orchestration
- `application/`: Application Challenge container source
- `kali/`: Kali participant container source
- `challenges/`: Challenge source, solvers, and evidence
- `scripts/`: Build, seed, reset, and utility scripts
- `tests/`: Verification and testing scripts
- `nginx/`: Nginx reverse proxy configuration
- `jenkins/`: Jenkins Configuration as Code
- `postgres/`: PostgreSQL database initialization
- `evidence/`: Test results and verification outputs
- `docs/`: Design documents and phase implementation guides

## Setup

See the main `README.md` for full setup instructions.

## Important Notes

- The `private/` directory is not included in this package because it
  contains real flag values, passwords, and signing keys.
- To deploy, you must generate fresh secrets using the scripts in
  `scripts/generate-*-secrets.sh`.
- The CTFd challenge configuration is documented in
  `scripts/ctfd-export-challenges.sh`.

## Contact

- IT24100139 - Pinthu D.I.U.
- IT24101169 - Weligampitiya S.A.S.D.
- IT24102318 - Wickrama Edirisooriya A.A.G
- IT24102358 - Silva D.P.L.T.D.
