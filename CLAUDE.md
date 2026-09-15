# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Qué es

Repositorio de configuración (backend git de Spring Cloud Config) para los servicios de `bull-code-system-backend`: `common-service`, `api-gateway` y `notification-service`. Contiene los YAML y el pipeline de Jenkins que los aplica en producción (`Jenkinsfile` + `jenkins/*.sh`). Sigue la convención de `taurus-config` (otro repo del mismo autor), pero sin replicar sus secretos en texto plano. Todo el repo (comentarios, docs) está en español.

## Comandos

```bash
bash jenkins/lint.sh                             # nombres de archivo + secretos en texto plano (corre en Git Bash)
bash jenkins/affected.sh <commit> <base>...      # qué servicios reiniciaría un push (necesita historial de git)
```

El resto de `jenkins/` (`served.sh`, `env-check.sh`, `restart.sh`, `smoke-test.sh`) solo corre en el servidor de producción: usa los stacks de `/opt/app/<servicio>`.

## Estado: fuente de verdad

`common-service`, `api-gateway` y `notification-service` son clientes del Config Server. Su `application.yml` local solo tiene `spring.application.name`, `spring.profiles.default` (backend) y el bootstrap del cliente: `spring.config.import=configserver:…` sin `optional:`, credenciales `CONFIG_SERVER_USERNAME`/`PASSWORD`, `fail-fast` y retry. No tienen `application-{perfil}.yml` locales. **Toda su configuración vive acá**: si una property falta en este repo, el servicio no la tiene.

- **Config Server** (`config-server/` en el backend, puerto 8888, HTTP Basic). Con el perfil `native` (local) lee esta carpeta tal cual, commiteada o no: el compose la monta en `/config-repo` y con `mvn` se pasa `CONFIG_NATIVE_LOCATION=file:///C:/ruta/a/bull-code-system-config/` (la barra final importa). En `prod` clona el repo por git y sirve **solo lo commiteado y pusheado a `main`**: el push tiene que ir antes que el deploy de un servicio que dependa del cambio.
- Los servicios leen la configuración al arrancar (no hay `/actuator/refresh`): un cambio se aplica reiniciándolos. En prod lo hace el pipeline de este repo.
- **Sin cliente:** `eureka-server` (es infraestructura raíz y el Config Server se registra en él: si dependiera del Config Server, reiniciar Eureka con el Config Server caído tiraría el discovery) y `config-server` (su configuración, la URI de este repo y el token para leerlo, tiene que existir antes de poder leerlo). La config de ambos vive en su `src/main/resources`: ninguno de los dos tiene archivos acá, y no hay que agregárselos.

## Cómo se arman los archivos

El Config Server combina, de mayor a menor prioridad: `{application}-{profile}.yml` → `application-{profile}.yml` → `{application}.yml` → `application.yml`. Son las reglas de Spring Boot: un archivo de perfil siempre le gana a uno sin perfil, aunque sea global. Por eso un `application-prod.yml` pisaría a `common-service.yml` (hoy no existe ninguno). El nombre que se pide es el `spring.application.name` del cliente.

- **`application.yml` (global) lo recibe TODO servicio.** Solo lleva lo que es seguro compartir (`server.shutdown`, `management`). Es la ÚNICA fuente de `management.endpoint.health.probes.enabled` para los tres clientes: sin eso no existe `/actuator/health/readiness`, que es lo primero que pide el `smoke-test.sh` de cada deploy. El secreto del JWT (HS256) va únicamente en `common-service*.yml`: la gateway no debe recibirlo, porque con ese secreto cualquier servicio podría firmar tokens. Esto difiere a propósito de `taurus-config`, que pone el JWT en el global.
- **Perfiles.** `common-service` usa `dev` (híbrido: Spring local, DB y Mailpit en `localhost`), `docker` (hosts = nombres de servicio de compose, `prefer-ip-address: true`) y `prod`. `api-gateway` y `notification-service` no tienen `dev`: su archivo base (sin perfil) ES la configuración de desarrollo local.
- **Secretos.** Siempre como `${VARIABLE}`, que el cliente resuelve con sus propias variables de entorno. En `*-prod.yml` van sin default para que el servicio no arranque si falta uno (fail fast). Los defaults de `dev`/`docker` son solo para desarrollo local.
- **Lo que NO va acá:** `spring.application.name`, `spring.profiles.default`, `spring.config.import` y `spring.cloud.config.*` (credenciales, `fail-fast`, retry). El cliente los necesita antes de hablar con el Config Server, así que quedan en su `application.yml` local.

## Pipeline

El README ("Pipeline") tiene las etapas, el alta del job y la operación. Lo que no se ve leyendo un solo archivo:

- **No despliega código.** Recrea con la misma imagen (`up --no-deps --no-build --force-recreate`) los contenedores que levantaron los jobs de `bull-code-system-backend`, para que relean su config. `--no-deps` queda como buena práctica: el reinicio toca solo ese servicio, nunca sus dependencias (PostgreSQL ya es su propio stack en el backend, `postgres/`, job `bull-code-postgres`).
- **`jenkins/common.sh` (`service_info`) duplica datos del backend:** carpeta del stack (`/opt/app/<servicio>`), servicio en compose, puerto y smoke test de cada app (ej. `common-service`: `/opt/app/common-service`, servicio `common-service`, 8080, `/api/auth/session` → 401). Tienen que coincidir con el `Jenkinsfile` y el `docker-compose.prod.yml` de cada servicio allá. Si cambian allá (un puerto, por ejemplo), cambian acá. `APPS` define también el orden de reinicio (`notification-service` → `common-service` → `api-gateway`).
- **El smoke test del job del config-server (en el backend) pide `/common-service/prod`.** Renombrar o borrar los `common-service*.yml` acá rompe también ese deploy, no solo el del backend.
- **`affected.sh` compara contra DOS bases** (último build exitoso y último build). Con una sola, el revert de un push que tiró un servicio da un diff neto vacío y el servicio queda caído.
- **`served.sh` usa el commit como label** (`/<app>/<perfil>/<commit>`) y corre dentro del contenedor del config-server con sus propias credenciales: nada de eso pasa por Jenkins.
- **`lint.sh` exige que todo `.yml` de la raíz sea de una app de `APPS` o global.** Un servicio nuevo se suma a `APPS` y `service_info`, o el lint rechaza sus archivos.
- Sin rollback automático: si un servicio no levanta, queda caído hasta el `git revert` + push.

## Convenciones que dependen del backend

- Gateway: prefijo nuevo `spring.cloud.gateway.server.webflux.*` (el viejo `spring.cloud.gateway.*` está deprecado y no se aplica). La ruta comodín `/api/** → common-service` (su dirección es `rrhh.gateway.services.common-service` = `${COMMON_SERVICE_URI:…}`, `lb://common-service` con Eureka) tiene `order: 1000`, así que un servicio nuevo suma su ruta en `api-gateway.yml` con un order menor y `uri: lb://<spring.application.name>`. El discovery locator queda apagado: toda ruta es explícita.
- Cada ruta de la gateway lleva su filtro `CircuitBreaker` (con `name` = el servicio) y su instancia en `resilience4j.circuitbreaker.instances`. El filtro exige la dependencia `spring-cloud-starter-circuitbreaker-reactor-resilience4j` en la imagen de la gateway: es la excepción a "primero la propiedad". Primero se despliega la gateway y después se pushea el filtro; al revés, no arranca. Las instancias `resilience4j.*` de common-service y notification-service sí son compatibles en cualquier orden (sin ellas se usan los defaults de Resilience4j).
- `management.health.circuitbreakers.enabled: false` vive en el global y no se enciende: un circuito abierto marcaría DOWN al servicio (healthcheck de Docker, Eureka y el smoke test).
- `notification-service` es interno: NO lleva ruta en `api-gateway.yml` (expuesto, cualquiera mandaría correos desde el dominio oficial). El backend lo llama con `rrhh.notification.*`: `mode` (`remote` | `smtp`, y `prod` sigue en `smtp` hasta migrar) y las mismas credenciales HTTP Basic que el servicio define en `spring.security.user.*`.
- Eureka exige HTTP Basic. Los clientes llevan las credenciales embebidas en `EUREKA_URI`. En `prod`, los clientes se registran con `eureka.instance.hostname` igual al nombre del servicio en compose, no con `prefer-ip-address`, porque tienen varias redes.
- Un servicio nuevo suma sus propios `{nombre}.yml` / `{nombre}-{perfil}.yml`, una fila en la tabla del `README.md` y su entrada en `APPS` / `service_info` de `jenkins/common.sh`.
- Orden entre repos: una propiedad nueva va primero acá (compatible con el código viejo) y después el código; una variable de entorno nueva va primero al `.env` y al compose del servicio (deploy del servicio) y después acá.
- `.gitattributes` fuerza LF: los scripts de `jenkins/` corren en Linux.
