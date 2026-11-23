cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# 使用顶层 CMakeLists.txt 的 BINARY_NAME 定义应用目标，保证 flutter run 能定位可执行文件。
#
# 应用新增的原生源文件应列入此目标。
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "linux_tray.cc"
  "linux_media.cc"
  "mpris_service.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# 应用共用编译选项。
apply_standard_settings(${BINARY_NAME})

# 通过预处理宏传入应用 ID。
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# 链接系统库和应用专用依赖。
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
