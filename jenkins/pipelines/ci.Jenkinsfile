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
    # Docker-in-Docker (DinD) replaces kaniko for ~3-5x faster builds:
    # parallel layer download, native build cache, no rootfs wipe between
    # build/push. Single container handles build → save tar (for trivy)
    # → push (after scan passes). Requires privileged for /var/lib/docker.
    - name: docker
      image: docker:24-dind
      command: ["dockerd-entrypoint.sh"]
      args: ["--host=unix:///var/run/docker.sock", "--storage-driver=overlay2"]
      tty: true
      securityContext:
        privileged: true
      env:
        - name: DOCKER_TLS_CERTDIR
          value: ""
      resources:
        requests:
          cpu: 500m
          memory: 1Gi
        limits:
          cpu: 2000m
          memory: 4Gi
      volumeMounts:
        - name: docker-storage
          mountPath: /var/lib/docker
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
    - name: docker-storage
      emptyDir:
        sizeLimit: 16Gi
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
          script { securityReport.summarize(tool: 'gitleaks', json: 'gitleaks-report.json') }
          archiveArtifacts artifacts: 'gitleaks-report.json,gitleaks-summary.md', allowEmptyArchive: true
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
              semgrep scan \
                --metrics=off \
                --config p/nodejs \
                --config p/owasp-top-ten \
                --config p/javascript \
                --json \
                --output semgrep-report.json \
                ${sevFlags} \
                --error \
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
          script { securityReport.summarize(tool: 'semgrep', json: 'semgrep-report.json') }
          archiveArtifacts artifacts: 'semgrep-report.json,semgrep-summary.md', allowEmptyArchive: true
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
          script { securityReport.summarize(tool: 'npm-audit', json: 'npm-audit-report.json') }
          archiveArtifacts artifacts: 'npm-audit-report.json,npm-audit-summary.md', allowEmptyArchive: true
        }
      }
    }

    stage('Build Container Image (local tarball)') {
      steps {
        container('docker') {
          sh '''
            set -eu
            for i in $(seq 1 30); do
              if docker info >/dev/null 2>&1; then break; fi
              echo "waiting for dockerd... ${i}/30"
              sleep 2
            done
            docker version

            # Pre-pull base images sequentially with retries. Chainguard's
            # cgr.dev free-tier registry rate-limits parallel blob fetches
            # ("Error 1040: Too many connections"); BuildKit's default parallel
            # layer download trips this. Pulling sequentially first warms the
            # local daemon cache; the subsequent build resolves to local layers
            # without any registry round-trip.
            for img in cgr.dev/chainguard/node:latest cgr.dev/chainguard/node:latest-dev; do
              for attempt in 1 2 3 4 5; do
                if docker pull "$img"; then
                  echo "pulled $img (attempt $attempt)"; break
                fi
                echo "pull $img failed (attempt $attempt) — backing off"
                sleep $((attempt * 5))
              done
            done

            DOCKER_BUILDKIT=1 docker build \
              --tag ${APP_REPO}:${GIT_SHA} \
              --file ${WORKSPACE}/app/Dockerfile \
              ${WORKSPACE}/app
            docker save -o ${WORKSPACE}/image.tar ${APP_REPO}:${GIT_SHA}
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
          script { securityReport.summarize(tool: 'trivy-image', json: 'trivy-image-report.json') }
          archiveArtifacts artifacts: 'trivy-image-report.json,trivy-image-summary.md', allowEmptyArchive: true
        }
      }
    }

    stage('Push Image to ECR') {
      steps {
        // Pod Identity gives the 'aws' sidecar credentials to fetch an ECR
        // auth token; pipe the password into the docker sidecar's CLI which
        // already has the locally-built image from the build stage.
        container('aws') {
          sh '''
            set -eu
            aws ecr get-login-password --region "$AWS_REGION" > .ecr-token
          '''
        }
        container('docker') {
          sh '''
            set -eu
            cat .ecr-token | docker login --username AWS --password-stdin "${ECR_HOST}"
            docker push ${APP_REPO}:${GIT_SHA}
            rm -f .ecr-token
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
