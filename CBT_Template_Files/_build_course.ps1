#Requires -Version 5.1
<#
.SYNOPSIS
    Generates CBT wrapper HTML files from a course manifest and HTML templates.

.DESCRIPTION
    Reads _course_manifest.json, then for each section reads
    _TPL_section_wrapper.html, substitutes all {{PLACEHOLDER}} tokens with
    manifest data, and writes the output file (e.g. S3_Section3.html).
    Also generates CBT_Introduction.html and EXAM_Final.html from their
    respective templates.

.USAGE
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    cd C:\S2L_Dev\CBT-Island-Mode-Systems
    .\_cbt_template\_build_course.ps1

    Add -WhatIf to preview substitutions without writing files.
    Add -Verbose to see every placeholder replaced.

.NOTES
    All output files are written UTF-8 (no BOM) to the workspace root.
    Template files must exist in the same directory as this script.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── PATHS ──────────────────────────────────────────────────────
$ScriptDir    = $PSScriptRoot
$WorkspaceDir = Split-Path $ScriptDir -Parent
$ManifestPath = Join-Path $WorkspaceDir '_course_manifest.json'

function Read-Template([string]$Name) {
    $path = Join-Path $ScriptDir $Name
    if (-not (Test-Path $path)) { throw "Template not found: $path" }
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Write-Output-File([string]$RelName, [string]$Content) {
    $outPath = Join-Path $WorkspaceDir $RelName
    if ($PSCmdlet.ShouldProcess($outPath, 'Write HTML file')) {
        [System.IO.File]::WriteAllText($outPath, $Content, (New-Object System.Text.UTF8Encoding $false))
        Write-Host "  [OK] $RelName" -ForegroundColor Green
    } else {
        Write-Host "  [WhatIf] Would write: $RelName" -ForegroundColor Yellow
    }
}

# ── LOAD MANIFEST ──────────────────────────────────────────────
Write-Host "`nLoading manifest: $ManifestPath" -ForegroundColor Cyan
$M = Get-Content $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

# ── HELPER: escape text for single-quoted JS string literal ───
function Escape-JsString([string]$s) {
    # Escape backslashes first, then single quotes
    return $s.Replace('\', '\\').Replace("'", "\'")
}

# ── HELPER: JS string — handles multiline via concatenation ───
function To-JsStr([string]$s) {
    return "'" + (Escape-JsString $s) + "'"
}

# ══════════════════════════════════════════════════════════════
#  BUILD SECTION WRAPPERS
# ══════════════════════════════════════════════════════════════
Write-Host "`nBuilding section wrappers..." -ForegroundColor Cyan

foreach ($section in $M.sections) {
    $n          = $section.num
    $totalSects = $M.sections.Count
    Write-Host "  Section ${n}: $($section.title)"

    # ── BUILD SCREENS_HTML ──────────────────────────────────────
    $screensHtml  = ""
    $screenIdx    = 0
    foreach ($scr in $section.screens) {
        $isActive = if ($screenIdx -eq 0) { ' active' } else { '' }
        $screensHtml += @"

  <!-- ── SCREEN $($screenIdx + 1): $($scr.label.ToUpper()) ─────────────────── -->
  <div class="screen iframe-screen$isActive" id="$($scr.id)"
       role="tabpanel" aria-label="$($scr.label)">
    <iframe src="$($scr.file)"
            width="1040" height="510"
            sandbox="allow-scripts allow-same-origin"
            frameborder="0" scrolling="no"
            title="$($scr.label)"></iframe>
  </div>
"@
        $screenIdx++
    }

    # ── BUILD SCREENS_JS ───────────────────────────────────────
    $jsItems = @()
    foreach ($scr in $section.screens) {
        $voEscaped = Escape-JsString $scr.vo
        $jsItems += @"
  {
    id:    '$($scr.id)',
    label: '$(Escape-JsString $scr.label)',
    vo:    '$voEscaped'
  }
"@
    }
    # Add quiz screen entry
    $quizVoEscaped = Escape-JsString $section.quiz.quiz_vo
    $jsItems += @"
  {
    id:    '$($section.quiz.screen_id)',
    label: 'Section Quiz $n',
    vo:    '$quizVoEscaped'
  }
"@
    $screensJs = $jsItems -join ",`n"

    # ── BUILD QUIZ_POOL_JS ─────────────────────────────────────
    $poolItems = @()
    foreach ($q in $section.quiz.pool) {
        $stemEsc = Escape-JsString $q.stem
        $optsJs = ($q.options | ForEach-Object {
            "      { val: '$($_.val)', text: '$(Escape-JsString $_.text)' }"
        }) -join ",`n"
        $fbCorrect = Escape-JsString $q.feedback.correct
        $fbWrong   = Escape-JsString $q.feedback.wrong
        $fbRetry   = Escape-JsString $q.feedback.retry
        $poolItems += @"
  {
    stem: '$stemEsc',
    options: [
$optsJs
    ],
    correct: '$($q.correct)',
    feedback: {
      correct: '$fbCorrect',
      wrong:   '$fbWrong',
      retry:   '$fbRetry'
    }
  }
"@
    }
    $quizPoolJs = $poolItems -join ",`n"

    # ── CALCULATE TOTALS ───────────────────────────────────────
    $totalScreens   = $section.screens.Count + 1   # lesson screens + quiz
    $quizPickLabel  = "$($section.quiz.pick) Questions"
    $sectionOfN     = "$n of $totalSects"

    # ── LOAD TEMPLATE AND SUBSTITUTE ──────────────────────────
    $html = Read-Template '_TPL_section_wrapper.html'

    $substitutions = @{
        '{{COURSE_ID}}'              = $M.course.id
        '{{COURSE_TITLE}}'           = $M.course.title
        '{{SECTION_NUM}}'            = $n.ToString()
        '{{SECTION_OF_N}}'           = $sectionOfN
        '{{SECTION_TITLE}}'          = $section.title
        '{{SECTION_DURATION}}'       = $section.duration
        '{{SCREENS_HTML}}'           = $screensHtml
        '{{SCREENS_JS}}'             = $screensJs
        '{{QUIZ_POOL_JS}}'           = $quizPoolJs
        '{{QUIZ_PICK}}'              = $section.quiz.pick.ToString()
        '{{QUIZ_PICK_LABEL}}'        = $quizPickLabel
        '{{QUIZ_PASS_THRESHOLD}}'    = $section.quiz.pass_threshold.ToString()
        '{{QUIZ_PASS_MSG}}'          = (Escape-JsString $section.quiz.pass_msg)
        '{{QUIZ_FAIL_MSG}}'          = (Escape-JsString $section.quiz.fail_msg)
        '{{TOTAL_SCREENS}}'          = $totalScreens.ToString()
        '{{NEXT_SECTION_HREF}}'      = $section.next_section_href
        '{{NEXT_SECTION_BTN_LABEL}}' = $section.next_section_btn_label
    }

    foreach ($kv in $substitutions.GetEnumerator()) {
        if ($html -notlike "*$($kv.Key)*") {
            Write-Warning "  Placeholder not found in template: $($kv.Key)"
        }
        $html = $html.Replace($kv.Key, $kv.Value)
        Write-Verbose "    $($kv.Key) -> $($kv.Value.Substring(0, [Math]::Min(60, $kv.Value.Length)))..."
    }

    Write-Output-File $section.output_file $html
}


# ══════════════════════════════════════════════════════════════
#  BUILD INTRODUCTION
# ══════════════════════════════════════════════════════════════
Write-Host "`nBuilding introduction..." -ForegroundColor Cyan

$intro     = $M.intro
$introHtml = Read-Template '_TPL_intro.html'
$objCount  = $intro.objectives.Count
$totalIntroScreens = $intro.screens.Count

# Build objectives HTML for INT-4
$objHtml = ""
foreach ($obj in $intro.objectives) {
    $objHtml += @"

      <div class="obj" id="obj-$($obj.num)">
        <div class="obj-n" id="on-$($obj.num)">$($obj.num)</div>
        <div>
          <div class="obj-tag">$($obj.tag)</div>
          <div class="obj-body">$($obj.text)</div>
        </div>
      </div>
"@
}

# Build INT-2 cards HTML
$int2Html = ""
foreach ($card in $intro.int2_cards) {
    $int2Html += @"
        <div class="card" style="border-left-color:$($card.border_color);">
          $($card.body)
        </div>
"@
}

# Build INT-3 key points HTML
$int3Html = ""
foreach ($kp in $intro.int3_kp) {
    $int3Html += @"
          <div class="kp">
            <div class="kp-dot $($kp.dot_class)">&#x25C9;</div>
            <div class="kp-body">$($kp.body)</div>
          </div>
"@
}
if ($intro.int3_highlight) {
    $int3Html += @"
          <div class="no-grid">$($intro.int3_highlight)</div>
"@
}
if ($intro.int3_closing) {
    $int3Html += @"
          <div class="kp" style="margin-top:6px;">
            <div class="kp-dot $($intro.int3_closing.dot_class)">!</div>
            <div class="kp-body">$($intro.int3_closing.body)</div>
          </div>
"@
}

# Build SCREENS_JS for intro
$introJsItems = @()
foreach ($scr in $intro.screens) {
    if ($scr.id -eq 's-int4') {
        # Multi-segment VO with revealAt array
        $voSegments = $scr.vo | ForEach-Object { "      " + (To-JsStr $_) }
        $voArray    = $voSegments -join ",`n"
        $revealParts = $scr.revealAt | ForEach-Object { if ($_ -eq $null) { "null" } else { $_.ToString() } }
        $revealArr  = $revealParts -join ", "
        $introJsItems += @"
  {
    id:       '$($scr.id)',
    label:    '$(Escape-JsString $scr.label)',
    vo: [
$voArray
    ],
    revealAt: [$revealArr]
  }
"@
    } else {
        $voEsc = Escape-JsString $scr.vo[0]
        $introJsItems += @"
  {
    id:    '$($scr.id)',
    label: '$(Escape-JsString $scr.label)',
    vo:    ['$voEsc']
  }
"@
    }
}
$introScreensJs = $introJsItems -join ",`n"

$introSubs = @{
    '{{COURSE_ID}}'          = $M.course.id
    '{{COURSE_TITLE}}'       = $M.course.title
    '{{INTRO_TITLE_HTML}}'   = $intro.title_html
    '{{INTRO_SUBTITLE}}'     = $intro.subtitle
    '{{DURATION_BADGE}}'     = $intro.duration_badge
    '{{SECTIONS_BADGE}}'     = $intro.sections_badge
    '{{AUDIENCE_BADGE}}'     = $intro.audience_badge
    '{{FOOTER_LABEL}}'       = $intro.footer_label
    '{{TOTAL_SCREENS}}'      = $totalIntroScreens.ToString()
    '{{OBJ_COUNT}}'          = $objCount.ToString()
    '{{OBJECTIVES_HTML}}'    = $objHtml
    '{{INT2_CARDS_HTML}}'    = $int2Html
    '{{INT3_KP_HTML}}'       = $int3Html
    '{{SCREENS_JS}}'         = $introScreensJs
    '{{FIRST_SECTION_HREF}}' = $intro.first_section_href
}

foreach ($kv in $introSubs.GetEnumerator()) {
    $introHtml = $introHtml.Replace($kv.Key, $kv.Value)
    Write-Verbose "  INTRO: $($kv.Key) replaced"
}

Write-Output-File $intro.output_file $introHtml


# ══════════════════════════════════════════════════════════════
#  BUILD EXAM
# ══════════════════════════════════════════════════════════════
Write-Host "`nBuilding exam..." -ForegroundColor Cyan

$exam     = $M.exam
$examHtml = Read-Template '_TPL_exam.html'

# Build QUESTIONS_JS
$qItems = @()
foreach ($q in $exam.questions) {
    $stemEsc = Escape-JsString $q.stem
    $optJs   = ($q.options | ForEach-Object { "    '" + (Escape-JsString $_) + "'" }) -join ",`n"
    $fbEsc   = Escape-JsString $q.feedback
    $qItems += @"
  {
    num:      $($q.num),
    type:     '$($q.type)',
    stem:     '$stemEsc',
    options:  [
$optJs
    ],
    correct:  $($q.correct),
    feedback: '$fbEsc'
  }
"@
}
$questionsJs = $qItems -join ",`n"

# Build SECTION_NAMES_MAP_JS
$mapLines = $exam.section_names | ForEach-Object {
    "  [$($_[0]), '$(Escape-JsString $_[1])']"
}
$sectionNamesJs = $mapLines -join ",`n"

# Build Q_SECTION_MAP_JS
$qSectionJs = ($exam.q_section_map | ForEach-Object { $_.ToString() }) -join ", "

$examSubs = @{
    '{{COURSE_ID}}'            = $M.course.id
    '{{COURSE_TITLE}}'         = $M.course.title
    '{{EXAM_TOTAL_Q}}'         = $exam.total_questions.ToString()
    '{{EXAM_PASS_SCORE}}'      = $exam.pass_score.ToString()
    '{{EXAM_PASS_PCT}}'        = $exam.pass_pct
    '{{EXAM_INSTR_TITLE}}'     = $exam.instr_title
    '{{EXAM_DURATION}}'        = $exam.duration
    '{{EXAM_PASS_MSG}}'        = (Escape-JsString $exam.pass_msg)
    '{{EXAM_FAIL_MSG}}'        = (Escape-JsString $exam.fail_msg)
    '{{QUESTIONS_JS}}'         = $questionsJs
    '{{SECTION_NAMES_MAP_JS}}' = $sectionNamesJs
    '{{Q_SECTION_MAP_JS}}'     = $qSectionJs
    '{{RETURN_HREF}}'          = $exam.return_href
}

foreach ($kv in $examSubs.GetEnumerator()) {
    $examHtml = $examHtml.Replace($kv.Key, $kv.Value)
    Write-Verbose "  EXAM: $($kv.Key) replaced"
}

Write-Output-File $exam.output_file $examHtml


# ══════════════════════════════════════════════════════════════
#  BUILD SUMMARY WRAPPER
# ══════════════════════════════════════════════════════════════
Write-Host "`nBuilding summary..." -ForegroundColor Cyan

$summary     = $M.summary
$summaryHtml = Read-Template '_TPL_summary_wrapper.html'

# Build SCREENS_HTML for summary
$sumScreensHtml = ""
$sumIdx = 0
foreach ($scr in $summary.screens) {
    $isActive = if ($sumIdx -eq 0) { ' active' } else { '' }
    $sumScreensHtml += @"

  <!-- ── SUMMARY SCREEN $($sumIdx + 1): $($scr.label.ToUpper()) ─────── -->
  <div class="screen iframe-screen$isActive" id="$($scr.id)"
       role="tabpanel" aria-label="$($scr.label)">
    <iframe src="$($scr.file)"
            width="1040" height="510"
            sandbox="allow-scripts allow-same-origin"
            frameborder="0" scrolling="no"
            title="$($scr.label)"></iframe>
  </div>
"@
    $sumIdx++
}

# Build SCREENS_JS for summary
$sumJsItems = @()
foreach ($scr in $summary.screens) {
    $voEscaped = Escape-JsString $scr.vo
    $sumJsItems += @"
  {
    id:    '$($scr.id)',
    label: '$(Escape-JsString $scr.label)',
    vo:    '$voEscaped'
  }
"@
}
$sumScreensJs = $sumJsItems -join ",`n"

$summarySubs = @{
    '{{COURSE_ID}}'       = $M.course.id
    '{{COURSE_TITLE}}'    = $M.course.title
    '{{SUMMARY_TITLE}}'   = 'Course Summary'
    '{{TOTAL_SCREENS}}'   = $summary.screens.Count.ToString()
    '{{SCREENS_HTML}}'    = $sumScreensHtml
    '{{SCREENS_JS}}'      = $sumScreensJs
    '{{NEXT_HREF}}'       = $summary.next_href
    '{{NEXT_BTN_LABEL}}'  = 'Final Exam &#x25b8;'
}

foreach ($kv in $summarySubs.GetEnumerator()) {
    $summaryHtml = $summaryHtml.Replace($kv.Key, $kv.Value)
    Write-Verbose "  SUMMARY: $($kv.Key) replaced"
}

Write-Output-File $summary.output_file $summaryHtml


# ══════════════════════════════════════════════════════════════
#  DONE
# ══════════════════════════════════════════════════════════════
Write-Host "`nBuild complete." -ForegroundColor Cyan
Write-Host "Output files written to: $WorkspaceDir" -ForegroundColor Gray
Write-Host ""
Write-Host "Files generated:"
$M.sections | ForEach-Object { Write-Host "  $($_.output_file)" }
Write-Host "  $($M.intro.output_file)"
Write-Host "  $($M.exam.output_file)"
Write-Host "  $($M.summary.output_file)"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Open the generated wrapper files in a browser to verify."
Write-Host "  2. Edit content screens (S*-*.html) separately using _TPL_content_screen.html."
Write-Host "  3. Update manifest quiz.pool arrays with full question banks."
Write-Host "  4. Re-run this script to regenerate after manifest changes."
