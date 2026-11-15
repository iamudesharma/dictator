// Opt-in comparison of the patched GGML operation with its original path.
#include "ggml.h"
#include "ggml-cpu.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

static void verify(int columns, int rows, int vectors, int threads,
                   bool half, bool padded) {
    auto *ctx = ggml_init({64 * 1024 * 1024, nullptr, false});
    if (!ctx) std::abort();
    auto *storage = ggml_new_tensor_2d(ctx, half ? GGML_TYPE_F16 : GGML_TYPE_F32,
                                     columns + (padded ? 3 : 0), rows);
    auto *matrix = padded ? ggml_view_2d(ctx, storage, columns, rows,
                              (columns + 3) * sizeof(float), 0) : storage;
    auto *input = ggml_new_tensor_2d(ctx, GGML_TYPE_F32, columns, vectors);
    for (int i = 0; i < (columns + (padded ? 3 : 0)) * rows; ++i) {
        float value = std::sin(float(i) * 0.173f) * 0.5f;
        if (half) static_cast<ggml_fp16_t *>(storage->data)[i] = ggml_fp32_to_fp16(value);
        else static_cast<float *>(storage->data)[i] = value;
    }
    for (int i = 0; i < columns * vectors; ++i)
        static_cast<float *>(input->data)[i] = std::cos(float(i) * 0.137f) * 0.5f;
    auto *output = ggml_mul_mat(ctx, matrix, input);
    auto *graph = ggml_new_graph(ctx);
    ggml_build_forward_expand(graph, output);
    auto plan = ggml_graph_plan(graph, threads, nullptr);
    std::vector<uint8_t> work(plan.work_size);
    plan.work_data = work.data();
    plan.use_ref = true; // Explicitly bypasses the new Accelerate path.
    if (ggml_graph_compute(graph, &plan) != GGML_STATUS_SUCCESS) std::abort();
    std::vector<float> expected(static_cast<float *>(output->data),
                                static_cast<float *>(output->data) + rows * vectors);
    plan.use_ref = false;
    if (ggml_graph_compute(graph, &plan) != GGML_STATUS_SUCCESS) std::abort();
    const float *actual = static_cast<float *>(output->data);
    for (int i = 0; i < rows * vectors; ++i) {
        const float tolerance = 2e-5f * (1.0f + std::fabs(expected[i]));
        if (!std::isfinite(actual[i]) || std::fabs(actual[i] - expected[i]) > tolerance) {
            std::fprintf(stderr, "Mismatch %dx%d vectors=%d threads=%d half=%d padded=%d index=%d: %g vs %g\n",
                         rows, columns, vectors, threads, half, padded, i, actual[i], expected[i]);
            std::abort();
        }
    }
    ggml_free(ctx);
}

int main() {
    int cases = 0;
    for (int columns : {1, 3, 7, 31, 128, 640, 1024, 4096})
        for (int rows : {1, 3, 17, 129})
            for (int threads : {1, 2, 4}) {
                verify(columns, rows, 1, threads, false, false); ++cases;
                // Multiple vectors and noncontiguous matrices must use fallback.
                verify(columns, rows, 3, threads, false, false); ++cases;
                verify(columns, rows, 1, threads, false, true); ++cases;
                // ggml's F16 vector conversion requires a SIMD-compatible width.
                if (columns % 32 == 0) {
                    verify(columns, rows, 1, threads, true, false); ++cases;
                }
            }
    std::printf("Passed %d native matrix cases (Accelerate/reference and fallback).\n", cases);
}
