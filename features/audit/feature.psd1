@{
    Name = 'audit'
    Command = 'audit'
    Aliases = @()
    EntryPoint = 'audit.ps1'
    Handler = 'Invoke-MeowskyAuditFeature'
    Help = 'help.txt'
    Description = 'Inspect a local workspace for maintainability concerns'
    SkipWorkRoot = $true
    AcceptsArguments = $true
}
