SRCS=$(wildcard *.cpp)
EXECUTABLE:=rvcpp

.SUFFIXES:
.PHONY: all clean tb

all:
	g++ -std=c++17 -O3 -Wall -Wextra -I include $(SRCS) -o $(EXECUTABLE)

# To match tb_cxxrtl/Makefile:
tb: all

clean:
	rm -f $(EXECUTABLE)
