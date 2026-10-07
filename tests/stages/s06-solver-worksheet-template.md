# S06 - Behind the Firewall Solver Worksheet

Complete this worksheet independently while solving S06. Copy this file,
fill it in, and keep the completed copy as evidence.

## 1. Prerequisites

- Root obtained inside the Application Challenge container (S05): YES / NO
- S06 pivot credential recovered: YES / NO
- S06 pivot user / host / port identified:
- Database reader credential recovered:

## 2. Reconnaissance

- `ip addr` output on the Application container:
- `ip route` output on the Application container:
- Additional subnets or interfaces discovered:
- Direct attempt to reach PostgreSQL from Kali:
  - Command used:
  - Result:
- Conclusion about direct reachability:

## 3. Tunnel establishment

- Command used to start the SSH SOCKS proxy:
- Local listening port for the SOCKS proxy:
- Command used to verify the tunnel was active:

## 4. Proxied discovery

- Proxied tool(s) used (proxychains, nmap -sT -Pn, etc.):
- PostgreSQL host/port discovered through the tunnel:
- Evidence that PostgreSQL was reached only through the tunnel:

## 5. Read-only database access

- psql command used:
- Row returned from `ctf_final`:
- S06 flag value recovered:
- S06 flag format: IE3132{PP_S06_<32 hex>}
- CTFd accepted token: YES / NO
- Attempt to INSERT / UPDATE / DELETE was denied: YES / NO

## 6. Full chain summary

- Artefact carried from S01 into S02:
- Artefact carried from S02 into S03:
- Artefact carried from S03 into S04:
- Artefact carried from S04 into S05:
- Artefact carried from S05 into S06:
- Overall incident reconstruction in 3–5 sentences:

## 7. Notes

- Unexpected shortcuts attempted:
- Incorrect paths attempted:
- Difficulty comments:
