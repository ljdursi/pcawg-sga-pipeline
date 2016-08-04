SHELL=/bin/bash -o pipefail
FB=/u/jdursi/sw/sga-extra/freebayes/bin/freebayes
BAMADDRG=/u/jdursi/sw/bamaddrg/bamaddrg

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

bychrom/$(CASE).old.freebayes.calls.vcf: $(VARIANT_BAM) $(BASE_BAM)
	SGE_RREQ="-l h_vmem=12G -l h_stack=32M " /usr/bin/time -v $(BAMADDRG) -b $(VARIANT_BAM) -c -s $(VARIANT_SAMPLE_NAME) -r variant -b $(BASE_BAM) -s $(BASE_SAMPLE_NAME) -r base | $(FB) -f $(REFERENCE) --pooled-discrete --pooled-continuous --min-alternate-fraction 0.1 --allele-balance-priors-off --genotype-qualities - > $@

bychrom/$(CASE).new.freebayes.calls.vcf: $(VARIANT_BAM) $(BASE_BAM)
	SGE_RREQ="-l h_vmem=12G -l h_stack=32M " /usr/bin/time -v $(BAMADDRG) -b $(VARIANT_BAM) -c -s $(VARIANT_SAMPLE_NAME) -r variant -b $(BASE_BAM) -s $(BASE_SAMPLE_NAME) -r base | $(FB) -f $(REFERENCE) --pooled-discrete --min-repeat-entropy 1 --min-alternate-fraction 0.05 --min-alternate-count 2 --genotype-qualities - > $@

# Merge freebayes calls and tag with somatic status
$(CASE).%.freebayes.allchr.vcf: bychrom/$(CASE).%.freebayes.calls.vcf
	SGE_REQ="-l h_vmem=2G -l h_stack=32M" /u/jdursi/sw/sga-extra/vcflib/bin//vcfcombine $^ | /u/jdursi/sw/sga-extra/vcflib/bin//vcfbreakmulti | /u/jdursi/sw/sga-extra/vcflib/bin//vcfsamplediff -s VT $(BASE_SAMPLE_NAME) $(VARIANT_SAMPLE_NAME) - > $@

# Split freebayes calls by somatic status
$(CASE).%.freebayes.allchr.somatic.vcf: $(CASE).%.freebayes.allchr.vcf
	cat $< | awk '$$1 ~ /#/ || $$0 ~ /somatic/' > $@

$(CASE).%.freebayes.allchr.germline.vcf: $(CASE).%.freebayes.allchr.vcf
	cat $< | awk '$$1 ~ /#/ || $$0 ~ /germline/ || $$0 ~ /reversion/' > $@
