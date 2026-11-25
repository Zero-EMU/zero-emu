# Zero EMU · 第三方声明（NOTICE）

Zero EMU 以 GNU General Public License v3.0（见 `LICENSE`）发布。版权所有 (c) 2026 Zero EMU。工程和代码里的 FoldArc 是它的开发代号。

Zero EMU 与任何游戏主机厂商没有关联，也未获其授权。Zero EMU 不包含任何游戏、密钥、固件或系统文件；它只加载用户自行导入、且已解密的文件，并拒绝加密文件。

## 已嵌入的组件

按构建产物核对（2026-10-28）：核心的链接命令（`Third-Party/azahar-build-ios/build.ninja` 里 `bin/Release/azahar_libretro.dylib` 那一行）列出的静态库，加上编进核心的纯头文件库，许可证取自各组件源码里的许可证文件。核心是 Azahar 2126.1.1 的 libretro 核心，由 `Scripts/build-azahar-ios.sh` 从源码构建，在 App 里是 `Frameworks/azahar_libretro.framework`（iOS 只接受放在 framework 里的动态库）。

| 组件 | 许可证 | 来源 / 说明 |
| --- | --- | --- |
| Azahar（3DS 模拟核心：common、core、audio_core、video_core、network、citra_libretro） | GPL-2.0-or-later（源码头）/ GPL-3.0（仓库） | https://github.com/azahar-emu/azahar ；Zero EMU 的修改以补丁形式放在 `Scripts/patches/azahar/`（清单见该目录 README，改动的源文件里有 "Modified by FoldArc" 标注） |
| MoltenVK v1.4.2（Vulkan → Metal，运行期 dlopen，随 App 嵌入 `MoltenVK.framework`，不链接进核心） | Apache-2.0 | https://github.com/KhronosGroup/MoltenVK ，`Scripts/fetch-moltenvk.sh` 取官方发布包并校验 SHA-256 |
| Boost（iostreams、serialization 及头文件） | BSL-1.0 | Azahar externals |
| Crypto++ | BSL-1.0（整体编排）；各文件进入公有领域 | Azahar externals |
| LibreSSL（libssl、libcrypto） | OpenSSL / SSLeay 许可；新增部分 ISC 或公有领域 | Azahar externals；供模拟机的 SSL / HTTP 服务使用 |
| cpp-httplib 0.14.0（头文件） | MIT | Azahar externals |
| nlohmann/json（头文件） | MIT | Azahar externals |
| dynarmic | 0BSD | Azahar externals（iOS 上 JIT 关闭，只用解释器） |
| mcl | MIT | dynarmic externals |
| oaknut（头文件） | MIT | Azahar externals（dynarmic 的 arm64 后端） |
| teakra | MIT | Azahar externals |
| faad2 | GPL-2.0-or-later（其 COPYING 写明只允许按 GPL 使用） | Azahar externals |
| SoundTouch | LGPL-2.1 | Azahar externals |
| enet | MIT | Azahar externals |
| fmt | MIT | Azahar externals |
| zstd、zstd seekable | BSD-3-Clause 或 GPL-2.0（双许可） | Azahar externals |
| xxHash | BSD-2-Clause | Azahar externals |
| lodepng | zlib | Azahar externals |
| sirit | BSD-3-Clause | Azahar externals |
| glslang、SPIRV | BSD-3-Clause 为主（另有 Apache-2.0、MIT 等，见其 LICENSE.txt） | Azahar externals |
| Vulkan Memory Allocator（头文件） | MIT | Azahar externals |
| nihstro（头文件） | BSD-3-Clause | Azahar externals |
| libretro-common、libretro.h、libretro_vulkan.h | MIT | `Sources/Core/`（编译期），取自 Azahar 2126.1.1 的 externals |
| Vulkan-Headers（`Sources/Core/vendor/`，仅编译期） | Apache-2.0 OR MIT | https://github.com/KhronosGroup/Vulkan-Headers （取自 MoltenVK 发布包） |

许可证全文随源码分发（各组件目录里的 LICENSE / COPYING）。核心里还编进了 Azahar 的网络相关代码：模拟机的套接字服务（soc:U）、HTTP / SSL 服务和 NUS 下载代码；Zero EMU 不调用 NUS 下载，也不提供任何下载入口。
