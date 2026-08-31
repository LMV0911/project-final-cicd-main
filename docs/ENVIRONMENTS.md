# Environnements

Les backends supportent explicitement les environnements suivants avec `APP_ENV` :

- `development`
- `staging`
- `production`
- `test`

`NODE_ENV` garde son role Node.js classique. Dans les stacks Swarm dev/staging/production, `NODE_ENV=production` car les images deployees sont des images runtime.

## Development local

Compose local :

```bash
docker-compose up --build
```

Backends :

- Docker target : `development`
- `APP_ENV=development`
- `NODE_ENV=development`
- demarrage : `npm run dev`

MongoDB est lance par Docker Compose.

## Dev Swarm

Fichier :

```bash
docker-compose.dev.yml
```

Usage Swarm :

```bash
export CI_REGISTRY_IMAGE=registry.gitlab.com/groupe/projet
export IMAGE_TAG=<commit-sha>
export DEV_FRONTEND_PORT=8082
export DEV_CORS_ORIGIN=http://dev.example.test:8082
docker-compose -f docker-compose.dev.yml build
docker stack deploy -c docker-compose.dev.yml e-commerce-dev --with-registry-auth
```

La ligne `build` est utile en manuel pour construire/tagger les images de dev. Pour Swarm, `docker stack deploy` ignore le build et utilise les champs `image`. En CI, les images sont donc construites par les jobs `build_*`, poussees dans le registry, puis deployees dans la stack dev isolee.

Backends :

- `APP_ENV=development`
- `NODE_ENV=production`
- bases MongoDB : `auth_dev`, `products_dev`, `orders_dev`
- `DEV_JWT_SECRET` optionnel, fallback dev non sensible
- frontend publie sur `DEV_FRONTEND_PORT`, defaut `8082`

## Staging / preproduction

Fichier :

```bash
docker-compose.staging.yml
```

Usage Swarm :

```bash
export CI_REGISTRY_IMAGE=registry.gitlab.com/groupe/projet
export IMAGE_TAG=<commit-sha>
export JWT_SECRET=<secret-staging>
docker stack deploy -c docker-compose.staging.yml e-commerce-staging --with-registry-auth
```

Par defaut, le frontend staging publie le port `8081`. Changer avec :

```bash
export STAGING_FRONTEND_PORT=8081
export STAGING_CORS_ORIGIN=http://staging.example.test:8081
```

Backends :

- `APP_ENV=staging`
- `NODE_ENV=production`
- bases MongoDB : `auth_staging`, `products_staging`, `orders_staging`
- `frontend` en `replicas: 3` et backends en `replicas: 2` (conformité haute disponibilité)
- `JWT_SECRET` injecté via **Docker Secret** (`/run/secrets/jwt_secret`) pour `auth-service` et `order-service`

## Production

Fichier :

```bash
docker-compose.prod.yml
```

Usage Swarm :

```bash
export CI_REGISTRY_IMAGE=registry.gitlab.com/groupe/projet
export IMAGE_TAG=<commit-sha>
printf "%s" "super_secure_jwt_secret" | docker secret create jwt_secret - 2>/dev/null || true
export CORS_ORIGIN=https://app.local
docker stack deploy -c docker-compose.prod.yml e-commerce --with-registry-auth
```

Backends et Frontend :

- `APP_ENV=production`
- `NODE_ENV=production`
- `frontend` en **3 répliquas** et backends en **2 répliquas** (haute disponibilité)
- ports backends non publics sur l'hôte, communication via le réseau overlay `ecommerce_net`
- `JWT_SECRET` injecté et lu nativement depuis le **Docker Secret** `/run/secrets/jwt_secret`

## Exposition & Reverse Proxy SSL (app.local)

Pour satisfaire l'exposition sécurisée en HTTPS et le reverse proxy vers les répliquas du frontend :

```bash
docker stack deploy -c docker-compose.proxy.yml e-commerce-proxy
```

- **Reverse proxy Nginx** : Termine le trafic HTTPS sur le port `443` (`http -> https` redirect sur `80`) et redirige vers le service `frontend:8080` sur le réseau `overlay` commun (`ecommerce_net`).
- **Certificat SSL auto-signé** : Généré automatiquement au démarrage par le script d'entrypoint Nginx pour le domaine `app.local`. Ajout à `/etc/hosts` : `127.0.0.1 app.local`.

## Targets Docker backend

Chaque backend fournit ces targets :

- `deps` : installe les dependances avec `npm ci`
- `build` : copie le code source applicatif
- `development` : inclut les devDependencies et lance `npm run dev`
- `runtime` : runtime minimal avec dependencies production
- `staging` : runtime avec `APP_ENV=staging`
- `production` : runtime avec `APP_ENV=production`

Exemples :

```bash
docker build --target development -t ecommerce/auth-service:dev services/auth-service
docker build --target staging -t ecommerce/auth-service:staging services/auth-service
docker build --target production -t ecommerce/auth-service:prod services/auth-service
```

Le meme modele existe pour `product-service` et `order-service`.
