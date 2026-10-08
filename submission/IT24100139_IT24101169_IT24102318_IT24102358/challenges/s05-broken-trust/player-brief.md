# S05 - Broken Trust

You now have code execution as the `pipeline-app` service account inside the
Application Challenge container.

A privileged deployment verification utility is installed in this container.
Its job is to run during release promotion, but it trusts a validation hook
defined by the deployment configuration.

## Objective

- Enumerate the local privilege boundary.
- Identify the privileged utility and its sudo policy.
- Identify the configuration it trusts.
- Determine which trusted file or path you can modify as `pipeline-app`.
- Use the trusted utility to escalate to `uid 0` **inside this container only**.
- Recover the S05 token and the S06 handoff credential.

## Rules

- Do not attempt to reach the Docker daemon or the Ubuntu host.
- Do not attempt to modify host namespaces, host mounts, or the Docker socket.
- The intended escalation is entirely local to this container.
- Kernel exploits, package CVEs, and unrelated misconfigurations are out of scope.

## Hints

- H1 (-5%): The intended flaw is local configuration, not a public kernel CVE.
- H2 (-10%): Compare what `sudo -l` permits with the files that utility trusts.
- H3 (-15%): One trusted hook reference is writable by the service account group.

## Flag format

IE3132{PP_S05_<32 hex>}
