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

// Constantes de configuration
#define MAX_THREADS 8
#define MAX_QUEUE_SIZE 1000
#define MAX_PATH_LEN 4096
#define LOG_BUFFER_SIZE 512

// Structure de statistiques pour suivre le progrès
typedef struct {
    int total_files;
    int completed_files;
    int failed_files;
    pthread_mutex_t stats_mutex;
    time_t start_time;
} ConversionStats;

// Structure de tâche pour les conversions de fichiers individuels
typedef struct {
    char filepath[MAX_PATH_LEN];
    int job_id;
} ConversionJob;

// File de travail thread-safe
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

// Variables globales
static WorkQueue work_queue;
static ConversionStats stats;
static pthread_t worker_threads[MAX_THREADS];
static int num_threads;

// Déclarations de fonctions
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

// Initialiser la file de travail
void init_work_queue(void) {
    memset(&work_queue, 0, sizeof(WorkQueue));
    
    if (pthread_mutex_init(&work_queue.mutex, NULL) != 0) {
        fprintf(stderr, "Échec de l'initialisation du mutex de la file de travail\n");
        exit(1);
    }
    
    if (pthread_cond_init(&work_queue.not_empty, NULL) != 0) {
        fprintf(stderr, "Échec de l'initialisation de la condition not_empty\n");
        exit(1);
    }
    
    if (pthread_cond_init(&work_queue.not_full, NULL) != 0) {
        fprintf(stderr, "Échec de l'initialisation de la condition not_full\n");
        exit(1);
    }
    
    work_queue.front = 0;
    work_queue.rear = 0;
    work_queue.count = 0;
    work_queue.shutdown = 0;
}

// Nettoyer les ressources de la file de travail
void cleanup_work_queue(void) {
    pthread_mutex_destroy(&work_queue.mutex);
    pthread_cond_destroy(&work_queue.not_empty);
    pthread_cond_destroy(&work_queue.not_full);
}

// Ajouter une tâche à la file (thread-safe)
int enqueue_job(const ConversionJob* job) {
    pthread_mutex_lock(&work_queue.mutex);
    
    // Attendre si la file est pleine
    while (work_queue.count == MAX_QUEUE_SIZE && !work_queue.shutdown) {
        pthread_cond_wait(&work_queue.not_full, &work_queue.mutex);
    }
    
    if (work_queue.shutdown) {
        pthread_mutex_unlock(&work_queue.mutex);
        return -1;
    }
    
    // Ajouter la tâche à la file
    work_queue.jobs[work_queue.rear] = *job;
    work_queue.rear = (work_queue.rear + 1) % MAX_QUEUE_SIZE;
    work_queue.count++;
    
    // Signaler que la file n'est pas vide
    pthread_cond_signal(&work_queue.not_empty);
    pthread_mutex_unlock(&work_queue.mutex);
    
    return 0;
}

// Retirer une tâche de la file (thread-safe)
int dequeue_job(ConversionJob* job) {
    pthread_mutex_lock(&work_queue.mutex);
    
    // Attendre une tâche ou le signal d'arrêt
    while (work_queue.count == 0 && !work_queue.shutdown) {
        pthread_cond_wait(&work_queue.not_empty, &work_queue.mutex);
    }
    
    if (work_queue.shutdown && work_queue.count == 0) {
        pthread_mutex_unlock(&work_queue.mutex);
        return -1; // Plus de tâches
    }
    
    // Obtenir la tâche de la file
    *job = work_queue.jobs[work_queue.front];
    work_queue.front = (work_queue.front + 1) % MAX_QUEUE_SIZE;
    work_queue.count--;
    
    // Signaler que la file n'est pas pleine
    pthread_cond_signal(&work_queue.not_full);
    pthread_mutex_unlock(&work_queue.mutex);
    
    return 0;
}

// Fonction du thread de travail
void* worker_thread(void* arg) {
    int thread_id = *(int*)arg;
    ConversionJob job;
    
    safe_log("INFO", thread_id, "Thread de travail démarré");
    
    while (1) {
        if (dequeue_job(&job) != 0) {
            break; // Arrêt ou erreur
        }
        
        safe_log("INFO", thread_id, "Traitement de la tâche %d: %s", job.job_id, job.filepath);
        
        int success = process_conversion_job(&job);
        update_stats(success);
        
        if (success) {
            safe_log("SUCCÈS", thread_id, "Tâche %d terminée: %s", job.job_id, job.filepath);
        } else {
            safe_log("ERREUR", thread_id, "Échec de la tâche %d: %s", job.job_id, job.filepath);
        }
        
        print_progress();
    }
    
    safe_log("INFO", thread_id, "Thread de travail terminé");
    return NULL;
}

// Traiter une tâche de conversion unique
int process_conversion_job(const ConversionJob* job) {
    char command[MAX_PATH_LEN * 2];
    char cwd[MAX_PATH_LEN];
    
    // Obtenir le répertoire de travail actuel
    if (getcwd(cwd, sizeof(cwd)) == NULL) {
        perror("échec de getcwd");
        return 0;
    }
    
    // Construire la commande
    int ret = snprintf(command, sizeof(command), 
                      "%s/lib/conversion.sh \"%s\"", 
                      cwd, job->filepath);
    
    if (ret >= (int)sizeof(command)) {
        fprintf(stderr, "Débordement du tampon de commande pour le fichier: %s\n", job->filepath);
        return 0;
    }
    
    // Exécuter la conversion
    int result = system(command);
    
    if (result == 0) {
        return 1; // Succès
    } else {
        if (WIFEXITED(result)) {
            fprintf(stderr, "Le script de conversion s'est terminé avec le code: %d pour le fichier: %s\n", 
                   WEXITSTATUS(result), job->filepath);
        } else if (WIFSIGNALED(result)) {
            fprintf(stderr, "Le script de conversion a été tué par le signal: %d pour le fichier: %s\n", 
                   WTERMSIG(result), job->filepath);
        }
        return 0; // Échec
    }
}

// Logging thread-safe
void safe_log(const char* level, int thread_id, const char* format, ...) {
    static pthread_mutex_t log_mutex = PTHREAD_MUTEX_INITIALIZER;
    char log_buffer[LOG_BUFFER_SIZE];
    char timestamp[32];
    time_t now;
    struct tm* tm_info;
    
    // Obtenir l'horodatage
    time(&now);
    tm_info = localtime(&now);
    strftime(timestamp, sizeof(timestamp), "%H:%M:%S", tm_info);
    
    // Formater le message
    va_list args;
    va_start(args, format);
    vsnprintf(log_buffer, sizeof(log_buffer), format, args);
    va_end(args);
    
    // Sortie thread-safe
    pthread_mutex_lock(&log_mutex);
    printf("[%s] [%s] THREAD-%d: %s\n", timestamp, level, thread_id, log_buffer);
    fflush(stdout);
    pthread_mutex_unlock(&log_mutex);
}

// Mettre à jour les statistiques de conversion
void update_stats(int success) {
    pthread_mutex_lock(&stats.stats_mutex);
    stats.completed_files++;
    if (!success) {
        stats.failed_files++;
    }
    pthread_mutex_unlock(&stats.stats_mutex);
}

// Afficher les informations de progrès
void print_progress(void) {
    static time_t last_print = 0;
    time_t now = time(NULL);
    
    // Limiter les mises à jour de progrès à une fois par seconde
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
        
        printf("\r[PROGRÈS] %d/%d (%.1f%%) - Succès: %d, Échecs: %d, Débit: %.1f fichiers/sec", 
               completed, total, progress, successful, failed, rate);
        fflush(stdout);
    }
}

// Obtenir le nombre optimal de threads basé sur les cœurs CPU
int get_optimal_thread_count(void) {
    long num_cores = sysconf(_SC_NPROCESSORS_ONLN);
    if (num_cores <= 0) {
        num_cores = 4; // Valeur par défaut de secours
    }
    
    // Utiliser le nombre de cœurs, mais limité à MAX_THREADS
    int optimal = (int)num_cores;
    if (optimal > MAX_THREADS) {
        optimal = MAX_THREADS;
    }
    
    printf("Détection de %ld cœurs CPU, utilisation de %d threads de travail\n", num_cores, optimal);
    return optimal;
}

// Vérifier si le fichier a une extension supportée
int is_supported_file(const char* filepath) {
    const char* ext = strrchr(filepath, '.');
    if (!ext) return 0;
    
    ext++; // Ignorer le point
    
    // Extensions supportées (ajouter plus si nécessaire)
    const char* supported[] = {
        "mp3", "wav", "flac", "aac", "ogg",           // Audio
        "mp4", "mkv", "avi", "mov", "flv", "wmv",     // Vidéo
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

// Signaler aux workers de s'arrêter
void shutdown_workers(void) {
    pthread_mutex_lock(&work_queue.mutex);
    work_queue.shutdown = 1;
    pthread_cond_broadcast(&work_queue.not_empty);
    pthread_mutex_unlock(&work_queue.mutex);
    
    // Attendre que tous les workers se terminent
    for (int i = 0; i < num_threads; i++) {
        pthread_join(worker_threads[i], NULL);
    }
}

// Scanner récursivement le répertoire et mettre en file les tâches
int scan_directory(const char* dir_path, int* job_counter) {
    DIR* d = opendir(dir_path);
    if (!d) {
        perror("échec d'opendir");
        return -1;
    }
    
    struct dirent* dir;
    int files_found = 0;
    
    while ((dir = readdir(d)) != NULL) {
        // Ignorer "." et ".."
        if (strcmp(dir->d_name, ".") == 0 || strcmp(dir->d_name, "..") == 0) {
            continue;
        }
        
        char full_path[MAX_PATH_LEN];
        int ret = snprintf(full_path, sizeof(full_path), "%s/%s", dir_path, dir->d_name);
        
        if (ret >= (int)sizeof(full_path)) {
            fprintf(stderr, "Chemin trop long: %s/%s\n", dir_path, dir->d_name);
            continue;
        }
        
        struct stat path_stat;
        if (stat(full_path, &path_stat) != 0) {
            perror("échec de stat");
            continue;
        }
        
        if (S_ISREG(path_stat.st_mode)) {
            // C'est un fichier régulier
            if (is_supported_file(full_path)) {
                ConversionJob job;
                strncpy(job.filepath, full_path, sizeof(job.filepath) - 1);
                job.filepath[sizeof(job.filepath) - 1] = '\0';
                job.job_id = ++(*job_counter);
                
                if (enqueue_job(&job) == 0) {
                    files_found++;
                } else {
                    fprintf(stderr, "Échec de la mise en file de la tâche pour: %s\n", full_path);
                }
            } else {
                printf("Fichier non supporté ignoré: %s\n", full_path);
            }
        }
    }
    
    closedir(d);
    return files_found;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <chemin_répertoire>\n", argv[0]);
        return 1;
    }
    
    char* dir_path = argv[1];
    printf("Convertisseur C threadé amélioré en cours de démarrage...\n");
    printf("Traitement du répertoire: %s\n", dir_path);
    
    // Initialiser les statistiques
    memset(&stats, 0, sizeof(ConversionStats));
    if (pthread_mutex_init(&stats.stats_mutex, NULL) != 0) {
        fprintf(stderr, "Échec de l'initialisation du mutex des statistiques\n");
        return 1;
    }
    stats.start_time = time(NULL);
    
    // Initialiser la file de travail
    init_work_queue();
    
    // Déterminer le nombre optimal de threads
    num_threads = get_optimal_thread_count();
    
    // Créer les threads de travail
    int thread_ids[MAX_THREADS];
    for (int i = 0; i < num_threads; i++) {
        thread_ids[i] = i + 1;
        if (pthread_create(&worker_threads[i], NULL, worker_thread, &thread_ids[i]) != 0) {
            fprintf(stderr, "Échec de la création du thread de travail %d\n", i + 1);
            return 1;
        }
    }
    
    // Scanner le répertoire et mettre les tâches en file
    int job_counter = 0;
    int files_found = scan_directory(dir_path, &job_counter);
    
    if (files_found < 0) {
        fprintf(stderr, "Échec du scan du répertoire\n");
        shutdown_workers();
        cleanup_work_queue();
        return 1;
    }
    
    // Mettre à jour le compteur total de fichiers
    pthread_mutex_lock(&stats.stats_mutex);
    stats.total_files = files_found;
    pthread_mutex_unlock(&stats.stats_mutex);
    
    printf("Trouvé %d fichiers supportés, mis en file pour traitement\n", files_found);
    
    if (files_found == 0) {
        printf("Aucun fichier supporté trouvé dans le répertoire\n");
        shutdown_workers();
        cleanup_work_queue();
        return 0;
    }
    
    // Attendre que toutes les tâches soient terminées
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
    
    // Arrêter les workers
    shutdown_workers();
    
    // Statistiques finales
    pthread_mutex_lock(&stats.stats_mutex);
    int total = stats.total_files;
    int completed = stats.completed_files;
    int failed = stats.failed_files;
    int successful = completed - failed;
    double elapsed = difftime(time(NULL), stats.start_time);
    pthread_mutex_unlock(&stats.stats_mutex);
    
    printf("\n\n=== RÉSUMÉ DE CONVERSION ===\n");
    printf("Total des fichiers: %d\n", total);
    printf("Réussis: %d\n", successful);
    printf("Échecs: %d\n", failed);
    printf("Temps écoulé: %.1f secondes\n", elapsed);
    printf("Débit moyen: %.2f fichiers/seconde\n", elapsed > 0 ? completed / elapsed : 0);
    printf("Taux de réussite: %.1f%%\n", total > 0 ? (double)successful / total * 100.0 : 0);
    
    // Nettoyage
    cleanup_work_queue();
    pthread_mutex_destroy(&stats.stats_mutex);
    
    printf("Assistant C threadé amélioré terminé.\n");
    return failed > 0 ? 1 : 0;
}