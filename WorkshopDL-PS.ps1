# ============================================================
#  WorkshopDL-PS - Steam 创意工坊 Mod 批量下载器
#  配置文件：%APPDATA%\WorkshopDL-PS\config.json
#  依赖：PowerShell 5.1+、SteamCMD
# ============================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------- 常量 ----------------
$AppVersion = "1.2.0"
$ConfigDir  = Join-Path $env:APPDATA "WorkshopDL-PS"
$ConfigPath = Join-Path $ConfigDir "config.json"
$BatchSize  = 20    # 每次 SteamCMD 调用合并下载的 Mod 数量

# ---------------- 游戏预设列表 ----------------
$GamePresets = @(
    @{ AppId="294100"; Name="环世界 (RimWorld)";      CopyToMods=$true  },
    @{ AppId="550";    Name="求生之路2 (L4D2)";       CopyToMods=$false },
    @{ AppId="4000";   Name="Garry's Mod";            CopyToMods=$false },
    @{ AppId="255710"; Name="城市天际线";             CopyToMods=$true  },
    @{ AppId="108600"; Name="僵尸毁灭工程";           CopyToMods=$true  },
    @{ AppId="322330"; Name="饥荒联机版 (DST)";       CopyToMods=$true  },
    @{ AppId="107410"; Name="武装突袭3 (Arma 3)";     CopyToMods=$false },
    @{ AppId="346110"; Name="方舟：生存进化";         CopyToMods=$false },
    @{ AppId="227300"; Name="欧洲卡车模拟2";          CopyToMods=$false },
    @{ AppId="270880"; Name="美国卡车模拟";           CopyToMods=$false },
    @{ AppId="427520"; Name="异星工厂";               CopyToMods=$false },
    @{ AppId="281990"; Name="群星 (Stellaris)";       CopyToMods=$true  },
    @{ AppId="1158310"; Name="十字军之王3";           CopyToMods=$true  },
    @{ AppId="394360"; Name="钢铁雄心4";              CopyToMods=$true  },
    @{ AppId="244850"; Name="太空工程师";             CopyToMods=$true  }
)

# ---------------- 配置工具函数 ----------------
function ConvertTo-HashtableRecursive($obj) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [string] -or $obj -is [int] -or $obj -is [long] `
        -or $obj -is [double] -or $obj -is [bool]) { return $obj }
    if ($obj -is [System.Management.Automation.PSCustomObject]) {
        $ht = @{}
        foreach ($p in $obj.PSObject.Properties) {
            $ht[$p.Name] = ConvertTo-HashtableRecursive $p.Value
        }
        return $ht
    }
    if ($obj -is [System.Collections.IEnumerable]) {
        $arr = @()
        foreach ($item in $obj) { $arr += ConvertTo-HashtableRecursive $item }
        return ,$arr
    }
    return $obj
}

function Get-DefaultConfig {
    $games = @{}
    foreach ($p in $GamePresets) {
        $games[$p.AppId] = @{
            Name       = $p.Name
            ModsDir    = ""
            CopyToMods = $p.CopyToMods
        }
    }
    return @{
        SteamCmd   = ""
        SteamUser  = ""
        InstallDir = ""
        LastGame   = ""
        Games      = $games
    }
}

function Load-Config {
    if (Test-Path $ConfigPath) {
        try {
            $json = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $cfg  = ConvertTo-HashtableRecursive $json
            if (-not $cfg.ContainsKey("Games"))      { $cfg.Games = @{} }
            if (-not $cfg.ContainsKey("SteamCmd"))   { $cfg.SteamCmd = "" }
            if (-not $cfg.ContainsKey("SteamUser"))  { $cfg.SteamUser = "" }
            if (-not $cfg.ContainsKey("InstallDir")) { $cfg.InstallDir = "" }
            if (-not $cfg.ContainsKey("LastGame"))   { $cfg.LastGame = "" }
            $cfg.InstallDir = Normalize-InstallDir $cfg.InstallDir
            return $cfg
        } catch {
            return Get-DefaultConfig
        }
    }
    return Get-DefaultConfig
}

function Save-Config($cfg) {
    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    $cfg | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
}

function Normalize-InstallDir([string]$dir) {
    # SteamCMD 的 +force_install_dir 需要 Steam 根目录，
    # 若用户误填到 steamapps/... 子路径，自动截断回根目录
    if (-not $dir) { return $dir }
    $d = $dir.TrimEnd('\', '/')
    $marker = '\steamapps'
    $idx = $d.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
    if ($idx -gt 0) { return $d.Substring(0, $idx) }
    return $dir
}

function Test-GlobalConfigComplete($cfg) {
    return ($cfg.SteamCmd -and (Test-Path $cfg.SteamCmd) -and
            $cfg.InstallDir -and (Test-Path $cfg.InstallDir) -and $cfg.SteamUser)
}


# ---------------- 全局设置窗口 ----------------
function Show-GlobalSettingsDialog {
    param($CurrentCfg)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "全局设置 - WorkshopDL-PS v$AppVersion"
    $dlg.Size = [System.Drawing.Size]::new(560, 220)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.Font = [System.Drawing.Font]::new("Microsoft YaHei UI", 9)

    $fields = @(
        @{ Key="SteamCmd";   Label="SteamCMD 路径："; IsFile=$true  },
        @{ Key="SteamUser";  Label="Steam 用户名：";  IsFile=$false },
        @{ Key="InstallDir"; Label="SteamCMD 目录：";  IsFile=$false }
    )

    $boxes = @{}
    $y = 20
    foreach ($f in $fields) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $f.Label
        $lbl.Location = [System.Drawing.Point]::new(20, ($y + 4))
        $lbl.Size = [System.Drawing.Size]::new(120, 24)
        $dlg.Controls.Add($lbl)

        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Location = [System.Drawing.Point]::new(145, $y)
        $txt.Size = [System.Drawing.Size]::new(290, 24)
        if ($CurrentCfg[$f.Key]) { $txt.Text = "$($CurrentCfg[$f.Key])" }
        $dlg.Controls.Add($txt)
        $boxes[$f.Key] = $txt

        if ($f.Key -ne "SteamUser") {
            $btn = New-Object System.Windows.Forms.Button
            $btn.Text = "..."
            $btn.Location = [System.Drawing.Point]::new(440, $y)
            $btn.Size = [System.Drawing.Size]::new(35, 24)
            $btn.Tag = @{ TextBox=$txt; IsFile=$f.IsFile }
            $btn.Add_Click({
                $tag = $this.Tag
                if ($tag.IsFile) {
                    $fd = New-Object System.Windows.Forms.OpenFileDialog
                    $fd.Filter = "程序 (*.exe)|*.exe"
                    if ($fd.ShowDialog() -eq "OK") { $tag.TextBox.Text = $fd.FileName }
                } else {
                    $fd = New-Object System.Windows.Forms.FolderBrowserDialog
                    if ($fd.ShowDialog() -eq "OK") { $tag.TextBox.Text = $fd.SelectedPath }
                }
            })
            $dlg.Controls.Add($btn)
        }
        $y += 40
    }

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "保存"
    $btnOk.Location = [System.Drawing.Point]::new(310, ($y + 10))
    $btnOk.Size = [System.Drawing.Size]::new(80, 30)
    $btnOk.DialogResult = "OK"
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "取消"
    $btnCancel.Location = [System.Drawing.Point]::new(400, ($y + 10))
    $btnCancel.Size = [System.Drawing.Size]::new(80, 30)
    $btnCancel.DialogResult = "Cancel"
    $dlg.Controls.Add($btnCancel)

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel

    if ($dlg.ShowDialog() -eq "OK") {
        $result = @{}
        foreach ($k in $boxes.Keys) { $result[$k] = $boxes[$k].Text.Trim() }
        return $result
    }
    return $null
}

# ---------------- 管理游戏窗口 ----------------
function Show-ManageGamesDialog {
    param($Cfg)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "管理游戏"
    $dlg.Size = [System.Drawing.Size]::new(780, 560)
    $dlg.StartPosition = "CenterParent"
    $dlg.Font = [System.Drawing.Font]::new("Microsoft YaHei UI", 9)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.Location = [System.Drawing.Point]::new(12, 12)
    $lv.Size = [System.Drawing.Size]::new(740, 280)
    $lv.View = "Details"
    $lv.FullRowSelect = $true
    $lv.GridLines = $true
    $lv.MultiSelect = $false
    [void]$lv.Columns.Add("游戏名称", 260)
    [void]$lv.Columns.Add("AppID", 90)
    [void]$lv.Columns.Add("Mods 目录", 370)
    $dlg.Controls.Add($lv)

    $y = 310

    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = "游戏名称："
    $lblName.Location = [System.Drawing.Point]::new(12, ($y + 4))
    $lblName.Size = [System.Drawing.Size]::new(80, 24)
    $dlg.Controls.Add($lblName)

    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = [System.Drawing.Point]::new(100, $y)
    $txtName.Size = [System.Drawing.Size]::new(650, 24)
    $dlg.Controls.Add($txtName)

    $y += 35

    $lblAppId = New-Object System.Windows.Forms.Label
    $lblAppId.Text = "AppID："
    $lblAppId.Location = [System.Drawing.Point]::new(12, ($y + 4))
    $lblAppId.Size = [System.Drawing.Size]::new(80, 24)
    $dlg.Controls.Add($lblAppId)

    $txtAppId = New-Object System.Windows.Forms.TextBox
    $txtAppId.Location = [System.Drawing.Point]::new(100, $y)
    $txtAppId.Size = [System.Drawing.Size]::new(180, 24)
    $dlg.Controls.Add($txtAppId)

    $lblPreset = New-Object System.Windows.Forms.Label
    $lblPreset.Text = "从预设选择："
    $lblPreset.Location = [System.Drawing.Point]::new(300, ($y + 4))
    $lblPreset.Size = [System.Drawing.Size]::new(100, 24)
    $dlg.Controls.Add($lblPreset)

    $cmbPreset = New-Object System.Windows.Forms.ComboBox
    $cmbPreset.Location = [System.Drawing.Point]::new(400, $y)
    $cmbPreset.Size = [System.Drawing.Size]::new(350, 24)
    $cmbPreset.DropDownStyle = "DropDownList"
    [void]$cmbPreset.Items.Add("(请选择)")
    foreach ($p in $GamePresets) {
        [void]$cmbPreset.Items.Add("$($p.AppId) - $($p.Name)")
    }
    $cmbPreset.SelectedIndex = 0
    $dlg.Controls.Add($cmbPreset)

    $y += 35

    $lblModsDir = New-Object System.Windows.Forms.Label
    $lblModsDir.Text = "Mods 目录："
    $lblModsDir.Location = [System.Drawing.Point]::new(12, ($y + 4))
    $lblModsDir.Size = [System.Drawing.Size]::new(80, 24)
    $dlg.Controls.Add($lblModsDir)

    $txtModsDir = New-Object System.Windows.Forms.TextBox
    $txtModsDir.Location = [System.Drawing.Point]::new(100, $y)
    $txtModsDir.Size = [System.Drawing.Size]::new(540, 24)
    $dlg.Controls.Add($txtModsDir)

    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Text = "..."
    $btnBrowse.Location = [System.Drawing.Point]::new(645, $y)
    $btnBrowse.Size = [System.Drawing.Size]::new(35, 24)
    $btnBrowse.Add_Click({
        $fd = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($fd.ShowDialog() -eq "OK") { $txtModsDir.Text = $fd.SelectedPath }
    })
    $dlg.Controls.Add($btnBrowse)

    $y += 35

    $chkCopy = New-Object System.Windows.Forms.CheckBox
    $chkCopy.Text = "下载后自动复制到 Mods 目录"
    $chkCopy.Location = [System.Drawing.Point]::new(100, $y)
    $chkCopy.Size = [System.Drawing.Size]::new(300, 24)
    $chkCopy.Checked = $true
    $dlg.Controls.Add($chkCopy)

    $y += 45

    $refreshList = {
        $lv.Items.Clear()
        foreach ($appId in ($Cfg.Games.Keys | Sort-Object)) {
            $g = $Cfg.Games[$appId]
            $item = New-Object System.Windows.Forms.ListViewItem("$($g.Name)")
            [void]$item.SubItems.Add("$appId")
            [void]$item.SubItems.Add("$($g.ModsDir)")
            $item.Tag = $appId
            [void]$lv.Items.Add($item)
        }
    }
    & $refreshList

    $lv.Add_SelectedIndexChanged({
        if ($lv.SelectedItems.Count -eq 0) { return }
        $appId = $lv.SelectedItems[0].Tag
        $g = $Cfg.Games[$appId]
        $txtName.Text    = "$($g.Name)"
        $txtAppId.Text   = "$appId"
        $txtModsDir.Text = "$($g.ModsDir)"
        $chkCopy.Checked = [bool]$g.CopyToMods
    })

    $cmbPreset.Add_SelectedIndexChanged({
        if ($cmbPreset.SelectedIndex -le 0) { return }
        $sel = $cmbPreset.SelectedItem.ToString()
        $parts = $sel -split ' - ', 2
        if ($parts.Count -eq 2) {
            $txtAppId.Text = $parts[0]
            $txtName.Text  = $parts[1]
        }
    })

    $btnAdd = New-Object System.Windows.Forms.Button
    $btnAdd.Text = "添加为新游戏"
    $btnAdd.Location = [System.Drawing.Point]::new(12, $y)
    $btnAdd.Size = [System.Drawing.Size]::new(130, 32)
    $dlg.Controls.Add($btnAdd)

    $btnAdd.Add_Click({
        $appId = $txtAppId.Text.Trim()
        $name  = $txtName.Text.Trim()
        if (-not $appId -or -not $name) {
            [System.Windows.Forms.MessageBox]::Show("AppID 和游戏名称不能为空")
            return
        }
        if ($appId -notmatch '^\d+$') {
            [System.Windows.Forms.MessageBox]::Show("AppID 必须是纯数字")
            return
        }
        if ($Cfg.Games.ContainsKey($appId)) {
            [System.Windows.Forms.MessageBox]::Show("该 AppID 已存在")
            return
        }
        $Cfg.Games[$appId] = @{
            Name       = $name
            ModsDir    = $txtModsDir.Text.Trim()
            CopyToMods = $chkCopy.Checked
        }
        & $refreshList
        Save-Config $Cfg
    })

    $btnUpdate = New-Object System.Windows.Forms.Button
    $btnUpdate.Text = "保存修改"
    $btnUpdate.Location = [System.Drawing.Point]::new(152, $y)
    $btnUpdate.Size = [System.Drawing.Size]::new(110, 32)
    $dlg.Controls.Add($btnUpdate)

    $btnUpdate.Add_Click({
        if ($lv.SelectedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("请先在列表中选择要修改的游戏")
            return
        }
        $oldAppId = $lv.SelectedItems[0].Tag
        $appId = $txtAppId.Text.Trim()
        $name  = $txtName.Text.Trim()
        if (-not $appId -or -not $name) { return }
        if ($appId -notmatch '^\d+$') {
            [System.Windows.Forms.MessageBox]::Show("AppID 必须是纯数字")
            return
        }

        if ($appId -ne $oldAppId) {
            if ($Cfg.Games.ContainsKey($appId)) {
                [System.Windows.Forms.MessageBox]::Show("新的 AppID 已存在")
                return
            }
            $Cfg.Games.Remove($oldAppId)
        }
        $Cfg.Games[$appId] = @{
            Name       = $name
            ModsDir    = $txtModsDir.Text.Trim()
            CopyToMods = $chkCopy.Checked
        }
        & $refreshList
        Save-Config $Cfg
    })

    $btnDelete = New-Object System.Windows.Forms.Button
    $btnDelete.Text = "删除选中"
    $btnDelete.Location = [System.Drawing.Point]::new(272, $y)
    $btnDelete.Size = [System.Drawing.Size]::new(110, 32)
    $dlg.Controls.Add($btnDelete)

    $btnDelete.Add_Click({
        if ($lv.SelectedItems.Count -eq 0) { return }
        $appId = $lv.SelectedItems[0].Tag
        $r = [System.Windows.Forms.MessageBox]::Show("确定删除游戏 '$($Cfg.Games[$appId].Name)'？", "确认", "YesNo")
        if ($r -eq "Yes") {
            $Cfg.Games.Remove($appId)
            & $refreshList
            Save-Config $Cfg
        }
    })

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "关闭"
    $btnClose.Location = [System.Drawing.Point]::new(662, $y)
    $btnClose.Size = [System.Drawing.Size]::new(90, 32)
    $btnClose.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($btnClose)

    [void]$dlg.ShowDialog()
}

# ---------------- 加载配置 ----------------
$Cfg = Load-Config

# ---------------- 跨线程通信 ----------------
$sync = [hashtable]::Synchronized(@{})
$sync.Log      = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
$sync.Running  = $false
$sync.Cfg      = $Cfg
$sync.AppId    = ""
$sync.FailFast = $true

# ---------------- 主窗口 ----------------
$form            = New-Object System.Windows.Forms.Form
$form.Text       = "WorkshopDL-PS v$AppVersion - Steam 创意工坊下载器"
$form.Size       = [System.Drawing.Size]::new(740, 620)
$form.StartPosition = "CenterScreen"
$form.Font       = [System.Drawing.Font]::new("Microsoft YaHei UI", 9)
$form.MinimumSize = [System.Drawing.Size]::new(600, 520)

# 游戏选择行
$lblGame = New-Object System.Windows.Forms.Label
$lblGame.Text = "游戏："
$lblGame.Location = [System.Drawing.Point]::new(12, 15)
$lblGame.Size = [System.Drawing.Size]::new(50, 24)
$form.Controls.Add($lblGame)

$cmbGame = New-Object System.Windows.Forms.ComboBox
$cmbGame.Location = [System.Drawing.Point]::new(62, 12)
$cmbGame.Size = [System.Drawing.Size]::new(380, 24)
$cmbGame.DropDownStyle = "DropDownList"
$cmbGame.DisplayMember = "Display"
$form.Controls.Add($cmbGame)

$btnManage = New-Object System.Windows.Forms.Button
$btnManage.Text = "管理游戏"
$btnManage.Location = [System.Drawing.Point]::new(452, 11)
$btnManage.Size = [System.Drawing.Size]::new(100, 26)
$form.Controls.Add($btnManage)

$btnGlobalSettings = New-Object System.Windows.Forms.Button
$btnGlobalSettings.Text = "全局设置"
$btnGlobalSettings.Location = [System.Drawing.Point]::new(560, 11)
$btnGlobalSettings.Size = [System.Drawing.Size]::new(100, 26)
$form.Controls.Add($btnGlobalSettings)

# 输入标签
$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = "粘贴 Mod ID（每行一个 / 逗号 / 空格 / 创意工坊链接都行）："
$lbl.Location = [System.Drawing.Point]::new(12, 48)
$lbl.Size = [System.Drawing.Size]::new(500, 20)
$form.Controls.Add($lbl)

$btnImport = New-Object System.Windows.Forms.Button
$btnImport.Text = "从文件导入"
$btnImport.Location = [System.Drawing.Point]::new(600, 45)
$btnImport.Size = [System.Drawing.Size]::new(112, 26)
$form.Controls.Add($btnImport)

# 输入框
$txtInput            = New-Object System.Windows.Forms.TextBox
$txtInput.Multiline  = $true
$txtInput.ScrollBars = "Vertical"
$txtInput.Location   = [System.Drawing.Point]::new(12, 72)
$txtInput.Size       = [System.Drawing.Size]::new(700, 130)
$txtInput.Anchor     = "Top,Left,Right"
$form.Controls.Add($txtInput)

# 按钮栏
$btnGo             = New-Object System.Windows.Forms.Button
$btnGo.Text        = "开始下载"
$btnGo.Location    = [System.Drawing.Point]::new(12, 210)
$btnGo.Size        = [System.Drawing.Size]::new(110, 32)
$form.Controls.Add($btnGo)

$btnOpen           = New-Object System.Windows.Forms.Button
$btnOpen.Text      = "打开 Mods 目录"
$btnOpen.Location  = [System.Drawing.Point]::new(132, 210)
$btnOpen.Size      = [System.Drawing.Size]::new(130, 32)
$form.Controls.Add($btnOpen)

$btnClear          = New-Object System.Windows.Forms.Button
$btnClear.Text     = "清空日志"
$btnClear.Location = [System.Drawing.Point]::new(272, 210)
$btnClear.Size     = [System.Drawing.Size]::new(100, 32)
$form.Controls.Add($btnClear)

$btnConfigCurrent  = New-Object System.Windows.Forms.Button
$btnConfigCurrent.Text = "配置当前游戏"
$btnConfigCurrent.Location = [System.Drawing.Point]::new(382, 210)
$btnConfigCurrent.Size = [System.Drawing.Size]::new(130, 32)
$form.Controls.Add($btnConfigCurrent)

# 失败策略：单选
$rbStop = New-Object System.Windows.Forms.RadioButton
$rbStop.Text = "失败即停"
$rbStop.Location = [System.Drawing.Point]::new(530, 218)
$rbStop.Size = [System.Drawing.Size]::new(80, 22)
$rbStop.Checked = $true
$form.Controls.Add($rbStop)

$rbSkip = New-Object System.Windows.Forms.RadioButton
$rbSkip.Text = "跳过失败继续"
$rbSkip.Location = [System.Drawing.Point]::new(614, 218)
$rbSkip.Size = [System.Drawing.Size]::new(110, 22)
$form.Controls.Add($rbSkip)

# 日志
$txtLog            = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline  = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.ReadOnly   = $true
$txtLog.BackColor  = [System.Drawing.Color]::FromArgb(24, 24, 24)
$txtLog.ForeColor  = [System.Drawing.Color]::LightGreen
$txtLog.Font       = [System.Drawing.Font]::new("Consolas", 9)
$txtLog.Location   = [System.Drawing.Point]::new(12, 250)
$txtLog.Size       = [System.Drawing.Size]::new(700, 320)
$txtLog.Anchor     = "Top,Bottom,Left,Right"
$form.Controls.Add($txtLog)

# ---------------- 填充游戏下拉框 ----------------
function Refresh-GameCombo {
    $cmbGame.Items.Clear()
    $sorted = $Cfg.Games.Keys | Sort-Object { $Cfg.Games[$_].Name }
    foreach ($appId in $sorted) {
        $g = $Cfg.Games[$appId]
        $display = if ($g.ModsDir) { $g.Name } else { "$($g.Name)  ⚠ 未配置 Mods 目录" }
        $obj = [pscustomobject]@{ AppId = "$appId"; Display = "$display" }
        [void]$cmbGame.Items.Add($obj)
    }
    if ($cmbGame.Items.Count -gt 0) {
        $idx = 0
        for ($i = 0; $i -lt $cmbGame.Items.Count; $i++) {
            if ($cmbGame.Items[$i].AppId -eq $Cfg.LastGame) { $idx = $i; break }
        }
        $cmbGame.SelectedIndex = $idx
    }
}

Refresh-GameCombo

$cmbGame.Add_SelectedIndexChanged({
    if ($cmbGame.SelectedItem) {
        $Cfg.LastGame = $cmbGame.SelectedItem.AppId
        Save-Config $Cfg
    }
})

# ---------------- 后台下载 ----------------
$script:Runspace = $null
$script:PSHandle = $null

function Start-Download {
    param([string[]]$Ids)

    if ($script:PSHandle -and -not $script:PSHandle.IsCompleted) { return }

    # 清理上一次已完成的 runspace/ps，避免句柄与线程泄漏
    if ($script:PSHandle) {
        try { $script:PSHandle.Dispose() } catch { }
        $script:PSHandle = $null
    }
    if ($script:Runspace) {
        try { $script:Runspace.Dispose() } catch { }
        $script:Runspace = $null
    }

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "MTA"
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()
    $rs.SessionStateProxy.SetVariable("sync", $sync)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($Ids, $BatchSize)

        function Write-Log([string]$msg) {
            [void]$sync.Log.Add(("[" + (Get-Date -Format 'HH:mm:ss') + "] " + $msg))
        }

        # runspace 与主脚本作用域隔离，此处需重复定义命令行参数转义函数
        function ConvertTo-ArgString([string]$a) {
            if ($null -eq $a -or $a -eq '') { return '""' }
            if ($a -notmatch '[\s"]') { return $a }
            $s = [regex]::Replace($a, '(\\*)"', '$1$1\"')
            $s = [regex]::Replace($s, '(\\+)$', '$1$1')
            return '"' + $s + '"'
        }

        $cfg       = $sync.Cfg
        $appId     = $sync.AppId
        $failFast  = $sync.FailFast
        $gameCfg   = $cfg.Games[$appId]
        $total     = $Ids.Count
        $okCount   = 0
        $failCount = 0
        $maxRetry  = 3
        $numBatches = [Math]::Ceiling($total / $BatchSize)
        $globalIdx = 0
        $batchNo   = 0

        while ($globalIdx -lt $total) {
            $batchNo++
            $bStart = $globalIdx
            $bEnd   = [Math]::Min($globalIdx + $BatchSize - 1, $total - 1)
            $pending = @($Ids[$bStart..$bEnd])
            $globalIdx = $bEnd + 1

            Write-Log "(批次 $batchNo/$numBatches) 下载 $($pending.Count) 个 Mod：$($pending -join ', ')"

            # 记录本批各 ID 下载前的文件数，兜底时对比，避免把残留/半成品误判为成功
            $baseline = @{}
            foreach ($id in $pending) {
                $bp = Join-Path $cfg.InstallDir "steamapps\workshop\content\$appId\$id"
                $baseline[$id] = if (Test-Path $bp) {
                    (Get-ChildItem $bp -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
                } else { 0 }
            }

            $output = ""

            # ---------- 重试循环 ----------
            for ($attempt = 1; $attempt -le $maxRetry; $attempt++) {
                $tempOut = [System.IO.Path]::GetTempFileName()
                $tempErr = "$tempOut.err"
                try {
                    # 合并本批所有待下载 ID，一次 SteamCMD 调用完成下载
                    $loginUser = if ($cfg.SteamUser) { $cfg.SteamUser } else { "anonymous" }
                    $sargs = @(
                        "+force_install_dir", $cfg.InstallDir,
                        "+login", $loginUser
                    )
                    foreach ($id in $pending) {
                        $sargs += @("+workshop_download_item", $appId, $id)
                    }
                    $sargs += "+quit"
                    # 按 Windows 规则转义参数，防止含空格/引号的路径被拆分
                    $quotedArgs = @($sargs | ForEach-Object { ConvertTo-ArgString $_ })

                    # 用 Start-Process 调用，给 SteamCMD 一个独立的隐藏 console
                    Start-Process -FilePath $cfg.SteamCmd `
                        -ArgumentList $quotedArgs `
                        -Wait -PassThru `
                        -WindowStyle Hidden `
                        -RedirectStandardOutput $tempOut `
                        -RedirectStandardError $tempErr | Out-Null
                    $output = (Get-Content $tempOut -Raw -ErrorAction SilentlyContinue)
                    if (-not $output) { $output = "" }
                    $errOut = (Get-Content $tempErr -Raw -ErrorAction SilentlyContinue)
                    if ($errOut) { $output += "`n" + $errOut }
                } catch {
                    $output = "EXCEPTION: $_"
                } finally {
                    Remove-Item $tempOut, $tempErr -Force -ErrorAction SilentlyContinue
                }

                # 方式一：输出匹配到 Success，提取每个成功的 ID
                $okIds = @()
                foreach ($m in [regex]::Matches($output, 'Success\.\s*Downloaded item\s+(\d+)')) {
                    $okId = $m.Groups[1].Value
                    if ($okIds -notcontains $okId) { $okIds += $okId }
                }

                # 方式二：文件系统兜底——仅在最后一次重试后启用，且要求文件数相比下载前确有增加，
                # 避免把中途失败留下的半成品或历史残留误判为成功
                if ($attempt -eq $maxRetry) {
                    foreach ($id in $pending) {
                        if ($okIds -contains $id) { continue }
                        $checkPath = Join-Path $cfg.InstallDir "steamapps\workshop\content\$appId\$id"
                        if (Test-Path $checkPath) {
                            $fileCount = (Get-ChildItem $checkPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
                            $baseCount = if ($baseline.ContainsKey($id)) { $baseline[$id] } else { 0 }
                            if ($fileCount -gt $baseCount) {
                                Write-Log "    ⚠ [$id] 输出未捕获，但目录文件数由 $baseCount 增至 $fileCount，视为成功"
                                $okIds += $id
                            }
                        }
                    }
                }

                # 成功的 ID 立即移出待重试集合，并复制到 Mods 目录
                $newlyOk = @($pending | Where-Object { $okIds -contains $_ })
                if ($newlyOk.Count -gt 0) {
                    if ($attempt -gt 1) { Write-Log "    √ 第 $attempt 次尝试成功：$($newlyOk -join ', ')" }
                    foreach ($id in $newlyOk) {
                        $okCount++
                        Write-Log "    √ [$id] 下载成功"

                        $src = Join-Path $cfg.InstallDir "steamapps\workshop\content\$appId\$id"
                        if (Test-Path $src) {
                            if ($gameCfg.CopyToMods -and $gameCfg.ModsDir) {
                                $dst = Join-Path $gameCfg.ModsDir $id
                                if (-not (Test-Path $dst)) {
                                    New-Item -ItemType Directory -Path $dst -Force | Out-Null
                                }
                                Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force
                                Write-Log "    √ [$id] 已复制到 $($gameCfg.ModsDir)"
                            } else {
                                Write-Log "    √ [$id] 已下载到 $src（未复制）"
                            }
                        } else {
                            Write-Log "    ⚠ [$id] 下载标记成功但目录不存在，检查 $src"
                        }
                    }
                    $pending = @($pending | Where-Object { $okIds -notcontains $_ })
                }

                if ($pending.Count -eq 0) { break }

                if ($attempt -lt $maxRetry) {
                    Write-Log "    第 $attempt 次尝试后仍有 $($pending.Count) 个失败：$($pending -join ', ')，3 秒后重试..."
                    Start-Sleep -Seconds 3
                }
            }
            # ---------- 重试循环结束 ----------

            if ($pending.Count -gt 0) {
                foreach ($id in $pending) {
                    $failCount++
                    Write-Log "    × [$id] 下载失败（已重试 $maxRetry 次）"
                }

                $tailLines = ($output -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 5) -join " | "
                if ($tailLines) { Write-Log "    最后输出：$tailLines" }

                if ($batchNo -eq 1) {
                    Write-Log "  可能原因："
                    Write-Log "  1. 该游戏不支持匿名下载（需要拥有游戏）"
                    Write-Log "  2. Mod ID 无效或已被删除"
                    Write-Log "  3. 网络问题，或 SteamCMD 凭据失效"
                    Write-Log "  如需账号登录，请先在命令行执行："
                    Write-Log "    $($cfg.SteamCmd) +login $($cfg.SteamUser)"
                }

                if ($failFast) {
                    Write-Log "  → 已设置为「失败即停」，终止后续任务"
                    Write-Log "===== 已终止：成功 $okCount，失败 $failCount ====="
                    $sync.Running = $false
                    return
                } else {
                    Write-Log "  → 跳过失败的 Mod，继续下一批"
                }
            }
        }

        Write-Log "===== 全部完成：成功 $okCount，失败 $failCount ====="
        $sync.Running = $false
    })
    [void]$ps.AddArgument($Ids)
    [void]$ps.AddArgument($BatchSize)

    $script:Runspace = $rs
    $script:PSHandle = $ps.BeginInvoke()
}

# ---------------- 定时刷新日志 ----------------
$timer          = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    $items = $sync.Log.ToArray()
    if ($items.Count -gt 0) {
        # 按已取出数量删除，避免 ToArray 与 Clear 之间新写入的日志被误删
        $sync.Log.RemoveRange(0, $items.Count)
        foreach ($line in $items) { $txtLog.AppendText("$line`r`n") }
        # 日志无限增长会拖慢 UI，超过上限时截断头部
        $maxLogChars = 200000
        if ($txtLog.TextLength -gt $maxLogChars) {
            $txtLog.Text = $txtLog.Text.Substring($txtLog.TextLength - $maxLogChars)
        }
        $txtLog.SelectionStart = $txtLog.Text.Length
        $txtLog.ScrollToCaret()
    }
    if ($sync.Running) {
        $btnGo.Enabled = $false
        $btnGo.Text    = "下载中..."
    } else {
        $btnGo.Enabled = $true
        $btnGo.Text    = "开始下载"
    }
})
$timer.Start()

# ---------------- 按钮事件 ----------------
$btnGo.Add_Click({
    if ($sync.Running) { return }
    if (-not $cmbGame.SelectedItem) {
        [System.Windows.Forms.MessageBox]::Show("请先选择游戏")
        return
    }

    $appId   = $cmbGame.SelectedItem.AppId
    $gameCfg = $Cfg.Games[$appId]

    if ($appId -notmatch '^\d+$') {
        [System.Windows.Forms.MessageBox]::Show("AppID 非法（应为纯数字）：$appId")
        return
    }

    if ($gameCfg.CopyToMods -and -not $gameCfg.ModsDir) {
        [System.Windows.Forms.MessageBox]::Show("该游戏尚未配置 Mods 目录，请点击「管理游戏」或「配置当前游戏」")
        return
    }

    $ids = [regex]::Matches($txtInput.Text, '\d{6,}') |
           ForEach-Object { $_.Value } | Select-Object -Unique

    if (-not $ids -or $ids.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("没有识别到有效的 Mod ID")
        return
    }

    $sync.AppId    = $appId
    $sync.FailFast = $rbStop.Checked
    $sync.Running  = $true
    $modeText = if ($rbStop.Checked) { "失败即停" } else { "跳过失败继续" }
    [void]$sync.Log.Add("[系统] 游戏：$($gameCfg.Name) | 识别到 $($ids.Count) 个 Mod ID | 模式：$modeText")
    Start-Download -Ids $ids
})

$btnImport.Add_Click({
    $fd = New-Object System.Windows.Forms.OpenFileDialog
    $fd.Filter = "文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*"
    $fd.Title = "选择包含 Mod ID 列表的文件"
    if ($fd.ShowDialog() -ne "OK") { return }

    try {
        $content = [System.IO.File]::ReadAllText($fd.FileName, [System.Text.Encoding]::UTF8)

        if ([string]::IsNullOrWhiteSpace($content)) {
            [System.Windows.Forms.MessageBox]::Show("文件是空的，请选择包含 Mod ID 的文件")
            return
        }

        $m = [regex]::Matches($content, 'workshop_download_item\s+\d+\s+(\d{6,})')
        if ($m.Count -gt 0) {
            $ids = $m | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
            [void]$sync.Log.Add("[系统] 识别为 SteamCMD 脚本格式")
        } else {
            $ids = [regex]::Matches($content, '\d{6,}') | ForEach-Object { $_.Value } | Select-Object -Unique
            [void]$sync.Log.Add("[系统] 识别为纯 ID 列表格式")
        }

        if (-not $ids -or $ids.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("文件中没有找到有效的 Mod ID")
            return
        }

        $existing = $txtInput.Text.Trim()
        if ($existing) {
            $txtInput.Text = $existing + "`r`n" + ($ids -join "`r`n")
        } else {
            $txtInput.Text = $ids -join "`r`n"
        }

        $fileName = [System.IO.Path]::GetFileName($fd.FileName)
        [void]$sync.Log.Add("[系统] 从 $fileName 导入了 $($ids.Count) 个 Mod ID")
    } catch {
        [System.Windows.Forms.MessageBox]::Show("读取文件失败：$_")
    }
})

$btnClear.Add_Click({ $txtLog.Clear() })

$btnOpen.Add_Click({
    if (-not $cmbGame.SelectedItem) { return }
    $appId   = $cmbGame.SelectedItem.AppId
    $gameCfg = $Cfg.Games[$appId]
    if ($gameCfg.ModsDir -and (Test-Path $gameCfg.ModsDir)) {
        Start-Process explorer.exe $gameCfg.ModsDir
    } elseif ($Cfg.InstallDir -and (Test-Path $Cfg.InstallDir)) {
        Start-Process explorer.exe $Cfg.InstallDir
    } else {
        [System.Windows.Forms.MessageBox]::Show("目录尚未配置")
    }
})

$btnManage.Add_Click({
    Show-ManageGamesDialog -Cfg $Cfg
    Refresh-GameCombo
    $sync.Cfg = $Cfg
})

$btnGlobalSettings.Add_Click({
    $newCfg = Show-GlobalSettingsDialog -CurrentCfg $Cfg
    if ($newCfg) {
        $Cfg.SteamCmd   = $newCfg.SteamCmd
        $Cfg.SteamUser  = $newCfg.SteamUser
        $Cfg.InstallDir = $newCfg.InstallDir
        Save-Config $Cfg
        $sync.Cfg = $Cfg
        [void]$sync.Log.Add("[系统] 全局配置已保存")
    }
})

$btnConfigCurrent.Add_Click({
    if (-not $cmbGame.SelectedItem) { return }
    $appId = $cmbGame.SelectedItem.AppId
    $g = $Cfg.Games[$appId]

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "配置：$($g.Name)"
    $dlg.Size = [System.Drawing.Size]::new(560, 200)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.Font = [System.Drawing.Font]::new("Microsoft YaHei UI", 9)

    $lbl1 = New-Object System.Windows.Forms.Label
    $lbl1.Text = "Mods 目录："
    $lbl1.Location = [System.Drawing.Point]::new(20, 30)
    $lbl1.Size = [System.Drawing.Size]::new(80, 24)
    $dlg.Controls.Add($lbl1)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = [System.Drawing.Point]::new(105, 27)
    $txt.Size = [System.Drawing.Size]::new(340, 24)
    $txt.Text = "$($g.ModsDir)"
    $dlg.Controls.Add($txt)

    $btnB = New-Object System.Windows.Forms.Button
    $btnB.Text = "..."
    $btnB.Location = [System.Drawing.Point]::new(450, 26)
    $btnB.Size = [System.Drawing.Size]::new(35, 26)
    $btnB.Add_Click({
        $fd = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($fd.ShowDialog() -eq "OK") { $txt.Text = $fd.SelectedPath }
    })
    $dlg.Controls.Add($btnB)

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = "下载后自动复制到 Mods 目录"
    $chk.Location = [System.Drawing.Point]::new(105, 70)
    $chk.Size = [System.Drawing.Size]::new(300, 24)
    $chk.Checked = [bool]$g.CopyToMods
    $dlg.Controls.Add($chk)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "保存"
    $btnOk.Location = [System.Drawing.Point]::new(310, 115)
    $btnOk.Size = [System.Drawing.Size]::new(80, 30)
    $btnOk.DialogResult = "OK"
    $dlg.Controls.Add($btnOk)

    $btnC = New-Object System.Windows.Forms.Button
    $btnC.Text = "取消"
    $btnC.Location = [System.Drawing.Point]::new(400, 115)
    $btnC.Size = [System.Drawing.Size]::new(80, 30)
    $btnC.DialogResult = "Cancel"
    $dlg.Controls.Add($btnC)

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnC

    if ($dlg.ShowDialog() -eq "OK") {
        $Cfg.Games[$appId].ModsDir    = $txt.Text.Trim()
        $Cfg.Games[$appId].CopyToMods = $chk.Checked
        Save-Config $Cfg
        $sync.Cfg = $Cfg
        Refresh-GameCombo
        [void]$sync.Log.Add("[系统] 已保存 $($g.Name) 的配置")
    }
})

# ---------------- 启动前检查全局配置 ----------------
if (-not (Test-GlobalConfigComplete $Cfg)) {
    [void]$sync.Log.Add("[系统] 首次运行，请先完成全局设置")
    $newCfg = Show-GlobalSettingsDialog -CurrentCfg $Cfg
    if ($newCfg) {
        $Cfg.SteamCmd   = $newCfg.SteamCmd
        $Cfg.SteamUser  = $newCfg.SteamUser
        $Cfg.InstallDir = $newCfg.InstallDir
        Save-Config $Cfg
        $sync.Cfg = $Cfg
    } else {
        [System.Windows.Forms.MessageBox]::Show("未完成设置，程序将退出。")
        $timer.Stop()
        return
    }
}

# ---------------- 显示主窗口 ----------------
[void]$form.ShowDialog()

# ---------------- 清理 ----------------
$timer.Stop()
$timer.Dispose()
if ($script:PSHandle) {
    try { $script:PSHandle.AsyncWaitHandle.Close() } catch { }
    try { $script:PSHandle.Dispose() } catch { }
}
if ($script:Runspace) {
    try { $script:Runspace.Close() } catch { }
    try { $script:Runspace.Dispose() } catch { }
}
