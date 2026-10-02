# SPEC — Etapa 1: NGINX base en VPS Dockerizado

**Versión:** 1.1 · **Estado:** cerrada · **Fecha:** 2026-10-01
**Alcance:** construir únicamente la infraestructura base `VPS → Docker → NGINX` como punto de entrada público. Sin aplicaciones detrás todavía.

---

## 1. Objetivo de etapa

Tener en el VPS un punto de entrada HTTP→HTTPS servido por NGINX en Docker, con:

- configuración versionada y montada desde el repositorio,
- TLS con renovación automática vía Let's Encrypt,
- logs observables vía Docker,
- reconstrucción documentada desde un VPS limpio.

Sin aplicaciones detrás todavía. Todo aquello que necesite una aplicación real para verificarse pertenece a etapas posteriores.

---

## 2. Contratos de infraestructura (heredables por etapas futuras)

| ID | Contrato | Qué establece | Verificación |
|----|----------|---------------|--------------|
| C1 | **Exposición** | Únicos puertos publicados al host: `80` y `443`, exclusivamente por el servicio NGINX. Ningún otro contenedor publica puertos. | `docker port <cada_contenedor>` solo muestra 80/443 en `nginx`. Desde fuera, solo 80/443 responden. |
| C2 | **Red** | NGINX corre en una red Docker dedicada con nombre propio (no la `default`). Contenedores futuros se suman a esa red sin publicar puertos. | `docker network inspect <red>` lista a NGINX; contenedores futuros resuelven por nombre dentro de la red. |
| C3 | **Volúmenes** | La configuración de NGINX se monta desde el repo al contenedor (solo lectura). El estado ACME (account key + certificados) vive en un volumen nombrado persistente, nunca en la imagen ni versionado. Nada útil vive solo dentro del contenedor. | `docker compose down && docker compose up -d` no pierde config ni certs. El repo es la fuente de verdad de la config. |

---

## 3. Requisitos de etapa

Cada requisito sigue la tríada **qué / por qué / cómo se verifica**.

### RF1 — NGINX en Docker como único punto de entrada

- **Qué:** NGINX corre como contenedor Docker y es el único servicio expuesto públicamente.
- **Por qué:** superficie única y controlada; base para etapas futuras.
- **Verificación:** `docker ps` muestra `nginx` en ejecución; `docker port nginx` mapea `80->80` y `443->443` y nada más.

### RF2 — Placeholder de vida

- **Qué:** mientras no haya aplicaciones detrás, NGINX sirve una página placeholder simple que indica claramente que el servicio está funcionando. Es una página estática servida por NGINX, no un `return` inline.
- **Por qué:** el "vacío" también es comportamiento; es el smoke test que valida todo el stack (red, montaje de config, TLS) sin depender de apps.
- **Verificación:** `curl -k https://localhost` (local) y `curl https://<hostname>` (VPS) devuelven `200` con el contenido identificador del placeholder. Navegador muestra la página.

### RF3 — HTTP → HTTPS obligatorio

- **Qué:** todo tráfico en puerto `80` redirige con `301` a `https://`.
- **Por qué:** cifrado; requisito del challenge HTTP-01 de Let's Encrypt (que necesita servir el puerto 80).
- **Verificación:** `curl -sI http://<hostname>` devuelve `301` con header `Location: https://...`. El path `/.well-known/acme-challenge/` queda excluido del redirect y es servido por el módulo ACME.

### RF4 — Configuración organizada y versionada

- **Qué:** la configuración de NGINX vive en el repositorio bajo `nginx/`, dividida por concern (`conf.d/` por vhost, `snippets/` para parámetros compartidos), y se monta al contenedor en solo lectura.
- **Por qué:** reproducibilidad; nada de estado mágico solo en el VPS.
- **Verificación:** `nginx -t` valida la config del repo; editar la config en el VPS fuera del repo no persiste (la fuente es el repo, se verifica con `git status`).

### RF5 — Flujo de modificación y recarga

- **Qué:** el ciclo documentado es `editar → nginx -t → reload` (recarga sin reinicio: los workers se reemplazan sin cortar conexiones). Nunca `restart` salvo cambio de imagen.
- **Por qué:** cambio seguro y repetible.
- **Verificación:** aplicar un cambio benigno siguiendo el flujo y comprobar que se refleja sin caída (`curl` continuo o `docker logs` sin reinicio del contenedor principal).

### RF6 — Logs a stdout/stderr

- **Qué:** access log y error log de NGINX al output del contenedor.
- **Por qué:** observabilidad con `docker logs`, cero volúmenes de log en v1.
- **Verificación:** `docker logs <nginx>` muestra accesos reales con método, path y código de respuesta.

### RF7 — TLS con Let's Encrypt y renovación automática

- **Qué:** certificado válido por hostname, obtención y renovación sin intervención manual vía módulo ACME nativo (ver P1). Un solo certificado para el hostname de etapa 1.
- **Por qué:** los certs expiran a 90 días; renovación manual es el requisito que tira sitios a los 2 meses.
- **Verificación:** logs del contenedor muestran issuance exitoso; `curl https://<hostname>` sin `-k` valida contra CA de confianza; renovación verificada con el mecanismo del módulo (dry-run / comprobación de estado en volumen).

### RF8 — Hostname DuckDNS

- **Qué:** un hostname DuckDNS (ej. `binario.duckdns.org`) con su A-record apuntando a la IPv4 estática del VPS, configurado una vez en el panel de DuckDNS. Sin cliente DDNS en el sistema (no es necesario con IP estática).
- **Por qué:** nombre estable y gratuito para el VPS.
- **Verificación:** `dig <hostname>` (o `nslookup`/`host`) resuelve a la IP pública del VPS. La configuración es manual en el panel; el token de DuckDNS permanece solo en la cuenta, no en el sistema.

### RNF1 — Reconstrucción desde cero

- **Qué:** con el repositorio + runbook documentado, un VPS limpio llega al estado completo de esta etapa siguiendo solo pasos versionados.
- **Por qué:** es la política de rollback de v1 y el anti-magia: nada vive solo en el servidor.
- **Verificación:** ejecutar el runbook paso a paso en VPS nuevo (o VM local limpia) y alcanzar estado completo (placeholder HTTPS funcionando + renovación verificable).

---

## 4. Decisiones con estado

### 4.1 Tomadas

| ID | Decisión | Razonamiento |
|----|----------|--------------|
| D1 | Routing por hostname (para etapas futuras) con config estática | Cada app = vhost propio. Agregar app = archivo nuevo, no tocar lo existente. |
| D2 | Sin NGINXes secundarios en apps | Un NGINX extra por app es otro punto de parcheo sin beneficio a esta escala. |
| D3 | Challenge HTTP-01 para LE | Requiere puerto 80 abierto — ya exigido por RF3. Sin wildcard en v1. |
| D4 | `nginx -t` + reload (no restart) | Reload reemplaza workers sin cortar conexiones. |
| D5 | Logs a stdout/stderr | Observabilidad sin volúmenes. |
| D6 | Placeholder servido por NGINX desde `nginx/static/` | Artefacto verificable separado de la config; smoke test independiente de apps. |

### 4.2 Superseded (registradas, no borradas)

| ID | Antes | Ahora | Motivo |
|----|-------|-------|--------|
| S1 | Routing por hostname-per-app (un DuckDNS por app) | Un solo hostname + path-routing (concepto aplazado a etapa 2) | Limitación DuckDNS: sin sub-subdominios como A-records, 5 hostnames gratis; más tarde dominio propio con CNAME. |
| S2 | RF8 con cliente DDNS y token en el sistema | RF8-v2 sin cliente (IP estática) | VPS con IPv4 estática: A-record configurado una vez en panel. |

### 4.3 Pendientes de verificar al implementar

| ID | Tema | Dónde se resuelve |
|----|------|-------------------|
| P3 | Límites de tasa de Let's Encrypt para hostnames DuckDNS (PSL) | T8 en staging (verificación empírica + `crt.sh`). |
| — | Comportamiento exacto del primer arranque ACME sin cert previo (Fase 3 del runbook) | T7→T8 (logs del módulo). |
| — | Mecanismo exacto de dry-run de renovación del módulo ACME | T9. |

> Nota: P1 (mecanismo TLS) y P4 (expiración DuckDNS) ya cerradas — ver `plan.md`.

### 4.4 Aplazadas a etapa 2 (explícitamente sin requisitos hoy)

Routing definitivo de apps (path vs hostname final con dominio propio), frontend, backend, Next.js/Express, `basePath`, `/api`, cantidad de apps, WebSockets/SSE.

---

## 5. Fuera de alcance — Etapa 1

- Wildcard certificates
- Auto-discovery / proxy dinámico
- Backups de volúmenes / estrategia de recuperación compleja
- Dominio propio (registrado como evolución documentada)
- Más de un VPS / contenedores remotos
- Fail2Ban, rate limiting, analíticas
- Cliente DDNS en el sistema
- IPv6

---

## 6. Criterios de aceptación de etapa

La etapa se considera completa cuando:

1. `spec.md`, `plan.md`, `tasks.md` y `runbook.md` existen y reflejan este documento.
2. En máquina local: `docker compose up` levanta NGINX, `nginx -t` pasa, placeholder responde por HTTPS (con cert provisional), y HTTP redirige a HTTPS.
3. En VPS real con hostname DuckDNS resuelto: placeholder por `https://<hostname>` con cert LE válido, HTTP→HTTPS operativo, renovación verificable, y runbook ejecutable desde VPS limpio.

Traza: cada criterio remite a un RF/RNF de esta spec (ver §3–4 y `tasks.md`).
