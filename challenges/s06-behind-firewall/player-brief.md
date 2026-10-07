# S06 - Behind the Firewall

You have escalated to root inside the Application Challenge container and
recovered an SSH pivot credential from S05.

The Nexora production database is reachable only from the Application
Challenge container's internal interface. It is not published to the
participant network and it does not listen on the Ubuntu host.

## Objective

- Map the routing and interfaces available to you.
- Establish a controlled SSH tunnel through the Application Challenge
  container.
- Discover the PostgreSQL service through the tunnel.
- Authenticate with the read-only database account and query the final
  incident record.

## Token location

The S06 token is stored in the `ctf_final` table of the `nexora_prod`
database, in the row with `record_key = 's06_final_record'`.

## Rules

- Do not attempt to reach the PostgreSQL container directly; the intended
  route is the SSH tunnel.
- Do not attempt to write to the database; the player account is
  SELECT-only.
- Do not attempt to bypass the tunnel by attaching to internal_net.

## Hints

- H1: The attacked server has multiple network interfaces.
- H2: Use its SSH service as a controlled relay.
- H3: An application configuration that is only useful after tunnelling
      contains a database identity.