// Jenkins Job DSL Seed Script
//
// Executed by the JCasC-managed seed job on Jenkins startup via the Job DSL plugin.
// Creates two pipeline jobs: max-weather-ci (upstream) and max-weather-deploy (downstream).
//
// HOW THIS WORKS:
//   helm upgrade jenkins → JCasC configScripts.seed-job → seed freestyle job created
//   → seed job runs THIS script → pipeline job blocks create/update both jobs.
//
// HOW TO MANAGE JOBS:
//   Add job:    Append a new pipeline job block here, re-run seed.
//   Delete job: Remove its pipelineJob block; seed re-run deletes it (removedJobAction: DELETE).
//   Edit logic: Change jenkins/pipelines/{ci,deploy}.Jenkinsfile — no seed re-run needed.
//
// SCM_URL: Set in the seed job's environment (via JCasC). Defaults to placeholder below.

// Auto-delete orphaned jobs when this script is re-run (set at seed-job level via JCasC/values.yaml)
// The removedJobAction('DELETE') below is the Job DSL script-level override:
removedJobAction('DELETE')

def scmUrl = binding.variables.get('SCM_URL') ?: 'https://github.com/your-org/max-weather.git'

// ------------------------------------------------------------------
// Job 1: max-weather-ci  (Upstream CI pipeline)
// ------------------------------------------------------------------
pipelineJob('max-weather-ci') {
    description('Upstream CI: lint, test, build, push image to ECR, trigger deploy (auto staging, manual prod gate)')
    logRotator {
        numToKeep(15)
    }
    triggers {
        // Poll SCM every 5 minutes as POC fallback; prefer webhook in production
        scm('H/5 * * * *')
    }
    definition {
        cpsScm {
            scm {
                git {
                    remote { url(scmUrl) }
                    branch('main')
                }
            }
            scriptPath('jenkins/pipelines/ci.Jenkinsfile')
        }
    }
}

// ------------------------------------------------------------------
// Job 2: max-weather-deploy  (Downstream deploy pipeline)
// ------------------------------------------------------------------
pipelineJob('max-weather-deploy') {
    description('Downstream Deploy: validates params, verifies ECR image, applies kustomize overlay, smoke tests, auto-rollback (staging only)')
    logRotator {
        numToKeep(20)
    }
    parameters {
        stringParam('IMAGE_TAG', '', 'Git short SHA — must already exist in ECR, e.g. a1b2c3d')
        stringParam('ENV',       '', 'Target environment: staging or prod')
        stringParam('APP_REPO',  '', 'Full ECR repo URL, e.g. 1234.dkr.ecr.us-east-1.amazonaws.com/weather-api')
    }
    // No triggers — invoked exclusively via `build job:` from max-weather-ci
    definition {
        cpsScm {
            scm {
                git {
                    remote { url(scmUrl) }
                    branch('main')
                }
            }
            scriptPath('jenkins/pipelines/deploy.Jenkinsfile')
        }
    }
}
