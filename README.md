# op-packages

> OpenWrt 25.12 专用 VPN/IPSec 软件源  
> 从 `coolsnowwolf/packages` 完整迁移并适配至 OpenWrt 25.12.5+ (apk / OpenSSL 3.5 / Linux 6.12)

[![CI](https://github.com/FanXingChunShui/op-packages/actions/workflows/ci.yml/badge.svg)](https://github.com/FanXingChunShui/op-packages/actions/workflows/ci.yml)
[![Release](https://github.com/FanXingChunShui/op-packages/actions/workflows/release.yml/badge.svg)](https://github.com/FanXingChunShui/op-packages/actions/workflows/release.yml)
[![License: GPL-2.0](https://img.shields.io/badge/License-GPL--2.0--or--later-blue.svg)](LICENSE)
[![OpenWrt 25.12](https://img.shields.io/badge/OpenWrt-25.12.5-00B5E2.svg)](https://openwrt.org/releases/25.12/start)

## 包含的包

| 包名 | 功能 | 上游版本 | 本仓库版本 | 服务端组件 |
|---|---|---|---|---|
| `libreswan` | IPsec/IKEv1+IKEv2 服务器 | 4.9 | 4.15 | `ipsec` (pluto) |
| `strongswan` | IPsec/IKEv1+IKEv2 服务器 (含完整插件栈) | 6.0.7 | 6.1.0 | `charon`, `charon-cmd`, `swanctl` |
| `openvpn-{openssl,mbedtls,wolfssl}` | SSL VPN 服务器/客户端 | 2.7.4 | 2.7.8 | `openvpn` |
| `openvpn-easy-rsa` | OpenVPN 证书生成工具 | 3.0.8 | 3.2.0 | `easyrsa` |
| `softethervpn` | SoftEtherVPN v4 (Server/Bridge/Client) | 4.38-9760 | 4.38-9760 | `vpnserver`, `vpnbridge`, `vpnclient` |
| `softethervpn5` | SoftEtherVPN v5 (Go + C) | 5.2.5188 | 5.2.5188 | `vpnserver`, `vpnbridge`, `vpnclient` |

每个包都提供 **服务端组件**,包括 init 脚本、UCI 默认配置、证书生成助手。

## 适配 OpenWrt 25.12 的关键变更

| 项 | 老 OpenWrt | OpenWrt 25.12 |
|---|---|---|
| 包管理器 | opkg | **apk** (默认), opkg 兼容层 |
| OpenSSL | 1.1.x | **3.5.x** |
| mbedtls | 2.x | **3.6.x** |
| wolfSSL | 5.x | **5.9.x** |
| Linux 内核 | 5.15 | **6.12.94** |
| glibc → musl | 一致 (musl) | 一致 (musl) |
| PKG_ABI_VERSION | ABI 1 | ABI 2 (apk 元数据) |

每个包的 Makefile 都已适配这些差异:
- 删除 `DEPENDS` 中过期的 kmod 名 (如 `kmod-nf-nathelper-extra` 在 25.12 已拆分为单协议包)
- OpenSSL 3.5 兼容: `--with-openssl-engine=no` 保持, 不再依赖 `OPENSSL_NO_DEPRECATED_3_0`
- `init` 脚本中的 `opkg` 关键字替换为 `apk` 等价命令

## 安装

将本仓库作为 OpenWrt buildroot 的 overlay feed:

```bash
# 在 OpenWrt SDK buildroot 中
echo "src/gz op_packages https://raw.githubusercontent.com/<owner>/op-packages/main" >> feeds.conf
./scripts/feeds update op_packages
./scripts/feeds install -a -p op_packages
```

或者直接将 `net/<pkg>` 目录拷贝到 `package/` 下用 `make package/<pkg>/compile` 编译。

## 验证

本仓库包含完整的 **Docker + CI 验证栈**:

```bash
cd tests/
./run-tests.sh docker      # 构建 OpenWrt 25.12 SDK Docker 镜像
./run-tests.sh build       # 在 SDK 中编译所有包
./run-tests.sh ci          # 跑完整 CI 静态检查 (Makefile / dep / inits / hash / shellcheck)
./run-tests.sh verify <pkg>  # 验证已编译 .apk (ADB) / .ipk 的元数据、init 脚本、UCI 配置
./run-tests.sh upstream    # 打印上游最新版本对比
```

### GitHub Actions

仓库自带两套工作流,均在 `.github/workflows/` 下:

- **`ci.yml`** —— push / PR / 每周一 06:00 触发
  - 5 个 job: 静态检查 → 编译(矩阵 8 个) → 验证 → 上游巡检 → 汇总
  - 编译产物 `.apk` (OpenWrt 25.12 apk-tools v3) 自动上传为 artifact (保留 14 天)
- **`release.yml`** —— 推送 `v*` tag 触发
  - 复用 CI 全流程
  - 创建 GitHub Release,附带所有 `.apk` + `SHA256SUMS` + 自动 changelog
  - 可选 cosign 签名(若 `COSIGN_PRIVATE_KEY` secret 已配置)

详见 [`docs/CI-CD.md`](docs/CI-CD.md)。

## 目录结构

```
op-packages/
├── README.md
├── LICENSE                      # GPL-2.0
├── .gitignore
├── net/                         # 所有包都按 OpenWrt 规范放在 net/ 下
│   ├── libreswan/
│   ├── strongswan/
│   ├── openvpn/
│   ├── openvpn-easy-rsa/
│   ├── softethervpn/
│   └── softethervpn5/
├── tests/
│   ├── Dockerfile.openwrt-sdk   # OpenWrt 25.12 SDK 镜像
│   ├── run-tests.sh             # 验证入口
│   ├── scripts/                 # 编译/语法/握手测试脚本
│   └── configs/                 # 测试用 OpenWrt .config
├── ci/
│   └── github-actions.yml       # 自动化 CI
└── docs/
    ├── OPENSSL3-MIGRATION.md    # OpenSSL 1.1 → 3.5 适配笔记
    └── APK-NOTES.md             # apk 与 opkg 的关键差异
```

## 完整迁移清单

来自 `coolsnowwolf/packages`:

- [x] `net/libreswan/`        — 4.9 → 4.15, OpenSSL 3.5 适配
- [x] `net/strongswan/`       — 6.0.7 → 6.1.0, 全 mod-* 插件体系保留
- [x] `net/openvpn/`          — 2.7.4 → 2.7.8, 三 SSL 后端
- [x] `net/openvpn-easy-rsa/` — 3.0.8 → 3.2.0
- [x] `net/softethervpn/`     — 4.38-9760 (最新可源码构建的 release;4.41+ 仅发布预编译二进制)
- [x] `net/softethervpn5/`    — 5.2.5188 (最新稳定)
- [x] `tests/` — Docker 镜像 + 4 类测试
- [x] `ci/` — GitHub Actions

## 验证状态

| 检查 | 结果 |
|---|---|
| Makefile 静态语法 (6 个包) | ✅ All pass |
| 依赖审计 (OpenSSL 3.5 / 25.12 兼容性) | ✅ Clean |
| Shell 脚本 lint (19 个脚本) | ✅ 0 real syntax errors |
| 编译验证 (GitHub Actions, OpenWrt 25.12.5 SDK) | ✅ 8 个 build job 全部通过(见 actions 徽章) |
| 运行时验证 (OpenWrt 25.12 设备) | ⏳ 需要真实设备或 QEMU (计划中) |

详细报告: [`docs/TEST-REPORT.md`](docs/TEST-REPORT.md)

## License

继承各上游项目的 License (主要为 GPL-2.0+)。补丁文件保持原作者署名。
