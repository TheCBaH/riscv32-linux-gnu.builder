#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

/* Exercises libpthread.so and malloc/free beyond a trivial hello-world -
 * threading is a specific place a from-source glibc build can be subtly
 * misconfigured while a hello-world using only printf still passes. */

static void *worker(void *arg) {
    int *value = malloc(sizeof(*value));
    if (!value) {
        return NULL;
    }
    *value = *(int *)arg * 2;
    return value;
}

int main(void) {
    pthread_t thread;
    int input = 21;
    void *result = NULL;

    if (pthread_create(&thread, NULL, worker, &input) != 0) {
        fprintf(stderr, "pthread_create failed\n");
        return 1;
    }
    if (pthread_join(thread, &result) != 0) {
        fprintf(stderr, "pthread_join failed\n");
        return 1;
    }
    if (!result) {
        fprintf(stderr, "worker returned NULL\n");
        return 1;
    }

    int value = *(int *)result;
    free(result);

    if (value != 42) {
        fprintf(stderr, "expected 42, got %d\n", value);
        return 1;
    }

    printf("pthread+malloc ok: %d\n", value);
    return 0;
}
