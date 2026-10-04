# Build the app on your computer

This guide is for building your own copy of Domabas, even if you do not write
code. Setup is needed once; after that, one command builds the app. The first
build downloads tools and libraries and can take several minutes.

The app connects to a Domabas server. You need that server's HTTP or HTTPS address when
you open the app, but the server does not need to be running during the build.
You do not need Go, Docker, a database, `task setup`, or `task generate` to build
these apps. To host a server too, follow the [hosting guide](compose.md).

## First-time setup

1. Download this repository's source ZIP and extract it, or clone the repository
   if you already use Git. Keep the whole folder together.
2. Install [Git](https://git-scm.com/downloads),
   [Flutter **3.47.4 stable**](https://docs.flutter.dev/install/archive),
   [Bun **1.4.2**](https://bun.com/docs/installation), and
   [Go Task **3.x**](https://taskfile.dev/docs/installation). Go Task is the
   command launcher; installing the Go programming language is not required.
   Choose the Flutter download for your computer and follow
   [Flutter's installation steps](https://docs.flutter.dev/install/manual),
   including adding its `bin` folder to PATH. PATH is the list of folders your
   terminal searches for commands. Use this checkout's versions rather than
   upgrading an existing Flutter project.
3. Close and reopen Terminal on a Mac or Linux, or PowerShell on Windows.
   Enter `cd ` followed by the extracted repository folder's path in quotes.
   For example: `cd "/Users/yourname/Downloads/domabas"` on a Mac, or
   `cd "C:\Users\yourname\Downloads\domabas"` on Windows. This is the folder
   containing `Taskfile.yml` and `readme.md`.
4. Check that the commands are available:

   ```sh
   git --version
   flutter --version
   bun --version
   task --version
   ```

5. Complete the setup below for the app you want. **Run its setup commands
   before the build command.** Then run `flutter doctor -v`. Resolve issues for
   your chosen platform; warnings about platforms you are not building can be
   ignored. You do not need an editor or a connected phone just to build.

| App you want | Computer you must build on | Build command after setup |
| --- | --- | --- |
| Android phone or tablet | Windows, macOS or Linux | `task build:android -- --release` |
| Mac | macOS | `task build:macos` |
| iPhone or iPad | macOS | `task build:ios` (unsigned; installation steps below) |
| iPhone simulator on your Mac | macOS | `task build:ios -- --simulator` |
| Windows PC | Windows | `task build:windows` |

Each task installs the locked script dependencies, checks the Flutter version
and build host, downloads the locked app dependencies, and builds the app. It
prints the output location when it succeeds. Repeat the same command after
updating the source; there is no separate dependency command to remember.
Internet access is needed for Flutter, package and native-library downloads.

## macOS and iOS

Install the full [Xcode application](https://developer.apple.com/xcode/) on your
Mac. Open it once, review its license and allow its requested components to
install. Command Line Tools alone cannot build these apps.

**Before the first build**, run these commands in Terminal:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

`sudo` asks for your Mac administrator password; typing it does not display
characters. If Xcode is in another folder, change the path. These commands select
Xcode for the computer and finish its tool setup. If asked to accept a license,
open Xcode or run `sudo xcodebuild -license` to review it first.

Check the result:

```sh
xcode-select -p
flutter doctor -v
```

The selected path must end in `Xcode.app/Contents/Developer` (or your renamed
Xcode application's equivalent), not `CommandLineTools`. The iOS build's native
dependencies need this system-wide selection; setting only `DEVELOPER_DIR`
does not replace it.

Domabas uses Swift Package Manager, which is included with Xcode. Its current
locked plugins do not need a separate CocoaPods installation. If you previously
disabled Swift Package Manager in Flutter, enable it before building:

```sh
flutter config --enable-swift-package-manager
```

A CocoaPods-only warning in `flutter doctor` can be ignored for this checkout.
Run one Flutter build or test command at a time in this folder; they share
generated plugin files.

Native integration tests also replace Xcode's generated Dart entry point with
a temporary test runner. Before returning to Xcode after those tests, run
`task build:ios` again to restore and verify the normal application entry point.
For a configuration-only refresh without compiling, run this from `frontend/`:

```sh
flutter build ios --config-only --release --no-codesign --target lib/main.dart
```

Use `--simulator --debug` instead of `--release --no-codesign` when preparing an
iOS simulator. Regenerate these files through Flutter rather than editing
`Generated.xcconfig` or generated plugin registration files by hand.

See Flutter's [Mac setup](https://docs.flutter.dev/platform-integration/macos/setup),
[iOS setup](https://docs.flutter.dev/platform-integration/ios/setup), and
[Swift Package Manager guide](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers).

### Build and open the Mac app

From the repository folder:

```sh
task build:macos
open frontend/build/macos/Build/Products/Release/domabas.app
```

You can also find `domabas.app` at that location in Finder and copy it to
Applications. The app requires macOS 12 or later. This is a local release build;
it is not an installer or a notarized download for distribution to other people.

### Build the iPhone and iPad app

In Xcode's **Settings → Components**, install iOS platform support if it is
missing. Then, from the repository folder:

```sh
task build:ios
```

The output is `frontend/build/ios/iphoneos/Runner.app`. It requires iOS 15 or
later. **This output is unsigned: it cannot be installed on an iPhone by copying
the file, and it is not an IPA installer.** To install your own copy:

1. Connect and unlock your iPhone or iPad, and trust the Mac when prompted.
2. Run `open frontend/ios/Runner.xcworkspace` from the repository folder.
3. In Xcode, add your Apple account under **Settings → Accounts**.
4. Select the **Runner** project, then its **Runner** target. Under
   **Signing & Capabilities**, enable **Automatically manage signing** and
   choose your team. If Xcode says the bundle identifier is unavailable, change
   `dev.domabas.domabas` to your own unique value, such as
   `com.yourname.domabas`. These settings belong to your local copy.
5. Select your connected device at the top of Xcode. Enable **Developer Mode**
   under the device's **Settings → Privacy & Security** if requested, then
   press Xcode's **Run** triangle. Xcode builds, signs and installs the app.
6. If the device asks you to trust your developer profile, follow its prompt
   under **Settings → General → VPN & Device Management**, then open Domabas.

A free personal Apple account can be used for local device testing, subject to
Apple's provisioning limits; it may need periodic rebuilding and reinstalling.
App Store and TestFlight distribution require a separate paid Apple Developer
membership and release signing setup. See Flutter's
[device setup](https://docs.flutter.dev/platform-integration/ios/setup) and
[iOS distribution guide](https://docs.flutter.dev/deployment/ios).

### Build for the iPhone simulator

You can build a simulator app without an iPhone or device signing team. Install
an iOS simulator runtime in Xcode's **Settings → Components** first, or run
`xcodebuild -downloadPlatform iOS` (a large download). Then:

```sh
task build:ios -- --simulator
open frontend/ios/Runner.xcworkspace
```

The debug app is `frontend/build/ios/iphonesimulator/Runner.app`. In Xcode,
select an iPhone simulator and press **Run**. Use Xcode to launch it with the
app's Keychain entitlements for saved sign-ins. A simulator build does not run
on a physical phone and does not test its camera scanner.

## Android

Install [Android Studio](https://developer.android.com/studio), open it once and
finish its setup wizard. Open **More Actions → SDK Manager** from its welcome
screen (or **Tools → SDK Manager** inside a project). Install the SDK platform
reported by Flutter and, under **SDK Tools**, install Android SDK Command-line
Tools, Build-Tools, Platform-Tools, CMake and NDK (Side by side). Flutter and
Gradle select the versions required by this checkout. Android Studio includes
Java; use the Java installation reported by `flutter doctor -v`.

**Before building**, review and accept the Android SDK licenses:

```sh
flutter doctor --android-licenses
flutter doctor -v
```

Then build an app for personal use:

```sh
task build:android -- --release
```

Copy `frontend/build/app/outputs/flutter-apk/app-release.apk` to your phone,
open it, and allow installation from that file manager when Android asks. The
app supports Android 7.0/API 24 or later. It asks for your HTTP or HTTPS server address
on first launch. An emulator and USB debugging are not needed for this method.

Both release and debug APKs use your computer's **development signing key**.
This is suitable for local use, not Google Play publication. An app built on
another computer or downloaded from a release may use a different key and cannot
be updated with this APK. Keep the same key for repeat builds. Uninstalling the
old app removes local settings, saved sign-ins and unuploaded scanner drafts;
finish uploading drafts before deciding to replace an installation.

For development with local HTTP, `task build:android` keeps the existing debug
build and produces `frontend/build/app/outputs/flutter-apk/app-debug.apk`.
See [Flutter's Android setup](https://docs.flutter.dev/platform-integration/android/setup)
if the SDK or Java is not detected.

## Windows

Use a Windows computer. Install [Visual Studio](https://visualstudio.microsoft.com/downloads/)
and select the **Desktop development with C++** workload in its installer.
Include the Windows SDK, CMake tools and **C++ ATL** component for your target
architecture under **Individual components**. Visual Studio Code is a different
product and does not provide these compilers.

Enable **Developer Mode** in Windows Settings so Flutter can create plugin
links. Searching Settings for “Developer Mode” finds the switch. Reopen
PowerShell, return to the repository folder and run:

```powershell
flutter doctor -v
task build:windows
```

Open `frontend\build\windows\x64\runner\Release\domabas.exe`. On an ARM64
Windows build computer, replace `x64` with `arm64`; the build command prints the
actual path.

**Keep the entire `Release` folder together.** It contains DLL libraries and a
`data` folder needed by the app. Copying just `domabas.exe` will not work. This
build creates a folder, not an MSI/MSIX installer. Another computer also needs
the matching [Microsoft Visual C++ Redistributable](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist).
See Flutter's [Windows setup](https://docs.flutter.dev/platform-integration/windows/setup)
and [distribution guide](https://docs.flutter.dev/deployment/windows).

## Connect to your documents

Open the app, enter your Domabas server's HTTP or HTTPS address, and press **Connect**.
Then sign in or create an account. Ask the person hosting Domabas for the address
if you do not know it. You can change it later in **Settings → Server**.

`localhost` on a phone means the phone itself, not your computer. Use a server
hostname or LAN address reachable from that device, such as
`http://192.168.0.230:8088`. Release mobile builds support HTTP too. Allow local
network access if asked. For private certificates and development addresses, see the
[server guide](../arch/frontend/server-configuration.md).

## If a command fails

| Message or problem | What to do |
| --- | --- |
| `task`, `bun` or `flutter` is not found | Finish its installation, check PATH, then reopen the terminal. |
| No Taskfile found | Use `cd` to enter the extracted repository folder containing `Taskfile.yml`. |
| Flutter version mismatch | Install the version in this checkout's `.tool-versions`; do not upgrade the app's dependencies to bypass the check. |
| Xcode or SDK missing | Complete the Apple setup commands above and check the selected Xcode has the required platform installed. |
| An unsigned iOS build mentions signing or native assets | First check `xcode-select -p` points to full Xcode. Native dependencies can fail when only Command Line Tools is selected, even if Flutter ends with a signing message. |
| Android licenses or command-line tools missing | Install Command-line Tools in Android Studio, then run `flutter doctor --android-licenses`. |
| Windows symlink or ATL error | Enable Developer Mode or add the C++ ATL component in Visual Studio Installer. |
| Package or native-library download failed | Check your network, proxy and access to pub.dev and GitHub, then rerun the same build command. |
| Build succeeds but server connection fails | Check the server address, port and local-network permission; check the certificate if using HTTPS. Building the app does not start the server. |

The common script can also be used as `task build:app -- macos`, replacing
`macos` with `android`, `ios` or `windows`. Run `task build:app -- --help` for
its options. For contributors, its implementation is
[build-app.ts](../../scripts/development/build-app.ts).

Web and Linux desktop builds remain available as `task build:web` and
`task build:linux`; their requirements are in the
[frontend guide](../../frontend/README.md#build-for-a-platform).
