# 版本与命名

[中文](versions.md) | [English](../versions.md)

版本就是 `php@` 后面写的内容。插件接受以下几种形式：

| 写法 | vfox 安装的版本 | 适用范围 |
| --- | --- | --- |
| `latest` | 最新的发布版本 | 所有平台 |
| `8` | 最新的 8.x.y | 所有平台 |
| `8.4` | 最新的 8.4.x | 所有平台 |
| `8.4.5` | 精确的 8.4.5 | 所有平台 |
| `8.4.5-nts` | 8.4.5 的 NTS 版本 | 仅 Windows |

```shell
vfox install php@latest
vfox install php@8.4
vfox install php@8.4.5
vfox install php@8.4.5-nts
```

## 版本如何匹配

插件把版本列表按从新到旧排序，然后取第一个匹配的：

1. 与版本相等的发布版本，包括 `-nts` 后缀。精确匹配总是优先。
2. 否则取第一个以“版本号加一个点”开头的发布版本。所以 `8.4` 取最新的 `8.4.x`，`8` 取最新的 `8.x.y`。

在 Windows 上，同一个发布版本如果同时有 TS 和 NTS 构建，TS 排在前面。所以 `8.4` 这样的版本系列选的是 TS 构建，只有明确写 `-nts` 才会选 NTS。`latest` 同样是 TS 构建。

除 `-nts` 以外的后缀都不会匹配，带 `-nts` 的版本系列也不匹配：`8.4-nts` 不是一个版本。Linux 和 macOS 上没有任何 `-nts` 发布版本，所以在那里写 `8.4.5-nts` 会提示找不到。

## 列表来自哪里

- **Linux 和 macOS**：php.net 的发布索引，覆盖 PHP 8、7 和 5。从 5.3.2 起，带源码压缩包的发布版本都会列出。压缩包附带 php.net 给出的 sha256，vfox 用它校验下载的文件。
- **Windows**：windows.php.net 上你所用架构的构建，包括当前发布版本和存档。只有 x64 和 x86 构建。每个发布版本都有 TS 构建和 NTS 构建。

## 搜索

`vfox search php` 按从新到旧列出发布版本：

```text
Available versions:
 - 8.5.12
 - 8.5.11
```

如果列表获取失败，插件会报出它尝试访问的地址，而不是返回一个空列表。对应的提示见[问题排查](troubleshooting.md)。

## 安装后的名字

vfox 用发布版本给已安装的 PHP 命名：`8.5.12`，Windows 上的 NTS 构建则是 `8.5.12-nts`。`vfox list php` 显示已安装的名字，`vfox use php@8.5.12` 使用的也是同样的名字。

## 错误

- `PHP version not found: 8.4.9`：没有匹配的发布版本。请对照 `vfox search php` 检查拼写。
- `No PHP releases found for windows/arm64`：PHP 没有为该架构发布构建。
