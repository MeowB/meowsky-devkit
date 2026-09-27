@{
    Name = 'identity'
    Command = 'identity'
    Aliases = @()
    EntryPoint = 'identity.ps1'
    Handler = 'Invoke-MeowskyIdentityFeature'
    Help = 'help.txt'
    Description = 'Explore semantic development environment identities'
    ReadOnly = $true
    AcceptsArguments = $true
}
