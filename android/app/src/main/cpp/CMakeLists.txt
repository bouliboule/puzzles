cmake_minimum_required(VERSION 3.22.1)
project(puzzles C)

# Repo root is five levels up from android/app/src/main/cpp.
get_filename_component(ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../../.. ABSOLUTE)
set(P ${ROOT}/vendor/puzzles)

set(CORE combi divvy draw-poly drawing dsf findloop grid latin laydomino
  loopgen malloc matching midend misc penrose penrose-legacy printing ps
  random sort tdq tree234 version hat spectre)
set(GAMES loopy bridges keen pattern pearl slant)

set(SRC ${CMAKE_CURRENT_SOURCE_DIR}/jni.c ${ROOT}/src/native/pz.c)
foreach(f IN LISTS CORE GAMES)
  list(APPEND SRC ${P}/${f}.c)
endforeach()

add_library(puzzles SHARED ${SRC})
target_include_directories(puzzles PRIVATE ${ROOT}/src/native ${P})
target_compile_definitions(puzzles PRIVATE COMBINED)
target_compile_options(puzzles PRIVATE -O2 -w)
target_link_libraries(puzzles android log m)
