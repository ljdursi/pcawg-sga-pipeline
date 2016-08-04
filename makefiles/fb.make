SHELL=/bin/bash -o pipefail
FB=/u/jdursi/sw/sga-extra/freebayes/bin/freebayes

# do not delete intermediate files
.SECONDARY:
# delete files when a command fails
.DELETE_ON_ERROR:

############################
# File paths
############################
REFERENCE=/.mounts/labs/simpsonlab/data/references/hs37d5.pp.fa

all: $(CASE).new.freebayes.allchr.germline.vcf $(CASE).new.freebayes.allchr.somatic.vcf $(CASE).old.freebayes.allchr.germline.vcf $(CASE).old.freebayes.allchr.somatic.vcf

############################
# freebayes calling
############################

BASE_BAM:=$(CASE).normal.bam
VARIANT_BAM:=$(CASE).tumor.bam

BASE_SAMPLE_NAME:=$(shell samtools view -H $(BASE_BAM) | grep "^@RG" | grep SM: | sed -e 's/.*SM:\([^[:space:]]*\).*/\1/' | sort | uniq )
VARIANT_SAMPLE_NAME:=$(shell samtools view -H $(VARIANT_BAM) | grep "^@RG" | grep SM: | sed -e 's/.*SM:\([^[:space:]]*\).*/\1/' | sort | uniq )

bychrom:
	mkdir $@

# Run freebayes on each chromosome independently
bychrom/$(CASE).old.freebayes.%.calls.vcf: 
	SGE_RREQ="-l h_vmem=8G -l h_stack=32M " /usr/bin/time -v $(FB) -r $* -f $(REFERENCE) --pooled-discrete --pooled-continuous --min-alternate-fraction 0.1 --allele-balance-priors-off --genotype-qualities $(CASE).tumor.bam $(CASE).normal.bam > $@

bychrom/$(CASE).new.freebayes.%.calls.vcf: 
	SGE_RREQ="-l h_vmem=8G -l h_stack=32M " /usr/bin/time -v $(FB) -r $* -f $(REFERENCE) --pooled-discrete --min-repeat-entropy 1 --genotype-qualities --min-alternate-fraction 0.05 --min-alternate-count 2 $(CASE).tumor.bam $(CASE).normal.bam > $@

CHR=1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 X Y
FREEBAYES_OLD_PER_CHR=$(addprefix bychrom/$(CASE).old.freebayes.,$(addsuffix .calls.vcf,$(CHR)))
FREEBAYES_NEW_PER_CHR=$(addprefix bychrom/$(CASE).new.freebayes.,$(addsuffix .calls.vcf,$(CHR)))

# Merge freebayes calls and tag with somatic status
$(CASE).new.freebayes.allchr.vcf: $(FREEBAYES_NEW_PER_CHR)
	/u/jdursi/sw/sga-extra/vcflib/bin//vcfcombine $^ | /u/jdursi/sw/sga-extra/vcflib/bin//vcfbreakmulti | /u/jdursi/sw/sga-extra/vcflib/bin//vcfsamplediff -s VT $(BASE_SAMPLE_NAME) $(VARIANT_SAMPLE_NAME) - > $@

$(CASE).old.freebayes.allchr.vcf: $(FREEBAYES_OLD_PER_CHR)
	/u/jdursi/sw/sga-extra/vcflib/bin//vcfcombine $^ | /u/jdursi/sw/sga-extra/vcflib/bin//vcfbreakmulti | /u/jdursi/sw/sga-extra/vcflib/bin//vcfsamplediff -s VT $(BASE_SAMPLE_NAME) $(VARIANT_SAMPLE_NAME) - > $@

# Split freebayes calls by somatic status, and remove variants on unplaced chromosomes and the mitochondria
$(CASE).%.freebayes.allchr.somatic.vcf: $(CASE).%.freebayes.allchr.vcf
	cat $< | awk '$$1 ~ /#/ || $$0 ~ /somatic/' | awk '$$1 ~ /#/ || ($$1 !~ /hs37d5/ && $$1 !~ /GL/ && $$1 !~ /MT/ && $$1 !~ /NC/)'> $@

# also filter germline by quality; qual score at least 5 for consideration
$(CASE).%.freebayes.allchr.germline.vcf: $(CASE).%.freebayes.allchr.vcf
	cat $< | awk '$$1 ~ /#/ || $$0 ~ /germline/ || $$0 ~ /reversion/' | awk '$$1 ~ /#/ || ($$1 !~ /hs37d5/ && $$1 !~ /GL/ && $$1 !~ /MT/ && $$1 !~ /NC/)' | awk '$$6 > 5' > $@
