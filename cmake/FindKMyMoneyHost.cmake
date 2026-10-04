# The host does not export a complete SDK. Use installed public headers and the
# matching host build/source (Craft or native) for headers omitted by its install rules.
set(KMYMONEY_BUILD_DIR "$ENV{KMYMONEY_BUILD_DIR}" CACHE PATH "Matching KMyMoney build tree")
if(NOT KMYMONEY_BUILD_DIR AND EXISTS "$ENV{CRAFT_ROOT}/build/extragear/kmymoney/work/build/CMakeCache.txt")
    set(KMYMONEY_BUILD_DIR "$ENV{CRAFT_ROOT}/build/extragear/kmymoney/work/build")
endif()
set(KMYMONEY_SDK_SOURCE_DIR "$ENV{KMYMONEY_SDK_SOURCE_DIR}" CACHE PATH "Source used to build the installed host")
if(NOT KMYMONEY_SDK_SOURCE_DIR AND EXISTS "${KMYMONEY_BUILD_DIR}/CMakeCache.txt")
    file(STRINGS "${KMYMONEY_BUILD_DIR}/CMakeCache.txt" _host_source_line
         REGEX "^CMAKE_HOME_DIRECTORY:INTERNAL=")
    string(REPLACE "CMAKE_HOME_DIRECTORY:INTERNAL=" "" KMYMONEY_SDK_SOURCE_DIR "${_host_source_line}")
endif()
if(NOT KMYMONEY_SDK_SOURCE_DIR)
    set(KMYMONEY_SDK_SOURCE_DIR "$ENV{KMYMONEY_SOURCE_DIR}")
endif()

find_path(KMYMONEY_INCLUDE_DIR kmymoneyplugin.h
    HINTS "$ENV{CRAFT_ROOT}/include/kmymoney" PATH_SUFFIXES kmymoney)
find_path(KMYMONEY_MODEL_EXPORT_DIR kmm_models_export.h
    HINTS "${KMYMONEY_INCLUDE_DIR}" "${KMYMONEY_BUILD_DIR}/kmymoney/models")
find_path(KMYMONEY_SET_INCLUDE_DIR kmmset.h
    HINTS "${KMYMONEY_INCLUDE_DIR}" "${KMYMONEY_SDK_SOURCE_DIR}/kmymoney/mymoney")
find_path(KMYMONEY_SELECTION_INCLUDE_DIR selectedobjects.h
    HINTS "${KMYMONEY_INCLUDE_DIR}" "${KMYMONEY_SDK_SOURCE_DIR}/kmymoney/misc")
find_path(KMYMONEY_PAYEE_EXPORT_DIR payeeidentifier/kmm_payeeidentifier_export.h
    HINTS "${KMYMONEY_INCLUDE_DIR}" "${KMYMONEY_BUILD_DIR}/kmymoney/mymoney")
foreach(_library mymoney models plugin selections)
    find_library(KMYMONEY_${_library}_LIBRARY NAMES kmm_${_library} HINTS "$ENV{CRAFT_ROOT}/lib")
endforeach()
include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(KMyMoneyHost REQUIRED_VARS
    KMYMONEY_INCLUDE_DIR KMYMONEY_MODEL_EXPORT_DIR KMYMONEY_SET_INCLUDE_DIR
    KMYMONEY_SELECTION_INCLUDE_DIR KMYMONEY_PAYEE_EXPORT_DIR KMYMONEY_mymoney_LIBRARY KMYMONEY_models_LIBRARY
    KMYMONEY_plugin_LIBRARY KMYMONEY_selections_LIBRARY)

# Fail rather than silently combine a newer SDK with unrelated source headers.
foreach(_header mymoneyfile.h mymoneytransaction.h mymoneysplit.h mymoneyenums.h)
    if(EXISTS "${KMYMONEY_SDK_SOURCE_DIR}/kmymoney/mymoney/${_header}")
        file(SHA256 "${KMYMONEY_INCLUDE_DIR}/${_header}" _installed_hash)
        file(SHA256 "${KMYMONEY_SDK_SOURCE_DIR}/kmymoney/mymoney/${_header}" _source_hash)
        if(NOT _installed_hash STREQUAL _source_hash)
            message(FATAL_ERROR "${_header} differs between installed host and SDK source. Set KMYMONEY_SDK_SOURCE_DIR to the source used for this host.")
        endif()
    endif()
endforeach()

add_library(KMyMoney::Host INTERFACE IMPORTED)
set_target_properties(KMyMoney::Host PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${KMYMONEY_INCLUDE_DIR};${KMYMONEY_MODEL_EXPORT_DIR};${KMYMONEY_SET_INCLUDE_DIR};${KMYMONEY_SELECTION_INCLUDE_DIR};${KMYMONEY_PAYEE_EXPORT_DIR}"
    INTERFACE_LINK_LIBRARIES "${KMYMONEY_mymoney_LIBRARY};${KMYMONEY_models_LIBRARY};${KMYMONEY_plugin_LIBRARY};${KMYMONEY_selections_LIBRARY};Qt6::Widgets;KF6::XmlGui;Alkimia::alkimia")
message(STATUS "KMyMoney SDK source: ${KMYMONEY_SDK_SOURCE_DIR}")
message(STATUS "KMyMoney generated headers: ${KMYMONEY_MODEL_EXPORT_DIR}")
