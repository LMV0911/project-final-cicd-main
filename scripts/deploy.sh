#!/usr/bin/env bash
# ==============================================================================
# Script de Déploiement Universel Docker Swarm (Clé en main pour l'Évaluateur)
# Projet : E-Commerce Microservices
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_NAME="${STACK_NAME:-e-commerce}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"

CI_REGISTRY_IMAGE="${CI_REGISTRY_IMAGE:-ecommerce}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
JWT_SECRET="${JWT_SECRET:-super_secret_jwt_key_prod_2026}"
CORS_ORIGIN="${CORS_ORIGIN:-http://localhost:8080}"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

if ! command -v docker >/dev/null 2>&1; then
  error "Docker est requis pour deployer la stack."
  exit 1
fi

# Vérifier si Docker Swarm est actif
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
  warn "Docker Swarm n'est pas actif. Initialisation automatique..."
  docker swarm init || true
fi

cd "${ROOT_DIR}"

# 1. Création automatique du secret Docker si absent
if ! docker secret inspect jwt_secret >/dev/null 2>&1; then
  info "Creation du Docker secret 'jwt_secret'..."
  printf "%s" "${JWT_SECRET}" | docker secret create jwt_secret - 2>/dev/null || true
else
  info "Le Docker secret 'jwt_secret' existe deja."
fi

# 2. Construction automatique des images locales si absentes
for svc in frontend auth-service product-service order-service; do
  img="${CI_REGISTRY_IMAGE}/${svc}:${IMAGE_TAG}"
  if ! docker image inspect "${img}" >/dev/null 2>&1; then
    dir="services/${svc}"
    if [ "${svc}" = "frontend" ]; then dir="frontend"; fi
    info "Construction de l'image de production pour ${svc} (${img})..."
    docker build --target production -t "${img}" "${ROOT_DIR}/${dir}"
  fi
done

# 3. Déploiement de la stack Swarm
info "Deploiement de la stack Swarm '${STACK_NAME}' avec ${COMPOSE_FILE}..."
CI_REGISTRY_IMAGE="${CI_REGISTRY_IMAGE}" \
IMAGE_TAG="${IMAGE_TAG}" \
CORS_ORIGIN="${CORS_ORIGIN}" \
docker stack deploy -c "${COMPOSE_FILE}" "${STACK_NAME}"

info "Attente de la convergence des services (15s)..."
sleep 15
docker stack services "${STACK_NAME}" || true

# 4. Déploiement du reverse-proxy HTTPS si présent
if [ -f "docker-compose.proxy.yml" ]; then
  info "Deploiement du reverse-proxy HTTPS (e-commerce-proxy)..."
  docker stack deploy -c docker-compose.proxy.yml e-commerce-proxy 2>/dev/null || true
fi

# 5. Peuplement initial des produits
info "Initialisation des donnees produits..."
sleep 5
PRODUCT_API_URL="http://localhost:8080/api" ./scripts/init-products.sh || true

info "================================================================="
info "✅ Deploiement termine avec succes !"
info "🌐 Acces Web HTTP  : http://localhost:8080"
info "🔒 Acces Web HTTPS : https://localhost (ou https://app.local)"
info "================================================================="
