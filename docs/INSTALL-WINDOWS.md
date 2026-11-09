# Windows 编译与安装

适用目标：Windows 电脑、iPhone 15 Pro / iOS 18.5、免费 Apple 账号。Windows 不能本地执行 Xcode 编译，本项目采用 GitHub 托管 macOS 编译与 Windows 本地签名的流程。尚未执行云端构建或真机安装，以下步骤需实际验证。

## 1. 获取云端未签名 IPA

1. 在自己的 GitHub 账号创建仓库，将本项目源码上传；不要上传照片、缓存、Apple 密码、证书或描述文件。
2. 在仓库 Actions 中启用工作流，选择 `iOS unsigned build`，点击 `Run workflow`。push 和 PR 也会运行。
3. 等待任务完整成功。日志应包含核心测试、Xcode 版本与 SDK、真机 Release 编译和 IPA 检查。失败时查看首个报错；失败任务不会发布 IPA。
4. 在成功任务的 Artifacts 中下载 `PhotoCleaner-unsigned-<运行号>`，解压外层 ZIP，得到 `PhotoCleaner-unsigned.ipa`。产物保留 7 天，过期可重新构建。

这份 IPA 尚未签名，不能直接点开或通过网页安装。工作流使用 runner 当前选中的 Xcode，并要求 iPhoneOS SDK 不低于 18.0；实际兼容性以构建日志为准。不要给 GitHub Actions 添加 Apple 登录凭据。

GitHub 公共仓库的标准托管 runner 计算通常免费；私有仓库会消耗账号配额，超额可能计费，artifact 存储也有单独额度。上传前核对自己的预算，不必为免费计算公开私人代码。参考 [GitHub Actions 计费](https://docs.github.com/en/billing/concepts/product-billing/github-actions)。

## 2. 准备 Windows 与 iPhone

1. 仅从 [Sideloadly 官方网站](https://sideloadly.io/) 下载 Windows 版。按官网 `Before you install` 提示安装 Apple 网页版 iTunes 与 iCloud；官网明确要求先卸载 Microsoft Store 版本，再使用其 Apple 官方下载链接。
2. 先打开 iTunes，确认它可以识别手机。使用支持数据传输的 USB 线连接，解锁手机，在手机上选择“信任此电脑”并输入锁屏密码。
3. iOS 16 及以上侧载开发 App 需要开发者模式。在“设置 → 隐私与安全性 → 开发者模式”开启，按提示重启并确认。若该项暂未出现，先完成 USB 配对和首次安装尝试，再检查设置；查看 [Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。

Sideloadly 是第三方本地签名工具，需要你自行接受其登录处理方式。Apple 账号、密码与双重认证码仅在你自己的电脑中按该工具提示操作，不放入本仓库、CI secrets 或聊天。

## 3. 本地签名并安装

1. 打开 Sideloadly，选择已连接的 iPhone，把 `PhotoCleaner-unsigned.ipa` 拖入窗口。
2. 输入自己的 Apple 账号，点击 `Start`，按提示完成密码和双重认证。首次安装记录工具最终使用的 Bundle ID 和签名账号，后续更新保持一致；不要每次随机更换 Bundle ID。
3. 等待工具明确报告安装完成。若系统要求信任开发者，在“设置 → 通用 → VPN 与设备管理”中按提示信任自己的开发者身份。
4. 打开“相册整理”，按需授予照片访问权限。先使用少量已备份照片完成 [真机检查表](DEVICE-CHECKLIST.md)。

若安装失败，保留 Sideloadly 首个错误码和完整错误描述，并检查 USB 识别、开发者模式、账号验证和 App 名额。不要把未签名 IPA 改后缀或反复删除照片来排障。

## 4. 免费账号续签与更新

免费个人账号的描述文件有效期为 7 天，每台设备最多安装 3 个此类 App；不能承诺永久免维护。限制见 [Apple 免费开发者账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account)。

在 Sideloadly 中启用自动刷新并保持其 Daemon 运行。续签时电脑必须可用，且手机可通过 USB 或已配置的同一 Wi-Fi 网络被发现；它不在纯手机离线状态下自动完成。首次建议 USB，Wi-Fi 刷新按 [Sideloadly 官方 FAQ](https://sideloadly.io/faq.html) 设置 iTunes 的 Wi-Fi 同步。

如果到期无法启动，连接电脑对同一个 App 重新签名安装。升级也是用新 IPA、同一签名账号及同一实际 Bundle ID 覆盖安装，优先保留本地索引和设置。不要先卸载，卸载会删除 App 的本地缓存和设置；原始照片仍由系统照片图库管理。
