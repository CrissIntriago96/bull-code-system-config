# BullCodeSystemConfig
Repositorio centralizado de archivos de configuración `.yml` para los servicios de
`bull-code-system-backend`, pensado para servirse con Spring Cloud Config Server.

## Cómo resuelve el Config Server

Para un servicio `{application}` con perfil `{profile}`, el Config Server combina (de mayor a menor prioridad):

1. `{application}-{profile}.yml` — ej. `rrhh-backend-prod.yml`
2. `{application}.yml` — ej. `rrhh-backend.yml`
3. `application-{profile}.yml`
4. `application.yml` — global, lo reciben TODOS los servicios

| Servicio        | `spring.application.name` | Perfiles              |
|-----------------|---------------------------|-----------------------|
| Backend RRHH    | `rrhh-backend`            | `dev`, `docker`, `prod` |
| API Gateway     | `api-gateway`             | (sin perfil), `docker`, `prod` |
| Eureka Server   | `eureka-server`           | (sin perfil), `docker`, `prod` |

## Reglas

- **Ningún secreto en texto plano.** Los secretos se escriben como `${VARIABLE}` y el
  cliente los resuelve con sus propias variables de entorno. En `prod` van sin default:
  si falta la variable, el servicio no arranca.
- **`application.yml` solo lleva lo que es seguro compartir con todos.** El secreto del
  JWT (HS256) vive únicamente en `rrhh-backend*.yml`: con ese secreto cualquier servicio
  podría firmar tokens.
- Quedan en el `application.yml` local de cada servicio: `spring.application.name`,
  `spring.profiles.default` y `spring.config.import` (el cliente los necesita antes de
  hablar con el Config Server).

## Estado

Todavía no existe el Config Server ni los servicios tienen `spring-cloud-starter-config`:
hoy cada servicio lee su configuración de `src/main/resources`. Hasta migrar, este repo
es un espejo y cualquier cambio hay que hacerlo en los dos lados.
