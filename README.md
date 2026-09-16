# BullCodeSystemConfig
Repositorio centralizado de archivos de configuración `.yml` para los servicios de
`bull-code-system-backend`, pensado para servirse con Spring Cloud Config Server.

## Cómo resuelve el Config Server

Para un servicio `{application}` con perfil `{profile}`, el Config Server combina (de mayor a menor prioridad):

1. `{application}-{profile}.yml` — ej. `common-service-prod.yml`
2. `application-{profile}.yml` — global de ese perfil
3. `{application}.yml` — ej. `common-service.yml`
4. `application.yml` — global, lo reciben TODOS los servicios

Sigue las reglas de Spring Boot: un archivo de perfil SIEMPRE le gana a uno sin perfil,
aunque sea global. Por eso un `application-prod.yml` pisaría lo que diga `common-service.yml`.
Hoy no existe ninguno.

| Servicio        | `spring.application.name` | Perfiles              |
|-----------------|---------------------------|-----------------------|
| Backend RRHH    | `common-service`          | `dev`, `docker`, `prod` |
| Talento Humano  | `rrhh-service`            | `dev`, `docker`, `prod` |
| API Gateway     | `api-gateway`             | (sin perfil), `docker`, `prod` |
| Notificaciones  | `notification-service`    | (sin perfil), `docker`, `prod` |

"Sin perfil" es el perfil `default`: el cliente lo pide cuando no tiene ninguno activo, y
recibe solo `{application}.yml` + `application.yml`. Para la gateway y notification-service
esa es la configuración de desarrollo local.

`eureka-server` y `config-server` no tienen archivos acá: su configuración vive en su
propio `src/main/resources`. El `config-server` necesita saber dónde está este repo, y
con qué token leerlo, antes de poder leerlo. `eureka-server` es infraestructura raíz: el
Config Server se registra en él, así que no puede depender del Config Server para arrancar.

## Reglas

- **Ningún secreto en texto plano.** Los secretos se escriben como `${VARIABLE}` y el
  cliente los resuelve con sus propias variables de entorno. En `prod` van sin default:
  si falta la variable, el servicio no arranca.
- **`application.yml` solo lleva lo que es seguro compartir con todos.** La clave PRIVADA
  del JWT (RS256, `RRHH_JWT_PRIVATE_KEY`) vive únicamente en `common-service*.yml`: con ella
  cualquier servicio podría firmar tokens. Los demás (`rrhh-service`) validan con la clave
  pública del JWKS de common-service (`rrhh.security.jwt.jwk-set-uri`), que no es secreta.
- **Lo que el cliente necesita ANTES de hablar con el Config Server no va acá**: queda en
  el `application.yml` local de cada servicio. Es `spring.application.name`,
  `spring.profiles.default` (common-service y rrhh-service), `spring.config.import` y
  `spring.cloud.config.*` (credenciales, `fail-fast` y retry).

## Estado

Este repo es la **fuente de verdad** de `common-service`, `rrhh-service`, `api-gateway` y
`notification-service`: fuera de lo de la regla anterior, toda su configuración está acá.
Importan el Config Server sin `optional:`, así que sin su configuración no arrancan.

- Local: el Config Server (`config-server/` en el backend, puerto 8888) lee esta
  carpeta con el perfil `native`, commiteada o no.
- `prod`: clona este repo por git y sirve **solo lo commiteado y pusheado a `main`**.
- Los servicios toman la configuración al arrancar: un cambio se aplica reiniciándolos
  (no hay `/actuator/refresh`). En prod lo hace el pipeline (abajo).

## Pipeline (`Jenkinsfile`)

Un push a `main` llega a producción solo. Jenkins revisa el repo cada 3 minutos y:

1. **Lint** (`jenkins/lint.sh`): todo `.yml` de la raíz es de una app conocida o global, y
   ningún secreto está en texto plano.
2. **Config Server** (`jenkins/served.sh`): el config-server de prod sirve cada app × perfil
   de ESE commit (HTTP 200). Un YAML roto se detecta acá, antes de tocar nada.
3. **Variables de entorno** (`jenkins/env-check.sh`): cada `${VAR}` sin default que el
   servicio carga en prod existe en su contenedor. Si el contenedor está caído, no se puede
   verificar: avisa y sigue.
4. **Reinicio** (`jenkins/restart.sh` + `jenkins/smoke-test.sh`): recrea con la misma imagen
   solo los servicios cuya configuración cambió, de a uno y en orden
   (`notification-service` → `common-service` → `rrhh-service` → `api-gateway`), con smoke
   test. `rrhh-service` va después de `common-service` porque valida los tokens con su JWKS. Un cambio en
   `application*.yml` los reinicia a todos. Mientras reinicia, cada servicio no atiende.

No buildea ni cambia imágenes: eso es de los jobs de `bull-code-system-backend`. Comparte
con ellos el candado `app-prod-deploy`, así un reinicio nunca se cruza con un deploy.

### Crear el job

Mismos requisitos de servidor que los jobs del backend (`DEPLOYMENT-PROD.md` del backend,
"1.6 Jenkins"): nodo `app-prod`, usuario `jenkins` en el grupo `docker`,
*Lockable Resources*.

| Campo | Valor |
| --- | --- |
| *New Item* → nombre, tipo **Pipeline** | `bull-code-config` |
| Definition | Pipeline script from SCM |
| SCM | Git: `https://github.com/CrissIntriago96/bull-code-system-config.git` + credencial de solo lectura |
| Branch | `*/main` |
| Script Path | `Jenkinsfile` |

Jenkins registra el polling y los parámetros recién después del primer build: lanzarlo a
mano (*Build Now*). Ese primer build solo valida, no reinicia nada.

> ⚠️ Con este job, **pushear a `main` reinicia servicios de producción**, y los scripts de
> `jenkins/` corren con permisos de `docker` (equivale a root). Protegé la rama `main`.

### Operación

| Acción | Cómo |
| --- | --- |
| Aplicar un cambio | Push a `main`: el pipeline decide solo a quién reiniciar |
| Forzar un reinicio | *Build with Parameters* → `RESTART=todos` (o un servicio) |
| Solo validar | *Build with Parameters* → `RESTART=ninguno` |
| Volver atrás | `git revert <commit>` + push |

**Si un servicio no levanta con la configuración nueva, queda CAÍDO hasta que se pushee el
revert.** El rollback a `:prev` de los jobs del backend no sirve: la imagen vieja leería la
misma configuración rota. El build del revert lo reinicia aunque el diff neto contra el
último build exitoso sea vacío (`jenkins/affected.sh` también compara contra el build
fallido). Los servicios que venían después en el orden no se tocan.

### Orden entre código y configuración

Los dos repos se despliegan por separado, así que cada cambio tiene que funcionar con la
versión que el otro tenga en ese momento:

- **Propiedad nueva que el código necesita:** primero la configuración (el código viejo la
  ignora), después el código.
- **Propiedad que el código deja de usar:** primero el código, después se borra de la
  configuración.
- **Variable de entorno nueva** (`${VAR}` sin default en `*-prod.yml`): primero va al `.env`
  y al `docker-compose.prod.yml` del servicio, y se despliega el servicio. Recién después se
  pushea la configuración que la usa. Si no, `env-check.sh` frena el pipeline.
