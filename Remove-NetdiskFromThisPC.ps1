#Requires -Version 5.1
<#
.SYNOPSIS
    清除“此电脑”中的百度网盘、123网盘、夸克网盘等网盘入口（不卸载软件）。

.DESCRIPTION
    网盘客户端通常会把自身注册到资源管理器的“命名空间(NameSpace)”中，从而以虚拟盘符/
    文件夹的形式出现在“此电脑”主页(设备与驱动器区域)、左侧导航树或桌面上。
    部分客户端(如百度网盘)会同时注册到当前用户(HKCU)与“本机所有用户(HKLM)”两个位置，
    只删 HKCU 时“此电脑”里仍会残留入口。

    本脚本自动扫描并删除以下三个范围中、显示名匹配关键词的入口：
      HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace
      HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace
      HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer\...(及 HKLM\Wow6432Node 32位视图)

    权限处理：
      - 当前用户(HKCU)入口：无需管理员权限，直接删除；
      - 本机(HKLM)入口：需要管理员权限。若脚本以普通权限运行且发现 HKLM 入口，
        会自动弹出 UAC 请求提升，由提权后的进程完成删除；
      - 若在 -WhatIf 预览模式或取消 UAC，则不会执行任何删除。

    说明：
      1. 只删除“此电脑”中的入口，不会卸载网盘客户端、不影响网盘软件本身；
      2. 部分网盘客户端重新启动后会再次把自己加回“此电脑”，属软件自身行为；
      3. 想连同 HKCU/HKLM\Software\Classes\CLSID 下对应的 CLSID 注册一并删除，
         请加 -RemoveClsid（属于更深层清理）。

.PARAMETER Keywords
    匹配关键词：入口的显示名(注册表默认值)只要包含其中任意一个词即命中。
    默认值覆盖百度网盘、夸克网盘、123网盘等常见网盘，可按需追加，例如：
    -Keywords 百度网盘,夸克网盘,某某网盘

.PARAMETER RemoveClsid
    一并删除 HKCU/HKLM\Software\Classes\CLSID\{GUID} 下的对应 CLSID 注册项。

.PARAMETER RestartExplorer
    清理完成后重启资源管理器，使界面立即刷新（会关闭已打开的文件夹窗口）。

.PARAMETER Force
    跳过删除前的 y/n 确认（适合无人值守/定时任务场景；自动提权时亦使用此参数）。

.EXAMPLE
    .\Remove-NetdiskFromThisPC.ps1
    清理当前用户与全机的网盘入口（发现 HKLM 入口时自动请求管理员权限）。

.EXAMPLE
    .\Remove-NetdiskFromThisPC.ps1 -WhatIf
    仅预览将删除哪些入口（含 HKLM），不执行任何删除。

.EXAMPLE
    .\Remove-NetdiskFromThisPC.ps1 -Keywords 百度网盘,夸克网盘 -RemoveClsid
    只清理百度网盘与夸克网盘，并深度清理对应 CLSID。

.EXAMPLE
    .\Remove-NetdiskFromThisPC.ps1 -RestartExplorer
    清理后重启资源管理器刷新界面。
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
param(
    [string[]]$Keywords = @(
        '百度网盘', '百度云盘', '夸克网盘', '夸克', '123网盘', '123云盘', '阿里云盘', '天翼云盘',
        '迅雷网盘', '迅雷云盘', '腾讯微云', '微云', '115网盘', 'UC网盘', '蓝奏云', '移动云盘',
        '和彩云', '沃云盘', '新浪微盘', '网易网盘', '网盘', '云盘',
        'BaiduNetdisk', 'BaiduYun', 'QuarkNetdisk', 'Quark', 'Xunlei', 'Weiyun'
    ),

    [switch]$RemoveClsid,
    [switch]$RestartExplorer,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Test-Admin {
    # 当前进程是否具有管理员权限
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RegDefault {
    # 读取注册表键的“(默认)”值；键不存在或读取失败时返回 $null
    param([string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $props = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
        $prop = $props.PSObject.Properties['(default)']
        if ($null -ne $prop) { return $prop.Value }
        return $null
    }
    catch {
        return $null
    }
}

function Get-RegValue {
    # 读取注册表键下指定名称的值；键或值不存在时返回 $null
    param([string]$Path, [string]$ValueName)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        return $item.GetValue($ValueName)
    }
    catch {
        return $null
    }
}

function Test-NetdiskName {
    # 名称命中任一关键词(不区分大小写、允许部分包含)则返回 $true
    param($Text)
    if ($null -eq $Text) { return $false }
    $str = [string]$Text
    if ([string]::IsNullOrWhiteSpace($str)) { return $false }
    # 形如 "@xxx.dll,-123" 的间接字符串(资源引用)不含可读名称，跳过避免误判
    if ($str.StartsWith('@')) { return $false }
    foreach ($kw in $Keywords) {
        if ($str -like ('*' + $kw + '*')) { return $true }
    }
    return $false
}

# ---------- 收集命中项(覆盖 HKCU / HKLM / HKLM-32位) ----------
$hits = @()

$sets = @(
    [pscustomobject]@{
        Label        = '当前用户 (HKCU)'
        ExplorerRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
        ClsidRoot    = 'HKCU:\Software\Classes\CLSID'
    },
    [pscustomobject]@{
        Label        = '本机所有用户 (HKLM)'
        ExplorerRoot = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer'
        ClsidRoot    = 'HKLM:\Software\Classes\CLSID'
    },
    [pscustomobject]@{
        Label        = '本机所有用户-32位 (HKLM\Wow6432Node)'
        ExplorerRoot = 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer'
        ClsidRoot    = 'HKLM:\Software\Wow6432Node\Classes\CLSID'
    }
)

foreach ($set in $sets) {
    foreach ($ns in 'MyComputer\NameSpace', 'Desktop\NameSpace') {
        $rootPath = Join-Path -Path $set.ExplorerRoot -ChildPath $ns
        if (-not (Test-Path -LiteralPath $rootPath)) { continue }

        $keys = Get-ChildItem -LiteralPath $rootPath -ErrorAction SilentlyContinue
        foreach ($k in $keys) {
            if (-not $k.PSIsContainer) { continue }

            $guid      = $k.PSChildName
            $entryPath = Join-Path -Path $rootPath -ChildPath $guid
            $nsName    = Get-RegDefault -Path $entryPath
            $clsidPath = Join-Path -Path $set.ClsidRoot -ChildPath $guid
            $clsidName = Get-RegDefault -Path $clsidPath
            # 部分网盘只在 CLSID 的 LocalizedString 中写入显示名(如“夸克网盘”)
            $clsidLoc  = Get-RegValue -Path $clsidPath -ValueName 'LocalizedString'
            if ($null -ne $clsidLoc -and [string]$clsidLoc -like '@*') { $clsidLoc = $null }

            if ((Test-NetdiskName $nsName) -or (Test-NetdiskName $clsidName) -or (Test-NetdiskName $clsidLoc)) {
                $shown = $nsName
                if ([string]::IsNullOrWhiteSpace([string]$shown)) { $shown = $clsidName }
                if ([string]::IsNullOrWhiteSpace([string]$shown)) { $shown = $clsidLoc }
                if ([string]::IsNullOrWhiteSpace([string]$shown)) { $shown = $guid }

                $hits += [pscustomobject]@{
                    Source      = $set.Label
                    Location    = $ns
                    Guid        = $guid
                    DisplayName = [string]$shown
                    EntryPath   = $entryPath
                    ClsidPath   = $clsidPath
                }
            }
        }
    }
}

# ---------- 结果展示 ----------
if ($hits.Count -eq 0) {
    Write-Host ''
    Write-Host ('未在“此电脑”中发现关键词命中的网盘入口。关键词: {0}' -f ($Keywords -join '、')) -ForegroundColor Yellow
    Write-Host '若网盘入口的显示名不在上述关键词中，请用 -Keywords 指定具体名称后重试。' -ForegroundColor Yellow
    return
}

Write-Host ''
Write-Host ('发现 {0} 个网盘入口:' -f $hits.Count) -ForegroundColor Cyan
$i = 0
foreach ($h in $hits) {
    $i++
    Write-Host ('  {0,2}. {1}  ({2})  来源: {3}' -f $i, $h.DisplayName, $h.Guid, $h.Source)
}
Write-Host ''

# ---------- 删除前确认 ----------
$proceed = $true
if (-not $Force -and -not $WhatIfPreference) {
    $ans = Read-Host '输入 y 确认删除以上入口(不会卸载任何软件)；按其他键取消'
    $proceed = ($ans -match '^[yY]')
    if (-not $proceed) {
        Write-Host '已取消，未做任何修改。' -ForegroundColor Yellow
        return
    }
}

$isAdmin    = Test-Admin
$hitsHkcu   = @($hits | Where-Object { $_.Source -like '当前用户*' })
$hitsHklm   = @($hits | Where-Object { $_.Source -like '本机*' })
$elevatedLaunched = $false

# ---------- 删除当前用户(HKCU)入口 ----------
$removedEntry = 0
foreach ($h in $hitsHkcu) {
    if ($PSCmdlet.ShouldProcess($h.EntryPath, ('删除网盘入口: ' + $h.DisplayName + ' (' + $h.Guid + ')'))) {
        try {
            Remove-Item -LiteralPath $h.EntryPath -Recurse -Force -ErrorAction Stop
            $removedEntry++
            Write-Host ('[OK] 已删除入口: {0} ({1})  来源: {2}' -f $h.DisplayName, $h.Guid, $h.Source) -ForegroundColor Green
        }
        catch {
            Write-Warning ('删除失败: {0} ({1}) -> {2}' -f $h.DisplayName, $h.Guid, $_.Exception.Message)
        }
    }
}

# ---------- 删除本机(HKLM)入口：非管理员时自动请求提权 ----------
if ($hitsHklm.Count -gt 0) {
    if (-not $isAdmin -and -not $WhatIfPreference) {
        Write-Host ''
        Write-Host ('发现 {0} 个本机(HKLM)入口，需要管理员权限，正在请求提升...' -f $hitsHklm.Count) -ForegroundColor Cyan

        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'), '-Force')
        if ($RemoveClsid)     { $argList += '-RemoveClsid' }
        if ($RestartExplorer) { $argList += '-RestartExplorer' }

        try {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList -Wait -ErrorAction Stop
            $elevatedLaunched = $true
            Write-Host '已由提升后的管理员进程完成本机(HKLM)入口清理。' -ForegroundColor Green
        }
        catch {
            Write-Warning ('未能获取管理员权限: {0}；请右键“以管理员身份运行”本脚本后再试。' -f $_.Exception.Message)
        }
    }
    else {
        # 已是管理员，或处于 -WhatIf 预览模式
        foreach ($h in $hitsHklm) {
            if ($PSCmdlet.ShouldProcess($h.EntryPath, ('删除网盘入口: ' + $h.DisplayName + ' (' + $h.Guid + ')'))) {
                try {
                    Remove-Item -LiteralPath $h.EntryPath -Recurse -Force -ErrorAction Stop
                    $removedEntry++
                    Write-Host ('[OK] 已删除入口: {0} ({1})  来源: {2}' -f $h.DisplayName, $h.Guid, $h.Source) -ForegroundColor Green
                }
                catch {
                    Write-Warning ('删除失败(可能需管理员权限): {0} ({1}) -> {2}' -f $h.DisplayName, $h.Guid, $_.Exception.Message)
                }
            }
        }
    }
}

# ---------- 可选: 深度清理 CLSID(若已提权运行，子进程已处理，此处会自然跳过) ----------
$removedClsid = 0
if ($RemoveClsid -and -not $elevatedLaunched) {
    Write-Host ''
    Write-Host '开始深度清理 CLSID(仅删除与上述入口同 GUID 的注册项)...' -ForegroundColor Cyan
    $seen = @{}
    foreach ($h in ($hits | Sort-Object Guid -Unique)) {
        if (-not (Test-Path -LiteralPath $h.ClsidPath)) { continue }
        if ($seen.ContainsKey($h.ClsidPath)) { continue }
        $seen[$h.ClsidPath] = $true

        if ($PSCmdlet.ShouldProcess($h.ClsidPath, ('删除 CLSID: ' + $h.DisplayName))) {
            try {
                Remove-Item -LiteralPath $h.ClsidPath -Recurse -Force -ErrorAction Stop
                $removedClsid++
                Write-Host ('[OK] 已删除 CLSID: {0}' -f $h.ClsidPath) -ForegroundColor Green
            }
            catch {
                Write-Warning ('CLSID 删除失败(可能需管理员权限): {0} -> {1}' -f $h.ClsidPath, $_.Exception.Message)
            }
        }
    }
}

# ---------- 汇总 ----------
Write-Host ''
if ($elevatedLaunched) {
    Write-Host '完成: 当前用户入口已由本进程删除，本机(HKLM)入口已由提权进程删除。' -ForegroundColor Green
}
else {
    Write-Host ('完成: 删除入口 {0} 个, 删除 CLSID {1} 个。' -f $removedEntry, $removedClsid) -ForegroundColor Green
}
if ($WhatIfPreference) {
    Write-Host '本次为 -WhatIf 预览模式，未执行任何删除。' -ForegroundColor Yellow
}
else {
    Write-Host '提示: 若界面未立即刷新，请按 F5，或重新运行加 -RestartExplorer 参数。' -ForegroundColor Gray
}

# ---------- 可选: 重启资源管理器刷新(提权子进程已处理过时不再重复) ----------
if ($RestartExplorer -and -not $elevatedLaunched) {
    if ($PSCmdlet.ShouldProcess('explorer.exe', '重启资源管理器以刷新界面')) {
        try {
            Get-Process -Name explorer -ErrorAction Stop | Stop-Process -Force -ErrorAction Stop
            Write-Host '资源管理器已重启，稍候将自动恢复界面...' -ForegroundColor Green
        }
        catch {
            Write-Warning ('重启资源管理器失败: {0}' -f $_.Exception.Message)
        }
    }
}
