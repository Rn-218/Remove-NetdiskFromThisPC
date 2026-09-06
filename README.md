# Remove-NetdiskFromThisPC

[![License: CC BY 4.0](https://img.shields.io/badge/License-CC%20BY%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by/4.0/)

一个 PowerShell 脚本，用于清除“此电脑”(This PC) 中百度网盘、夸克网盘、123网盘、阿里云盘等网盘客户端留下的入口/虚拟盘图标（**不卸载软件**）。

## 背景

网盘客户端通过把自身注册到资源管理器的“命名空间”(NameSpace) 中，让自身以虚拟盘符/文件夹的形式出现在“此电脑”主页（设备与驱动器区域）、左侧导航树或桌面上。部分客户端（如百度网盘）还会同时注册到 **当前用户 (HKCU)** 与 **本机所有用户 (HKLM)** 两处，只删 HKCU 时“此电脑”里仍会残留入口。

本脚本自动扫描并删除三个范围中、显示名匹配关键词的入口：

- `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace`
- `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace`
- `HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer\...`（含 `HKLM\Wow6432Node` 32 位视图）

## 特性

- ✅ 内置覆盖：百度网盘、夸克网盘、123网盘/云盘、阿里云盘、天翼云盘、迅雷网盘/云盘、腾讯微云、115网盘、UC网盘、蓝奏云、和彩云、移动云盘等，以及 `BaiduNetdisk`/`Quark`/`Xunlei` 等英文名
- ✅ 兜底泛关键词“网盘 / 云盘”：其它未知品牌同样可被识别
- ✅ 同时读取 CLSID 的 `LocalizedString` 字段，防止个别网盘只在该字段写显示名
- ✅ 自动覆盖 HKCU + HKLM + 32 位视图；非管理员运行时发现 HKLM 入口会自动弹 UAC 提权完成清理
- ✅ 支持 `-WhatIf` 预览、`-Keywords` 自定义关键词、`-RemoveClsid` 深层清理、`-RestartExplorer` 刷新界面
- ✅ UTF-8 with BOM，兼容 Windows PowerShell 5.1 / PowerShell 7

## 使用方法

```powershell
# 一键清理（发现本机 HKLM 入口时自动请求管理员权限）
.\Remove-NetdiskFromThisPC.ps1

# 先预览会删除哪些入口（安全，不实际删除）
.\Remove-NetdiskFromThisPC.ps1 -WhatIf

# 只清理指定网盘 + 追加未识别的网盘名
.\Remove-NetdiskFromThisPC.ps1 -Keywords 百度网盘,夸克网盘,我的私有盘

# 深层清理（连同 Classes\CLSID 注册一起删除）并刷新资源管理器
.\Remove-NetdiskFromThisPC.ps1 -RemoveClsid -RestartExplorer
```

如果提示执行策略限制，先执行：

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## 参数

| 参数 | 作用 | 默认 |
| --- | --- | --- |
| `-Keywords` | 匹配关键词列表（逗号分隔），显示名包含任一关键词即命中 | 内置常用网盘名单 + “网盘”“云盘” |
| `-RemoveClsid` | 连同 `Classes\CLSID` 下的注册项一并删除（更深层清理） | 关闭 |
| `-RestartExplorer` | 清理完成后重启资源管理器刷新界面（会关闭已打开的文件夹窗口） | 关闭 |
| `-Force` | 跳过删除前的 y/n 确认 | 关闭 |
| `-WhatIf` | 仅预览将删除的入口，不执行删除 | 关闭 |

## 注意事项

- 本脚本只删除“此电脑”中的入口，不会卸载网盘客户端，不影响网盘软件本身。
- 部分网盘客户端重新启动后会再次注册入口（属客户端自身行为），发现入口复现时重新运行本脚本即可。
- 手动“固定到快速访问/主页”的网盘文件夹属于用户固定项，不在本脚本处理范围，请右键手动取消固定。

## 环境要求

- Windows 10 / 11
- Windows PowerShell 5.1 或 PowerShell 7+

## 许可

本项目采用 [知识共享署名 4.0 国际（CC BY 4.0）](https://creativecommons.org/licenses/by/4.0/deed.zh-hans) 许可协议开源。

- 您可以自由共享（复制、分发）、演绎（修改、再创作）本作品，甚至用于**商业目的**，但必须**署名原作者**。
- 完整法律文本见 [LICENSE](./LICENSE)；[许可摘要（人类可读）](https://creativecommons.org/licenses/by/4.0/)。
