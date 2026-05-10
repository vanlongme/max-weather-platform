pipeline {
  agent any

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
    CLUSTER    = 'max-weather'
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
        sh '''
          set -euo pipefail
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

    stage('Update Kustomize Image') {
      steps {
        sh '''
          set -euo pipefail
          cd k8s/overlays/${ENV}
          kustomize edit set image weather-api=${APP_REPO}:${IMAGE_TAG}
        '''
      }
    }

    stage('Deploy') {
      steps {
        sh '''
          set -euo pipefail
          aws eks update-kubeconfig --name $CLUSTER --region $AWS_REGION
          kubectl apply -k k8s/overlays/${ENV}
          kubectl rollout status deployment/weather-api -n weather-${ENV} --timeout=180s
        '''
      }
    }

    stage('Smoke Test') {
      steps {
        sh '''
          set -euo pipefail
          NLB=$(kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller \
            -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
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

  post {
    failure {
      script {
        if (params.ENV == 'staging') {
          echo "Deploy FAILED on staging — triggering auto-rollback..."
          sh '''
            set -euo pipefail
            aws eks update-kubeconfig --name $CLUSTER --region $AWS_REGION
            kubectl rollout undo deployment/weather-api -n weather-${ENV}
            echo "Rollback complete for staging"
          '''
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
