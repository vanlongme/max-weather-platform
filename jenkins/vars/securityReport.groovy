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
// Severity formatting helpers — emoji + markdown bold only. No raw HTML.
// Jenkins default markup formatter is plain-text and would escape <span>
// tags as literal characters; emoji renders identically in plain-text,
// markdown viewers, and terminal — the universal color signal.
// ---------------------------------------------------------------------------
private String _sevBadge(String sev) {
    def s = (sev ?: 'UNKNOWN').toString().toUpperCase()
    // Normalize aliases used across scanners.
    if (s == 'ERROR')    s = 'CRITICAL'
    if (s == 'WARNING')  s = 'HIGH'
    if (s == 'MODERATE') s = 'MEDIUM'
    switch (s) {
        case 'CRITICAL': return '🔴 **CRITICAL**'
        case 'HIGH':     return '🟠 **HIGH**'
        case 'MEDIUM':   return '🟡 **MEDIUM**'
        case 'LOW':      return '🔵 **LOW**'
        case 'INFO':     return '⚪ **INFO**'
        default:         return '⚪ **UNKNOWN**'
    }
}

private String _statusBanner(int count, String cleanMsg) {
    if (count == 0) {
        return "✅ **PASS** — ${cleanMsg}\n"
    }
    return "❌ **FAIL** — ${count} finding(s)\n"
}

private String _sevTable(Map counts, List order) {
    def rows = new StringBuilder()
    order.each { sev ->
        def n = counts[sev] ?: 0
        if (n > 0) {
            rows << "| ${_sevBadge(sev)} | **${n}** |\n"
        }
    }
    if (rows.length() == 0) return ""
    return "| Severity | Count |\n|----------|------:|\n${rows}\n"
}

// ---------------------------------------------------------------------------
// gitleaks: top-level is an array of findings; empty == clean.
// Each finding: { RuleID, Description, File, StartLine, Match, Commit, ... }
// ---------------------------------------------------------------------------
private String _gitleaks(String raw) {
    def findings = new JsonSlurper().parseText(raw) ?: []
    if (!(findings instanceof List)) { findings = [] }

    def out = new StringBuilder()
    out << "# 🔐 gitleaks — Secret Scan\n\n"
    out << _statusBanner(findings.size(), "No secrets detected.")
    out << "\n"
    if (findings.isEmpty()) {
        return out.toString()
    }

    // Gitleaks has no severity field — all leaks treated CRITICAL.
    out << "**Severity:** ${_sevBadge('CRITICAL')} (all secret leaks)\n\n"

    def byRule = findings.groupBy { it.RuleID ?: 'unknown' }
    out << "## Findings by Rule\n\n"
    out << "| Rule | Count |\n|------|------:|\n"
    byRule.sort { -it.value.size() }.each { rule, list ->
        out << "| `${rule}` | **${list.size()}** |\n"
    }
    out << "\n## Top 10 occurrences\n\n"
    out << "| Severity | File:Line | Rule | Commit |\n|----------|-----------|------|--------|\n"
    findings.take(10).each { f ->
        def loc = "${f.File ?: '?'}:${f.StartLine ?: '?'}"
        def commit = (f.Commit ?: '').take(8)
        out << "| ${_sevBadge('CRITICAL')} | `${loc}` | `${f.RuleID ?: '?'}` | `${commit}` |\n"
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
    out << "# 🛡️ semgrep — SAST\n\n"
    out << _statusBanner(results.size(), "No SAST issues found.")
    out << "\n"
    if (results.isEmpty()) {
        return out.toString()
    }

    def bySev = results.groupBy { (it.extra?.severity ?: 'INFO').toString() }
    def counts = [:]
    bySev.each { k, v -> counts[k] = v.size() }
    out << _sevTable(counts, ['ERROR', 'WARNING', 'INFO'])
    out << "## Top 10 findings\n\n"
    out << "| Severity | Rule | File:Line | Message |\n|----------|------|-----------|---------|\n"
    def ordered = []
    ['ERROR', 'WARNING', 'INFO'].each { sev -> ordered.addAll(bySev[sev] ?: []) }
    def top = ordered.size() > 10 ? ordered.subList(0, 10) : ordered
    top.each { r ->
        def sev = r.extra?.severity ?: 'INFO'
        def rule = (r.check_id ?: '?').toString().tokenize('.').last()
        def loc = "${r.path ?: '?'}:${r.start?.line ?: '?'}"
        def msg = (r.extra?.message ?: '').toString().replaceAll(/[\r\n|]/, ' ').take(80)
        out << "| ${_sevBadge(sev)} | `${rule}` | `${loc}` | ${msg} |\n"
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
    out << "# 📦 npm audit — SCA (production deps)\n\n"
    def total = (meta.total ?: vulns.size()) as int
    out << _statusBanner(total, "No vulnerable production dependencies.")
    out << "\n"
    if (total == 0) {
        return out.toString()
    }
    def counts = [:]
    ['critical', 'high', 'moderate', 'low', 'info'].each { sev ->
        counts[sev] = (meta[sev] ?: 0) as int
    }
    out << _sevTable(counts, ['critical', 'high', 'moderate', 'low', 'info'])
    out << "## Top 10 vulnerable packages\n\n"
    out << "| Severity | Package | Via |\n|----------|---------|-----|\n"
    List entries = []
    vulns.each { k, v -> entries.add([k: k, v: v]) }
    entries = entries.toSorted { a, b -> _sevRank(b.v?.severity ?: '') <=> _sevRank(a.v?.severity ?: '') }
    int n = Math.min(10, entries.size())
    for (int i = 0; i < n; i++) {
        def e = entries[i]
        def name = e.k
        def v = e.v ?: [:]
        def sev = v.severity ?: 'info'
        def viaList = (v.via ?: []).collect { it instanceof Map ? (it.title ?: it.name ?: '?') : it.toString() }
        def viaTrunc = viaList.size() > 2 ? viaList.subList(0, 2) : viaList
        def via = viaTrunc.join(', ')
        if (via.length() > 60) via = via.substring(0, 60)
        out << "| ${_sevBadge(sev)} | `${name}` | ${via} |\n"
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
    out << "# 🐳 trivy — Container Image Scan\n\n"
    out << _statusBanner(vulns.size(), "No fixable CVEs at configured threshold.")
    out << "\n"
    if (vulns.isEmpty()) {
        return out.toString()
    }
    def bySev = vulns.groupBy { (it.Severity ?: 'UNKNOWN').toString() }
    def counts = [:]
    bySev.each { k, v -> counts[k] = v.size() }
    out << _sevTable(counts, ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'UNKNOWN'])
    out << "## Top 10 CVEs\n\n"
    out << "| Severity | CVE | Package | Installed → Fixed |\n|----------|-----|---------|-------------------|\n"
    def ordered = []
    ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'UNKNOWN'].each { sev ->
        ordered.addAll(bySev[sev] ?: [])
    }
    def top = ordered.size() > 10 ? ordered.subList(0, 10) : ordered
    top.each { v ->
        def id = v.VulnerabilityID ?: '?'
        def sev = v.Severity ?: 'UNKNOWN'
        def pkg = v.PkgName ?: '?'
        def fix = "${v.InstalledVersion ?: '?'} → ${v.FixedVersion ?: '(no fix)'}"
        out << "| ${_sevBadge(sev)} | `${id}` | `${pkg}` | ${fix} |\n"
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

/**
 * Aggregate all per-tool *-summary.md files into a single consolidated report
 * for the Approve Prod input gate. Reads files that exist; silently skips
 * missing ones (a stage may have errored before producing its summary).
 *
 * @param args.out      Optional. Output path. Default 'summary-report.md'.
 * @param args.tools    Optional. Ordered list of tool keys to include.
 *                      Default: ['gitleaks','semgrep','npm-audit','trivy-image'].
 * @param args.header   Optional. Map of build metadata rendered at the top
 *                      (e.g. [build: env.BUILD_TAG, sha: env.GIT_SHA, image: env.APP_REPO]).
 * @return The merged markdown string (also written to args.out).
 */
def aggregate(Map args = [:]) {
    def outPath = args.out ?: 'summary-report.md'
    def tools = args.tools ?: ['gitleaks', 'semgrep', 'npm-audit', 'trivy-image']
    def header = args.header ?: [:]

    def md = new StringBuilder()
    md << "# 🛡️ CI Security Summary — Promotion Gate\n\n"
    if (header) {
        md << "## Build Metadata\n\n"
        md << "| Field | Value |\n|-------|-------|\n"
        header.each { k, v -> md << "| **${k}** | `${v ?: 'n/a'}` |\n" }
        md << "\n"
    }

    def perTool = [:]
    int totalFindings = 0
    tools.each { t ->
        def path = "${t}-summary.md"
        if (!fileExists(path)) {
            perTool[t] = [status: 'MISSING', findings: -1, body: null]
            return
        }
        def body = readFile(path)
        def clean = body.contains('✅ PASS')
        def m = body =~ /(\d+) finding\(s\)/
        int n = clean ? 0 : (m ? (m[0][1] as int) : 0)
        perTool[t] = [status: clean ? 'PASS' : 'FAIL', findings: n, body: body]
        if (n > 0) totalFindings += n
    }

    def overall
    if (perTool.values().any { it.status == 'MISSING' }) {
        overall = '⚠️ **INCOMPLETE** — one or more scan reports missing'
    } else if (perTool.values().every { it.status == 'PASS' }) {
        overall = '✅ **ALL SCANS PASSED** — safe to promote'
    } else {
        overall = "❌ **FINDINGS PRESENT** — ${totalFindings} total finding(s) across scans; review before promote"
    }
    md << "## Overall Posture\n\n${overall}\n\n"

    md << "## Scan Status\n\n"
    md << "| Scan | Status | Findings |\n|------|--------|---------:|\n"
    tools.each { t ->
        def info = perTool[t]
        def status
        switch (info.status) {
            case 'PASS':    status = '✅ **PASS**'; break
            case 'FAIL':    status = '❌ **FAIL**'; break
            default:        status = '⚠️ **MISSING**'; break
        }
        def n = info.findings < 0 ? 'n/a' : info.findings.toString()
        md << "| ${t} | ${status} | **${n}** |\n"
    }
    md << "\n---\n\n"

    tools.each { t ->
        def info = perTool[t]
        md << "## ${t}\n\n"
        if (info.body) {
            md << info.body
        } else {
            md << "⚠️ **MISSING** — report not produced (upstream stage may have errored before emitting summary).\n"
        }
        md << "\n---\n\n"
    }

    writeFile file: outPath, text: md.toString()
    echo "securityReport.aggregate: merged ${tools.size()} reports → ${outPath}"
    return md.toString()
}
