@{
    Name = 'c'
    Command = ':CBuild'
    Aliases = @(':CRun')
    EntryPoint = 'c.ps1'
    Handler = 'Invoke-MeowskyCFeature'
    Help = 'help.txt'
    Description = 'Build and run C programs with GCC'
    SkipWorkRoot = $true
    AcceptsAction = $true
    CaseSensitive = $true
}
