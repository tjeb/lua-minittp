#!/bin/sh

# This is part of the advance2 example; it takes the given command-line
# argument, and prints it in an eternal loop (using sleep(0.5))

PREFIX=shift
C=0
while [ 1 ]; do
    echo "$C\t$1";
    sleep 0.05;
    C=`expr $C + 1`
done
