# S02 - Pipeline Breach Solver Checklist

## Starting Dependency

- Recover Jenkins username from S01
- Recover Jenkins password from S01
- Recover Jenkins job clue from S01
- Do not use administrator credentials

## Intended Path

- Access Jenkins through Nginx HTTPS
- Authenticate using recovered S01 account
- Enumerate permitted Jenkins jobs
- Locate nexora-release
- Inspect historical builds
- Identify compromised release
- Inspect archived artifacts
- Recover S02 token
- Download evidence-s03.zip
- Submit S02 token to CTFd
- Record compromised build number
- Record artifact filename

## Negative Tests

- Anonymous artifact access fails
- Incorrect credentials fail
- pipeline-reader cannot build
- pipeline-reader cannot configure jobs
- pipeline-reader cannot access Script Console
- pipeline-reader cannot access credentials
- Jenkins TCP 8080 is not published
- Jenkins belongs only to control_net
- Jenkins has no Docker socket
- Build console does not contain S02 flag
- S03 bundle exists only in intended build