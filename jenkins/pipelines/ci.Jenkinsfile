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
    provisioner: karpenter
  tolerations:
    - key: karpenter.sh/provisioned
      operator: Equal
      value: "true"
      effect: NoSchedule
  restartPolicy: Never
  containers:
    - name: jnlp
      image: jenkins/inbound-agent:latest-jdk21
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
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
          cpu: 200m
          memory: 512Mi
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
          cpu: 100m
          memory: 256Mi
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
          cpu: 500m
          memory: 1Gi
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
          cpu: 200m
          memory: 512Mi
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
          cpu: 200m
          memory: 256Mi
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
          cpu: 200m
          memory: 512Mi
        limits:
          cpu: 1000m
          memory: 2Gi
    - name: syft
      image: anchore/syft:latest
      command: ["sleep"]
      args: ["infinity"]
      tty: true
      resources:
        requests:
          cpu: 200m
          memory: 256Mi
        limits:
          cpu: 500m
          memory: 512Mi
    - name: cosign
      image: cgr.dev/chainguard/cosign:latest
      command: ["sleep"]
      args: ["infinity"]
      tty: true
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
    - name: zap
      image: zaproxy/zap-stable:latest
      command: ["sleep"]
      args: ["infinity"]
      tty: true
      resources:
        requests:
          cpu: 500m
          memory: 1Gi
        limits:
          cpu: 2000m
          memory: 4Gi
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

    stage('Pre-Source Gates') {
      parallel {
        stage('Secret Scan (gitleaks)') {
          steps {
            container('gitleaks') {
              script {
                // Run gitleaks — capture exit code, archive report, then decide via policy
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
                // semgrep exits 1 on findings, 0 on clean
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
        stage('SCA FS (trivy-fs)') {
          steps {
            container('trivy') {
              script {
                def threshold = securityPolicy.thresholdFor('sca_fs')
                def allowlist = securityPolicy.allowlistFor('sca_fs')
                sh """
                  set +e
                  trivy fs \
                    --no-progress \
                    --scanners vuln,secret \
                    --severity ${threshold} \
                    --ignore-unfixed \
                    --format json \
                    --output trivy-fs-report.json \
                    --ignorefile ${allowlist} \
                    --cache-dir /root/.cache/trivy \
                    app/
                  TRIVY_EXIT=\$?
                  set -e
                  echo "trivy-fs exit: \${TRIVY_EXIT}"
                  echo "\${TRIVY_EXIT}" > .trivy-fs-exit-code
                """
                def exitCode = sh(returnStdout: true, script: 'cat .trivy-fs-exit-code').trim().toInteger()
                if (exitCode != 0 && securityPolicy.blocking('sca_fs')) {
                  error("SCA FS FAILED (blocking mode): findings in trivy-fs-report.json")
                } else if (exitCode != 0) {
                  catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                    error("SCA FS found issues (advisory mode — see trivy-fs-report.json)")
                  }
                }
              }
            }
          }
          post {
            always {
              archiveArtifacts artifacts: 'trivy-fs-report.json', allowEmptyArchive: true
            }
          }
        }
        stage('SCA NPM (npm audit)') {
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

    stage('Build + Push App Image (kaniko)') {
      steps {
        container('kaniko') {
          sh '''
            set -eu
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

    stage('Image Gates') {
      parallel {
        stage('Trivy Image') {
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
                    "${APP_REPO}:${GIT_SHA}"
                  TRIVY_EXIT=\$?
                  set -e
                  echo "trivy-image exit: \${TRIVY_EXIT}"
                  echo "\${TRIVY_EXIT}" > .trivy-image-exit-code
                """
                def exitCode = sh(returnStdout: true, script: 'cat .trivy-image-exit-code').trim().toInteger()
                if (exitCode != 0 && securityPolicy.blocking('container')) {
                  error("Container scan FAILED (blocking mode): findings in trivy-image-report.json")
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
        stage('SBOM (syft)') {
          steps {
            container('syft') {
              sh '''
                set -eu
                syft "${APP_REPO}:${GIT_SHA}" -o spdx-json=sbom.spdx.json
                echo "SBOM generated: sbom.spdx.json"
              '''
            }
          }
          post {
            always {
              archiveArtifacts artifacts: 'sbom.spdx.json', allowEmptyArchive: true
            }
          }
        }
        stage('Cosign Sign') {
          steps {
            container('aws') {
              script {
                // Resolve image digest — sign by digest not tag for immutability
                env.IMAGE_DIGEST = sh(
                  returnStdout: true,
                  script: """
                    aws ecr describe-images \
                      --repository-name poc-max-weather-api-repo \
                      --image-ids imageTag=${env.GIT_SHA} \
                      --region ${env.AWS_REGION} \
                      --query 'imageDetails[0].imageDigest' \
                      --output text
                  """
                ).trim()
                echo "Image digest: ${env.IMAGE_DIGEST}"
              }
            }
            container('cosign') {
              sh '''
                set -eu
                cosign sign \
                  --yes \
                  --key "awskms:///alias/max-weather-cosign-signer" \
                  "${APP_REPO}@${IMAGE_DIGEST}"
                echo "Image signed: ${APP_REPO}@${IMAGE_DIGEST}"
              '''
            }
          }
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

    stage('Runtime Gates') {
      steps {
        script {
          // Resolve staging invoke URL from Terraform output cached as env var,
          // or fall back to a terraform output call.
          // STAGING_URL should be set as a Jenkins credential or env var.
          // Format: https://<api-id>.execute-api.<region>.amazonaws.com/staging
          def stagingUrl = env.STAGING_URL ?: sh(
            returnStdout: true,
            script: 'cd infra/envs/poc && terraform output -raw api_gateway_invoke_url_staging 2>/dev/null || echo ""'
          ).trim()

          if (!stagingUrl) {
            if (securityPolicy.blocking('dast')) {
              error("Runtime Gates: STAGING_URL not set and terraform output failed (blocking mode)")
            } else {
              catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                error("Runtime Gates: STAGING_URL not set — skipping ZAP scan (advisory mode)")
              }
              return
            }
          }

          container('aws') {
            withCredentials([]) {
              // Mint short-lived JWT (10 min) for ZAP to authenticate against API Gateway
              // IMPORTANT: set +x prevents JWT from appearing in logs; mask-passwords plugin masks the secret value
              sh '''
                set +x
                JWT_SECRET=$(aws secretsmanager get-secret-value \
                  --secret-id poc-max-weather-authorizer-jwt-secret \
                  --region "$AWS_REGION" \
                  --query SecretString \
                  --output text)
                ZAP_TOKEN=$(node -e "
                  const jwt = require('jsonwebtoken');
                  const secret = process.env.JWT_SECRET || '$JWT_SECRET';
                  console.log(jwt.sign(
                    { scope: 'weather-api/read', iss: 'max-weather-pipeline' },
                    secret,
                    { algorithm: 'HS256', expiresIn: '10m' }
                  ));
                " 2>/dev/null)
                echo "$ZAP_TOKEN" > /tmp/zap-token
                unset JWT_SECRET ZAP_TOKEN
                set -x
              '''
              env.ZAP_TOKEN_FILE = '/tmp/zap-token'
            }
          }

          container('zap') {
            script {
              def zapTarget = "${stagingUrl}/weather?latitude=10&longitude=10"
              sh """
                set +e
                ZAP_TOKEN=\$(cat /tmp/zap-token)
                zap-baseline.py \
                  -t "${zapTarget}" \
                  -z "-config replacer.full_list(0).description=jwt \\
                      -config replacer.full_list(0).enabled=true \\
                      -config 'replacer.full_list(0).matchtype=REQ_HEADER' \\
                      -config 'replacer.full_list(0).matchstr=Authorization' \\
                      -config 'replacer.full_list(0).regex=false' \\
                      -config 'replacer.full_list(0).replacement=Bearer \${ZAP_TOKEN}'" \\
                  -c .zap/baseline.conf \\
                  -J zap-report.json \\
                  -I
                ZAP_EXIT=\$?
                rm -f /tmp/zap-token
                set -e
                echo "zap exit: \${ZAP_EXIT}"
                echo "\${ZAP_EXIT}" > .zap-exit-code
              """
              def exitCode = sh(returnStdout: true, script: 'cat .zap-exit-code').trim().toInteger()
              if (exitCode != 0 && securityPolicy.blocking('dast')) {
                error("DAST FAILED (blocking mode): findings in zap-report.json")
              } else if (exitCode != 0) {
                catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                  error("DAST found issues (advisory mode — see zap-report.json)")
                }
              }
            }
          }
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'zap-report.json', allowEmptyArchive: true
          sh 'rm -f /tmp/zap-token .zap-exit-code || true'
        }
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

    stage('Pre-Prod Gates') {
      parallel {
        stage('Cosign Verify') {
          steps {
            container('aws') {
              script {
                // Re-resolve digest to ensure we verify what we are about to deploy
                def digest = env.IMAGE_DIGEST ?: sh(
                  returnStdout: true,
                  script: """
                    aws ecr describe-images \
                      --repository-name poc-max-weather-api-repo \
                      --image-ids imageTag=${env.GIT_SHA} \
                      --region ${env.AWS_REGION} \
                      --query 'imageDetails[0].imageDigest' \
                      --output text
                  """
                ).trim()
                env.IMAGE_DIGEST = digest
              }
            }
            container('cosign') {
              sh '''
                set -eu
                cosign verify \
                  --key "awskms:///alias/max-weather-cosign-signer" \
                  "${APP_REPO}@${IMAGE_DIGEST}"
                echo "Cosign verify PASSED for ${APP_REPO}@${IMAGE_DIGEST}"
              '''
            }
          }
        }
        stage('Drift Re-scan') {
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
                    --output trivy-drift-report.json \
                    --ignorefile ${allowlist} \
                    --cache-dir /root/.cache/trivy \
                    "${APP_REPO}:${GIT_SHA}"
                  DRIFT_EXIT=\$?
                  set -e
                  echo "drift-scan exit: \${DRIFT_EXIT}"
                  echo "\${DRIFT_EXIT}" > .drift-exit-code
                """
                def exitCode = sh(returnStdout: true, script: 'cat .drift-exit-code').trim().toInteger()
                if (exitCode != 0 && securityPolicy.blocking('container')) {
                  error("Drift re-scan FAILED (blocking mode): new CVEs since initial scan — see trivy-drift-report.json")
                } else if (exitCode != 0) {
                  catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                    error("Drift re-scan found new CVEs (advisory mode — see trivy-drift-report.json)")
                  }
                }
              }
            }
          }
          post {
            always {
              archiveArtifacts artifacts: 'trivy-drift-report.json', allowEmptyArchive: true
            }
          }
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
