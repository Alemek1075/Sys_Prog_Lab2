#define _POSIX_C_SOURCE 199309L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define NOINLINE __attribute__((noinline))

static double now(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec * 1e-9;
}

static unsigned rng_state = 12345u;

static float frand(void)
{
    rng_state = rng_state * 1664525u + 1013904223u;
    return (float)(rng_state >> 8) * (1.0f / 16777216.0f) - 0.5f;
}

static float *alloc_floats(size_t n)
{
    float *p = aligned_alloc(64, ((n * sizeof(float) + 63) / 64) * 64);
    if (!p) {
        perror("aligned_alloc");
        exit(1);
    }
    return p;
}

NOINLINE static void fill(float *a, size_t n)
{
    for (size_t i = 0; i < n; i++)
        a[i] = frand();
}

NOINLINE static void matmul(int n, const float *restrict a,
                            const float *restrict b, float *restrict c)
{
#ifdef OPT_SRC
    memset(c, 0, sizeof(float) * (size_t)n * (size_t)n);
    for (int i = 0; i < n; i++) {
        float *crow = c + (size_t)i * n;
        for (int k = 0; k < n; k++) {
            const float aik = a[(size_t)i * n + k];
            const float *brow = b + (size_t)k * n;
            for (int j = 0; j < n; j++)
                crow[j] += aik * brow[j];
        }
    }
#else
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++) {
            float s = 0.0f;
            for (int k = 0; k < n; k++)
                s += a[(size_t)i * n + k] * b[(size_t)k * n + j];
            c[(size_t)i * n + j] = s;
        }
#endif
}

NOINLINE static void blur(int w, int h, const float *restrict in,
                          float *restrict out)
{
    for (int y = 1; y < h - 1; y++)
        for (int x = 1; x < w - 1; x++) {
            size_t i = (size_t)y * w + x;
            out[i] = (in[i - w] + in[i - 1] + in[i] + in[i + 1] + in[i + w]) * 0.2f;
        }
}

NOINLINE static void saxpy(size_t n, float k, const float *restrict x,
                           float *restrict y)
{
    for (size_t i = 0; i < n; i++)
        y[i] = k * x[i] + y[i];
}

NOINLINE static double checksum(const float *a, size_t n)
{
    double s = 0.0;
    for (size_t i = 0; i < n; i++)
        s += a[i];
    return s;
}

static void usage(const char *prog)
{
    fprintf(stderr,
            "usage: %s [-n matrix_n] [-w image_side] [-b blur_reps] "
            "[-v vector_len] [-s saxpy_reps] [-q]\n"
            "defaults: -n 1024 -w 2048 -b 200 -v 8388608 -s 200\n",
            prog);
}

int main(int argc, char **argv)
{
    int n = 1024, w = 2048, blur_reps = 200, saxpy_reps = 200, quiet = 0;
    size_t vlen = 8u << 20;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-q")) {
            quiet = 1;
            continue;
        }
        if (i + 1 >= argc) {
            usage(argv[0]);
            return 2;
        }
        const char *opt = argv[i], *val = argv[++i];
        if (!strcmp(opt, "-n")) n = atoi(val);
        else if (!strcmp(opt, "-w")) w = atoi(val);
        else if (!strcmp(opt, "-b")) blur_reps = atoi(val);
        else if (!strcmp(opt, "-v")) vlen = (size_t)strtoull(val, NULL, 10);
        else if (!strcmp(opt, "-s")) saxpy_reps = atoi(val);
        else {
            usage(argv[0]);
            return 2;
        }
    }

    const size_t nn = (size_t)n * n, ww = (size_t)w * w;
    float *a = alloc_floats(nn), *b = alloc_floats(nn), *c = alloc_floats(nn);
    float *img = alloc_floats(ww), *tmp = alloc_floats(ww);
    float *x = alloc_floats(vlen), *y = alloc_floats(vlen);

    double t0 = now();
    fill(a, nn);
    fill(b, nn);
    fill(img, ww);
    memcpy(tmp, img, ww * sizeof(float));
    fill(x, vlen);
    fill(y, vlen);
    double t1 = now();

    matmul(n, a, b, c);
    double t2 = now();

    for (int r = 0; r < blur_reps; r++) {
        blur(w, w, img, tmp);
        float *sw = img;
        img = tmp;
        tmp = sw;
    }
    double t3 = now();

    for (int r = 0; r < saxpy_reps; r++)
        saxpy(vlen, 1.0001f, x, y);
    double t4 = now();

    double cs = checksum(c, nn) + checksum(img, ww) + checksum(y, vlen);
    double t5 = now();

    if (!quiet) {
        printf("fill      %8.3f s\n", t1 - t0);
        printf("matmul    %8.3f s  (n=%d)\n", t2 - t1, n);
        printf("blur      %8.3f s  (%dx%d, %d reps)\n", t3 - t2, w, w, blur_reps);
        printf("saxpy     %8.3f s  (len=%zu, %d reps)\n", t4 - t3, vlen, saxpy_reps);
        printf("checksum  %8.3f s\n", t5 - t4);
        printf("total     %8.3f s\n", t5 - t0);
    }
    printf("result %.6e\n", cs);

    free(a); free(b); free(c); free(img); free(tmp); free(x); free(y);
    return 0;
}
