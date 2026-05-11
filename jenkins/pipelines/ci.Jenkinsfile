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

    stage('Container Image Scan') {
      steps {
        container('trivy') {
          sh '''
            set -eu
            echo "Scanning ${APP_REPO}:${GIT_SHA} with trivy (report-only, never fails build)"
            trivy image \
              --no-progress \
              --scanners vuln \
              --severity HIGH,CRITICAL \
              --ignore-unfixed \
              --exit-code 0 \
              --format table \
              "${APP_REPO}:${GIT_SHA}"
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
