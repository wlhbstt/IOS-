# 验证记录

日期：2026-11-13。

## 0.3.1 删除反馈修复

- 用户反馈：滑动整理的待删清单提交后长时间不可操作、没有提示，截图显示 7,116 项图库与待确认 0 项。截图不能单独证明时间消耗在哪个阶段。
- 代码确认：原删除流程在 PhotoKit 成功、清空待删清单后仍等待全库索引 `retain`；根页面的删除提示会被全屏整理页和确认 sheet 遮挡，刷新状态也未在全屏页显示。
- 回归提交 `3d63671`，[运行 43399803558](https://github.com/wlhbstt/IOS-/actions/runs/43399803558) 按预期失败：系统删除弹窗出现后，确认页没有处理状态。其余既有核心、原生和另外两条界面流程通过。
- 修复源码 `bb8f6c7`：确认页、全屏页和根页面分别显示核验、系统删除或刷新状态；PhotoKit 成功后只按本次 ID 异步清理索引，不再等待缓存维护才恢复操作。相簿与保护清单查询移出主线程，刷新期间保护设置变化则重新读取。确认页提交中禁止下滑关闭。
- [运行 43401823686](https://github.com/wlhbstt/IOS-/actions/runs/43401823686) 成功：Xcode 16.4 / SDK 18.5，29 项核心、8 项原生、3 项界面流程通过。原先失败的确认页状态断言通过，取消后重试、确认删除、返回整理和数量减一均通过；Release 编译、arm64、设备平台与 ZIP 检查通过。
- 新增 8,000 条索引定向删除测试通过，检查保留搜索文字、其他特征及复核后新增记录，重复清理不改变结果。该测试耗时 0.429 秒包含准备、写入、删除和重新加载，不能作为真机删除耗时指标。本地 Swift 语法解析、项目输入与差异检查通过。
- 本地安装包 `build/PhotoCleaner-0.3.1.ipa` 已核对：0.3.1 / build 4、829733 字节、`com.localphototools.PhotoCleaner`、iPhoneOS、最低 iOS 18.0、arm64 Mach-O、ZIP 全条目校验通过。SHA-256：`fc42d447131127c99901747d663b395fb47bc2be7ffa6bee47f9811b7af82739`。云端产物为 `PhotoCleaner-unsigned-22`，沿用原账号和实际 Bundle ID 覆盖安装。
- 目标手机的具体删除耗时、图库同步和系统最近删除恢复仍待新包安装后验证；不把源码问题认定为真机长耗时的唯一原因。

## 0.3.0 追加验证

- 最终源码 `e93fa700f2e2497d6844fee8a8955e7b61097e48`，[运行 43385418935](https://github.com/wlhbstt/IOS-/actions/runs/43385418935) 成功。Xcode 16.4 / SDK 18.5，29 项核心、7 项索引/压缩原生测试、3 项界面流程全部通过；Release 真机编译、arm64、设备平台及 ZIP 检查通过，安装包 Artifact 为 `PhotoCleaner-unsigned-20`。
- 界面流程实际覆盖：公开样片加载和分析、短时前后台切换、四向滑动、撤销、收藏暂存与确认、取消删除后再次确认、列表数量减一、双行浏览、生成压缩预览、保存副本后数量加一且原件保留。模拟器为 iPhone 16 Pro / iOS 18.5；这些流程不能证明目标手机的大图库性能或持续后台运行。
- 本地安装包 `build/PhotoCleaner-0.3.0.ipa` 已核对：0.3.0 / build 3、820506 字节、`com.localphototools.PhotoCleaner`、iPhoneOS、最低 iOS 18.0、arm64 Mach-O、ZIP 全条目校验通过。SHA-256：`0cb7688e2c6b8f3d225e8968511c1cc59f73f8f47a7556b213bd2d5b1562a7e7`。这份 IPA 未签名，需沿用原 Apple ID 和实际 Bundle ID 通过 Sideloadly 覆盖安装。
- 本地核心验证：既有 27 项及新增 2 项压缩原件删除保护测试通过；App/测试全部 Swift 文件语法解析、项目输入与 shell 语法检查通过。
- 初轮提交 `e707e82`，[运行 43379405435](https://github.com/wlhbstt/IOS-/actions/runs/43379405435)：Xcode 16.4 / SDK 18.5 模拟器编译通过，27 项核心、7 项原生索引/压缩测试以及原有分析与删除界面流程通过。视频测试实际生成并导出 MP4，验证尺寸、时长及输入不变；图片测试验证降采样和原件不变。
- 初轮两项新增界面流程失败：整理大图元素未找到，压缩接受开关未开启；Release 打包未执行，未发布 IPA。后续已调整点击范围、无障碍标识与开关测试定位，最终结果见本节首项。
- 第二轮 `2033ef7`，[运行 43381090083](https://github.com/wlhbstt/IOS-/actions/runs/43381090083)：29 项核心、7 项原生测试与既有界面流程通过。新增界面流程实际通过四向手势、撤销、收藏提交和生成压缩预览；后续失败分别为测试未滚动至保存按钮，以及系统取消按钮为 `Don’t Allow` 而非 `Cancel`。未发布 IPA。测试定位已修正于 `dba4d84`。
- 第三轮 `dba4d84`，[运行 43383331416](https://github.com/wlhbstt/IOS-/actions/runs/43383331416)：滑动、撤销、收藏、取消删除、再次确认删除以及计数减一完整通过。压缩已生成 1004204 字节副本预览，原件 2379043 字节；保存按钮被父 Section 的无障碍标识覆盖，测试失败。已移除父标识，并补上副本预览的独立标识与加载检查。
- 连拍读取核对：原查询没有开启 `includeAllBurstAssets`，会遗漏未挑选的连拍成员。已统一全库、按 ID、相簿保护、收藏和删除的查询选项；依据 [Apple 文档](https://developer.apple.com/documentation/photos/phfetchoptions/includeallburstassets)。真实连拍分组和删除需真机验收。
- 真机四向手势、自定义、有限授权、照片坐标、视频音轨/HDR、iCloud、压缩质量及大型图库性能待验收。

## 0.2.0 本地基线

- 官方 Swift 6.0.3、WSL Ubuntu 24.04：`swift test` 运行 18 项 XCTest，0 失败。覆盖搜索归一化、元数据更新、大小排序和删除保护规则。
- Swift 前端解析 App 全部 9 个 Swift 文件及界面测试：退出码 0。仅语法解析，不是 Apple SDK 类型检查。
- `node scripts/validate-project.mjs`：退出码 0，项目输入文件和必需声明存在。
- PowerShell XML 解析 `App/Info.plist`：通过。
- `bash -n scripts/build-ios.sh scripts/install-swift-test-toolchain.sh`：退出码 0。
- `git diff --check`：通过。

## 0.2.0 集成与设备状态

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
