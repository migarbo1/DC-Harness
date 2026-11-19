claude cli installation in windows powershell:
1. Install claude from source
`irm https://claude.ai/install.ps1 | iex`
2. add claude to path
`[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";$env:USERPROFILE\.local\bin", "User")`
3. close terminal