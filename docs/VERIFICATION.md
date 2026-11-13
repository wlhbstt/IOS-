# 验证记录

日期：2026-11-13。

## 本地已验证

- 官方 Swift 6.0.3、WSL Ubuntu 24.04：`swift test` 运行 18 项 XCTest，0 失败。覆盖搜索归一化、元数据更新、大小排序和删除保护规则。
- Swift 前端解析 App 全部 9 个 Swift 文件及界面测试：退出码 0。仅语法解析，不是 Apple SDK 类型检查。
- `node scripts/validate-project.mjs`：退出码 0，项目输入文件和必需声明存在。
- PowerShell XML 解析 `App/Info.plist`：通过。
- `bash -n scripts/build-ios.sh scripts/install-swift-test-toolchain.sh`：退出码 0。
- `git diff --check`：通过。

## 集成与设备状态

- 旧版 0.1.0：用户已通过 Sideloadly 安装运行。新版 0.2.0 覆盖安装、免费账号续签及真机结果待验证。
- 性能和删除变更的基线提交 `9672e1a`：[运行 43351440397](https://github.com/wlhbstt/IOS-/actions/runs/43351440397) 成功，Xcode 16.4 / iPhoneOS SDK 18.5，18 项核心测试、3 项模拟器索引测试、Release 编译与 IPA 校验通过。此基线不包含后续界面和后台变更。
- 后续原生界面验收在隔离模拟器使用 6 张系统样片和 3 张公开样片。已实际检查首页与选择截图，修正了工具栏层级、权限处理和按钮空白区域点击范围。失败的界面测试不发布 IPA。
- 0.2.0 / build 2，提交 `093f2fd`：[运行 43366426837](https://github.com/wlhbstt/IOS-/actions/runs/43366426837) 成功。Xcode 16.4 / iPhoneOS SDK 18.5，18 项核心测试、3 项索引测试和 1 项原生界面流程通过，真机 Release 编译与 IPA 校验通过。产物为 `PhotoCleaner-unsigned-15`。
- 原生界面流程确认样片预览加载、9 张样片分析完成、短时切前后台、勾选删除、系统删除确认及列表数量减一。该流程耗时 71.614 秒包含启动、授权和界面等待，不能用作照片分析速度指标。
- 预览回归：在原图存在的情况下，旧 `fast-single + resize: exact` 请求返回 `PHPhotosErrorDomain 3303`；改为小尺寸高质量请求后，实际加载检查通过。云端测试使用本地临时签名的模拟器 App，Release IPA 保持未签名。
- 已下载并核对 `build/PhotoCleaner-0.2.0.ipa`：522604 字节，0.2.0 / build 2、iPhoneOS、最低 iOS 18.0、arm64 Mach-O、ZIP 全部条目校验通过。SHA-256：`1d05496b78a73504c0726f9196ae062a34d9a19815c95d888ca291f748487910`。
- 已查看原生首页、图库选择、搜索、系统删除确认和删除后截图：真实样片显示，计数从 9 项变为 8 项；可见文字与操作栏无重叠。截图来自 iPhone 16 Pro / iOS 18.5 模拟器，不是目标手机的截图。
- 新版真机 PhotoKit 删除和系统“最近删除”、锁屏后台调度、iCloud、识别准确率与几万张图库耗时/内存/温度：尚未验证。

## 重现本地测试

```powershell
wsl -d Ubuntu -- bash scripts/install-swift-test-toolchain.sh test --package-path /mnt/e/git-sanyi/iphone-photo-cleaner
node scripts/validate-project.mjs
```

自动化验证只覆盖所列环境和样本，不替代 [真机检查表](DEVICE-CHECKLIST.md)。
