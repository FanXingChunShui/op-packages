# tests/

OpenWrt 25.12 验证栈。所有脚本假设仓库根目录 (`..`) 包含 `net/` 目录。

## 快速开始 (Docker)

```bash
# 1. 构建 SDK Docker 镜像 (首次 ~ 5-10 分钟,之后秒级)
./tests/run-tests.sh docker

# 2. 编译所有包 (~ 15-30 分钟首次构建)
docker run --rm -v "$(pwd):/src" op-packages-sdk \
    bash -c 'cd /src && ./tests/scripts/build-all.sh'

# 3. 只跑静态检查 (秒级,不需要 Docker)
./tests/run-tests.sh all-static
```

## 脚本一览

| 脚本 | 用途 | 需要 Docker | 时间 |
|---|---|---|---|
| `run-tests.sh docker` | 构建 SDK 镜像 | 是 | 5-10 min |
| `run-tests.sh build` | 编译所有包 | 是 | 15-30 min |
| `run-tests.sh shellcheck` | lint 所有 init 脚本 | 否 | 几秒 |
| `run-tests.sh syntax` | Makefile 静态检查 | 否 | 几秒 |
| `run-tests.sh deps` | OpenSSL 3.5 / 25.12 兼容性审计 | 否 | 几秒 |
| `run-tests.sh all` | 全部静态检查 + 编译 | 是 | 20-40 min |

## 本地 SDK 使用 (无 Docker)

如果你已有 OpenWrt 25.12 SDK 提取到某处:

```bash
export OPENWRT_SDK=/path/to/openwrt-sdk-25.12.5-x86-64
./tests/run-tests.sh build
```

## 测试产物

所有日志写到 `tests/artifacts/`:

```
tests/artifacts/
├── feeds-update.log
├── libreswan-build.log
├── strongswan-default-build.log
├── openvpn-openssl-build.log
├── ...
└── <pkg>-build.log
```

CI 会自动上传失败包的日志作为 artifact。

## 端到端握手测试 (可选,需要 QEMU)

`scripts/qemu/` 下有 (TODO) 一对 QEMU 启动脚本,
分别跑 `strongswan` 服务端和 `openvpn` 客户端验证隧道建立。

## 故障排查

### "Package not found"

确认 `./scripts/feeds update -i` 和 `feeds install op-packages` 已运行。
SDK 默认 `feeds.conf` 不包含我们这个 feed,需要手动加:

```bash
echo "src-link op-packages /path/to/op-packages/net" >> feeds.conf
./scripts/feeds update op-packages
./scripts/feeds install op-packages
```

### "OpenSSL headers not found"

`./scripts/feeds install libopenssl` 后重试,或确保 `.config` 中
`CONFIG_PACKAGE_libopenssl=y`。

### "kmod-ovpn-dco-v2 not found"

在 SDK 的 `.config` 里 `CONFIG_PACKAGE_kmod-ovpn-dco-v2=y`,
OpenWrt 25.12 SDK 默认应已启用;如果是 25.12 之前的 SDK,旧名是
`kmod-ovpn-backports`,需要替换。

## 维护

- 升级包版本时,运行 `upstream-check.sh` 看上游最新版本,然后同步更新
  对应包的 `PKG_VERSION`
- 添加新包时,把它加进 `tests/scripts/build-all.sh` 的 `PACKAGES` 数组
  和 `ci/github-actions.yml` 的矩阵中
