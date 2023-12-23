
#include <stdio.h>

static int read_fd(FILE *fd, unsigned char *buf, int buflen, int *written)
{
	unsigned char *p = buf;
	int len = 0;
	*written = 0;

	do {
		len = fread(p, 1, 4096, fd);
		*written += len;
		p += len;
		if (p > buf + buflen)
			return 0;
	} while (len == 4096);

	return 1;
}

static int write_file(const char *filename, unsigned char *buf, int buflen)
{
	FILE *file = NULL;
	int ok;

	file = fopen(filename, "w");
	if (file == NULL)
		return 0;

	ok = fwrite(buf, buflen, 1, file);
	fclose(file);
	return ok;
}

static int read_file(const char *filename, unsigned char *buf, int buflen, int *written)
{
	FILE *file = NULL;
	int ok;

	file = fopen(filename, "r");
	if (file == NULL)
		return 1;

	ok = read_fd(file, buf, buflen, written);
	fclose(file);
	return ok;
}

