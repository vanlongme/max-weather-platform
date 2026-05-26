// jenkins/vars/securityReport.groovy
//
// Human-readable security scan report formatter — Jenkins Shared Library var.
//
// Parses the JSON output of each security scanner and prints a compact summary
// table to the build console, then writes the same content as a markdown file
// (archived alongside the raw JSON). One helper per tool keeps the parsing
// logic close to the tool's actual schema.
//
// USAGE inside a stage's post.always block:
//
//   post {
//     always {
//       script {
//         securityReport.summarize(tool: 'gitleaks', json: 'gitleaks-report.json')
//       }
//       archiveArtifacts artifacts: 'gitleaks-report.json,gitleaks-summary.md',
//                        allowEmptyArchive: true
//     }
//   }
//
// Supported tools: gitleaks, semgrep, npm-audit, trivy-image.

import groovy.json.JsonSlurper

/**
 * Entry point. Dispatches to the per-tool formatter based on `args.tool`.
 *
 * @param args.tool  Required. One of: gitleaks, semgrep, npm-audit, trivy-image.
 * @param args.json  Required. Workspace-relative path to the JSON report.
 * @param args.out   Optional. Markdown output path. Defaults to "${tool}-summary.md".
 */
def summarize(Map args) {
    def tool = args.tool ?: error("securityReport.summarize: 'tool' is required")
    def jsonPath = args.json ?: error("securityReport.summarize: 'json' is required")
    def outPath = args.out ?: "${tool}-summary.md"

    if (!fileExists(jsonPath)) {
        echo "securityReport: skip ${tool} — ${jsonPath} not found"
        return
    }

    def raw = readFile(jsonPath).trim()
    if (!raw) {
        echo "securityReport: skip ${tool} — ${jsonPath} is empty"
        return
    }

    def md
    switch (tool) {
        case 'gitleaks':    md = _gitleaks(raw);   break
        case 'semgrep':     md = _semgrep(raw);    break
        case 'npm-audit':   md = _npmAudit(raw);   break
        case 'trivy-image': md = _trivyImage(raw); break
        default:
            error("securityReport: unknown tool '${tool}'. Supported: gitleaks, semgrep, npm-audit, trivy-image")
    }

    // Pretty-print to console with banner; archive markdown for download.
    echo "\n================ SECURITY REPORT: ${tool.toUpperCase()} ================\n${md}\n================ END ${tool.toUpperCase()} ================"
    writeFile file: outPath, text: md
}

// ---------------------------------------------------------------------------
// gitleaks: top-level is an array of findings; empty == clean.
// Each finding: { RuleID, Description, File, StartLine, Match, Commit, ... }
// ---------------------------------------------------------------------------
private String _gitleaks(String raw) {
    def findings = new JsonSlurper().parseText(raw) ?: []
    if (!(findings instanceof List)) { findings = [] }

    def out = new StringBuilder()
    out << "# gitleaks — Secret Scan\n\n"
    out << "**Findings:** ${findings.size()}\n\n"
    if (findings.isEmpty()) {
        out << "_No secrets detected._\n"
        return out.toString()
    }

    // Group by rule for compactness.
    def byRule = findings.groupBy { it.RuleID ?: 'unknown' }
    out << "| Rule | Count |\n|------|------:|\n"
    byRule.sort { -it.value.size() }.each { rule, list ->
        out << "| ${rule} | ${list.size()} |\n"
    }
    out << "\n## Top 10 occurrences\n\n"
    out << "| File:Line | Rule | Commit |\n|-----------|------|--------|\n"
    findings.take(10).each { f ->
        def loc = "${f.File ?: '?'}:${f.StartLine ?: '?'}"
        def commit = (f.Commit ?: '').take(8)
        out << "| ${loc} | ${f.RuleID ?: '?'} | ${commit} |\n"
    }
    return out.toString()
}

// ---------------------------------------------------------------------------
// semgrep: { results: [ { check_id, path, start.line, extra.severity, extra.message } ], errors: [...] }
// ---------------------------------------------------------------------------
private String _semgrep(String raw) {
    def data = new JsonSlurper().parseText(raw) ?: [:]
    def results = data.results ?: []

    def out = new StringBuilder()
    out << "# semgrep — SAST\n\n"
    out << "**Findings:** ${results.size()}\n\n"
    if (results.isEmpty()) {
        out << "_No SAST issues found._\n"
        return out.toString()
    }

    def bySev = results.groupBy { (it.extra?.severity ?: 'INFO').toString() }
    out << "| Severity | Count |\n|----------|------:|\n"
    ['ERROR', 'WARNING', 'INFO'].each { sev ->
        def n = (bySev[sev] ?: []).size()
        if (n > 0) { out << "| ${sev} | ${n} |\n" }
    }
    out << "\n## Top 10 findings\n\n"
    out << "| Severity | Rule | File:Line | Message |\n|----------|------|-----------|---------|\n"
    results.take(10).each { r ->
        def sev = r.extra?.severity ?: '?'
        def rule = (r.check_id ?: '?').toString().tokenize('.').last()
        def loc = "${r.path ?: '?'}:${r.start?.line ?: '?'}"
        def msg = (r.extra?.message ?: '').toString().replaceAll(/[\r\n|]/, ' ').take(80)
        out << "| ${sev} | ${rule} | ${loc} | ${msg} |\n"
    }
    return out.toString()
}

// ---------------------------------------------------------------------------
// npm audit --json: { vulnerabilities: { <pkg>: { severity, via: [...] } },
//                     metadata: { vulnerabilities: { info, low, moderate, high, critical, total } } }
// ---------------------------------------------------------------------------
private String _npmAudit(String raw) {
    def data = new JsonSlurper().parseText(raw) ?: [:]
    def meta = data.metadata?.vulnerabilities ?: [:]
    def vulns = data.vulnerabilities ?: [:]

    def out = new StringBuilder()
    out << "# npm audit — SCA (production deps)\n\n"
    def total = meta.total ?: vulns.size()
    out << "**Vulnerable packages:** ${total}\n\n"
    out << "| Severity | Count |\n|----------|------:|\n"
    ['critical', 'high', 'moderate', 'low', 'info'].each { sev ->
        def n = meta[sev] ?: 0
        if (n > 0) { out << "| ${sev} | ${n} |\n" }
    }
    if (vulns.isEmpty()) {
        out << "\n_No vulnerable production dependencies._\n"
        return out.toString()
    }
    out << "\n## Top 10 vulnerable packages\n\n"
    out << "| Package | Severity | Via |\n|---------|----------|-----|\n"
    vulns.entrySet().take(10).each { e ->
        def name = e.key
        def v = e.value ?: [:]
        def sev = v.severity ?: '?'
        def via = (v.via ?: []).collect { it instanceof Map ? (it.title ?: it.name ?: '?') : it.toString() }.take(2).join(', ')
        out << "| ${name} | ${sev} | ${via.take(60)} |\n"
    }
    return out.toString()
}

// ---------------------------------------------------------------------------
// trivy image --format json:
// { Results: [ { Target, Vulnerabilities: [ { VulnerabilityID, PkgName,
//                                              InstalledVersion, FixedVersion,
//                                              Severity, Title } ] } ] }
// ---------------------------------------------------------------------------
private String _trivyImage(String raw) {
    def data = new JsonSlurper().parseText(raw) ?: [:]
    def results = data.Results ?: []
    def vulns = results.collectMany { it.Vulnerabilities ?: [] }

    def out = new StringBuilder()
    out << "# trivy — Container Image Scan\n\n"
    out << "**CVEs (fixable):** ${vulns.size()}\n\n"
    if (vulns.isEmpty()) {
        out << "_No fixable CVEs at configured threshold._\n"
        return out.toString()
    }
    def bySev = vulns.groupBy { (it.Severity ?: 'UNKNOWN').toString() }
    out << "| Severity | Count |\n|----------|------:|\n"
    ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'UNKNOWN'].each { sev ->
        def n = (bySev[sev] ?: []).size()
        if (n > 0) { out << "| ${sev} | ${n} |\n" }
    }
    out << "\n## Top 10 CVEs\n\n"
    out << "| CVE | Severity | Package | Installed → Fixed |\n|-----|----------|---------|-------------------|\n"
    vulns.sort { a, b -> _sevRank(b.Severity) <=> _sevRank(a.Severity) }.take(10).each { v ->
        def id = v.VulnerabilityID ?: '?'
        def sev = v.Severity ?: '?'
        def pkg = v.PkgName ?: '?'
        def fix = "${v.InstalledVersion ?: '?'} → ${v.FixedVersion ?: '(no fix)'}"
        out << "| ${id} | ${sev} | ${pkg} | ${fix} |\n"
    }
    return out.toString()
}

private int _sevRank(String sev) {
    switch ((sev ?: '').toUpperCase()) {
        case 'CRITICAL': return 4
        case 'HIGH':     return 3
        case 'MEDIUM':   return 2
        case 'LOW':      return 1
        default:         return 0
    }
}
