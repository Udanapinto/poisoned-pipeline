# Operation Poisoned Pipeline

This is our **IE3132 Penetration Testing** group project. We built a Docker-based CTF environment where players investigate a software supply-chain attack across six connected challenges. Each stage gives a clue or access needed for the next one.

**Repository:** https://github.com/Udanapinto/poisoned-pipeline

| Stage | Challenge | Points |
|---|---|---:|
| S01 | The Git Leak | 100 |
| S02 | Pipeline Breach | 100 |
| S03 | The Ghost Dependency | 150 |
| S04 | Poisoned Runtime | 200 |
| S05 | Broken Trust | 200 |
| S06 | Behind the Firewall | 250 |
| **Total** | | **1,000** |

## 1. Before starting

We developed the project for **Ubuntu 24.04 LTS**, with Docker Engine, Docker Compose v2, Git and Python 3. The stack uses Nginx, CTFd, MariaDB, Redis, Gitea, Jenkins, Flask, PostgreSQL 16 and a Kali participant container.

Install the basic tools:

```bash
sudo apt update
sudo apt install -y git curl jq unzip openssl python3 python3-venv
```

Install Docker Engine and the Compose plugin using the [official Ubuntu instructions](https://docs.docker.com/engine/install/ubuntu/) if they are not already installed. Check the installation:

```bash
docker --version
docker compose version
docker run --rm hello-world
```

If Docker reports a permission error, add your account to the Docker group with `sudo usermod -aG docker "$USER"`, then log out and log back in. Docker group access gives elevated control over the host, so use it only on a trusted development machine.

## 2. Get the project files

```bash
git clone https://github.com/Udanapinto/poisoned-pipeline.git
cd poisoned-pipeline
```

Run the remaining commands **from this project folder**. VS Code can be opened with `code .` if installed.

## 3. Prepare the environment and challenge data

First, create the local environment file:

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

Replace the `CHANGE_ME` values with separate strong values. For the CTFd database password, MariaDB root password and CTFd secret key, I used random hex values (generate each one using `openssl rand -hex 24`). The stage flags and Jenkins credentials are generated separately by the scripts below. The S06 generator also adds the required `POSTGRES_ADMIN_PASSWORD` to `.env`.

Generate the TLS certificate, challenge secrets, Git history and S03 evidence **in this order**:

```bash
bash scripts/generate-tls-cert.sh
bash scripts/generate-s01-secrets.sh
bash challenges/s01-git-leak/seed/create-s01-bundle.sh
bash scripts/generate-s02-secrets.sh
bash scripts/generate-s03-secrets.sh
bash scripts/generate-s03-evidence.sh
bash scripts/generate-s04-secrets.sh
bash scripts/generate-s05-secrets.sh
bash scripts/generate-s06-secrets.sh
```

These scripts create files under `private/` and prepare the signed S01/S03 material. **Keep `.env`, `private/`, certificates' private keys and generated flags out of GitHub.** The TLS certificate is self-signed because this is a local lab.

## 4. Build and start the containers

The application image must be built through its own script because S04–S06 use private build-time files. After that, build Jenkins and Kali, then start the complete stack:

```bash
docker compose config -q
bash scripts/build-application.sh
docker compose build jenkins kali
docker compose up -d --no-build
docker compose ps
```

Check that the services are running. Jenkins and CTFd can take longer than the other containers to become healthy. If a service has a problem, view its logs with:

```bash
docker compose logs --tail=80 ctfd
docker compose logs --tail=80 jenkins
```

For this repository, avoid rebuilding the application with a general `docker compose up -d --build` after the private staging files have been cleaned up; use `scripts/build-application.sh` when its image needs to be rebuilt.

## 5. Seed the challenge services

For a **fresh lab installation**, create the Gitea challenge repository, Jenkins historical builds and S06 database records:

```bash
bash scripts/reset-s01.sh
bash scripts/seed-jenkins-s02.sh
bash scripts/seed-postgres-s06.sh
```

The first script recreates the S01 Gitea challenge data, so it should not be used to preserve an existing Gitea setup. The second script loads the Jenkins release job and its historical artifacts; the third adds the final database record and read-only credentials.

## 6. Complete CTFd setup

Open **https://10.13.10.20/** in Ubuntu's browser (or `https://localhost/` through the published Nginx port). Accept the self-signed certificate warning for this lab only.

On the first visit, complete the CTFd setup page and create the administrator account. Then sign in and add the six challenges from the table above. To see the configured categories, descriptions of the flag formats, scores and three hints per challenge, run:

```bash
bash scripts/ctfd-export-challenges.sh
```

Add the **real generated flags**, not the example flag formats. They are kept in `private/s01/s01.env`, `private/s02/s02.env`, `private/s03/answer-manifest.env`, and `private/s04/`, `private/s05/`, `private/s06/` respectively. S03 uses a derived flag. The supplied CTFd API helper is not a complete importer, so we add the challenges through the administrator interface.

### Main lab addresses

| Service | Address |
|---|---|
| CTFd | `https://10.13.10.20/` |
| Gitea (S01) | `https://10.13.10.20/git/` |
| Jenkins (S02) | `https://10.13.10.20/jenkins/` |
| Flask challenge (S04–S05) | `http://10.13.10.30:5000/` |
| PostgreSQL (S06) | `10.13.20.10:5432` — internal network only |

## 7. Test the full setup

Run the checks after seeding the services and finishing CTFd setup:

```bash
bash tests/stages/verify-clean-deploy.sh
bash tests/stages/verify-phase14-ctfd.sh
bash tests/stages/verify-end-to-end.sh
bash tests/stages/verify-isolation-sweep.sh
```

For the participant view, enter the Kali container:

```bash
docker compose exec kali bash
```

Our network design uses `player_net` (`10.13.10.0/24`), `control_net` and `internal_net` (`10.13.20.0/24`). Kali should **not** reach PostgreSQL directly; the intended S06 path is through the application/SSH pivot. If external egress blocking is required by your lab checks, `scripts/enforce-application-egress-block.sh` configures host firewall rules and needs administrator access; review the rules before applying them.

## 8. Normal operation, reset and evidence

To stop and restart the containers **without deleting their volumes**:

```bash
docker compose stop
docker compose up -d --no-build
```

After the full environment is verified, we can save a local baseline and record the build details:

```bash
bash scripts/create_golden_seed.sh
bash scripts/generate-build-manifest.sh
```

The baseline archive contains sensitive configuration and database data, so it must be stored privately. The stage reset command below **recreates challenge state**; run it only when a reset is intended:

```bash
bash scripts/reset-all.sh
```

For Fast reset process:

```bash
bash scripts/fast_reset.sh
```

Our test results and screenshots are organized under `evidence/test-results/`, `evidence/logs/` and `evidence/screenshots/`. We use these files to show the working challenges, network isolation and repeatable setup during the assignment demonstration.

## Quick troubleshooting

- **Port 443 already in use:** check with `sudo ss -tulpn | grep ':443'` and identify the conflicting service.
- **Missing environment variable:** check `.env` and rerun the relevant secret generator.
- **Container not healthy:** use `docker compose ps` followed by `docker compose logs --tail=80 <service>`.
- **CTFd shows the setup page again:** check the MariaDB container and the existing CTFd volumes before resetting anything.
- **Gitea/Jenkins returns 502:** check their containers and restart Nginx with `docker compose restart nginx` if the backend was recreated.

This project is an **intentionally vulnerable training environment**. We run it only on our isolated lab machine and do not expose the challenge services to the public internet.
