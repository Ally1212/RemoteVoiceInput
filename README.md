# 远程语音输入（RemoteVoiceInput）

一个 macOS 文字中转小工具：用本机豆包输入法说话，再把文字粘贴到苹果屏幕共享中的远程 Mac。

**本机听写 → 本机输入窗 → 共享剪贴板 → 远端粘贴。**

它不传输麦克风、不自己识别语音，也不需要在远程电脑安装配套软件。
当前版本为 **0.1.6**。

## 使用

1. 打开苹果“屏幕共享”，连接远程 Mac，在“编辑”中勾选“使用共享的剪贴板”。
2. 启动本工具，按提示授予“辅助功能”和控制“System Events（系统事件）”的自动化权限。
3. 点击远程电脑里要输入的文本框，再点本机右上角的“语音输入”悬浮按钮。
4. 用平时的豆包语音快捷键说话，确认文字出现在本工具的小窗里。
5. 按 `⌘Enter` 并松开，或点“发送到远程”，等待约两秒后检查远端文字。

看不到悬浮按钮时，点“选远程位置（3秒）”，再在三秒内点击远程输入框。
也可用全局快捷键 `⌃⌥⌘D` 打开输入窗。

## 构建与安装

需要 macOS 和 Swift 6 工具链，项目最低部署目标为 macOS 13。

```sh
swift test
zsh scripts/build.sh
open dist/RemoteVoiceInput.app
```

构建产物为 `dist/RemoteVoiceInput.app`。需要安装到“应用程序”时，可使用项目的更新脚本：

```sh
osascript scripts/install-preserving-draft.applescript \
  "$PWD/dist/RemoteVoiceInput.app" \
  /Applications/RemoteVoiceInput.app
```

脚本会在更新期间把原草稿保留在内存中。构建优先使用本机已有的 Apple Development
签名身份，没有时使用 ad-hoc 签名；签名身份改变后可能需要重新授权。
产物未经过 Apple 公证。

## 注意

- 只粘贴文字，不自动按远程回车提交；请先在空白文本编辑器里测试。
- 发送会替换本机剪贴板；草稿只保留在内存，退出应用后消失。
- 本工具不录音、不保存听写历史、不记录正文日志；豆包的语音处理由其自身设置决定。
- 发送期间不要切换窗口、点击或打字，否则会取消发送。
- 没有远端送达确认接口，请以远端实际显示为准，不要盲目重复发送。
- 当前针对苹果屏幕共享，不是 UU、RDP 等远程软件的通用插件。

## 项目结构

```text
Sources/RemoteVoiceInput/   macOS 界面、目标窗口和粘贴发送
Sources/TransferPolicy/     输入检查与菜单名称匹配
Tests/                     自动化测试
Resources/                 应用配置
scripts/                   构建、更新和界面自检脚本
docs/                      详细原理及排障记录
```

关键修复是**先写本机剪贴板，再激活远程连接**，避免粘贴上一轮文字。
当前环境已完成快捷键、按钮和用户实际使用验证；不保证其他环境下同样成功。
详细过程见 [排障与验收记录](docs/TROUBLESHOOTING.md)。
