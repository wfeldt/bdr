#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <inttypes.h>
#include <getopt.h>
#include <fcntl.h>
#include <errno.h>
#include <stdarg.h>
#include <time.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <linux/fs.h>
#include <linux/loop.h>

extern void bdrive_start, bdrive_end;
extern void mbr_start, mbr_end;

#define SECTOR_SIZE	512

#define SECTOR_BITS	48
#define LEN_BITS	12
#define DRIVE_BITS	 4

#define CRC_BITS	16

#if SECTOR_BITS + LEN_BITS + DRIVE_BITS != 64 || SECTOR_BITS + CRC_BITS != 64
#error We use 64 bits!
#endif

#define MAX_MAP_LEN	((1 << LEN_BITS) - 1)
//#define MAX_MAP_LEN	50	// testing

#define MAX_DRIVES	(1 << DRIVE_BITS)

#define BDR_MAGIC	0x9ef8cb23cbe2c18ell

#define ENCODE_START(a) a
#define ENCODE_LEN(a) ((uint64_t) a << SECTOR_BITS)
#define ENCODE_DRIVE(a) ((uint64_t) a << (SECTOR_BITS + LEN_BITS))
#define ENCODE_CRC(a) ((uint64_t) (a & ((1 << CRC_BITS) - 1)) << SECTOR_BITS)

#define DECODE_START(a) (a & ((1ll << SECTOR_BITS) - 1))
#define DECODE_LEN(a) ((a >> SECTOR_BITS) & ((1 << LEN_BITS) - 1))
#define DECODE_DRIVE(a) ((a >> (SECTOR_BITS + LEN_BITS)) & ((1 << DRIVE_BITS) - 1))
#define DECODE_CRC(a) (a >> SECTOR_BITS)


typedef struct {
  char *name;				// device name
  unsigned dev_num;			// major/minor
  uint64_t start, size;			// first (excl. loop_start)/size in sectors
  uint64_t loop_start;			// if loop dev: offset in sectors
  uint64_t min, max;			// first (incl. loop_start)/last sector
} dev_info_t;

typedef struct {
  uint64_t offset;			// offset in bytes
  char *file_name;			// real file name (if any could be determined)
} loop_info_t;

typedef struct {
  uint64_t start;			// start sector
  unsigned len;				// len sectors
  unsigned drive;			// on this drive
} map_entry_t;

typedef struct {
  unsigned file_size;			// size of file to map in sectors
  map_entry_t *map;			// array of map entries
  unsigned map_len;			// length of that array
  unsigned char *map_image;		// encoded map
  unsigned map_image_len;		// length of encoded map in bytes
  dev_info_t *drive[MAX_DRIVES];	// drive infos
} map_t;

typedef struct {
  uint64_t id;				// id, increments with each sector
  uint64_t next;			// pointer to next sector
} sector_head_t;

typedef struct __attribute ((packed)) {
  uint64_t magic;			// our magic id
  unsigned char drive_map[MAX_DRIVES];	// last drive assignments
  uint16_t bdr_size;			// sectors
  uint16_t map_size;			// sectors
  uint16_t map_entries;			// entries in block map
  uint16_t bios_drive;			// emulated BIOS drive number
  uint64_t disk_size;			// disk size (in sectors)
  uint16_t disk_geo_cylinders;		// cylinders
  uint8_t disk_geo_heads;		// heads
  uint8_t disk_geo_sectors;		// sectors/track
  uint16_t flags;			// bit 0: edd enabled
} bdr_head_t;

typedef struct {
  sector_head_t s_h;
  bdr_head_t bdr_h;
  map_entry_t *start;
  map_t *map;
} bdr_location_t;

void help(void);
void print_bdr(bdr_location_t *bdr);
bdr_location_t *find_mapping(const char *file, int first_only);
int add_mapping(const char *file);
map_t *bmap(const char *file);
dev_info_t *free_dev_info(dev_info_t *di);
dev_info_t *dev_check(char *sysfs_dir, char *dev_name, unsigned dev_num);
dev_info_t *dev_info(unsigned dev_num);
loop_info_t *free_loop_info(loop_info_t *li);
loop_info_t *dev_loop_info(const char *dev_name);
int sys_scanf(const char *dir, const char *name, const char *format, ...) __attribute__ ((format (scanf, 3, 4)));
map_entry_t *free_map_entry(map_entry_t *m);
map_t *free_map(map_t *map);
map_entry_t *map_sector(map_t *map, uint64_t sector);
uint64_t urandom(void);
uint64_t encode_map_entry(map_entry_t *m);
map_entry_t *decode_map_entry(uint64_t num);
void encode_map(map_t *map);
int verify_map(const char *file, map_t *map, int check_crc);
unsigned calc_crc(unsigned char *buf);
int store_mbr(const char *mbr, bdr_location_t *bdr);
char *mnt_image(const char *file);
int umnt_image(const char *file, char *mp);
int read_sector(map_t *map, map_entry_t *m, unsigned char *buf);
char *bios_drive_to_str(uint16_t bd);
char *flags_to_str(unsigned flags);


struct option options[] = {
  { "verbose",    0, NULL,  'v' },
  { "test",       1, NULL, 1000 },
  { "map-file",   0, NULL, 1001 },
  { "create-map", 0, NULL, 1002 },
  { "verify-map", 0, NULL, 1003 },
  { "add-to-mbr", 1, NULL, 1004 },
  { "bios",       1, NULL, 1005 },
  { "geo",        1, NULL, 1006 },
  { "flags",      1, NULL, 1007 },
  { "help",       0, NULL,  'h' },
  { }
};

struct {
  unsigned verbose;
  unsigned map_file:1;
  unsigned create_map:1;
  unsigned verify_map:1;
  unsigned bios;
  unsigned heads;
  unsigned secs_pt;
  unsigned flags;
  uint64_t test;
  char *image;
  char *mbr;
} opt = { test: -1, bios: 0x80, heads: 64, secs_pt: 16, flags: 3 };

int main(int argc, char **argv)
{
  int i;
  unsigned u, u1;
  char *s, *t;
  bdr_location_t *bdr;

  if(sizeof (bdr_head_t) != 0x2e) {
    fprintf(stderr, "bdr_head_t has wrong size: %d\n", (int) sizeof (bdr_head_t));
#if 1
    // make ld fail
    extern void wrong_struct_size(void);
    wrong_struct_size();
#endif
    return 1;
  }

  opterr = 0;

  while((i = getopt_long(argc, argv, "v", options, NULL)) != -1) {
    switch(i) {
      case 'v':
        opt.verbose++;
        break;

      case 1000:
        opt.test = strtoull(optarg, NULL, 0);
        break;

      case 1001:
        opt.map_file = 1;
        break;

      case 1002:
        opt.create_map = 1;
        break;

      case 1003:
        opt.verify_map = 1;
        break;

      case 1004:
        opt.mbr = optarg;
        break;

      case 1005:
        u = 0;
        s = optarg;
        if(*s == '+' || *s == '-') {
          u = 0x8000;
          s++;
        }
        i =  strtol(optarg, &s, 0);
        if(*s) {
          fprintf(stderr, "invalid bios drive spec\n");
          return 1;
        }
        u += i & 0xff;
        opt.bios = u;
        break;

      case 1006:
        s = optarg;
        u = u1 = 0;
        u1 =  strtoul(s, &s, 0);
        if(*s == ',' || *s == '/') {
          u =  strtoul(s + 1, &s, 0);
        }
        if(!u || !u1 || *s) {
          fprintf(stderr, "invalid geometry\n");
          return 1;
        }
        opt.heads = u1;
        opt.secs_pt = u;
        break;

      case 1007:
        s = optarg;
        while((t = strsep(&s, ","))) {
          if(!strcmp(t, "+edd")) opt.flags |= 1;
          else if(!strcmp(t, "-edd")) opt.flags &= ~1;
          else if(!strcmp(t, "rw")) opt.flags |= 2;
          else if(!strcmp(t, "ro")) opt.flags &= ~2;
          else {
            fprintf(stderr, "invalid flag\n");
            return 1;
          }
        }
        break;

      default:
        help();
        return 0;
    }
  }

  argc -= optind; argv += optind;

  if(argc != 1) {
    help();

    return 1;
  }

  opt.image = *argv;

  if(opt.map_file) {
    return bmap(opt.image) ? 0 : 1;
  }

  if(opt.create_map) {
    if(!add_mapping(opt.image)) return 1;
    printf("mapping info created\n");
  }

  if(opt.verify_map) {
    bdr = find_mapping(opt.image, 0);

    if(bdr) {
      print_bdr(bdr);
    }
    else {
      printf("%s: no map\n", opt.image);
    }

    if(!bdr) return 1;
  }

  if(opt.mbr) {
    bdr = find_mapping(opt.image, 0);

    if(bdr) {
      print_bdr(bdr);

      i = store_mbr(opt.mbr, bdr);

      if(i) printf("\n%s: mbr updated\n", opt.mbr);

      return i ? 0 : 1;
    }
    else {
      printf("%s: no map\n", opt.image);
    }

    if(!bdr) return 1;
  }

  return 0;
}


void help()
{
  fprintf(stderr, "%s",
    "Usage: bdr [options] IMAGE_FILE\n"
    "\nOptions:\n"
    "  --create-map                Create block map of IMAGE_FILE and store it in IMAGE_FILE.\n"
    "  --verify-map                Verify map stored in IMAGE_FILE.\n"
    "  --add-to-mbr DEVICE         Write boot code to DEVICE that points to IMAGE_FILE.\n"
    "  --bios DRIVE_NR             Set BIOS drive number.\n"
    "  --geo HEADS,SECTORS         Set drive geometry.\n"
    "  --map-file                  Show block map of IMAGE_FILE.\n"
    "  --verbose                   Be more verbose.\n"
  
  );
}


void print_bdr(bdr_location_t *bdr)
{
  unsigned mt;

  if(!bdr) return;

  mt = bdr->s_h.id >> 32;
  mt = (mt ^ (mt >> 16)) & 0xffff;

  printf(
    "%s: mapping found\n"
    "        id: %016llx\n"
    "      date: %u/%u/%u\n"
    "bios drive: %s\n"
    " disk size: %llu sectors\n"
    "  disk geo: chs %u/%u/%u\n"
    "     flags: %s\n"
    "     drive: %u = %s\n"
    "    sector: %llu\n",
    opt.image,
    (unsigned long long) bdr->s_h.id,
    mt & 0x1f, (mt >> 5) & 0xf, 2000 + (mt >> 9),
    bios_drive_to_str(bdr->bdr_h.bios_drive),
    (unsigned long long) bdr->bdr_h.disk_size,
    bdr->bdr_h.disk_geo_cylinders,
    bdr->bdr_h.disk_geo_heads,
    bdr->bdr_h.disk_geo_sectors,
    flags_to_str(bdr->bdr_h.flags),
    bdr->start->drive,
    bdr->map->drive[bdr->start->drive]->name,
    (unsigned long long) bdr->start->start
  );
}


bdr_location_t *find_mapping(const char *file, int first_only)
{
  bdr_location_t *bdr = NULL;
  map_t *map1 = NULL, *map2 = NULL;
  int fd, ok = 0, maps_found = 0, maps_ok = 0;
  unsigned char buf[SECTOR_SIZE];
  unsigned u2, mt;
  sector_head_t s_h, s0_h;
  bdr_head_t bdr_h;
  unsigned char *bdr_image = NULL, *map_image = NULL;
  char *mp = NULL, *map_name = NULL;
  unsigned bdr_image_len, map_image_len;
  map_entry_t *m1 = NULL, *m2 = NULL;

  fd = open(file, O_RDONLY | O_LARGEFILE);
  if(fd < 0) {
    perror(file);
    return NULL;
  }

  map1 = bmap(file);

  if(!map1) {
    close(fd);
    return NULL;
  }

  mp = mnt_image(file);
  if(!mp) return NULL;

  asprintf(&map_name, "%s/bdr.map", mp);
  map2 = bmap(map_name);

  umnt_image(map_name, mp);
  free(map_name); map_name = NULL;

  m1 = map_sector(map2, 0);
  if(m1) m2 = map_sector(map1, m1->start);

  if(read_sector(map1, m2, buf)) ok = 1;

  if(ok) {
    memcpy(&s_h, buf, sizeof s_h);
    memcpy(&s0_h, buf, sizeof s0_h);
    memcpy(&bdr_h, buf + sizeof s_h, sizeof bdr_h);

    ok = 0;

    if(bdr_h.magic == BDR_MAGIC && !calc_crc(buf)) {
      if(bdr_h.bdr_size && bdr_h.map_size) {
        bdr_image_len = (bdr_h.bdr_size + bdr_h.map_size) * SECTOR_SIZE;
        bdr_image = calloc(1, bdr_image_len);
        memcpy(bdr_image, buf, SECTOR_SIZE);
        ok = 1;
        for(u2 = 1; u2 < bdr_h.bdr_size + bdr_h.map_size; u2++) {
          m2->start = DECODE_START(s_h.next);
          if(!read_sector(map1, m2, bdr_image + u2 * SECTOR_SIZE)) ok = 0;
          if(calc_crc(bdr_image + u2 * SECTOR_SIZE)) { ok = 0; break; }
          memcpy(&s_h, bdr_image + u2 * SECTOR_SIZE, sizeof s_h);
        }
      }
    }

    if(ok) {
      maps_found++;

      mt = s0_h.id >> 32;
      mt = (mt ^ (mt >> 16)) & 0xffff;

      if(opt.verbose >= 1) {
        fprintf(stderr,
          "%s: map at sector %llu:\n"
          "    id: %16llx\n"
          "  date: %u/%u/%u\n"
          "  size: %u sectors (bdr %u, map %u)\n"
          "   map: %u entries\n",
          file, (unsigned long long) m1->start, (unsigned long long) s0_h.id,
          mt & 0x1f, (mt >> 5) & 0xf, 2000 + (mt >> 9),
          bdr_image_len / SECTOR_SIZE,
          bdr_h.bdr_size, bdr_h.map_size,
          bdr_h.map_entries
        );
      }

      ok = 0;

      // fprintf(stderr, "%u %u, %u %u\n", bdr_h.map_entries, map1->map_len, bdr_h.map_size, map1->map_image_len / SECTOR_SIZE);

      if(
        bdr_h.map_entries == map1->map_len &&
        bdr_h.map_size == map1->map_image_len / SECTOR_SIZE
      ) {
        map_image_len = bdr_h.map_size * SECTOR_SIZE;
        map_image = calloc(1, map_image_len);
        memcpy(map_image, bdr_image + bdr_h.bdr_size * SECTOR_SIZE, map_image_len);

        for(u2 = 0; u2 < map_image_len; u2 += SECTOR_SIZE) {
          memset(map_image + u2, 0, sizeof s_h);
        }

        if(!memcmp(map_image, map1->map_image, map_image_len)) ok = 1;

        free(map_image); map_image = NULL;
      }

      if(ok) {
        maps_ok++;
        if(!bdr) {
          bdr = calloc(1, sizeof *bdr);
          bdr->map = map1;
          bdr->s_h = s0_h;
          bdr->bdr_h = bdr_h;
          bdr->start = map_sector(map1, m1->start);
        }

        if(opt.verbose >= 1) fprintf(stderr, "map ok\n");
      }
      else {
        if(opt.verbose >= 1) fprintf(stderr, "map outdated\n");
      }
    }

    if(bdr_image) {
      free(bdr_image);
      bdr_image = NULL;
    }
  }

  m1 = free_map_entry(m1);
  m2 = free_map_entry(m2);

  close(fd);

  if(!bdr) free_map(map1);

  free_map(map2);

  return bdr;
}


int add_mapping(const char *file)
{
  map_t *map = NULL, *map2 = NULL;
  map_entry_t *m = NULL, *m2 = NULL;
  unsigned char *bdr_image;
  unsigned bdr_image_len, u, u1, u2, u3, crc;
  int i, fd, ok = 0;
  uint64_t id, id1;
  struct tm *tms;
  time_t tt;
  char *map_name = NULL, *mp = NULL;
  sector_head_t s_h = { };
  bdr_head_t bdr_h = { magic: BDR_MAGIC };

  id = urandom() & ~(1ll << 31);

  time(&tt);
  tms = gmtime(&tt);

  id1 = (((tms->tm_year - 100) & 0x7f) << 9) + ((tms->tm_mon + 1) << 5) + tms->tm_mday;
  id1 ^= (id >> 48) ^ ((id >> 32) & 0xffff);
  id1 <<= 32;
  id ^= id1;

  map = bmap(file);

  if(!map) return 0;

  bdr_h.bdr_size = (
    sizeof bdr_h + &bdrive_end - &bdrive_start + SECTOR_SIZE - sizeof s_h - 1
  ) / (SECTOR_SIZE - sizeof s_h);

  bdr_image_len = bdr_h.bdr_size * SECTOR_SIZE + map->map_image_len;
  bdr_image = calloc(1, bdr_image_len);

  memcpy(bdr_image + bdr_h.bdr_size * SECTOR_SIZE, map->map_image, map->map_image_len);

  bdr_h.map_size = map->map_image_len / SECTOR_SIZE;
  bdr_h.map_entries = map->map_len;
  bdr_h.bios_drive = opt.bios;
  bdr_h.disk_size = map->file_size;
  bdr_h.flags = opt.flags;
  bdr_h.disk_geo_heads = opt.heads;
  bdr_h.disk_geo_sectors = opt.secs_pt;
  u = bdr_h.disk_size / (opt.heads * opt.secs_pt);
  bdr_h.disk_geo_cylinders = u > 1024 ? 1024 : u;

  memcpy(bdr_image + sizeof s_h, &bdr_h, sizeof bdr_h);
  u = &bdrive_end - &bdrive_start;
  if(u > SECTOR_SIZE - sizeof s_h - sizeof bdr_h) u = SECTOR_SIZE - sizeof s_h - sizeof bdr_h;
  memcpy(bdr_image + sizeof s_h + sizeof bdr_h, &bdrive_start, u);
  u3 = u;
  u = &bdrive_end - &bdrive_start;
  for(u2 = SECTOR_SIZE + sizeof s_h; u3 < u; u2 += SECTOR_SIZE, u3 += SECTOR_SIZE - sizeof s_h) {
    u1 = u - u3;
    if(u1 > SECTOR_SIZE - sizeof s_h) u1 = SECTOR_SIZE - sizeof s_h;
    memcpy(bdr_image + u2, &bdrive_start + u3, u1);
  }

  mp = mnt_image(file);

  if(!mp) return 0;

  asprintf(&map_name, "%s/bdr.map", mp);

  fd = open(map_name, O_WRONLY | O_TRUNC | O_CREAT, 0644);
  if(fd >= 0) {
    u = write(fd, bdr_image, bdr_image_len);
    fdatasync(fd);
    close(fd);
    if(u == -1) perror(map_name);
    if(u == bdr_image_len) ok = 1;
  }

  if(ok) {
    // now, map the mapfile

    if(!(map2 = bmap(map_name))) {
      ok = 0;
    }
    else {
      u2 = bdr_image_len / SECTOR_SIZE;
      for(u = 0; ok && u < u2; u++) {
        m = map_sector(map2, (u + 1 == u2 ? u : u + 1));
        if(m) {
          m2 = map_sector(map, m->start);
        }
        if(m2) {
          s_h.id = id++;
          s_h.next = ENCODE_START(u + 1 == u2 ? 0 : m2->start);
          memcpy(bdr_image + u * SECTOR_SIZE, &s_h, sizeof s_h);
          crc = calc_crc(bdr_image + u * SECTOR_SIZE);
          s_h.next += ENCODE_CRC(-crc);
          memcpy(bdr_image + u * SECTOR_SIZE, &s_h, sizeof s_h);
        }
        else {
          ok = 0;
        }
        m2 = free_map_entry(m2);
        m = free_map_entry(m);
      }
    }
  }

  if(ok) {
    ok = 0;
    fd = open(map_name, O_WRONLY);
    if(fd >= 0) {
      u = write(fd, bdr_image, bdr_image_len);
      fdatasync(fd);
      close(fd);
      if(u == bdr_image_len) ok = 1;
    }
  }

  if(ok && !verify_map(map_name, map2, 1)) {
    fprintf(stderr, "%s: oops, mapping changed unexpectedly\n", map_name);
    ok = 0;
  }

  map2 = free_map(map2);

  map = free_map(map);

  free(map_name); map_name = NULL;

  i = umnt_image(file, mp);

  return i;
}


map_t *bmap(const char *file)
{
  int fd, warn_hole = 0;
  struct stat64 sbuf;
  uint64_t size;
  unsigned u, u2, block, block_size, blocks, block2, blocks2;
  dev_info_t *di = NULL;
  map_entry_t *m = NULL;
  map_t *map1 = NULL, *map2 = NULL;

  // O_ACCMODE O_RDONLY, O_RDWR
  fd = open(file, O_RDONLY | O_LARGEFILE);
  if(fd < 0) {
    perror(file);
    return NULL;
  }

  fdatasync(fd);

  if(fstat64(fd, &sbuf)) {
    perror(file);
    close(fd);
    return NULL;
  }

  if(ioctl(fd, FIGETBSZ, &block_size)) {
    perror(file);
    close(fd);
    return NULL;
  }

  if(block_size < SECTOR_SIZE) return NULL;

  size = sbuf.st_size;

  if(size & (SECTOR_SIZE - 1)) {
    fprintf(stderr, "%s: file size not multiple of sector size\n", file);
    return NULL;
  }

  blocks = (size + block_size - 1) / block_size;

  if(opt.verbose >= 2) {
    fprintf(stderr,
      "%s:\n  size = %lld (%u blocks)\n  map block size = %u\n  dev = %08x\n",
      file, (long long) size, blocks, block_size, (unsigned) sbuf.st_dev
    );
  }

  if(!blocks) {
    fprintf(stderr, "no blocks to map\n");
    close(fd);
    return NULL;
  }

  map1 = calloc(1, sizeof *map1);
  map1->map = calloc(map1->map_len = blocks, sizeof *map1->map);

  map2 = calloc(1, sizeof *map2);
  map2->map = calloc(map2->map_len = blocks, sizeof *map2->map);

  if(!(di = dev_info(sbuf.st_dev))) {
    fprintf(stderr, "failed to detect device\n");
    close(fd);
    return NULL;
  }

  map1->drive[0] = di;

  if(opt.verbose >= 3) {
    fprintf(stderr, "block map:\n");
  }

  for(block = 0; block < blocks; block++) {
    u = block;
    if(ioctl(fd, FIBMAP, &u)) {
      fprintf(stderr, "failed to map block %u\n", block);
      close(fd);
      return NULL;
    }

    if(u == 0 && !warn_hole) {
      fprintf(stderr, "Warning: %s: file has holes\n", file);
      warn_hole = 1;
    }

    if(opt.verbose >= 3) fprintf(stderr, "%8u -> %8u\n", block, u);

    if(u) {
      map1->map[block].start = u * (block_size / SECTOR_SIZE) + di->start + di->loop_start;
    }
    else {
      map1->map[block].start = 0;
    }
    map1->map[block].len = block_size / SECTOR_SIZE;
    map1->map[block].drive = 0;
  }

  close(fd);

  memcpy(&map2->drive, &map1->drive, sizeof map2->drive);
  memset(&map1->drive, 0, sizeof map1->drive);

  map2->map[0] = map1->map[0];
  for(block = 1, block2 = 0; block < blocks; block++) {
    if(
      map1->map[block].drive == map2->map[block2].drive &&
      (
        (map1->map[block].start == map2->map[block2].start + map2->map[block2].len) ||
        (map1->map[block].start == 0 && map2->map[block2].start == 0)	// holes
      )
    ) {
      map2->map[block2].len += map1->map[block].len;
    }
    else {
      map2->map[++block2] = map1->map[block];
    }
  }

  blocks2 = block2 + 1;

  for(u = blocks = 0; u < blocks2; u++) {
    blocks += (map2->map[u].len + MAX_MAP_LEN - 1) / MAX_MAP_LEN;
  }

  map1 = free_map(map1);
  map1 = calloc(1, sizeof *map1);
  map1->map = calloc(map1->map_len = blocks, sizeof *map1->map);

  memcpy(&map1->drive, &map2->drive, sizeof map1->drive);
  memset(&map2->drive, 0, sizeof map2->drive);

  for(block = block2 = 0; block2 < blocks2; block2++) {
    u2 = (map2->map[block2].len + MAX_MAP_LEN - 1) / MAX_MAP_LEN;
    for(u = 0; u < u2; u++, block++) {
      map1->map[block] = map2->map[block2];
      if(map1->map[block].len > MAX_MAP_LEN) map1->map[block].len = MAX_MAP_LEN;
      map2->map[block2].len -= MAX_MAP_LEN;
      map2->map[block2].start += MAX_MAP_LEN;
    }
  }

  map2 = free_map(map2);

  map1->file_size = (size + SECTOR_SIZE - 1)/SECTOR_SIZE;

  if(opt.verbose >= 1) {
    printf("sector map:\n  drive      start   len\n");
    for(block = 0; block < blocks; block++) {
      printf("     %2u %10llu %5u\n",
        map1->map[block].drive,
        (unsigned long long) map1->map[block].start,
        map1->map[block].len
      );
    }
  }

  if(opt.test != -1ll) {
    m = map_sector(map1, opt.test);
    if(m) {
      printf("%s[%llu] -> %s[%llu]\n",
        file, (unsigned long long) opt.test,
        di->name, (unsigned long long) m->start
      );
    }
    else {
      printf("%s[%llu] -> ?\n", file, (unsigned long long) opt.test);
    }
    m = free_map_entry(m);
  }

  if(!verify_map(file, map1, 0)) {
    fprintf(stderr, "%s: oops, map not correct\n", file);
    return NULL;
  }

  encode_map(map1);

  return map1;
}


dev_info_t *free_dev_info(dev_info_t *di)
{
  if(di) {
    free(di->name);
    free(di);
  }

  return NULL;
}


dev_info_t *dev_check(char *sysfs_dir, char *dev_name, unsigned dev_num)
{
  unsigned major, minor;
  dev_info_t *di = NULL;
  loop_info_t *li = NULL;
  unsigned dev_id;
  unsigned long long u;
  char *cname = NULL, *s;

  if(sys_scanf(sysfs_dir, "dev", "%u:%u", &major, &minor) == 2) {
    dev_id = (major << 8) + (minor & 0xff);
    if(dev_num == dev_id) {
      di = calloc(1, sizeof *di);
      di->dev_num = dev_num;
      asprintf(&di->name, "/dev/%s", dev_name);
      if(sys_scanf(sysfs_dir, "size", "%llu", &u) == 1) di->size = u;
      if(sys_scanf(sysfs_dir, "start", "%llu", &u) == 1) di->start = u;
      if(di->start) {
        cname = canonicalize_file_name(sysfs_dir);
        if((s = strrchr(cname, '/'))) {
          *s = 0;
          if(sys_scanf(cname, "dev", "%u:%u", &major, &minor) == 2) {
            if((s = strrchr(cname, '/'))) {
              free(di->name);
              asprintf(&di->name, "/dev/%s", s + 1);
            }
          }
        }
        free(cname);
        cname = NULL;
      }
      if(major == 7) {	// loop
        if((li = dev_loop_info(di->name))) {
          if(li->file_name) {
            free(di->name);
            di->name = strdup(li->file_name);
          }
          if(li->offset & (SECTOR_SIZE - 1)) {
            fprintf(stderr, "Warning: loop offset not block aligned!\n");
            di = free_dev_info(di);
          }
          else {
            di->loop_start = li->offset / SECTOR_SIZE;
          }
          li = free_loop_info(li);
        }
      }

      di->min = di->start + di->loop_start;
      di->max = di->min + di->size - 1;

      if(opt.verbose >= 2) {
        fprintf(stderr, "  %s: %08x, start = %llu+%llu, size = %llu\n",
          di->name,
          di->dev_num,
          (unsigned long long) di->start,
          (unsigned long long) di->loop_start,
          (unsigned long long) di->size
        );
      }
    }
  }

  return di;
}


dev_info_t *dev_info(unsigned dev_num)
{
  DIR *d;
  struct dirent *de;
  char *dname;
  dev_info_t *di = NULL;
  FILE *f;
  char *s, buf[256];

  d = opendir("/sys/class/block");
  if(d) {	// new sysfs style
    while((de = readdir(d))) {
      if(*de->d_name == '.') continue;
      asprintf(&dname, "/sys/class/block/%s", de->d_name);
      di = dev_check(dname, de->d_name, dev_num);
      free(dname);
      if(di) break;
    }
    closedir(d);
  }
  else {	// old sysfs style
    f = popen("find /sys/block -name dev", "r");
    if(f) {
      while(fgets(buf, sizeof buf, f)) {
        if((s = strrchr(buf, '/'))) {
          *s = 0;
          if((s = strrchr(buf, '/'))) {
            di = dev_check(buf, s + 1, dev_num);
            if(di) break;
          }
        }
      }
      pclose(f);
    }
  }

  return di;
}


loop_info_t *free_loop_info(loop_info_t *li)
{
  if(li) {
    free(li->file_name);
    free(li);
  }

  return NULL;
}


loop_info_t *dev_loop_info(const char *dev_name)
{
  struct loop_info64 li64 = {};
  int fd;
  char tmp[LO_NAME_SIZE];
  loop_info_t *li = NULL;

  fd = open(dev_name, O_RDONLY | O_LARGEFILE);
  if(fd >= 0) {
    if(!ioctl(fd, LOOP_GET_STATUS64, &li64)) {
      li = calloc(1, sizeof *li);
      li->offset = li64.lo_offset;
      memcpy(tmp, li64.lo_file_name, LO_NAME_SIZE);
      tmp[LO_NAME_SIZE - 1] = 0;
      if(strlen(tmp) < LO_NAME_SIZE - 1) li->file_name = strdup(tmp);	// else too long
    }

    close(fd);
  }

  return li;
}


int sys_scanf(const char *dir, const char *name, const char *format, ...)
{
  char *fname;
  FILE *f;
  int i = 0;
  va_list args;

  asprintf(&fname, "%s/%s", dir, name);

  if((f = fopen(fname, "r"))) {
    va_start(args, format);
    i = vfscanf(f, format, args);
    va_end(args);
    
    fclose(f);
  }

  free(fname);
  
  return i;
}


map_entry_t *free_map_entry(map_entry_t *m)
{
  if(m) {
    free(m);
  }

  return NULL;
}


map_t *free_map(map_t *map)
{
  if(map) {
    free(map->map);
    free(map->map_image);
  }

  return NULL;
}


map_entry_t *map_sector(map_t *map, uint64_t sector)
{
  unsigned u;
  map_entry_t *m = NULL;

  if(!map) return NULL;

  for(u = 0; u < map->map_len; u++) {
    if(sector < map->map[u].len) {
      m = calloc(1, sizeof *m);
      m->drive = map->map[u].drive;
      m->len = 1;
      if(map->map[u].start) {
        m->start = map->map[u].start + sector;
      }
      else {
        m->start = 0;	// hole
      }
      break;
    }
    sector -= map->map[u].len;
  }

  return m;
}


uint64_t urandom()
{
  int fd, i;
  uint64_t u = 0;

  fd = open("/dev/urandom", O_RDONLY);
  if(fd >= 0) {
    i = read(fd, &u, sizeof u);
    if(i != sizeof u) u = 0;
    close(fd);
  }

  return u;
}


uint64_t encode_map_entry(map_entry_t *m)
{
  return ENCODE_START(m->start) + ENCODE_LEN(m->len) + ENCODE_DRIVE(m->drive);
}


map_entry_t *decode_map_entry(uint64_t num)
{
  map_entry_t *m = calloc(1, sizeof *m);

  m->start = DECODE_START(num);
  m->len = DECODE_LEN(num);
  m->drive = DECODE_DRIVE(num);

  return m;
}


void encode_map(map_t *map)
{
  unsigned u, u2, map_sectors;
  uint64_t entry;

  // 62 map entries per sector
  map_sectors = (map->map_len + 61) / 62;

  map->map_image = calloc(map_sectors, SECTOR_SIZE);
  map->map_image_len = map_sectors * SECTOR_SIZE;

  for(u = u2 = 0; u < map->map_len; u++, u2++) {
    if(!(u % 62)) u2 += 2;	// new sector: skip two entries
    entry = encode_map_entry(map->map + u);
    memcpy(map->map_image + 8 * u2, &entry, 8);
  }
}


int verify_map(const char *file, map_t *map, int check_crc)
{
  dev_info_t *di;
  unsigned u;
  unsigned char buf1[SECTOR_SIZE], buf2[SECTOR_SIZE];
  int fd[MAX_DRIVES], fd_file;
  map_entry_t *m = NULL;
  int ok = 0, err = 0;

  if(!map) return 0;

  for(u = 0; u < map->map_len; u++) {
    if(!(di = map->drive[map->map[u].drive])) return 0;
    if(
      map->map[u].start &&
      (map->map[u].start < di->min || map->map[u].start + map->map[u].len - 1 > di->max)
    ) return 0;
  }

  fd_file = open(file, O_RDONLY | O_LARGEFILE);
  if(fd_file < 0) return 0;
  fdatasync(fd_file);

  ok = 1;

  for(u = 0; u < MAX_DRIVES; u++) {
    if((di = map->drive[u])) {
      fd[u] = open(di->name, O_RDONLY | O_LARGEFILE);
      if(fd[u] < 0) {
        ok = 0;
      }
      else {
        ioctl(fd[0], BLKFLSBUF, 0);
      }
    }
    else {
      fd[u] = -1;
    }
  }

  if(ok) {
    for(u = 0; ok && u < map->file_size; u++) {
      if(read(fd_file, buf1, sizeof buf1) != sizeof buf1) {
        ok = 0;
        break;
      }

      m = map_sector(map, u);

      if(m) {
        if(m->start) {
          if(lseek64(fd[m->drive], m->start * SECTOR_SIZE, 0) == (off64_t) -1) ok = 0;
          if(read(fd[m->drive], buf2, sizeof buf2) != sizeof buf2) ok = 0;
        }
        else {
          memset(buf2, 0, sizeof buf2);
        }
      }
      else {
        ok = 0;
      }

      if(ok && memcmp(buf1, buf2, sizeof buf1)) {
        // delay error to see all differences
        err = 1;
        fprintf(stderr, "oops: sectors differ: %s[%u] != %s[%llu]\n",
          file, u,
          map->drive[m->drive]->name,
          (unsigned long long) m->start
        );
      }

      m = free_map_entry(m);

      if(!ok) break;

      if(check_crc && calc_crc(buf1)) ok = 0;
    }
  }

  if(err) ok = 0;

  for(u = 0; u < MAX_DRIVES; u++) {
    if(fd[u] >= 0) close(fd[u]);
  }

  close(fd_file);

  return ok;
}


unsigned calc_crc(unsigned char *buf)
{
  unsigned crc = 0, u;
  unsigned short *us = (unsigned short *) buf;

  for(u = 0; u < 0x100; u++) {
    crc += us[u];
  }

  return crc & 0xffff;
}


int store_mbr(const char *mbr, bdr_location_t *bdr)
{
  unsigned char buf[SECTOR_SIZE];
  int fd, ok = 0;
  uint64_t s;

  fd = open(mbr, O_RDWR | O_LARGEFILE);
  if(fd < 0) {
    perror(mbr);
    return 0;
  }

  if(read(fd, buf, sizeof buf) == sizeof buf) {
    memcpy(buf, &mbr_start, 0x1b8);
    s = bdr->start->start;
    memcpy(buf + 0x1a8, &s, 8);
    memcpy(buf + 0x1b0, &bdr->s_h.id, 8);
    memcpy(buf + 0x1fe, &mbr_start + 0x1fe, 2);

    if(lseek64(fd, 0, 0) == (off64_t) -1) {
      perror(mbr);
    }
    else {
      if(write(fd, buf, sizeof buf) == sizeof buf) {
        ok = 1;
      }
      else {
        perror(mbr);
      }
    }
  }

  close(fd);

  return ok;
}


char *mnt_image(const char *file)
{
  char *mp = NULL, *buf = NULL;
  unsigned char mbr[SECTOR_SIZE];
  unsigned u, pstart, psize;
  int i, fd;

  fd = open(file, O_RDONLY | O_LARGEFILE);
  if(fd < 0) return NULL;
  u = read(fd, mbr, sizeof mbr);
  close(fd);

  if(u != sizeof mbr) return NULL;

  pstart = mbr[0x1be + 8] +
           (mbr[0x1be + 9] << 8) +
           (mbr[0x1be + 10] << 16) +
           (mbr[0x1be + 11] << 24);
  psize = mbr[0x1be + 12] +
          (mbr[0x1be + 13] << 8) +
          (mbr[0x1be + 14] << 16) +
          (mbr[0x1be + 15] << 24);

  if(
    mbr[0x1fe] != 0x55 ||
    mbr[0x1ff] != 0xaa ||
    !psize
  ) {
    fprintf(stderr, "%s: no/invalid partition table\n", file);
    return NULL;
  }

  if(opt.verbose >= 2) fprintf(stderr, "partition: start = %u, size = %u\n", pstart, psize);

  mp = strdup("/tmp/bdr.XXXXXX");
  if(!mkdtemp(mp)) {
    free(mp); return NULL;
  }

  asprintf(&buf, "mount -oloop,offset=%u %s %s", pstart * SECTOR_SIZE, file, mp);
  i = system(buf);
  free(buf); buf = NULL;

  if(i) {
    fprintf(stderr, "%s: mount failed\n", file);

    rmdir(mp);
    free(mp);
    return NULL;
  }

  return mp;
}


int umnt_image(const char *file, char *mp)
{
  char *buf = NULL;
  int i;

  if(!mp) return 1;

  asprintf(&buf, "umount %s", mp);

  i = system(buf);
  free(buf);

  rmdir(mp);
  free(mp);

  if(i) {
    if(file) fprintf(stderr, "%s: umount failed\n", file);
    return 0;
  }

  return 1;
}


int read_sector(map_t *map, map_entry_t *m, unsigned char *buf)
{
  int fd, ok = 0;
  char *file;
  unsigned len;

  if(!map || !m || !buf) return 0;

  file = map->drive[m->drive]->name;
  if(!file) return 0;

  fd = open(file, O_RDONLY | O_LARGEFILE);
  if(fd < 0) {
    perror(file);
    return 0;
  }

  if(lseek64(fd, m->start * SECTOR_SIZE, 0) != (off64_t) -1) ok = 1;

  len = m->len * SECTOR_SIZE;

  if(ok && read(fd, buf, len) == len) ok = 1;

  close(fd);

  return ok;
}


char *bios_drive_to_str(uint16_t bd)
{
  static char buf[32];
  int i;

  if((bd & 0x8000)) {
    i = bd & 0xff;
    if(i & 0x80) i += (-1 & ~0xff);
    sprintf(buf, "%+d", i);
  }
  else {
    sprintf(buf, "0x%02x", bd & 0xff);
  }

  return buf;
}


char *flags_to_str(unsigned flags)
{
  static char buf[256];

  sprintf(buf, "%cedd, %s",
    flags & 1 ? '+' : '-',
    flags & 2 ? "rw" : "ro"
  );

  return buf;
}


