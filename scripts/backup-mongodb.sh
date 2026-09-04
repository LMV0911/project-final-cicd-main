#!/usr/bin/env bash
# ==============================================================================
# Script de Sauvegarde Automatisée MongoDB (Bonus Piste 9)
# Projet : E-Commerce Microservices - Orchestration Docker Swarm
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-${ROOT_DIR}/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
BACKUP_NAME="mongodb_backup_${TIMESTAMP}"
TARGET_DIR="${BACKUP_DIR}/${BACKUP_NAME}"
ARCHIVE_PATH="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Script de sauvegarde à chaud des bases de données MongoDB (Swarm ou Compose).
Exporte les bases 'auth', 'products' et 'orders', compresse l'archive et purge
les anciennes sauvegardes selon la politique de rétention.

Options:
  -h, --help       Afficher cette aide
  -d, --dir DIR    Dossier de destination (défaut: ./backups)
  -r, --retention  Nombre de jours de rétention (défaut: 7)
  --dry-run        Simuler l'exécution sans effectuer d'export
EOF
}

DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -d|--dir)
      BACKUP_DIR="$2"
      shift 2
      ;;
    -r|--retention)
      RETENTION_DAYS="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    *)
      error "Option inconnue : $1"
      usage
      exit 1
      ;;
  esac
done

info "=== Démarrage de la sauvegarde MongoDB ==="
info "Horodatage : ${TIMESTAMP}"
info "Dossier cible : ${BACKUP_DIR}"
info "Rétention : ${RETENTION_DAYS} jours"

mkdir -p "${BACKUP_DIR}"

# Détection du conteneur MongoDB actif (Swarm ou Compose)
MONGO_CONTAINER=""
if command -v docker >/dev/null 2>&1; then
  # 1. Recherche conteneur Swarm
  MONGO_CONTAINER="$(docker ps -q -f name=e-commerce_mongodb -f status=running | head -n 1 || true)"
  # 2. Fallback Compose local
  if [ -z "${MONGO_CONTAINER}" ]; then
    MONGO_CONTAINER="$(docker ps -q -f name=mongodb -f status=running | head -n 1 || true)"
  fi
fi

if [ -z "${MONGO_CONTAINER}" ]; then
  error "Aucun conteneur MongoDB en cours d'exécution détecté."
  exit 1
fi

info "Conteneur MongoDB détecté : ${MONGO_CONTAINER}"

if [ "${DRY_RUN}" -eq 1 ]; then
  info "[DRY-RUN] Simulation réussie : conteneur trouvé, sauvegarde non effectuée."
  exit 0
fi

# Création du dossier temporaire de dump
mkdir -p "${TARGET_DIR}"

info "Export des bases de données avec mongodump..."
# Exécute mongodump à l'intérieur du conteneur dans /tmp/dump
docker exec "${MONGO_CONTAINER}" rm -rf /tmp/dump
docker exec "${MONGO_CONTAINER}" mongodump --out=/tmp/dump --quiet

info "Extraction du dump depuis le conteneur..."
docker cp "${MONGO_CONTAINER}:/tmp/dump/." "${TARGET_DIR}/"
docker exec "${MONGO_CONTAINER}" rm -rf /tmp/dump

# Vérification du contenu exporté
DUMPED_DBS=$(find "${TARGET_DIR}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
info "Bases sauvegardées : ${DUMPED_DBS//$'\n'/, }"

# Compression de l'archive
info "Compression de l'archive tar.gz..."
tar -czf "${ARCHIVE_PATH}" -C "${BACKUP_DIR}" "${BACKUP_NAME}"
rm -rf "${TARGET_DIR}"

# Calcul de l'empreinte SHA256 pour intégrité
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "${ARCHIVE_PATH}" > "${ARCHIVE_PATH}.sha256"
fi

FILE_SIZE=$(du -h "${ARCHIVE_PATH}" | awk '{print $1}')
info "Sauvegarde créée avec succès : ${ARCHIVE_PATH} (${FILE_SIZE})"

# Purge des anciennes sauvegardes
info "Nettoyage des sauvegardes antérieures à ${RETENTION_DAYS} jours..."
find "${BACKUP_DIR}" -name "mongodb_backup_*.tar.gz*" -type f -mtime +"${RETENTION_DAYS}" -exec rm -f {} + || true

info "=== Sauvegarde terminée avec succès ==="
