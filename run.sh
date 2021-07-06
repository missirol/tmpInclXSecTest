#!/bin/bash -e
#SBATCH -p standard
#SBATCH --account=t3
#SBATCH --job-name=testMG5
#SBATCH --mem=900M
#SBATCH --time 05:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=8
#SBATCH -o /work/%u/test/.slurm/%x_%A_%a.out
#SBATCH -e /work/%u/test/.slurm/%x_%A_%a.err

if [ -z ${SLURM_ARRAY_TASK_ID} ]; then
  if [ $# -ne 3 ]; then
    printf "%s\n" ">> invalid number of cmd-line arguments ($# != 3), must be [FS_NAME] [OUT_DIR] [MU_R/F SCALE]"
    exit 1
  fi
  FS_NAME=$1
  OUT_DIR=$2
  MURF_SCALE=$3
  SLURM_ARRAY_TASK_ID=$3
else
  if [ $# -ne 2 ]; then
    printf "%s\n" ">> invalid number of cmd-line arguments ($# != 2), must be [FS_NAME] [OUT_DIR]"
    exit 1
  fi
  FS_NAME=$1
  OUT_DIR=$2
  MURF_SCALE=${SLURM_ARRAY_TASK_ID}
fi

# define SLURM_JOB_NAME and SLURM_ARRAY_JOB_ID, if they are not defined already (e.g. if script is executed locally)
[ ! -z ${SLURM_JOB_NAME} ] || SLURM_JOB_NAME=testMG5
[ ! -z ${SLURM_ARRAY_JOB_ID} ] || SLURM_ARRAY_JOB_ID=local$(date +%y%m%d%H%M%S)

echo "------------------------------------------------------------"
echo "[`date`] Job started"
echo "------------------------------------------------------------"
DATE_START=`date +%s`

echo HOSTNAME: ${HOSTNAME}
echo HOME: ${HOME}
echo USER: ${USER}
echo SLURM_JOB_NAME: ${SLURM_JOB_NAME}
echo SLURM_JOB_ID: ${SLURM_JOB_ID}
echo SLURM_ARRAY_JOB_ID: ${SLURM_ARRAY_JOB_ID}
echo SLURM_ARRAY_TASK_ID: ${SLURM_ARRAY_TASK_ID}

# output directory
#if [ -d ${OUT_DIR} ]; then
#  printf "%s\n" ">> target output directory already exists: ${OUT_DIR}"
#  exit 1
#fi

# path to text file with patch for MG5 source code
# ref: https://answers.launchpad.net/mg5amcnlo/+question/678621
PATCHFILE_MG5=${PWD}/mg5_ymc_running_"${FS_NAME}".patch

if [ ! -f ${PATCHFILE_MG5} ]; then
  printf "%s\n" ">> required input file does not exist: ${PATCHFILE_MG5}"
  exit 1
fi

# path to text file with patch for loop_sm_MSbar_yb UFO
# to use MSbar scheme for the charm Yukawa coupling
PATCHFILE_UFO=${PWD}/loop_sm_MSbar_yb_yc.patch

if [ ! -f ${PATCHFILE_UFO} ]; then
  printf "%s\n" ">> required input file does not exist: ${PATCHFILE_UFO}"
  exit 1
fi

# path to text file with MG5 restriction card
RESTRICTCARDFILE=${PWD}/restrict_"${FS_NAME}".dat

if [ ! -f ${RESTRICTCARDFILE} ]; then
  printf "%s\n" ">> required input file does not exist: ${RESTRICTCARDFILE}"
  exit 1
fi

# path to text file with MG5 process definition
PROCCARDFILE=${PWD}/proc_card_"${FS_NAME}".txt

if [ ! -f ${PROCCARDFILE} ]; then
  printf "%s\n" ">> required input file does not exist: ${PROCCARDFILE}"
#  printf "%s\n" ">> invalid value for \"Flavour Scheme\" name (must 3FS or 4FS): ${FS_NAME}"
  exit 1
fi

#export LHAPDF_DATA_PATH=/cvmfs/sft.cern.ch/lcg/external/lhapdfsets/current
#[ -d ${LHAPDF_DATA_PATH} ] || unset LHAPDF_DATA_PATH
if [ -z ${LHAPDF_DATA_PATH} ]; then
  printf "%s\n" "Environment variable \"LHAPDF_DATA_PATH\" is not defined. Job will be stopped." 1>&2
  exit 1
elif [ ! -d ${LHAPDF_DATA_PATH} ]; then
  printf "%s\n" ">> required input directory does not exist: ${LHAPDF_DATA_PATH}"
  exit 1
fi

mkdir -p ${OUT_DIR}
OUT_DIR=$(readlink -e "${OUT_DIR}")
cd ${OUT_DIR}

# download and untar MG5
MG5_DIR=${OUT_DIR}/MG5_aMC_v2_6_7

if [ ! -d ${MG5_DIR} ]; then

  printf "%s\n" ">> setting up MadGraph: ${MG5_DIR}"
  [ -f MG5_aMC_v2.6.7.tar.gz ] || (wget https://launchpad.net/mg5amcnlo/2.0/2.6.x/+download/MG5_aMC_v2.6.7.tar.gz)
  tar xzf MG5_aMC_v2.6.7.tar.gz
  rm -f MG5_aMC_v2.6.7.tar.gz

  # optional: modify default text editor used when running MG5 in interactive mode
  echo "text_editor = emacs -nw" >> ${MG5_DIR}/input/mg5_configuration.txt
  echo "automatic_html_opening = False" >> ${MG5_DIR}/input/mg5_configuration.txt
  echo "run_mode = 2" >> ${MG5_DIR}/input/mg5_configuration.txt
  echo "nb_core = 8" >> ${MG5_DIR}/input/mg5_configuration.txt
#  echo "lhapdf = ${HOME}/Downloads/LHAPDF_6.3.0/bin/lhapdf-config" >> ${MG5_DIR}/input/mg5_configuration.txt

  if [ ! -d ${MG5_DIR}/models/loop_sm_MSbar_yb_yc ]; then
    # download, untar and rename UFO model (and clean up some unnecessary files)
    wget https://cms-project-generators.web.cern.ch/cms-project-generators/loop_sm_MSbar_yb.tar -O loop_sm_MSbar_yb_yc.tar
    tar xvf loop_sm_MSbar_yb_yc.tar
    mv loop_sm_MSbar_yb loop_sm_MSbar_yb_yc
    rm -f loop_sm_MSbar_yb_yc/*{~,.pyo}

    pushd loop_sm_MSbar_yb_yc
    cat "${PATCHFILE_UFO}" | patch -p1
    popd

    # added restriction cards with non-null ymc value
    cp "${RESTRICTCARDFILE}" loop_sm_MSbar_yb_yc

    # move the model in MG5 and remove tarball
    mv loop_sm_MSbar_yb_yc ${MG5_DIR}/models
    rm -f loop_sm_MSbar_yb_yc.tar
  fi

  # apply patch to MG5 source code
  pushd "${MG5_DIR}"
  cat "${PATCHFILE_MG5}" | patch -p1
  popd
fi

TMPPROCCARDFILE=proc_card_"${SLURM_ARRAY_JOB_ID}"_"${SLURM_ARRAY_TASK_ID}".txt

sed "s|__MURF_SCALE__|${MURF_SCALE}|g" "${PROCCARDFILE}" > "${TMPPROCCARDFILE}"

# uncomment the line below to run MG5
#"${MG5_DIR}"/bin/mg5_aMC "${TMPPROCCARDFILE}"

echo "------------------------------------------------------------"
echo "[`date`] Job completed successfully"
DATE_END=`date +%s`
runtime=$((DATE_END-DATE_START))
echo "[`date`] Elapsed time: ${runtime} sec"
echo "------------------------------------------------------------"
