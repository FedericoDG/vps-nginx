# RUNBOOK — Reconstrucción desde VPS limpio (Etapa 1)

**Spec base:** `spec.md` v1.1 · **Plan base:** `plan.md` v1.0
**Principio:** cada fase termina con una verificación. Si un paso requiere "memoria" fuera del repo, es un bug del runbook y debe corregirse aquí.

---

## Fase 0 — Provisionamiento del VPS (manual, no versionado como código)

> Esta fase no produce archivos en el repo, pero está versionada como checklist porque es parte de RNF1.

- [ ] VPS con IPv4 estática y acceso SSH por clave.
- [ ] Docker y Docker Compose instalados (seguir la documentación oficial de Docker para la distro del VPS).
- [ ] Firewall del VPS / grupo de seguridad: solo puertos `22` (SSH), `80` (HTTP) y `443` (HTTPS) abiertos al exterior. Política default-deny para el resto.

**Verificación Fase 0:**
```bash
docker --version
docker compose version
sudo ss -tlnp | grep -E ':80|:443'   # antes del deploy, libres
# Desde otra máquina:
nmap -Pn <ip-vps>   # solo 22, 80, 443 visibles
```

---

## Fase 1 — DNS: hostname DuckDNS (manual, en el panel)

- [ ] Crear cuenta en DuckDNS y registrar un hostname (ej. `binario`).
- [ ] En el panel de DuckDNS, configurar el A-record del hostname para que apunte a la IPv4 estática del VPS. **Una sola vez** (no hay cliente DDNS con IP estática).
- [ ] Esperar propagación DNS (segundos a pocos minutos).

**Verificación Fase 1:**
```bash
dig binario.duckdns.org +short        # → IP del VPS
# o:
host binario.duckdns.org
nslookup binario.duckdns.org
```

> El token de DuckDNS permanece solo en la cuenta; no se almacena en el sistema. El hostname se mantiene vivo por el uso continuo; no requiere cadencia de update con IP estática.

---

## Fase 2 — Bootstrap del repositorio en el VPS

- [ ] Clonar el repositorio en el VPS:
  ```bash
  git clone <url-del-repo> vps-nginx
  cd vps-nginx
  ```
- [ ] Verificar que el tag de imagen en `docker-compose.yml` coincide con lo versionado (imagen mainline con `nginx-module-acme`, tag pinneado — ver `plan.md` P1).

**Verificación Fase 2:**
```bash
git status          # limpio
ls -R               # estructura coincide con plan.md §2
docker compose config   # valida el compose sin levantar nada
```

---

## Fase 3 — Primer arranque (arranque en frío)

> Fase delicada: NGINX levanta el listener 443 sin certificado previo; el módulo ACME debe obtenerlo contra Let's Encrypt. Es la fuente principal de hallazgos reales.

- [ ] Levantar el stack:
  ```bash
  docker compose up -d
  docker compose ps
  ```
- [ ] Observar los logs del módulo ACME durante la obtención inicial:
  ```bash
  docker compose logs -f nginx
  # Buscar: issuance / ACME / certificate obtained
  docker compose exec nginx nginx -t
  ```

**Verificación Fase 3:**
```bash
curl -sI http://binario.duckdns.org/    # → 301 Location: https://...
curl https://binario.duckdns.org/       # → 200 con placeholder (RF2), cert válido (RF7)
# Si se usó staging en T8:
# curl -k https://binario.duckdns.org/  # cert de staging, issuer = Fake LE
```

> Nota de implementación: T7 usa un cert provisional/self-signed para verificación local sin dominio; T8 cambia el issuer a staging de LE y T9 a producción. En VPS limpio el primer arranque ya va contra LE (ver `tasks.md` T8–T9).

---

## Fase 4 — Verificación de vida (smoke checks)

- [ ] Placeholder servido por HTTPS y accesible desde navegador en `https://<hostname>`.
- [ ] Logs observables:
  ```bash
  docker logs nginx --tail 20
  # Debe mostrar líneas de access con método, path y código
  ```
- [ ] Red y exposición:
  ```bash
  docker port vps-nginx-nginx-1   # o nombre del servicio
  # Solo 80->80 y 443->443 (C1, RF1)
  docker network inspect vps-nginx_vps-net  # lista a nginx (C2)
  ```

**Verificación Fase 4:**
```bash
curl -sI http://binario.duckdns.org/ | head -n1   # 301
curl -s https://binario.duckdns.org/ | grep -i "nginx\|funcionando\|placeholder"
docker logs nginx 2>&1 | tail
```

---

## Fase 5 — Verificación de renovación (post-deploy)

- [ ] Verificar que la renovación automática está operativa. El módulo ACME renueva según la ARI de LE y el `state_path` persistente en el volumen nombrado.
- [ ] Ejecutar la verificación documentada del módulo (dry-run / inspección de estado):
  ```bash
  docker compose exec nginx ls -R /var/cache/nginx/acme  # state_path (ajustar según config)
  docker compose logs nginx | grep -i "renew\|acme"
  # En el módulo nativo la renovación se valida observando el estado y forzando
  # un check contra staging si se requiere (ver plan.md P1).
  ```

**Verificación Fase 5:**
- Logs indican próximo ciclo de renovación programado.
- Volumen `acme-state` persiste tras `docker compose down && docker compose up -d`.

> Hallazgos de T9 (2026-10-02):
> - **Setear staging/producción NO re-emite** si hay cert vigente en el estado: para cambiar de issuer, resetear el volumen (`docker compose down && docker volume rm acme-state && docker compose up -d`) y dejar re-bootstrapear la cuenta/cert. Cuenta de staging es independiente de la de producción.
> - La renovación es interna al módulo (ARI sobre el `state_path`); no hay comando de dry-run observable. Verificación práctica: archivos `*.crt/key` en el volumen, `docker logs | grep -i acme` cerca del expiry, y re-emisión automática demostrada cuando el estado está vacío.
> - Tras `git pull` que cambie archivos montados bind por archivo (nginx.conf), hacer `docker compose down && up -d`: los mount siguen al inodo viejo.

---

## Notas de repetibilidad

- El mismo checklist desde un VPS limpio debe pasar completo. Si un paso requiere un detalle "de memoria" no escrito aquí, es un bug del runbook: corregirlo y commitear el fix pertenece a esta fase (T10 en `tasks.md`).
- Cambios de `spec.md`/`plan.md` se reflejan aquí antes de tocar `docker-compose.yml` o `nginx/`.

## Checklist compacto (para copiar en PRs/issues)

```
- [ ] Fase 0: VPS + Docker + firewall 22/80/443
- [ ] Fase 1: DuckDNS A-record → IP VPS (dig OK)
- [ ] Fase 2: git clone + docker compose config OK
- [ ] Fase 3: compose up + ACME issuance (logs) + curl 301/200
- [ ] Fase 4: placeholder en navegador + docker logs + port/network
- [ ] Fase 5: renovación verificada + volumen persiste tras down/up
```
