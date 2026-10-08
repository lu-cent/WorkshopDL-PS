# WorkshopDL-PS

![截图](https://github.com/user-attachments/assets/ac230132-2cee-4e26-a599-71d9305f103b)

带图形界面的 Steam 创意工坊 Mod 批量下载器，基于 SteamCMD，零依赖。

## 下载

前往 [Releases](https://github.com/lu-cent/WorkshopDL-PS/releases) 页面下载最新版 `WorkshopDL-PS.exe`，双击即可运行（无需安装 PowerShell 模块）。

## 特性

- 纯 PowerShell + WinForms，Windows 系统自带，无需安装任何运行环境
- 图形界面，粘贴 Mod ID 即可批量下载
- 自动识别创意工坊链接、逗号、空格、换行等多种格式
- 支持从 SteamCMD 脚本文件批量导入 Mod ID
- 自动去重
- 支持多游戏切换，配置独立保存
- 下载后自动复制到游戏 Mods 目录
- 失败即停 / 跳过失败继续，两种模式可选
- 后台线程运行，界面不卡顿
- 配置保存在 `%APPDATA%\WorkshopDL-PS\config.json`

## 使用前提

1. Windows 系统，PowerShell 5.1 或更高
2. 已安装 [SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD)
3. SteamCMD 已缓存登录凭据（见下方）

## 首次准备

SteamCMD 需要先缓存登录凭据，打开命令行运行一次：

    D:\steamcmd\steamcmd.exe +login 你的Steam用户名

输入密码和 Steam Guard 验证码后，输入 `quit` 退出。之后脚本才能自动登录。

## 使用方式

### 方式一：直接运行脚本

    powershell.exe -ExecutionPolicy Bypass -File "WorkshopDL-PS.ps1"

首次运行会弹出全局设置窗口，填入：

- SteamCMD 路径（如 `D:\steamcmd\steamcmd.exe`）
- Steam 用户名（留空则匿名登录）
- SteamCMD 目录（如 `D:\steamcmd`，即 steamcmd.exe 所在目录）

之后进入主界面，点「配置当前游戏」为每个游戏单独设置 Mods 目录。

### 方式二：打包成 exe

    Install-Module ps2exe -Scope CurrentUser -Force
    Import-Module ps2exe
    Invoke-ps2exe -InputFile "WorkshopDL-PS.ps1" -OutputFile "WorkshopDL-PS.exe" -noConsole

## 从订阅列表批量导出

如果你在创意工坊订阅了几百个 Mod，手动找 ID 太麻烦，推荐这个流程：

1. 用 [steam-workshop-linker](https://github.com/DLW114/steam-workshop-linker) 导出你的订阅列表（浏览器脚本，一键生成 `.txt`）
2. 打开本工具，点「从文件导入」，选择那个 `.txt`
3. 点「开始下载」

工具会自动识别文件格式：
- `workshop_download_item <appid> <modid>` 格式（SteamCMD 脚本）
- 纯数字 ID 列表

## 支持的平台

内置以下游戏的预设配置：

- 环世界 (RimWorld)
- 求生之路2 (L4D2)
- Garry's Mod
- 城市天际线
- 僵尸毁灭工程
- 饥荒联机版 (DST)
- 武装突袭3 (Arma 3)
- 方舟：生存进化
- 欧洲卡车模拟2
- 美国卡车模拟
- 异星工厂
- 群星 (Stellaris)
- 十字军之王3
- 钢铁雄心4
- 太空工程师

其他游戏可通过「管理游戏」手动添加 AppID。

## 常见问题

**Q: 提示「下载失败」？**

- 检查 SteamCMD 路径、账号是否配置正确
- 确认游戏是否允许匿名下载创意工坊内容
- 部分游戏（如 CS2、Dota2）必须拥有游戏才能下载
- 确认网络通畅，或 SteamCMD 凭据未过期

**Q: 界面卡住不动？**

下载是后台线程，界面不会卡；如果长时间无响应，检查是否在等待密码输入。

**Q: 如何更新已下载的 Mod？**

直接重新粘贴 Mod ID 再点开始下载即可覆盖。

**Q: 提示「文件是空的」？**

导入的文件没有内容，检查是不是选错了文件。

## 相关项目

- [steam-workshop-linker](https://github.com/DLW114/steam-workshop-linker) —— 浏览器脚本，一键提取你在 Steam 创意工坊订阅的所有 Mod ID，输出标准 SteamCMD 脚本文件，可直接被本工具的「从文件导入」识别。

## 免责声明

本工具仅供已合法拥有对应游戏的用户，用于批量下载创意工坊内容。

使用本工具下载的内容版权归原作者所有。请勿用于任何侵犯版权的用途。

## 许可证

MIT License