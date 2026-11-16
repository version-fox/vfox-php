# 从源码安装

[中文](install-from-source.md) | [English](../install-from-source.md)

要在发布之前试用本仓库，就把它的检出版本作为插件安装。vfox 用 `vfox add -s` 读取本地压缩包，压缩包的根目录必须直接是插件，`metadata.lua` 与各个文件夹并列。

```shell
git clone https://github.com/version-fox/vfox-php.git
cd vfox-php
zip -r ../php.zip ./
vfox add -s ../php.zip
vfox install php@latest
```

压缩包建在检出目录之外，这样 `zip` 不会把它自己打包进去。CI 工作流在仓库根目录用 `zip -r php.zip ./` 制作的也是同样的压缩包。

修改插件之后，先删除旧的副本，再添加新的压缩包：

```shell
vfox remove php
cd vfox-php
zip -r ../php.zip ./
vfox add -s ../php.zip
```

要求与正式发布的插件相同：vfox 0.3.2 或更新版本（`metadata.lua` 写明的最低版本），以及[平台](platforms.md)中列出的系统软件包。`vfox link --detect` 和卸载时删除构建目录都需要 vfox 1.1.0 或更新版本。
