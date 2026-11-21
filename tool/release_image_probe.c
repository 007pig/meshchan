/* Observe executable vnode mappings in a child without a task port. */
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <libproc.h>
#include <mach/vm_prot.h>
#include <signal.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

struct image {
    char path[MAXPATHLEN];
    struct stat file;
};

static volatile sig_atomic_t interrupted;

static void interrupt(int signal_number) {
    interrupted = signal_number;
}

static bool inspect_image(const char *path, struct image *image) {
    return path[0] == '/' && realpath(path, image->path) != NULL &&
           stat(image->path, &image->file) == 0 && S_ISREG(image->file.st_mode);
}

static const char *data_volume_path(const char *path) {
    const char prefix[] = "/System/Volumes/Data";
    if (!strncmp(path, prefix, sizeof(prefix) - 1) && path[sizeof(prefix) - 1] == '/') {
        return path + sizeof(prefix) - 1;
    }
    return path;
}

static bool same_path(const char *observed, const char *expected) {
    return !strcmp(data_volume_path(observed), data_volume_path(expected));
}

static bool matches(const struct proc_regionwithpathinfo *region, const struct image *image) {
    const struct vnode_info_path *vnode = &region->prp_vip;
    return vnode->vip_vi.vi_stat.vst_dev == (uint32_t)image->file.st_dev &&
           vnode->vip_vi.vi_stat.vst_ino == image->file.st_ino &&
           same_path(vnode->vip_path, image->path);
}

static uint64_t observe(pid_t pid, const struct image *executable, const struct image *library,
                        int *observation_error) {
    char path[PROC_PIDPATHINFO_MAXSIZE];
    if (proc_pidpath(pid, path, sizeof(path)) <= 0) {
        *observation_error = errno;
        return 0;
    }
    if (!same_path(path, executable->path)) {
        return 0;
    }

    bool executable_seen = false;
    uint64_t library_address = 0;
    uint64_t address = 0;
    /* A bound protects the observer if the child's address space keeps changing. */
    for (size_t count = 0; count < 16384; ++count) {
        struct proc_regionwithpathinfo region;
        int bytes = proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, address, &region, sizeof(region));
        if (bytes != sizeof(region)) {
            *observation_error = errno;
            break;
        }
        const struct proc_regioninfo *mapping = &region.prp_prinfo;
        if (mapping->pri_protection & VM_PROT_EXECUTE) {
            if (matches(&region, executable)) {
                executable_seen = true;
            }
            if (matches(&region, library)) {
                library_address = mapping->pri_address;
            }
            if (executable_seen && library_address) {
                return library_address;
            }
        }
        uint64_t next = mapping->pri_address + mapping->pri_size;
        if (next <= address) {
            break;
        }
        address = next;
    }
    return 0;
}

/* Only signal the direct, unreaped child spawned by this observer. */
static pid_t wait_for_child(pid_t pid, int *status, int options) {
    pid_t result;
    do {
        result = waitpid(pid, status, options);
    } while (result < 0 && errno == EINTR);
    return result;
}

static void stop_child(pid_t pid) {
    int status;
    kill(pid, SIGTERM);
    for (int attempt = 0; attempt < 25; ++attempt) {
        if (wait_for_child(pid, &status, WNOHANG) != 0) {
            return;
        }
        usleep(10000);
    }
    kill(pid, SIGKILL);
    wait_for_child(pid, &status, 0);
}

int main(int argc, char **argv) {
    struct image executable, library;
    if (argc < 4 || !inspect_image(argv[2], &library) || !inspect_image(argv[3], &executable) ||
        same_path(executable.path, library.path)) {
        fputs("Usage: release-image-probe NEW_RECEIPT LIBRARY EXECUTABLE [ARG ...]\n", stderr);
        return 2;
    }
    FILE *receipt = fopen(argv[1], "wx");
    if (!receipt || fcntl(fileno(receipt), F_SETFD, FD_CLOEXEC) == -1) {
        perror("Open new image receipt");
        return 2;
    }
    struct sigaction action = {0};
    action.sa_handler = interrupt;
    if (sigemptyset(&action.sa_mask) == -1 || sigaction(SIGTERM, &action, NULL) == -1 ||
        sigaction(SIGINT, &action, NULL) == -1) {
        perror("Install observer signal handler");
        fclose(receipt);
        return 2;
    }

    pid_t pid;
    int spawn_error = posix_spawn(&pid, executable.path, NULL, NULL, &argv[3], environ);
    if (spawn_error) {
        fprintf(stderr, "Launch observed executable: %s\n", strerror(spawn_error));
        fclose(receipt);
        return 2;
    }

    uint64_t address = 0;
    int observation_error = 0, status = 0;
    while (true) {
        if (interrupted) {
            stop_child(pid);
            fclose(receipt);
            return 128 + interrupted;
        }
        if (!address) {
            address = observe(pid, &executable, &library, &observation_error);
        }
        pid_t reaped = wait_for_child(pid, &status, WNOHANG);
        if (reaped < 0) {
            perror("Wait for observed executable");
            fclose(receipt);
            return 2;
        }
        if (reaped == pid) {
            break;
        }
        usleep(address ? 2000 : 250);
    }

    int code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    int error = fprintf(receipt, "{\"observerPid\":%d,\"pid\":%d,\"exitCode\":%d,\"mapping\":",
                        getpid(), pid, code);
    if (address) {
        error |= fprintf(receipt, "{\"address\":\"0x%" PRIx64 "\",\"device\":%" PRIu32
                         ",\"inode\":%" PRIu64 "}", address, (uint32_t)library.file.st_dev,
                         (uint64_t)library.file.st_ino);
    } else {
        error |= fprintf(receipt, "null,\"lastObservationErrno\":%d", observation_error);
    }
    error |= fputs("}\n", receipt);
    if (fclose(receipt) == EOF || error < 0) {
        perror("Write image receipt");
        return 2;
    }
    return code;
}
