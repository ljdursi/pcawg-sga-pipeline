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
qmake -l h_stack=32M -cwd -V -o ./$1.stdout -e ./$1.stderr -- -j 16 -f ../graph-concordance.make CASE=$1 >& graph-concordance.make.out
#make -n -f ../graph-concordance.make CASE=$1
cd ..
