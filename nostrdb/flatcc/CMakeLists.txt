include_directories (
    "${PROJECT_SOURCE_DIR}/include"
)

add_library(flatccrt
    builder.c
    emitter.c
    refmap.c
    verifier.c
    json_parser.c
    json_printer.c
)

if (FLATCC_INSTALL)
    install(TARGETS flatccrt DESTINATION ${lib_dir})
endif()
