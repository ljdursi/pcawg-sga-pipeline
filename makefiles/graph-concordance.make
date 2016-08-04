SHELL=/bin/bash -o pipefail
NEWSGA=/u/jdursi/code/test-sga/sga/bin/sga
OLDSGA=/u/jdursi/sw/sga/bin/sga
FB=/u/jdursi/sw/sga-extra/freebayes/bin/freebayes
SGAEXTRA=/u/jdursi/sw/sga-extra/
SAMTOOLS=$(SGAEXTRA)/samtools/samtools
BCFTOOLS=$(SGAEXTRA)/bcftools/bcftools

# do not delete intermediate files
.SECONDARY:
# delete files when a command fails
.DELETE_ON_ERROR:

############################
# File paths
############################
REFERENCE=/.mounts/labs/simpsonlab/data/references/hs37d5.pp.fa

BASE_BAM:=$(CASE).normal.bam
VARIANT_BAM:=$(CASE).tumor.bam

all: $(CASE).20.merged.oldfb.passed.vcf $(CASE).30.oldmerged.oldfb.passed.vcf 

############################
# filtering
############################

# Filter freebayes calls against the assembly graph
$(CASE).new.freebayes.allchr.somatic.graph.vcf: $(CASE).new.freebayes.allchr.somatic.vcf $(CASE).new.freebayes.allchr.germline.vcf $(CASE).tumor.bwt $(CASE).tumor.sai $(CASE).normal.bwt $(CASE).normal.sai
	SGE_RREQ="-N newGC-$(CASE) -l h_vmem=32G -l h_stack=32M -pe smp 4 -l h_core=128G" /usr/bin/time -v $(NEWSGA) graph-concordance -v -t 4 --ref $(REFERENCE) -r $(CASE).tumor.fastq.gz -b $(CASE).normal.fastq.gz -g $(CASE).new.freebayes.allchr.germline.vcf $(CASE).new.freebayes.allchr.somatic.vcf 2> graphfilter.err > $@

# Filter freebayes calls against the assembly graph
$(CASE).new.freebayes.allchr.somatic.oldgraph.vcf: $(CASE).new.freebayes.allchr.somatic.vcf $(CASE).new.freebayes.allchr.germline.vcf $(CASE).tumor.bwt $(CASE).tumor.sai $(CASE).normal.bwt $(CASE).normal.sai
	SGE_RREQ="-N oldGC-$(CASE) -l h_vmem=32G -l h_stack=32M -pe smp 4 -l h_core=128G" /usr/bin/time -v $(OLDSGA) graph-concordance --ref $(REFERENCE) -r $(CASE).tumor.fastq.gz -b $(CASE).normal.fastq.gz -g $(CASE).new.freebayes.allchr.germline.vcf $(CASE).new.freebayes.allchr.somatic.vcf 2> oldgraphfilter.err > $@

$(CASE).old.freebayes.allchr.somatic.graph.vcf: $(CASE).old.freebayes.allchr.somatic.vcf $(CASE).old.freebayes.allchr.germline.vcf $(CASE).tumor.bwt $(CASE).tumor.sai $(CASE).normal.bwt $(CASE).normal.sai
	SGE_RREQ="-N newGC-$(CASE) -l h_vmem=32G -l h_stack=32M -pe smp 4 -l h_core=128G" /usr/bin/time -v $(NEWSGA) graph-concordance -v -t 4 --ref $(REFERENCE) -r $(CASE).tumor.fastq.gz -b $(CASE).normal.fastq.gz -g $(CASE).old.freebayes.allchr.germline.vcf $(CASE).old.freebayes.allchr.somatic.vcf 2> graphfilter.err > $@

# Filter freebayes calls against the assembly graph
$(CASE).old.freebayes.allchr.somatic.oldgraph.vcf: $(CASE).old.freebayes.allchr.somatic.vcf $(CASE).old.freebayes.allchr.germline.vcf $(CASE).tumor.bwt $(CASE).tumor.sai $(CASE).normal.bwt $(CASE).normal.sai
	SGE_RREQ="-N oldGC-$(CASE) -l h_vmem=32G -l h_stack=32M -pe smp 4 -l h_core=128G" /usr/bin/time -v $(OLDSGA) graph-concordance --ref $(REFERENCE) -r $(CASE).tumor.fastq.gz -b $(CASE).normal.fastq.gz -g $(CASE).old.freebayes.allchr.germline.vcf $(CASE).old.freebayes.allchr.somatic.vcf 2> oldgraphfilter.err > $@

# Left align calls and remove variants on unplaced chromosomes and the mitochondria
%.leftalign.vcf: %.vcf
	$(BCFTOOLS) norm -f $(REFERENCE) $< | awk '$$1 ~ /#/ || ($$1 !~ /hs37d5/ && $$1 !~ /GL/ && $$1 !~ /MT/ && $$1 !~ /NC/)'> $@

# Mark dbSNP variants
%.dbsnp.vcf: %.vcf
	SGE_RREQ="-N dbSNP-$(CASE) -l h_vmem=2G -l h_stack=32M" $(SGAEXTRA)/sga-dbsnp-filter.pl --extra $(SGAEXTRA) --dbsnp $(SGAEXTRA)/dbsnp/00-All.vcf.gz --cosmic $(SGAEXTRA)/cosmic $< > $@

# Filter calls
%.filters.vcf: %.vcf $(VARIANT_BAM) $(BASE_BAM)
	SGE_RREQ="-N filter-$(CASE) -l h_vmem=4G -l h_stack=32M -pe smp 8" 	$(OLDSGA) somatic-variant-filters -t 8 --min-var-dp 3 --min-af 0.02 --tumor $(VARIANT_BAM) --normal $(BASE_BAM) --reference $(REFERENCE) $< > $@

# Merge the results of SGA and freebayes
$(CASE).%.merged.vcf: $(CASE).sga.calls.leftalign.filters.dbsnp.vcf $(CASE).new.freebayes.allchr.somatic.graph.leftalign.filters.dbsnp.vcf
	$(SGAEXTRA)/sga_freebayes_merge.pl --nograph_concordance --min-quality=$* $^ > $@

# Subset to passed-only sites
$(CASE).%.merged.passed.vcf: $(CASE).%.merged.vcf
	cat $^ | awk '$$1 ~ /#/ || $$7 ~ /PASS/' > $@

# Merge the results of SGA and freebayes
$(CASE).%.oldmerged.vcf: $(CASE).sga.calls.leftalign.filters.dbsnp.vcf $(CASE).new.freebayes.allchr.somatic.oldgraph.leftalign.filters.dbsnp.vcf
	$(SGAEXTRA)/sga_freebayes_merge.pl --min-quality=$* $^ > $@

# Subset to passed-only sites
$(CASE).%.oldmerged.passed.vcf: $(CASE).%.oldmerged.vcf
	cat $^ | awk '$$1 ~ /#/ || $$7 ~ /PASS/' > $@


# Merge the results of SGA and freebayes
$(CASE).%.merged.oldfb.vcf: $(CASE).sga.calls.leftalign.filters.dbsnp.vcf $(CASE).old.freebayes.allchr.somatic.graph.leftalign.filters.dbsnp.vcf
	SGE_RREQ="-l h_vmem=4G" $(SGAEXTRA)/sga_freebayes_merge.pl --nograph_concordance --min-quality=$* $^ > $@

# Subset to passed-only sites
$(CASE).%.merged.oldfb.passed.vcf: $(CASE).%.merged.oldfb.vcf
	cat $^ | awk '$$1 ~ /#/ || $$7 ~ /PASS/' > $@

# Merge the results of SGA and freebayes
$(CASE).%.oldmerged.oldfb.vcf: $(CASE).sga.calls.leftalign.filters.dbsnp.vcf $(CASE).old.freebayes.allchr.somatic.oldgraph.leftalign.filters.dbsnp.vcf
	SGE_RREQ="-l h_vmem=4G" $(SGAEXTRA)/sga_freebayes_merge.pl --min-quality=$* $^ > $@

# Subset to passed-only sites
$(CASE).%.oldmerged.oldfb.passed.vcf: $(CASE).%.oldmerged.oldfb.vcf
	cat $^ | awk '$$1 ~ /#/ || $$7 ~ /PASS/' > $@

