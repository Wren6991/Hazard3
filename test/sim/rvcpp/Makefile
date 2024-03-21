SRCS=$(wildcard *.cpp)
EXECUTABLE:=rvcpp

.SUFFIXES:
.PHONY: all clean

all:
	g++ -std=c++17 -O3 -Wall -Wno-parentheses -I $(PWD)/include $(SRCS) -o $(EXECUTABLE)

clean:
	rm -f $(EXECUTABLE)
