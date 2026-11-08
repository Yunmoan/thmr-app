"""Fix legacy plugin build scripts without pinning their package versions."""

import json
import re
from pathlib import Path
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname


def fix_webview(source):
    if "TARGET ${PROJECT_NAME}_DEPENDENCIES_DOWNLOAD PRE_BUILD" in source:
        # DEPENDS is only valid with the OUTPUT form of add_custom_command.
        return source.replace("\n  DEPENDS ${NUGET}", "")
    return source


def fix_media_kit(source):
    # The upstream downloader accepts HTTP error bodies, then reports only a
    # checksum mismatch. Retry failed/partial downloads without weakening the
    # plugin's pinned checksum or ever keeping a corrupt archive in the cache.
    downloader = r'''function(download_and_verify url md5 locationForArchive)
  if(EXISTS "${locationForArchive}")
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)
    if(md5 STREQUAL ARCHIVE_MD5)
      return()
    endif()
    file(REMOVE "${locationForArchive}")
  endif()

  foreach(attempt RANGE 1 3)
    message(STATUS "Downloading ${url} (attempt ${attempt}/3)")
    file(DOWNLOAD "${url}" "${locationForArchive}"
      STATUS download_status TIMEOUT 180 INACTIVITY_TIMEOUT 30 TLS_VERIFY ON)
    list(GET download_status 0 download_code)
    list(GET download_status 1 download_message)
    if(download_code EQUAL 0)
      file(MD5 "${locationForArchive}" ARCHIVE_MD5)
      if(md5 STREQUAL ARCHIVE_MD5)
        message(STATUS "${locationForArchive} Verification successful.")
        return()
      endif()
      set(download_message "Integrity check failed")
    endif()
    file(REMOVE "${locationForArchive}")
    message(STATUS "Download failed: ${download_message}")
    if(attempt LESS 3)
      math(EXPR retry_delay "${attempt} * 5")
      execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep "${retry_delay}")
    endif()
  endforeach()
  message(FATAL_ERROR "Could not download and verify ${url} after 3 attempts: ${download_message}")
endfunction()'''
    source = re.sub(
        r'function\(download_and_verify url md5 locationForArchive\).*?endfunction\(\)',
        lambda _: downloader, source, count=1, flags=re.DOTALL,
    )
    return source.replace(
        'TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT"\n    COMMAND',
        'TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT" POST_BUILD\n    COMMAND',
    )


def fix_symlinks(source):
    return source.replace(
        "$item = Get-Item $realPath",
        "$item = Get-Item -LiteralPath $realPath -Force",
    )


def main():
    config = Path(__file__).resolve().parent.parent / ".dart_tool/package_config.json"
    packages = json.loads(config.read_text(encoding="utf-8"))["packages"]
    fixes = {
        "flutter_inappwebview_windows": ("windows/CMakeLists.txt", fix_webview),
        "media_kit_libs_windows_audio": ("windows/CMakeLists.txt", fix_media_kit),
        "smtc_windows": ("cargokit/cmake/resolve_symlinks.ps1", fix_symlinks),
    }
    for package in packages:
        if package["name"] not in fixes:
            continue
        uri = urlparse(urljoin(config.as_uri(), package["rootUri"]))
        if uri.scheme != "file" or uri.netloc:
            raise ValueError("Expected a local plugin directory")
        relative, transform = fixes[package["name"]]
        target = Path(url2pathname(uri.path)) / relative
        source = target.read_text(encoding="utf-8")
        patched = transform(source)
        if patched != source:
            target.write_text(patched, encoding="utf-8")
            print(f"Updated native build compatibility: {package['name']}")


if __name__ == "__main__":
    main()
