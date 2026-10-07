# S04 - Poisoned Runtime

The S03 forensic analysis revealed that a component in the Nexora
release was substituted from an unexpected package source. That
substituted component introduced an undocumented diagnostics feature
into the running application.

You have been given:

- the affected application version
- the target host alias
- the diagnostics feature path

## Objective

- Enumerate the application service.
- Identify the unsafe diagnostics behaviour.
- Write a small Python proof-of-concept that triggers controlled
  command execution.
- Confirm the execution identity.
- Recover the S04 flag.

## Token location

The S04 flag is a file readable by the application service account
after successful code execution.

## Rules

- Only attack the isolated lab container.
- Do not attempt to access the Docker host, other containers, or
  any external system.
- The diagnostics endpoint is expected to execute under the same
  low-privileged account as the application itself.

## Hints

- H1: The substituted component added an undocumented diagnostics
  capability.
- H2: Compare the endpoint input with the server-side action it
  triggers.
- H3: Automate one crafted request and verify the executing account.
