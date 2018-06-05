#!/bin/bash
#PBS -N CASENAME
#PBS -A UHAR0008
#PBS -l walltime=12:00:00
#PBS -q regular
#PBS -j oe
#PBS -m abe
#PBS -M kangwanying1992@gmail.com
#PBS -l select=NNODE:ncpus=NCORES:mpiprocs=NCORES:ompthreads=1
source /etc/profile.d/modules.sh

module list
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:NETCDF_LIB:MPI_LIB

# stop on error
set -e

cd workdir
cp execdir/mima.x .
cp execdir/INPUT/* ./INPUT/
cp execdir/input.nml execdir/field_table execdir/diag_table .

# run the model
export npes=NCORES
n=0
while [ $n -lt NSUBMIT ]
do
  echo 'SRART WITH ITERATION '$n
  index=`printf %04d ${n%*} ${n##*}`
  omp_cmd ./mima.x 
  mppnccombine -r ${index}.atmos_daily.nc atmos_daily.nc.????
  mppnccombine -r ${index}.atmos_avg.nc atmos_avg.nc.????
  cp RESTART/*res* INPUT/
  echo 'DONE WITH ITERATION '$n
  let n=$n+1
done
