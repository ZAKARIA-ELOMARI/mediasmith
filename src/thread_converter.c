#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <pthread.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>
#include <time.h>

// Configuration constants
#define MAX_THREADS 8
#define MAX_QUEUE_SIZE 1000
#define MAX_PATH_LEN 4096
#define LOG_BUFFER_SIZE 512

// Statistics structure for tracking progress
typedef struct {
    int total_files;
    int completed_files;
    int failed_files;
    pthread_mutex_t stats_mutex;
    time_t start_time;
} ConversionStats;

// Job structure for individual file conversions
typedef struct {
    char filepath[MAX_PATH_LEN];
    int job_id;
} ConversionJob;

// Thread-safe work queue
typedef struct {
    ConversionJob jobs[MAX_QUEUE_SIZE];
    int front;
    int rear;
    int count;
    int shutdown;
    pthread_mutex_t mutex;
    pthread_cond_t not_empty;
    pthread_cond_t not_full;
} WorkQueue;

// Global variables
static WorkQueue work_queue;
static ConversionStats stats;
static pthread_t worker_threads[MAX_THREADS];
static int num_threads;

// Function declarations
void init_work_queue(void);
void cleanup_work_queue(void);
int enqueue_job(const ConversionJob* job);
int dequeue_job(ConversionJob* job);
void* worker_thread(void* arg);
int process_conversion_job(const ConversionJob* job);
void safe_log(const char* level, int thread_id, const char* format, ...);
void update_stats(int success);
void print_progress(void);
int get_optimal_thread_count(void);
int is_supported_file(const char* filepath);
void shutdown_workers(void);

// Initialize the work queue
void init_work_queue(void) {
    memset(&work_queue, 0, sizeof(WorkQueue));
    
    if (pthread_mutex_init(&work_queue.mutex, NULL) != 0) {
        fprintf(stderr, "Failed to initialize work queue mutex\n");
        exit(1);
    }
    
    if (pthread_cond_init(&work_queue.not_empty, NULL) != 0) {
        fprintf(stderr, "Failed to initialize not_empty condition\n");
        exit(1);
    }
    
    if (pthread_cond_init(&work_queue.not_full, NULL) != 0) {
        fprintf(stderr, "Failed to initialize not_full condition\n");
        exit(1);
    }
    
    work_queue.front = 0;
    work_queue.rear = 0;
    work_queue.count = 0;
    work_queue.shutdown = 0;
}

// Cleanup work queue resources
void cleanup_work_queue(void) {
    pthread_mutex_destroy(&work_queue.mutex);
    pthread_cond_destroy(&work_queue.not_empty);
    pthread_cond_destroy(&work_queue.not_full);
}

// Add job to queue (thread-safe)
int enqueue_job(const ConversionJob* job) {
    pthread_mutex_lock(&work_queue.mutex);
    
    // Wait if queue is full
    while (work_queue.count == MAX_QUEUE_SIZE && !work_queue.shutdown) {
        pthread_cond_wait(&work_queue.not_full, &work_queue.mutex);
    }
    
    if (work_queue.shutdown) {
        pthread_mutex_unlock(&work_queue.mutex);
        return -1;
    }
    
    // Add job to queue
    work_queue.jobs[work_queue.rear] = *job;
    work_queue.rear = (work_queue.rear + 1) % MAX_QUEUE_SIZE;
    work_queue.count++;
    
    // Signal that queue is not empty
    pthread_cond_signal(&work_queue.not_empty);
    pthread_mutex_unlock(&work_queue.mutex);
    
    return 0;
}

// Remove job from queue (thread-safe)
int dequeue_job(ConversionJob* job) {
    pthread_mutex_lock(&work_queue.mutex);
    
    // Wait for job or shutdown signal
    while (work_queue.count == 0 && !work_queue.shutdown) {
        pthread_cond_wait(&work_queue.not_empty, &work_queue.mutex);
    }
    
    if (work_queue.shutdown && work_queue.count == 0) {
        pthread_mutex_unlock(&work_queue.mutex);
        return -1; // No more jobs
    }
    
    // Get job from queue
    *job = work_queue.jobs[work_queue.front];
    work_queue.front = (work_queue.front + 1) % MAX_QUEUE_SIZE;
    work_queue.count--;
    
    // Signal that queue is not full
    pthread_cond_signal(&work_queue.not_full);
    pthread_mutex_unlock(&work_queue.mutex);
    
    return 0;
}

// Worker thread function
void* worker_thread(void* arg) {
    int thread_id = *(int*)arg;
    ConversionJob job;
    
    safe_log("INFO", thread_id, "Worker thread started");
    
    while (1) {
        if (dequeue_job(&job) != 0) {
            break; // Shutdown or error
        }
        
        safe_log("INFO", thread_id, "Processing job %d: %s", job.job_id, job.filepath);
        
        int success = process_conversion_job(&job);
        update_stats(success);
        
        if (success) {
            safe_log("SUCCESS", thread_id, "Completed job %d: %s", job.job_id, job.filepath);
        } else {
            safe_log("ERROR", thread_id, "Failed job %d: %s", job.job_id, job.filepath);
        }
        
        print_progress();
    }
    
    safe_log("INFO", thread_id, "Worker thread terminated");
    return NULL;
}

// Process a single conversion job
int process_conversion_job(const ConversionJob* job) {
    char command[MAX_PATH_LEN * 2];
    char cwd[MAX_PATH_LEN];
    
    // Get current working directory
    if (getcwd(cwd, sizeof(cwd)) == NULL) {
        perror("getcwd failed");
        return 0;
    }
    
    // Build command
    int ret = snprintf(command, sizeof(command), 
                      "%s/lib/conversion.sh \"%s\"", 
                      cwd, job->filepath);
    
    if (ret >= (int)sizeof(command)) {
        fprintf(stderr, "Command buffer overflow for file: %s\n", job->filepath);
        return 0;
    }
    
    // Execute conversion
    int result = system(command);
    
    if (result == 0) {
        return 1; // Success
    } else {
        if (WIFEXITED(result)) {
            fprintf(stderr, "Conversion script exited with code: %d for file: %s\n", 
                   WEXITSTATUS(result), job->filepath);
        } else if (WIFSIGNALED(result)) {
            fprintf(stderr, "Conversion script killed by signal: %d for file: %s\n", 
                   WTERMSIG(result), job->filepath);
        }
        return 0; // Failure
    }
}

// Thread-safe logging
void safe_log(const char* level, int thread_id, const char* format, ...) {
    static pthread_mutex_t log_mutex = PTHREAD_MUTEX_INITIALIZER;
    char log_buffer[LOG_BUFFER_SIZE];
    char timestamp[32];
    time_t now;
    struct tm* tm_info;
    
    // Get timestamp
    time(&now);
    tm_info = localtime(&now);
    strftime(timestamp, sizeof(timestamp), "%H:%M:%S", tm_info);
    
    // Format message
    va_list args;
    va_start(args, format);
    vsnprintf(log_buffer, sizeof(log_buffer), format, args);
    va_end(args);
    
    // Thread-safe output
    pthread_mutex_lock(&log_mutex);
    printf("[%s] [%s] THREAD-%d: %s\n", timestamp, level, thread_id, log_buffer);
    fflush(stdout);
    pthread_mutex_unlock(&log_mutex);
}

// Update conversion statistics
void update_stats(int success) {
    pthread_mutex_lock(&stats.stats_mutex);
    stats.completed_files++;
    if (!success) {
        stats.failed_files++;
    }
    pthread_mutex_unlock(&stats.stats_mutex);
}

// Print progress information
void print_progress(void) {
    static time_t last_print = 0;
    time_t now = time(NULL);
    
    // Limit progress updates to once per second
    if (now - last_print < 1) {
        return;
    }
    last_print = now;
    
    pthread_mutex_lock(&stats.stats_mutex);
    int completed = stats.completed_files;
    int total = stats.total_files;
    int failed = stats.failed_files;
    int successful = completed - failed;
    double elapsed = difftime(now, stats.start_time);
    pthread_mutex_unlock(&stats.stats_mutex);
    
    if (total > 0) {
        double progress = (double)completed / total * 100.0;
        double rate = elapsed > 0 ? completed / elapsed : 0;
        
        printf("\r[PROGRESS] %d/%d (%.1f%%) - Success: %d, Failed: %d, Rate: %.1f files/sec", 
               completed, total, progress, successful, failed, rate);
        fflush(stdout);
    }
}

// Get optimal number of threads based on CPU cores
int get_optimal_thread_count(void) {
    long num_cores = sysconf(_SC_NPROCESSORS_ONLN);
    if (num_cores <= 0) {
        num_cores = 4; // Default fallback
    }
    
    // Use number of cores, but cap at MAX_THREADS
    int optimal = (int)num_cores;
    if (optimal > MAX_THREADS) {
        optimal = MAX_THREADS;
    }
    
    printf("Detected %ld CPU cores, using %d worker threads\n", num_cores, optimal);
    return optimal;
}

// Check if file has supported extension
int is_supported_file(const char* filepath) {
    const char* ext = strrchr(filepath, '.');
    if (!ext) return 0;
    
    ext++; // Skip the dot
    
    // Supported extensions (add more as needed)
    const char* supported[] = {
        "mp3", "wav", "flac", "aac", "ogg",           // Audio
        "mp4", "mkv", "avi", "mov", "flv", "wmv",     // Video
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", // Image
        NULL
    };
    
    for (int i = 0; supported[i]; i++) {
        if (strcasecmp(ext, supported[i]) == 0) {
            return 1;
        }
    }
    
    return 0;
}

// Signal workers to shutdown
void shutdown_workers(void) {
    pthread_mutex_lock(&work_queue.mutex);
    work_queue.shutdown = 1;
    pthread_cond_broadcast(&work_queue.not_empty);
    pthread_mutex_unlock(&work_queue.mutex);
    
    // Wait for all workers to finish
    for (int i = 0; i < num_threads; i++) {
        pthread_join(worker_threads[i], NULL);
    }
}

// Recursively scan directory and enqueue jobs
int scan_directory(const char* dir_path, int* job_counter) {
    DIR* d = opendir(dir_path);
    if (!d) {
        perror("opendir failed");
        return -1;
    }
    
    struct dirent* dir;
    int files_found = 0;
    
    while ((dir = readdir(d)) != NULL) {
        // Skip "." and ".."
        if (strcmp(dir->d_name, ".") == 0 || strcmp(dir->d_name, "..") == 0) {
            continue;
        }
        
        char full_path[MAX_PATH_LEN];
        int ret = snprintf(full_path, sizeof(full_path), "%s/%s", dir_path, dir->d_name);
        
        if (ret >= (int)sizeof(full_path)) {
            fprintf(stderr, "Path too long: %s/%s\n", dir_path, dir->d_name);
            continue;
        }
        
        struct stat path_stat;
        if (stat(full_path, &path_stat) != 0) {
            perror("stat failed");
            continue;
        }
        
        if (S_ISREG(path_stat.st_mode)) {
            // It's a regular file
            if (is_supported_file(full_path)) {
                ConversionJob job;
                strncpy(job.filepath, full_path, sizeof(job.filepath) - 1);
                job.filepath[sizeof(job.filepath) - 1] = '\0';
                job.job_id = ++(*job_counter);
                
                if (enqueue_job(&job) == 0) {
                    files_found++;
                } else {
                    fprintf(stderr, "Failed to enqueue job for: %s\n", full_path);
                }
            } else {
                printf("Skipping unsupported file: %s\n", full_path);
            }
        }
        // Note: Not handling subdirectories in this version
        // Add recursive directory scanning here if needed
    }
    
    closedir(d);
    return files_found;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <directory_path>\n", argv[0]);
        return 1;
    }
    
    char* dir_path = argv[1];
    printf("Enhanced C threaded converter starting...\n");
    printf("Processing directory: %s\n", dir_path);
    
    // Initialize statistics
    memset(&stats, 0, sizeof(ConversionStats));
    if (pthread_mutex_init(&stats.stats_mutex, NULL) != 0) {
        fprintf(stderr, "Failed to initialize stats mutex\n");
        return 1;
    }
    stats.start_time = time(NULL);
    
    // Initialize work queue
    init_work_queue();
    
    // Determine optimal thread count
    num_threads = get_optimal_thread_count();
    
    // Create worker threads
    int thread_ids[MAX_THREADS];
    for (int i = 0; i < num_threads; i++) {
        thread_ids[i] = i + 1;
        if (pthread_create(&worker_threads[i], NULL, worker_thread, &thread_ids[i]) != 0) {
            fprintf(stderr, "Failed to create worker thread %d\n", i + 1);
            return 1;
        }
    }
    
    // Scan directory and enqueue jobs
    int job_counter = 0;
    int files_found = scan_directory(dir_path, &job_counter);
    
    if (files_found < 0) {
        fprintf(stderr, "Failed to scan directory\n");
        shutdown_workers();
        cleanup_work_queue();
        return 1;
    }
    
    // Update total files count
    pthread_mutex_lock(&stats.stats_mutex);
    stats.total_files = files_found;
    pthread_mutex_unlock(&stats.stats_mutex);
    
    printf("Found %d supported files, queued for processing\n", files_found);
    
    if (files_found == 0) {
        printf("No supported files found in directory\n");
        shutdown_workers();
        cleanup_work_queue();
        return 0;
    }
    
    // Wait for all jobs to complete
    while (1) {
        pthread_mutex_lock(&stats.stats_mutex);
        int completed = stats.completed_files;
        int total = stats.total_files;
        pthread_mutex_unlock(&stats.stats_mutex);
        
        if (completed >= total) {
            break;
        }
        
        sleep(1);
    }
    
    // Shutdown workers
    shutdown_workers();
    
    // Final statistics
    pthread_mutex_lock(&stats.stats_mutex);
    int total = stats.total_files;
    int completed = stats.completed_files;
    int failed = stats.failed_files;
    int successful = completed - failed;
    double elapsed = difftime(time(NULL), stats.start_time);
    pthread_mutex_unlock(&stats.stats_mutex);
    
    printf("\n\n=== CONVERSION SUMMARY ===\n");
    printf("Total files: %d\n", total);
    printf("Successful: %d\n", successful);
    printf("Failed: %d\n", failed);
    printf("Time elapsed: %.1f seconds\n", elapsed);
    printf("Average rate: %.2f files/second\n", elapsed > 0 ? completed / elapsed : 0);
    printf("Success rate: %.1f%%\n", total > 0 ? (double)successful / total * 100.0 : 0);
    
    // Cleanup
    cleanup_work_queue();
    pthread_mutex_destroy(&stats.stats_mutex);
    
    printf("Enhanced threaded C helper finished.\n");
    return failed > 0 ? 1 : 0;
}