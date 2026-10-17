# CI/CD 流水线

op-packages 仓库自带两套 GitHub Actions 工作流,提供 **静态检查 → 编译 → 功能验证 → Release** 的完整链路。
目标平台固定为 **OpenWrt 25.12.5 (apk-tools v3 / `.apk`)**,不维护旧 OpenWrt / opkg 兼容。

## 工作流概览

```
                    push / PR / schedule / workflow_call
                            │
                ┌───────────┴───────────┐
                ▼                       ▼
        ┌──────────────┐         ┌──────────────┐
        │   ci.yml     │         │ release.yml  │
        │              │         │ (tag 触发)   │
        └──────┬───────┘         └──────┬───────┘
               │                        │
        ┌──────┴──────────────┐         │
        ▼                     ▼         ▼
  1. static-checks   2. build (8)    复用 ci.yml
  3. verify (全部)                ↓
  4. upstream-watch      release job
  5. summary             ↓
                       GitHub Release
                       + .apk assets
```

## 1. ci.yml — 持续集成

**触发条件**
- `push` 到 `main` / `master`
- `pull_request` 到 `main` / `master`
- 每周一 06:00 UTC 定时
- 手动触发 (`workflow_dispatch`)
- 被 `release.yml` 以 `workflow_call` 复用

**Job 1: static-checks** (~10 秒)
| 检查 | 工具 | 阻塞? |
|---|---|---|
| Makefile 静态语法 | 自研 (`makefile-syntax.sh`) | ✅ |
| 依赖审计 (OpenSSL 3.5 / 25.12 兼容) | 自研 (`dep-audit.sh`) | ✅ |
| Init 脚本语义 (procd / UCI) | 自研 (`validate-inits.sh`) | ✅ |
| PKG_HASH 校验 | 自研 (`hash-check.sh`) | ✅ (main/master 严格) |
| Shell lint | shellcheck | ✅ |

**Job 2: build** (~15-40 分钟,矩阵 6 个 = 6 个包目录)
> 每个 job = 一个 **包目录**。`softethervpn` / `softethervpn5` 一个源码树产出 4 个 `.apk`
> (base/libs + server + bridge + client),`openvpn` 一个源码树产出 3 个 SSL 后端
> (`openssl` / `mbedtls`),因此它们各只构建一次,产物全部收集。

| 目录 | 产出的 .apk |
|---|---|
| `libreswan` | `libreswan` |
| `strongswan` | `strongswan-default` + `strongswan-mod-*` |
| `openvpn` | `openvpn-openssl` + `openvpn-mbedtls` |
| `openvpn-easy-rsa` | `openvpn-easy-rsa` |
| `softethervpn` | `softethervpn-{base,server,bridge,client}` |
| `softethervpn5` | `softethervpn5-{libs,server,bridge,client}` |

> `openvpn-wolfssl` 不在其中: 它的 `@BROKEN` 是准确的 —— wolfSSL 后端对
> OpenVPN 2.7.8 编译不过, 因为该变体仍会编译 `ssl_openssl.c`, 而其中
> `X509_STORE_CTX_set0_crls()` 在 wolfSSL 的兼容头里不存在
> (`ssl_openssl.c:321: implicit declaration of function`)。
> 选中它会让整个 openvpn 目录编译失败, 连带丢掉 openssl/mbedtls 的产物。

> ⚠️ **不要在 `make` 命令行上传 `BUILD_VARIANT=`**。它看似是选变体的正确方式,但
> `include/subdir.mk:75` 把它当作**全局覆盖**处理,遍历每个目录时都会套用,并经
> `subdir_make_opts` 以 `BUILD_VARIANT="$(4)"` 递归传给子 make。由于
> `package.mk:11` 用它拼构建目录 (`$(BUILD_DIR)/$(if $(BUILD_VARIANT),$(PKG_NAME)-$(BUILD_VARIANT)/)...`),
> **所有依赖包**都会被带上该后缀,例如 `iproute2-default`、`openssl-openssl`。iproute2 只认
> `iptiny/ipfull/tctiny/tcbpf/tcfull`,拿到 `default` 后 `LIBBPF_FORCE` 为空,configure 直接
> 打印 usage 并 `exit 1`:
> `--libbpf_force=` → `Usage: ./configure [OPTIONS]` → `ERROR: package/feeds/base/iproute2 failed to build (build variant: default).`
>
> 正确机制是**按目录**:`scripts/package-metadata.pl` 会从各包的 `VARIANT:=` 元数据生成
> `$(curdir)/<path>/variants`,subdir.mk 只遍历这些。因此编译整个目录会以各自的构建目录
> 构建全部**已选中**的变体。

每个 build job 的步骤:
1. 安装构建依赖 (Ubuntu 24.04 原生,无 Docker)
2. 用 `actions/cache@v4` 缓存官方 SDK tarball
3. 解压 SDK:
   `https://downloads.openwrt.org/releases/25.12.5/targets/x86/64/openwrt-sdk-25.12.5-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst`
4. **接线 feeds** (顺序关键,三点陷阱):
   - **base feed 必须先 `update -a` + `install -a`**,否则 SDK 的 `package/` 几乎是空的,
     所有 `DEPENDS` (libopenssl / libreadline / ...) 解析失败
   - **`feeds install <feedname>` 只认包名**,对 feed 名会打印
     `WARNING: No feed for package 'oppackages' found` 且什么都不装 —— 必须用
     `./scripts/feeds install -a -p oppackages`
   - **openwrt/packages 自带这 6 个上游包**,`feeds install -a` 会装上游代码而不是我们的;
     先把 `feeds/packages/net/{libreswan,strongswan,openvpn,openvpn-easy-rsa,softethervpn,softethervpn5}`
     删掉并 `feeds update -i packages` 重索引
5. `make defconfig` (种子配置在 `tests/configs/sdk-minimal.config`)
6. `make package/feeds/oppackages/<dir>/compile BUILD_VARIANT=... DEVELOPER=1`
7. 收集 `bin/packages/.../*.apk` 到 `tests/artifacts/apk/`
8. 用 **SDK 自带的 `staging_dir/host/bin/apk`** 现场验证 (ADB 容器完整性 +
   元数据 + 文件清单 + conffiles + init 语法 + 路径安全)
9. 上传 `.apk` artifact (`pkg-<dir>`,保留 14 天)

**Job 3: verify** (全部产物,1 个 job)
- 下载所有 `pkg-*` artifact 合并到 `dist/`
- 从缓存的 SDK tarball 里只取出 `staging_dir/host/bin/apk`
- `tests/scripts/verify-pkg.sh` 对每个 `.apk` 做:
  - `apk verify --allow-untrusted` (ADB 容器完整性)
  - `apk adbdump` 结构转储
  - `apk extract` 解包后检查 `.PKGINFO` 元数据、文件清单、conffiles、
    init 脚本语法、路径安全、UCI 结构

**Job 4: upstream-watch** (每周)
- 调用 `upstream-check.sh` 比较 PKG_VERSION 与上游最新,输出留痕

**Job 5: summary** — 汇总所有 job 结果,失败打 `::warning::`

## 2. release.yml — 发布自动化

**触发条件**:推送 tag `v*` (如 `v1.0.0`, `v0.3-rc1`) 或手动触发

**流程**
1. `uses: ./.github/workflows/ci.yml` — 复用同一套 build+verify
2. 收集所有 `pkg-*` artifact 到 `dist/apk/`
3. 生成 `SHA256SUMS`
4. `git log` 自动 changelog
5. `softprops/action-gh-release` 创建 Release
   - assets: 所有 `.apk` + `SHA256SUMS`
   - 预发布: tag 含 `-rc` / `-beta`

## 本地复现 CI 行为

```bash
# 1. 静态检查(无需 SDK,5-15 秒)
./tests/run-tests.sh ci

# 2. 完整编译(需要 SDK tarball + 构建依赖,在 SDK buildroot 内)
#    下载并解压 SDK 后:
#    cp tests/configs/sdk-minimal.config .config && make defconfig
#    make package/feeds/oppackages/<dir>/compile DEVELOPER=1

# 3. 验证已编译的 .apk
ls tests/artifacts/apk/
./tests/run-tests.sh verify openvpn-openssl
```

## 故障排查

| 错误 | 原因 | 修复 |
|---|---|---|
| `No rule to make target 'package/feeds/oppackages/<dir>/compile'` | `feeds install <feedname>` 只认包名,feed 没装上 | 用 `./scripts/feeds install -a -p oppackages`,确认 `package/feeds/oppackages/` 存在 |
| `WARNING: No feed for package 'oppackages' found` | 同上 | 同上 |
| `LIB_READLINE-NOTFOUND` / `libopenssl does not exist` | SDK `package/` 为空,base feed 未安装 | 先 `./scripts/feeds update -a && ./scripts/feeds install -a` |
| 编译的是上游代码而不是我们的 | openwrt/packages 自带同名包,`feeds install -a` 优先装了上游 | 删 `feeds/packages/net/<pkg>` 再 `feeds update -i packages` |
| `recursive dependency detected` (nginx/asterisk/qemu/gensio/mutt/rsyslog) | openwrt/packages 上游既有问题,与本仓库无关 | 已在上游,CI 只做统计不当作失败 |
| `.apk` 无法用 tar/unzip 解包 | 25.12 的 `.apk` 是 apk-tools v3 "ADB" 二进制格式 | 用 SDK 的 `staging_dir/host/bin/apk` (verify-pkg.sh 自动寻找) |
| `PKG_HASH is still 'skip'` | release 前未补 hash | `make package/<pkg>/download` 生成 |

## 工作流版本

| 文件 | 修改日期 |
|---|---|
| `.github/workflows/ci.yml` | 2026-10-16 |
| `.github/workflows/release.yml` | 2026-10-16 |
| `tests/scripts/verify-pkg.sh` | 2026-10-16 |
| `tests/scripts/verify-ipk.sh` | 2026-10-16 (deprecated 委托给 verify-pkg.sh) |
| `tests/scripts/validate-inits.sh` | 2026-10-15 |
| `tests/scripts/hash-check.sh` | 2026-10-15 |
