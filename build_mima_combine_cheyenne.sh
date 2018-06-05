#!/bin/bash
#########################################################################
# File Name: /glade/u/home/${USER}/build_mima_combine.sh
# Author: Wanying Kang
# Created Time: Thu 24 May 2018 08:08:52 AM MDT
# To use just type: ./build_mima_combine.sh [CASENAME:-test] [NCORES:-32]
#########################################################################
source /glade/u/home/${USER}/.bashrc
VERSION=1.0.0
DATE="May 24, 2018"
USAGE="Usage: compile or running MiMA"
OPTIONS="casename [default:test], ncores [default:36]"
#----------------------------------------------------------------
## get in arguments ##
#----------------------------------------------------------------
if [ $# == 0 ] ; then
    echo $USAGE
    echo $OPTIONS
    exit 1;
fi
export CASENAME=${1:-"test"}
export MiMAHOME=/DIR/TO/CASE/ROOT/			    	# the holder of all cases
export execdir=${MiMAHOME}/${CASENAME}/				# compile and generate executable
export workdir=/DIR/TO/SCRATCH/DIR/${CASENAME}/		# running model and output
export MiMAROOT=/DIR/TO/MiMA/CODE					# original source code
export srcmoddir=${MiMAHOME}/srcmods/				# where hold the modified source code if any
export inputdir=${MiMAHOME}/input/					# where hold the modified input files if any

export PLATFORM=cheyenne							# Machine name, determine the templates for mkmf and run_script to use
export NCORES=${2:-"32"}							# how many cores to use
export NCORE_NODE=36								# machine #CPU per Node
export NNODE=$(((NCORES - 1) / NCORE_NODE + 1))		# should be integer
export NSUBMIT=1									# how many times to rerun

if [ -e $workdir ]; then
  echo "ERROR: Existing workdir already exist, running will overwrite workdir. Please Move or remove $workdir and try again."
  exit 1
else
  mkdir -p $workdir
fi

#----------------------------------------------------------------
## set PATH and environment variables##
#----------------------------------------------------------------
export compiler_type=intel
export compiler_name=intel/17.0.1
export compiler_fmulti=mpif90
export compiler_cmulti=mpicc
export compiler_fsingle=ifort
export compiler_csingle=icc
export mpi_type=mpt
export mpi_name=mpt/2.15f # support both MPI and OpenMP 
export omp_cmd=omplace
export mpi_cmd='mpiexec -n $npes'
export netcdf_name=netcdf/4.4.1.1

module purge
module load ncarenv/1.2
module load ${compiler_name}
module load ncarcompilers
module load ${mpi_name}
module load ${netcdf_name}
module list

#----------------------------------------------------------------
## customer code/namelist ##
#----------------------------------------------------------------
export pathnames_tmp=${MiMAROOT}/exp/path_names			# compile file list template
export pathnames=$execdir/path_names						# compile file list

mkdir -p $execdir/
cp -f ${MiMAROOT}/input/* $execdir/ 2>/dev/null 
cp -f ${inputdir}/* $execdir/ 2>/dev/null # overwrite, if any, input.nml, diag_table and field_table
cp $pathnames_tmp $execdir 2>/dev/null
mkdir -p $execdir/srcmods

if [ "$(ls -A $execdir/srcmods)" ]; then
	cp -rf $srcmoddir $execdir/srcmods 2>/dev/null # modified code cp and add to the head of path_names list
	find $execdir/srcmods -maxdepth 1 -iname "*.f90" -o -iname "*.inc" -o -iname "*.c" -o -iname "*.h" > ${pathnames}
	echo "Modifying the following SourceCode"
	cat ${pathnames}
fi
cat $pathnames_tmp >> ${pathnames}

# prepare workdir
cd $execdir
cp input.nml field_table diag_table $workdir/
mkdir -p $workdir/INPUT
mkdir -p $workdir/RESTART

#----------------------------------------------------------------
## compile ##
#----------------------------------------------------------------
# define environment variable used in compiling
export sourcedir=${MiMAROOT}/src							# path to directory containing model source code
export mkmf=${MiMAROOT}/bin/mkmf							# path to executable mkmf
export namelist=$workdir//input.nml							# path to namelist file
export diagtable=$workdir//diag_table						# path to diagnositics table
export fieldtable=$workdir//field_table						# path to field table (specifies tracers)
export platform=${PLATFORM}
export npes=${NCORES}
export template=${MiMAROOT}/bin/mkmf.${PLATFORM}.${compiler_type}	# path_name list template for compiling 
export mppnccombine=${execdir}/mppnccombine.${PLATFORM}.${compiler_type}    # path to executable mppnccombine

# C compile the nc file combiner
if [ ! -f $mppnccombine ]; then
  ${compiler_csingle} -O -o ${mppnccombine} -I${NETCDF_INC} -L${NETCDF_LIB} -lnetcdf -I${MPI_INC} -L${MPI_LIB} -lmpi ${MiMAROOT}/postprocessing/mppnccombine.c 
fi

# compile the model code and create executable
cd $execdir
cppDefs="-Duse_libMPI -Duse_netCDF"
$mkmf -p mima.x -t $template -c "$cppDefs" -a $sourcedir $pathnames $sourcedir/shared/mpp/include $sourcedir/shared/include
make -j8 -f Makefile > $execdir/bldlog 

#----------------------------------------------------------------
## generate run script ##
#----------------------------------------------------------------
# copy from template and do some change
cd $execdir
cp ${MiMAROOT}/exp/${PLATFORM}_runscript_${mpi_type}.sh run_${CASENAME}.sh
for var in execdir workdir NSUBMIT CASENAME MiMAROOT NNODE NCORE_NODE NCORES PLATFORM mppnccombine omp_cmd mpi_cmd NETCDF_LIB MPI_LIB
do
	content=$(eval echo `echo '$'$var`)
	sed -i -e "s#$var#$content#g" run_${CASENAME}.sh
done
ed run_${CASENAME}.sh << END
11i
module purge
module load ncarenv
module load ${compiler_name}
module load ncarcompilers
module load ${mpi_name}
module load ${netcdf_name}
module load mkl
.
w
q
END
# add exe authority
chmod +x run_${CASENAME}.sh
mkdir obj
mv *.o *.mod Makefile bldlog obj
ln -s $MiMAROOT/input/INPUT .

#----------------------------------------------------------------
## print happy ending
#----------------------------------------------------------------
echo " "
echo "===================++++++++++++++++++++++===================="
echo "To submit job:"
echo "cd ${execdir}"
echo "qsub run_${CASENAME}.sh"
echo "===================++++++++++++++++++++++===================="


