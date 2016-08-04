SHELL=/bin/bash -o pipefail
SGA=/u/jdursi/sw/sga/bin/sga
SAMTOOLS=/u/jdursi/sw/sga-extra/samtools/samtools
# do not delete intermediate files
.SECONDARY:
# delete files when a command fails
.DELETE_ON_ERROR:

############################
# File paths
############################
REFERENCE=/.mounts/labs/simpsonlab/data/references/hs37d5.pp.fa

all: $(CASE).normal.bwt $(CASE).tumor.bwt $(CASE).normal.sai $(CASE).tumor.sai $(CASE).sga.calls.vcf

############################
# sga calling
############################

# Preprocess the variant input bam files
%.fastq.gz: %.bam
	SGE_RREQ="-l h_vmem=96G -l h_stack=32M" /u/jdursi/sw/sga-extra/bam2fastq/bam2fastq --pairs-to-stdout $< | $(SGA) preprocess --pe-mode 2 - | gzip >> $@

# Build an FM-index for reads
# was: 38*4, 19*8
%.bwt: %.fastq.gz
	SGE_RREQ="-l h_vmem=24G -l h_stack=32M -pe smp 4" /usr/bin/time -v $(SGA) index -a ropebwt -t 4 --no-reverse --no-sai $<

%.sai: %.fastq.gz %.bwt
	SGE_RREQ="-l h_vmem=16G -l h_stack=32M -pe smp 8" /usr/bin/time -v $(SGA) gen-ssa --sai-only -t 8 $<

# Make SGA calls
$(CASE).sga.calls.vcf: $(CASE).tumor.bwt $(CASE).tumor.sai $(CASE).normal.bwt $(CASE).normal.sai $(CASE).normal.fastq.gz $(CASE).tumor.fastq.gz
	SGE_RREQ="-l h_vmem=19G -l h_stack=32M -pe smp 8" /usr/bin/time -v $(SGA) graph-diff -p $(CASE).sga --min-dbg-count 2 -k 55 -x 4 -t 8 -a debruijn -r $(CASE).tumor.fastq.gz -b $(CASE).normal.fastq.gz --ref $(REFERENCE)

