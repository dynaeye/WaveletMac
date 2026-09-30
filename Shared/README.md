# Shared 接入要点

- 将 `Models.swift` 加入 macOS App target。
- 将 `Resources` 下的 JSON 以及根目录 `docs/电台目录翻译.json` 加入 Copy Bundle Resources。
- Debug 会读取 `stations-candidates.json`，Release 会读取 `stations.json`。
- `Models.swift` 会以文件名 `电台目录翻译.json` 读取六语翻译，勿改名，除非同步修改加载代码。
- Mac 版不包含 iOS 的随机金句功能，不需要打包 `motivational-quotes.json`。
- 将 `Fonts` 中需要的字体加入 target 后，在 macOS 启动时注册；字体授权文件必须一同保留。
