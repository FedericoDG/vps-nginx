#!/usr/bin/env bash
# tests/verify-nginx.sh — regresión de la config de nginx (probes P1-P5)
#
# Por qué existe: este repo despliega nginx en un VPS compartido por varias apps.
# Una config inválida no se detecta hasta que el CI recrea el contenedor en el VPS,
# y para entonces el sitio ya está caído. Este script corre las mismas probes de
# forma local, ANTES de pushear.
#
# Requiere: docker + la imagen nginx:1.29-alpine (misma que usa docker-compose.yml).
# No toca ningún entorno remoto ni el estado del repo.
#
#   sh tests/verify-nginx.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMG=nginx:1.29-alpine
SCRATCH="$(mktemp -d)"
NET="ngx-test-$$"

cleanup() {
  docker rm -f ngx-up ngx-new ngx-old ngx-inv 2>/dev/null || true
  docker network rm "$NET" 2>/dev/null || true
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

docker network create "$NET" >/dev/null

M=(
  -v "$ROOT/nginx/nginx.conf:/etc/nginx/nginx.conf:ro"
  -v "$ROOT/nginx/conf.d:/etc/nginx/conf.d:ro"
  -v "$ROOT/nginx/includes:/etc/nginx/includes:ro"
  -v "$ROOT/nginx/snippets:/etc/nginx/snippets:ro"
  -v "$ROOT/nginx/static:/usr/share/nginx/placeholder:ro"
  -v "$ROOT/nginx/certs:/etc/nginx/certs:ro"
)

# --- P1: la config es válida SIN que existan los contenedores de las apps -----
# En una red aislada no resuelven panel-backend/panel-web/turnos-web, que es
# justamente el caso que nginx tiene que tolerar para poder arrancar.
echo "P1: nginx -t sin los hosts de las apps"
docker run --rm --network "$NET" "${M[@]}" "$IMG" nginx -t

# --- P5: no quedaron referencias al nombre viejo del vhost -------------------
echo "P5: sin referencias a 10-placeholder.conf"
! grep -rn "10-placeholder" "$ROOT" --exclude-dir=.git

# --- P4: el vhost dedicado no debe montar POS --------------------------------
echo "P4: separación de vhosts"
if grep -vE '^[[:space:]]*#' "$ROOT/nginx/conf.d/20-reservaplus.conf" | grep -qiE 'panel-|api-pos-offline'; then
  echo "FAIL P4: el vhost dedicado no debe mencionar rutas de POS"; exit 1
fi
grep -q 'includes/pos-offline.conf' "$ROOT/nginx/conf.d/10-vhost-principal.conf"
grep -q 'includes/turnos.conf' "$ROOT/nginx/conf.d/10-vhost-principal.conf"

# --- P2: el mapeo de URIs de POS es idéntico al del baseline -----------------
# Compara la respuesta de HEAD contra la del commit d4351fd, lado a lado.
echo "P2: paridad de mapeo de URIs de POS contra el baseline"
cat > "$SCRATCH/up.conf" <<'EOF'
events {} http { server { listen 4000; listen 3000; listen 80; default_type text/plain; return 200 "$request_uri"; } }
EOF
cat > "$SCRATCH/sub.conf" <<'EOF'
events {} http { server { listen 8080; include /etc/nginx/includes/pos-offline.conf; include /etc/nginx/includes/turnos.conf; } }
EOF

docker run -d --name ngx-up --network "$NET" \
  --network-alias panel-backend --network-alias panel-web --network-alias turnos-web \
  -v "$SCRATCH/up.conf:/etc/nginx/nginx.conf:ro" "$IMG" >/dev/null
docker run -d --name ngx-new --network "$NET" -p 18080:8080 \
  -v "$SCRATCH/sub.conf:/etc/nginx/nginx.conf:ro" \
  -v "$ROOT/nginx/includes:/etc/nginx/includes:ro" "$IMG" >/dev/null

mkdir -p "$SCRATCH/base"
git -C "$ROOT" archive d4351fd | tar -x -C "$SCRATCH/base"
docker run -d --name ngx-old --network "$NET" -p 18081:8080 \
  -v "$SCRATCH/sub.conf:/etc/nginx/nginx.conf:ro" \
  -v "$SCRATCH/base/nginx/includes:/etc/nginx/includes:ro" "$IMG" >/dev/null
sleep 2

chk() {
  [ "$(curl -s "http://127.0.0.1:18080$1")" = "$2" ] \
    && [ "$(curl -s "http://127.0.0.1:18081$1")" = "$2" ] \
    || { echo "FAIL P2 $1"; exit 1; }
}
chk "/api-pos-offline/updates/latest.json?x=1" "/api/updates/latest.json?x=1"
chk "/api/updates/latest.json?x=1"             "/api/updates/latest.json?x=1"
# El panel pasó a basePath /admin: la URL vieja ahora reescribe a la nueva.
# Es un cambio deliberado, así que este caso no compara contra el baseline
# (el commit viejo sigue devolviendo /panel-pos-offline/algo por diseño).
[ "$(curl -s "http://127.0.0.1:18080/panel-pos-offline/algo")" = "/admin/algo" ] \
  || { echo "FAIL P2: el rewrite del panel no reescribe a /admin"; exit 1; }

# --- P3: el orden "set" antes de "rewrite ... break" es obligatorio ----------
# Invertido, el break corta la fase de rewrite y la variable queda sin inicializar.
echo "P3: el orden invertido debe fallar"
cat > "$SCRATCH/inv.conf" <<'EOF'
events {} http { server { listen 8080; resolver 127.0.0.11 ipv6=off; rewrite ^/api-pos-offline/(.*)$ /api/$1 break; set $u http://panel-backend:4000; proxy_pass $u; } }
EOF
docker run -d --name ngx-inv --network "$NET" -p 18082:8080 \
  -v "$SCRATCH/inv.conf:/etc/nginx/nginx.conf:ro" "$IMG" >/dev/null
sleep 1
[ "$(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:18082/api-pos-offline/x')" = "500" ] \
  || { echo "FAIL P3"; exit 1; }

echo "ALL PROBES PASSED"
