

#include "io.h"
#include "nostrdb.h"
#include <sys/mman.h>
#include <time.h>
#include <stdlib.h>
#include <assert.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

int map_file(const char *filename, unsigned char **p, size_t *flen)
{
	struct stat st;
	int des;
	stat(filename, &st);
	*flen = st.st_size;

	des = open(filename, O_RDONLY);

	*p = mmap(NULL, *flen, PROT_READ, MAP_PRIVATE, des, 0);
	close(des);

	return *p != MAP_FAILED;
}

static int bench_parser()
{
	long nanos, ms;
	size_t written;
	struct ndb *ndb;
	struct timespec t1, t2;
	char *json;
	int times = 1;
	struct ndb_config config;
	ndb_default_config(&config);

	ndb_config_set_mapsize(&config, 1024ULL * 1024ULL * 400ULL * 10ULL);
	ndb_config_set_ingest_threads(&config, 8);
	ndb_config_set_flags(&config, NDB_FLAG_SKIP_NOTE_VERIFY);

	assert(ndb_init(&ndb, "testdata/db", &config));
	const char *filename = "testdata/many-events.json";
	if (!map_file(filename, (unsigned char**)&json, &written)) {
		printf("mapping testdata/many-events.json failed\n");
		return 2;
	}

	printf("mapped %ld bytes in %s\n", written, filename);

	clock_gettime(CLOCK_MONOTONIC, &t1);

	ndb_process_events(ndb, json, written);

	ndb_destroy(ndb);

	clock_gettime(CLOCK_MONOTONIC, &t2);

	nanos = (t2.tv_sec - t1.tv_sec) * (long)1e9 + (t2.tv_nsec - t1.tv_nsec);
	ms = nanos / 1e6;
	printf("ns/run\t%ld\nms/run\t%f\nns\t%ld\nms\t%ld\n",
		nanos/times, (double)ms/(double)times, nanos, ms);

	return 1;
}

int main(int argc, char *argv[], char **env)
{
	if (!bench_parser())
		return 2;
	
	return 0;
}

