#include "util.h"

#include <stdarg.h>
#include <stdio.h>
#include "tb_cxxrtl_io.h"

#define PRINTF_BUF_SIZE 256
void debug_printf(const char* fmt, ...) {
	char buf[PRINTF_BUF_SIZE];
	va_list args;
	va_start(args, fmt);
	vsnprintf(buf, PRINTF_BUF_SIZE, fmt, args);
	tb_puts(buf);
	va_end(args);
}
