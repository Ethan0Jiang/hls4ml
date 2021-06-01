#!/bin/bash

pycmd=python
xilinxpart="xcu250-figd2104-2L-e"
clock=5
io=io_parallel
rf=1
strategy="Latency"
type="ap_fixed<16,6>"
yml=""
ciyaml=false
basedir=vivado_prj

sanitizer="[^A-Za-z0-9._]"

function print_usage {
   echo "Usage: `basename $0` [OPTION] MODEL[:H5FILE]..."
   echo ""
   echo "MODEL is the name of the model json file without extension. Optionally"
   echo "a H5 file with weights can be provided using the MODEL:H5FILE synthax."
   echo "By default, it is assumed that weights are stored in MODEL_weights.h5."
   echo "Multiple models can be specified."
   echo ""
   echo "Options are:"
   echo "   -x DEVICE"
   echo "      Xilinx device part number. Defaults to 'xcu250-figd2104-2L-e'."
   echo "   -c CLOCK"
   echo "      Clock period to use. Defaults to 5."
   echo "   -s"
   echo "      Use streaming I/O. If not specified uses parallel I/O."
   echo "   -r FACTOR"
   echo "      Reuse factor. Defaults to 1."
   echo "   -g STRATEGY"
   echo "      Strategy. 'Latency' or 'Resource'."
   echo "   -t TYPE"
   echo "      Default precision. Defaults to 'ap_fixed<16,6>'."
   echo "   -d DIR"
   echo "      Output directory."
   echo "   -y FILE"
   echo "      YAML config file to take HLS config from. If specified, -r, -g and -t are ignored."
   echo "   -h"
   echo "      Prints this help message."
}

args=$@
while getopts ":x:c:sr:g:t:d:y:fh" opt; do
   case "$opt" in
   x) xilinxpart=$OPTARG
      ;;
   c) clock=$OPTARG
      ;;
   s) io=io_stream
      ;;
   r) rf=$OPTARG
      ;;
   g) strategy=$OPTARG
      ;;
   t) type=$OPTARG
      ;;
   d) basedir=$OPTARG
      ;;
   y) yml=$OPTARG
      ;;
   f) ciyaml=true
      ;;
   h)
      print_usage
      exit
      ;;
   :)
      echo "Option -$OPTARG requires an argument."
      exit 1
      ;;
   esac
done

shift $((OPTIND-1))

models=("$@")
if [[ ${#models[@]} -eq 0 ]]; then
   echo "No models specified."
   exit 1
fi

mkdir -p "${basedir}"

for model in "${models[@]}"
do
   name=${model}
   h5=${name}"_weights"
   IFS=":" read -ra model_h5_pair <<< "${model}" # If models are provided in "json:h5" format
   if [[ ${#model_h5_pair[@]} -eq 2 ]]; then
      name="${model_h5_pair[0]}"
      h5="${model_h5_pair[1]}"
   fi

   echo "Creating config file for model '${model}'"
   base=`echo "${h5}" | sed -e 's/\(_weights\)*$//g'`
   prjname="${base}-${xilinxpart//${sanitizer}/_}-c${clock}-${io}-rf${rf}-${type//${sanitizer}/_}-${strategy}"
   file="${basedir}/${prjname}.yml"
   prjdir="${basedir}/$prjname"

   hlscfg=""
   if [ ! -z "${yml}" ]; then
      hlscfg=`sed -ne '/HLSConfig/,$p' ../example-models/config-files/${yml}`
   fi

   echo "KerasJson: ../example-models/keras/${name}.json" > ${file}
   echo "KerasH5:   ../example-models/keras/${h5}.h5" >> ${file}
   echo "OutputDir: ${prjdir}" >> ${file}
   echo "ProjectName: myproject" >> ${file}
   echo "XilinxPart: ${xilinxpart}" >> ${file}
   echo "ClockPeriod: ${clock}" >> ${file}
   echo "" >> ${file}
   echo "IOType: ${io}" >> ${file}
   
   if [ -z "${hlscfg}" ]
   then
      echo "HLSConfig:" >> ${file}
      echo "  Model:" >> ${file}
      echo "    ReuseFactor: ${rf}" >> ${file}
      echo "    Precision: ${type} " >> ${file}
      echo "    Strategy: ${strategy} " >> ${file}
   else
      echo "${hlscfg}" >> ${file}
   fi

   if $ciymlfile ; then
      echo -e "convert ${prjname}:\n extends: .convert\n variables:\n    ARGS: ${args}\n    HLS4ML_PRJ: ${prjname}\n\n" >> convert-keras-models-ci.yml
      echo -e "csim ${prjname}:\n  extends: .csim\n  needs:\n  - convert ${prjname}\n  variables:\n    HLS4ML_PRJ: ${prjname}\n\n" >> convert-keras-models-ci.yml
      echo -e "csynth ${prjname}:\n  extends: .csynth\n  needs:\n  - csim ${prjname}\n  variables:\n    HLS4ML_PRJ: ${prjname}\n\n" >> convert-keras-models-ci.yml
   fi
   ${pycmd} ../scripts/hls4ml convert -c ${file} || exit 1
   rm ${file}
   rm -rf "${prjdir}"
   echo ""


done
