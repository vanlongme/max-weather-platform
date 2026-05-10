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

    stage('Build + Push Base Image (apko)') {
      when {
        anyOf {
          changeset 'base-image/**'
          expression { return !sh(returnStdout: true, script: "aws ecr describe-images --repository-name ${CLUSTER}-base-nodejs --image-ids imageTag=latest --region ${AWS_REGION} 2>&1 || echo MISSING").contains('imageDigest') }
        }
      }
      steps {
        sh 'AWS_REGION=$AWS_REGION CLUSTER=$CLUSTER bash base-image/build.sh'
      }
    }

    stage('Build + Push App Image') {
      steps {
        sh '''
          set -euo pipefail
          aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_HOST
          BASE=$ECR_HOST/$CLUSTER-base-nodejs:latest
          docker buildx build --platform linux/amd64 \
            --build-arg BASE_IMAGE=$BASE \
            --build-arg BUILDER_IMAGE=$BASE \
            -t $APP_REPO:$GIT_SHA \
            --push app/
        '''
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
