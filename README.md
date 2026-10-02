# vps-nginx — Infraestructura base NGINX en VPS (Etapa 1)

Infraestructura Dockerizada mínima para un VPS con NGINX como único punto de entrada público. Proyecto de aprendizaje guiado por Spec-Driven Development (SDD): la especificación es la fuente de verdad y el código la sigue.

> **Alcance de esta etapa:** `VPS → Docker → NGINX` únicamente. Sin aplicaciones detrás todavía. Ver `spec.md` para el alcance exacto.

## Estructura

```
spec.md                  — requisitos y contratos (fuente de verdad)
plan.md                  — decisiones técnicas con razonamiento
tasks.md                 — tablero de trabajo por tasks (T1..T10)
runbook.md               — reconstrucción desde VPS limpio (checklist)
docker-compose.yml       — topología (servicio, red, volúmenes, puertos)
nginx/
  conf.d/                — vhosts por archivo (00- ACME+redirect, 10- placeholder)
  snippets/              — parámetros TLS compartidos
  static/                — placeholder de vida (RF2)
```

## Flujo SDD

```
spec → plan → tasks → implementación → verificación
```

Cada cambio que la implementación necesite y la spec no contemple se reconcilia **spec-primero**.

## Uso rápido

```bash
# Local (sin dominio real, cert provisional)
docker compose up -d
docker compose exec nginx nginx -t
curl -sI http://localhost/          # 301 → https
curl -k https://localhost/          # placeholder 200

# En VPS con hostname DuckDNS (ver runbook.md fases 0-1)
# El módulo ACME nativo obtiene el cert automáticamente.
curl -sI http://<tu-hostname>.duckdns.org   # 301
curl https://<tu-hostname>.duckdns.org      # placeholder 200, cert válido
docker logs nginx
```

## Documentación

- **Spec:** `spec.md` — qué debe cumplir el sistema y cómo se verifica.
- **Plan:** `plan.md` — qué se decidió y por qué (con fallback).
- **Runbook:** `runbook.md` — cómo reconstruir desde VPS limpio, paso a paso con checks.

## Requisitos

- Docker + Docker Compose
- VPS con IPv4 estática y puertos 80/443 alcanzables
- Hostname DuckDNS apuntando al VPS (un A-record en el panel)
