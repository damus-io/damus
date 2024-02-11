
#if defined(_WIN32) || defined(_WIN64)
	#include <windows.h>
#elif defined(__linux__)
	#include <unistd.h>
#elif defined(__APPLE__)
	#include <sys/types.h>
	#include <sys/sysctl.h>
#else
	#error "Unsupported platform"
#endif

static inline int get_cpu_cores() {
	int num_cores = 0;

	// Windows
	#if defined(_WIN32) || defined(_WIN64)
		SYSTEM_INFO sysinfo;
		GetSystemInfo(&sysinfo);
		num_cores = sysinfo.dwNumberOfProcessors; // This returns logical processors
		// Further use GetLogicalProcessorInformation for physical cores...
	// Linux
	#elif defined(__linux__)
		num_cores = sysconf(_SC_NPROCESSORS_ONLN); // This returns logical processors
	// macOS
	#elif defined(__APPLE__)
		size_t size = sizeof(num_cores);
		sysctlbyname("hw.physicalcpu", &num_cores, &size, NULL, 0);
	#else
		num_cores = 2; // Unsupported platform
	#endif

	return num_cores;
}
