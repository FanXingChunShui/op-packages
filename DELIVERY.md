# op-packages Migration & CI/CD Delivery Report

## 概要

本仓库 `op-packages` 是从 coolsnowwolf/packages 迁移 6 个 IPSec/OpenVPN/SoftEther VPN 服务端插件到 OpenWrt 25.12.5 + apk + OpenSSL 3.5 + Linux 6.12 的独立仓库。

**已完成 (Done):**
- 6 个包迁移完毕并通过 5 项静态检查
- CI/CD 基础设施完整: 静态检查 → 构建 6 个包目录 (13 个变体) → apk 验证 → weekly upstream 监测
- 主仓库已推送至 `https://github.com/FanXingChunShui/op-packages`
- run `39012977431` (HEAD `551e78e`): **整条流水线全绿**, 6 个 build job 全部编译
  并通过 Verify, Stage 3 对 103 个 .apk 的 829 项检查全部通过。详见第九节
- 三个阻断性根因 (A/B/C) 已定位、修复并本地实证, 见第八节
- 后续四项问题 (strongswan 版本、metapackage、Stage 3 工具链) 见第九节

**状态: 交付完成。** 6 个包在 OpenWrt 25.12.5 / apk-tools 3.0.5 / OpenSSL 3.5 /
GCC 14.3 上全部编译成功并通过功能验证。

---

## 一. 仓库结构

```
op-packages/
├── .github/workflows/
│   ├── ci.yml           # 5-stage CI: 静态+构建+验证+上游监测+汇总
│   └── release.yml      # tag 触发
├── net/                 # 6 个 VPN 包
│   ├── libreswan/       # IPsec/IKEv1+IKEv2 (4.9 → 4.15)
│   ├── strongswan/      # IPsec/IKEv1+IKEv2 (6.0.7 → 6.1.0)
│   ├── openvpn/         # SSL VPN (2.7.4 → 2.7.8, 3 SSL 后端变体)
│   ├── openvpn-easy-rsa/# CA 管理工具 (3.0.8 → 3.2.0)  ✓ 已端到端验证
│   ├── softethervpn/    # (4.38 → 4.42)
│   └── softethervpn5/   # (5.2.5188 latest)
├── tests/
│   ├── configs/sdk-minimal.config  # OpenWrt SDK 引导配置
│   ├── scripts/                    # 7 个测试/验证脚本
│   ├── Dockerfile.openwrt-sdk      # 本地 Docker 构建 (保留)
│   └── ...
├── docs/
│   ├── OPENSSL3-MIGRATION.md       # OpenSSL 3.5 适配
│   ├── APK-NOTES.md                # apk vs opkg 兼容性
│   └── CI-CD.md                    # CI/CD 详细文档
└── README.md
```

每个包都遵循 OpenWrt Makefile + patches/ + files/ 三件套结构。

---

## 二. CI/CD 流水线 (5 Stage)

```
Push / PR / Tag 触发
  ↓
1. Static checks  (jobs.ubuntu-latest, ~12s)
   - makefile-syntax.sh    Makefile 语法
   - dep-audit.sh          依赖审计 (废弃 kmod/symbols 检查)
   - shellcheck-all.sh     所有 init 脚本 shellcheck
   - validate-inits.sh     procd + UCI semantic check
   - hash-check.sh         PKG_HASH=skip 检查

  ↓
2. Build × 13 matrix  (jobs.ubuntu-24.04)
   - install OpenWrt 工具链
   - 缓存 SDK tarball (actions/cache@v4)
   - 解压 SDK + defconfig
   - git clone op-packages → /opt/oppackages
   - src-link oppackages /opt/oppackages/net (regex-safe 名称)
   - ./scripts/feeds update oppackages
   - ./scripts/feeds install oppackages -a
   - make package/feeds/oppackages/<dir>/compile [BUILD_VARIANT=<x>]
   - 拷贝 .apk/.ipk 到 artifact

  ↓
3. Verify × 6 matrix  (jobs.ubuntu-24.04)
   - tests/scripts/verify-pkg.sh <pkg>
     gzip 完整性 + control.tar.gz 存在
     包元数据匹配 (Package/Architecture/CONFFILES)
     sh -n 检查所有 /etc/init.d/ 脚本
     路径安全检查 / UCI parse

  ↓
4. Upstream version watch (weekly cron)
   - tests/scripts/upstream-check.sh
   - 与上游 packages 对比 PKG_VERSION

  ↓
5. Summary  (jobs.ubuntu-latest, 始终跑完)
   - 汇总所有 job 结果
```

---

## 三. 已修复的构建问题 (#1–#20 及后续 A/B/C, 完整迁移路径)

| 问题 | 根因 | 修复 |
|---|---|---|
| `#1` Docker daemon 没启 | GHA ubuntu-latest 不起 Docker | `docker/setup-buildx-action@v3` |
| `#2` SDK URL `gcc-13.3.0/.tar.xz` | 我的乌龙, 实际是 `gcc-14.3.0/.tar.zst` | 修正 URL, 加 `zstd` |
| `#3` `package/op-packages/` 找不到 | apk 时代 SDK 默认无此目录 | `mkdir -p` 在 symlink 之前 |
| `#4` openvpn-easy-rsa 找不到 rules | Makefile 在 docker 容器内的瞬时目录编译 | 同 docker 容器内收集 |
| `#5` make target path 错 (`package/op-packages/op-packages/<pkg>/compile`) | 我的多算一个 op-packages 段 | 改为单 op-packages 段 |
| `#6` `make install` 退出码被 tail 掩盖 | `make \| tee \| tail` 返回 tail 状态 | 用 `PIPESTATUS[0]` 捕获 make |
| `#7` `python3-distutils` 找不到 | Ubuntu 24.04 Noble 已删 distutils | 从 apt 列表删掉 |
| `#8` `src-link op-packages` feeds.conf 语法错误 | OpenWrt 用 `\w+` regex 解析 feed 名, hyphen 失败 | feed 名换为 `oppackages` |
| `#9` 严格 subdir 检查假阳性 | 多个变体共享单 Makefile 时目录不存在 | 改用包索引路径解析 |
| `#10` bash `if/fi` 没闭合 | 上一次编辑漏 `fi` | 补 `fi` |
| `#11` Config.in 缺失 | kconfig 扫描子目录失败: `tmp/.config-package.in:711: glob failed` | 给 6 个包加最小 Config.in |
| `#12` defconfig 还需 `.config` 启动 | OpenWrt 缺 .config → 走 menuconfig → `Error opening terminal: unknown.` | 拷贝 sdk-minimal.config + defconfig + `TERM=dumb` |
| `#13` `.ipk` vs `.apk` 误判 | OpenWrt 25.12 走 apk 工具链; 产物是 .apk 而非 .ipk | `verify-pkg.sh` 用 .apk/.ipk 双后缀; glob 同步更新 |
| `#14` `softethervpn5-base` 实际是 `softethervpn5-libs` | 历史别名丢失 | 修正 matrix entry, 同时加 `softethervpn5-bridge` |
| `#15` `FEED` not selected | catch-all `%::` 走 `conf --defconfig`, 把 symbol 拨回 `default=n` | `DEVELOPER=1` 强制所有 BuildPackage 注册 |
| `#16` `kmod-fs-afs` 缺 `kafs.ko` 模块 | SDK 缺 `CONFIG_AFS_FS=m` 但被 transitive 拉入 | drop 多余 kmod-*, 仅留 `kmod-tun` |
| `#17` feed 路径解析 | symlink 不被 subdir.mk 当 feed | canonical src-link + feeds install |
| `#18` dir-based target + BUILD_VARIANT | variant 包在 dir 路径下, 名字 <pkgname> 不等于 <dir> | 改 matrix 为 `dir=... variant=...` |
| `#19` `ERROR: package/toolchain failed to build` (`cp: cannot stat .../libasan.so.*`) | `DEVELOPER=1` 让 `Package/$(x)` 注册在 `.config` 之外 — `include/package-bin.mk` 判定 `ifneq ($(CONFIG_PACKAGE_$(1))$(DEVELOPER),)` 永真, 于是把整个 `package/toolchain` 拉进构建; toolchain 里的 `Package/libasan` (`DEPENDS:=@USE_GLIBC`) 在 musl SDK 上 `$(CP) .../toolchain/lib/libasan.so.*` 无文件可拷 | 去掉 `DEVELOPER=1`, 只依赖 `sdk-minimal.config` 里已 `=y` 的 13 个 `CONFIG_PACKAGE_*` |
| `#20` `No feed for package 'libcurl'` / `'libgcrypt'` / `'libsodium'` / `'kmod-ovpn-dco-v2'` ... | 手写 `feeds.conf` 只保留 `base` 一条, 丢了 `packages` 源 — SDK 的 `package/` 几乎为空, 这些共享库与 `python3/host` 全在 `packages` feed | 在 `feeds.conf` heredoc 里同时 `grep` 出 `base` + `packages` 两条 `src-git`, 保留 `install -a -p` 拼写 |

---

## 四. 当前状态 (HEAD 551e78e, run 39012977431)

run `39012977431` (push `551e78e`) 结果: **全绿**。

| Job | 状态 | 备注 |
|---|---|---|
| 1. Static checks | ✅ success | 5 个静态脚本全过 |
| 2. Build libreswan | ✅ success | `libreswan-4.15-r1.apk` |
| 2. Build strongswan | ✅ success | 30+ 子包 (含 4 个 metapackage) |
| 2. Build openvpn | ✅ success | openssl + mbedtls 双后端 |
| 2. Build openvpn-easy-rsa | ✅ success | |
| 2. Build softethervpn | ✅ success | |
| 2. Build softethervpn5 | ✅ success | |
| 3. Verify .apk | ✅ success | **103 个 .apk, 829 项检查全过** |
| 4. Upstream version watch | ⏭ skipped | weekly only |
| 5. CI summary | ✅ success | 汇总 |

CI 日志实测要点:
- `apk-tools 3.0.5, compiled for x86_64` —— Stage 3 的宿主 apk 自检通过;
- `count: 103` → `OK: all 103 package artifact(s) passed functional verification`;
- 4 个 strongswan metapackage 以 `✓ metapackage: no payload (dependency-only)` 通过。

对照基线: 历史 run `68a0b5e` 的 openvpn-easy-rsa job **唯一成功** ——
它的 make 命令行是 `make "package/feeds/oppackages/openvpn-easy-rsa/compile" V=s`,
**没有** `DEVELOPER=1`; 其 `package/toolchain` 只产出 `libgcc1/libc/libatomic1/
libquadmath1/libstdcpp6/libpthread/librt`, 零 `libasan` 引用。这直接证明 #19 是
`DEVELOPER=1` 引入的回归 (该回归已由 `4c4634f` 修复, 后续 run 全部越过此门槛)。

---

## 五. 已交付产物 (可下载的 .apk)

run `39012977431` 的 `pkg-*` artifact 共 103 个 .apk, 覆盖 6 个包目录的全部变体:

| 包 | 产物 | 验证 |
|---|---|---|
| libreswan | `libreswan-4.15-r1.apk` | ✅ |
| openvpn | `openvpn-openssl-2.7.8-r1.apk`、`openvpn-mbedtls-2.7.8-r1.apk` | ✅ |
| openvpn-easy-rsa | `openvpn-easy-rsa-3.2.0-r1.apk` | ✅ |
| softethervpn | base/client/bridge/server (`4.38-r2`) | ✅ |
| softethervpn5 | libs/client/bridge/server (`5.2.5188-r2`) | ✅ |
| strongswan | `-default/-full/-isakmp/-minimal` 等 (`6.0.7-r1`) | ✅ |

openvpn-easy-rsa 的验证内容 (其余包同流程):
  - 全部 14 个 EasyRSA 文件 (easyrsa, vars, openssl-easyrsa.cnf, x509-types/*)
  - /etc/init.d/ + /etc/profile.d/ 全套配置
  - apk-tools v3 格式 (Alpine-compatible)

> 注: `openvpn-wolfssl` **不在**产物中 —— 该变体带 `@BROKEN`, 且 wolfSSL 后端确实
> 编不过 (`ssl_openssl.c:321` 的 `X509_STORE_CTX_set0_crls` 在 wolfSSL 头里不存在)。
> 因此 CI 不选它, `CONFIG_BROKEN` 也不设。这是有意为之, 非遗漏, 见
> `sdk-minimal.config`、`docs/CI-CD.md`、`tests/scripts/build-all.sh` 的说明。

---

## 六. commits 已推送, 仓库 PR-ready

最新 HEAD `551e78e`, 已推送至 main。按阶段倒序:

```
551e78e fix(ci): extract the whole host bin/ and lib/ dirs for Stage 3
285f4a2 fix(ci): extract host lib dir so Stage 3 can run apk-tools
2f51d5f fix(verify): allow dependency-only metapackages with no payload
daabb1b fix(verify): accept real UCI configs (package line, tab-indented options)
cb2e128 fix(strongswan,openvpn): align strongswan to 6.0.7, drop unbuildable wolfssl
21d6db3 docs: record root causes A/B/C behind run 38918400689
3c7ce50 fix(ci): stop BUILD_VARIANT leaking, verify ADB v3 properly, add gcc14 patch
1220c53 docs: record the DEVELOPER=1 / packages-feed regressions and next steps
4c4634f fix(ci): drop DEVELOPER=1 and restore the packages feed
92a63b3 fix(ci): install our feed with -a -p, drop upstream dupes, single build per dir
...
```

仓库已 Public 公开：https://github.com/FanXingChunShui/op-packages

---

## 七. 残余事项 (不阻塞交付)

第七节原列的 7 项包级问题, 已随 A/B/C 修复与 strongswan 对齐全部消除
(openvpn 的 libnl/DCO 探测、`kmod-ovpn-backports` 改名、libreswan 的 NSS 头、
strongswan 补丁 hunk、softethervpn 的 tarball 404 等)。仅剩两项**有意保留**的
已知限制:

1. **openvpn-wolfssl 变体不构建**: wolfSSL 后端在本代码版本确实编不过
   (`ssl_openssl.c:321` 的 `X509_STORE_CTX_set0_crls` wolfSSL 头未提供)。
   上游亦标 `@BROKEN`。openssl/mbedtls 双后端正常产出, 覆盖了实际需求。
2. **softethervpn 的 `Secure.c:532`**: OpenSSL 3.5 的 const 限定符差异, 仅在
   Windows 路径触发, Linux 不编译该分支 (已本地 `-fsyntax-only` 实证)。

若日后需要 wolfssl 后端或 Windows 目标, 需上游先修对应源码。

---

## 八. run 38918400689 的三个根因与修复 (HEAD 3c7ce50)

run `38918400689` (HEAD `1220c53`) 把这批问题推到了新阶段: **6 个 job 已经真正
编译成功并产出 .apk**, 但全部卡在 Verify 步骤。排查后确认是三个彼此独立的根因,
A 掩盖了 B/C 的成果。

| Job | 编译 | 产物 | 卡在哪 |
|---|---|---|---|
| libreswan | ✅ | `libreswan-4.15-r1.apk` | Verify (根因 A) |
| openvpn-openssl | ✅ | `openvpn-openssl-2.7.8-r1.apk` | Verify (A) |
| openvpn-mbedtls | ✅ | `openvpn-mbedtls-2.7.8-r1.apk` | Verify (A) |
| openvpn-easy-rsa | ✅ | `openvpn-easy-rsa-3.2.0-r1.apk` | Verify (A) |
| softethervpn5 | ✅ | 4 个 .apk | Verify (A) |
| openvpn-wolfssl | ✅ | 无 (`@BROKEN` 未选中) | Collect (空) |
| strongswan-default | ❌ | — | Compile (根因 B) |
| softethervpn | ❌ | — | Compile (根因 C) |

### 根因 A — verify 脚本按 v2 格式读取 ADB v3 包 (#21)

脚本假定 `apk extract` 之后根目录存在 `.PKGINFO`。**apk-tools v3 (ADB) 根本不写
这个文件** —— 它只存在于 v2/opkg 的 tar 格式里 (apk-tools `src/extract_v2.c:303`),
`src/extract_v3.c` 只写 payload 树。所以 6 个编译成功的包在元数据解析阶段就失败。

修复:
- 元数据改从 `apk adbdump` 的 ADB `info` 对象读取 (新增 `adb_info()`)。
- file list / conffiles 改从 payload 里的
  `lib/apk/packages/<pkg>.list` / `.conffiles_static` 读取 —— 这些是 OpenWrt
  `include/package-pack.mk:562` 打包时写入的真实清单。
- 清单名匹配按包名前缀, 允许数字 ABI 后缀 (`include/feeds.mk:70` FormatABISuffix),
  **不再**盲目取目录里第一个 `*.list` —— 那会校验到别的包的文件列表, 掩盖真实
  mismatch。

顺带修掉被 A 掩盖的两处原有缺陷:
- init 脚本扫描把 `find` 返回的**绝对**路径又拼了一次 `${root}`, 得到双倍路径;
- 包名 fragment 推导只做了一次 `${base%-*}`, 对 `libgcc1-14.3.0-r5` 得到
  `libgcc1-14.3.0`, 永远无法匹配 → 改为先剥 `-r<release>` 再剥 `-<version>`;
- UCI 正则原先只接受带引号的 section 名, 真实 OpenWrt 用 `config dropbear main`
  (不带引号)。

### 根因 B — `BUILD_VARIANT` 泄漏污染所有依赖包 (#22)

CI 用 `make ... BUILD_VARIANT=<variant>` 选后端, 看着自然, 但
`include/subdir.mk:75` 把它当**全局覆盖**:

```
$(foreach variant,$(filter-out *,$(if $(BUILD_VARIANT),$(BUILD_VARIANT), ...)))
```

它在遍历**每个**目录时套用, 且 `subdir_make_opts` 以 `BUILD_VARIANT="$(4)"`
递归传给每个子 make。又因为 `package.mk:11` 用它拼构建目录:

```
PKG_BUILD_DIR ?= $(BUILD_DIR)/$(if $(BUILD_VARIANT),$(PKG_NAME)-$(BUILD_VARIANT)/)...
```

于是**依赖包**全被带上后缀: `iproute2-default`、`openssl-default`、
`toolchain-default`。iproute2 只认 `iptiny/ipfull/tctiny/tcbpf/tcfull`, 拿到
`default` 后 `LIBBPF_FORCE` 为空, configure 直接打 usage 并 exit 1:

```
--libbpf_force=      ->  Usage: ./configure [OPTIONS]
ERROR: package/feeds/base/iproute2 failed to build (build variant: default).
```

正确机制是**按目录**: `scripts/package-metadata.pl` 从各包的 `VARIANT:=` 元数据
生成 `$(curdir)/<path>/variants`, subdir.mk 只遍历这些。所以编译整个目录会以各自
构建目录产出全部**已选中**变体 —— 这正是 openvpn 3 个后端能在一个 job 里出的原因,
softethervpn/softethervpn5 本来就是这个形态。

修复: 删掉命令行的 `BUILD_VARIANT=`, 矩阵由 8 job 收敛为 6 job (openvpn 合一),
并移除已无用的 `variant:` 键 —— strongswan 的那个本来就是错的, 该 Makefile 并未
声明任何 `VARIANT`。

### 根因 C — softethervpn 缺 GCC14 补丁, 且 kmod 依赖名陈旧

- 上游 openwrt/packages 有 `100-gcc14.patch`, 修 `CK_ULONG` /
  `CK_SESSION_HANDLE_PTR` 指针类型 (GCC 14 把不兼容指针类型升为 error)。我们仓库
  缺该补丁。已原样加入 (`net/softethervpn/patches/100-gcc14.patch`, 与上游 25.12
  逐字节一致)。
  本地对照实验 (`cc -fsyntax-only -Werror=incompatible-pointer-types`):
  仅原有 4 补丁 → 13 处报错 (行号与 CI 日志逐一吻合); 加上该补丁 → 1 处, 且
  剩下的 `Secure.c:532` 是 OpenSSL 3.5 const 限定符差异, **Linux 不触发**。
- 补丁文件保留了原本的 CRLF/LF 混合行尾 —— 这是**必要的**: 上游源码是 CRLF, 若把
  补丁整成纯 LF, `patch` 会因上下文不匹配而全部 hunk 失败 (已实测)。
- `net/openvpn/Makefile` 依赖 `kmod-ovpn-dco-v2` 已不存在; 25.12 feed 里
  `kernel/ovpn-dco` 的 `KernelPackage/ovpn-backports` 才是真名
  (`kmod-ovpn-backports`)。`dep-audit.sh` 里改名方向也写反了, 一并纠正。

### 附带修复 — Collect 步骤把 ~160 个无关包拖进验证

原 glob `bin/packages/*/*/*.apk` 也匹配到 base feed, 于是固件 blob、libopenssl3、
libnl* 全被拷进 artifact 并喂给 verify-pkg.sh, 真实失败被噪声淹没。现限定为本 feed。

### 本地实证 (无 Docker)

- 本地编译出与 CI 同版本的真实 `apk` 二进制 (apk-tools 3.0.5, `--version` 一致)。
- `verify-pkg.sh` 对**真实** OpenWrt ADB 包端到端通过 (dropbear 带
  conffiles+init.d+UCI; libgcc1 纯库), 且对文件名与包名不符的产物**如实失败**。
- 5 个静态检查脚本全部 rc=0; ci.yml/release.yml YAML 解析通过。

---

## 九. 从 A/B/C 到全绿: 四项后续问题 (HEAD 551e78e)

第八节之后又跑了 6 轮 CI。每轮都只暴露出**下一层**问题: 先是补掉最后一个编译
问题 (strongswan 版本), 之后全是**验证侧**的缺陷 —— 从 run `39008990370` 起
6 个包已全部编译成功, 剩下的红都出在 Verify 与 Stage 3 上, 而非包本身。

| run | HEAD | 结果 | 暴露的问题 |
|---|---|---|---|
| 38992578693 | `3c7ce50` | 4/6 build 绿; openvpn、strongswan 红 | openvpn 是 wolfssl 变体编不过; strongswan 版本与补丁集不匹配 |
| 39005336167 | `cb2e128` | 5/6 build 绿; openvpn、strongswan 红 | strongswan 同版本问题; openvpn 编译已过, 卡在 Verify 的 UCI 检查 |
| 39007018435 | `daabb1b` | **5/6 build job 绿** | Verify 判 metapackage 非法 |
| 39008990370 | `2f51d5f` | **6/6 build 绿**, Stage 3 全红 | Stage 3 的 apk 跑不起来 |
| 39011100454 | `285f4a2` | 6/6 build 绿, Stage 3 自检即失败 | 只补了 loader, 漏了 `.apk.bin` |
| **39012977431** | **`551e78e`** | **全绿** | — |

### 问题一 — strongswan 版本与补丁集不匹配 (cb2e128)

`PKG_VERSION:=6.1.0`, 但补丁集 (`0903/0904/0905`) 与上游 25.12 **逐字节一致**,
而上游对应的是 **6.0.7**。本地实测:

- 6.0.7 → 0903/0904/0905 全部干净应用;
- 6.1.0 → 0904、0905 均 `Hunk FAILED`。

已回退 6.0.7, `PKG_HASH:=e518e34e159514f4c6ba80d1f926cb151e0dd4e3a1d94213171234b8b9ae6f55`
(已下载校验一致)。同轮撤掉 `CONFIG_BROKEN=y`、不再选中 wolfssl (理由见第五节)。

### 问题一之附 — openvpn 两个变体的失败其实是两件不同的事

这两轮里 openvpn 都红了, 但原因不同, 且都不是 openvpn 源码本身的问题:

- run `38992578693`: 失败在 **wolfssl 变体**
  (`package/feeds/oppackages/openvpn failed to build (build variant: wolfssl)`),
  即 `ssl_openssl.c:321` 的 `X509_STORE_CTX_set0_crls` wolfSSL 头未提供。由
  `cb2e128` 不再选中该变体解决。
- run `39005336167`: 编译**已经通过** (build-log 末尾是
  `make[1]: Leaving directory ...`, 无 Error), 卡在 Verify:

  ```
  ✓ conffiles: 2 declared and present
  ✓ init scripts: 1 parse as shell
  ✗ openvpn-mbedtls-2.7.8-r1.apk: malformed UCI config /etc/config/openvpn
  ```

  这是**脚本**过于严格 —— 真实 `/etc/config/openvpn` 使用 `package openvpn` 行与
  tab 缩进, 而正则只认带引号的 section 名。由 `daabb1b` 修复。

### 问题二 — verify 脚本对 metapackage 判错 (2f51d5f)

strongswan 的 `-default/-full/-isakmp/-minimal` 是**纯依赖包**,
`net/strongswan/Makefile:501-515` 的 install 体就是 `true`。OpenWrt 仍会为它们
产出**正常**的 .apk, 所以"文件列表非空"是它们永远无法满足的要求 —— 是检查错了,
不是包错了。

改为结合**解包后的实际内容**判定, 而非只看清单:

| 文件列表 | 实际负载文件 | 判定 |
|---|---|---|
| 非空 | — | ok (正常包) |
| 空 | 0 | ok, 标注 `metapackage: no payload (dependency-only)` |
| 空 | >0 | **fail** (`empty file list but N payload path(s) unpacked`) |

第三行是关键: 真正**丢失了内容**的包仍会失败, 不会被放过。计数只统计
`/lib/apk/packages/` 之外的正规文件 —— 空 metapackage 仍带有 `lib/`、`lib/apk/`、
`lib/apk/packages/` 三层目录, 它们不算负载。

三个方向均本地实证 (apk 3.0.5):

- 空列表 + 无负载 → 通过;
- 有负载文件 + 空列表 → **失败, exit 1**;
- CI 真实产物 `libreswan-4.15-r1.apk` → 仍通过。

> 关于 `.list` 是否存在的取证: `include/package-pack.mk:562` 用
> `find ... > $(TMP_DIR)/$(1).list && mv` **无条件**写入, 因此真实 metapackage
> 必然带一个 `.list` (内容可能为空)。据此没有放宽"清单必须存在", 只放宽了
> "清单必须非空"。

### 问题三 — Stage 3 的宿主 apk 无法运行 (285f4a2 + 551e78e)

run `39008990370` 里 6 个 build job 全绿, 但 Stage 3 把 **103 个产物全部**判为
`apk verify failed`。真实原因藏在下一行:

```
.../staging_dir/host/bin/apk: line 5:
.../staging_dir/host/lib/ld-linux-x86-64.so.2: No such file or directory
```

Stage 3 为省时间对 SDK tar 做**部分提取**, 只取了
`--wildcards '*/staging_dir/host/bin/apk'`。但那个文件是 **wrapper 脚本**, 不是程序本身:

1. 它从同级 `../lib/` 里 exec 自己的 loader;
2. 它再 exec 真正的二进制 —— 存成**点开头**的 `.apk.bin`。

所以需要三样东西 (wrapper + loader + `.apk.bin`), 只取 wrapper 必然失败。
build job 不受影响, 因为它们解压**完整** SDK —— 这解释了"同一份脚本、同一批包,
一个 job 绿一个 job 红"。

两次尝试:

- `285f4a2` 补了 `staging_dir/host/lib/*` → 自检立刻报 `host apk is not runnable`,
  日志揭示还缺 `.apk.bin`;
- `551e78e` 改为按**目录成员**提取整个 `bin/` 与 `lib/`, 并显式断言 `.apk.bin`
  存在。用 `bin/apk*` 这种文件名通配是不行的: **通配符匹配不到点开头的文件**。

该行为已用 GNU tar 在本地合成包上复现:

| 提取模式 | 实际得到 |
|---|---|
| `'*/staging_dir/host/bin/apk*'` | 仅 `apk` (漏 `.apk.bin`) |
| `'*/staging_dir/host/bin/'` `'*/staging_dir/host/lib/'` | `apk`、`.apk.bin`、loader 全部 |

顺带加了一道**一次性自检**: 提取完立即跑 `apk --version`, 失败就带明确信息退出,
而不是把工具链故障摊成 103 条误导性的"包验证失败"。
run `39011100454` 证明了这道自检的价值 —— 它把同样的故障从 103 条噪声收敛成 1 行 `FATAL`。

### 结果

run `39012977431` (HEAD `551e78e`):

```
1. Static checks        success
2. Build libreswan      success      2. Build strongswan     success
2. Build openvpn        success      2. Build softethervpn   success
2. Build openvpn-easy-rsa success    2. Build softethervpn5  success
3. Verify .apk          success      5. CI summary           success
```

Stage 3 实测: `apk-tools 3.0.5, compiled for x86_64` → `count: 103` →
`OK: all 103 package artifact(s) passed functional verification` (829 项检查通过)。

