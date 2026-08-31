#!/bin/sh
set -e

mkdir -p /etc/nginx/certs

if [ ! -f /etc/nginx/certs/app.local.crt ] || [ ! -f /etc/nginx/certs/app.local.key ]; then
    echo "Génération du certificat SSL auto-signé pour app.local..."
    apk add --no-cache openssl >/dev/null 2>&1 || true
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/certs/app.local.key \
        -out /etc/nginx/certs/app.local.crt \
        -subj "/CN=app.local/O=Ecommerce/C=FR"
fi
