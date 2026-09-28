// Объявления системной libarchive (/usr/lib/libarchive.dylib), которые использует mTC.
// В SDK есть сама библиотека (libarchive.tbd), но нет заголовков, поэтому объявляем нужное сами.
// Сигнатуры совпадают с archive.h / archive_entry.h из libarchive 3.x (ABI стабилен).

#ifndef MTC_LIBARCHIVE_H
#define MTC_LIBARCHIVE_H

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <time.h>

struct archive;
struct archive_entry;

#define ARCHIVE_EOF 1
#define ARCHIVE_OK 0
#define ARCHIVE_RETRY (-10)
#define ARCHIVE_WARN (-20)
#define ARCHIVE_FAILED (-25)
#define ARCHIVE_FATAL (-30)

#define AE_IFMT   ((mode_t)0170000)
#define AE_IFREG  ((mode_t)0100000)
#define AE_IFLNK  ((mode_t)0120000)
#define AE_IFDIR  ((mode_t)0040000)

typedef const char *archive_passphrase_callback(struct archive *, void *client_data);

// Чтение
struct archive *archive_read_new(void);
int archive_read_support_filter_all(struct archive *);
int archive_read_support_format_all(struct archive *);
int archive_read_support_format_raw(struct archive *);
int archive_read_add_passphrase(struct archive *, const char *);
int archive_read_set_passphrase_callback(struct archive *, void *client_data, archive_passphrase_callback *);
int archive_read_open_filename(struct archive *, const char *filename, size_t block_size);
int archive_read_next_header(struct archive *, struct archive_entry **);
int archive_read_data_block(struct archive *, const void **buff, size_t *size, int64_t *offset);
int archive_read_data_skip(struct archive *);
int archive_read_free(struct archive *);

// Запись
struct archive *archive_write_new(void);
int archive_write_set_format_zip(struct archive *);
int archive_write_set_format_7zip(struct archive *);
int archive_write_set_format_pax_restricted(struct archive *);
int archive_write_add_filter_gzip(struct archive *);
int archive_write_add_filter_xz(struct archive *);
int archive_write_set_passphrase(struct archive *, const char *);
int archive_write_set_options(struct archive *, const char *);
int archive_write_open_filename(struct archive *, const char *);
int archive_write_header(struct archive *, struct archive_entry *);
ssize_t archive_write_data(struct archive *, const void *, size_t);
int archive_write_close(struct archive *);
int archive_write_free(struct archive *);

struct archive_entry *archive_entry_new(void);
void archive_entry_free(struct archive_entry *);
void archive_entry_set_pathname_utf8(struct archive_entry *, const char *);
void archive_entry_set_symlink_utf8(struct archive_entry *, const char *);
void archive_entry_set_size(struct archive_entry *, int64_t);
void archive_entry_set_filetype(struct archive_entry *, unsigned int);
void archive_entry_set_perm(struct archive_entry *, mode_t);
void archive_entry_set_mtime(struct archive_entry *, time_t, long);

// Общее
const char *archive_error_string(struct archive *);
int archive_errno(struct archive *);
int64_t archive_filter_bytes(struct archive *, int);
const char *archive_format_name(struct archive *);

// Запись элемента
const char *archive_entry_pathname(struct archive_entry *);
const char *archive_entry_pathname_utf8(struct archive_entry *);
const char *archive_entry_symlink(struct archive_entry *);
const char *archive_entry_symlink_utf8(struct archive_entry *);
const char *archive_entry_hardlink(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
int archive_entry_size_is_set(struct archive_entry *);
time_t archive_entry_mtime(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
mode_t archive_entry_perm(struct archive_entry *);
int archive_entry_is_encrypted(struct archive_entry *);

#endif
