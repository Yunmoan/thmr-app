cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# 使用顶层 CMakeLists.txt 的 BINARY_NAME 定义应用目标，保证 flutter run 能定位可执行文件。
#
# 应用新增的原生源文件应列入此目标。
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "single_instance.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# 应用共用编译选项。
apply_standard_settings(${BINARY_NAME})

# 通过预处理宏传入构建版本。
# 源码包含 UTF-8 编码的中文窗口标题，使 MSVC 按 UTF-8 解析。
 target_compile_options(${BINARY_NAME} PRIVATE "/utf-8")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# 禁用与 C++ 标准库函数重名的 Windows 宏。
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# 链接应用所需的库，并添加其头文件目录。
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" "ole32.lib" "uuid.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Flutter 工具生成的步骤，负责生成应用资源和库。
add_dependencies(${BINARY_NAME} flutter_assemble)

# THMR 原生频谱，通过 WASAPI loopback 采样并执行 FFT，由 dart:ffi 调用。
add_library(thmr_capture SHARED "${CMAKE_CURRENT_SOURCE_DIR}/../../native/thmr_capture.cpp")
target_compile_definitions(thmr_capture PRIVATE "_CRT_SECURE_NO_WARNINGS" "NOMINMAX" "WIN32_LEAN_AND_MEAN")
set_target_properties(thmr_capture PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner/$<CONFIG>"
)
target_link_libraries(thmr_capture PRIVATE ole32)
install(TARGETS thmr_capture
  RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
