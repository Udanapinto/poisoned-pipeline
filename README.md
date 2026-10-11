# Operation Poisoned Pipeline

**IE3132 – Penetration Testing | Assignment 02 | Group 40**  
**Project type:** Docker-based Capture the Flag (CTF) Play Box  
**Repository:** To be added before final submission

## 1. About our project

For our Assignment 02, we developed **Operation Poisoned Pipeline**, a six-stage CTF that follows a simulated software supply-chain compromise at a fictional company called Nexora Technologies. Instead of keeping the challenges completely separate, we connected them so that information or access obtained in one stage helps the participant move to the next stage.

We used Docker Compose to run the platform, challenge services and a Kali Linux participant environment on an isolated lab network. This README explains how to prepare, deploy, test and reset the box using the project files included in our submission.

### Group members

| Student ID | Name |
|---|---|
| IT24100139 | Pinthu D.I.U. |
| IT24101169 | Weligampitiya S.A.S.D. |
| IT24102318 | Wickrama Edirisooriya A.A.G. |
| IT24102358 | Silva D.P.L.T.D. |

## 2. Challenge pathway

| Stage | Challenge | Main area | Difficulty | Points |
|---|---|---|---|---:|
| S01 | The Git Leak | OSINT and Git reconnaissance | Easy | 100 |
| S02 | Pipeline Breach | Web security and CI/CD investigation | Easy | 100 |
| S03 | The Ghost Dependency | Software supply-chain forensics | Moderate | 150 |
| S04 | Poisoned Runtime | Application command execution | Moderate | 200 |
| S05 | Broken Trust | Linux privilege escalation | Moderate–Hard | 200 |
| S06 | Behind the Firewall | Network pivoting and database access | Hard | 250 |
| | **Total** | | | **1,000** |

Our intended path is **Git history → Jenkins build evidence → dependency investigation → vulnerable application → local privilege escalation → internal PostgreSQL database**. S06 is the final challenge. The detailed participant instructions are provided in the relevant `challenges/s0*/` folders, and the CTFd setup reference is in `scripts/ctfd-export-challenges.sh`.

The flag format is `IE3132{PP_S0X_<32-hex-token>}`. Each stage uses its own generated flag or derived answer. We use CTFd to validate submissions and manage challenge points and hints.

## 3. Technologies and architecture

Our project uses **Ubuntu 24.04 LTS**, Docker Engine and Docker Compose v2. The main services are:

- **Nginx** – HTTPS reverse proxy and entry point.
- **CTFd, MariaDB and Redis** – challenge platform, database and supporting cache.
- **Gitea** – seeded Git repository for S01.
- **Jenkins** – historical pipeline and artifacts for S02 and S03.
- **Custom Python/Flask application** – application challenge used by S04–S06.
- **PostgreSQL 16** – protected database containing the final S06 record.
- **Kali Linux container** – participant environment and testing tools.

We separated the services into three Docker networks:

| Network | Subnet | Purpose |
|---|---|---|
| `player_net` | `10.13.10.0/24` | Participant-facing services and Kali |
| `control_net` | Docker-managed internal network | CTFd, MariaDB, Redis, Gitea and Jenkins |
| `internal_net` | `10.13.20.0/24` | Protected application-to-database path |

Only **TCP 443** is published to the Ubuntu host by Nginx in `compose.yml`. CTFd, Gitea, Jenkins and PostgreSQL do not publish their application ports directly to the host. Kali is attached to `player_net`, whereas PostgreSQL is attached only to `internal_net`. For the last challenge, participants must use the intended application/SSH pivot rather than connecting directly to the database.

## 4. Requirements before installation

We recommend an Ubuntu 24.04 LTS lab machine or VM with enough RAM and disk space for Docker images and Jenkins. A stable internet connection is needed for the initial image downloads.

Required tools: Docker Engine, the Docker Compose plugin, Git, Python 3, Bash, OpenSSL, curl, jq and unzip. Install the basic Ubuntu packages with:

```bash
sudo apt update
sudo apt install -y git curl jq unzip openssl python3 python3-venv
```

Install Docker Engine and the Compose plugin using Docker's official Ubuntu installation instructions: <https://docs.docker.com/engine/install/ubuntu/>.

Check that Docker works:

```bash
docker --version
docker compose version
docker run --rm hello-world
```

If Docker gives a socket permission error, use `sudo` for Docker commands or configure the Docker group on your trusted lab VM. Docker group membership grants powerful access to the host.

## 5. Open the submitted project

Extract the submitted ZIP and open a terminal **inside the folder containing `compose.yml`**. For example, if the extracted folder is named `poisoned-pipeline`:

```bash
cd poisoned-pipeline
ls compose.yml .env.example scripts/
```

For a fresh build, also confirm that the submitted package includes `scripts/generate-tls-cert.sh` and `challenges/s01-git-leak/seed/create-s01-bundle.sh`. These two files are used by the setup sequence below.

All commands in the next sections are run from this folder. The submitted files can be used directly; cloning GitHub is not required. We will add our repository link separately.

### Main folders

```text
poisoned-pipeline/
├── application/        # Flask application, container build and challenge logic
├── challenges/         # S01–S06 challenge files, briefs, PoCs and solvers
├── ctfd/               # CTF platform-related project files
├── evidence/           # Test logs, screenshots and verification results
├── gitea/              # Git challenge material and public signing key
├── jenkins/            # Dockerfile, configuration and release job
├── kali/               # Participant container
├── nginx/              # HTTPS reverse proxy configuration
├── postgres/           # Database initialization
├── scripts/            # Secret generation, seeding, build and reset scripts
├── tests/              # Automated verification checks
├── .env.example        # Environment configuration template
├── compose.yml         # Docker Compose services and networks
└── README.md
```

Some copies of our development package also include an existing `.env`, `private/` directory, `golden-seed.tar.gz` and test backups. These are lab-generated data used for demonstration or recovery. **If they are included, keep the matching files together**. Regenerating only part of an existing setup can make the flags, signing keys or restored database state inconsistent.

## 6. Prepare a fresh installation

This section is for a fresh deployment **without an already configured lab state**. If you are restoring a matching existing baseline, read Section 10 first.

### Step 1 – Set the environment values

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

Update the placeholder values, especially `CTFD_DB_PASSWORD`, `MARIADB_ROOT_PASSWORD`, `POSTGRES_PASSWORD` and `CTFD_SECRET_KEY`. We generate individual random values with:

```bash
openssl rand -hex 24
```

Use a separate value for each required setting. The S06 generation script also sets up the PostgreSQL administrator value used by the Compose configuration. Do not copy test credentials from another unrelated project.

### Step 2 – Generate challenge material

Run these scripts in the order shown:

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

These scripts prepare the local TLS certificate, S01 Git history and signing material, S03 forensic evidence, stage credentials and final database configuration. Most generated stage settings are stored under `private/s01/` through `private/s06/`. This is a controlled CTF, so these credentials are synthetic lab values, not real organization accounts.

The Nginx certificate is self-signed. A browser certificate warning is expected when accessing this local lab.

### Step 3 – Build the images and start the services

The application must be built using its provided script because it stages private build-time challenge files:

```bash
docker compose config -q
bash scripts/build-application.sh
docker compose build jenkins kali
docker compose up -d --no-build
docker compose ps
```

The first build may take some time while Docker downloads images and Jenkins dependencies. Wait for services with health checks to become healthy. If one is not starting, inspect its logs:

```bash
docker compose logs --tail=80 ctfd
docker compose logs --tail=80 jenkins
docker compose logs --tail=80 application
```

For later application rebuilds, use `bash scripts/build-application.sh` so its private build inputs are prepared correctly.

### Step 4 – Seed the challenge services

After the containers start, initialize the Git challenge, Jenkins historical release data and the final PostgreSQL record:

```bash
bash scripts/reset-s01.sh
bash scripts/seed-jenkins-s02.sh
bash scripts/seed-postgres-s06.sh
```

`reset-s01.sh` recreates the Gitea challenge state, so it is appropriate for initial setup or an intentional reset, not for preserving an existing Git service. The Jenkins and database seed scripts populate the challenge records required for the intended path.

### Step 5 – Configure CTFd

Open **<https://localhost/>** in the browser on the Ubuntu host. The lab gateway can also be reached at **<https://10.13.10.20/>** where Docker bridge routing allows it. If Ubuntu is running in a VM, open the URL inside that VM unless you have configured additional host-to-VM networking.

On a fresh CTFd installation, complete the first-run setup and create the administrator account. Then open the CTFd administration area and manually add the six challenges. We use this script as our configuration reference:

```bash
bash scripts/ctfd-export-challenges.sh
```

It prints the **challenge titles, categories, points, flag formats and three hints per stage**. Add the actual generated flag values from the corresponding private stage files, rather than entering the example formats. S03 uses the derived token documented in its player brief and private answer manifest. Our `ctfd-apply-challenges.py` is a reference helper, **not a finished automatic importer**, so the admin-interface step remains necessary for a fresh deployment.

After creating the challenges, confirm that all six appear on the CTFd Challenges page and that the correct flags are accepted.

## 7. How to access the CTF

| Service | Lab URL or address | Usage |
|---|---|---|
| CTFd | `https://localhost/` or `https://10.13.10.20/` | Challenge portal and flag submission |
| Gitea | `https://10.13.10.20/git/` | S01 Git investigation |
| Jenkins | `https://10.13.10.20/jenkins/` | S02 pipeline investigation and S03 evidence |
| Application | `http://10.13.10.30:5000/` | S04 and S05 target within the lab |
| PostgreSQL | `10.13.20.10:5432` | S06 protected database, not directly exposed |

To enter the participant container:

```bash
docker compose exec kali bash
```

The Kali container provides the participant-side network view. The intended challenge environment should not be connected to public or university production networks.

## 8. Checking whether the box works

After the services are seeded and CTFd is configured, run our verification scripts:

```bash
bash tests/stages/verify-clean-deploy.sh
bash tests/stages/verify-phase14-ctfd.sh
bash tests/stages/verify-end-to-end.sh
bash tests/stages/verify-bypass.sh
bash tests/stages/verify-isolation-sweep.sh
```

Our submitted `evidence/test-results/` directory includes recorded results from our implementation. Examples include:

| Evidence file | Result recorded in our lab |
|---|---|
| `phase17-clean-deploy.txt` | 30 checks passed |
| `phase17-end-to-end.txt` | 10 checks passed |
| `phase17-bypass.txt` | 13 checks passed |
| `phase16-reproducibility.txt` | 15 checks passed |
| `phase14-ctfd-verification.txt` | 15 checks passed |

The end-to-end checks cover the Git-history clue, Jenkins artifact access, S03 evidence, low-privilege execution in S04, S05 local privilege boundary and the S06 network/database path. The bypass checks look for shortcuts such as direct database access and access to later-stage secrets before the intended stage is solved.

These logs show the results from our recorded lab; the lecturer can rerun the checks on the deployed box.

## 9. Normal stop, start and troubleshooting

To stop containers without discarding named volumes:

```bash
docker compose stop
```

To start the same existing installation again:

```bash
docker compose up -d --no-build
docker compose ps
```

Useful checks if a service is not accessible:

```bash
docker compose ps
docker compose logs --tail=80 nginx
docker compose logs --tail=80 gitea
docker compose logs --tail=80 jenkins
sudo ss -tulpn | grep ':443'
```

If port 443 is already used by another local service, identify that service before restarting Nginx. If CTFd unexpectedly shows its setup page, check the MariaDB container and existing Docker volumes first; it can indicate that CTFd is using a new or empty database. If Nginx returns 502 after a backend restarts, check that backend's health and then try `docker compose restart nginx`.

## 10. Reset and recovery

We implemented two forms of recovery:

**Individual/full challenge reset.** To return challenge state to the intended starting point, the repository includes `scripts/reset-s01.sh` through `scripts/reset-s06.sh` and the master script:

```bash
bash scripts/reset-all.sh
```

The master reset reinitializes the stages, resets Kali and runs stage verification. It intentionally recreates some Gitea, Jenkins and PostgreSQL challenge data. Use it when the current challenge progress is no longer needed.

**Golden baseline recovery.** If the package includes `golden-seed.tar.gz`, it may contain a snapshot of Docker volumes and private configuration from our fully provisioned lab. It is intended for restoring a **matching** environment, using:

```bash
bash scripts/fast_reset.sh
```

This command **replaces current lab volume contents with the saved snapshot**. It is not an ordinary restart. Use it only when the archive, `.env` settings, images and project configuration belong to the same baseline and there is no new work to preserve. For a newly built installation, configure and verify everything first; a new baseline can then be created using `bash scripts/create_golden_seed.sh` if that script is included.

We keep recovery and repeatability evidence under `evidence/test-results/`, including multiple reset trials and post-reset end-to-end checks.

## 11. Source code and individual contribution evidence

The submission includes the challenge implementation files, stage solver scripts, automation, Docker configuration and test evidence. The main solver locations are:

```text
challenges/s01-git-leak/solver/s01-solver.sh
challenges/s02-pipeline-breach/solver/s02-solver.sh
challenges/s03-ghost-dependency/solver/s03-solver.sh
challenges/s04-poisoned-runtime/solver/s04-solver.py
challenges/s05-broken-trust/solver/s05-solver.sh
challenges/s06-behind-firewall/solver/s06-solver.sh
```

Additional proof-of-concept files are included under the challenge `poc/` directories. The `tests/` scripts and `evidence/` outputs document our integration testing, security validation, isolation checks and reset trials. Our Git commit history and the repository link, once added, provide additional contribution evidence.

## 12. Safety and references

This box is built for authorized learning and marking purposes only. Its intentionally vulnerable features, lab flags and seeded credentials should be used **only within the isolated project environment**. We do not use real user credentials or target external systems. The group acknowledges the third-party tools and container images used in the implementation, including Docker, Nginx, CTFd, Gitea, Jenkins, Flask, PostgreSQL, MariaDB, Redis and Kali Linux. The exact configured image references are in `compose.yml`, `.env.example`, and the relevant Dockerfiles. Our main upstream references are:

- [Docker / Docker Compose](https://docs.docker.com/)
- [CTFd](https://docs.ctfd.io/)
- [Gitea](https://docs.gitea.com/)
- [Jenkins](https://www.jenkins.io/doc/)
- [Nginx](https://nginx.org/en/docs/)
- [Flask](https://flask.palletsprojects.com/)
- [PostgreSQL](https://www.postgresql.org/docs/)
- [MariaDB](https://mariadb.com/docs/)
- [Redis](https://redis.io/docs/latest/)
- [Kali Linux](https://www.kali.org/docs/)

The submitted demonstration video shows our running implementation. This README is intended to help the lecturer reproduce and inspect the CTF using the source files.
