# OpenSSL 1.1 → 3.5 迁移笔记

OpenWrt 25.12 内置 OpenSSL **3.5.7**。本仓库所有包都已适配。

## 关键变化

| 项目 | OpenSSL 1.1.x | OpenSSL 3.5.x |
|---|---|---|
| 默认 provider | 默认 (legacy disabled) | default |
| Legacy provider | 不需要 | 显式加载才能用 |
| FIPS provider | 模块化 (libcrypto.so) | provider 形式 (libfips.so) |
| 低级 API | 可直接用 | **被 deprecate**,仍可用但触发 `deprecation` warning |
| `EVP_CIPHER_CTX_init()` | 可用 | **被移除** |
| `HMAC_CTX_new()` | 默认 provider | legacy provider only |
| `RAND_pseudo_bytes()` | 可用 | **被移除** |
| `FIPS_mode()` | 可用 | **被移除** |
| `SSL_OP_NO_SSLv3` | 有效 | 编译时已 hard-code |
| ENGINE API | 主推 | **被 legacy**,推荐 EVP_PKEY |

## 我们做了哪些适配

### 1. libreswan

libreswan 不直接链接 libopenssl,改用 NSS。所以无需 OpenSSL 适配,
仅 `DEPENDS:=+nss-utils+nspr` 保留。

### 2. strongswan

- 强天鹅 6.1.0 已原生兼容 OpenSSL 3.x(`mod-openssl` 插件使用 EVP API)。
- 我们不需要额外补丁。
- wolfSSL 插件依赖的 `ML-KEM` header 在 wolfSSL 5.9 已重命名,源补丁 `0905`
  继续保留(已包含这个 fix)。

### 3. openvpn

- `--with-openssl-engine=no` 保留(OpenSSL 3.x 的 ENGINE 已被 EVP_PKEY 取代)
- mbedTLS 运行时版本检查补丁在 mbedTLS 3.6 中可能不需要,保留以防 fallback。

### 4. softethervpn / softethervpn5

- 移除 `CONFIG_OPENSSL_WITH_SSL3` 条件编译(该 config 在 25.12 不存在)
- 直接 `-DSSL_OP_NO_SSLv3`(SSLv3 在 OpenSSL 3.5 默认禁用,no-op)

## 编译期可能遇到的警告

`DEPRECATED` 警告是预期的(OpenSSL 3.5 标注的 `__attribute__((deprecated))`
函数),不应被当作错误:

```
warning: 'RSA_generate_key_ex' is deprecated: since OpenSSL 3.0 [-Wdeprecated-declarations]
```

如果上游包启用了 `-Werror`,需要在 Makefile 中加:

```make
TARGET_CFLAGS += -Wno-deprecated-declarations
```

## 如何在目标上验证

```bash
# 在 OpenWrt 25.12 设备上
opkg update
opkg install strongswan-default strongswan-mod-openssl
strongswan --version    # 应输出 6.1.0
strongswan pki --print   # 应能生成证书

openssl version         # 应输出 OpenSSL 3.5.x
```

## 参考资料

- [OpenSSL 3.0 Migration Guide](https://github.com/openssl/openssl/blob/master/doc/man7/migration_guide.pod)
- [OpenWrt 25.12 OpenSSL 3.5 security notes](https://openwrt.org/releases/25.12/notes-25.12.5)
- 强天鹅 wiki: https://wiki.strongswan.org/projects/strongswan/wiki/openssl
