pipeline {
  agent {
    kubernetes {
      defaultContainer 'jnlp'
      yaml '''
apiVersion: v1
kind: Pod
metadata:
  labels:
    job: max-weather-deploy
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
          cpu: 100m
          memory: 256Mi
        limits:
          cpu: 500m
          memory: 512Mi
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
    - name: kubectl
      image: alpine/k8s:1.30.0
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
'''
    }
  }

  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 20, unit: 'MINUTES')
    disableConcurrentBuilds(abortPrevious: false)
  }

  parameters {
    string(name: 'IMAGE_TAG', defaultValue: '', description: 'Git short SHA, e.g. a1b2c3d')
    string(name: 'ENV',       defaultValue: '', description: 'Target environment: staging or prod')
    string(name: 'APP_REPO',  defaultValue: '', description: 'Full ECR repo URL, e.g. 1234.dkr.ecr.us-east-1.amazonaws.com/weather-api')
  }

  environment {
    AWS_REGION = 'us-east-1'
    CLUSTER    = 'poc-max-weather-cluster'
  }

  stages {

    stage('Validate Params') {
      steps {
        script {
          if (!params.IMAGE_TAG?.trim()) {
            error("IMAGE_TAG is required and must not be empty")
          }
          if (!params.APP_REPO?.trim()) {
            error("APP_REPO is required and must not be empty")
          }
          if (!['staging', 'prod'].contains(params.ENV)) {
            error("ENV must be 'staging' or 'prod', got: '${params.ENV}'")
          }
          echo "Deploying ${params.IMAGE_TAG} to ${params.ENV}"
        }
      }
    }

    stage('Verify ECR Image Exists') {
      steps {
        container('aws') {
          sh '''
            set -eu
            REPO_NAME=$(echo "$APP_REPO" | cut -d/ -f2-)
            echo "Checking ECR for $APP_REPO:$IMAGE_TAG ..."
            for i in $(seq 1 5); do
              if aws ecr describe-images \
                  --repository-name "$REPO_NAME" \
                  --image-ids imageTag="$IMAGE_TAG" \
                  --region "$AWS_REGION" > /dev/null 2>&1; then
                echo "Image found on attempt $i"
                exit 0
              fi
              echo "Image not yet available (attempt $i/5), waiting 3s..."
              sleep 3
            done
            echo "ERROR: Image $APP_REPO:$IMAGE_TAG not found in ECR after 5 attempts"
            exit 1
          '''
        }
      }
    }

    stage('Deploy') {
      steps {
        container('kubectl') {
          sh '''
            set -eu
            aws eks update-kubeconfig --name "$CLUSTER" --region "$AWS_REGION"
            cd k8s/overlays/${ENV}
            kustomize edit set image weather-api=${APP_REPO}:${IMAGE_TAG}
            cd -
            kubectl apply -k k8s/overlays/${ENV}
          '''
        }
      }
    }

    stage('Smoke Test') {
      steps {
        container('kubectl') {
          sh '''
            set -eu
            NLB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
              -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
            CODE=000
            for i in $(seq 1 30); do
              CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                -H "Host: ${ENV}.max-weather.local" \
                "http://$NLB/healthz" -m 10 || echo "000")
              [ "$CODE" = "200" ] && break
              echo "Waiting for smoke test... ($i/30)"
              sleep 5
            done
            [ "$CODE" = "200" ] || { echo "Smoke test FAILED: HTTP $CODE"; exit 1; }
            echo "Smoke test PASSED: HTTP 200"
          '''
        }
      }
    }

  }

  post {
    failure {
      script {
        if (params.ENV == 'staging') {
          echo "Deploy FAILED on staging — triggering auto-rollback..."
          container('kubectl') {
            sh '''
              set -eu
              aws eks update-kubeconfig --name "$CLUSTER" --region "$AWS_REGION"
              REV_COUNT=$(kubectl rollout history deployment/weather-api -n weather-${ENV} 2>/dev/null | tail -n +3 | wc -l || echo 0)
              if [ "$REV_COUNT" -ge 2 ]; then
                kubectl rollout undo deployment/weather-api -n weather-${ENV}
                echo "Rollback complete for staging"
              else
                echo "No prior revision to roll back to (first deploy or single-revision); skipping rollback"
              fi
            '''
          }
        } else {
          echo "Deploy FAILED on prod — manual intervention required. NO auto-rollback per policy."
        }
      }
    }
    success {
      echo "Deploy SUCCESS: ${params.IMAGE_TAG} → weather-${params.ENV}"
    }
  }
}
