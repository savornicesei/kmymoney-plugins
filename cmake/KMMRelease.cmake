# Included only for isolated, single-plugin release builds.
list(LENGTH KMM_PLUGIN_SELECTION _release_count)
if(NOT _release_count EQUAL 1 OR KMM_PLUGIN_SELECTION STREQUAL "all")
    message(FATAL_ERROR "Release packaging requires exactly one selected plugin")
endif()
set(_release_plugin "${KMM_PLUGIN_SELECTION}")
file(GLOB _release_metadata "${CMAKE_SOURCE_DIR}/plugins/${_release_plugin}/*.json.in")
list(LENGTH _release_metadata _metadata_count)
if(NOT _metadata_count EQUAL 1)
    message(FATAL_ERROR "Release requires one plugin metadata JSON template in plugins/${_release_plugin}")
endif()
file(READ "${_release_metadata}" _metadata)
string(JSON _release_name GET "${_metadata}" KPlugin Name)
string(JSON _release_license GET "${_metadata}" KPlugin License)
string(JSON _release_id GET "${_metadata}" KPlugin Id)
if(NOT EXISTS "${CMAKE_SOURCE_DIR}/LICENSES/${_release_license}.txt")
    message(FATAL_ERROR "Missing license text for ${_release_license}")
endif()

set(CPACK_PACKAGE_NAME "kmymoney-plugin-${_release_plugin}")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_VENDOR "KMyMoney plugin contributors")
set(CPACK_PACKAGE_CONTACT "KMyMoney plugin contributors")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "${_release_name} plugin for KMyMoney")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_SOURCE_DIR}/LICENSES/${_release_license}.txt")
set(CPACK_PACKAGE_DIRECTORY "${CMAKE_BINARY_DIR}/packages")
set(CPACK_INCLUDE_TOPLEVEL_DIRECTORY OFF)
set(CPACK_PACKAGE_RELOCATABLE FALSE)
set(CPACK_SET_DESTDIR OFF)
set(CPACK_PACKAGING_INSTALL_PREFIX "/")
set(CPACK_ARCHIVE_COMPONENT_INSTALL OFF)
set(CPACK_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION ON)
foreach(_install_dir KDE_INSTALL_PLUGINDIR KDE_INSTALL_LOCALEDIR)
    if(IS_ABSOLUTE "${${_install_dir}}")
        message(FATAL_ERROR "Release requires relative install directories: ${_install_dir}=${${_install_dir}}")
    endif()
endforeach()
string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _release_arch)
if(_release_arch MATCHES "^(amd64|x64)$")
    set(_release_arch "x86_64")
elseif(_release_arch STREQUAL "aarch64")
    set(_release_arch "arm64")
endif()
if(WIN32)
    set(CPACK_GENERATOR ZIP)
    set(_release_platform "windows")
elseif(APPLE)
    set(CPACK_GENERATOR TGZ)
    set(_release_platform "macos")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(CPACK_GENERATOR TGZ)
    set(_release_platform "linux")
else()
    message(FATAL_ERROR "Unsupported release platform: ${CMAKE_SYSTEM_NAME}")
endif()
set(CPACK_PACKAGE_FILE_NAME "${_release_plugin}-${PROJECT_VERSION}-${_release_platform}-${_release_arch}")

set(_release_doc "share/doc/${CPACK_PACKAGE_NAME}")
file(WRITE "${CMAKE_BINARY_DIR}/INSTALL.txt"
    "${_release_name} ${PROJECT_VERSION}\n"
    "Requires the matching KMyMoney host ABI recorded in release-manifest.json.\n"
    "Archives contain plugin files and translations relative to an installation prefix.\n"
    "Use a separate prefix and add its lib/plugins directory to QT_PLUGIN_PATH and\n"
    "its share directory (bin/data on Windows) to XDG_DATA_DIRS when launching KMyMoney.\n"
    "Requires Craft KMyMoney target ${KMM_RELEASE_HOST_TARGET}, built as ${KMM_RELEASE_HOST_VERSION}.\n"
    "On Linux/macOS, launch in the matching Craft library environment.\n"
    "Enable the plugin in KMyMoney's plugin settings after installation.\n"
    "Close KMyMoney before replacing plugin files. No host or Qt libraries are bundled.\n")
install(FILES "${CMAKE_BINARY_DIR}/INSTALL.txt" "${CPACK_RESOURCE_FILE_LICENSE}" DESTINATION "${_release_doc}")
install(FILES "${CMAKE_BINARY_DIR}/release-manifest.json" DESTINATION "${_release_doc}" OPTIONAL)
file(SHA256 "${KMYMONEY_INCLUDE_DIR}/mymoneyfile.h" _host_header_hash)
set(_host_version "${KMM_RELEASE_HOST_VERSION}")
if(EXISTS "${KMYMONEY_BUILD_DIR}/config-kmymoney-version.h")
    file(STRINGS "${KMYMONEY_BUILD_DIR}/config-kmymoney-version.h" _host_version_line REGEX "^#define VERSION ")
    string(REGEX REPLACE "^#define VERSION \"([^\"]*)\".*" "\\1" _host_version "${_host_version_line}")
endif()
if(NOT KMM_RELEASE_HOST_TARGET OR NOT KMM_RELEASE_HOST_VERSION OR NOT _host_version STREQUAL KMM_RELEASE_HOST_VERSION)
    message(FATAL_ERROR "Release requires the verified Craft host target and matching SDK version")
endif()
file(WRITE "${CMAKE_BINARY_DIR}/release-build-info.txt"
    "PluginId=${_release_id}\nVersion=${PROJECT_VERSION}\nPlatform=${_release_platform}\n"
    "Architecture=${_release_arch}\nQtVersion=${Qt6_VERSION}\n"
    "Compiler=${CMAKE_CXX_COMPILER_ID}\nCompilerVersion=${CMAKE_CXX_COMPILER_VERSION}\n"
    "HostTarget=${KMM_RELEASE_HOST_TARGET}\nHostVersion=${_host_version}\nHostHeaderSHA256=${_host_header_hash}\n"
    "PackageName=${CPACK_PACKAGE_FILE_NAME}\nGenerator=${CPACK_GENERATOR}\n")
include(CPack)
