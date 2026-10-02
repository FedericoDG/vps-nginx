# PLAN — Etapa 1: NGINX base en VPS Dockerizado

**Versión:** 1.0 · **Estado:** cerrado · **Fecha:** 2026-10-01
**Spec base:** `spec.md` v1.1

Este documento registra cada decisión técnica con su razonamiento y fallback. Cada decisión puede trazarse a un requisito de `spec.md`.

---

## 1. Decisiones técnicas

### P1 — Mecanismo de obtención y renovación TLS → **módulo ACME nativo de NGINX**

**Opciones investigadas (fuentes: nginx.org/linux_packages, nginx/docker-nginx mainline Dockerfile, letsencrypt.org blog 2025-09-11):**

| Alternativa | Cómo funciona | Ventaja | Desventaja |
|-------------|---------------|---------|------------|
| **A1 Companion (Certbot webroot)** | Segundo contenedor Certbot + webroot compartido + volumen de certs + reload vía señal | Battle-tested, documentación infinita | Dos contenedores, 2 volúmenes compartidos, reload frágil |
| A2 Standalone/cron en host | Certbot `--standalone` abre su servidor en 80 | Simple de invocar | Compite por puerto 80; cron fuera de Docker; contra C3 |
| **A3 Nativo (elegida)** | `ngx_http_acme_module` dentro del propio NGINX; issuer declarado en config; NGINX sirve el challenge, guarda `state_path` y renueva solo | Un contenedor, config declarativa en repo, reload interno | Joven (preview 2025 → v0.4.1 estable 2026), menos tutoriales |
| A4 Caddy / acme.sh | Otros clientes ACME | — | Abandona NGINX (Caddy) o no aporta sobre A1 |

**Decisión:** A3 nativo. Imagen oficial Docker **mainline** incluye `nginx-module-acme` (ver `nginx/docker-nginx` Dockerfile mainline/alpine: `ACME_VERSION 0.4.1`). Paquete `nginx-module-acme` disponible desde NGINX 1.29.1 (`nginx.org/linux_packages`).

**Por qué para este proyecto:**
- Etapa 1 es minimalista (un solo cert): A1 añade complejidad sin valor hoy.
- Alinea con RF4/RF5: cert y routing en el mismo flujo `editar → nginx -t → reload`.
- Reproducibilidad (RNF1): `docker compose up` es todo; sin ordering extra.

**Fallback documentado:** si el módulo falla, migrar a A1 companion (dos contenedores, webroot compartido). El fallback es compatible con C1-C3 y la estructura de `nginx/conf.d/` ya soporta el cambio.

**Suposición resuelta:** HTTP-01 y TLS-ALPN-01 soportados por el módulo; wildcard/DNS-01 no (no necesario — RF7 sin wildcard). Verificado en `nginx/nginx-acme` README.

---

### P2 — Secretos

**Decisión:** único secreto persistente de etapa 1 es el estado ACME (`state_path`) en volumen nombrado. No hay token DuckDNS en el sistema (IP estática — ver P4). Convención de env vars/secrets de apps aplazada a etapa 2.

**Razonamiento:** la account key y claves privadas nunca se versionan; el volumen es la única pieza sensible. Bind-mount `./data/` sería equivalente pero con riesgo de `.gitignore` incorrecto; volumen nombrado hace el error imposible.

---

### P3 — Límites de tasa Let's Encrypt para hostnames DuckDNS

**Estado:** validada en T8 (2026-10-02). Emisión staging exitosa primera-try (tras fix de resolver IPv4-only); sin rate limits. Contacto real configurado (`binariodevlabs@gmail.com`). Para producción (T9) se aplicará el mismo flujo; staging ya validó el hostname + método HTTP-01.

---

### P4 — Vida del hostname DuckDNS

**Decisión:** cerrada por IP estática. El A-record se configura **una vez** en el panel de DuckDNS. No hay cadencia de update ni expiración por inactividad relevante (el uso continuo del hostname lo mantiene vivo). El token permanece solo en la cuenta DuckDNS, no en el sistema.

**Antes:** cliente DDNS con token en el sistema; ahora RF8-v2 sin cliente.

---

## 2. Estructura del repositorio (cerrada)

```
vps-nginx/
├── spec.md
├── plan.md
├── tasks.md
├── runbook.md
├── README.md
├── docker-compose.yml
├── nginx/
│   ├── conf.d/
│   │   ├── 00-acme-and-redirect.conf
│   │   └── 10-placeholder.conf
│   ├── snippets/
│   │   └── tls-params.conf
│   └── static/
│       └── placeholder.html
└── .gitignore
```

### Rationale por pieza (D-E1..D-E8)

| ID | Pieza | Rationale |
|----|-------|-----------|
| D-E1 | Docs en raíz (`spec.md`, `plan.md`, `tasks.md`, `runbook.md`) | En SDD la spec es artefacto de producto, no "docs de apoyo"; visible al abrir el repo. |
| D-E2 | `nginx/conf.d/` en lugar de `sites-available/enabled` | Convención de distro con symlinks = estado en filesystem, incompatible con RF4 (la config versionada ES la config). `conf.d/` es el include oficial de la imagen Docker. |
| D-E3 | Numeración `00-` / `10-` | NGINX incluye alfabéticamente. `00` = listener 80 (ACME + redirect, raíz de la cadena); `10` = placeholder 443. Etapas futuras: `20-app.conf`, etc. |
| D-E4 | `snippets/` desde día cero | Parámetros TLS compartidos en un solo lugar; duplicarlos entre vhosts diverge. Patrón creado con un consumidor. |
| D-E5 | Placeholder en `nginx/static/` | Separar contenido (HTML) de comportamiento (vhost); artefacto verificable independiente. |
| D-E6 | Estado ACME en volumen nombrado | El contenido nunca se versiona; volumen nombrado hace imposible el error de commitear claves. |
| D-E7 | Sin templating envsubst en etapa 1 | Un dominio, versionado literal; parametrizar resuelve un problema que no existe (YAGNI). Revisitada en etapa 2. |
| D-E8 | Imagen: tag mainline pinneado | Reproducibilidad (RNF1); el compose versiona el pin exacto. |

---

## 3. Runbook — referencia

El runbook completo con fases y verificaciones vive en `runbook.md`. Resumen:

- **Fases 0–1**: manuales (VPS + panel DuckDNS) — versionadas como checklist, aunque no sean código.
- **Fases 2–5**: `git clone` → primer arranque (fase delicada: ACME bootstrap sin cert previo) → smoke checks RF2/RF6 → renovación.

Cada fase termina con verificación ligada a un RF/RNF. Si un paso requiere "memoria" fuera del repo, es un bug del runbook.

---

## 4. Matriz de trazabilidad

| Spec | Plan que lo materializa |
|------|-------------------------|
| C1, C2, C3 | `docker-compose.yml` + red/volúmenes |
| RF1 | `docker-compose.yml` (servicio nginx) |
| RF2 | `10-placeholder.conf` + `static/placeholder.html` |
| RF3, RF7 | `00-acme-and-redirect.conf` (ACME nativo + redirect) |
| RF4 | Estructura `nginx/` + montaje RO |
| RF5 | Flujo `nginx -t` + reload (documentado en runbook + compose) |
| RF6 | Config de logs a stdout/stderr en snippets/vhosts |
| RF8 | Runbook fase 1 (panel DuckDNS) |
| RNF1 | Runbook fases 2–5 |

---

## 5. Riesgos y mitigaciones

| Riesgo | Mitigación |
|--------|------------|
| Módulo ACME joven; primer arranque sin cert puede comportarse distinto | T7 con cert provisional local + T8 en staging antes de producción; fallback A1 documentado |
| Imagen mainline avanza rápido | Tag pinneado; cambio de tag es una decisión versionada |
| Rate limits LE en DuckDNS | Staging primero; `crt.sh` antes de producción |

---

## 6. Estado

PLAN cerrado. Próxima fase: `tasks.md` → implementación por tasks T1..T10.
