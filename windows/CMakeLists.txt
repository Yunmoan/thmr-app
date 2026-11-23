# Windows 项目的顶层 CMake 配置。
cmake_minimum_required(VERSION 3.14)
project(thmr_app LANGUAGES CXX)

# 应用实际写入磁盘的可执行文件名称。
set(BINARY_NAME "thmr_app")

# 采用该 CMake 版本对应的策略，避免较新版本报告旧策略警告。
cmake_policy(VERSION 3.14...3.25)

# 定义受支持的构建配置。
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Profile 构建沿用 Release 的编译选项。
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# 所有目标使用 Unicode。
add_definitions(-DUNICODE -D_UNICODE)

# 多数应用和插件目标共用的编译选项。
#
# 插件也会使用此函数。仅影响个别目标的编译选项应直接加在目标上。
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter 库及工具构建规则。
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# 应用本体的构建规则见 runner/CMakeLists.txt。
add_subdirectory("runner")


# 引入自动生成的插件构建规则，将插件链接或复制到应用。
include(flutter/generated_plugins.cmake)

# C++/WinRT 使用标准协程。较新的 MSVC 不支持 WebView 插件的 C++17 配置选中的实验性协程头文件。
if(TARGET flutter_inappwebview_windows_plugin)
  target_compile_features(flutter_inappwebview_windows_plugin PRIVATE cxx_std_20)
  # 当前插件仍依赖 MSVC 旧式名称查找及扩展。
  target_compile_options(flutter_inappwebview_windows_plugin PRIVATE /permissive)
endif()


# === 安装 ===
# 将支持文件安装到可执行文件旁，使应用可直接从 Visual Studio 的构建目录运行。
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# 将安装步骤加入默认构建，以便直接运行应用。
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
# 无条件使用 FORCE。部分 MSVC 定制版 CMake（如 3.31.6-msvc）不会设置
# CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT，默认安装前缀可能落到 Program Files。
set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# 复制各依赖包通过 build.dart 生成的原生资源。
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# 每次安装重新复制整个资源目录，避免残留上次安装的文件。
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# 仅在非 Debug 构建中安装 AOT 库。
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
