# 待办：测试偏好域残留清理（下次 Wavelet 升级时一起做）

> 状态：**未实施**。2026-10-28 已把历史残留清空，代码侧未做任何修改，特意留给下一次版本升级一并处理。
> 触发时机：下一次改 `CURRENT_PROJECT_VERSION` / 发布前的测试流程改造时。
> 全部结论均来自 2026-10-28 在 macOS 27.0.1 上的实测，不是推测；下面的「实测否掉」一节请先读，避免重复踩坑。

## 一、现象与根因

跑一次 `xcodebuild test` 会在 `~/Library/Preferences` 里留下约 42 个 42 字节的空 plist：

```
WaveletMacTests.<UUID>.plist        ← CatalogTests.swift:15-18 的 suite
WaveletMediaTests.<UUID>.plist      ← MediaTests.swift:7-10 的 suite
```

- 测试用 `UserDefaults(suiteName: "WaveletMacTests.<UUID>")` 做隔离，每个测试方法一个域（CatalogTests 22 + MediaTests 20）。
- 测试的 `defer` 里确实调了 `removePersistentDomain`，但它**只把域写成空 `{}`，不删除文件**。
- 2026-10-28 清理时统计：677 个文件（538 WaveletMacTests + 127 WaveletMediaTests + 5 `wavelet-test-` + 5 WaveletSnapshot + 2 WaveletLayout），内容全是 `{}`，合计 27.8 KB（占盘 2.64 MB，每文件一个 4K 块）。时间分布 Oct 1/6/10/20/21/22 对应各轮跑测试。
- 旁证：iOS 的 `iOS/scripts/PersonalStoreChecks.swift:13-15` 用 `wavelet-test-<UUID>`，同样模式，5 个残留来自 10 月 6 日那一轮。
- `WaveletLayout.*` / `WaveletSnapshot.*` 在源码和 git 历史里都搜不到，属更早测试代码的遗留，不会再新增。

危害：只是偏好目录和 `defaults domains` 里的噪声，不占实际空间，不影响功能。所以优先级低、可以延后。

## 二、实测否掉的三条路（别再试）

| 做法 | 实测结果 | 判定 |
|---|---|---|
| `defaults delete <domain>` | 退出码 0，但 plist **文件仍在**；对已空的域报 `Error: Domain '...' not found` | ✗ 无效 |
| 测试 `defer` 里删文件（`removePersistentDomain` + `synchronize()` + `FileManager.removeItem`） | 进程退出 t=0s/3s 不存在 → **t=10s 又冒回来**（cfprefsd 延迟落盘），t=60s 仍在 | ✗ 无效 |
| 进程退出**之后**再删文件 | 移入废纸篓后 30s、60s 都不再出现 | ✓ **可靠** |
| `killall cfprefsd` 强制刷新 | 未验证，且会丢弃其他 App 未落盘的偏好，**不建议引入** | — |

结论：cfprefsd 的落盘有约 10 秒延迟，任何「在测试进程内顺手删掉」的写法都会被回写。**唯一可靠时机是测试进程退出之后。**

## 三、方案 A（推荐：清扫脚本，不改生产代码）

### 改动清单

| # | 文件 | 位置 | 改什么 |
|---|---|---|---|
| 1 | `Mac/scripts/purge-test-prefs.sh` | 新增 | 清扫脚本（全文见下） |
| 2 | `Mac/WaveletMacTests/CatalogTests.swift` | `15-18` `makeDefaults()` | 前缀 `WaveletMacTests.` → `waveletTest-`（P2，可选） |
| 3 | `Mac/WaveletMacTests/MediaTests.swift` | `7-10` `makeDefaults()` | 前缀 `WaveletMediaTests.` → `waveletTest-`（P2，可选） |
| 4 | 测试流程 | 见下 | `xcodebuild test-without-building` 之后串上脚本（P1：是否包成 `scripts/test.sh`） |
| 5 | skill `wavelet-mac-app` | 「构建与预览」+ Pitfalls | 把清扫写进流程，并记「进程内删除会被回写」的坑 |
| 6 | `Mac/project.yml` | — | **不用改**。`WaveletMacTests` target 是目录引用（`sources: - path: WaveletMacTests`），新增文件重跑 `xcodegen generate` 自动纳入 |

**不需要改**的 15 处 `removePersistentDomain`（CatalogTests 47/77/191/228/265/302/346/473/494/518；MediaTests 279/320/342/429/478）——它们仍负责清空域内容，只是不足以删除文件。
**不需要改** `iOS/scripts/PersonalStoreChecks.swift`——`wavelet-test-` 前缀已被脚本覆盖。

### 脚本全文（`Mac/scripts/purge-test-prefs.sh`）

```bash
#!/bin/bash
# 清掉跑测试/检查脚本后留在 ~/Library/Preferences 的空偏好域。
# 必须：① 在测试进程退出之后运行；② 多轮重试——cfprefsd 落盘有约 10s 延迟，
# 第一轮漏掉的文件会在几秒后才出现（实测 t=10s 才出现）。
set -uo pipefail

PREFS="$HOME/Library/Preferences"
PATTERN='^WaveletMacTests\.|^WaveletMediaTests\.|^WaveletLayout\.|^WaveletSnapshot\.|^waveletTest-|^wavelet-test-'
DEST="$HOME/.Trash/wavelet-test-prefs-$(date +%Y%m%d-%H%M%S)"

sweep_once() {
  local n=0 f
  for f in $(ls -1 "$PREFS" | grep -E "$PATTERN"); do
    mkdir -p "$DEST"
    n=$((n+1))
    mv "$PREFS/$f" "$DEST/$(printf '%03d-%s' "$n" "$f")"
  done
  echo "$n"
}

total=0
for round in 1 2 3 4; do
  moved=$(sweep_once)
  total=$((total+moved))
  left=$(ls -1 "$PREFS" | grep -cE "$PATTERN")
  echo "第 ${round} 轮：移出 ${moved} 个，剩余 ${left}"
  [ "$left" -eq 0 ] && [ "$moved" -eq 0 ] && break
  sleep 5
done

left=$(ls -1 "$PREFS" | grep -cE "$PATTERN")
echo "合计移出 ${total} 个 → ${DEST:-（无残留）}；最终剩余 ${left}"
[ "$left" -eq 0 ]
```

设计要点：只按前缀命中，绝不碰 `com.mythmedia.waveletmac*`；每个源加序号前缀避免同名嵌套；全部 `mv` 进废纸篓（用户硬性要求，禁 `rm`）；末行给退出码，可直接进 `make test` 链。

### 流程与验收

```bash
cd ~/workspace/radio/Mac
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodebuild test-without-building -project WaveletMac.xcodeproj -scheme WaveletMac \
  -configuration Debug -derivedDataPath dist/DerivedDataDebug -destination 'platform=macOS'
bash scripts/purge-test-prefs.sh          # 自动等 ~10s 回写窗口

ls -1 ~/Library/Preferences | grep -cE '(WaveletMacTests|WaveletMediaTests)\.'   # 预期 0
defaults domains | tr ',' '\n' | sed 's/^ *//' | grep -cE '^wavelet'              # 预期 0
stat -f "%Sm %N" -t "%F %T" ~/Library/Preferences/com.mythmedia.waveletmac.plist  # app 偏好 mtime 不变
```

- 测试基线：49 项（CatalogTests 22 / MediaTests 20 / PlaybackProgressTests 7），跑完必须仍全绿。
- 回滚：`mv ~/.Trash/wavelet-test-prefs-<时间戳>/*.plist ~/Library/Preferences/`（去掉 `NNN-` 序号前缀）。
- 代价：每轮约 42 个空文件堆进 `~/.Trash/wavelet-test-prefs-<时间戳>/`，需手动清空废纸篓——这是「可恢复优先」换来的。

## 四、方案 B（真·根治：测试不产生偏好域）

把 `private let defaults: UserDefaults` 抽成 `PreferencesStore` 协议 + 内存实现，测试注入内存实现，一个 plist 都不产生。

改造量（2026-10-28 统计）：

| 文件 | 位置 | `defaults.` 调用点 |
|---|---|---|
| `WaveletMac/RadioCatalogStore.swift` | `:30` | 26 |
| `WaveletMac/PlaybackEngine.swift` | `:51`、`:80` | 4 |
| `WaveletMac/StreamSongRecognition.swift` | `:48`、`:61` | 2 |
| `WaveletMac/Media/LocalMediaStore.swift` | `:22` | 3 |
| `WaveletMacTests/{Catalog,Media}Tests.swift` | — | 33 |

协议需覆盖：`object / string / stringArray / data / bool / integer / dictionaryRepresentation / set / removeObject`。
注意：`Shared/` 下的文件在 `project.yml:22-24` 是逐个显式列出的，新协议放 `Shared/` 要手动加一行；放 `WaveletMac/` 才会被目录 glob 自动收进来。

**建议：与下一次存储层改造（如 schema 迁移）合并做，不要为清残留单独重构。** 存储层是发布前核心路径，35 处调用点需要全量测试 + 实机验收（收藏、上次电台、音量、语言、媒体库进度）。

## 五、已完成的动作（供对照，勿重复）

2026-10-28：用户手动清除了 677 个历史残留（`~/Library/Preferences` 下 `^wavelet` 前缀文件归零，`com.mythmedia.waveletmac.plist` 与 `com.mythmedia.wavelet.shazamkitprobe.plist` 保留）。同日做的排查性探针文件（`waveletTest-probe-*`、`zzz-hermes-probe-*` 及 `Mac/dist/prefs-probe/`）均已移入废纸篓，`dist/` 在 `.gitignore` 内。

## 六、待定决策

- **P1｜清扫时机**：脚本挂在测试命令后手工执行，还是新建 `scripts/test.sh` 把 `build → test → purge` 包成一条命令。
- **P2｜是否统一偏好域前缀**为 `waveletTest-<UUID>`：好处是未来只需一条正则、不会与 App 域混淆；代价是丢失「哪个测试类留下的」信息。改 2 行。
