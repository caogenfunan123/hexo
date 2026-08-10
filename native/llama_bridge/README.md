# llama_bridge 本地模型桥接层（已弃用）

> **已弃用**：本项目本地 GGUF 推理已改用 pub.dev 的 `llamadart` 插件
> （`lib/core/ai/local_llama_provider.dart` 内部基于 `llamadart`）。
> `llamadart` 通过 pub build hook 自动下载匹配平台的预编译 llama.cpp native
> 运行时，Android 默认启用 CPU + Vulkan 双后端，无需手动编译或放置 .so，
> 导入 GGUF 即可直接使用。
>
> 以下内容仅供历史参考，不再用于生产构建。

`libllama_bridge.so` 是 llama.cpp 的 C ABI 桥接层，供 Flutter 端 `LocalLlamaProvider`
（`lib/core/ai/local_llama_provider.dart`）通过 Dart FFI 调用，实现完全离线的 GGUF 推理。

## 支持的平台

- Android（arm64-v8a / armeabi-v7a / x86_64）——主要目标
- Linux 桌面（开发调试用）

## 构建步骤（Android）

1. 拉取 llama.cpp 源码并编译静态库：

```bash
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp
cmake -B build \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DLLAMA_CURL=OFF
cmake --build build --target llama -j$(nproc)
```

2. 编译桥接层（需 Android NDK）：

```bash
cd native/llama_bridge
cmake -B build \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-23 \
  -DLLAMA_CPP_DIR=/path/to/llama.cpp \
  -DLLAMA_BUILD_DIR=/path/to/llama.cpp/build
cmake --build build --target llama_bridge -j$(nproc)
```

3. 复制产物到 App：

```bash
mkdir -p android/app/src/main/jniLibs/arm64-v8a
cp build/libllama_bridge.so android/app/src/main/jniLibs/arm64-v8a/
# 如需支持其他 ABI，重复 2-3 步（armeabi-v7a / x86_64）
```

## 放置 GGUF 模型

将 `.gguf` 模型文件放入应用存储目录的 `models/` 子目录：

- 桌面端：`$HOME/.local/share/<app>/hexo_blog_manager/models/`
- Android：`/data/data/com.example.hexo/files/models/`

也可以在「AI 模型管理」页面点击内存图标，通过文件选择器直接导入 `.gguf` 文件，
导入过程会自动复制进 `models/` 并登记为 `provider = local` 的模型。

## Dart 侧调用

```dart
final llama = LocalLlamaProvider.instance;
if (!llama.isAvailable) llama.init();
final err = llama.loadModel('/path/to/model.gguf');
if (err == null) {
  final text = llama.complete('hello');
}
```

## ABI 说明

桥接层导出以下符号（稳定 ABI，改动需同步 Dart 侧 `_bindSymbols`）：

| 函数 | 说明 |
|------|------|
| `llama_bridge_load(const char*) -> const char*` | 加载模型；返回空串成功 |
| `llama_bridge_is_loaded() -> int` | 模型是否已加载 |
| `llama_bridge_token_count() -> int` | 上下文 token 数 |
| `llama_bridge_complete(...) -> int` | 单次完整生成 |
| `llama_bridge_generate_start(...) -> int` | 流式生成开始 |
| `llama_bridge_generate_next(char*, int) -> int` | 流式取下一 token |
| `llama_bridge_unload()` | 卸载模型释放内存 |
| `llama_bridge_last_error() -> const char*` | 最近错误信息 |

上下文长度通过环境变量 `LLAMA_N_CTX` 读取（默认 4096）。
