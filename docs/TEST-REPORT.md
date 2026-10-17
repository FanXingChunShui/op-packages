# 测试报告 / Test Report

> 仓库: `op-packages`
> 源仓库: `coolsnowwolf/packages`
> 目标 OpenWrt: **25.12.5** (2026-07-01 发布)
> 验证时间: 2026-10-15

## 已完成验证

| 项 | 命令 | 结果 |
|---|---|---|
| Makefile 静态语法 | `./tests/scripts/makefile-syntax.sh` | ✅ 6/6 通过 |
| 依赖审计 (OpenSSL 3.5 / 25.12 兼容性) | `./tests/scripts/dep-audit.sh` | ✅ Clean,无废弃 kmod/符号 |
| Shell 脚本 lint | `./tests/scripts/shellcheck-all.sh` | ✅ 19/19,0 真实语法错误 |

### Makefile 静态语法

```
checking net/strongswan/Makefile
checking net/softethervpn5/Makefile
checking net/openvpn-easy-rsa/Makefile
checking net/openvpn/Makefile
checking net/libreswan/Makefile
checking net/softethervpn/Makefile

All Makefiles pass static checks.
```

每个 Makefile 都满足:
- 必需的 `PKG_NAME` / `PKG_VERSION` / `PKG_RELEASE` 都已定义
- 无尾随空格
- 至少一个 `$(eval $(call BuildPackage,...))` 或 `BuildPlugin`
- 引用的 `.patch` 文件全部存在于 `patches/` 目录

### 依赖审计

```
Dependency audit: clean. No deprecated references found.
```

已审计以下已知与 OpenWrt 25.12 不兼容的项:
- `kmod-nf-nathelper-extra` (已拆分为单协议模块)
- `kmod-ovpn-backports` (已重命名为 `kmod-ovpn-dco-v2`,OpenWrt 25.12 内置 ovpn-dco)
- `kmod-ipsec-transforms` (已废弃)
- OpenSSL 3.5 已移除的 API: `EVP_CIPHER_CTX_init`, `RAND_pseudo_bytes`, `FIPS_mode`, `HMAC_CTX_new`(legacy only), `EC_KEY_new_by_curve_name`(legacy only)

仓库中无任何包引用这些已废弃项。

### Shell 脚本 lint

```
shellcheck summary
  scripts scanned     : 19
  scripts clean       : 5
  scripts with advisory (OpenWrt-pattern warnings): 14
  scripts with real syntax errors : 0
```

14 个 advisory 是 OpenWrt init 脚本的常见模式(已白名单,不影响功能):
- `START`/`STOP`/`USE_PROCD` 是由 `/etc/rc.common` 读取 (SC2034)
- `local` 在 OpenWrt 的 ash 中可用 (SC3043)
- uci helper 的内部赋值 shellcheck 无法追踪 (SC2154/SC2155)
- `. file "$arg"` 是 ash 扩展 (SC2240)

## 手动验证 (需要在 OpenWrt 25.12 设备上)

下列操作 **需要在真实 OpenWrt 25.12 设备或 QEMU 镜像** 上执行,本仓库不包含设备模拟器。

### 1. 编译验证 (Docker)

```bash
cd /path/to/op-packages
./tests/run-tests.sh docker       # 首次构建 SDK 镜像 (~5-10 min)
docker run --rm -v "$(pwd):/src" op-packages-sdk \
    bash -c 'cd /src && ./tests/scripts/build-all.sh'
```

预期输出: 13 个包全部编译成功,生成 13+ 个 `.ipk` 文件。

### 2. 运行时验证

在 OpenWrt 25.12.5 x86_64 设备上:

```bash
# 安装
apk update
apk add strongswan-default strongswan-mod-openssl \
       openvpn-openssl openvpn-easy-rsa

# 启动 IPsec 服务端 (IKEv2 PSK)
uci set ipsec.@ipsec[0].enabled=1
uci set ipsec.@tunnel[0]="tunnel"
uci set ipsec.@tunnel[0].local_subnet="10.0.0.0/24"
uci set ipsec.@tunnel[0].remote_subnet="10.0.1.0/24"
uci commit ipsec
/etc/init.d/swanctl enable
/etc/init.d/swanctl start

# 启动 OpenVPN 服务端
/etc/init.d/openvpn enable
/etc/init.d/openvpn start

# 检查
swanctl --list-sas         # 应输出已建立的 SA
openvpn --version          # 应输出 OpenVPN 2.7.8
strongswan --version       # 应输出 strongSwan 6.1.0
ipsec --version            # 应输出 Libreswan 4.15
```

### 3. 端到端握手 (QEMU,可选)

需要 2 个 QEMU VM,分别跑 strongswan 和 openvpn 服务端。
详见 `tests/README.md` 中的 "端到端握手测试" 一节。

## 已知遗留事项

| 项 | 说明 | 后续行动 |
|---|---|---|
| `PKG_HASH := skip` | 6 个包都标记为 `skip`,需要在首次 release 前用 `make package/<pkg>/download` 重新生成 | release 前 |
| mbedtls 运行时版本检查补丁 | 在 OpenVPN 2.7.8 + mbedtls 3.6 可能不再需要,但保留作为 fallback | 编译失败时移除 |
| 强天鹅 0903 hotplug 补丁 | 检查是否仍需在 25.12 上 (Linux 6.12 netlink 接口可能已变) | 编译失败时调整 |
| SoftEther v4 4.42-9787 | 在 25.12 上首次编译时需要确认 musl libc 兼容性 | 编译失败时降级到 4.42 |
| LibreSwan 5.x | 未升级到主线 5.x,因 4.15 已是 4.x 末班车且 API 稳定 | 后续可升级到 5.3.2 |

## 验证脚本

仓库根目录下:

```bash
./tests/run-tests.sh all       # 跑全部静态检查
./tests/run-tests.sh build     # Docker 编译 (需要 Docker)
./tests/run-tests.sh docker    # 构建 SDK 镜像
```

详细说明见 [`tests/README.md`](../tests/README.md)。
