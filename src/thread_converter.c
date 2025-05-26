#include <stdio.h>
#include <stdlib.h> // Required for malloc
#include <string.h>
#include <pthread.h>
#include <dirent.h>     // Required for reading directories
#include <sys/stat.h>   // Required for checking if a path is a file or directory

// The job for each thread now contains the real file path
// and an ID for logging purposes.
typedef struct {
    char filepath[4096];
    int thread_id;
} ConversionJob;

// This is the real worker function.
// It receives a pointer to a ConversionJob struct.
void *thread_conversion_function(void *arg) {
    ConversionJob *job = (ConversionJob *)arg;
    char outpath[4096]; // Buffer for the output path

    // --- Create a realistic output path ---
    // Example: files/image.jpg -> files/image_converted.jpg
    char *dot = strrchr(job->filepath, '.');
    if (dot) {
        // Copy the part before the extension
        int base_len = dot - job->filepath;
        strncpy(outpath, job->filepath, base_len);
        outpath[base_len] = '\0';
        // Add "_converted" and the original extension
        snprintf(outpath + base_len, sizeof(outpath) - base_len, "_converted%s", dot);
    } else {
        // If no extension, just append
        snprintf(outpath, sizeof(outpath), "%s_converted", job->filepath);
    }

    // --- Safe Logging (as corrected before) ---
    char log_buffer[512];
    {
        int static_len = snprintf(NULL, 0, "THREAD-%d: Processing %s -> %s", job->thread_id, "", "");
        int max_path_len = (sizeof(log_buffer) - 1 - static_len) / 2;
        if (max_path_len < 0) max_path_len = 0;

        snprintf(log_buffer, sizeof(log_buffer),
                 "THREAD-%d: Processing %.*s -> %.*s",
                 job->thread_id,
                 max_path_len, job->filepath,
                 max_path_len, outpath);
        printf("%s\n", log_buffer);
    }

    //
    // --- REAL CONVERSION LOGIC WOULD GO HERE ---
    // Example: build a command like `ffmpeg -i "job->filepath" "outpath"`
    // and execute it with system().
    // For this test, we'll just simulate success.
    //
    printf("THREAD-%d: Success for %s\n", job->thread_id, job->filepath);


    // Free the memory allocated for the job struct in main
    free(job);
    return NULL;
}


int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <directory_path>\n", argv[0]);
        return 1;
    }

    char *dir_path = argv[1];
    printf("C threaded converter received path: %s\n", dir_path);

    DIR *d;
    struct dirent *dir;
    d = opendir(dir_path);
    if (!d) {
        perror("opendir failed");
        return 1;
    }

    pthread_t threads[256]; // Allow for a maximum of 256 files
    int thread_count = 0;

    // Read every entry in the directory
    while ((dir = readdir(d)) != NULL && thread_count < 256) {
        // Skip "." and ".." directories
        if (strcmp(dir->d_name, ".") == 0 || strcmp(dir->d_name, "..") == 0) {
            continue;
        }

        char full_path[4096];
        snprintf(full_path, sizeof(full_path), "%s/%s", dir_path, dir->d_name);

        struct stat path_stat;
        stat(full_path, &path_stat);

        // Check if it's a regular file (not a directory)
        if (S_ISREG(path_stat.st_mode)) {
            // This is a file, create a job for it
            ConversionJob *job = malloc(sizeof(ConversionJob));
            if (!job) {
                perror("malloc for job failed");
                continue;
            }

            strncpy(job->filepath, full_path, sizeof(job->filepath));
            job->thread_id = thread_count + 1;

            // Create a dedicated thread for this job
            if (pthread_create(&threads[thread_count], NULL, thread_conversion_function, job) != 0) {
                perror("pthread_create failed");
                free(job); // Clean up
            } else {
                thread_count++;
            }
        }
    }
    closedir(d);

    printf("Dispatched %d jobs to threads.\n", thread_count);

    // Wait for all dispatched threads to complete
    for (int i = 0; i < thread_count; i++) {
        if (pthread_join(threads[i], NULL) != 0) {
            perror("pthread_join failed");
        }
    }

    printf("Threaded C helper finished.\n");
    return 0;
}