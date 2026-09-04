#!/usr/bin/env bash
# ==============================================================================
# Script de Restauration Automatisée MongoDB (Bonus Piste 9)
# Projet : E-Commerce Microservices - Orchestration Docker Swarm
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-${ROOT_DIR}/backups}"
FORCE=0

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
  cat <<EOF
Usage: $0 [OPTIONS] [FICHIER_BACKUP.tar.gz]

Script de restauration des bases de données MongoDB à partir d'une archive tar.gz.
Si aucun fichier n'est spécifié, la sauvegarde la plus récente dans ./backups est utilisée.

Options:
  -h, --help    Afficher cette aide
  -f, --force   Exécuter la restauration sans confirmation interactive
  -d, --dir DIR Dossier contenant les sauvegardes (défaut: ./backups)
EOF
}

ARCHIVE_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -f|--force)
      FORCE=1
      shift
      ;;
    -d|--dir)
      BACKUP_DIR="$2"
      shift 2
      ;;
    *)
      if [ -z "${ARCHIVE_ARG}" ]; then
        ARCHIVE_ARG="$1"
        shift
      else
        error "Argument inattendu : $1"
        usage
        exit 1
      fi
      ;;
  esac
done

# Détection de l'archive
if [ -n "${ARCHIVE_ARG}" ]; then
  ARCHIVE_PATH="${ARCHIVE_ARG}"
else
  # Recherche de la sauvegarde la plus récente
  ARCHIVE_PATH=$(find "${BACKUP_DIR}" -name "mongodb_backup_*.tar.gz" -type f 2>/dev/null | sort -r | head -n 1 || true)
fi

if [ -z "${ARCHIVE_PATH}" ] || [ ! -f "${ARCHIVE_PATH}" ]; then
  error "Aucune archive de sauvegarde trouvée dans ${BACKUP_DIR}."
  exit 1
fi

info "=== Restauration MongoDB ==="
info "Archive sélectionnée : ${ARCHIVE_PATH}"

# Vérification intégrité sha256 si présent
if [ -f "${ARCHIVE_PATH}.sha256" ] && command -v sha256sum >/dev/null 2>&1; then
  info "Vérification de l'empreinte SHA256..."
  (cd "$(dirname "${ARCHIVE_PATH}")" && sha256sum -c "$(basename "${ARCHIVE_PATH}").sha256" --quiet)
  info "Empreinte SHA256 validée."
fi

# Confirmation utilisateur si pas --force
if [ "${FORCE}" -ne 1 ]; then
  printf '[ATTENTION] Cette action va écraser les collections existantes (--drop). Confirmer ? (o/N) '
  read -r response
  if [[ ! "$response" =~ ^([oOyY])$ ]]; then
    warn "Restauration annulée par l'utilisateur."
    exit 0
  fi
fi

# Détection conteneur MongoDB actif
MONGO_CONTAINER=""
if command -v docker >/dev/null 2>&1; then
  MONGO_CONTAINER="$(docker ps -q -f name=e-commerce_mongodb -f status=running | head -n 1 || true)"
  if [ -z "${MONGO_CONTAINER}" ]; then
    MONGO_CONTAINER="$(docker ps -q -f name=mongodb -f status=running | head -n 1 || true)"
  fi
fi

if [ -z "${MONGO_CONTAINER}" ]; then
  error "Aucun conteneur MongoDB en cours d'exécution détecté."
  exit 1
fi

info "Conteneur cible : ${MONGO_CONTAINER}"

# Décompression dans un dossier temporaire
TEMP_RESTORE_DIR=$(mktemp -d)
trap 'rm -rf "${TEMP_RESTORE_DIR}"' EXIT

info "Extraction de l'archive..."
tar -xzf "${ARCHIVE_PATH}" -C "${TEMP_RESTORE_DIR}"

DUMP_DIR=$(find "${TEMP_RESTORE_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n 1)

if [ -z "${DUMP_DIR}" ]; then
  error "Format d'archive invalide : aucun répertoire de dump trouvé."
  exit 1
fi

info "Transfert des fichiers dans le conteneur..."
docker exec "${MONGO_CONTAINER}" rm -rf /tmp/restore
docker cp "${DUMP_DIR}/." "${MONGO_CONTAINER}:/tmp/restore"

info "Exécution de mongorestore (--drop)..."
docker exec "${MONGO_CONTAINER}" mongorestore --drop /tmp/restore --quiet

docker exec "${MONGO_CONTAINER}" rm -rf /tmp/restore

info "=== Restauration terminée avec succès ==="
