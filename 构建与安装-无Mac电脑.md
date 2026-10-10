# 把 PixMate 装到 iPhone 上

这份是照着你这台 Windows 电脑写的。不用 Mac，不用开发者账号，花 0 元。

---

## 先说清楚为什么非要「云端编译」这一步

iOS 的 App 只能在 macOS 上编译打包 —— 这是 Apple 的硬规定，绕不过去。
所以做法是：**把代码交给 GitHub，让 GitHub 的云端 Mac 帮你编译**，编译好的安装包你下载下来装进手机。

GitHub 的 macOS 构建机对**公开仓库完全免费**。代价有两个，都提前告诉你：

- 代码会变成公开的（里面没有隐私数据，只有 App 源码）
- 免费 Apple ID 签出来的 App **7 天有效期**，到期重装一次即可

---

## 我这边已经替你做好的部分

| 事情 | 状态 |
|---|---|
| 工程源码（30 个 Swift 文件） | 已完成 |
| 云端构建脚本 `.github/workflows/build-ipa.yml` | 已写好 |
| 工程配置里的 scheme（缺了云端构建必挂） | 已补上 |
| `.gitignore`（避免把构建垃圾推上去） | 已加 |
| **git 仓库初始化 + 首次提交** | **已完成**（36 个文件已入库） |
| 结构体检（括号配平、类型重复、键路径） | 已通过 |

**所以你不用碰任何命令行。** 剩下三件事，全在图形界面里点。

---

## 第 1 步 · 把代码送上 GitHub（约 5 分钟）

### 1.1 打开 GitHub Desktop

工具我已经通过 winget 帮你装好了。在开始菜单搜 `GitHub Desktop` 打开。

> 如果搜不到（安装失败），去 https://desktop.github.com/ 下载安装，一路下一步即可。

### 1.2 登录 GitHub

第一次打开会停在欢迎页：

- 已经有 GitHub 账号 → 点 **Sign in to GitHub.com** → 浏览器弹出登录 → 授权后回到 GitHub Desktop
- 没有账号 → 点 **Create your free account**，用邮箱注册一个（免费，1 分钟）

### 1.3 把这个文件夹加进来

GitHub Desktop 顶部菜单 **File → Add local repository...**

在弹出的窗口里，**Local path** 那一栏，把下面这行整个复制进去：

```
C:\Users\饭饭之叫\WorkBuddy\2026-10-10-12-14-33\outputs\PixMate
```

然后点 **Add Repository**。

> 正常的话，你会看到左边列出了 36 个文件，底部写着 "No local changes"。
> 如果它说这不是一个 Git 仓库，说明路径粘错了 —— 注意结尾没有多余的空格。

### 1.4 发布到 GitHub

点界面**顶部中间**的 **Publish repository** 按钮。

弹出来的小窗里有两点要处理：

1. **把 `Keep this code private` 的勾去掉** —— 这一步最关键。私有仓库跑 macOS 构建要花额度，公开仓库完全免费
2. Repository name 保持 `PixMate` 就行

然后点 **Publish repository**。

到此，代码已经在你 GitHub 账号上了。

---

## 第 2 步 · 拿云端编译好的安装包（约 10 分钟）

1. 打开浏览器，进入 `https://github.com/你的用户名/PixMate`
2. 点顶部 **Actions** 标签
3. 会看到一条 **Build unsigned IPA** 正在跑（黄色圆点）。等它变成**绿色勾**（约 5–10 分钟）
4. 点进那条运行记录 → 拉到页面**最底部** → **Artifacts** → 点 **PixMate-unsigned-ipa** 下载
5. 下载到的是一个 zip，**解压**得到 `PixMate-unsigned.ipa`

**如果变成红叉**：点进失败的那一步，把日志截图或文字发我，我来改工程。
这一步出错基本只有两种原因：Xcode 版本对不上、或者代码里有编译错误 —— 前者我改脚本，后者我改代码。

---

## 第 3 步 · 装到 iPhone（约 10 分钟）

### 3.1 装两个前置软件

| 软件 | 从哪下 | 注意 |
|---|---|---|
| **iTunes** | **必须从 apple.com 下载官方版** | 不要用微软商店版，它不带 iPhone 驱动，Sideloadly 会报错 |
| **Sideloadly** | https://sideloadly.io/ 选 Windows 版 | 免费 |

iTunes 装完**至少打开一次**（我们只是要它带的那份驱动，不是让你用它听歌）。

### 3.2 用 Sideloadly 装

1. 手机用数据线插到电脑，**手机上弹出「信任此电脑」要点信任**
2. 打开 Sideloadly，界面从上到下依次：
   - **iDevice**：应该自动认出你的 iPhone
   - **Apple ID**：填你的 Apple ID 账号（免费账号就行）。建议用自己常用的那个，不要用小号 —— 它会生成一份设备描述文件
   - 把 `PixMate-unsigned.ipa` **拖进中间的框**
3. 点 **Start**，会让你输一次 Apple ID 密码（送给 Apple 服务器签名用）
4. 等到提示 **Done**，手机桌面上就出现「像素搭档」了

### 3.3 手机上还要开两个开关（只做一次）

- **信任开发者**：设置 → 通用 → VPN与设备管理 → 开发者 App → 点你的 Apple ID → 信任
- **开发者模式**：设置 → 隐私与安全性 → 拉到底 → 开发者模式 → 打开 → **重启手机**

第二个开关不开的话，点图标会直接闪退。这是 iOS 17 的强制要求，不是 App 的问题。

---

## 第 4 步 · 7 天到期怎么续

免费 Apple ID 签的 App 是 **7 天有效期**，第 8 天点开会提示「无法验证 App」。

**续期**：Sideloadly 里设置都还在，把 ipa 再拖进去点一次 Start 就行。

**项目数据不会丢** —— 项目库和照片都在 App 沙盒里，重装同一份 ipa 不清数据。

嫌麻烦的两档升级（自用其实没必要）：

- 借一台 Mac 用 Xcode 直接 Run（同样受 7 天限制）
- 开发者账号 99 美元/年（签名变 1 年）

---

## 卡住了对着这张表查

| 现象 | 原因 / 解决 |
|---|---|
| GitHub Desktop 里点 Publish 后 Actions 没动静 | 确认推上去的分支是 `main`；确认 `.github/workflows/build-ipa.yml` 在仓库里能看到 |
| Actions 红叉，日志写 `scheme not found` | 推上去的工程不是最新的，重新提交一次 |
| Actions 红叉，日志里是 Swift 编译错误 | 把那段日志发我，我改代码 |
| 下载 Artifacts 是灰色的点不动 | 没登录 GitHub，或这次运行还没结束 |
| Sideloadly 报 `Could not find Apple Mobile Device Support` | 装的 iTunes 是微软商店版，卸掉换 apple.com 官方版 |
| 手机列表里认不到设备 | 换一根**能传数据**的线（有些线只供电）；手机上确认点了「信任此电脑」 |
| App 图标点开就闪退 | 开发者模式没开（设置 → 隐私与安全性 → 开发者模式） |
| 提示「无法验证 App」 | 7 天到期了，重新 Start 签一次 |
| 装上了但连不上相机 | 回到正题了 —— 按 App 里连接向导的四步核对相机设置 |

---

## 装好之后：回到真机校准

App 跑起来、Z6II 连上、实时取景出图之后，把诊断日志发我：

**连接相机页 → 拉到底「诊断」→ 点开「协议交互日志」→ 点「导出诊断日志」**
→ 分享面板选微信 → 发给「文件传输助手」→ 电脑上收下来 → 拖进对话。

日志里带着设备型号、iOS 版本、连接状态、帧率，以及每一步 PTP 命令的原始返回码。
**快门入参**和**参数档位**这两处校准点，就靠它一次修到位。

---

## 附：如果你更想用命令行

工程已经初始化好 git 仓库并提交过了，所以最短路径是：

```bash
cd "C:/Users/饭饭之叫/WorkBuddy/2026-10-10-12-14-33/outputs/PixMate"

# 先在 GitHub 网页上建一个空的公开仓库（不要勾 Add README / .gitignore）
git remote add origin https://github.com/<你的用户名>/PixMate.git
git branch -M main
git push -u origin main
```

推送时会要求认证。GitHub 不接受账号密码，两条路：

- 装 [GitHub CLI](https://cli.github.com/)，跑 `gh auth login`，之后再 `gh repo create` + `git push`
- 或者生成 Personal Access Token（GitHub 网页 → Settings → Developer settings → Tokens，勾 `repo` 权限），push 时用户名填 GitHub 用户名、密码粘 token

命令行这条路的好处是：装好 `gh` 并登录之后，**建仓库、推送、盯构建、下载 ipa 我都能替你跑完**，你只需要授权一次。想走这条就告诉我。
