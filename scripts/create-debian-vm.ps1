[CmdletBinding()]
param(
    [string]$VmName = 'Debian SIT Lab',
    [ValidateRange(1024,65535)][int]$SshPort = 2222,
    [ValidateRange(2048,32768)][int]$MemoryMB = 6144,
    [ValidateRange(1,16)][int]$CpuCount = 4,
    [ValidateRange(20,200)][int]$DiskGB = 40,
    [string]$IsoPath,
    [Security.SecureString]$GuestPassword
)

$ErrorActionPreference = 'Stop'
$virtualBox = Join-Path $env:ProgramFiles 'Oracle\VirtualBox'
$vboxManage = Join-Path $virtualBox 'VBoxManage.exe'
if (-not (Test-Path -LiteralPath $vboxManage)) {
    throw 'Install VirtualBox first: winget install --id Oracle.VirtualBox --exact --source winget'
}

function Invoke-VBox {
    & $vboxManage @args
    if ($LASTEXITCODE -ne 0) { throw "VBoxManage $($args[0]) failed ($LASTEXITCODE)." }
}

$vmRoot = Join-Path $env:USERPROFILE 'VirtualBox VMs'
$vmFolder = Join-Path $vmRoot $VmName
$registeredVms = Invoke-VBox list vms
if (($registeredVms -match ('^"' + [regex]::Escape($VmName) + '"\s')) -or (Test-Path -LiteralPath $vmFolder)) {
    throw "A VM or folder named '$VmName' already exists. Use -VmName to create a separate VM."
}
$existingListener = Get-NetTCPConnection -State Listen -LocalPort $SshPort -ErrorAction SilentlyContinue
if ($existingListener) { throw "Port $SshPort is busy. Pass a different -SshPort." }

if (-not $IsoPath) {
    $downloadDir = Join-Path $env:USERPROFILE 'Downloads\sit-debian'
    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
    $mirror = 'https://cdimage.debian.org/debian-cd/current/amd64/iso-cd'
    $sumsFile = Join-Path $downloadDir 'SHA512SUMS'
    curl.exe -fLsS --retry 3 -o $sumsFile "$mirror/SHA512SUMS"
    if ($LASTEXITCODE -ne 0) { throw 'Could not download Debian checksums.' }
    $isoEntry = Select-String -LiteralPath $sumsFile -Pattern '^(?<sha>[a-fA-F0-9]{128})\s+\*?(?<name>debian-13\.[0-9.]+-amd64-netinst\.iso)$' |
        Select-Object -First 1
    if (-not $isoEntry) { throw 'Debian 13 amd64 netinst is missing from the official list. Pass a verified ISO using -IsoPath.' }

    $isoName = $isoEntry.Matches[0].Groups['name'].Value
    $expectedHash = $isoEntry.Matches[0].Groups['sha'].Value
    $IsoPath = Join-Path $downloadDir $isoName
    if (-not (Test-Path -LiteralPath $IsoPath) -or (Get-FileHash -LiteralPath $IsoPath -Algorithm SHA512).Hash -ne $expectedHash) {
        Write-Host "Downloading $isoName"
        $partialPath = "$IsoPath.part"
        curl.exe -fL --retry 3 -o $partialPath "$mirror/$isoName"
        if ($LASTEXITCODE -ne 0) { throw 'Could not download the Debian ISO.' }
        if ((Get-FileHash -LiteralPath $partialPath -Algorithm SHA512).Hash -ne $expectedHash) {
            throw 'The Debian ISO failed SHA-512 verification.'
        }
        Move-Item -Force -LiteralPath $partialPath -Destination $IsoPath
    }
}
$IsoPath = (Get-Item -LiteralPath $IsoPath).FullName
if (-not $GuestPassword) {
    $GuestPassword = Read-Host 'Choose a Debian password for lab (SSH and sudo)' -AsSecureString
}
if ($GuestPassword.Length -eq 0) { throw 'The Debian password must not be empty.' }

Invoke-VBox createvm "--name=$VmName" --ostype=Debian13_64 "--basefolder=$vmRoot" --register
Invoke-VBox modifyvm $VmName "--memory=$MemoryMB" "--cpus=$CpuCount" --vram=32 --graphicscontroller=vmsvga --firmware=bios --rtcuseutc=on --nic1=nat --boot1=disk --boot2=dvd --boot3=none --boot4=none --audio-enabled=off
Invoke-VBox modifyvm $VmName --natpf1 "ssh,tcp,127.0.0.1,$SshPort,,22"
$disk = Join-Path $vmFolder 'debian.vdi'
Invoke-VBox createmedium disk "--filename=$disk" "--size=$($DiskGB * 1024)" --format=VDI
Invoke-VBox storagectl $VmName --name=SATA --add=sata --controller=IntelAhci --portcount=3 --bootable=on
Invoke-VBox storageattach $VmName --storagectl=SATA --port=0 --device=0 --type=hdd "--medium=$disk"
Invoke-VBox storageattach $VmName --storagectl=SATA --port=1 --device=0 --type=dvddrive --medium=emptydrive

$passwordFile = New-TemporaryFile
$templateFile = New-TemporaryFile
$passwordPointer = [IntPtr]::Zero
try {
    $encoding = New-Object Text.UTF8Encoding($false)
    $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($GuestPassword)
    [IO.File]::WriteAllText($passwordFile.FullName, [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer), $encoding)
    $templatePath = Join-Path $virtualBox 'UnattendedTemplates\debian_preseed.cfg'
    $preseed = [IO.File]::ReadAllText($templatePath).Replace("`r`n", "`n")
    [IO.File]::WriteAllText($templateFile.FullName, $preseed + "`n" + 'tasksel tasksel/first multiselect standard, ssh-server' + "`n", $encoding)

    # VBoxManage prints the guest password in its installation summary.
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $installOutput = & $vboxManage unattended install $VmName "--iso=$IsoPath" --user=lab --full-user-name='SIT Lab' "--user-password-file=$($passwordFile.FullName)" --hostname=debian-sit.local --locale=en_US --country=US --package-selection-adjustment=minimal --no-install-additions "--script-template=$($templateFile.FullName)" --start-vm=headless 2>&1
        $installStatus = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($installStatus -ne 0) {
        $installOutput | ForEach-Object { "$_" } | Where-Object { $_ -match 'error:' -and $_ -notmatch '(?i)password' } | Write-Host
        throw "VirtualBox could not start unattended installation ($installStatus)."
    }
} finally {
    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
    Remove-Item -LiteralPath $passwordFile.FullName,$templateFile.FullName -Force
}

Write-Host "Debian installation started in '$VmName'. Wait for SSH to become available."
Write-Host "Connect with: ssh -L 8088:127.0.0.1:8088 -p $SshPort lab@127.0.0.1"
