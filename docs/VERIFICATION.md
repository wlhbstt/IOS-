# 验证记录

日期：2026-11-09。

## 本地已验证

- 官方 Swift 6.0.3、WSL Ubuntu 24.04：`swift test` 运行 16 项 XCTest，0 失败。
- Swift 前端解析 App 全部 7 个 Swift 文件：退出码 0。仅语法解析，不是 Apple SDK 类型检查。
- `node scripts/validate-project.mjs`：退出码 0，项目输入文件和必需声明存在。
- PowerShell XML 解析 `App/Info.plist`：通过。
- `bash -n scripts/build-ios.sh scripts/install-swift-test-toolchain.sh`：退出码 0。
- 规格审查与代码质量审查：发现的问题已修正，包括删除审核过期、复杂资源推荐、暂停时相似结果丢失、关闭云端读取未取消扫描及 SDK 18 符号兼容。

## 集成与设备状态

- GitHub macOS 构建：准备运行，尚无成功证据。
- 未签名 IPA：尚未生成。
- Windows 签名、iPhone 安装、免费账号续签：尚未执行。
- 真机 UI、PhotoKit 回调、iCloud、识别效果与几万张图库性能：尚未执行。

## 重现本地测试

```powershell
wsl -d Ubuntu -- bash scripts/install-swift-test-toolchain.sh test --package-path /mnt/e/git-sanyi/iphone-photo-cleaner
node scripts/validate-project.mjs
```

云端成功只证明构建和核心测试通过，不替代 [真机检查表](DEVICE-CHECKLIST.md)。
