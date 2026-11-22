# OhMusic

OpenHarmony 音乐应用：网易云音乐网页播放器 + 本地媒体库播放器。

## 功能

- 在线：加载 `https://music.163.com/st/webplayer`，移动 UA，Cookie/DOM 存储，
  拦截 `orpheus://`、`netease-music://` 等 App scheme，底部后退/前进/刷新/首页/搜索。
- 本地：扫描媒体库音频，列表、当前曲高亮、播放/暂停/停止、进度条与拖动 seek。
- 在线/本地顶部切换，WebView 隐藏时保持页面状态。

## 构建

需要 OpenHarmony SDK API 11 和 hvigor 3.2.4：

```powershell
$env:OHOS_BASE_SDK_HOME="$env:OHOS_TOOLS/sdk"
$env:NODE_PATH="$env:OHOS_TOOLS/hvigor-3.2.4/node_modules"
& "$env:DEVECO_HOME/tools/node/node.exe" `
  "$env:OHOS_TOOLS/hvigor-3.2.4/node_modules/@ohos/hvigor/bin/hvigor-simple.js" `
  --mode module -p product=default -p buildMode=debug assembleHap
```

工具链变量（`OHOS_TOOLS` / `DEVECO_HOME` 等）的约定见 `ohos-device/docs/ENVIRONMENT.md` §零。

HAP 输出：`web/build/default/outputs/default/web-default-unsigned.hap`。

## 签名与系统权限

本地播放使用 `mediaLibrary` + `AVPlayer fdSrc`。manifest 申请
`ohos.permission.READ_MEDIA`，签名 profile 需为 `apl=system_basic`、
`app-feature=hos_system_app`，并在 `acls.allowed-acls` 中允许该权限。
安装到开发板后用 root shell 授权：

```sh
atm perm -g -i <tokenID> -p ohos.permission.READ_MEDIA
```

签名材料（`signing/`、`*.p12`、`*.p7b`）不入库。

## 已知限制

- AudioViewPicker 返回的 docs URI 在 OH 4.1 app 沙箱中 `fs.openSync` 报
  `13900001`，任意文件导入不可用；优先使用媒体库扫描。
- 网易云在线播放依赖网页端可用性，部分歌曲可能受版权/网页端限制。
