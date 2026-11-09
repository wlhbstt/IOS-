# IOS- / 相册整理 PhotoCleaner

面向 iPhone 的本地相册整理工具，最低 iOS 18.0，目标验收设备为 iPhone 15 Pro / iOS 18.5。已通过云端 Xcode 16.4 / iPhoneOS SDK 18.5 编译并生成未签名 IPA；尚未在该设备上安装验收。

## 已实现的范围

- 普通静态照片按原始资源 SHA-256 检查精确重复；复杂资源、实况照片和视频不纳入精确重复组。
- 结合拍摄时间、感知哈希及 Vision 图像特征生成保守的相似候选，人工对比后选择。
- 本地 OCR、画面分类、截图规则和模糊/极暗提示；按文字、标签和拍摄日期搜索。
- 原始资源字节大小数值排序，未知大小始终排在最后。
- 本地分片缓存、前台扫描暂停与继续；收藏和指定相簿保护；批量选择与删除前校验，并保留系统删除确认。

## Windows 上开始

按 [Windows 安装说明](docs/INSTALL-WINDOWS.md) 在 GitHub macOS runner 编译，再在自己的 Windows 电脑用 Sideloadly 签名安装。GitHub 不需要 Apple 账号、密码或签名证书；未签名 IPA 不能直接安装到 iPhone。

免费 Apple 账号需要周期续签。源码位于 `codex/initial-app` 分支；[已验证构建与安装包](https://github.com/wlhbstt/IOS-/actions/runs/42593273529)见该任务的 Artifacts。构建成功和真机行为须分别验收，见 [真机检查表](docs/DEVICE-CHECKLIST.md)。

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

脚本先运行 `swift test`，再生成 Xcode 工程、编译 Release 真机 App、检查 arm64 可执行文件并打包 `build/PhotoCleaner-unsigned.ipa`。GitHub Actions 支持手动触发、push 和 PR；仅全部成功后上传未签名 IPA。Node 检查与 Linux 核心测试不等于 Apple SDK 编译验证。

## 使用边界

- 首次仅能扫描系统授权可见的项目；完整相册需完整照片权限。iCloud 独有资源需要开启 App 内网络读取，可能产生下载、流量和耗时；关闭时无法读取的内容保留未知或待处理状态。
- 大小为原始媒体资源字节之和，不等于本机占用或立即可释放空间。删除会影响 iCloud 同步图库，系统“最近删除”也会影响空间回收。
- 识别结果为启发式候选，会误判或漏判；尚无自然语言语义向量搜索，不能承诺任意描述检索。
- OCR、标签和特征缓存在本机，不上传照片到自建服务；系统 iCloud 下载由 PhotoKit 处理。扫描在前台进行，进入后台会暂停。
- 相似组、敏感内容和模糊提示需逐张核对。首次测试使用已备份样本，勿直接批量删除重要原片。
