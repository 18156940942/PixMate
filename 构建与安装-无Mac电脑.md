# 没有 Mac，怎么把它装到 iPhone 上

这份是给「只有一台 Windows 电脑」的情况写的。全程不需要 Mac，也不需要开发者账号（花 0 元），  
唯一的小代价是免费账号签出来的 App **7 天有效期**，到期重装一次即可续期。

总共四步，大约 20 分钟，其中 10 分钟是等云端编译。

---

## 前置准备（一次性）

| 需要什么       | 说明                                                |
| ---------- | ------------------------------------------------- |
| GitHub 账号  | 免费注册即可，公共仓库跑 macOS 构建**不收钱**                      |
| Git        | 你这台机器已经有（Git Bash）。没有就装 Git for Windows           |
| iTunes     | **必须从 apple.com 下载官方版**，不要用微软商店版（商店版不带 iPhone 驱动） |
| Sideloadly | 官网 sideloadly.io 下载 Windows 版，免费                  |
| iPhone     | iOS 17 及以上（工程部署目标就是 17.0）；需要一根数据线                 |

---

## 第 1 步 · 把工程推上 GitHub

在 Git Bash 里执行（把 `<你的用户名>` 换成你的 GitHub 用户名）：

```bash
cd "C:/Users/饭饭之叫/WorkBuddy/2026-10-10-12-14-33/outputs/PixMate"

git init
git add .
git commit -m "PixMate v1.1"
git branch -M main
git remote add origin https://github.com/<你的用户名>/pixmate.git
git push -u origin main
```

**先在 GitHub 网页上新建一个空仓库**（名字随便，比如 `pixmate`），**不要**勾选  
「Add a README」或「.gitignore」——否则 push 会冲突。

推送时会要求登录。GitHub 现在不接受密码，两个办法二选一：

- **简单**：装 [GitHub Desktop](https://desktop.github.com/)，登录后把  
  `outputs/PixMate` 这个文件夹「Add local repository」→ Publish，图形界面点两下就完事；
- **命令行**：在 GitHub 网页 `Settings → Developer settings → Personal access tokens`  
  生成一个勾了 `repo` 权限的 token，push 时用户名填 GitHub 用户名，密码处粘贴 token。

> 仓库根目录就是 `outputs/PixMate`（`.github/workflows/build-ipa.yml` 在这个文件夹里），  
> 云端脚本的路径是按这个结构写的。如果你推的是整个 WorkBuddy 工作区，需要把 yml 里的  
> `xcodegen generate` 前面补一行 `cd outputs/PixMate`。

---

## 第 2 步 · 等云端编译，下载 ipa

推上去之后：

1. 打开你的仓库 → 顶部 **Actions** 标签页
2. 会看到一条 `Build unsigned IPA` 正在跑（黄点），等到变**绿勾**（约 5–10 分钟）
3. 点进那次运行 → 页面底部 **Artifacts** → 下载 `PixMate-unsigned-ipa.zip`
4. 解压得到 **`PixMate-unsigned.ipa`**

如果变红叉：点进失败的那一步看日志，把日志发我，我来改工程。  
最常见的是 Xcode 版本对不上（脚本已固定用 runner 上最新的 Xcode）和 scheme 缺失（已在  
`project.yml` 里显式声明，不该再出现）。

---

## 第 3 步 · 用 Sideloadly 装到 iPhone

1. **装好官方 iTunes** 并至少打开一次（装的是 iPhone 驱动，不是让你用 iTunes 听歌）
2. 手机用数据线插到电脑，**手机上点「信任此电脑」**
3. 打开 **Sideloadly**，界面从上到下：
   - `iDevice`：应该自动识别出你的 iPhone
   - `Apple ID`：填你的 Apple ID（免费账号就行，**不建议用小号**，因为会生成设备描述文件）
   - 把 `PixMate-unsigned.ipa` **拖进中间的框**
4. 点 **Start**，会让你输一次 Apple ID 密码（这是送给 Apple 服务器签名用的，Sideloadly 官方说明不会上传到别处）
5. 等到提示 `Done`，手机桌面上就出现「像素搭档」了

### 手机上还要开两个开关（只做一次）

- **信任开发者**：设置 → 通用 → VPN与设备管理 → 开发者 App → 点你的 Apple ID → 信任
- **开发者模式**（iOS 16+ 必须）：设置 → 隐私与安全性 → 拉到底 → 开发者模式 → 打开 → **重启手机**

不打开第二个开关，App 图标点一下会闪退，这是 iOS 17 的强制要求，不是 bug。

---

## 第 4 步 · 7 天到期怎么办

免费 Apple ID 签的 App 是 7 天有效期，到第 8 天点开会提示「无法验证 App」。

**续期方式**：Sideloadly 保持之前的设置，重新点一次 Start 就行。**项目数据不会丢**——  
项目库和照片都存在 App 沙盒里，重装同一份 ipa 不会清数据。

嫌麻烦的话有两档升级：

- 借一台 Mac 用 Xcode 直接 Run：连 Xcode 就不用 Sideloadly，但免费账号同样是 7 天；
- 开发者账号（99 美元/年）：签名变成 1 年有效期，还能开更多功能。自用没必要。

---

## 常见报错

| 现象                                                        | 原因 / 解决                                      |
| --------------------------------------------------------- | -------------------------------------------- |
| Actions 里红叉，日志说 `scheme not found`                        | `project.yml` 里的 `schemes:` 段没生效，确认推上去的是最新工程 |
| Sideloadly 报 `Could not find Apple Mobile Device Support` | 装的 iTunes 是微软商店版，卸掉换 apple.com 官方版           |
| App 图标点开就闪退                                               | 开发者模式没开（设置 → 隐私与安全性 → 开发者模式）                 |
| 提示「无法验证 App」                                              | 7 天到期了，重新 Start 签一次                          |
| 手机列表里认不到设备                                                | 换一根**能传数据**的线；手机上确认点了「信任此电脑」                 |
| 装上了但连不上相机                                                 | 这才是回到正题——按 App 里连接向导的四步核对相机设置                |

---

## 装好之后：回到真机校准

App 跑起来、Z6II 连上、实时取景出图之后，把诊断日志发我就行：

**连接相机页 → 拉到底「诊断」→ 点开「协议交互日志」→ 点「导出诊断日志」**  
→ 分享面板选微信 → 发给「文件传输助手」→ 电脑上收下来 → 拖进对话。

日志里带着设备型号、iOS 版本、连接状态、帧率，以及每一步 PTP 命令的原始返回码。  
快门入参和参数档位这两处校准点，就靠它一次修到位。
