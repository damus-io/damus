
#include "io.h"
#include "nostrdb.h"
#include <sys/mman.h>
#include <time.h>
#include <stdlib.h>

static int bench_parser(int times, const char *json, int len)
{
	static unsigned char buf[2<<18];

	struct timespec t1, t2;
	int i;
	long nanos, ms;
	struct ndb_note *note;

	clock_gettime(CLOCK_MONOTONIC, &t1);
	for (i = 0; i < times; i++) {
		if (!ndb_note_from_json(json, len, &note, buf, sizeof(buf))) {
			return 0;
		}
	}
	clock_gettime(CLOCK_MONOTONIC, &t2);

	nanos = (t2.tv_sec - t1.tv_sec) * (long)1e9 + (t2.tv_nsec - t1.tv_nsec);
	ms = nanos / 1e6;
	printf("ns/run\t%ld\nms/run\t%f\nns\t%ld\nms\t%ld\n",
		nanos/times, (double)ms/(double)times, nanos, ms);

	return 1;
}

int main(int argc, char *argv[], char **env)
{
	static const int alloc_size = 2 << 18;
	int times = 10000, len = 0;
	unsigned char buf[alloc_size];

	if (!read_file("testdata/contacts.json", buf, alloc_size, &len))
		return 1;

	if (argc >= 2)
		times = atoi(argv[1]);

	fprintf(stderr, "benching parser %d times\n", times);
	if (!bench_parser(times, (const char*)&buf[0], len))
		return 2;

	return 0;
}

