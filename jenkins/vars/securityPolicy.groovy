// jenkins/vars/securityPolicy.groovy
//
// Security gate policy helper — Jenkins Shared Library global variable.
//
// Reads jenkins/security-policy.yaml and exposes typed gate-decision methods.
// Single source of truth: never embed thresholds directly in Jenkinsfiles.
//
// USAGE in a Jenkinsfile (declarative or scripted):
//
//   @Library('max-weather-shared') _
//
//   pipeline {
//     stages {
//       stage('Secret Scan') {
//         steps {
//           script {
//             // Optional explicit load — most callers use the convenience methods
//             // directly, which load the yaml on each call.
//             def cfg = securityPolicy.scan('secrets')
//             sh "gitleaks detect --config ${cfg.allowlist_file}"
//             if (securityPolicy.blocking('secrets')) {
//               error('Secret scan failed (blocking mode)')
//             }
//           }
//         }
//       }
//       stage('Container Scan') {
//         steps {
//           script {
//             def threshold = securityPolicy.thresholdFor('container')
//             sh "trivy image --severity ${threshold} ..."
//           }
//         }
//       }
//     }
//   }
//
// REQUIRES: pipeline-utility-steps plugin (provides readYaml step).
// Plugin registration is handled by jenkins.yaml in the Helm values.

/**
 * Load the policy yaml and return the parsed Map.
 *
 * Callers typically use the convenience methods (scan, blocking, thresholdFor,
 * allowlistFor) which call this internally. Use load() directly only when
 * iterating over the full policy (e.g. listing all scans).
 *
 * @param path  Path to security-policy.yaml relative to WORKSPACE.
 *              Default: 'jenkins/security-policy.yaml'.
 * @return      Map representation of the parsed yaml.
 */
def load(String path = 'jenkins/security-policy.yaml') {
    return readYaml(file: path)
}

/**
 * Return the scan config map for a named scan.
 *
 * Errors loudly if the scan name is not found in the policy — this is a
 * pipeline-author bug, not a runtime condition to recover from.
 *
 * @param name  Scan key (secrets, sast, sca_fs, sca_npm, container, dast, sign,
 *              verify, sbom).
 * @return      Map with: tool, mode, severity_threshold, allowlist_file, etc.
 */
def scan(String name) {
    def policy = load()
    def scanConfig = policy?.scans?.get(name)
    if (scanConfig == null) {
        def known = policy?.scans?.keySet()?.sort()?.join(', ') ?: '(none)'
        error("securityPolicy: unknown scan name '${name}'. Valid keys: ${known}")
    }
    return scanConfig
}

/**
 * Return true if the named scan is in blocking mode.
 *
 * Use this to decide whether a scan failure should fail the pipeline:
 *
 *   if (securityPolicy.blocking('sast')) { error('SAST blocking failure') }
 *
 * @param name  Scan key.
 * @return      true if mode == 'blocking', false otherwise (including 'advisory'
 *              or any missing/unknown mode value).
 */
def blocking(String name) {
    def s = scan(name)
    return s?.mode == 'blocking'
}

/**
 * Return the severity threshold string for a named scan.
 *
 * Pass directly to scanner CLI arguments. Case is preserved as declared in the
 * yaml — different scanners use different conventions (HIGH for trivy/semgrep,
 * high for npm-audit, High for ZAP).
 *
 * @param name  Scan key.
 * @return      String threshold (e.g. 'HIGH', 'high', 'High', 'any') or null if
 *              not set on this scan.
 */
def thresholdFor(String name) {
    def s = scan(name)
    return s?.severity_threshold
}

/**
 * Return the allowlist file path for a named scan, or null if not configured.
 *
 * @param name  Scan key.
 * @return      String workspace-relative path (e.g. '.gitleaks.toml',
 *              '.trivyignore') or null when the scan does not declare an
 *              allowlist file.
 */
def allowlistFor(String name) {
    def s = scan(name)
    return s?.allowlist_file
}
