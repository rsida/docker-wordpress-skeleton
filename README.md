# docker-wordpress-skeleton — Stack WordPress locale avec Docker

Stack de développement WordPress local basée sur Docker. Elle inclut WordPress, MariaDB, phpMyAdmin et Mailpit, accessibles via des domaines locaux en HTTPS sans spécifier de port. Le routage HTTPS est assuré par le reverse proxy Traefik fourni par le projet **[local-network-multisite](https://github.com/rsida/local-network-multisite)**, qui est une dépendance obligatoire.

## Sommaire

1. [Prérequis](#1-prérequis)
2. [Architecture](#2-architecture)
3. [De zéro à WordPress — installation complète](#3-de-zéro-à-wordpress--installation-complète)
   - [Étape 1 — Cloner et lancer local-network-multisite](#étape-1--cloner-et-lancer-local-network-multisite)
   - [Étape 2 — Cloner docker-wordpress-skeleton](#étape-2--cloner-wordpressbuilder)
   - [Étape 3 — Configurer l'environnement](#étape-3--configurer-lenvironnement)
   - [Étape 4 — Déclarer le domaine dans le fichier hosts](#étape-4--déclarer-le-domaine-dans-le-fichier-hosts)
   - [Étape 5 — Vérifier et lancer la stack](#étape-5--vérifier-et-lancer-la-stack)
   - [Étape 6 — Finaliser l'installation WordPress](#étape-6--finaliser-linstallation-wordpress)
4. [Variables d'environnement](#4-variables-denvironnement)
5. [Configurer les limites PHP](#5-configurer-les-limites-php)
6. [Lancer plusieurs sites en parallèle](#6-lancer-plusieurs-sites-en-parallèle)
7. [Services disponibles](#7-services-disponibles)
8. [Commandes Make](#8-commandes-make)
9. [Structure des fichiers](#9-structure-des-fichiers)
10. [Dépannage](#10-dépannage)

---

## 1. Prérequis

### Outils à installer

| Outil | Vérification | Installation |
|-------|-------------|--------------|
| Docker Desktop (Windows) ou Docker Engine | `docker --version` | [docs.docker.com](https://docs.docker.com/desktop/install/windows-install/) |
| Docker Compose v2 | `docker compose version` | Inclus dans Docker Desktop |
| make | `make --version` | `sudo apt install make` |

> Sous Windows avec WSL2, Docker Desktop doit avoir l'intégration WSL2 activée.
> Vérifier dans Docker Desktop -> Settings -> Resources -> WSL Integration.

### Dépendance obligatoire : local-network-multisite

Ce projet nécessite que **[local-network-multisite](https://github.com/rsida/local-network-multisite)** soit installé et en cours d'exécution. Ce projet distinct fournit :

- Le reverse proxy **Traefik** (ports 80 et 443)
- Le réseau Docker partagé `traefik-net`
- Les certificats TLS locaux (`*.local`) via mkcert

Sans `local-network-multisite` lancé, docker-wordpress-skeleton ne peut pas démarrer (le réseau `traefik-net` n'existe pas).

Chemin attendu : `~/project/local-network-multisite`

---

## 2. Architecture

```
                    +----------------------------------+
  Navigateur        |      local-network-multisite / Traefik       |  ports 80 / 443
  Windows  -------> |   route par nom de domaine       |  dashboard: https://traefik.local
                    +----------+----------+------------+
                               |          |
                    +----------v---+  +---v----------+
                    |  Site 1      |  |  Site 2       |
                    |  monsite.    |  |  autresite.   |
                    |  local       |  |  local        |
                    |  ----------  |  |  ----------   |
                    |  WordPress   |  |  WordPress    |
                    |  MariaDB     |  |  MariaDB      |
                    |  phpMyAdmin  |  |  phpMyAdmin   |
                    |  Mailpit     |  |  Mailpit      |
                    +--------------+  +---------------+
```

### Réseaux Docker

Chaque projet docker-wordpress-skeleton utilise deux réseaux Docker :

- **`traefik-net`** — réseau externe créé par local-network-multisite. WordPress, phpMyAdmin et Mailpit y sont connectés pour que Traefik puisse les atteindre et router le trafic HTTPS entrant.
- **`internal`** — réseau isolé propre au projet. Permet la communication entre WordPress, MariaDB, phpMyAdmin et Mailpit, sans les exposer à Traefik ni à l'hôte.

MariaDB est uniquement connectée au réseau `internal` : elle n'est pas accessible depuis l'extérieur. Aucun port n'est exposé directement sur l'hôte — tout le trafic passe par Traefik.

---

## 3. De zéro à WordPress — installation complète

### Étape 1 — Cloner et lancer local-network-multisite

Si ce n'est pas déjà fait, installer et démarrer local-network-multisite. C'est l'opération à faire **une seule fois** — local-network-multisite reste ensuite actif pour tous les projets.

```bash
git clone <url-local-network-multisite> ~/project/local-network-multisite
cd ~/project/local-network-multisite
cp .env.example .env

# Générer les certificats TLS locaux (nécessite mkcert)
make certs

# Démarrer Traefik
make up
```

> Pour que Chrome sur Windows fasse confiance aux certificats, le CA mkcert doit également être importé dans le magasin de certificats Windows. Voir [local-network-multisite README](../local-network-multisite README), section "WSL2 notes".

Vérifier que Traefik tourne :

```bash
make ps
```

Ouvrir [https://traefik.local](https://traefik.local) dans le navigateur pour confirmer.

---

### Étape 2 — Cloner docker-wordpress-skeleton

```bash
git clone https://github.com/rsida/docker-wordpress-skeleton ~/project/docker-wordpress-skeleton
cd ~/project/docker-wordpress-skeleton
```

Pour utiliser ce projet comme base pour un site nommé `monsite` :

```bash
cp -r ~/project/docker-wordpress-skeleton ~/project/monsite
cd ~/project/monsite
```

---

### Étape 3 — Configurer l'environnement

```bash
cp .env.example .env
```

Editer `.env` :

```dotenv
PROJECT_NAME=monsite          # Identifiant unique (lettres, chiffres, tirets)
SITE_DOMAIN=monsite.local     # Domaine local souhaité

TRAEFIK_NETWORK=traefik-net   # Doit correspondre à local-network-multisite/.env

DB_NAME=monsite_db
DB_USER=monsite_user
DB_PASSWORD=monsite_pass
DB_ROOT_PASSWORD=root

TABLE_PREFIX=wp_
WP_DEBUG=1
WP_MEMORY_LIMIT=256M
WP_MAX_MEMORY_LIMIT=256M
```

> `PROJECT_NAME` doit être **unique** parmi tous les projets lancés simultanément. Il sert à nommer les routeurs Traefik en interne — un doublon provoquerait un conflit de routage.

---

### Étape 4 — Déclarer le domaine dans le fichier hosts

Le navigateur (Chrome sur Windows) résout le DNS côté Windows. Le domaine local doit donc être déclaré dans le fichier `hosts` de Windows.

**Obtenir la ligne exacte à ajouter :**

```bash
make hosts
```

Cette commande affiche la ligne à copier, par exemple :

```
127.0.0.1 monsite.local pma.monsite.local mail.monsite.local
```

**Ajouter la ligne dans le fichier hosts :**

- **Windows (WSL2)** : ouvrir `C:\Windows\System32\drivers\etc\hosts` avec le Bloc-notes **en administrateur** et ajouter la ligne.
- **Linux / Mac natif** : `sudo nano /etc/hosts` et ajouter la ligne.

Vider le cache DNS Windows après modification :

```
ipconfig /flushdns
```

---

### Étape 5 — Vérifier et lancer la stack

```bash
# Vérifier que le réseau traefik-net existe (local-network-multisite doit tourner)
make check-network

# Lancer WordPress + MariaDB + phpMyAdmin + Mailpit
make start
```

Contrôler que tous les conteneurs sont en cours d'exécution :

```bash
make ps
```

Résultat attendu :

```
NAME                    SERVICE       STATUS     PORTS
monsite-wordpress-1     wordpress     running
monsite-mariadb-1       mariadb       running
monsite-phpmyadmin-1    phpmyadmin    running
monsite-mailpit-1       mailpit       running
```

> Aucun port n'est exposé directement sur l'hôte — Traefik gère tout le trafic entrant.

---

### Étape 6 — Finaliser l'installation WordPress

Ouvrir `https://monsite.local` dans le navigateur Windows.

L'assistant d'installation WordPress s'affiche. Renseigner :

- **Titre du site** : nom de votre choix
- **Identifiant** : admin (ou autre)
- **Mot de passe** : choisir un mot de passe
- **E-mail** : n'importe quelle adresse (les mails sont interceptés par Mailpit, rien ne sort)

Cliquer **Installer WordPress**.

Accéder ensuite à l'administration : `https://monsite.local/wp-admin`

---

## 4. Variables d'environnement

Toutes les variables sont définies dans `.env` (copié depuis `.env.example`).

| Variable | Défaut | Description |
|----------|--------|-------------|
| `PROJECT_NAME` | `monsite` | Identifiant unique du projet, utilisé pour nommer les routeurs Traefik. Doit être différent pour chaque site lancé simultanément. |
| `SITE_DOMAIN` | `monsite.local` | Domaine local du site. WordPress sera accessible sur `https://SITE_DOMAIN`. |
| `TRAEFIK_NETWORK` | `traefik-net` | Nom du réseau Docker partagé avec Traefik. Doit correspondre à `TRAEFIK_NETWORK` dans `local-network-multisite/.env`. |
| `DB_NAME` | `wordpress` | Nom de la base de données MariaDB. |
| `DB_USER` | `wpuser` | Utilisateur MariaDB pour WordPress. |
| `DB_PASSWORD` | `wppassword` | Mot de passe de l'utilisateur MariaDB. |
| `DB_ROOT_PASSWORD` | `root` | Mot de passe root MariaDB (utilisé par phpMyAdmin). |
| `TABLE_PREFIX` | `wp_` | Préfixe des tables WordPress. |
| `WP_DEBUG` | `1` | Active le mode debug WordPress (`1` = activé, `0` = désactivé). |
| `WP_MEMORY_LIMIT` | `256M` | Mémoire allouée aux requêtes front WordPress. Doit être <= `memory_limit` dans `docker/php/custom.ini`. |
| `WP_MAX_MEMORY_LIMIT` | `256M` | Mémoire allouée à l'administration WordPress. Doit être <= `memory_limit` dans `docker/php/custom.ini`. |

---

## 5. Configurer les limites PHP

Les limites PHP se configurent dans `docker/php/custom.ini`. Les valeurs actuelles par défaut :

```ini
upload_max_filesize = 2G      ; taille maximale d'un fichier uploadé
post_max_size       = 2G      ; doit être >= upload_max_filesize
memory_limit        = -1      ; mémoire par requête PHP (-1 = illimité)
max_execution_time  = 300     ; secondes
max_input_time      = 300     ; secondes
```

Après toute modification, redémarrer le conteneur WordPress :

```bash
docker compose restart wordpress

# Vérifier que les valeurs sont bien prises en compte
docker compose exec wordpress php -r "echo ini_get('upload_max_filesize');"
```

> **Règle mémoire :** `WP_MEMORY_LIMIT` <= `WP_MAX_MEMORY_LIMIT` <= `memory_limit` (PHP)

---

## 6. Lancer plusieurs sites en parallèle

Traefik tourne dans local-network-multisite et est partagé entre tous les projets. Un second site n'a pas besoin de relancer local-network-multisite.

```bash
cp -r ~/project/docker-wordpress-skeleton ~/project/autresite
cd ~/project/autresite
cp .env.example .env
```

Dans `.env` du second site, utiliser des valeurs uniques :

```dotenv
PROJECT_NAME=autresite
SITE_DOMAIN=autresite.local
TRAEFIK_NETWORK=traefik-net
DB_NAME=autresite_db
DB_USER=autresite_user
DB_PASSWORD=autresite_pass
DB_ROOT_PASSWORD=root
```

Ajouter le domaine dans le fichier `hosts` Windows :

```
127.0.0.1 autresite.local pma.autresite.local mail.autresite.local
```

Lancer :

```bash
make start
```

Les deux sites sont accessibles simultanément :

- `https://monsite.local`
- `https://autresite.local`

---

## 7. Services disponibles

Pour un site dont `SITE_DOMAIN=monsite.local` :

| URL | Service | Description |
|-----|---------|-------------|
| `https://monsite.local` | WordPress | Front du site + admin (`/wp-admin`) |
| `https://pma.monsite.local` | phpMyAdmin | Interface de gestion de la base de données |
| `https://mail.monsite.local` | Mailpit | Boite mail de développement — intercepte tous les envois WordPress |
| `https://traefik.local` | Traefik Dashboard | Vue des routeurs actifs (fourni par local-network-multisite) |

> Mailpit capture tous les e-mails envoyés par WordPress (réinitialisation de mot de passe, notifications WooCommerce, etc.). Aucun mail ne sort réellement vers l'extérieur.

---

## 8. Commandes Make

```bash
make help           # Liste toutes les commandes disponibles avec leur description
```

### Démarrage et arrêt

| Commande | Description |
|----------|-------------|
| `make start` | Démarre la stack WordPress (local-network-multisite doit tourner) |
| `make stop` | Arrête tous les conteneurs du projet |
| `make restart` | Arrête puis redémarre la stack |
| `make logs` | Affiche les logs en temps réel (Ctrl+C pour quitter) |
| `make ps` | Liste les conteneurs du projet et leur statut |

### WordPress et base de données

| Commande | Description |
|----------|-------------|
| `make wp-cli CMD="..."` | Exécute une commande WP-CLI dans le conteneur WordPress |
| `make wp-shell` | Ouvre un shell bash dans le conteneur WordPress |
| `make db-shell` | Ouvre un shell MariaDB en root |

### Utilitaires

| Commande | Description |
|----------|-------------|
| `make check-network` | Vérifie que le réseau `traefik-net` existe |
| `make hosts` | Affiche la ligne à ajouter dans le fichier hosts |

### Exemples WP-CLI

```bash
make wp-cli CMD="plugin list"
make wp-cli CMD="theme list"
make wp-cli CMD="user list"
make wp-cli CMD="cache flush"

# WP-CLI directement dans le conteneur
docker compose exec wordpress wp plugin install woocommerce --activate --allow-root
docker compose exec wordpress wp search-replace 'http://ancien-domaine.local' 'https://monsite.local' --allow-root
```

---

## 9. Structure des fichiers

```
docker-wordpress-skeleton/
├── compose.yaml               # Définition des services Docker
├── .env                       # Configuration du site (à créer depuis .env.example)
├── .env.example               # Modèle de configuration
├── Makefile                   # Commandes raccourcis
│
├── wp-content/                # Monté dans le conteneur WordPress
│   ├── themes/                # Thèmes (versionnables)
│   ├── plugins/               # Plugins (versionnables)
│   └── uploads/               # Médias uploadés (à exclure du git)
│
└── docker/
    └── php/
        └── custom.ini         # Configuration PHP (upload, mémoire, etc.)
```

**Recommandations `.gitignore` :**

```gitignore
.env
wp-content/uploads/
```

---

## 10. Dépannage

### Le réseau `traefik-net` est introuvable

```bash
make check-network
# Si erreur : démarrer local-network-multisite
cd ~/project/local-network-multisite && make up
```

### Le site affiche une erreur SSL / certificat non reconnu

Les certificats sont gérés par local-network-multisite. Vérifier :

1. Que `make certs` a été exécuté dans local-network-multisite
2. Que le CA mkcert a été importé dans le magasin de certificats Windows (`certmgr.msc` -> Trusted Root Certification Authorities)
3. Que Chrome a été redémarré après l'import
4. Que local-network-multisite tourne : `cd ~/project/local-network-multisite && make ps`

### Le domaine ne se résout pas (`ERR_NAME_NOT_RESOLVED`)

- Vérifier le fichier `hosts` Windows : la ligne doit pointer vers `127.0.0.1`
- Vider le cache DNS Windows : `ipconfig /flushdns` dans PowerShell
- S'assurer que le navigateur ne passe pas par un proxy

### Erreur "port 80 already in use"

Un autre service occupe le port 80 ou 443. Vérifier qu'aucun autre Traefik ou serveur web ne tourne en parallèle :

```bash
sudo lsof -i :80
sudo lsof -i :443
```

### WordPress redirige en boucle ou affiche "Too many redirects"

`WP_SITEURL` / `WP_HOME` est mal configuré. Vérifier dans `.env` que `SITE_DOMAIN` correspond exactement au domaine déclaré dans le fichier `hosts`.

En dernier recours, corriger via phpMyAdmin dans la table `wp_options`, champs `siteurl` et `home`.

### Les mails ne s'affichent pas dans Mailpit

WordPress utilise par défaut la fonction PHP `mail()`. Pour que Mailpit intercepte les mails, un plugin SMTP est nécessaire :

1. Installer **WP Mail SMTP** ou **FluentSMTP** via l'administration WordPress
2. Configurer : hôte `mailpit`, port `1025`, sans authentification

### Le dashboard Traefik est vide (aucun routeur affiché)

Le conteneur WordPress n'a pas encore démarré ou ses labels n'ont pas été lus.

```bash
make logs   # Vérifier qu'il n'y a pas d'erreur au démarrage
cd ~/project/local-network-multisite && docker compose restart traefik
```

### Deux projets ont le même `PROJECT_NAME`

Si deux projets partagent le même `PROJECT_NAME`, leurs routeurs Traefik entrent en conflit et l'un des deux sites devient inaccessible. Chaque projet doit avoir une valeur `PROJECT_NAME` unique dans son `.env`.
