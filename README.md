# Zero EMU

A dual-screen handheld emulator for iPhone, designed for the foldable iPhone Duo: open it and the two halves are the two screens; close the lid and the game sleeps; open it and play on. It runs on other iPhone models too.

为双屏折叠 iPhone 设计的掌机模拟器：展开就是两块屏幕，合上盖子游戏自动休眠，打开接着玩。普通 iPhone 也能用。

- Support / 支持: https://zero-emu.github.io/zero-emu/support.html
- Privacy policy / 隐私政策: https://zero-emu.github.io/zero-emu/privacy.html
- User agreement / 用户协议: https://zero-emu.github.io/zero-emu/terms.html
- Contact / 联系: zeroemu@outlook.com

Zero EMU ships with no games, keys, firmware or system files, and offers no downloads of or links to any. It opens only files you import yourself, and it refuses encrypted ones. Zero EMU is not affiliated with, authorized or endorsed by any console maker.

Zero EMU 不附带任何游戏、密钥、固件或系统文件，也不提供它们的下载或链接。它只打开你自己导入的文件，加密的文件会被拒绝。Zero EMU 与任何游戏主机厂商没有关联。

## Source code / 源码

This repository holds the source code of Zero EMU 1.0.1 (7), the version on the App Store, under the GNU General Public License v3.0 (version 1.0 (6) was built from the same code). The release of each version on the Releases page also carries its complete corresponding source as one archive, with the emulation core and Zero EMU's patches to it applied.

这里是 App Store 上 Zero EMU 1.0.1 (7) 的源码，以 GNU 通用公共许可证第 3 版发布（1.0 (6) 用的是同一份代码）。Releases 页面里每个版本另附一份完整对应源码包，包括打好 Zero EMU 补丁的模拟核心。

The pages at the top level (`index.html`, `support.html`, `privacy.html`, `terms.html`, `style.css`) are the website above, published with GitHub Pages.

## What is here

| Folder | |
| --- | --- |
| `Sources/` | The app (SwiftUI and RealityKit). `Sources/Core` is the bridge to the emulation core. |
| `Scripts/` | Building the core and embedding it in the app. |
| `Scripts/patches/azahar/` | Zero EMU's changes to the core, as patches (listed in the README there). |
| `FoldArc.xcodeproj` | The Xcode project. |

The Xcode project, its targets and many identifiers are still named FoldArc, the app's working name.

## Building

You need a Mac with Xcode 27.1 or later (the iOS 27.1 SDK) and Homebrew's `cmake` (`ninja` makes it much faster).

1. Build the emulation core (Azahar's libretro core, tag 2126.1.1, with the patches applied). The first run clones the sources and takes 20–60 minutes:

   ```sh
   zsh Scripts/build-azahar-ios.sh                              # iPhone
   PLATFORM=iphonesimulator zsh Scripts/build-azahar-ios.sh     # Simulator
   ```

2. Fetch MoltenVK (the official release, checked against its SHA-256):

   ```sh
   zsh Scripts/fetch-moltenvk.sh
   ```

3. Open `FoldArc.xcodeproj`, choose a scheme (`FoldArc-Duo` for the iPhone Duo), set your own signing team, then build and run.

Without the core the app still builds and says the core is unavailable; without MoltenVK the core falls back to its software renderer.

## License

Zero EMU is released under the GNU General Public License v3.0 (see `LICENSE`).

The emulation core is [Azahar](https://github.com/azahar-emu/azahar). The third-party components and their licences are listed in `NOTICE.md`; the full licence texts are in `Sources/ThirdPartyLicenses.txt` and are shown in the app.
