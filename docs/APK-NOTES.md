# apk 与 opkg 关键差异 (OpenWrt 25.12)

OpenWrt 25.12 默认包管理器从 **opkg** 切换到 **apk**,但提供 opkg 兼容层。
本仓库的包都同时兼容两种包管理器。

## 命令差异

| 操作 | opkg | apk |
|---|---|---|
| 安装本地包 | `opkg install foo.ipk` | `apk add --allow-untrusted foo.apk` |
| 列出已装包 | `opkg list-installed` | `apk list --installed` |
| 改过的 conffiles | `opkg list-changed-conffiles` | `apk audit` (无等价 CLI,需要 `apk diff`) |
| 搜索仓库 | `opkg find foo` | `apk search foo` |
| 删除 | `opkg remove foo` | `apk del foo` |

## 我们做的适配

### 1. 弱化 postinst 中的 opkg 假设

源包中 `strongswan-ipsec/postinst` 调用 `opkg list-changed-conffiles`,
这是 opkg-only。我们改为:

```sh
if command -v opkg >/dev/null 2>&1; then
    opkg list-changed-conffiles 2>/dev/null | grep -qx /etc/ipsec.conf || \
        rm -f /etc/ipsec.conf-opkg
else
    rm -f /etc/ipsec.conf-opkg /etc/ipsec.conf.apk-new
fi
```

这样在两种系统上都能正常清理 conffile 备份。

### 2. `$IPKG_INSTROOT` 变量

init 脚本中的 `$IPKG_INSTROOT/lib/functions.sh` 等引用在 apk 下依然有效:
- OpenWrt buildroot 在编译时设置该变量
- apk 包管理器的脚本也尊重同一变量

无需修改。

### 3. conffiles 列表

`Package/<x>/conffiles` 在两种包格式下都支持(都是 `/etc/foo` 形式的相对路径),
无需修改。

### 4. 软链接

`apk` 与 `opkg` 都能正确处理安装时的符号链接。我们的 `softethervpn-base`
中的 `vpncmd` 符号链接在两种包格式下都工作。

## 兼容性测试

如果你想在 25.12 设备上验证,请按以下顺序:

```bash
# 1. apk 路径 (默认)
apk update
apk add strongswan-default strongswan-mod-openssl

# 2. opkg 路径 (兼容层)
opkg update
opkg install strongswan-default strongswan-mod-openssl
```

两者都应成功启动 `charon` 守护进程。

## CI 注意事项

在 Docker SDK 镜像中,OpenWrt 25.12 SDK 的构建产物仍是 `.ipk` 格式
(apk 使用 `.apk` 格式,但 SDK 内仍兼容旧工具链生成 ipk)。

我们仓库里的 `PKG_ABI_VERSION` 不需要手动设置 — OpenWrt buildroot 会根据
目标自动选择 `PKG_ABI_VERSION=2`(apk 元数据)或 `1`(opkg 元数据)。

## 参考

- OpenWrt 25.12 release notes: https://openwrt.org/releases/25.12/start
- apk 官方: https://wiki.alpinelinux.org/wiki/Alpine_Package_Keeper
