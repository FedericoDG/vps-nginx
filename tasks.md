# TASKS — Etapa 1: NGINX base en VPS Dockerizado

**Spec base:** `spec.md` v1.1 · **Plan base:** `plan.md` v1.0
**Convención de estados:** `pending` · `in_progress` · `done` · `blocked`

> Cada task tiene un solo outcome verificable y un criterio de aceptación (AC) que remite a IDs de `spec.md`. El orden es topológico por dependencias.

---

## Bloque A — Documentación del proyecto (primero)

### T1 — Redactar `spec.md` v1.1
- **Estado:** done
- **Archivos:** `spec.md`
- **Depende de:** —
- **AC:** el archivo contiene C1-C3, RF1-RF8, RNF1, tabla de decisiones con estado (tomadas / superseded / pendientes / aplazadas) y fuera de alcance. Verificado por inspección.

### T2 — Redactar `plan.md`
- **Estado:** done
- **Archivos:** `plan.md`
- **Depende de:** T1
- **AC:** cada decisión P1-P4 con razonamiento y fallback documentado; estructura del repositorio D-E1..D-E8 con rationale; matriz de trazabilidad spec→plan.

### T3 — Redactar `tasks.md` + `README.md`
- **Estado:** done
- **Archivos:** `tasks.md`, `README.md`
- **Depende de:** T1, T2
- **AC:** `tasks.md` lista T1..T10 con archivos, dependencias y AC vinculados a spec; `README.md` describe el proyecto y enlaza spec/plan/runbook.

### T4 — Redactar `runbook.md`
- **Estado:** done
- **Archivos:** `runbook.md`
- **Depende de:** T1
- **AC:** fases 0-5 con checks; cada fase termina con verificación ligada a RF/RNF; RNF1 cubierto (reconstrucción desde VPS limpio). Verificado por inspección.

---

## Bloque B — Infraestructura Docker/NGINX

### T5 — `docker-compose.yml` (topología)
- **Estado:** done — verificado: `docker compose config` OK, `docker port` solo 80/443, red `vps-net`, volumen `acme-state` persiste tras down/up
- **Archivos:** `docker-compose.yml`
- **Depende de:** T1-T4
- **Scope:** servicio `nginx` (imagen mainline con `nginx-module-acme`, tag pinneado), red dedicada, volumen nombrado para estado ACME, puertos `80:80` y `443:443`, montaje de `nginx/` en solo lectura.
- **AC:**
  - `docker compose config` valida sin errores.
  - `docker compose up -d` levanta `nginx`.
  - `docker port <nginx>` solo muestra `80->80` y `443->443` (C1, RF1).
  - `docker network inspect <red>` lista al servicio (C2).
  - Volumen nombrado existe y persiste tras `down` (C3).

### T6 — `nginx/conf.d/00-acme-and-redirect.conf` + `nginx/snippets/tls-params.conf` + `nginx/nginx.conf`
- **Estado:** done — verificado: `nginx -t` OK, `curl http://localhost/` → 301 (RF3), challenge path excluido
- **Archivos:** `nginx/nginx.conf` (issuer staging + load_module), `nginx/conf.d/00-acme-and-redirect.conf`, `nginx/snippets/tls-params.conf`
- **Depende de:** T5
- **Scope:** listener `:80` con doble rol: servir `/.well-known/acme-challenge/` vía módulo ACME y redirigir el resto `301 → https://`. Snippet con parámetros TLS compartidos (protocolos, cifrados, headers) que el vhost 443 reutiliza.
- **AC:**
  - `docker compose exec nginx nginx -t` pasa.
  - `curl -sI http://localhost/` desde dentro o fuera del contenedor devuelve `301` con `Location: https://...` (RF3).
  - Path `/.well-known/acme-challenge/` queda excluido del redirect (requisito de RF7).

### T7 — `nginx/conf.d/10-placeholder.conf` + `nginx/static/placeholder.html` + `nginx/certs/placeholder.*`
- **Estado:** done — verificado: `curl -k https://localhost/` → 200 placeholder (RF2), `docker logs` muestra accesos (RF6), reload sin caída (RF5)
- **Archivos:** `nginx/conf.d/10-placeholder.conf`, `nginx/static/placeholder.html`, `nginx/certs/placeholder.crt/.key` (self-signed local)
- **Depende de:** T6
- **Scope:** vhost `:443` que sirve el placeholder estático e incluye el snippet TLS. Incluye generación local de cert provisional/self-signed para verificación en máquina sin dominio real.
- **AC:**
  - `nginx -t` pasa con el nuevo vhost.
  - `curl -k https://localhost/` (o `https://localhost --resolve`) devuelve `200` con el contenido identificador del placeholder (RF2).
  - `docker logs nginx` muestra accesos (RF6).

### T8 — Emisión con ACME en staging (requiere VPS real)
- **Estado:** done — verificado en VPS: cert de staging emitido (volumen acme-state: `account.key` + `<hostname>-*.crt/key`), issuer `(STAGING) Baloney Bulgur YE2` servido en 443, `curl -sI http` → 301, challenge HTTP-01 con 200 desde validadores LE. Fix aplicado en el camino: `resolver ipv6=off` (bridge sin IPv6; LE staging tiene AAAA) y recreate de contenedor tras `git pull` (bind-mount por archivo ancla al inodo). Commits `6890d13` + `da10b7e`.
- **Archivos:** `nginx/conf.d/00-acme-and-redirect.conf` (bloque `acme_issuer` apuntando a staging), `nginx/conf.d/10-placeholder.conf` (activación ACME en 443), `nginx/nginx.conf` (contacto + resolver)
- **Depende de:** T7 + fases 0-1 del runbook (VPS con Docker + hostname DuckDNS resuelto)
- **Scope:** configurar issuer ACME contra el entorno **staging** de Let's Encrypt, levantar en VPS y verificar issuance.
- **AC:**
  - Logs del contenedor muestran issuance exitoso contra staging.
  - `curl https://<hostname>/` con CA de staging (o `-k` + inspección de issuer) confirma cert emitido (RF7, primer hit).
  - `curl -sI http://<hostname>/` → `301` (RF3 en dominio real).
  - P3 validada: staging no golpea rate limits de producción.

### T9 — Cambio a producción LE + verificación de renovación
- **Estado:** pending
- **Archivos:** `nginx/conf.d/00-acme-and-redirect.conf` (cambio de `uri` a producción)
- **Depende de:** T8
- **Scope:** cambiar issuer a producción, renovar/reemitir, y ejecutar verificación de renovación (dry-run / comprobación de estado en volumen + logs).
- **AC:**
  - `curl https://<hostname>/` sin `-k` valida contra CA de confianza (cert de producción, RF7 cerrado).
  - Mecanismo de renovación verificado (comando/estado del módulo documentado en runbook).

### T10 — Verificación final: runbook end-to-end
- **Estado:** pending
- **Archivos:** `runbook.md` (correcciones si surgen)
- **Depende de:** T9
- **Scope:** recorrer el runbook completo desde un VPS limpio (o VM local limpia) y alcanzar estado completo.
- **AC:**
  - Checklist fases 0-5 en verde sin pasos "de memoria".
  - Correcciones al runbook, si aparecen hallazgos, commiteadas en el mismo ciclo.
  - Cierra RNF1: el repositorio es la fuente completa de la infraestructura.

---

## Orden de ejecución

```
T1 → T2 → T3 → T4 → T5 → T6 → T7 → (requiere VPS) → T8 → T9 → T10
         └────────────── docs-first ──────────────┘   └─ local ─┘ └─ VPS ─┘
```

## Notas

- T5-T7 son verificables en máquina local sin dominio (cert provisional).
- T8 es la primera task que exige un VPS real con hostname público, porque Let's Encrypt debe alcanzarlo por HTTP.
- T10 es la prueba de reproducibilidad; si el runbook falla ahí, el fix pertenece al runbook (no a la infra).
