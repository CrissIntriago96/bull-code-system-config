// ─────────────────────────────────────────────────────────────────────────────
//  RRHH — pipeline de CONFIGURACIÓN (bull-code-system-config) · servidor Rocky Linux 9
//
//  Los servicios leen su configuración del Config Server solo al ARRANCAR. Este
//  job hace que un push a main llegue a producción: valida la configuración y
//  reinicia solo los servicios a los que les cambió.
//
//    checkout → lint → config-server sirve el commit → [candado] variables → reinicio + smoke test
//
//  No buildea ni cambia imágenes: reinicia los contenedores que ya desplegaron los
//  jobs de bull-code-system-backend, con la misma imagen, para que relean su config.
//  No hay rollback automático, y el ":prev" de los jobs del backend no sirve (la
//  imagen vieja leería la misma configuración): si un servicio no levanta, queda
//  caído hasta que se pushee el "git revert", y el build siguiente lo reinicia.
//
//  La lógica vive en jenkins/. Configuración del job: README.md, "Pipeline".
// ─────────────────────────────────────────────────────────────────────────────

pipeline {
    agent { label 'app-prod' }

    triggers {
        pollSCM('H/3 * * * *')
    }

    parameters {
        choice(name: 'RESTART',
               choices: ['auto', 'todos', 'ninguno', 'common-service', 'api-gateway', 'notification-service'],
               description: 'auto: reinicia los servicios cuya configuración cambió. todos / uno: fuerza el reinicio. ninguno: solo valida.')
    }

    options {
        disableConcurrentBuilds()
        skipDefaultCheckout()
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    environment {
        SCRIPTS = 'jenkins'
    }

    stages {
        stage('Checkout') {
            steps {
                script {
                    def scmVars = checkout scm
                    env.COMMIT = scmVars.GIT_COMMIT
                    def shortCommit = env.COMMIT.substring(0, 12)

                    // En el primer build los parámetros todavía no existen: vale "auto".
                    def restart = params.RESTART ?: 'auto'
                    def allApps = sh(returnStdout: true, script: '. "$SCRIPTS/common.sh" && echo "$APPS"').trim()

                    if (restart == 'auto') {
                        // Contra el último exitoso Y el último a secas: un revert de un push
                        // que rompió un servicio igual lo reinicia (ver affected.sh).
                        def bases = ''
                        for (base in [scmVars.GIT_PREVIOUS_SUCCESSFUL_COMMIT, scmVars.GIT_PREVIOUS_COMMIT]) {
                            if (base) { bases += " '${base}'" }
                        }
                        env.AFFECTED = sh(returnStdout: true,
                                script: "bash \"\$SCRIPTS/affected.sh\" '${env.COMMIT}'${bases}").trim()
                    } else if (restart == 'todos') {
                        env.AFFECTED = allApps
                    } else if (restart == 'ninguno') {
                        env.AFFECTED = ''
                    } else {
                        env.AFFECTED = restart
                    }

                    currentBuild.description = env.AFFECTED
                            ? "reinicia: ${env.AFFECTED} · ${shortCommit}"
                            : "solo validación · ${shortCommit}"
                }
            }
        }

        stage('Lint') {
            steps {
                sh 'bash "$SCRIPTS/lint.sh"'
            }
        }

        stage('Config Server') {
            steps {
                script {
                    // Con servicios para reiniciar, sin Config Server no arrancarían: es obligatorio.
                    def required = env.AFFECTED ? '--required' : ''
                    sh "bash \"\$SCRIPTS/served.sh\" \"\$COMMIT\" ${required}"
                }
            }
        }

        // Candado compartido con los jobs de los servicios y del frontend: a producción
        // entra uno por vez, así un reinicio nunca se cruza con un deploy.
        stage('Producción') {
            when { expression { (env.AFFECTED ?: '').trim() != '' } }
            options { lock(resource: 'rrhh-prod-deploy') }
            stages {
                stage('Variables de entorno') {
                    steps {
                        script {
                            for (app in env.AFFECTED.tokenize(' ')) {
                                sh "bash \"\$SCRIPTS/env-check.sh\" ${app}"
                            }
                        }
                    }
                }

                // Uno por vez y en orden: si uno no levanta, los siguientes quedan con
                // la configuración anterior en vez de caerse todos juntos.
                stage('Reinicio') {
                    steps {
                        script {
                            for (app in env.AFFECTED.tokenize(' ')) {
                                env.CURRENT_APP = app
                                sh "bash \"\$SCRIPTS/restart.sh\" ${app}"
                                sh "bash \"\$SCRIPTS/smoke-test.sh\" ${app}"
                            }
                            env.CURRENT_APP = ''
                        }
                    }
                }
            }
        }
    }

    post {
        failure {
            script {
                sh "bash \"\$SCRIPTS/diagnose.sh\" ${env.CURRENT_APP ?: ''} || true"
                if (env.CURRENT_APP) {
                    // El rollback a :prev de los jobs del backend NO sirve acá: la imagen vieja
                    // leería la misma configuración rota.
                    echo "${env.CURRENT_APP} no levantó con la configuración nueva y QUEDA CAÍDO hasta que se pushee el revert: " +
                         "git revert ${env.COMMIT} && git push. El build siguiente lo reinicia con la versión anterior. " +
                         "Los servicios que venían después en el orden no se tocaron."
                }
            }
        }
    }
}
