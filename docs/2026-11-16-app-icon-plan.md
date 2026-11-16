# A 方案应用图标

目标：将用户确认的绿色照片叠层与勾选图标加入 App，交付 0.3.3 / build 6 未签名 IPA。

- [x] 将预览 A 的原始 1024 方图转为 RGB PNG，加入 `App/Assets.xcassets/AppIcon.appiconset`；保留完整方形背景，由系统处理外形。
- [x] `project.yml` 指定主 AppIcon，保留名称与 Bundle ID；本地检查 PNG、资源 JSON 和构建脚本语法通过。
- [x] 运行 43790053998 的 45 项测试和 Release 编译成功，产物主图标声明与 Assets.car 检查通过；已下载校验版本、架构、ZIP 和包内图标文件。
- [x] 更新安装入口与验证记录；同一签名账号及实际 Bundle ID 覆盖安装，真机桌面图标待安装确认。
