#!/bin/bash
if [ -z "$1" -o ! -d "$1" ]
then
    echo "Usage: $0 directory"
    exit
fi

cd $1
pwd
module purge
module load gcc/4.8.1 use.own sga/sga sga-extra
qmake -l h_stack=32M -cwd -V -o ./stdout -e ./stderr -- -j 16 -f ../index.make CASE=$1 >& index.make.out
#qmake -n -f ../index.make CASE=$1
cd ..
