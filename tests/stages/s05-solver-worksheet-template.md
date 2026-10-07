# S05 - Broken Trust Solver Worksheet

Complete this worksheet independently while solving S05.
Copy this file, fill it in, and keep the completed copy as evidence.

## 1. Prerequisites

- pipeline-app shell obtained from S04: YES / NO
- Local deployment clue recovered from S04: YES / NO

## 2. Privilege enumeration

- `id` output:
- `sudo -l` output:
- Privately installed privileged utilities discovered:
- Trusted configuration file discovered:
- Trusted hook path discovered:

## 3. Trust violation

- Owner:group of the hook file:
- File mode of the hook file:
- Can pipeline-app write to the hook? YES / NO
- Reason this is a trust violation:

## 4. Controlled escalation

- Hook content used:
- Command used to invoke the utility:
- uid/gid after escalation:
- Escalation confirmed inside the container only: YES / NO

## 5. Flag recovery

- S05 flag file path:
- S05 flag format: IE3132{PP_S05_<32 hex>}
- CTFd accepted token: YES / NO

## 6. S06 handoff

- S06 pivot user recovered:
- S06 pivot credential recovered: YES / NO
- S06 pivot host identified:

## 7. Notes

- Unexpected shortcuts attempted:
- Incorrect paths attempted:
- Difficulty comments:

