rm $2

nvcc \
-I/usr/local/cuda/extras/CUPTI/samples/extensions/include/profilerhost_util \
-I/usr/local/cuda/extras/CUPTI/include \
-I/usr/local/cuda/extras/CUPTI/samples/extensions/include/c_util \
-L/usr/local/cuda/targets/x86_64-linux \
-L/usr/local/cuda/extras/CUPTI/lib64 \
-L/usr/local/cuda/extras/CUPTI/samples/extensions/src/profilerhost_util \
-lcuda  -lcupti -lnvperf_host -lnvperf_target -lprofilerHostUtil \
$1 \
-o $2