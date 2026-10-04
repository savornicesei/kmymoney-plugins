# Compile the matching host's unmodified storage adapters into tests only.
# Nothing here is linked into the plugin or installed into the host.
set(_sdk "${KMYMONEY_SDK_SOURCE_DIR}/kmymoney")
find_package(Qt6 REQUIRED COMPONENTS Sql Xml)
find_library(_online_task_library NAMES onlinetask_interfaces HINTS "$ENV{CRAFT_ROOT}/lib" REQUIRED)
find_library(_payee_library NAMES kmm_payeeidentifier HINTS "$ENV{CRAFT_ROOT}/lib" REQUIRED)
set(_platform_source "${_sdk}/misc/platformtools_gnu.cpp")
if(WIN32)
    set(_platform_source "${_sdk}/misc/platformtools_nognu.cpp")
endif()
add_library(draft_host_storage STATIC
    "${_sdk}/plugins/xml/mymoneyxmlreader.cpp"
    "${_sdk}/plugins/xml/mymoneyxmlwriter.cpp"
    "${_sdk}/plugins/xml/mymoneystoragenames.cpp"
    "${_sdk}/mymoney/xmlhelper/xmlstoragehelper.cpp"
    "${_sdk}/plugins/sql/mymoneystoragesql.cpp"
    "${_sdk}/plugins/sql/mymoneydbdef.cpp"
    "${_sdk}/plugins/sql/mymoneydbdriver.cpp"
)
# The helper was removed from newer host revisions. Older storage adapters
# still reference it, so compile it when supplied by the matching SDK source.
if(EXISTS "${_platform_source}")
    target_sources(draft_host_storage PRIVATE "${_platform_source}")
endif()
target_include_directories(draft_host_storage PUBLIC
    "${_sdk}/plugins/xml" "${_sdk}/plugins/sql"
    PRIVATE "${_sdk}" "${_sdk}/plugins" "${_sdk}/mymoney/payeeidentifier"
    "${_sdk}/mymoney/xmlhelper" "${_sdk}/mymoney/storage" "${_sdk}/plugins/onlinetasks/interfaces"
    "${KMYMONEY_BUILD_DIR}" "${KMYMONEY_BUILD_DIR}/kmymoney/plugins/onlinetasks/interfaces")
target_link_libraries(draft_host_storage PUBLIC KMyMoney::Host Qt6::Sql Qt6::Xml
    KF6::I18n KF6::CoreAddons "${_online_task_library}" "${_payee_library}")
if(WIN32)
    target_link_libraries(draft_host_storage PRIVATE advapi32)
endif()
target_link_libraries(draftservicetest PRIVATE draft_host_storage)
target_compile_definitions(draftservicetest PRIVATE DRAFT_HOST_STORAGE_TESTS)
