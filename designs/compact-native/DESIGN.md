# 远程语音输入 0.3.0

原生 AppKit 实现；不引入 WebView。工作表面优先输入、确认、返回远程，避免重复标题和长段首屏说明。

- 输入窗 460 × 330，左右留白 22，垂直间距 12；系统字体与语义颜色，跟随系统明暗外观。
- 圆角输入区 12，字号 17；标题 15，说明和状态 11。
- 帮助按钮承接首次设置，授权状态与发送按钮同行。菜单保留所有高级功能。
- 打开时淡入 140ms；系统启用减少动态效果时立即显示。发送行为与防重复保护保持原样。
- 输入窗显示时每秒复查系统授权；签名不匹配仍需用户重新授权，轮询无法绕过系统判断。

## 图标

使用内置 image_gen 生成，原始 PNG 位于 `Resources/AppIcon.png`，多尺寸 macOS 图标位于 `Resources/AppIcon.icns`。深蓝底、白色语音气泡、青色声波与发送箭头。

生成提示词：

> Use case: logo-brand. Create one polished macOS utility application icon for RemoteVoiceInput, a speech text bridge between Macs. Square 1024px canvas, transparent outside a centered rounded-square app tile occupying 88% width. Tile has deep midnight blue satin finish, subtly rounded beveled edges. A single crisp ivory speech bubble containing three short teal waveform bars; bubble tail extends into a restrained directional arrow to evoke sending text. Strong simple silhouette readable at 32px, mature understated Apple desktop utility, subtle studio lighting, no typography, no letters, no microphone, no extra surrounding objects, no mockup, no watermark. Actual final icon artwork.

`preview.png` 是原生内容视图的离屏渲染，不包含系统窗口阴影或标题栏；不代表远程发送验收。
