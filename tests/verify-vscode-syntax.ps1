# Isolated settings plus installed VS Code grammars; never launches or configures VS Code.
param([string]$VSCodeAppDirectory)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('meowsky-syntax-tests-' + [guid]::NewGuid().ToString('N'))
$checks = 0
function Assert-Equal($Actual, $Expected, [string]$Label) {
  if ([string]$Actual -cne [string]$Expected) { throw "$Label failed. Expected '$Expected', received '$Actual'." }
  $script:checks++
}
function Assert-Error([scriptblock]$Action, [string]$Pattern) {
  $message = ''
  try { $null = & $Action } catch { $message = $_.Exception.Message }
  Assert-Equal ($message.Length -gt 0 -and $message -like $Pattern) $true "Expected error: $Pattern (received: $message)"
}
try {
  [IO.Directory]::CreateDirectory($fixture) | Out-Null
  . (Join-Path $repo 'powershell/profile.ps1')
  $theme = Read-MeowskyIdentityTheme (Resolve-MeowskyIdentityTheme 'meo-matrix')
  $definition = Get-MeowskyVSCodeDefinition $theme
  $syntax = $definition.Syntax
  $expected = @{
    comment = 'comment'; keyword = 'keyword'; function = 'function'; method = 'function'
    type = 'type'; struct = 'type'; string = 'string'; number = 'number'; operator = 'operator'
    variable = 'text'; parameter = 'text'; property = 'text'; macro = 'constant'; enumMember = 'constant'
    'variable.readonly' = 'constant'; 'property.readonly' = 'constant'
  }
  foreach ($selector in $expected.Keys) { Assert-Equal $syntax.SemanticRules[$selector] $theme.syntax.($expected[$selector]) "Semantic mapping $selector" }
  foreach ($rule in $syntax.TextMateRules) {
    $role = $rule.name.Substring('Meowsky Identity: '.Length)
    Assert-Equal $rule.settings.foreground $theme.syntax.$role "TextMate role $role"
  }
  $other = $theme | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  foreach ($property in $other.syntax.PSObject.Properties) { $property.Value = '#123456' }
  $different = Get-MeowskyVSCodeDefinition $other
  foreach ($selector in $different.Syntax.SemanticRules.Keys) { Assert-Equal $different.Syntax.SemanticRules[$selector] '#123456' 'No hardcoded semantic palette' }
  foreach ($rule in $different.Syntax.TextMateRules) { Assert-Equal $rule.settings.foreground '#123456' 'No hardcoded TextMate palette' }
  Assert-Equal $different.Colors['editor.foreground'] '#123456' 'Unclassified code uses syntax text'
  Assert-Equal $different.Colors['editorError.foreground'] '#123456' 'Errors use syntax error'
  Assert-Equal $different.Colors['editorWarning.foreground'] '#123456' 'Warnings use syntax warning'

  foreach ($text in @('{}', '{"editor.tokenColorCustomizations":{}}', '{"editor.semanticTokenColorCustomizations":{"rules":{}}}')) {
    $updated = Edit-MeowskyVSCodeSettings $text $definition
    $parsed = ConvertFrom-Json $updated
    Assert-Equal $parsed.'editor.semanticHighlighting.enabled' $true 'Semantic highlighting enabled'
    Assert-Equal $parsed.'editor.semanticTokenColorCustomizations'.enabled $true 'Base theme semantic opt-in enabled'
    Assert-Equal $parsed.'editor.semanticTokenColorCustomizations'.rules.function $theme.syntax.function 'Semantic rules merged'
    Assert-Equal @($parsed.'editor.tokenColorCustomizations'.textMateRules).Count $syntax.TextMateRules.Count 'All named fallback rules added'
    Assert-Equal (Edit-MeowskyVSCodeSettings $updated $definition) $updated 'Syntax merge idempotence'
  }
  $jsonc = @'
{
  "workbench.colorTheme": "Existing Theme",
  "editor.fontSize": 17,
  "editor.semanticHighlighting.enabled": false,
  "editor.semanticTokenColorCustomizations": {
    "enabled": false,
    "[Existing Theme]": {"rules":{"variable":"#112233"}},
    "rules": {
      "function": {"foreground":"#000000","bold":true,"italic":false}, // keep styles
      "customType": {"foreground":"#123456","underline":true},
      "variable.readonly:c": "#AABBCC",
    },
  },
  "editor.tokenColorCustomizations": {
    "comments": "#112233",
    "[Existing Theme]": {"strings":"#334455"},
    "textMateRules": [
      {"name":"User rule","scope":"custom.scope","settings":{"foreground":"#123456","fontStyle":"italic"}},
      {"name":"Meowsky Identity: comment","scope":"old.scope","settings":{"foreground":"#000000","fontStyle":"italic"},"customField":true}, // owned color, preserved style
    ],
  },
}
'@
  $updated = Edit-MeowskyVSCodeSettings $jsonc $definition
  foreach ($fragment in @('"workbench.colorTheme": "Existing Theme"', '"editor.fontSize": 17', '"bold":true,"italic":false', '// keep styles', '"customType": {"foreground":"#123456","underline":true}', '"variable.readonly:c": "#AABBCC"', '"[Existing Theme]": {"rules":{"variable":"#112233"}}', '"[Existing Theme]": {"strings":"#334455"}', '"comments": "#112233"', '{"name":"User rule","scope":"custom.scope","settings":{"foreground":"#123456","fontStyle":"italic"}}', '"fontStyle":"italic"', '"customField":true', '// owned color, preserved style')) {
    Assert-Equal ($updated.Contains($fragment)) $true "Preserves unrelated settings/styles: $fragment"
  }
  Assert-Equal ([regex]::Matches($updated, 'Meowsky Identity: comment').Count) 1 'Owned TextMate rule updated without duplication'
  Assert-Equal (Edit-MeowskyVSCodeSettings $updated $definition) $updated 'Preserving styles remains idempotent'
  $second = Edit-MeowskyVSCodeSettings $updated $different
  Assert-Equal ($second.Contains('"foreground":"#123456","bold":true')) $true 'Another identity updates owned foreground only'
  foreach ($text in @('{"editor.semanticTokenColorCustomizations":null}', '{"editor.semanticTokenColorCustomizations":{"rules":[]}}', '{"editor.tokenColorCustomizations":[]}', '{"editor.tokenColorCustomizations":{"textMateRules":{}}}', '{"editor.tokenColorCustomizations":{"textMateRules":[{"name":"Meowsky Identity: comment"},{"name":"Meowsky Identity: comment"}]}}', '{"editor.tokenColorCustomizations":{"textMateRules":[{"name":"Meowsky Identity: comment","settings":null}]}}')) {
    Assert-Error { Edit-MeowskyVSCodeSettings $text $definition } '*'
  }
  $plan = [pscustomobject]@{ Path = 'fixture/settings.json'; Definition = $definition; Changed = $true }
  $preview = (Show-MeowskyVSCodePlan $plan) -join "`n"
  foreach ($fragment in @('semantic function: #00E5FF', 'semantic variable: #E8FFE8', 'Meowsky Identity: comment:', 'editorError.foreground: #FF7070', 'editorWarning.foreground: #FFE45C', 'editor.semanticHighlighting.enabled: True')) {
    Assert-Equal ($preview.Contains($fragment)) $true "Preview shows syntax $fragment"
  }

  # Use VS Code's own installed tokenizer and grammars, without downloading packages.
  if (-not $VSCodeAppDirectory -and $env:LOCALAPPDATA) {
    $base = Join-Path $env:LOCALAPPDATA 'Programs/Microsoft VS Code'
    if (Test-Path -LiteralPath $base -PathType Container) {
      foreach ($candidate in @(Join-Path $base 'resources/app') + @(Get-ChildItem -LiteralPath $base -Directory | ForEach-Object { Join-Path $_.FullName 'resources/app' })) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'node_modules/vscode-textmate/release/main.js')) { $VSCodeAppDirectory = $candidate; break }
      }
    }
  }
  if (-not $VSCodeAppDirectory -or -not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host 'SKIP: Installed grammar tokenization needs Node and VSCodeAppDirectory. Mapping/merge checks still ran.'
  } else {
    $inputPath = Join-Path $fixture 'definition.json'
    [IO.File]::WriteAllText($inputPath, (ConvertTo-Json -InputObject $definition -Depth 12))
    $runnerPath = Join-Path $fixture 'grammars.cjs'
    $runner = @'
const fs = require('fs'), path = require('path');
const [app, repo, input] = process.argv.slice(2);
const tm = require(path.join(app, 'node_modules/vscode-textmate/release/main.js'));
const onig = require(path.join(app, 'node_modules/vscode-oniguruma/release/main.js'));
const definition = JSON.parse(fs.readFileSync(input, 'utf8'));
const grammars = new Map(), languages = new Map(), injections = new Map();
for (const folder of fs.readdirSync(path.join(app, 'extensions'))) {
  const root = path.join(app, 'extensions', folder), manifest = path.join(root, 'package.json');
  if (!fs.existsSync(manifest)) continue;
  const pkg = JSON.parse(fs.readFileSync(manifest, 'utf8'));
  for (const grammar of pkg.contributes?.grammars ?? []) {
    grammars.set(grammar.scopeName, path.join(root, grammar.path));
    if (grammar.language) languages.set(grammar.language, grammar.scopeName);
    for (const target of grammar.injectTo ?? []) {
      injections.set(target, [...(injections.get(target) ?? []), grammar.scopeName]);
    }
  }
}
const cases = [
  ['c','identity-syntax.c',[['#include','include','keyword'],['#define MAX_ITEMS','MAX_ITEMS','constant'],['typedef struct','typedef','keyword'],['typedef struct Item','Item','text'],['const char *name','char','type'],['const char *name','const','keyword'],['static int total','total','function'],['if (item','item','text'],['if (item','if','keyword'],['return item->count','count','text'],['return 0;','return','keyword'],['return 0;','0','number'],['item == NULL','NULL','constant'],['item == NULL','==','operator'],['Item item =','Matrix','string'],['/* Inspect','Inspect','comment']]],
  ['javascript','identity-syntax.js',[['// Inspect','Inspect','comment'],['function total','total','function'],['return 0','return','keyword'],['new Item("Matrix"','Matrix','string'],['const LIMIT = 4','4','number']]],
  ['typescript','identity-syntax.ts',[['interface Item','Item','type'],['function total','total','function'],['const LIMIT','4','number'],['name: "Matrix"','Matrix','string']]],
  ['python','identity-syntax.py',[['# Parameters','Parameters','comment'],['def total','total','function'],['return 0','return','keyword'],['Item("Matrix"','Matrix','string'],['LIMIT = 4','4','number']]],
  ['html','identity-syntax.html',[['<!-- Inspect','Inspect','comment'],['<main class','main','type'],['data-count="4"','4','string'],['const count = 4','4','number']]],
  ['css','identity-syntax.css',[['/* Inspect','Inspect','comment'],['.item, #preview','item','type'],['"Example"','Example','string'],['640px','640','number']]],
  ['scss','identity-syntax.scss',[['// Inspect','Inspect','comment'],['4px','4','number'],['"Example"','Example','string']]],
  ['powershell','identity-syntax.ps1',[['# Inspect','Inspect','comment'],['function Get-ItemTotal','Get-ItemTotal','function'],['return 0','return','keyword'],["$name = 'Matrix'",'Matrix','string']]],
  ['shellscript','identity-syntax.sh',[['# Inspect','Inspect','comment'],['total()','total','function'],['return 1','return','keyword'],["printf '%s: %d",'%s','string']]],
  ['json','identity-syntax.json', [['"count": 4','4','number'],['"name": "Matrix"','Matrix','string'],['"enabled": true','true','constant']]],
  ['yaml','identity-syntax.yaml',[['# Inspect','Inspect','comment'],['count: 4','4','number'],['"Matrix"','Matrix','string'],['enabled: true','true','constant']]],
  ['dockerfile','Dockerfile',[['# Highlighting','Highlighting','comment'],['FROM scratch','FROM','keyword'],['"Matrix"','Matrix','string']]],
  // The installed SQL grammar classifies NULL as a keyword, unlike C's constant.language.
  ['sql','identity-syntax.sql',[['-- Inspect','Inspect','comment'],['SELECT 4','SELECT','keyword'],['SELECT 4','4','number'],["'Matrix'",'Matrix','string'],['NOT NULL','NULL','keyword']]],
  ['markdown','identity-syntax.md',[['# Identity','Identity','keyword'],['`inline code`','inline','string'],['const char','char','type'],['printf("%s','printf','function']]],
];
(async () => {
  const wasm = fs.readFileSync(path.join(app, 'node_modules/vscode-oniguruma/release/onig.wasm'));
  await onig.loadWASM(wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.byteLength));
  const registry = new tm.Registry({
    onigLib: Promise.resolve({createOnigScanner: p => new onig.OnigScanner(p), createOnigString: s => new onig.OnigString(s)}),
    loadGrammar: async scope => grammars.has(scope) ? tm.parseRawGrammar(fs.readFileSync(grammars.get(scope), 'utf8'), grammars.get(scope)) : null,
    getInjections: scope => injections.get(scope) ?? [],
    theme: {settings: [{settings:{foreground:definition.Colors['editor.foreground']}}, ...definition.Syntax.TextMateRules]},
  });
  let failures = 0, checked = 0, skipped = 0;
  for (const [language, file, probes] of cases) {
    const scope = languages.get(language);
    if (!scope) { console.log(`SKIP grammar: ${language}`); skipped++; continue; }
    const grammar = await registry.loadGrammar(scope);
    const lines = fs.readFileSync(path.join(repo, 'docs/samples', file), 'utf8').split(/\r?\n/);
    let state = tm.INITIAL;
    const tokens = lines.map(line => { const result = grammar.tokenizeLine2(line,state); state=result.ruleStack; return result.tokens; });
    let count = 0;
    for (const [match, needle, role] of probes) {
      const index = lines.findIndex(line => line.includes(match));
      const offset = index < 0 ? -1 : lines[index].indexOf(needle, lines[index].indexOf(match));
      if (offset < 0) { console.log(`FAIL ${language}: missing probe ${match}/${needle}`); failures++; continue; }
      const spans = tokens[index]; let metadata;
      for (let i=0;i<spans.length;i+=2) if (spans[i]<=offset) metadata=spans[i+1];
      const color = registry.getColorMap()[(metadata >>> 15) & 511];
      const expected = definition.Syntax.TextMateRules.find(rule => rule.name === `Meowsky Identity: ${role}`).settings.foreground;
      checked++; count++;
      if (color?.toUpperCase() !== expected.toUpperCase()) {
        const detail = grammar.tokenizeLine(lines[index],index ? tm.INITIAL : null).tokens.find(t=>t.startIndex<=offset&&t.endIndex>offset);
        console.log(`FAIL ${language}: ${needle} expected ${role}=${expected}, got ${color}; scopes ${detail?.scopes.join(' ')}`); failures++;
      }
    }
    console.log(`CHECK grammar: ${language} (${count} probes)`);
  }
  console.log(`Grammar result: ${checked} color probes, ${skipped} missing grammars, ${failures} failures. Semantic providers/visual rendering are not tested.`);
  registry.dispose();
  process.exitCode = failures ? 1 : 0;
})().catch(error => { console.error(error); process.exitCode = 1; });
'@
    [IO.File]::WriteAllText($runnerPath, $runner)
    & node $runnerPath $VSCodeAppDirectory $repo $inputPath
    if ($LASTEXITCODE -ne 0) { throw 'Installed grammar color probes failed.' }
  }
  Write-Host "PASS: $checks syntax mapping/merge checks."
} finally {
  $resolved = [IO.Path]::GetFullPath($fixture)
  if ((Split-Path $resolved -Parent) -eq ([IO.Path]::GetTempPath()).TrimEnd('\') -and (Split-Path $resolved -Leaf) -like 'meowsky-syntax-tests-*') {
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
  }
}
