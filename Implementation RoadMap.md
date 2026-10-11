# Operation Poisoned Pipeline — Project Implementation Roadmap

## Recommended Development Environment

For our project implementation, we selected the following development environment and technologies.

**Host OS:** Ubuntu 24.04 LTS  
**Editor:** VS Code  
**Runtime:** Docker Engine 28.x  
**Orchestration:** Docker Compose v2  
**Version control:** Git  
**Primary coding:** Python / Flask, shell scripts, YAML, Dockerfiles  
**Database:** PostgreSQL 16 + MariaDB for CTFd  
**CTF platform:** CTFd  
**Git server:** Gitea  
**CI/CD:** Jenkins LTS  
**Proxy:** Nginx  

These technologies match the technical baseline that we defined in our project design.

We can use Ubuntu Desktop 24.04 instead of Ubuntu Server for our development work. However, we need to record the actual host operating system in our implementation evidence if it differs from our original design baseline.

---

# Full Implementation Roadmap

For our CTF project, I divided the initial implementation process into **14 phases** instead of deploying the complete Docker Compose environment at once.

This approach allows us to develop and test each component separately before connecting everything together. It also makes troubleshooting easier because we can identify problems within a particular phase.

The implementation starts with preparing Ubuntu and Docker, followed by creating the network architecture, setting up the necessary services, developing the six CTF challenges, and finally integrating and testing the complete environment.

## Phase 1 — Prepare Ubuntu

The first task is to prepare Ubuntu with the tools we need for development.

First, update the system:

```bash
sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y
```

Next, install the basic development tools:

```bash
sudo apt install -y \
git \
curl \
wget \
jq \
tree \
unzip \
ca-certificates \
gnupg \
python3 \
python3-pip \
python3-venv
```

After installation, verify that the main tools are working:

```css
git --version
python3 --version
curl --version
jq --version
```

Once these tools are installed, we can install VS Code and open our project folder.

For VS Code, we use the following extensions:

- Docker
- YAML
- Python
- GitLens
- Remote Development

One important consideration is how we manage the challenge flags. When we start generating the actual flag values, we should not store them directly in public source files that are visible through VS Code and our Git repository.

---

## Phase 2 — Install and Verify Docker

Our project design requires Docker Engine 28.x and Docker Compose v2.

After installing Docker, I verify the installation using these commands:

```lua
docker --version
docker compose version
sudo systemctl status docker
```

Next, add our Ubuntu user account to the Docker group:

```bash
sudo usermod -aG docker $USER
```

After running this command, we need to log out and log back in for the group changes to take effect.

Then, test whether Docker can successfully run a container:

```
docker run --rm hello-world
```

This test is important because all the main components of our CTF environment will run using Docker.

Before moving to the next phase, we need to confirm that Docker and Docker Compose are working correctly.

---

# Phase 3 — Create the Project Repository

For this project, we use one main Git repository to organize all the implementation files.

First, create the project directory:

```bash
mkdir -p ~/Projects
cd ~/Projects

mkdir poisoned-pipeline
cd poisoned-pipeline

git init
code .
```

I organized the project using the following directory structure:

```arduino
poisoned-pipeline/
│
├── compose.yml
├── .env.example
├── .gitignore
├── README.md
│
├── nginx/
│   ├── nginx.conf
│   └── certs/
│
├── ctfd/
│   ├── config/
│   ├── challenges/
│   └── seeds/
│
├── gitea/
│   ├── config/
│   └── seeds/
│       └── repository/
│
├── jenkins/
│   ├── Dockerfile
│   ├── casc/
│   │   └── jenkins.yaml
│   ├── jobs/
│   └── artifacts/
│
├── challenges/
│   ├── s01-git-leak/
│   ├── s02-pipeline-breach/
│   ├── s03-ghost-dependency/
│   ├── s04-poisoned-runtime/
│   ├── s05-broken-trust/
│   └── s06-behind-firewall/
│
├── application/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── app/
│   ├── scripts/
│   ├── sudoers/
│   └── ssh/
│
├── postgres/
│   ├── init/
│   └── seed.sql
│
├── kali/
│   └── Dockerfile
│
├── seeds/
│   ├── git/
│   ├── jenkins/
│   ├── evidence/
│   └── database/
│
├── scripts/
│   ├── build.sh
│   ├── start.sh
│   ├── stop.sh
│   ├── reset.sh
│   ├── test.sh
│   ├── verify-isolation.sh
│   └── checksums.sh
│
├── tests/
│   ├── stages/
│   ├── networking/
│   ├── isolation/
│   └── reset/
│
├── evidence/
│   ├── screenshots/
│   ├── logs/
│   └── test-results/
│
└── private/
    └── build-manifest.example.yml
```

We separated the project files based on their purpose.

The directory:

```
challenges/
```

contains the player-facing implementation files for the six CTF stages.

The directory:

```
private/
```

is used to store instructor-side and developer-side information, such as answers, generated flag records, and validation data.

According to our project design, actual randomly generated flags should not be included in the ordinary project repository.

This separation helps us maintain the intended challenge difficulty and prevents participants from finding sensitive information directly in the project source files.

---

# Phase 4 - DONE — Build the Docker Networks FIRST

For this phase, we focused on creating the Docker network architecture before deploying the CTF services.

We decided to complete the network setup first because all the other project components depend on these networks.

According to our design, the network architecture contains three Docker networks:

```
player_net   → 10.13.10.0/24
internal_net → 10.13.20.0/24
control_net  → isolated control network
```

Each network has a specific responsibility.

The participant container should only be connected to `player_net`, while the Application Challenge container must be connected to both `player_net` and `internal_net`.

For the initial setup, we configure only the network definitions inside our `compose.yml`.

The network configuration is:

```yaml
networks:

  player_net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.13.10.0/24

  control_net:
    driver: bridge
    internal: true

  internal_net:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 10.13.20.0/24
```

After creating these networks, we test them using temporary Alpine containers.

To check the Docker networks, we use:

```
docker network ls
docker network inspect poisoned-pipeline_player_net
docker network inspect poisoned-pipeline_internal_net
docker network inspect poisoned-pipeline_control_net
```

### Phase 4 Checkpoint

Before completing this phase, we need to verify that all three required networks exist:

```arduino
player_net     exists
control_net    exists
internal_net   exists
```

This network architecture provides the foundation for our challenge isolation and communication requirements.

---

# Phase 5 - DONE — Build the CTF Control Stack

In this phase, we implemented the main CTF control services.

The required components are:

```
Nginx
CTFd
MariaDB
Redis
```

These services handle participant access, challenge descriptions, scoring, hints, and flag validation.

MariaDB and Redis are kept isolated from direct participant access.

We planned the deployment in the following order:

```
MariaDB
   ↓
Redis
   ↓
CTFd
   ↓
Nginx
```

We do not expose the MariaDB or Redis ports directly to the Ubuntu host.

Our intended communication flow is:

```
Browser
   ↓ HTTPS
Nginx
   ↓
CTFd
```

Nginx acts as the main participant-facing gateway.

According to our communication design, Nginx forwards requests internally to CTFd, Gitea, and Jenkins.

The backend service ports remain inside `control_net`.

### Phase 5 Checkpoint

First, check the running containers:

```
docker compose ps
```

Then, test the HTTPS connection:

```
curl -I https://localhost
```

The expected result is that CTFd loads through Nginx.

This confirms that the main CTF platform and reverse proxy are functioning correctly.

---

# Phase 6 - DONE — Implement S01: The Git Leak

In this phase, we implemented our first challenge, **S01 — The Git Leak**, using Gitea.

The purpose of this challenge is to demonstrate how sensitive credentials can remain exposed in Git history even after being removed from the latest version of a repository.

Our intended challenge flow is:

```bash
developer commits credential
        ↓
credential remains in Git history
        ↓
developer removes it from current tree
        ↓
participant examines history
        ↓
finds S01 flag + Jenkins credential
```

This flow follows the requirements defined for S01 in our project design.

For this challenge, we create a small sample project named `deployment-tools`.

Its structure is:

```
deployment-tools/
├── README.md
├── config/
│   └── pipeline.env
└── scripts/
    └── deploy.sh
```

Next, we create a controlled Git commit history.

The planned commit sequence is:

```sql
Commit A
normal project

Commit B
accidentally adds:
JENKINS_USER=...
JENKINS_PASSWORD=...
S01 flag

Commit C
removes credential

Commit D
normal update
```

In the final version of the branch, the credentials and flag must no longer appear in the current files.

However, they should still be recoverable from the Git history.

This means participants must investigate previous commits rather than simply reading the current repository files.

To solve the challenge, participants will need commands such as:

```perl
git log
git show
git diff
grep
```

Our project design specifically requires that the current branch does not expose the credential or flag directly.

For reproducibility, we create a repository-generation script at:

```
gitea/seeds/create-s01-repository.sh
```

We also need to generate and record the following evidence:

```sql
clean Git bundle
expected HEAD
commit count
commit SHA checksums
```

These details help us verify that the seeded repository contains the correct challenge history.

---

# Phase 7 - DONE — Implement S02: Pipeline Breach

The second challenge is **S02 — Pipeline Breach**, which uses Jenkins LTS.

In this phase, we configure Jenkins to simulate a CI/CD environment containing historical build artifacts.

As part of our security design, we do not provide Jenkins with direct access to:

```
/var/run/docker.sock
```

Our design specifically excludes Docker socket access.

For configuration management, we use Jenkins Configuration as Code.

The main configuration file is:

```
jenkins/casc/jenkins.yaml
```

We configure a synthetic Jenkins user named:

```
pipeline-reader
```

This user receives limited permissions:

```
View jobs
Read builds
Read artifacts
```

The account must not be able to perform administrative or build-execution operations such as:

```
Create job
Configure job
Run arbitrary script
Install plugin
Administer Jenkins
```

According to our design, this user represents an old CI integration account that still has access to historical build information and artifacts.

However, it cannot administer Jenkins or execute new builds.

For the challenge, we seed several fake Jenkins builds.

The planned build history is:

```bash
Build #101  normal
Build #102  normal
Build #103  compromised release
Build #104  normal
```

The compromised build includes archived evidence files.

These files are:

```
release-manifest.txt
evidence-s03.zip
S02 flag
```

The participant must investigate the historical builds to find the compromised release and retrieve the relevant evidence.

The `evidence-s03.zip` file is important because it becomes the input for the next challenge, S03.

This is how we connect S02 with S03 in our challenge sequence.

---

# Phase 8 - DONE — Implement S03: The Ghost Dependency

For **S03 — The Ghost Dependency**, we use a static evidence package instead of creating another vulnerable container.

The main objective is to investigate software supply-chain evidence and identify an unauthorized dependency.

According to our project design, the evidence package contains:

```lua
CycloneDX 1.7 JSON SBOM
build log
approved-component baseline
package URL information
SHA-256 manifest
```

We organize these files into the following structure:

```lua
s03-evidence/
├── sbom.json
├── build.log
├── approved-components.json
├── package-sources.txt
└── SHA256SUMS
```

For this challenge, we introduce one malicious or unauthorized package into the dependency information.

A simple example is:

```
approved:

nexora-utils
```

and the substituted dependency:

```
nexorra-utils
```

However, our challenge should not be solvable by only identifying a spelling difference.

Participants need to compare several pieces of evidence before identifying the correct component.

The required indicators are:

```
name
version
source
checksum
```

Our design requires exactly one evidence chain to satisfy all four indicators.

To make the evidence reproducible, we create a Python evidence-generation script:

```bash
challenges/s03-ghost-dependency/generate-evidence.py
```

This script generates the required challenge evidence instead of depending on manually edited files.

Using a script also allows us to recreate the same challenge materials during reset testing.

---

# Phase 9 - DONE — Build the Application Challenge Container

In this phase, we build the custom Application Challenge container.

This is one of the most important parts of our project because the same container supports three connected challenges:

**S04 — Poisoned Runtime, S05 — Broken Trust, and S06 — Behind the Firewall.**

According to our design, this container uses a pinned Linux environment with the following tools and components:

```
Python 3.9
Flask 3.x
OpenSSH
sudo
gcc
jq
challenge utilities
```

We start by creating the main Dockerfile:

```
application/Dockerfile
```

Then, we prepare the application requirements and startup files:

```bash
application/requirements.txt
application/app/app.py
application/scripts/entrypoint.sh
```

Inside the container, we create a dedicated user named:

```
pipeline-app
```

The Flask application must run under this account:

```
pipeline-app
```

It must not run as root.

For network communication, the Application Challenge container is connected to both required networks:

```
Application Challenge
    ├── player_net
    └── internal_net
```

The static IP addresses defined in our design are:

```
player_net   → 10.13.10.30
internal_net → 10.13.20.1
```

This configuration allows the participant to access the application through the player network while also allowing the application to communicate with services inside the internal network.

---

# Phase 10 - DONE — Implement S04: Poisoned Runtime

For S04, we implement an intentionally vulnerable diagnostics feature inside the Flask application.

The purpose of this challenge is to demonstrate controlled command execution through an unsafe application feature.

Our intended attack sequence is:

```
S03 reveals suspicious component
             ↓
participant finds diagnostics endpoint
             ↓
crafts Python request
             ↓
controlled command execution
             ↓
execution identity = pipeline-app
             ↓
S04 flag
```

This flow follows the S04 objective described in our project specification.

During development, we maintain two versions of the application code:

```bash
application/vulnerable/
application/patched/
```

The vulnerable version is used in the challenge environment.

The patched version is used for comparison and security documentation.

This helps us demonstrate both the vulnerability and how it can be corrected.

For the implementation, we must preserve an important security boundary:

```
S04 must get pipeline-app
NOT root
NOT Docker host
```

Our design explicitly requires the successful command execution to operate under the `pipeline-app` account.

The S04 flag should be stored in a location that is readable by the intended application account after successful interaction.

This allows the challenge to demonstrate command execution without giving the participant unintended root access.

---

# Phase 11 - DONE — Implement S05: Broken Trust

The S05 challenge is implemented inside the same Application Challenge container.

For this stage, we create a custom deployment verification utility:

```swift
/usr/local/bin/deploy-verify
```

We configure sudo permissions so that the `pipeline-app` user can execute only this utility with elevated privileges.

The intended sudo configuration is:

```ruby
pipeline-app ALL=(root) NOPASSWD: /usr/local/bin/deploy-verify
```

We do not provide unrestricted passwordless sudo access to other commands such as:

```bash
/bin/bash
/bin/sh
python
vim
less
find
```

The vulnerability in S05 is based on an unsafe trust relationship.

The root-running deployment verification utility reads a hook path from a configuration file.

However, the configuration is incorrectly writable by the `pipeline-app` group.

Our intended privilege escalation flow is:

```sql
deploy-verify
        ↓
reads deployment configuration
        ↓
uses trusted hook
        ↓
configuration is incorrectly group writable
        ↓
participant modifies hook
        ↓
sudo deploy-verify
        ↓
UID 0 inside container
```

When the participant successfully exploits this issue, they obtain root privileges inside the challenge container.

After obtaining root access, the participant can retrieve:

```
S05 flag
internal subnet clue
S06 SSH credential
```

However, we must verify that root privileges remain limited to the container.

The participant must not gain access to:

```cpp
Docker daemon
Ubuntu host root filesystem
host PID namespace
host network namespace
```

Our security design specifically prohibits these container escape paths.

This ensures that S05 demonstrates a controlled privilege escalation scenario without compromising the Ubuntu host environment.

---

# Phase 12 - DONE — Implement S06: Behind the Firewall

The final challenge is **S06 — Behind the Firewall**.

For this stage, we deploy PostgreSQL 16 inside the internal Docker network.

The database configuration is:

```
PostgreSQL 16
10.13.20.10
internal_net only
```

We do not expose the PostgreSQL port directly to the host using:

```makefile
ports:
  - "5432:5432"
```

We also do not connect PostgreSQL to:

```
player_net
```

According to our network design, PostgreSQL must be accessible only through `internal_net`.

Inside PostgreSQL, we create a synthetic database named:

```
nexora_prod
```

The database contains tables such as:

```
deployments
components
incident_records
ctf_final
```

We also create a restricted database account:

```
ctf_reader
```

This account receives only the following permission:

```
SELECT
```

It must not receive write or administrative permissions such as:

```sql
INSERT
UPDATE
DELETE
CREATE
DROP
```

The intended communication path for the final challenge is:

```yaml
Kali
 |
 | SSH
 v
Application Challenge
10.13.10.30
 |
 | internal_net
 v
10.13.20.10
PostgreSQL
```

The participant must use the SSH credential recovered from S05 to establish a controlled tunnel into the internal network.

The expected challenge-solving process includes:

```typescript
route/interface discovery
SSH SOCKS tunnel
proxied TCP enumeration
PostgreSQL discovery
DB authentication
final read-only query
```

A key requirement is that direct database access from Kali must fail.

The following path should not work:

```
Kali → PostgreSQL directly
```

However, the intended pivoting path should succeed:

```
Kali → Application → PostgreSQL
```

This isolation requirement is one of the most important validation points in our complete CTF implementation.

---

# Pentest Structure / Phase 13 — Build the Kali Participant Container

For our participant environment, we use a dedicated Kali Linux container.

We do not need to install every package available in Kali.

Instead, we install only the tools required to complete the six challenges.

The Dockerfile is created at:

```
kali/Dockerfile
```

The required tools are:

```
git
curl
jq
python
python requests
nmap
proxychains4
openssh-client
postgresql-client
netcat
grep
awk
diff
```

These tools match the participant toolset defined in our project design.

The Kali container must be connected only to:

```
player_net
```

It must not be connected to:

```
control_net
internal_net
```

After starting the Kali container, we verify the network configuration using:

```
ip addr
ip route
```

We also test that Kali cannot directly communicate with the PostgreSQL address.

This confirms that the participant environment follows our intended network isolation rules.

---

# Phase 14 — Integrate All Six Stages into CTFd

Once the six challenges work independently, we integrate them into CTFd.

We decided to complete the individual implementations before configuring the full challenge platform so that integration problems can be identified more easily.

The six challenges and their scores are:

| Stage | Challenge Name | Score |
|---|---|---|
| S01 | The Git Leak | 100 |
| S02 | Pipeline Breach | 100 |
| S03 | The Ghost Dependency | 150 |
| S04 | Poisoned Runtime | 200 |
| S05 | Broken Trust | 200 |
| S06 | Behind the Firewall | 250 |

The total available score is **1,000 points**.

For each stage, we configure three hints.

According to our design, the hint penalties are cumulative:

```ini
H1 = 5%
H2 = 10%
H3 = 15%
```

The maximum penalty is:

```
30%
```

We use the following flag formats:

```swift
IE3132{PP_S01_<32-hex>}
IE3132{PP_S02_<32-hex>}
IE3132{PP_S03_<derived-value>}
IE3132{PP_S04_<32-hex>}
IE3132{PP_S05_<32-hex>}
IE3132{PP_S06_<32-hex>}
```

Our design requires cryptographically generated 128-bit random values for the random-token stages.

S03 is different because its flag is based on the derived SHA-256 logic used in the dependency investigation.

---

# Complete Challenge Dependency Chain

One of the main requirements of our project is that all six challenges must be connected.

A participant should not be able to complete the challenges as unrelated activities.

Instead, each stage provides information needed for the next stage.

Our complete dependency chain is:

```markdown
S01 — The Git Leak
        |
        | Jenkins credential
        | job name
        v

S02 — Pipeline Breach
        |
        | SBOM
        | build log
        | approved components
        | checksums
        v

S03 — Ghost Dependency
        |
        | malicious component
        | application version
        | target
        | diagnostics clue
        v

S04 — Poisoned Runtime
        |
        | pipeline-app access
        | deploy-verify clue
        v

S05 — Broken Trust
        |
        | root inside container
        | internal subnet
        | SSH pivot credential
        v

S06 — Behind the Firewall
        |
        | PostgreSQL via SSH tunnel
        v

      FINAL FLAG
```

This sequence is based on the handoff matrix defined in our design document.

Because of these dependencies, we should not necessarily implement the challenges in stage-number order.

We need to consider the infrastructure dependencies as well.

For that reason, the recommended infrastructure implementation order is:

```swift
Docker
   ↓
Networks
   ↓
Application container
   ↓
PostgreSQL
   ↓
S04/S05/S06
   ↓
Gitea/S01
   ↓
Jenkins/S02
   ↓
S03 evidence
   ↓
CTFd
   ↓
Nginx
   ↓
Kali
   ↓
Full integration
```

We selected this order because S04, S05, and S06 contain most of the network architecture and container complexity.

If those components are not functioning correctly, completing the CTFd and Gitea configuration first will not solve the underlying infrastructure problems.

Therefore, validating the Application Challenge and PostgreSQL environment early is useful for the overall implementation.

---

# Phase 15 — Reset System

The reset system is a required part of our implementation.

According to our project design, the environment must support deterministic recreation and three successful reset trials.

To implement this, we create:

```
scripts/reset.sh
```

The reset process should follow this general structure:

```graphql
docker compose down

# remove only challenge-state volumes that are meant to reset

docker compose up -d --build
```

After restarting the environment, the reset script must restore the required challenge data.

This includes:

```bash
Gitea repository
Jenkins jobs/artifacts
S03 evidence
PostgreSQL data
flags
permissions
```

We should not use a broad Docker cleanup operation such as:

```css
docker system prune -a --volumes
```

as our official reset mechanism.

That command is too broad for a controlled CTF reset because it can remove Docker resources that are not part of the intended challenge state.

Instead, our reset script should identify the exact project resources that need to be recreated.

These include:

```
containers
volumes
seed archives
permissions
checksums
```

The objective is to restore the CTF environment to a known working state without affecting unrelated resources.

---

# Phase 16 — Build Manifest

For this phase, we create a build manifest to record the technical details of the final environment.

The manifest file is:

```
private/build-manifest.yml
```

The planned structure is:

```yaml
project:
  name: Operation Poisoned Pipeline

host:
  os: Ubuntu 24.04
  architecture: x86_64

docker:
  engine_version:
  compose_version:

images:
  nginx:
    tag:
    digest:

  ctfd:
    tag:
    digest:

  gitea:
    tag:
    digest:

  jenkins:
    tag:
    digest:

  postgres:
    tag:
    digest:

  application:
    digest:

baselines:
  git_bundle_sha256:
  s03_evidence_sha256:
  postgres_seed_sha256:

implementation_commit:
```

According to our design document, we need to record the following implementation details:

- Docker image tags
- Docker image digests
- Seed checksums
- Volume baseline checksums
- Configuration commit identifiers

We also need to avoid floating `latest` image tags after the final build is frozen.

This information is useful when verifying that the same environment can be recreated consistently.

---

# Phase 17 — Testing Order

After implementing the main environment, we need to test more than just whether all six flags can be obtained.

Our testing process covers individual stage functionality, challenge handoffs, security isolation, and reproducibility.

## Stage Testing

We use the following stage test requirements:

```sql
ST-01 S01 works from clean Kali
ST-02 S01 → S02 handoff works
ST-03 S03 has exactly one valid evidence chain
ST-04 S04 gets pipeline-app, not root
ST-05 S05 gives container root only
ST-06 S06 direct DB fails but tunnel succeeds
```

Each test verifies an important part of the challenge design.

For example, the S04 proof of concept must demonstrate command execution under the `pipeline-app` account.

It must not result in immediate root access.

Similarly, S05 must demonstrate root access inside the container only, while S06 must verify that the intended network pivot is required.

## Isolation Testing

We also need to check the Docker configuration and network isolation.

The main inspection commands are:

```
docker network inspect ...
docker inspect ...
ss -tulpn
docker compose config
```

The isolation tests should verify that the following actions fail:

```
Kali → PostgreSQL        FAIL
Internet from challenge  FAIL
Docker socket access     FAIL
Host filesystem access   FAIL
PostgreSQL writes        FAIL
```

At the same time, all intended challenge communication paths must work correctly.

Our security-control table requires us to verify network configuration, permissions, prohibited connectivity, external network access, secret exposure, and reset functionality.

We should record the results of these tests as implementation evidence.

---

# Phase 18 — Evidence Collection

For our assignment, evidence collection is an important part of the implementation process.

Instead of collecting everything at the end, we should save evidence throughout development.

For each significant implementation step, we record:

```bash
command
screenshot
configuration file
commit ID
test result
checksum
```

We organize the evidence using the following structure:

```perl
evidence/
├── screenshots/
│   ├── docker-version.png
│   ├── network-inspect.png
│   ├── s01-solve.png
│   ├── s02-permissions.png
│   ├── s04-pipeline-app.png
│   ├── s05-root.png
│   └── s06-tunnel.png
│
├── logs/
│   ├── isolation-tests.txt
│   ├── reset-test-01.txt
│   ├── reset-test-02.txt
│   └── reset-test-03.txt
│
└── test-results/
```

These files will help us demonstrate that our implementation meets the project requirements.

According to our design, we should not consider a test fully verified unless the required evidence exists.

This is particularly important for the individual stage tests, network isolation tests, and reset verification.

---

# What I Need to Complete First in VS Code

For the initial implementation, I decided not to start directly with the vulnerable Flask application.

The first milestone is to prepare a working development environment.

It includes:

```markdown
Ubuntu
   +
VS Code
   +
Git repository
   +
Docker Engine
   +
Docker Compose
   +
3 Docker networks
```

Once these components are working, we can move to the remaining development milestones.

## Milestone 2 — Application Container and PostgreSQL

```
Milestone 2
Application container + PostgreSQL
```

## Milestone 3 — Implement S04, S05, and S06

```
Milestone 3
S04 + S05 + S06
```

## Milestone 4 — Gitea and S01

```
Milestone 4
Gitea + S01
```

## Milestone 5 — Jenkins and S02

```
Milestone 5
Jenkins + S02
```

## Milestone 6 — S03 Evidence

```
Milestone 6
S03 evidence
```

## Milestone 7 — CTFd and Nginx

```
Milestone 7
CTFd + Nginx
```

## Milestone 8 — Kali Participant Environment

```
Milestone 8
Kali participant
```

## Milestone 9 — Full Challenge Integration

```
Milestone 9
Full S01 → S06 clean run
```

## Milestone 10 — Final Validation

```
Milestone 10
Reset + isolation + two independent tester validation
```

These milestones follow the deployment approach described in our project document.

The process starts with installing Docker, preparing the required images and networks, and deploying the control services.

After that, we set up the Application Challenge and PostgreSQL environment, configure the Kali participant container, and perform the required testing.

The final validation covers challenge dependencies, privilege boundaries, flag retrieval, network isolation, reset functionality, and reproducibility.

---

# Immediate Next Step

At this stage, I plan to complete the implementation one milestone at a time rather than trying to build the entire environment at once.

Our first implementation task is:

**PART 01 — Ubuntu + VS Code + Docker project setup → create the exact project folders → create the first `compose.yml` → create `player_net`, `control_net`, and `internal_net` → test the isolation.**

Once this part is completed and verified, we can continue with:

**PART 02 — Build the Application Challenge Docker container.**

For each part, we need to prepare the required files, identify their correct locations in VS Code, add the implementation code, execute the necessary terminal commands, and verify the expected results.

By following this process, we can implement our CTF environment in an organized manner while making sure that each component works correctly before moving to the next development stage.