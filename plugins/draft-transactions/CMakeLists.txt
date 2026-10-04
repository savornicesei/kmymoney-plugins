add_library(drafttransactions_core STATIC
    src/draftcodec.cpp
    src/draftservice.cpp
)
target_include_directories(drafttransactions_core PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(drafttransactions_core PUBLIC KMyMoney::Host KF6::I18n)
target_compile_definitions(drafttransactions_core PUBLIC TRANSLATION_DOMAIN="drafttransactions")
ki18n_install(po)

configure_file(drafttransactions.json.in drafttransactions.json @ONLY)
# Recompile the factory when embedded translations change, including with MSVC's
# dependency scanner, which may miss dependencies reached through generated MOC.
set_property(SOURCE src/drafttransactionsplugin.cpp APPEND PROPERTY
    OBJECT_DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/drafttransactions.json")
kcoreaddons_add_plugin(drafttransactions
    SOURCES src/drafttransactionsplugin.cpp src/draftsview.cpp drafttransactions.qrc
    INSTALL_NAMESPACE "kmymoney_plugins")
# Keep the filename-derived plugin ID aligned with metadata and XMLGUI resources
# on Unix as well as Windows, including with older KF6 CMake helpers.
set_target_properties(drafttransactions PROPERTIES PREFIX "")
target_include_directories(drafttransactions PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
target_link_libraries(drafttransactions PRIVATE drafttransactions_core KF6::CoreAddons)
if(MSVC)
    install(FILES "$<TARGET_PDB_FILE:drafttransactions>"
        DESTINATION "${KDE_INSTALL_PLUGINDIR}/kmymoney_plugins" OPTIONAL)
endif()

if(BUILD_TESTING)
    find_package(Qt6 REQUIRED COMPONENTS Test)
    add_executable(draftservicetest tests/draftservicetest.cpp src/draftsview.cpp)
    target_link_libraries(draftservicetest PRIVATE drafttransactions_core Qt6::Test KF6::CoreAddons)
    target_compile_definitions(draftservicetest PRIVATE DRAFT_PLUGIN_FILE="$<TARGET_FILE:drafttransactions>")
    add_dependencies(draftservicetest drafttransactions pofiles)
    add_test(NAME draft-transactions.service COMMAND draftservicetest)
    set_tests_properties(draft-transactions.service PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;LANGUAGE=en_US")

    add_executable(drafttranslationtest tests/drafttranslationtest.cpp src/draftsview.cpp)
    target_link_libraries(drafttranslationtest PRIVATE drafttransactions_core Qt6::Test KF6::CoreAddons)
    target_compile_definitions(drafttranslationtest PRIVATE
        DRAFT_PLUGIN_FILE="$<TARGET_FILE:drafttransactions>"
        DRAFT_LOCALE_DIR="${CMAKE_CURRENT_BINARY_DIR}/locale")
    add_dependencies(drafttranslationtest drafttransactions pofiles)
    # Gettext caches catalogs in-process on Windows; test each language at startup.
    file(STRINGS po/LINGUAS draft_locales)
    foreach(locale IN LISTS draft_locales)
        add_test(NAME draft-transactions.translation.${locale} COMMAND drafttranslationtest)
        set_tests_properties(draft-transactions.translation.${locale} PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;LANGUAGE=${locale};DRAFT_TEST_LOCALE=${locale}")
    endforeach()
    option(BUILD_HOST_STORAGE_TESTS "Test against the matching host XML and SQLite adapters" ON)
    if(BUILD_HOST_STORAGE_TESTS)
        include(tests/HostStorage.cmake)
    endif()
endif()
