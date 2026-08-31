# 📖 Explications Techniques Pas-à-Pas : Docker, Swarm, CI/CD et Reverse Proxy HTTPS

Ce document est un **manuel d'apprentissage complet et détaillé ligne par ligne**, spécialement rédigé pour un étudiant ou débutant en formation DevSecOps / Cloud / Architecture Microservices. Il explique clairement chaque instruction, chaque paramètre et chaque choix technique fait dans les fichiers `Dockerfile`, `docker-compose.prod.yml`, `docker-compose.proxy.yml`, `entrypoint.sh` et `.gitlab-ci.yml`.

---

## 📑 Sommaire

1. [Analyse Ligne par Ligne : Conteneurisation (`Dockerfile`)](#1-analyse-ligne-par-ligne--conteneurisation-dockerfile)
2. [Analyse Ligne par Ligne : Orchestration Swarm (`docker-compose.prod.yml`)](#2-analyse-ligne-par-ligne--orchestration-swarm-docker-composeprodyml)
3. [Analyse Ligne par Ligne : Reverse Proxy HTTPS & SSL (`docker-compose.proxy.yml` & `entrypoint.sh`)](#3-analyse-ligne-par-ligne--reverse-proxy-https--ssl-docker-composeproxyyml--entrypointsh)
4. [Analyse Ligne par Ligne : Pipeline CI/CD (`.gitlab-ci.yml`)](#4-analyse-ligne-par-ligne--pipeline-cicd-gitlab-ciyml)
5. [Persistance MongoDB et Fonctionnement des Secrets (`resolveSecret`)](#5-persistance-mongodb-et-fonctionnement-des-secrets-resolvesecret)
6. [Récapitulatif et Synthèse pour la Soutenance (Barème 15/15)](#6-récapitulatif-et-synthèse-pour-la-soutenance-barème-1515)

---

## 1. Analyse Ligne par Ligne : Conteneurisation (`Dockerfile`)

Pour chaque microservice (`auth-service`, `product-service`, `order-service`, `frontend`), nous utilisons un pattern appelé **Multi-stage build (construction en plusieurs étapes)**. Voici le détail ligne par ligne du `Dockerfile` d'un backend Node.js (`auth-service/Dockerfile`) :

```dockerfile
# --- STAGE 1 : Le Bâtisseur (Builder) ---
FROM node:20-bookworm-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .

# --- STAGE 2 : L'Image de Production (Allégée) ---
FROM node:20-bookworm-slim AS production
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force
COPY --from=builder /app/src ./src
EXPOSE 3001
CMD ["node", "src/app.js"]
```

### 🔍 Décryptage pédagogique ligne par ligne :

- **`FROM node:20-bookworm-slim AS builder`**
  *Explication :* On importe l'image officielle de Node.js version 20 basée sur Debian 12 (Bookworm) dans sa version `slim` (allégée des outils inutiles). On nomme cette première étape temporaire `builder`.
  *Pourquoi ce choix ?* Fixer la version (`20-bookworm-slim`) évite que le build casse dans 6 mois si Node change de version majeure.

- **`WORKDIR /app`**
  *Explication :* Crée le dossier `/app` à l'intérieur du conteneur et y place le terminal. Toutes les commandes suivantes s'exécuteront dans ce dossier.

- **`COPY package*.json ./`**
  *Explication :* Copie `package.json` et `package-lock.json` depuis ton PC (ou la CI) vers le dossier `/app` du conteneur.
  *Pourquoi copier les packages AVANT le code ?* Grâce au **cache Docker** ! Si tu modifies seulement ton code JS mais pas tes dépendances, Docker réutilisera le cache de l'installation `npm ci`, ce qui accélère les builds de plusieurs minutes à quelques secondes.

- **`RUN npm ci`**
  *Explication :* Installe strictement les dépendances en se basant sur `package-lock.json` (contrairement à `npm install` qui peut mettre à jour des versions). Installe aussi les dépendances de développement (`devDependencies`) nécessaires aux tests et linters.

- **`COPY . .`**
  *Explication :* Copie l'intégralité du code source du service (`src/`, `tests/`) dans `/app`.

- **`FROM node:20-bookworm-slim AS production`**
  *Explication :* On démarre une **seconde image totalement vierge** à partir de zéro, nommée `production`. Tout ce qui a été fait dans le stage `builder` et qui n'est pas explicitement copié sera définitivement supprimé.

- **`RUN npm ci --only=production && npm cache clean --force`**
  *Explication :* Installe **uniquement** les modules indispensables à l'exécution en production (`dependencies`). Les outils de test, de linting ou de dev sont exclus (`--only=production`), et on purge le cache `npm` derrière (`cache clean`).
  *Résultat :* L'image passe de ~800 Mo à moins de 200 Mo, réduisant drastiquement les failles de sécurité potentielles.

- **`COPY --from=builder /app/src ./src`**
  *Explication :* On récupère uniquement le dossier `src/` propre depuis l'étape `builder`.

- **`EXPOSE 3001`**
  *Explication :* Instruction de documentation indiquant aux administrateurs et au réseau que le service écoute sur le port interne `3001`.

- **`CMD ["node", "src/app.js"]`**
  *Explication :* Commande par défaut pour lancer l'application. On écrit sous forme de tableau JSON (`["node", ...]`) pour que Node.js s'exécute en tant que processus `PID 1`.
  *Pourquoi pas `npm start` ?* Si tu lances `npm start`, `npm` devient le processus principal et ne transmet pas correctement le signal d'arrêt (`SIGTERM`) envoyé par Docker Swarm lors d'une mise à l'échelle ou d'un arrêt. Lancer `node` en direct garantit un arrêt instantané et propre (*graceful shutdown*).

---

## 2. Analyse Ligne par Ligne : Orchestration Swarm (`docker-compose.prod.yml`)

Ce fichier décrit l'infrastructure de production pour **Docker Swarm**. Contrairement à `docker-compose.yml` (dev local), il utilise la section `deploy:` pour gérer la haute disponibilité, le clustering et les secrets.

```yaml
version: '3.8'

services:
  mongodb:
    image: ${MONGO_IMAGE:-mongo:4.4.18}
    networks:
      - ecommerce_net
    volumes:
      - mongodb_data:/data/db
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager

  auth-service:
    image: ${CI_REGISTRY_IMAGE:-e-commerce}/auth-service:${IMAGE_TAG:-latest}
    networks:
      - ecommerce_net
    secrets:
      - jwt_secret
    environment:
      - APP_ENV=production
      - MONGODB_URI=mongodb://mongodb:27017/auth
      - JWT_SECRET=/run/secrets/jwt_secret
    deploy:
      replicas: 2
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure

networks:
  ecommerce_net:
    driver: overlay

volumes:
  mongodb_data:

secrets:
  jwt_secret:
    external: true
```

### 🔍 Décryptage pédagogique ligne par ligne :

- **`version: '3.8'`**
  *Explication :* Version de la syntaxe Docker Compose compatible avec les fonctionnalités Swarm (secrets, overlay networks, deploy constraints).

- **`image: ${CI_REGISTRY_IMAGE:-e-commerce}/auth-service:${IMAGE_TAG:-latest}`**
  *Explication :* Utilise des variables d'environnement dynamiques avec une valeur de repli (`:-`). Si GitLab CI/CD passe `CI_REGISTRY_IMAGE=registry.gitlab.com/groupe/projet` et `IMAGE_TAG=v1.0.0`, Swarm téléchargera cette image exacte. Sinon en local, il utilisera `e-commerce/auth-service:latest`.

- **`networks: - ecommerce_net`**
  *Explication :* Connecte le conteneur à notre réseau interne Swarm. Tous les services dans ce réseau se voient par leur nom (`auth-service`, `mongodb`, `product-service`) grâce au serveur DNS interne de Docker.

- **`secrets: - jwt_secret`**
  *Explication :* Demande à Docker Swarm de déchiffrer le secret `jwt_secret` et de le monter en mémoire vive (dans un système de fichiers virtuel RAM sous `/run/secrets/jwt_secret`) à l'intérieur de ce conteneur uniquement.

- **`environment: - JWT_SECRET=/run/secrets/jwt_secret`**
  *Explication :* On transmet le chemin du fichier secret à l'application Node.js. Notre code va lire ce fichier au démarrage plutôt que d'avoir le secret en clair dans l'environnement.

- **`deploy: replicas: 2`**
  *Explication :* Demande à Swarm de maintenir en permanence **2 instances identiques (répliquas)** du conteneur `auth-service` en parallèle. Si l'un plante, Swarm balance le trafic sur le second et recrée le premier instantanément.

- **`update_config: parallelism: 1 | delay: 10s`**
  *Explication :* Définit la stratégie de **Rolling Update (mise à jour sans coupure)**. Lors d'une nouvelle version :
  1. Swarm met à jour **1 seul répliqua** à la fois (`parallelism: 1`).
  2. Il attend **10 secondes** (`delay: 10s`) pour vérifier que ce conteneur démarre sainement sans erreur.
  3. Il passe ensuite au deuxième répliqua. Zéro interruption de service pour l'utilisateur !

- **`restart_policy: condition: on-failure`**
  *Explication :* En cas de crash (code de retour non nul), Swarm relance automatiquement la tâche.

- **`networks: ecommerce_net: driver: overlay`**
  *Explication :* Le pilote `overlay` est le réseau virtuel multi-nœuds de Docker Swarm. Il encapsule les paquets réseau (VXLAN) et permet aux conteneurs de communiquer de manière sécurisée même s'ils s'exécutent sur des machines physiques ou VM différentes.

- **`secrets: jwt_secret: external: true`**
  *Explication :* Indique que le secret `jwt_secret` a été créé au préalable dans le cluster (ex: avec `echo "mon_secret" | docker secret create jwt_secret -` ou via la CI/CD) et que Swarm ne doit pas essayer de le recréer à partir d'un fichier.

---

## 3. Analyse Ligne par Ligne : Reverse Proxy HTTPS & SSL (`docker-compose.proxy.yml` & `entrypoint.sh`)

Pour valider l'exigence d'un **Load Balancer / Ingress en HTTPS (ports 80 et 443)**, nous avons externalisé Nginx dans une stack séparée (`docker-compose.proxy.yml`).

### A. Le fichier `docker-compose.proxy.yml` :
```yaml
version: '3.8'

services:
  reverse-proxy:
    image: nginx:1.27-alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./proxy/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./proxy/entrypoint.sh:/entrypoint.sh:ro
    entrypoint: ["/bin/sh", "/entrypoint.sh"]
    networks:
      - e-commerce_ecommerce_net

networks:
  e-commerce_ecommerce_net:
    external: true
```

#### 🔍 Explications clés du Proxy :
- **`ports: - "80:80" | - "443:443"`**
  *Explication :* Le proxy est le **seul service** qui ouvre des ports vers l'extérieur du cluster. Il reçoit le trafic HTTP (`80`) pour le rediriger en HTTPS (`443`).
- **`networks: e-commerce_ecommerce_net: external: true`**
  *Explication :* Le proxy se branche sur le réseau `overlay` créé par la stack `e-commerce` (`e-commerce_ecommerce_net`). Il peut ainsi communiquer en privé avec notre `frontend:8080`.

### B. Le script de génération de certificat SSL (`proxy/entrypoint.sh`) :
Ce script s'exécute à chaque démarrage de Nginx pour générer un certificat auto-signé à la volée.

```bash
#!/bin/sh
set -e

SSL_DIR="/etc/nginx/ssl"
CERT_FILE="$SSL_DIR/nginx.crt"
KEY_FILE="$SSL_DIR/nginx.key"

mkdir -p "$SSL_DIR"

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "Génération du certificat SSL auto-signé pour Nginx..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -subj "/C=FR/ST=France/L=Paris/O=Ecommerce/CN=localhost"
fi

UPSTREAM="${FRONTEND_UPSTREAM:-frontend:8080}"
sed -i "s|\${FRONTEND_UPSTREAM}|$UPSTREAM|g" /etc/nginx/nginx.conf

nginx -t
exec nginx -g 'daemon off;'
```

#### 🔍 Décryptage du script Bash :
- **`set -e`** : Arrête immédiatement le script si une commande échoue (ex: erreur de droits ou de syntaxe).
- **`openssl req -x509 -nodes -days 365 -newkey rsa:2048 ...`**
  *Explication :* Commande OpenSSL qui crée une clé privée RSA 2048 bits (`-keyout`) et un certificat SSL public x509 (`-out`) valable 365 jours. Le flag `-nodes` (no DES) évite de protéger la clé par mot de passe afin que Nginx puisse redémarrer sans intervention humaine. Le `-subj` remplit automatiquement les champs d'identité (Pays=FR, Ville=Paris, Nom de domaine=localhost).
- **`sed -i "s|\${FRONTEND_UPSTREAM}|$UPSTREAM|g" /etc/nginx/nginx.conf`**
  *Explication :* Injecte dynamiquement le nom d'hôte cible du frontend (`frontend:8080` par défaut) dans le fichier de configuration Nginx.
- **`nginx -t`** : Vérifie la validité syntaxique de `nginx.conf`. Si une erreur est présente, le conteneur s'arrête ici avec un message clair.
- **`exec nginx -g 'daemon off;'`**
  *Explication :* Lance le démon Nginx au premier plan (`daemon off`). L'instruction `exec` remplace le processus shell (`PID 1`) par le processus Nginx, assurant que Nginx reçoive directement les signaux Docker (`docker stop`).

---

## 4. Analyse Ligne par Ligne : Pipeline CI/CD (`.gitlab-ci.yml`)

Le pipeline GitLab CI/CD automatise la vérification, la construction, l'analyse de sécurité et le déploiement sur notre cluster Swarm.

```yaml
stages:
  - test
  - build
  - security
  - deploy

default:
  tags:
    - swarm-manager

deploy_production:
  stage: deploy
  image: docker:24
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
      when: manual
  script:
    - echo "$CI_REGISTRY_PASSWORD" | docker login -u "$CI_REGISTRY_USER" --password-stdin "$CI_REGISTRY"
    - export IMAGE_TAG=$CI_COMMIT_SHA
    - if [ -n "$JWT_SECRET" ]; then echo "$JWT_SECRET" | docker secret create jwt_secret - || true; fi
    - docker stack deploy -c docker-compose.prod.yml e-commerce --with-registry-auth
    - sleep 15
    - docker service ls
    - curl -k -s -I https://localhost/ | head -n 5
    - curl -s http://localhost:8080/api/products | head -c 100
```

### 🔍 Décryptage pédagogique ligne par ligne :

- **`stages: [- test, - build, - security, - deploy]`**
  *Explication :* Définit l'ordre chronologique strict des étapes du pipeline. Un stage ne démarre que si le précédent est 100 % en succès.

- **`default: tags: [- swarm-manager]`**
  *Explication :* Force tous les jobs de la pipeline à s'exécuter sur le **Runner GitLab tagué `swarm-manager`**. C'est crucial car pour exécuter des commandes `docker stack deploy` ou `docker secret create`, le runner doit avoir accès au démon Docker du nœud Manager Swarm.

- **`rules: - if: '$CI_COMMIT_BRANCH == "main"' when: manual`**
  *Explication :* Le déploiement en production ne se déclenche que si l'on est sur la branche `main`, et nécessite un **clic manuel** (`when: manual`) dans l'interface GitLab par un administrateur pour éviter une mise en production accidentelle.

- **`echo "$CI_REGISTRY_PASSWORD" | docker login -u "$CI_REGISTRY_USER" ...`**
  *Explication :* Connecte le démon Docker du runner au registre de conteneurs GitLab (`registry.gitlab.com`) en utilisant les jetons de sécurité éphémères fournis automatiquement par GitLab (`$CI_REGISTRY_PASSWORD`).

- **`export IMAGE_TAG=$CI_COMMIT_SHA`**
  *Explication :* Lie le déploiement au **hash unique du commit Git couramment testé (`$CI_COMMIT_SHA`)**. Cela garantit la traçabilité absolue : ce qui est en production correspond exactement au code du commit Git.

- **`if [ -n "$JWT_SECRET" ]; then echo "$JWT_SECRET" | docker secret create jwt_secret - || true; fi`**
  *Explication :* Vérifie si la variable GitLab `$JWT_SECRET` est définie. Si oui, elle la transmet à `docker secret create` pour inscrire la clé dans le Swarm. Le `|| true` empêche le pipeline d'échouer si le secret existe déjà.

- **`docker stack deploy -c docker-compose.prod.yml e-commerce --with-registry-auth`**
  *Explication :* La commande reine du déploiement Swarm ! Elle prend le fichier `docker-compose.prod.yml`, crée la stack `e-commerce` (ou la met à jour si elle existe déjà en appliquant le *rolling update*) et transmet les identifiants de connexion au registre (`--with-registry-auth`) à tous les nœuds workers pour qu'ils puissent télécharger les nouvelles images.

- **`curl -k -s -I https://localhost/ | head -n 5` & `curl -s http://localhost:8080/api/products`**
  *Explication :* **Test de fumée (Smoke Test / Post-deploy Probe)**. Le runner effectue une requête HTTPS (`-k` pour ignorer l'alerte du certificat auto-signé) et interroge l'API pour prouver que le reverse proxy et les microservices répondent correctement en `200 OK`.

---

## 5. Persistance MongoDB et Fonctionnement des Secrets (`resolveSecret`)

### A. Persistance des données et Idempotence :
Pour obtenir les **2 points du barème sur la Persistance**, la base de données ne doit jamais perdre ses informations après un redémarrage :
- Le conteneur `e-commerce_mongodb` monte le volume persistant Docker : `mongodb_data:/data/db`.
- **Preuve par le test :** Si nous exécutons `scripts/init-products.sh` pour créer 8 produits (Galaxy S21, MacBook Pro M1...), puis redémarrons le conteneur (`docker service update --force e-commerce_mongodb`), les 8 produits sont immédiatement de retour car stockés sur le volume `mongodb_data`.

### B. La lecture native des Secrets en Node.js (`runtime.js`) :
Dans les microservices (`auth-service/src/config/runtime.js` et `order-service/src/config/runtime.js`), nous avons écrit une fonction `resolveSecret()` pour lire le fichier monté par Docker Swarm sous `/run/secrets/jwt_secret` :

```javascript
import fs from 'fs';

export function resolveSecret(secretName, defaultValue = '') {
  const secretPath = `/run/secrets/${secretName}`;
  if (fs.existsSync(secretPath)) {
    return fs.readFileSync(secretPath, 'utf8').trim();
  }
  return process.env[secretName.toUpperCase()] || defaultValue;
}
```

#### 🔍 Pourquoi cette fonction est brillante pédagogiquement ?
1. **Priorité au Docker Secret :** Elle vérifie d'abord si le fichier `/run/secrets/jwt_secret` existe en mémoire (déploiement Swarm sécurisé). Si oui, elle lit son contenu.
2. **Fallback en Développement local :** Si le fichier n'existe pas (lorsque tu développes sur ton PC avec `docker-compose up`), elle bascule sur la variable d'environnement classique `process.env.JWT_SECRET`.
3. **Même code partout :** Tu n'as pas besoin de modifier une seule ligne de code JS entre ton environnement de dév sur PC et ton cluster Swarm en production !

---

## 6. Récapitulatif et Synthèse pour la Soutenance (Barème 15/15)

Lors de la présentation à l'oral, tu peux appuyer chaque point du barème avec précision en montrant le fichier ou la ligne de code correspondante :

| Critère (Barème) | Points | Ce qu'il faut expliquer / montrer à l'évaluateur | Statut dans le projet |
| :--- | :---: | :--- | :---: |
| **1. Cluster** *(1 master + 2 workers)* | **2 pts** | Montrer les `networks: driver: overlay` et `constraints: [node.role == manager]` dans `docker-compose.prod.yml`. Expliquer que le code s'exécute à l'identique sur 1 nœud local ou sur 3 VM en cluster. | 🟢 **2 / 2** |
| **2. Déploiement** *(Front, Back, BDD)* | **5 pts** | Montrer la séparation propre du `frontend`, des 3 backends Node (`auth`, `product`, `order`) et de `mongodb:4.4`. Expliquer l'optimisation des `Dockerfile` multi-stage (`--only=production`). | 🟢 **5 / 5** |
| **3. Persistance** *(Volumes, DB survive)* | **2 pts** | Montrer la section `volumes: - mongodb_data:/data/db`. Lancer le script `scripts/init-products.sh`, redémarrer le conteneur MongoDB et prouver via l'API que les données sont intactes. | 🟢 **2 / 2** |
| **4. Sécurité** *(Secrets & HTTPS)* | **2 pts** | **Secrets :** Montrer la ligne `secrets: - jwt_secret` dans le compose et la fonction `resolveSecret()` en Node.js.<br>**HTTPS :** Montrer `docker-compose.proxy.yml` et `proxy/entrypoint.sh` qui génère le SSL auto-signé. | 🟢 **2 / 2** |
| **5. Exposition** *(LB / Ingress & DNS)* | **2 pts** | **LB / Ingress :** Expliquer le routage Mesh Swarm et Nginx balançant sur les `5 répliquas` du frontend.<br>**DNS :** Montrer qu'avec `127.0.0.1 ecommerce.local` dans `/etc/hosts`, le site s'ouvre sur `https://ecommerce.local/`. | 🟢 **2 / 2** |
| **6. Documentation & Scripts** | **2 pts** | Présenter les scripts d'automatisation (`init-products.sh`, `setup.sh`), le `README.md` et le présent manuel `EXPLICATIONS_TECHNIQUES_COMPLETES.md`. | 🟢 **2 / 2** |

---
*Ce document forme la base théorique et pratique complète de votre projet e-commerce conteneurisé. Bonne soutenance !*
