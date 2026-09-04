#!/usr/bin/env bash
# ==============================================================================
# Script de Scalabilité Automatique pour Docker Swarm (Bonus Piste 10)
# Projet : E-Commerce Microservices - Orchestration Docker Swarm
# ==============================================================================
set -euo pipefail

SERVICE_NAME="${1:-e-commerce_frontend}"
MIN_REPLICAS="${MIN_REPLICAS:-3}"
MAX_REPLICAS="${MAX_REPLICAS:-8}"
CPU_UP_THRESHOLD="${CPU_UP_THRESHOLD:-75}"
CPU_DOWN_THRESHOLD="${CPU_DOWN_THRESHOLD:-25}"
CHECK_INTERVAL="${CHECK_INTERVAL:-15}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-30}"
DRY_RUN=0
ONCE=0

info() { printf '[INFO] [%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { printf '[WARN] [%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }
error() { printf '[ERROR] [%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }

usage() {
  cat <<EOF
Usage: $0 [OPTIONS] [NOM_DU_SERVICE]

Démon ou outil d'auto-scaling horizontal dynamique pour services Docker Swarm (HPA-like).
Surveille l'utilisation CPU moyenne des conteneurs du service et ajuste dynamiquement
le nombre de répliques entre MIN_REPLICAS et MAX_REPLICAS.

Options:
  -h, --help               Afficher cette aide
  -s, --service NOM        Nom du service Swarm (défaut: e-commerce_frontend)
  --min N                  Nombre minimum de répliques (défaut: 3)
  --max N                  Nombre maximum de répliques (défaut: 8)
  --cpu-up N               Seuil CPU (%) pour déclencher un Scale Up (défaut: 75)
  --cpu-down N             Seuil CPU (%) pour déclencher un Scale Down (défaut: 25)
  --interval N             Intervalle de vérification en secondes (défaut: 15)
  --cooldown N             Délai de cooldown anti-flapping en secondes (défaut: 30)
  --once                   Exécuter une seule évaluation et quitter
  --dry-run                Simuler sans exécuter 'docker service scale'
EOF
}

# Analyse des arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -s|--service)
      SERVICE_NAME="$2"
      shift 2
      ;;
    --min)
      MIN_REPLICAS="$2"
      shift 2
      ;;
    --max)
      MAX_REPLICAS="$2"
      shift 2
      ;;
    --cpu-up)
      CPU_UP_THRESHOLD="$2"
      shift 2
      ;;
    --cpu-down)
      CPU_DOWN_THRESHOLD="$2"
      shift 2
      ;;
    --interval)
      CHECK_INTERVAL="$2"
      shift 2
      ;;
    --cooldown)
      COOLDOWN_SECONDS="$2"
      shift 2
      ;;
    --once)
      ONCE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -*)
      error "Option inconnue : $1"
      usage
      exit 1
      ;;
    *)
      SERVICE_NAME="$1"
      shift
      ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  error "Docker est requis pour exécuter ce script."
  exit 1
fi

info "=== Démarrage du moniteur d'auto-scaling Swarm ==="
info "Service surveillé : ${SERVICE_NAME}"
info "Limites de répliques : Min = ${MIN_REPLICAS} | Max = ${MAX_REPLICAS}"
info "Seuils CPU : Scale-Up > ${CPU_UP_THRESHOLD}% | Scale-Down < ${CPU_DOWN_THRESHOLD}%"
info "Intervalle : ${CHECK_INTERVAL}s | Cooldown : ${COOLDOWN_SECONDS}s"
if [ "${DRY_RUN}" -eq 1 ]; then info "Mode : DRY-RUN (simulation)"; fi

LAST_SCALE_TIME=0

evaluate_and_scale() {
  # 1. Vérifier si le service existe dans Swarm
  if ! docker service inspect "${SERVICE_NAME}" >/dev/null 2>&1; then
    warn "Le service Swarm '${SERVICE_NAME}' n'existe pas ou le cluster n'est pas actif."
    return 1
  fi

  # 2. Récupérer le nombre actuel de répliques configurées
  CURRENT_REPLICAS=$(docker service inspect "${SERVICE_NAME}" --format '{{.Spec.Mode.Replicated.Replicas}}' 2>/dev/null || echo "0")
  if [ -z "${CURRENT_REPLICAS}" ] || [ "${CURRENT_REPLICAS}" -eq 0 ]; then
    CURRENT_REPLICAS=1
  fi

  # 3. Récupérer la liste des conteneurs locaux correspondant au service
  CONTAINER_IDS=$(docker ps -q -f name="${SERVICE_NAME}\." || true)

  if [ -z "${CONTAINER_IDS}" ]; then
    info "Aucun conteneur en cours d'exécution sur ce nœud pour ${SERVICE_NAME} (répliques cluster: ${CURRENT_REPLICAS})."
    return 0
  fi

  # 4. Calculer la moyenne d'utilisation CPU
  TOTAL_CPU=0
  COUNT=0
  while IFS= read -r line; do
    if [ -n "${line}" ]; then
      # Extrait la valeur numérique sans le %
      CPU_VAL=$(echo "${line}" | tr -d '%' | awk '{print int($1)}')
      TOTAL_CPU=$((TOTAL_CPU + CPU_VAL))
      COUNT=$((COUNT + 1))
    fi
  done < <(docker stats --no-stream --format "{{.CPUPerc}}" ${CONTAINER_IDS})

  if [ "${COUNT}" -eq 0 ]; then
    AVG_CPU=0
  else
    AVG_CPU=$((TOTAL_CPU / COUNT))
  fi

  info "Métriques ${SERVICE_NAME} : CPU Moyen = ${AVG_CPU}% | Répliques actuelles = ${CURRENT_REPLICAS}"

  NOW=$(date +%s)
  ELAPSED=$((NOW - LAST_SCALE_TIME))

  # 5. Décision de Scaling
  if [ "${AVG_CPU}" -ge "${CPU_UP_THRESHOLD}" ]; then
    if [ "${CURRENT_REPLICAS}" -ge "${MAX_REPLICAS}" ]; then
      info "Plafond max de répliques atteint (${MAX_REPLICAS}). Pas de scale-up possible."
    elif [ "${ELAPSED}" -lt "${COOLDOWN_SECONDS}" ]; then
      info "Seuil dépassé mais période de cooldown active (${ELAPSED}s / ${COOLDOWN_SECONDS}s). Attente."
    else
      NEW_REPLICAS=$((CURRENT_REPLICAS + 1))
      info "🚀 DÉCISION : SCALE UP -> Passage de ${CURRENT_REPLICAS} à ${NEW_REPLICAS} répliques."
      if [ "${DRY_RUN}" -eq 0 ]; then
        docker service scale "${SERVICE_NAME}=${NEW_REPLICAS}"
        LAST_SCALE_TIME=$(date +%s)
      else
        info "[DRY-RUN] Commande simulée : docker service scale ${SERVICE_NAME}=${NEW_REPLICAS}"
      fi
    fi

  elif [ "${AVG_CPU}" -le "${CPU_DOWN_THRESHOLD}" ]; then
    if [ "${CURRENT_REPLICAS}" -le "${MIN_REPLICAS}" ]; then
      # Normal state, already at minimum
      :
    elif [ "${ELAPSED}" -lt "${COOLDOWN_SECONDS}" ]; then
      info "Charge faible mais période de cooldown active (${ELAPSED}s / ${COOLDOWN_SECONDS}s). Attente."
    else
      NEW_REPLICAS=$((CURRENT_REPLICAS - 1))
      info "🔻 DÉCISION : SCALE DOWN -> Passage de ${CURRENT_REPLICAS} à ${NEW_REPLICAS} répliques."
      if [ "${DRY_RUN}" -eq 0 ]; then
        docker service scale "${SERVICE_NAME}=${NEW_REPLICAS}"
        LAST_SCALE_TIME=$(date +%s)
      else
        info "[DRY-RUN] Commande simulée : docker service scale ${SERVICE_NAME}=${NEW_REPLICAS}"
      fi
    fi
  fi
}

if [ "${ONCE}" -eq 1 ]; then
  evaluate_and_scale || true
  exit 0
fi

# Boucle de surveillance continue
while true; do
  evaluate_and_scale || true
  sleep "${CHECK_INTERVAL}"
done
