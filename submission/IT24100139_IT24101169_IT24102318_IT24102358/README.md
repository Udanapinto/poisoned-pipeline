# Operation Poisoned Pipeline

A fully Docker-based Capture The Flag (CTF) play box implementing a six-stage
software supply chain attack investigation.

## Overview

Operation Poisoned Pipeline is a CTF environment designed for the IE3132
Penetration Testing module. It simulates a software supply chain compromise
across six progressive stages:

| Stage | Name | Domain | Difficulty | Points |
|-------|------|--------|------------|--------|
| S01 | The Git Leak | OSINT / Reconnaissance | Easy | 100 |
| S02 | Pipeline Breach | Web Technologies / Web Security | Easy | 100 |
| S03 | The Ghost Dependency | Digital Forensics | Moderate | 150 |
| S04 | Poisoned Runtime | Linux and System Security | Moderate | 200 |
| S05 | Broken Trust | Linux and System Security | Moderate-Hard | 200 |
| S06 | Behind the Firewall | Networking | Hard (capstone) | 250 |

**Total: 1000 points**

## Architecture

The environment is built with Docker Compose and consists of:

- **CTF control stack**: Nginx, CTFd, MariaDB, Redis
- **Early-stage services**: Gitea (S01), Jenkins (S02)
- **Application Challenge**: Custom Flask container (S04, S05, S06 pivot)
- **Database Challenge**: PostgreSQL 16 (S06)
- **Participant environment**: Kali Linux container

Three isolated Docker networks enforce the security boundaries:

- `player_net` (10.13.10.0/24): Participant-facing network
- `control_net`: Isolated control/services network
- `internal_net` (10.13.20.0/24): Protected database network

## Prerequisites

- Ubuntu 24.04 LTS (or similar Linux host)
- Docker Engine 28.x
- Docker Compose v2
- Git
- OpenSSL
- jq
- unzip

## Quick Start

### 1. Clone the repository

```bash
git clone <repository-url>
cd poisoned-pipeline

