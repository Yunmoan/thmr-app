# Linux 项目的顶层 CMake 配置。
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# 应用实际写入磁盘的可执行文件名称。
set(BINARY_NAME "thmr_app")
# GTK 应用标识，也用于匹配桌面入口。命名规则见 https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "cn.yunmoan.thmr.thmr_app")

# 采用该 CMake 版本对应的策略，避免较新版本报告旧策略警告。
cmake_policy(SET CMP0063 NEW)

# 从可执行文件旁的 lib/ 加载随包分发的库。
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# 交叉编译用的根文件系统。
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# 定义受支持的构建配置。
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# 多数应用和插件目标共用的编译选项。
#
# 插件也会使用此函数。仅影响个别目标的编译选项应直接加在目标上。
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter 库及工具构建规则。
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# 系统依赖。
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# 应用本体的构建规则见 runner/CMakeLists.txt。
add_subdirectory("runner")

# Flutter 工具生成的构建步骤，负责生成应用资源和库。
add_dependencies(${BINARY_NAME} flutter_assemble)

# 构建目录中的裸可执行文件缺少正确的资源相对路径，因此将它放在中间目录。
# 运行时应从安装步骤生成的 bundle 启动。
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# 引入自动生成的插件构建规则，将插件链接或复制到应用。
include(flutter/generated_plugins.cmake)

# 新版系统头文件和 Clang 可能标记这些依赖使用的旧接口。保留弃用警告，并继续将其余警告视为错误。
if(TARGET tray_manager_plugin)
  target_compile_options(tray_manager_plugin PRIVATE
    -Wno-error=deprecated-declarations)
endif()
if(TARGET flutter_secure_storage_linux_plugin AND
   CMAKE_CXX_COMPILER_ID MATCHES "Clang" AND
   CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL 17)
  target_compile_options(flutter_secure_storage_linux_plugin PRIVATE
    -Wno-error=deprecated-literal-operator)
endif()


# === 安装 ===
# 默认安装到构建目录下，可整体移动生成的 bundle。
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# 每次安装都先清理旧 bundle。
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

# 频谱解码器随包分发，无需系统安装 ffmpeg 命令。
add_library(thmr_mp3 SHARED "${CMAKE_CURRENT_SOURCE_DIR}/../native/mp3_decoder.cc")
target_compile_features(thmr_mp3 PRIVATE cxx_std_14)
target_include_directories(thmr_mp3 SYSTEM PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../native/vendor/minimp3")
set_target_properties(thmr_mp3 PROPERTIES CXX_VISIBILITY_PRESET hidden)
install(TARGETS thmr_mp3 LIBRARY DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../native/vendor/minimp3/LICENSE"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/licenses/minimp3" COMPONENT Runtime)

add_executable(thmr_runtime_check
  "${CMAKE_CURRENT_SOURCE_DIR}/../native/check_linux_runtime.cc")
target_link_libraries(thmr_runtime_check PRIVATE ${CMAKE_DL_LIBS})
install(TARGETS thmr_runtime_check RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
install(PROGRAMS "${CMAKE_CURRENT_SOURCE_DIR}/../tool/linux/launch.sh"
  DESTINATION "${CMAKE_INSTALL_PREFIX}" RENAME thmr COMPONENT Runtime)
install(PROGRAMS
  "${CMAKE_CURRENT_SOURCE_DIR}/../tool/linux/install-desktop.sh"
  "${CMAKE_CURRENT_SOURCE_DIR}/../tool/linux/uninstall-desktop.sh"
  DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../docs/user/linux.md"
  DESTINATION "${CMAKE_INSTALL_PREFIX}" RENAME README-Linux.md COMPONENT Runtime)

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# 复制各依赖包通过 build.dart 生成的原生资源。
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
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
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
