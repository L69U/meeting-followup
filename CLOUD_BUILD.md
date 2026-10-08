# 在 Windows 上准备、通过云端 Mac 验证 iOS

当前没有 Mac、Xcode 或已连接的 GitHub 构建环境。项目已准备手动触发的 GitHub Actions 配置，但没有运行过；这不是已通过构建的证据。

## 这条路径能做到什么

GitHub 的 macOS runner 可以生成 Xcode 项目、编译模拟器版本并执行 XCTest。无需先买 Apple Developer 会员即可做模拟器编译测试。它不会自动让 App 安装到你的 iPhone，也不会替你上架。

真机安装、TestFlight 和正式发布还需要后续的签名、开发者账号及相应配置。当前工作流不包含这些步骤。

## 运行前

1. 准备你自己管理的 GitHub 账号及仓库；建议先用私有仓库。
2. 核实账户 Actions 免费额度、macOS runner 计费和预算设置。私有仓库的云端构建不能假定无限免费。
3. 仓库根目录应直接包含 `ios`、`backend`、`scripts` 和 `.github`，即上传本项目目录内的内容，不是整个 Codex 工作目录。
4. 不上传录音、客户文件、API Key、访问令牌、`.env`、Apple 证书或密码。此构建任务不需要任何 API 凭据。
5. 在 Actions 中选择 `iOS simulator verification` → Run workflow。工作流只支持手动触发，普通提交不会自动开跑。

## 如何解释结果

- 绿色：表示该次提交在那个云端 Xcode 环境下构建并通过当前四项模型测试；不代表 UI、真实转录或 App Store 审核通过。
- 红色：查看第一个编译或测试失败点，修复后重新运行。
- `ios-test-results`：可下载的 XCTest 结果包，保留七天。
- 不把模拟器构建产物称为可安装到 iPhone 的 IPA。

## 官方资料

- [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Actions 计费](https://docs.github.com/en/actions/concepts/billing-and-usage)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
