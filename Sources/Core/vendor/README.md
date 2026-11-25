# 第三方头文件（只在编译期使用）

- `vulkan/vulkan.h`、`vulkan/vk_platform.h`、`vulkan/vulkan_core.h`、`vk_video/*.h`：Khronos Vulkan-Headers（`VK_HEADER_VERSION 357`），取自 MoltenVK v1.4.2 发布包（`MoltenVK-all.tar` 的 `MoltenVK/include`）。许可证：Apache-2.0 OR MIT（见各文件头 SPDX 标识）。
- 上一级目录的 `libretro_vulkan.h`：libretro-common（MIT），取自 Azahar 2126.1.1 的 `externals/libretro-common`。

FoldArc 以 `VK_NO_PROTOTYPES` 方式使用这些头文件：所有 Vulkan 函数都在运行期通过 MoltenVK 的 `vkGetInstanceProcAddr` 取得，App 不在链接期依赖 Vulkan 库。
