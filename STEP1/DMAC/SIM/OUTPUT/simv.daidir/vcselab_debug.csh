#!/bin/csh -f

cd /home/SOC43/Project2_Pipelined_DMA/STEP1/DMAC/SIM/OUTPUT

#This ENV is used to avoid overriding current script in next vcselab run 
setenv SNPS_VCSELAB_SCRIPT_NO_OVERRIDE  1

/INST/vcs/R-2020.12-SP1-1/linux64/bin/vcselab $* \
    -o \
    simv \
    -nobanner \

cd -

