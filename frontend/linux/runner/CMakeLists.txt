cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES C CXX)

find_program(GLIB_COMPILE_RESOURCES glib-compile-resources)
if(NOT GLIB_COMPILE_RESOURCES)
  message(FATAL_ERROR "glib-compile-resources is required for the Domabas app icon")
endif()

set(DOMABAS_ICON_RESOURCE "${CMAKE_CURRENT_BINARY_DIR}/domabas_icons.c")
add_custom_command(
  OUTPUT "${DOMABAS_ICON_RESOURCE}"
  COMMAND "${GLIB_COMPILE_RESOURCES}"
    --generate-source
    --target=${DOMABAS_ICON_RESOURCE}
    --sourcedir=${CMAKE_CURRENT_SOURCE_DIR}
    "${CMAKE_CURRENT_SOURCE_DIR}/resources.gresource.xml"
  DEPENDS "resources.gresource.xml" "resources/app_icon.png"
  VERBATIM
)

add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${DOMABAS_ICON_RESOURCE}"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

apply_standard_settings(${BINARY_NAME})

add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
