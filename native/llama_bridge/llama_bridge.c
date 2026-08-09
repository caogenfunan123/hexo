// llama_bridge.c - llama.cpp 桥接层
// 提供稳定的 C ABI，供 Dart FFI (LocalLlamaProvider) 调用。
//
// 编译方式（需 NDK，Android）：
//   cmake -B build -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
//     -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-23
//   cmake --build build --target llama_bridge -j
//   产物: libllama_bridge.so，放入 android/app/src/main/jniLibs/arm64-v8a/
//
// 依赖 llama.cpp 源码（需先编译 llama 静态库 libllama.a 并链接）：
//   - 从 https://github.com/ggml-org/llama.cpp 拉取源码
//   - 编译静态库: cmake -B build -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TESTS=OFF -DBUILD_SHARED_LIBS=OFF
//   - 链接: target_link_libraries(llama_bridge PRIVATE llama llama-common)
//
// 上下文长度通过环境变量 LLAMA_N_CTX 读取，默认 4096。

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "llama.h"

#define BRIDGE_OK 0
#define BRIDGE_ERR -1

static struct llama_model *g_model = NULL;
static struct llama_context *g_ctx = NULL;
static char g_error[1024] = {0};

static void set_error(const char *fmt, const char *arg) {
  snprintf(g_error, sizeof(g_error), fmt, arg ? arg : "");
}

static int32_t bridge_n_ctx(void) {
  const char *env = getenv("LLAMA_N_CTX");
  if (env && *env) {
    return (int32_t)strtol(env, NULL, 10);
  }
  return 4096;
}

// 加载模型：返回空串表示成功，否则返回错误信息
const char *llama_bridge_load(const char *model_path) {
  if (!model_path || !*model_path) {
    set_error("model path is empty", NULL);
    return g_error;
  }
  if (g_model) {
    llama_bridge_unload();
  }
  llama_model_params mparams = llama_model_default_params();
  mparams.n_gpu_layers = 0;
  g_model = llama_load_model_from_file(model_path, mparams);
  if (!g_model) {
    set_error("failed to load model: %s", model_path);
    return g_error;
  }
  llama_context_params cparams = llama_context_default_params();
  cparams.n_ctx = bridge_n_ctx();
  g_ctx = llama_init_from_model(g_model, cparams);
  if (!g_ctx) {
    llama_free_model(g_model);
    g_model = NULL;
    set_error("failed to create context", NULL);
    return g_error;
  }
  g_error[0] = '\0';
  return g_error; // 空串 = 成功
}

int llama_bridge_is_loaded(void) { return (g_model != NULL) ? 1 : 0; }

int llama_bridge_token_count(void) {
  if (!g_ctx) return 0;
  return (int)llama_n_ctx(g_ctx);
}

const char *llama_bridge_last_error(void) { return g_error; }

static int32_t tokenize(const char *text, llama_token *tokens, int32_t capacity) {
  int32_t n = llama_tokenize(g_model, text, (int32_t)strlen(text), tokens, capacity, true, false);
  return n;
}

// 单次完整生成，输出写入 out（容量 out_cap）。返回 0 成功，非 0 失败。
int llama_bridge_complete(const char *prompt, int max_tokens, float temperature,
                          float top_p, char *out, int out_cap) {
  if (!g_model || !g_ctx || !prompt || !out) {
    set_error("model not loaded", NULL);
    return BRIDGE_ERR;
  }
  llama_token *tokens = (llama_token *)malloc(sizeof(llama_token) * (bridge_n_ctx() / 2));
  if (!tokens) return BRIDGE_ERR;
  int32_t n_prompt = tokenize(prompt, tokens, bridge_n_ctx() / 2);
  if (n_prompt < 0) {
    set_error("tokenize failed", NULL);
    free(tokens);
    return BRIDGE_ERR;
  }

  llama_batch batch = llama_batch_init(n_prompt, 0, 1);
  for (int32_t i = 0; i < n_prompt; i++) {
    batch.token[i] = tokens[i];
    batch.pos[i] = i;
    batch.n_seq_id[i] = 1;
    batch.seq_id[i][0] = 0;
    batch.logits[i] = false;
  }
  batch.n_tokens = n_prompt;
  batch.logits[batch.n_tokens - 1] = true;

  size_t out_len = 0;
  int generated = 0;
  const float t = (temperature <= 0.0f) ? 0.8f : temperature;
  const float tp = (top_p <= 0.0f) ? 0.9f : top_p;

  while (generated < max_tokens) {
    if (llama_decode(g_ctx, batch) != 0) {
      set_error("llama_decode failed", NULL);
      break;
    }
    llama_token new_token_id = 0;
    {
      const float *logits = llama_get_logits_ith(g_ctx, batch.n_tokens - 1);
      int32_t n_vocab = llama_n_vocab(g_model);
      float max_l = -1e30f;
      int32_t max_i = 0;
      for (int32_t i = 0; i < n_vocab; i++) {
        if (logits[i] > max_l) { max_l = logits[i]; max_i = i; }
      }
      if (t >= 1.0f - 1e-6f) {
        new_token_id = (llama_token)max_i;
      } else {
        // 简化的 top-p + temperature 采样
        int32_t n_vocab = llama_n_vocab(g_model);
        typedef struct { float v; int32_t i; } scored;
        scored *arr = (scored *)malloc(sizeof(scored) * n_vocab);
        for (int32_t i = 0; i < n_vocab; i++) {
          arr[i].v = logits[i] / t;
          arr[i].i = i;
        }
        // 简单排序（选择 top candidates）——生产环境请用 llama_sampler_chain
        // 这里用 argmax 近似，保证正确性优先
        new_token_id = (llama_token)max_i;
        free(arr);
      }
    }
    (void)tp;

    if (llama_token_is_eog(g_model, new_token_id)) {
      break;
    }
    char piece[128];
    int32_t n = llama_token_to_piece(g_model, new_token_id, piece, 128, 0, false);
    if (n > 0) {
      if (out_len + (size_t)n + 1 < (size_t)out_cap) {
        memcpy(out + out_len, piece, (size_t)n);
        out_len += (size_t)n;
        out[out_len] = '\0';
      } else {
        break;
      }
    }
    generated++;

    // 准备下一批：单 token
    llama_batch_clear(batch);
    batch.token[0] = new_token_id;
    batch.pos[0] = batch.pos[batch.n_tokens - 1] + 1;
    batch.n_seq_id[0] = 1;
    batch.seq_id[0][0] = 0;
    batch.logits[0] = true;
    batch.n_tokens = 1;
  }

  if (generated == 0) {
    set_error("no tokens generated", NULL);
  }
  free(tokens);
  llama_batch_free(batch);
  return (generated > 0) ? BRIDGE_OK : BRIDGE_ERR;
}

// 流式生成开始：重置内部状态。返回 0 成功。
static llama_token *g_stream_tokens = NULL;
static int32_t g_stream_n_prompt = 0;
static int32_t g_stream_total = 0;
static int32_t g_stream_max = 0;
static int32_t g_stream_ctx = 0;

int llama_bridge_generate_start(int max_tokens, const char *prompt,
                                int prompt_len, float temperature, float top_p) {
  (void)temperature;
  (void)top_p;
  if (!g_model || !g_ctx || !prompt || max_tokens <= 0) {
    set_error("model not loaded", NULL);
    return BRIDGE_ERR;
  }
  int32_t cap = bridge_n_ctx() / 2;
  if (g_stream_tokens) { free(g_stream_tokens); g_stream_tokens = NULL; }
  g_stream_tokens = (llama_token *)malloc(sizeof(llama_token) * (size_t)cap);
  if (!g_stream_tokens) return BRIDGE_ERR;
  g_stream_n_prompt = tokenize(prompt, g_stream_tokens, cap);
  if (g_stream_n_prompt <= 0) {
    set_error("tokenize failed", NULL);
    free(g_stream_tokens); g_stream_tokens = NULL;
    return BRIDGE_ERR;
  }
  g_stream_total = g_stream_n_prompt;
  g_stream_max = max_tokens;
  g_stream_ctx = cap;
  g_error[0] = '\0';
  return BRIDGE_OK;
}

// 流式生成下一步：产出下一个 token 文本。返回 0 表示结束或错误。
int llama_bridge_generate_next(char *out, int out_cap) {
  if (!g_model || !g_ctx || !g_stream_tokens || out_cap <= 0) {
    return 0;
  }
  int generated = g_stream_total - g_stream_n_prompt;
  if (generated >= g_stream_max) return 0;

  // 每次解码从上文起点开始（简单实现；生产环境可用 kv cache + llama_batch）
  llama_batch batch = llama_batch_init(g_stream_total, 0, 1);
  int32_t i;
  for (i = 0; i < g_stream_total; i++) {
    batch.token[i] = g_stream_tokens[i];
    batch.pos[i] = i;
    batch.n_seq_id[i] = 1;
    batch.seq_id[i][0] = 0;
    batch.logits[i] = (i == g_stream_total - 1);
  }
  batch.n_tokens = g_stream_total;

  if (llama_decode(g_ctx, batch) != 0) {
    llama_batch_free(batch);
    return 0;
  }
  llama_batch_free(batch);

  const float *logits = llama_get_logits_ith(g_ctx, g_stream_total - 1);
  int32_t n_vocab = llama_n_vocab(g_model);
  float max_l = -1e30f;
  int32_t max_i = 0;
  for (i = 0; i < n_vocab; i++) {
    if (logits[i] > max_l) { max_l = logits[i]; max_i = i; }
  }
  llama_token new_token_id = (llama_token)max_i;

  if (llama_token_is_eog(g_model, new_token_id)) {
    return 0;
  }
  char piece[128];
  int32_t n = llama_token_to_piece(g_model, new_token_id, piece, 128, 0, false);
  if (n <= 0) return 0;
  if ((size_t)n >= (size_t)out_cap) n = out_cap - 1;
  memcpy(out, piece, (size_t)n);
  out[n] = '\0';

  if (g_stream_total < g_stream_ctx) {
    g_stream_tokens[g_stream_total++] = new_token_id;
  } else {
    // 上下文已满，按比例丢弃最旧 token
    int32_t drop = g_stream_ctx / 8;
    if (drop < 1) drop = 1;
    memmove(g_stream_tokens, g_stream_tokens + drop,
            sizeof(llama_token) * (size_t)(g_stream_ctx - drop));
    g_stream_total = g_stream_ctx - drop + 1;
    g_stream_tokens[g_stream_total - 1] = new_token_id;
  }
  return 1;
}

void llama_bridge_unload(void) {
  if (g_ctx) { llama_free(g_ctx); g_ctx = NULL; }
  if (g_model) { llama_free_model(g_model); g_model = NULL; }
  if (g_stream_tokens) { free(g_stream_tokens); g_stream_tokens = NULL; }
  g_stream_n_prompt = 0;
  g_stream_total = 0;
  g_stream_max = 0;
  g_error[0] = '\0';
}
