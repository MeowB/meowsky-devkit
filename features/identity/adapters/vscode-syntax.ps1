# Syntax definitions are independent of settings discovery and installation.
function Get-MeowskyVSCodeSyntax {
  param($Theme, [switch]$Validated)
  if (-not $Validated) { Assert-MeowskyIdentityTheme -Theme $Theme -ExpectedId $Theme.id }
  $semanticRoles = [ordered]@{
    comment = @('comment'); keyword = @('keyword'); function = @('function', 'method')
    type = @('type', 'class', 'struct', 'enum', 'interface', 'typeParameter', 'namespace')
    string = @('string', 'regexp'); number = @('number'); operator = @('operator')
    text = @('variable', 'parameter', 'property', 'event', 'label')
    constant = @('enumMember', 'macro', 'variable.readonly', 'property.readonly', 'parameter.readonly')
  }
  $semantic = [ordered]@{}
  foreach ($role in $semanticRoles.Keys) {
    foreach ($selector in $semanticRoles[$role]) { $semantic[$selector] = $Theme.syntax.$role }
  }
  # Specific scopes refine broad fallbacks. Avoid coloring entire preprocessor lines.
  $textMateRoles = [ordered]@{
    text = @('source', 'variable', 'punctuation', 'meta.object-literal.key', 'support.type.property-name', 'entity.other.attribute-name')
    comment = @('comment')
    keyword = @('keyword', 'storage.modifier', 'keyword.control.directive', 'punctuation.definition.directive', 'markup.heading', 'entity.name.section')
    function = @('entity.name.function', 'support.function')
    type = @('entity.name.type', 'support.type', 'storage.type', 'entity.name.tag', 'entity.other.inherited-class', 'entity.other.attribute-name.class.css', 'entity.other.attribute-name.id.css', 'entity.other.attribute-name.class.scss', 'entity.other.attribute-name.id.scss')
    string = @('string', 'constant.character', 'markup.inline.raw', 'markup.raw')
    number = @('constant.numeric')
    constant = @('constant.language', 'constant.other', 'variable.other.constant', 'variable.other.enummember', 'entity.name.function.preprocessor', 'entity.name.other.preprocessor.macro', 'support.constant')
    operator = @('keyword.operator')
    error = @('invalid.illegal')
    warning = @('invalid.deprecated')
  }
  $rules = @()
  foreach ($role in $textMateRoles.Keys) {
    $rules += [ordered]@{
      name = "Meowsky Identity: $role"
      scope = $textMateRoles[$role]
      settings = [ordered]@{ foreground = $Theme.syntax.$role }
    }
  }
  [pscustomobject]@{ SemanticRules = $semantic; TextMateRules = $rules }
}

function Add-MeowskyVSCodeSyntaxEdits {
  param([string]$Text, $Root, $Syntax, $RootValues, $Edits)

  $semanticName = 'editor.semanticTokenColorCustomizations'
  $semantic = Get-MeowskySettingsJsonProperty $Root $semanticName
  if ($semantic) {
    if ($semantic.Kind -ne '{') { throw "VS Code '$semanticName' must be an object." }
    $rules = Get-MeowskySettingsJsonProperty $semantic 'rules'
    $semanticValues = [ordered]@{ enabled = $true }
    if ($rules) {
      if ($rules.Kind -ne '{') { throw "VS Code '$semanticName.rules' must be an object." }
      $missing = [ordered]@{}
      foreach ($selector in $Syntax.SemanticRules.Keys) {
        $existing = Get-MeowskySettingsJsonProperty $rules $selector
        if ($existing -and $existing.Kind -eq '{') {
          # Keep existing bold/italic/underline and any other style fields.
          Set-MeowskySettingsJsonProperties $Text $existing ([ordered]@{ foreground = $Syntax.SemanticRules[$selector] }) $Edits
        } else { $missing[$selector] = $Syntax.SemanticRules[$selector] }
      }
      Set-MeowskySettingsJsonProperties $Text $rules $missing $Edits
    } else { $semanticValues['rules'] = $Syntax.SemanticRules }
    Set-MeowskySettingsJsonProperties $Text $semantic $semanticValues $Edits
  } else { $RootValues[$semanticName] = [ordered]@{ enabled = $true; rules = $Syntax.SemanticRules } }

  $tokenName = 'editor.tokenColorCustomizations'
  $tokens = Get-MeowskySettingsJsonProperty $Root $tokenName
  if (-not $tokens) {
    $RootValues[$tokenName] = [ordered]@{ textMateRules = $Syntax.TextMateRules }
    return
  }
  if ($tokens.Kind -ne '{') { throw "VS Code '$tokenName' must be an object." }
  $rules = Get-MeowskySettingsJsonProperty $tokens 'textMateRules'
  if (-not $rules) {
    Set-MeowskySettingsJsonProperties $Text $tokens ([ordered]@{ textMateRules = $Syntax.TextMateRules }) $Edits
    return
  }
  if ($rules.Kind -ne '[') { throw "VS Code '$tokenName.textMateRules' must be an array." }
  $newRules = @()
  foreach ($rule in $Syntax.TextMateRules) {
    $matches = @($rules.Items | Where-Object {
      $name = Get-MeowskySettingsJsonProperty $_ 'name'
      $name -and $name.Kind -eq 'String' -and $name.Value -ceq $rule.name
    })
    if ($matches.Count -gt 1) { throw "Duplicate Identity TextMate rule '$($rule.name)' is ambiguous." }
    if ($matches.Count -eq 0) {
      $newRules += ConvertTo-Json -InputObject $rule -Depth 8 -Compress
      continue
    }
    $existing = $matches[0]
    $settings = Get-MeowskySettingsJsonProperty $existing 'settings'
    $values = [ordered]@{ scope = $rule.scope }
    if ($settings) {
      if ($settings.Kind -ne '{') { throw "Identity TextMate rule '$($rule.name)' settings must be an object." }
      Set-MeowskySettingsJsonProperties $Text $settings $rule.settings $Edits
    } else { $values['settings'] = $rule.settings }
    Set-MeowskySettingsJsonProperties $Text $existing $values $Edits
  }
  Add-MeowskySettingsJsonMembers $rules $newRules $Edits
}
