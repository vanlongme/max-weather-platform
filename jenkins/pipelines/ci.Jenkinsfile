@Library('max-weather-shared') _

pipeline {
  agent {
    kubernetes {
      defaultContainer 'jnlp'
      yaml '''
apiVersion: v1
kind: Pod
metadata:
  labels:
    job: max-weather-ci
spec:
  serviceAccountName: jenkins-agent
  nodeSelector:
    role: infra
  tolerations:
    - key: role
      operator: Equal
      value: infra
      effect: NoSchedule
  restartPolicy: Never
  containers:
    - name: jnlp
      image: jenkins/inbound-agent:latest-jdk21
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
    - name: node
      image: node:22-bookworm-slim
      command: ["sleep"]
      args: ["infinity"]
      tty: true
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
        limits:
          cpu: 1000m
          memory: 1Gi
    - name: aws
      image: amazon/aws-cli:2.17.16
      command: ["sleep"]
      args: ["infinity"]
      tty: true
      env:
        - name: AWS_REGION
          value: us-east-1
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
    - name: kaniko
      image: gcr.io/kaniko-project/executor:v1.23.2-debug
      command: ["sleep"]
      args: ["infinity"]
      tty: true
      env:
        - name: AWS_SDK_LOAD_CONFIG
          value: "true"
        - name: AWS_EC2_METADATA_DISABLED
          value: "false"
      resources:
        requests:
          cpu: 250m
          memory: 512Mi
        limits:
          cpu: 2000m
          memory: 4Gi
    - name: trivy
      image: aquasec/trivy:latest
      command: ["sleep"]
      args: ["infinity"]
      tty: true
      env:
        - name: AWS_REGION
          value: us-east-1
        - name: AWS_SDK_LOAD_CONFIG
          value: "true"
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
        limits:
          cpu: 1000m
          memory: 1Gi
      volumeMounts:
        - name: trivy-db-cache
          mountPath: /root/.cache/trivy
    - name: gitleaks
      image: zricethezav/gitleaks:latest
      command: ["sleep"]
      args: ["infinity"]
      tty: true
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
    - name: semgrep
      image: semgrep/semgrep:latest
      command: ["sleep"]
      args: ["infinity"]
      tty: true
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
        limits:
          cpu: 1000m
          memory: 2Gi
  volumes:
    - name: trivy-db-cache
      persistentVolumeClaim:
        claimName: trivy-db-cache
'''
    }
  }

  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '15'))
    timeout(time: 30, unit: 'MINUTES')
  }

  environment {
    AWS_REGION = 'us-east-1'
    CLUSTER    = 'poc-max-weather-cluster'
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.GIT_SHA = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
        }
      }
    }

    stage('Resolve ECR Repo') {
      steps {
        container('aws') {
          script {
            env.APP_REPO = sh(returnStdout: true, script: '''
              aws ecr describe-repositories \
                --repository-names poc-max-weather-api-repo \
                --region "$AWS_REGION" \
                --query 'repositories[0].repositoryUri' \
                --output text
            ''').trim()
            env.ECR_HOST = env.APP_REPO.tokenize('/')[0]
            echo "APP_REPO=${env.APP_REPO} ECR_HOST=${env.ECR_HOST}"
          }
        }
      }
    }

    stage('Secret Scan (gitleaks)') {
      steps {
        container('gitleaks') {
          script {
            sh '''
              set +e
              gitleaks detect \
                --source . \
                --config .gitleaks.toml \
                --redact \
                --no-banner \
                --report-format json \
                --report-path gitleaks-report.json \
                --exit-code 1
              GITLEAKS_EXIT=$?
              set -e
              echo "gitleaks exit: ${GITLEAKS_EXIT}"
              echo "${GITLEAKS_EXIT}" > .gitleaks-exit-code
            '''
            def exitCode = sh(returnStdout: true, script: 'cat .gitleaks-exit-code').trim().toInteger()
            if (exitCode != 0 && securityPolicy.blocking('secrets')) {
              error("Secret scan FAILED (blocking mode): findings in gitleaks-report.json")
            } else if (exitCode != 0) {
              catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                error("Secret scan found issues (advisory mode — see gitleaks-report.json)")
              }
            }
          }
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'gitleaks-report.json', allowEmptyArchive: true
        }
      }
    }

    stage('App Lint + Test') {
      steps {
        container('node') {
          sh 'cd app && npm ci && npm run lint && npm test'
        }
      }
      post {
        always {
          junit allowEmptyResults: true, testResults: 'app/junit.xml'
        }
      }
    }

    stage('SAST (semgrep)') {
      steps {
        container('semgrep') {
          script {
            def threshold = securityPolicy.thresholdFor('sast')
            def sevFlags = threshold.split(',').collect { "--severity ${it.trim()}" }.join(' ')
            sh """
              set +e
              semgrep ci \
                --metrics=off \
                --config p/nodejs \
                --config p/owasp-top-ten \
                --config p/javascript \
                --json \
                --output semgrep-report.json \
                ${sevFlags} \
                app/src/
              SEMGREP_EXIT=\$?
              set -e
              echo "semgrep exit: \${SEMGREP_EXIT}"
              echo "\${SEMGREP_EXIT}" > .semgrep-exit-code
            """
            def exitCode = sh(returnStdout: true, script: 'cat .semgrep-exit-code').trim().toInteger()
            if (exitCode != 0 && securityPolicy.blocking('sast')) {
              error("SAST FAILED (blocking mode): findings in semgrep-report.json")
            } else if (exitCode != 0) {
              catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                error("SAST found issues (advisory mode — see semgrep-report.json)")
              }
            }
          }
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'semgrep-report.json', allowEmptyArchive: true
        }
      }
    }

    stage('SCA (npm audit)') {
      steps {
        container('node') {
          script {
            def threshold = securityPolicy.thresholdFor('sca_npm')
            sh """
              set +e
              cd app
              npm ci --prefer-offline
              npm audit \
                --omit=dev \
                --audit-level=${threshold} \
                --json > ../npm-audit-report.json
              NPM_EXIT=\$?
              set -e
              echo "npm-audit exit: \${NPM_EXIT}"
              echo "\${NPM_EXIT}" > ../.npm-audit-exit-code
            """
            def exitCode = sh(returnStdout: true, script: 'cat .npm-audit-exit-code').trim().toInteger()
            if (exitCode != 0 && securityPolicy.blocking('sca_npm')) {
              error("SCA NPM FAILED (blocking mode): findings in npm-audit-report.json")
            } else if (exitCode != 0) {
              catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                error("SCA NPM found issues (advisory mode — see npm-audit-report.json)")
              }
            }
          }
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'npm-audit-report.json', allowEmptyArchive: true
        }
      }
    }

    stage('Build Container Image (local tarball)') {
      steps {
        container('kaniko') {
          sh '''
            set -eu
            # Build image into a workspace tarball — NO push yet.
            # Trivy scans the tarball in the next stage; only on pass does the
            # subsequent push stage re-run kaniko with --cache=true to hit ECR
            # layer cache (cache:sha256:* blobs) and skip already-built layers.
            #
            # No --cache here: kaniko rejects --cache with --no-push unless
            # --cache-repo is set; we deliberately bypass the layer cache on
            # the gate pass so a failed scan cannot poison the registry cache.
            /kaniko/executor \
              --context=dir://${WORKSPACE}/app \
              --dockerfile=Dockerfile \
              --destination=${APP_REPO}:${GIT_SHA} \
              --no-push \
              --tar-path=${WORKSPACE}/image.tar \
              --snapshot-mode=redo \
              --use-new-run \
              --verbosity=info
            ls -lh ${WORKSPACE}/image.tar
          '''
        }
      }
    }

    stage('Container Image Scan (trivy)') {
      steps {
        container('trivy') {
          script {
            def threshold = securityPolicy.thresholdFor('container')
            def allowlist = securityPolicy.allowlistFor('container')
            sh """
              set +e
              trivy image \
                --no-progress \
                --scanners vuln \
                --severity ${threshold} \
                --ignore-unfixed \
                --format json \
                --output trivy-image-report.json \
                --ignorefile ${allowlist} \
                --cache-dir /root/.cache/trivy \
                --input ${WORKSPACE}/image.tar
              TRIVY_EXIT=\$?
              set -e
              echo "trivy-image exit: \${TRIVY_EXIT}"
              echo "\${TRIVY_EXIT}" > .trivy-image-exit-code
            """
            def exitCode = sh(returnStdout: true, script: 'cat .trivy-image-exit-code').trim().toInteger()
            if (exitCode != 0 && securityPolicy.blocking('container')) {
              error("Container scan FAILED (blocking mode): image NOT pushed — findings in trivy-image-report.json")
            } else if (exitCode != 0) {
              catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                error("Container scan found issues (advisory mode — see trivy-image-report.json)")
              }
            }
          }
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'trivy-image-report.json', allowEmptyArchive: true
        }
      }
    }

    stage('Push Image to ECR') {
      steps {
        container('kaniko') {
          sh '''
            set -eu
            # Re-run kaniko WITH push. Layer cache + --use-new-run means this
            # is effectively a push-only operation, not a rebuild.
            /kaniko/executor \
              --context=dir://${WORKSPACE}/app \
              --dockerfile=Dockerfile \
              --destination=${APP_REPO}:${GIT_SHA} \
              --snapshot-mode=redo \
              --use-new-run \
              --cache=true \
              --cache-ttl=24h \
              --verbosity=info
          '''
        }
      }
    }

    stage('Deploy to Staging') {
      steps {
        build job: 'max-weather-deploy',
          parameters: [
            string(name: 'IMAGE_TAG', value: env.GIT_SHA),
            string(name: 'ENV',       value: 'staging'),
            string(name: 'APP_REPO',  value: env.APP_REPO)
          ],
          wait: true,
          propagate: true
      }
    }

    stage('Approve Prod Deploy') {
      steps {
        timeout(time: 24, unit: 'HOURS') {
          input message: "Promote build ${env.GIT_SHA} to PRODUCTION?",
                ok: 'Promote',
                submitterParameter: 'PROMOTER'
        }
      }
    }

    stage('Deploy to Prod') {
      steps {
        build job: 'max-weather-deploy',
          parameters: [
            string(name: 'IMAGE_TAG', value: env.GIT_SHA),
            string(name: 'ENV',       value: 'prod'),
            string(name: 'APP_REPO',  value: env.APP_REPO)
          ],
          wait: true,
          propagate: true
      }
    }

  }

  post {
    success {
      echo "CI SUCCESS: ${env.GIT_SHA} promoted through full pipeline"
    }
    failure {
      echo "CI FAILED for commit: ${env.GIT_SHA}"
    }
  }
}
