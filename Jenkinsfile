pipeline {
  agent any

  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '15'))
    timeout(time: 30, unit: 'MINUTES')
  }

  environment {
    AWS_REGION = 'us-east-1'
    CLUSTER    = 'max-weather'
    NAMESPACE  = 'weather-staging'
    GIT_SHA    = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
    APP_REPO   = sh(returnStdout: true, script: 'cd infra/envs/poc && terraform output -raw weather_api_repository_url 2>/dev/null || echo PLACEHOLDER').trim()
    ECR_HOST   = sh(returnStdout: true, script: 'cd infra/envs/poc && terraform output -raw weather_api_repository_url 2>/dev/null | cut -d/ -f1 || echo PLACEHOLDER').trim()
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('App Lint + Test') {
      steps {
        sh 'cd app && npm ci && npm run lint && npm test'
      }
      post {
        always {
          junit allowEmptyResults: true, testResults: 'app/junit.xml'
        }
      }
    }

    stage('Authorizer Test') {
      steps {
        sh 'cd lambda-authorizer && npm ci && npm test'
      }
    }

    stage('Build + Push Image') {
      steps {
        sh '''
          aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_HOST
          docker buildx build --platform linux/amd64 \
            -t $APP_REPO:staging-$GIT_SHA \
            -t $APP_REPO:latest \
            --push app/
        '''
      }
    }

    stage('Update Kustomize Image') {
      steps {
        sh '''
          cd k8s/overlays/staging
          kustomize edit set image weather-api=$APP_REPO:staging-$GIT_SHA
        '''
      }
    }

    stage('Install Cluster Addons') {
      steps {
        sh '''
          CLUSTER_NAME=$CLUSTER AWS_REGION=$AWS_REGION bash scripts/install-helm-addons.sh
        '''
      }
    }

    stage('Deploy to Staging') {
      steps {
        sh '''
          aws eks update-kubeconfig --name $CLUSTER --region $AWS_REGION
          kubectl apply -k k8s/overlays/staging
          kubectl rollout status deployment/weather-api -n $NAMESPACE --timeout=180s
        '''
      }
    }

    stage('Smoke Test') {
      steps {
        sh '''
          NLB=$(kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller \
            -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
          for i in $(seq 1 30); do
            CODE=$(curl -s -o /dev/null -w "%{http_code}" \
              -H "Host: staging.max-weather.local" \
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
    success {
      echo "Build SUCCESS: staging-${env.GIT_SHA} deployed to ${env.NAMESPACE}"
    }
    failure {
      echo "Build FAILED for commit: ${env.GIT_SHA}"
    }
  }
}
