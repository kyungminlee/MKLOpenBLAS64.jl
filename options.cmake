set(MKL_INCLUDE_PATH "/usr/include/mkl")
set(MKL_LIBRARIES
    "-Wl,--start-group"
/usr/lib/x86_64-linux-gnu/libmkl_core.a
/usr/lib/x86_64-linux-gnu/libmkl_gf_ilp64.a
/usr/lib/x86_64-linux-gnu/libmkl_gnu_thread.a
/usr/lib/x86_64-linux-gnu/liblapacke64.a
    "-Wl,--end-group"
    -lgomp -lpthread -lm -ldl
)
