#!/bin/bash

usage()
{
  echo "Usage: $0 <algorithm> <iva> <iva data> <iva data file> <core count file> <power profile file> <time serial analytics file> <time parallel analytics file> <space serial analytics file> <space parallel analytics file> <power serial analytics file> <power parallel analytics file> <energy serial analytics file> <energy parallel analytics file> <speedup analytics file> <freeup analytics file> <powerup analytics file> <energyup analytics file> <id> <repo> <repo name> <start time> <progress>"
  exit 1
}

if [ "$#" -ne 29 ]; then
    echo "Invalid number of parameters. Expected:29 Passed:$#"
    usage
fi

algo=$1
main_file=$2
target_fn=$3
target_fn_iva_name=$4
target_fn_iva_start=$5
target_fn_iva_end=$6
argc=$7
iva_name=$8
iva_data=$9
iva_data_file=${10}
core_count_file=${11}
power_profile_file=${12}
time_serial_analytics_file=${13}
time_parallel_analytics_file=${14}
space_serial_analytics_file=${15}
space_parallel_analytics_file=${16}
power_serial_analytics_file=${17}
power_parallel_analytics_file=${18}
energy_serial_analytics_file=${19}
energy_parallel_analytics_file=${20}
speedup_analytics_file=${21}
freeup_analytics_file=${22}
powerup_analytics_file=${23}
energyup_analytics_file=${24}
id=${25}
repo=${26}
repo_name=${27}
start_time=${28}
progress=${29}

serial_measurement=serial.csv
parallel_measurement=parallel.csv
analysis_file=analysis.json

# parallel code generation config
parallel_plugin_so=MyRewriter.so
parallel_plugin_name=rew

# cleanup
rm $time_serial_analytics_file 2> /dev/null
rm $time_parallel_analytics_file 2> /dev/null
rm $space_serial_analytics_file 2> /dev/null
rm $space_parallel_analytics_file 2> /dev/null
rm $power_serial_analytics_file 2> /dev/null
rm $power_parallel_analytics_file 2> /dev/null
rm $energy_serial_analytics_file 2> /dev/null
rm $energy_parallel_analytics_file 2> /dev/null
rm $speedup_analytics_file 2> /dev/null
rm $freeup_analytics_file 2> /dev/null
rm $powerup_analytics_file 2> /dev/null
rm $energyup_analytics_file 2> /dev/null
rm $serial_measurement 2> /dev/null
rm $parallel_measurement 2> /dev/null

readarray -t iva_arr  < $iva_data_file
readarray -t core_arr < $core_count_file

power_profile=()

while IFS=, read -r i p;
do power_profile+=($p);
done < $power_profile_file

iva=()
core=()

for i in ${iva_arr[@]}
do
  iva+=($i)
done

for i in ${core_arr[@]}
do
  core+=($i)
done

# make - serial
make -f Makefile-serial

# make a copy of original execuatble
algo_orig="$algo"_original
mv $algo $algo_orig

# generate TALP parallel code
clang -fplugin=$parallel_plugin_so -Xclang -plugin -Xclang $parallel_plugin_name -Xclang -plugin-arg-rew -Xclang -target-function -Xclang -plugin-arg-rew -Xclang $target_fn -Xclang -plugin-arg-rew -Xclang -out-file -Xclang -plugin-arg-rew -Xclang $main_file -Xclang -plugin-arg-rew -Xclang -iva -Xclang -plugin-arg-rew -Xclang $target_fn_iva_name -Xclang -plugin-arg-rew -Xclang -iva-start -Xclang -plugin-arg-rew -Xclang $target_fn_iva_start -Xclang -plugin-arg-rew -Xclang -iva-end -Xclang -plugin-arg-rew -Xclang $target_fn_iva_end -Xclang -plugin-arg-rew -Xclang -argc -Xclang -plugin-arg-rew -Xclang $argc -c $main_file

# make - parallel
make -f Makefile-parallel

# serial run

time_serial=()
space_serial=()
power_serial=()
energy_serial=()

# time - serial
progress_bandwidth=10

for i in ${iva[@]}
do
  # time
  start=`date +%s.%N`;\
  ./$algo_orig $i $i;\
  end=`date +%s.%N`;\
  time_serial+=(`printf '%.8f' $( echo "$end - $start" | bc -l )`);

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=${#iva[@]}; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Serial Time Measurement\",\
  \"nextStep\":\"Serial Memory Measurement\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file
done

# memory - serial
progress_bandwidth=10

count=1
for i in ${iva[@]}
do
  # memory
  heaptrack -o "$algo.$count" ./$algo_orig $i $i;\
  space_serial+=(`heaptrack --analyze "$algo.$count.zst"  | grep "peak heap memory consumption" | awk '{print $5}'`);
  count=$((count+1))

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=${#iva[@]}; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Serial Memory Measurement\",\
  \"nextStep\":\"Serial Power Measurement\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file

done

# power - serial
progress_bandwidth=10

for i in ${iva[@]}
do
  # power
  power_serial+=(${power_profile[0]})

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=${#iva[@]}; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Serial Power Measurement\",\
  \"nextStep\":\"Parallel Time Measurement\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file

done

# energy - serial
for i in "${!iva[@]}"
do
  # energy
  energy_serial+=(`echo "tm=${time_serial[i]};pw=${power_serial[i]};tm * pw" | bc -l`);
done

# serial measurement file
for i in "${!iva[@]}"
do
  echo "${iva[i]},${time_serial[i]},${memory_serial[i]},${power_serial[i]},${energy_serial[i]}" >> "$serial_measurement"
done

# parallel run

time_parallel=()
space_parallel=()
power_parallel=()
energy_parallel=()

# time - parallel
progress_bandwidth=10

for i in ${core[@]}
do
  # time
  start=`date +%s.%N`;\
  ./$algo $iva_data $iva_data $i;\
  end=`date +%s.%N`;\
  time_parallel+=(`printf '%.8f' $( echo "$end - $start" | bc -l )`);

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=${#core[@]}; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Parallel Time Measurement\",\
  \"nextStep\":\"Parallel Memory Measurement\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file

done

# memory - parallel
progress_bandwidth=10

count=1
for i in ${core[@]}
do
  # memory
  heaptrack -o "$algo.$count" ./$algo $iva_data $iva_data $i;\
  space_parallel+=(`heaptrack --analyze "$algo.$count.zst"  | grep "peak heap memory consumption" | awk '{print $5}'`);
  count=$((count+1))

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=${#core[@]}; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Parallel Memory Measurement\",\
  \"nextStep\":\"Parallel Power Measurement\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file

done

# power - parallel
progress_bandwidth=10

for i in ${core[@]}
do
  # power
  power_parallel+=(${power_profile[i-1]})

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=${#core[@]}; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Parallel Power Measurement\",\
  \"nextStep\":\"Predictive Model Generation\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file
done

# energy - parallel
for i in "${!core[@]}"
do
  # energy
  energy_parallel+=(`echo "tm=${time_parallel[i]};pw=${power_parallel[i]};tm * pw" | bc`);
done

# parallel measurement file
for i in "${!core[@]}"
do
  echo "${core[i]},${time_parallel[i]},${memory_parallel[i]},${power_parallel[i]},${energy_parallel[i]}" >> "$parallel_measurement"
done

# data prep
for i in "${!space_serial[@]}"; do
  if [[ ${space_serial[$i]: -1} == "K" ]]; then
    val=${space_serial[$i]::-1}
    space_serial[$i]=`printf '%.4f' $(echo "v=$val;v * 0.001" | bc)`
  else
    space_serial[$i]=${space_serial[$i]::-1}
  fi
done

for i in "${!space_parallel[@]}"; do
  if [[ ${space_parallel[$i]: -1} == "K" ]]; then
    val=${space_parallel[$i]::-1}
    space_parallel[$i]=`printf '%.4f' $(echo "v=$val;v * 0.001" | bc)`
  else
    space_parallel[$i]=${space_parallel[$i]::-1}
  fi
done

# speedup
speedup=()
t_max=${time_parallel[0]}
for t in "${time_parallel[@]}"; do
  speedup+=(`echo "scale=2;$t_max/$t" | bc`)
done

# freeup
freeup=()
s_max=${space_parallel[0]}
for s in "${space_parallel[@]}"; do
  freeup+=(`echo "scale=2;$s_max/$s" | bc`)
done

# powerup
powerup=()
p_1=${power_parallel[0]}
for p_core in "${power_parallel[@]}"; do
  powerup+=(`echo "scale=4;$p_1/$p_core" | bc`)
done

# energyup
energyup=()
e_1=${energy_parallel[0]}
for e_core in "${energy_parallel[@]}"; do
  energyup+=(`echo "scale=4;$e_1/$e_core" | bc`)
done

jo -p iva=$(jo name=$iva_name values=$(jo -a ${iva[@]})) \
measurements=$(jo -a ${time_serial[@]}) > time-serial.json
jo -p iva=$(jo name=core values=$(jo -a ${core[@]})) \
measurements=$(jo -a ${time_parallel[@]}) > time-parallel.json
jo -p iva=$(jo name=$iva_name values=$(jo -a ${iva[@]})) \
measurements=$(jo -a ${space_serial[@]}) > space-serial.json
jo -p iva=$(jo name=core values=$(jo -a ${core[@]})) \
measurements=$(jo -a ${space_parallel[@]}) > space-parallel.json
jo -p iva=$(jo name=$iva_name values=$(jo -a ${iva[@]})) \
measurements=$(jo -a ${power_serial[@]}) > power-serial.json
jo -p iva=$(jo name=core values=$(jo -a ${core[@]})) \
measurements=$(jo -a ${power_parallel[@]}) > power-parallel.json
jo -p iva=$(jo name=$iva_name values=$(jo -a ${iva[@]})) \
measurements=$(jo -a ${energy_serial[@]}) > energy-serial.json
jo -p iva=$(jo name=core values=$(jo -a ${core[@]})) \
measurements=$(jo -a ${energy_parallel[@]}) > energy-parallel.json
jo -p iva=$(jo name=core values=$(jo -a ${core[@]})) \
measurements=$(jo -a ${speedup[@]}) > speedup.json
jo -p iva=$(jo name=core values=$(jo -a ${core[@]})) \
measurements=$(jo -a ${freeup[@]}) > freeup.json
jo -p iva=$(jo name=core values=$(jo -a ${core[@]})) \
measurements=$(jo -a ${powerup[@]}) > powerup.json
jo -p iva=$(jo name=core values=$(jo -a ${core[@]})) \
measurements=$(jo -a ${energyup[@]}) > energyup.json

# curve fitting
progress_bandwidth=10
fit_count=12

fit.py --in-file time-serial.json --out-file time-serial-fitted.json

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=$fit_count; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Predictive Model Generation\",\
  \"nextStep\":\"None\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file

fit.py --in-file time-parallel.json --out-file time-parallel-fitted.json

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=$fit_count; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Predictive Model Generation\",\
  \"nextStep\":\"None\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file

fit.py --in-file space-serial.json --out-file space-serial-fitted.json

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=$fit_count; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Predictive Model Generation\",\
  \"nextStep\":\"None\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file

fit.py --in-file space-parallel.json --out-file space-parallel-fitted.json

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=$fit_count; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Predictive Model Generation\",\
  \"nextStep\":\"None\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file

fit.py --in-file power-serial.json --out-file power-serial-fitted.json

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=$fit_count; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Predictive Model Generation\",\
  \"nextStep\":\"None\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file

fit.py --in-file power-parallel.json --out-file power-parallel-fitted.json --error-threshold 2

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=$fit_count; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Predictive Model Generation\",\
  \"nextStep\":\"None\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file

fit.py --in-file energy-serial.json --out-file energy-serial-fitted.json

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=$fit_count; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Predictive Model Generation\",\
  \"nextStep\":\"None\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file

fit.py --in-file energy-parallel.json --out-file energy-parallel-fitted.json --error-threshold 2

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=$fit_count; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Predictive Model Generation\",\
  \"nextStep\":\"None\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file

fit.py --in-file speedup.json --out-file speedup-fitted.json --error-threshold 2

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=$fit_count; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Predictive Model Generation\",\
  \"nextStep\":\"None\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file

fit.py --in-file freeup.json --out-file freeup-fitted.json

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=$fit_count; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Predictive Model Generation\",\
  \"nextStep\":\"None\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file

fit.py --in-file powerup.json --out-file powerup-fitted.json

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=$fit_count; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Predictive Model Generation\",\
  \"nextStep\":\"None\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file

fit.py --in-file energyup.json --out-file energyup-fitted.json --error-threshold 2

  progress=`echo "scale=1; p=$progress; bw=$progress_bandwidth; l=$fit_count; p + (bw/l)" | bc -l`

  echo "{\"id\":\"$id\",\"repo\":\"$repo\",\"repoName\":\"$repo_name\",\"startTime\":\"$start_time\",\
  \"endTime\":\"\",\"status\":\"In progress\",\"progress\":{\"currentStep\":\"Predictive Model Generation\",\
  \"nextStep\":\"None\",\"percent\":$progress},\
  \"result\":{\"errorCode\":0,\"message\":\"\",\"repo\":\"\"}}" > $analysis_file

# time serial
jo -p \
iva=$(jo data=$(jo -a ${iva[@]}) name=$iva_name unit=size) \
measurements=$(jo data=$(jo -a ${time_serial[@]}) name=time unit=seconds) \
predictions=$(jo data="`jq '.fitted_measurements' time-serial-fitted.json`" name=time unit=seconds) \
polynomial="`jq '.polynomial' time-serial-fitted.json`" \
maxError="`jq '.max_error' time-serial-fitted.json`" \
rSquared="`jq '.r_squared' time-serial-fitted.json`" \
> $time_serial_analytics_file

# time parallel
jo -p \
iva=$(jo data=$(jo -a ${core[@]}) name=core unit=count) \
measurements=$(jo data=$(jo -a ${time_parallel[@]}) name=time unit=seconds) \
predictions=$(jo data="`jq '.fitted_measurements' time-parallel-fitted.json`" name=time unit=seconds) \
polynomial="`jq '.polynomial' time-parallel-fitted.json`" \
maxError="`jq '.max_error' time-parallel-fitted.json`" \
rSquared="`jq '.r_squared' time-parallel-fitted.json`" \
> $time_parallel_analytics_file

# memory serial
jo -p \
iva=$(jo data=$(jo -a ${iva[@]}) name=$iva_name unit=size) \
measurements=$(jo data=$(jo -a ${space_serial[@]}) name=memory unit=MB) \
predictions=$(jo data="`jq '.fitted_measurements' space-serial-fitted.json`" name=memory unit=MB) \
polynomial="`jq '.polynomial' space-serial-fitted.json`" \
maxError="`jq '.max_error' space-serial-fitted.json`" \
rSquared="`jq '.r_squared' space-serial-fitted.json`" \
> $space_serial_analytics_file

# memory parallel
jo -p \
iva=$(jo data=$(jo -a ${core[@]}) name=core unit=count) \
measurements=$(jo data=$(jo -a ${space_parallel[@]}) name=memory unit=MB) \
predictions=$(jo data="`jq '.fitted_measurements' space-parallel-fitted.json`" name=memory unit=MB) \
polynomial="`jq '.polynomial' space-parallel-fitted.json`" \
maxError="`jq '.max_error' space-parallel-fitted.json`" \
rSquared="`jq '.r_squared' space-parallel-fitted.json`" \
> $space_parallel_analytics_file

# power serial
jo -p \
iva=$(jo data=$(jo -a ${iva[@]}) name=$iva_name unit=size) \
measurements=$(jo data=$(jo -a ${power_serial[@]}) name=power unit="watts") \
predictions=$(jo data="`jq '.fitted_measurements' power-serial-fitted.json`" name=power unit="watts") \
polynomial="`jq '.polynomial' power-serial-fitted.json`" \
maxError="`jq '.max_error' power-serial-fitted.json`" \
rSquared="`jq '.r_squared' power-serial-fitted.json`" \
> $power_serial_analytics_file

# power parallel
jo -p \
iva=$(jo data=$(jo -a ${core[@]}) name=core unit=count) \
measurements=$(jo data=$(jo -a ${power_parallel[@]}) name=power unit="watts") \
predictions=$(jo data="`jq '.fitted_measurements' power-parallel-fitted.json`" name=power unit="watts") \
polynomial="`jq '.polynomial' power-parallel-fitted.json`" \
maxError="`jq '.max_error' power-parallel-fitted.json`" \
rSquared="`jq '.r_squared' power-parallel-fitted.json`" \
> $power_parallel_analytics_file

# energy serial
jo -p \
iva=$(jo data=$(jo -a ${iva[@]}) name=$iva_name unit=size) \
measurements=$(jo data=$(jo -a ${energy_serial[@]}) name=energy unit="watt-seconds") \
predictions=$(jo data="`jq '.fitted_measurements' energy-serial-fitted.json`" name=energy unit="watt-seconds") \
polynomial="`jq '.polynomial' energy-serial-fitted.json`" \
maxError="`jq '.max_error' energy-serial-fitted.json`" \
rSquared="`jq '.r_squared' energy-serial-fitted.json`" \
> $energy_serial_analytics_file

# energy parallel
jo -p \
iva=$(jo data=$(jo -a ${core[@]}) name=core unit=count) \
measurements=$(jo data=$(jo -a ${energy_parallel[@]}) name=energy unit="watt-seconds") \
predictions=$(jo data="`jq '.fitted_measurements' energy-parallel-fitted.json`" name=energy unit="watt-seconds") \
polynomial="`jq '.polynomial' energy-parallel-fitted.json`" \
maxError="`jq '.max_error' energy-parallel-fitted.json`" \
rSquared="`jq '.r_squared' energy-parallel-fitted.json`" \
> $energy_parallel_analytics_file

# speedup
jo -p \
iva=$(jo data=$(jo -a ${core[@]}) name=core unit=count) \
measurements=$(jo data=$(jo -a ${speedup[@]}) name='T1/Tcore' unit='') \
predictions=$(jo data="`jq '.fitted_measurements' speedup-fitted.json`" name='T1/Tcore' unit='') \
polynomial="`jq '.polynomial' speedup-fitted.json`" \
maxError="`jq '.max_error' speedup-fitted.json`" \
rSquared="`jq '.r_squared' speedup-fitted.json`" \
> $speedup_analytics_file

# freeup
jo -p \
iva=$(jo data=$(jo -a ${core[@]}) name=core unit=count) \
measurements=$(jo data=$(jo -a ${freeup[@]}) name='S1/Score' unit='') \
predictions=$(jo data="`jq '.fitted_measurements' freeup-fitted.json`" name='S1/Score' unit='') \
polynomial="`jq '.polynomial' freeup-fitted.json`" \
maxError="`jq '.max_error' freeup-fitted.json`" \
r_squared="`jq '.r_squared' freeup-fitted.json`" \
> $freeup_analytics_file

# powerup
jo -p \
iva=$(jo data=$(jo -a ${core[@]}) name=core unit=count) \
measurements=$(jo data=$(jo -a ${powerup[@]}) name='PowerEfficiency(P1/Pcore)' unit='') \
predictions=$(jo data="`jq '.fitted_measurements' powerup-fitted.json`" name='PowerEfficiency(P1/Pcore)' unit='') \
polynomial="`jq '.polynomial' powerup-fitted.json`" \
maxError="`jq '.max_error' powerup-fitted.json`" \
rSquared="`jq '.r_squared' powerup-fitted.json`" \
> $powerup_analytics_file

# energyup
jo -p \
iva=$(jo data=$(jo -a ${core[@]}) name=core unit=count) \
measurements=$(jo data=$(jo -a ${energyup[@]}) name='EnergyEfficiency(E1/Ecore)' unit='') \
predictions=$(jo data="`jq '.fitted_measurements' energyup-fitted.json`" name='EnergyEfficiency(E1/Ecore)' unit='') \
polynomial="`jq '.polynomial' energyup-fitted.json`" \
maxError="`jq '.max_error' energyup-fitted.json`" \
rSquared="`jq '.r_squared' energyup-fitted.json`" \
> $energyup_analytics_file

