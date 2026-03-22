# docker-wordpress-skeleton — Local WordPress stack with Docker

A local WordPress development stack based on Docker. It includes WordPress, MariaDB, phpMyAdmin and Mailpit, accessible via local HTTPS domains without specifying a port. HTTPS routing is handled by the Traefik reverse proxy provided by the **[local-network-multisite](https://github.com/rsida/local-network-multisite)** project, which is a mandatory dependency.

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Architecture](#2-architecture)
3. [From zero to WordPress — full installation](#3-from-zero-to-wordpress--full-installation)
   - [Step 1 — Clone and start local-network-multisite](#step-1--clone-and-start-local-network-multisite)
   - [Step 2 — Clone docker-wordpress-skeleton](#step-2--clone-docker-wordpress-skeleton)
   - [Step 3 — Configure the environment](#step-3--configure-the-environment)
   - [Step 4 — Declare the domain in the hosts file](#step-4--declare-the-domain-in-the-hosts-file)
   - [Step 5 — Verify and start the stack](#step-5--verify-and-start-the-stack)
   - [Step 6 — Complete the WordPress installation](#step-6--complete-the-wordpress-installation)
4. [Environment variables](#4-environment-variables)
5. [Configuring PHP limits](#5-configuring-php-limits)
6. [Running multiple sites in parallel](#6-running-multiple-sites-in-parallel)
7. [Available services](#7-available-services)
8. [Make commands](#8-make-commands)
9. [File structure](#9-file-structure)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Prerequisites

### Required tools

| Tool | Check | Install |
|------|-------|---------|
| Docker Desktop (Windows) or Docker Engine | `docker --version` | [docs.docker.com](https://docs.docker.com/desktop/install/windows-install/) |
| Docker Compose v2 | `docker compose version` | Included in Docker Desktop |
| make | `make --version` | `sudo apt install make` |

> On Windows with WSL2, Docker Desktop must have WSL2 integration enabled.
> Check in Docker Desktop → Settings → Resources → WSL Integration.

### Mandatory dependency: local-network-multisite

This project requires **[local-network-multisite](https://github.com/rsida/local-network-multisite)** to be installed and running. That separate project provides:

- The **Traefik** reverse proxy (ports 80 and 443)
- The shared Docker network `traefik-net`
- Local TLS certificates (`*.local`) via mkcert

Without `local-network-multisite` running, docker-wordpress-skeleton cannot start (the `traefik-net` network does not exist).

Expected path: `~/project/local-network-multisite`

---

## 2. Architecture

```
                    +----------------------------------+
  Browser           |   local-network-multisite / Traefik  |  ports 80 / 443
  Windows  -------> |   routes by domain name          |  dashboard: https://traefik.local
                    +----------+----------+------------+
                               |          |
                    +----------v---+  +---v----------+
                    |  Site 1      |  |  Site 2       |
                    |  mysite.     |  |  othersite.   |
                    |  local       |  |  local        |
                    |  ----------  |  |  ----------   |
                    |  WordPress   |  |  WordPress    |
                    |  MariaDB     |  |  MariaDB      |
                    |  phpMyAdmin  |  |  phpMyAdmin   |
                    |  Mailpit     |  |  Mailpit      |
                    +--------------+  +---------------+
```

### Docker networks

Each docker-wordpress-skeleton project uses two Docker networks:

- **`traefik-net`** — external network created by local-network-multisite. WordPress, phpMyAdmin and Mailpit are connected to it so Traefik can reach them and route incoming HTTPS traffic.
- **`internal`** — project-specific isolated network. Allows communication between WordPress, MariaDB, phpMyAdmin and Mailpit, without exposing them to Traefik or the host.

MariaDB is connected only to the `internal` network: it is not accessible from outside. No ports are exposed directly on the host — all traffic goes through Traefik.

---

## 3. From zero to WordPress — full installation

### Step 1 — Clone and start local-network-multisite

If not already done, install and start local-network-multisite. This is a **one-time** operation — local-network-multisite then stays active for all projects.

```bash
git clone <local-network-multisite-url> ~/project/local-network-multisite
cd ~/project/local-network-multisite
cp .env.example .env

# Generate local TLS certificates (requires mkcert)
make certs

# Start Traefik
make up
```

> For Chrome on Windows to trust the certificates, the mkcert CA must also be imported into the Windows certificate store. See the [local-network-multisite README](../local-network-multisite/README.md), section "WSL2 notes".

Verify that Traefik is running:

```bash
make ps
```

Open [https://traefik.local](https://traefik.local) in the browser to confirm.

---

### Step 2 — Clone docker-wordpress-skeleton

```bash
git clone https://github.com/rsida/docker-wordpress-skeleton ~/project/docker-wordpress-skeleton
cd ~/project/docker-wordpress-skeleton
```

To use this project as a base for a site named `mysite`:

```bash
cp -r ~/project/docker-wordpress-skeleton ~/project/mysite
cd ~/project/mysite
```

---

### Step 3 — Configure the environment

```bash
cp .env.example .env
```

Edit `.env`:

```dotenv
PROJECT_NAME=mysite           # Unique identifier (letters, digits, hyphens)
SITE_DOMAIN=mysite.local      # Desired local domain

TRAEFIK_NETWORK=traefik-net   # Must match local-network-multisite/.env

DB_NAME=mysite_db
DB_USER=mysite_user
DB_PASSWORD=mysite_pass
DB_ROOT_PASSWORD=root

TABLE_PREFIX=wp_
WP_DEBUG=1
WP_MEMORY_LIMIT=256M
WP_MAX_MEMORY_LIMIT=256M
```

> `PROJECT_NAME` must be **unique** across all simultaneously running projects. It is used to name Traefik routers internally — a duplicate would cause a routing conflict.

---

### Step 4 — Declare the domain in the hosts file

The browser (Chrome on Windows) resolves DNS on the Windows side. The local domain must therefore be declared in the Windows `hosts` file.

**Get the exact line to add:**

```bash
make hosts
```

This command displays the line to copy, for example:

```
127.0.0.1 mysite.local pma.mysite.local mail.mysite.local
```

**Add the line to the hosts file:**

- **Windows (WSL2)**: open `C:\Windows\System32\drivers\etc\hosts` with Notepad **as Administrator** and add the line.
- **Native Linux / Mac**: `sudo nano /etc/hosts` and add the line.

Flush the Windows DNS cache after editing:

```
ipconfig /flushdns
```

---

### Step 5 — Verify and start the stack

```bash
# Verify that the traefik-net network exists (local-network-multisite must be running)
make check-network

# Start WordPress + MariaDB + phpMyAdmin + Mailpit
make start
```

Check that all containers are running:

```bash
make ps
```

Expected output:

```
NAME                    SERVICE       STATUS     PORTS
mysite-wordpress-1      wordpress     running
mysite-mariadb-1        mariadb       running
mysite-phpmyadmin-1     phpmyadmin    running
mysite-mailpit-1        mailpit       running
```

> No ports are exposed directly on the host — Traefik handles all incoming traffic.

---

### Step 6 — Complete the WordPress installation

Open `https://mysite.local` in the Windows browser.

The WordPress installation wizard appears. Fill in:

- **Site title**: name of your choice
- **Username**: admin (or other)
- **Password**: choose a password
- **Email**: any address (emails are intercepted by Mailpit, nothing is sent out)

Click **Install WordPress**.

Then access the administration: `https://mysite.local/wp-admin`

---

## 4. Environment variables

All variables are defined in `.env` (copied from `.env.example`).

| Variable | Default | Description |
|----------|---------|-------------|
| `PROJECT_NAME` | `mysite` | Unique project identifier, used to name Traefik routers. Must be different for each simultaneously running site. |
| `SITE_DOMAIN` | `mysite.local` | Local site domain. WordPress will be accessible at `https://SITE_DOMAIN`. |
| `TRAEFIK_NETWORK` | `traefik-net` | Name of the Docker network shared with Traefik. Must match `TRAEFIK_NETWORK` in `local-network-multisite/.env`. |
| `DB_NAME` | `wordpress` | MariaDB database name. |
| `DB_USER` | `wpuser` | MariaDB user for WordPress. |
| `DB_PASSWORD` | `wppassword` | MariaDB user password. |
| `DB_ROOT_PASSWORD` | `root` | MariaDB root password (used by phpMyAdmin). |
| `TABLE_PREFIX` | `wp_` | WordPress table prefix. |
| `WP_DEBUG` | `1` | Enable WordPress debug mode (`1` = enabled, `0` = disabled). |
| `WP_MEMORY_LIMIT` | `256M` | Memory allocated to WordPress front-end requests. Must be <= `memory_limit` in `docker/php/custom.ini`. |
| `WP_MAX_MEMORY_LIMIT` | `256M` | Memory allocated to the WordPress admin. Must be <= `memory_limit` in `docker/php/custom.ini`. |

---

## 5. Configuring PHP limits

PHP limits are configured in `docker/php/custom.ini`. Current default values:

```ini
upload_max_filesize = 2G      ; maximum size of an uploaded file
post_max_size       = 2G      ; must be >= upload_max_filesize
memory_limit        = -1      ; memory per PHP request (-1 = unlimited)
max_execution_time  = 300     ; seconds
max_input_time      = 300     ; seconds
```

After any change, restart the WordPress container:

```bash
docker compose restart wordpress

# Verify that the values are applied
docker compose exec wordpress php -r "echo ini_get('upload_max_filesize');"
```

> **Memory rule:** `WP_MEMORY_LIMIT` <= `WP_MAX_MEMORY_LIMIT` <= `memory_limit` (PHP)

---

## 6. Running multiple sites in parallel

Traefik runs in local-network-multisite and is shared between all projects. A second site does not need to restart local-network-multisite.

```bash
cp -r ~/project/docker-wordpress-skeleton ~/project/othersite
cd ~/project/othersite
cp .env.example .env
```

In the second site's `.env`, use unique values:

```dotenv
PROJECT_NAME=othersite
SITE_DOMAIN=othersite.local
TRAEFIK_NETWORK=traefik-net
DB_NAME=othersite_db
DB_USER=othersite_user
DB_PASSWORD=othersite_pass
DB_ROOT_PASSWORD=root
```

Add the domain to the Windows `hosts` file:

```
127.0.0.1 othersite.local pma.othersite.local mail.othersite.local
```

Start:

```bash
make start
```

Both sites are accessible simultaneously:

- `https://mysite.local`
- `https://othersite.local`

---

## 7. Available services

For a site with `SITE_DOMAIN=mysite.local`:

| URL | Service | Description |
|-----|---------|-------------|
| `https://mysite.local` | WordPress | Site front-end + admin (`/wp-admin`) |
| `https://pma.mysite.local` | phpMyAdmin | Database management interface |
| `https://mail.mysite.local` | Mailpit | Development mailbox — intercepts all WordPress outgoing mail |
| `https://traefik.local` | Traefik Dashboard | Active routers view (provided by local-network-multisite) |

> Mailpit captures all emails sent by WordPress (password reset, WooCommerce notifications, etc.). No email is actually sent to the outside.

---

## 8. Make commands

```bash
make help           # List all available commands with their description
```

### Start and stop

| Command | Description |
|---------|-------------|
| `make start` | Start the WordPress stack (local-network-multisite must be running) |
| `make stop` | Stop all project containers |
| `make restart` | Stop then restart the stack |
| `make logs` | Display real-time logs (Ctrl+C to quit) |
| `make ps` | List project containers and their status |

### WordPress and database

| Command | Description |
|---------|-------------|
| `make wp-cli CMD="..."` | Run a WP-CLI command in the WordPress container |
| `make wp-shell` | Open a bash shell in the WordPress container |
| `make db-shell` | Open a MariaDB shell as root |

### Utilities

| Command | Description |
|---------|-------------|
| `make check-network` | Verify that the `traefik-net` network exists |
| `make hosts` | Display the line to add to the hosts file |

### WP-CLI examples

```bash
make wp-cli CMD="plugin list"
make wp-cli CMD="theme list"
make wp-cli CMD="user list"
make wp-cli CMD="cache flush"

# WP-CLI directly in the container
docker compose exec wordpress wp plugin install woocommerce --activate --allow-root
docker compose exec wordpress wp search-replace 'http://old-domain.local' 'https://mysite.local' --allow-root
```

---

## 9. File structure

```
docker-wordpress-skeleton/
├── compose.yaml               # Docker service definitions
├── .env                       # Site configuration (to create from .env.example)
├── .env.example               # Configuration template
├── Makefile                   # Shortcut commands
│
├── wp-content/                # Mounted into the WordPress container
│   ├── themes/                # Themes (versionable)
│   ├── plugins/               # Plugins (versionable)
│   └── uploads/               # Uploaded media (exclude from git)
│
└── docker/
    └── php/
        └── custom.ini         # PHP configuration (upload, memory, etc.)
```

**Recommended `.gitignore`:**

```gitignore
.env
wp-content/uploads/
```

---

## 10. Troubleshooting

### The `traefik-net` network is not found

```bash
make check-network
# If error: start local-network-multisite
cd ~/project/local-network-multisite && make up
```

### The site shows an SSL error / untrusted certificate

Certificates are managed by local-network-multisite. Check:

1. That `make certs` has been run in local-network-multisite
2. That the mkcert CA has been imported into the Windows certificate store (`certmgr.msc` → Trusted Root Certification Authorities)
3. That Chrome has been restarted after the import
4. That local-network-multisite is running: `cd ~/project/local-network-multisite && make ps`

### The domain does not resolve (`ERR_NAME_NOT_RESOLVED`)

- Check the Windows `hosts` file: the line must point to `127.0.0.1`
- Flush the Windows DNS cache: `ipconfig /flushdns` in PowerShell
- Make sure the browser is not going through a proxy

### Error "port 80 already in use"

Another service is using port 80 or 443. Check that no other Traefik or web server is running in parallel:

```bash
sudo lsof -i :80
sudo lsof -i :443
```

### WordPress redirects in a loop or shows "Too many redirects"

`WP_SITEURL` / `WP_HOME` is misconfigured. Check in `.env` that `SITE_DOMAIN` exactly matches the domain declared in the `hosts` file.

As a last resort, correct it via phpMyAdmin in the `wp_options` table, fields `siteurl` and `home`.

### Emails are not displayed in Mailpit

WordPress uses the PHP `mail()` function by default. For Mailpit to intercept emails, an SMTP plugin is required:

1. Install **WP Mail SMTP** or **FluentSMTP** via the WordPress admin
2. Configure: host `mailpit`, port `1025`, no authentication

### The Traefik dashboard is empty (no routers displayed)

The WordPress container has not yet started or its labels have not been read.

```bash
make logs   # Check for startup errors
cd ~/project/local-network-multisite && docker compose restart traefik
```

### Two projects have the same `PROJECT_NAME`

If two projects share the same `PROJECT_NAME`, their Traefik routers conflict and one of the sites becomes inaccessible. Each project must have a unique `PROJECT_NAME` value in its `.env`.
