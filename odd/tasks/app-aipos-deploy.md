# Desplegar POS Online (sistemapos-web) en app.aipos.com.ar

Objetivo: publicar el POS Online (React + Node) en `https://app.aipos.com.ar`
sobre el mismo VPS, con deploy automático al pushear a `main`.

Repos afectados: **`vps-nginx`** (vhost + cert) y **`sistemapos-web`**
(empaquetado, compose y CI).

## Specs

- **S1** — El POS Online se sirve en `https://app.aipos.com.ar/` (raíz, sin prefijo de path).
  El certificado es ACME/Let's Encrypt, emitido por el módulo nativo de nginx.
- **S2** — La API del POS Online se sirve en `https://app.aipos.com.ar/api/`.
  El backend tiene todas sus rutas bajo `/api/` (ver `backend/src/index.ts`), así que
  el prefijo se preserva sin rewrite.
- **S3** — Web y API comparten origen. El build del frontend **no** debe hornear
  `BACKEND_URL` ni `VITE_API_URL`: vacías ⇒ llamadas relativas ⇒ sin CORS.
  Si se hornea `http://localhost:4100`, el panel admin queda roto en producción.
- **S4** — nginx envía la IP real del cliente al backend en `X-Forwarded-For`,
  **reemplazando** el valor del cliente (no agregando). El backend corre con
  `trust proxy = 1` y sus rate limiters keyean por `req.ip`; si se agregara,
  cualquiera podría inventar su IP y saltearse los límites.
- **S5** — `/api/pos/stream/...` es SSE: el proxy necesita `proxy_buffering off` y
  timeout largo, o el stream se corta.
- **S6** — Push a `main` en `sistemapos-web` despliega solo, y **solo si la suite
  de pruebas pasó**. Los secretos de la app viven en el VPS, no en GitHub.
- **S7** — `aipos.com.ar`, `/admin` y `/api/` (POS Offline) no se tocan.

## Tasks

- [x] T1 — Vhost `app.aipos.com.ar` en `vps-nginx` (`nginx/conf.d/40-app-aipos.conf`). Validado con `nginx -t`.
- [x] T2 — Empaquetado en `sistemapos-web`: `.dockerignore`, `backend/Dockerfile`,
      `frontend/Dockerfile`, `frontend/nginx.conf`.
- [x] T3 — `compose.prod.yml` + `deploy.sh` (ejecutable) en `sistemapos-web`. YAML validado.
- [x] T4 — `.github/workflows/deploy.yml` (deploy tras pruebas verdes). YAML validado.
- [x] T5 — Variables de producción documentadas en `deploy/env/README.md`
      (el `.example` no se pudo crear por la regla de permisos `*.env*`, y no hace falta).
- [ ] T6 — Prerrequisitos manuales en Cloudflare/VPS + verificación en vivo. Pendiente del usuario.

## Evidencia

- `nginx -t` con `nginx:1.29-alpine` y el vhost 40 incluido: **syntax ok**.
- `compose.prod.yml` y `.github/workflows/deploy.yml`: YAML válido (PyYAML).
- Alias en `vps-net`: `onlinepos-backend` y `onlinepos-web` (únicos).
- `.gitignore`: verificado que `deploy/env/backend.env` queda ignorado y
  `deploy/env/backend.env.example` se puede versionar. **Sin la línea agregada,
  el `.env` de producción con la cadena de Neon entraba al repo** (el patrón `.env`
  no matchea `backend.env`).
- **DNS `app.aipos.com.ar`: NXDOMAIN** al momento del trabajo. Sin ese registro el
  módulo ACME no puede emitir el certificado.

## Prerrequisitos manuales (bloquean el deploy)

1. **Cloudflare**: A `app.aipos.com.ar` → `157.173.98.54`, en modo **Solo DNS (gris)**.
   Sin esto el módulo ACME no puede emitir el certificado. Verificado: hoy da NXDOMAIN.
2. **GitHub** (repo `sistemapos-web`): `SSH_PRIVATE_KEY` (Secret) y `SSH_HOST` (Variable).
3. **VPS**: clonar el repo en `/root/apps/sistemapos-web` y crear
   `deploy/env/backend.env` a partir de `deploy/env/backend.env.example`.

## Log

**L1** — "Ya está hecho, ahora lo que quiero en que cada vez que se pushea a main se
despliegue solo en el vps. Ademas hay que hacer todos los cambios necesarios en el repo
de vps-nginx, etc etc. Arrancá"
