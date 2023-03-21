SRCS=$(wildcard *.cpp)
EXECUTABLE:=rvcpp

.SUFFIXES:
.PHONY: all clean

all:
	g++ -std=c++17 -O3 -Wall -Wno-parentheses $(SRCS) -o $(EXECUTABLE)

clean:
	rm -f $(EXECUTABLE)
