# IOS- / 相册整理 PhotoCleaner

面向 iPhone 的本地相册整理工具，最低 iOS 18.0，目标验收设备为 iPhone 15 Pro / iOS 18.5。旧版已安装运行；0.2.0 的验证记录见 [验证说明](docs/VERIFICATION.md)，新版真机验收待执行。

## 已实现的范围

- 0.3.0：四向滑动整理、自定义手势、撤销、待删除/待收藏复核；三列网格与横向双行浏览。
- 全部照片、视频、截图、实况、收藏、相簿、月份和照片坐标地点分组；直接整理不依赖全库分析。
- 本机图片 JPEG / 视频 MP4 压缩预览及另存副本，原件默认保留；实际输出不变小则拒绝保存，删除原件前复核版本与副本。
- 普通静态照片按原始资源 SHA-256 检查精确重复；复杂资源、实况照片和视频不纳入精确重复组。
- 结合拍摄时间、感知哈希及 Vision 图像特征生成保守的相似候选，人工对比后选择。
- 本地 OCR、画面分类、截图规则和模糊/极暗提示；按文字、标签和拍摄日期搜索。
- 原始资源字节大小数值排序，未知大小始终排在最后。
- 本地分片缓存、扫描检查点与自动续扫；收藏和指定相簿保护；勾选后直接发起删除，并保留系统删除确认。
- 原生 SwiftUI 清理首页、分类照片预览与常驻待删操作栏；快速分析与读取原件分开执行。

## Windows 上开始

按 [Windows 安装说明](docs/INSTALL-WINDOWS.md) 在 GitHub macOS runner 编译，再在自己的 Windows 电脑用 Sideloadly 签名安装。GitHub 不需要 Apple 账号、密码或签名证书；未签名 IPA 不能直接安装到 iPhone。

免费 Apple 账号需要周期续签。源码位于 `codex/initial-app` 分支；[0.2.0 已验证构建与安装包](https://github.com/wlhbstt/IOS-/actions/runs/43366426837)见该任务的 Artifacts。构建成功和真机行为须分别验收，见 [真机检查表](docs/DEVICE-CHECKLIST.md)。

## 验证与构建

Windows 安装 Node.js 22 后可运行静态输入检查：

```powershell
node scripts/validate-project.mjs
```

WSL Ubuntu 24.04 可使用项目提供的 Swift 6.0.3 测试工具链脚本；首次需要联网下载，且具备 `curl`、`tar`、`apt-get`、`dpkg-deb`：

```powershell
wsl bash -lc 'cd /mnt/e/git-sanyi/iphone-photo-cleaner && bash scripts/install-swift-test-toolchain.sh test'
```

macOS 安装 Xcode（iPhoneOS SDK 18.0 或更新）与 XcodeGen 后：

```bash
brew install xcodegen
node scripts/validate-project.mjs
bash scripts/build-ios.sh
```

脚本先运行 `swift test`，生成 Xcode 工程，再运行模拟器索引与界面测试，最后编译 Release 真机 App、检查 arm64 可执行文件并打包 `build/PhotoCleaner-unsigned.ipa`。模拟器使用公开样片，不读取用户照片，截图单独保存为 artifact。GitHub Actions 支持手动触发、push 和 PR；仅全部成功后上传未签名 IPA。Node 检查与 Linux 核心测试不等于 Apple SDK 编译验证。

## 使用边界

- 0.3.0 交互参考 [PhotoDelete](https://github.com/01MVP/PhotoDelete)，源码及素材未复制。构建和验收进度见 [本版计划](docs/2026-11-13-photodelete-plan.md)。
- 滑动动作在当前会话内可撤销；离开后重开从集合起点开始。待删除/待收藏暂存于内存，强制结束 App 不保存清单。已确认写入系统相册的删除/收藏不可通过滑动撤销。
- 地点使用照片已有经纬度按 0.1° 网格聚合并显示坐标，不请求当前位置，不联网转换城市名。没有位置数据的照片单列。
- 压缩为有损转换，可能丢失 HDR、透明度或特殊视频效果，需明确接受后执行；实况、RAW、动画、连拍和复杂多资源内容暂不支持。另存副本会先增加空间，原件删除及系统最近删除清理后才可能减少占用。
- 首次仅能扫描系统授权可见的项目；完整相册需完整照片权限。iCloud 独有资源需要开启 App 内网络读取，可能产生下载、流量和耗时；关闭时无法读取的内容保留未知或待处理状态。
- 大小为原始媒体资源字节之和，不等于本机占用或立即可释放空间。删除会影响 iCloud 同步图库，系统“最近删除”也会影响空间回收。
- 识别结果为启发式候选，会误判或漏判；尚无自然语言语义向量搜索，不能承诺任意描述检索。
- OCR、标签和特征缓存在本机，不上传照片到自建服务；系统 iCloud 下载由 PhotoKit 处理。先执行“快速分析照片”，需要大小排序和精确重复时再执行“读取原件大小与完全重复”。
- 离开前台时请求有限后台时间和系统调度，约每 3 秒或每 64 项保存检查点，回前台自动续扫；手动暂停会取消续扫。iOS 决定后台运行时机和时长，不能保证锁屏后持续扫描，强制退出后需重新打开 App。
- 后台识别使用 CPU，前台保留系统硬件加速；切换后台导致当前请求失败时保存进度等待续扫，不把该照片记为分析完成。
- 索引使用首次解锁后可读的系统文件保护级别，以便锁屏后台任务访问；重启后首次解锁前不可读。清除索引不删除系统照片。
- 相似组、敏感内容和模糊提示需逐张核对。首次测试使用已备份样本，勿直接批量删除重要原片。
